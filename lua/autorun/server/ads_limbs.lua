-- Advanced Damage System – Limb HP Subsystem (server-side)
-- Loaded after ads_core.lua (alphabetical: "ads_core" < "ads_limbs")
if CLIENT then return end

local DBG = GetConVar("ads_debug")  -- reuse core debug convar
-- level: minimum ads_debug tier (1=compact+, 2=verbose/events only)
local function dprint(level, ...) if DBG and DBG:GetInt() >= level then print("[ADS Limbs]", ...) end end

-- Convars (all FCVAR_REPLICATED so cl_ads.lua sliders work)
local EN_LIMBS      = CreateConVar("ads_limbs_enabled",                    "1",   FCVAR_REPLICATED + FCVAR_ARCHIVE)
local HEAD_FRAC     = CreateConVar("ads_limb_head_frac",                   "0.5", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local ARMS_FRAC     = CreateConVar("ads_limb_arms_frac",                   "0.5", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local LEGS_FRAC     = CreateConVar("ads_limb_legs_frac",                   "0.5", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local DMG_XFER_HEAD = CreateConVar("ads_limb_damage_transfer_head",        "1.5", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local DMG_XFER_ARMS = CreateConVar("ads_limb_damage_transfer_arms",        "0.7", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local DMG_XFER_LEGS = CreateConVar("ads_limb_damage_transfer_legs",        "0.7", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local ACC_ARM       = CreateConVar("ads_limb_accuracy_max_penalty_per_arm","1.0", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local ACC_HEAD      = CreateConVar("ads_limb_accuracy_max_penalty_head",   "0.5", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local SPD_LEG       = CreateConVar("ads_limb_min_speed_mult_per_leg",      "0.5", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local STN50_DUR     = CreateConVar("ads_limb_head_stun_50_duration",       "1.0", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local STN25_DUR     = CreateConVar("ads_limb_head_stun_25_duration",       "2.5", FCVAR_REPLICATED + FCVAR_ARCHIVE)

-- Safe ratio: returns 0 if max is invalid instead of NaN/inf
local function safeRatio(cur, max)
    if not max or max <= 0 then return 0 end
    return math.Clamp(cur / max, 0, 1)
end

-- Try to get a bone world position; returns nil on failure
local function GetBonePos(npc, boneName)
    local ok, pos = pcall(function()
        local idx = npc:LookupBone(boneName)
        if idx then return npc:GetBonePosition(idx) end
    end)
    return (ok and pos) or nil
end

-- Best-effort weapon drop for NPCs. Returns the world entity left behind (or nil).
-- Marks the weapon for the scavenger subsystem and records it as the NPC's own
-- drop (retrieve-own mode). Guards keep limbs working without ads_scavenger.lua.
local function TryDropWeapon(npc, pos)
    local wep = npc:GetActiveWeapon()
    if not IsValid(wep) then return nil end
    local cls     = wep:GetClass()
    local dropPos = pos or (npc:GetPos() + Vector(0, 0, 32))
    local dropped = nil
    -- Attempt 1: engine-level drop (exposed for some human NPC types)
    local ok = pcall(function() npc:DropWeapon(wep, dropPos, Vector(0, 0, 50)) end)
    if ok then
        dropped = wep
        -- Deferred mark: the engine clears weapon ownership one tick after the drop
        -- (same pattern as EquipWeapon in ads_scavenger.lua)
        timer.Simple(0.05, function()
            if IsValid(dropped) and not IsValid(dropped:GetOwner())
               and ADS.MarkWeaponAsDroppedBy then
                ADS.MarkWeaponAsDroppedBy(dropped, npc)
            end
        end)
    else
        -- Attempt 2: spawn world copy + strip from NPC (the original is destroyed,
        -- so the copy is what gets tracked)
        local w = ents.Create(cls)
        if IsValid(w) then
            w:SetPos(dropPos)
            w:Spawn()
            pcall(function() w:PhysWake() end)
            dropped = w
            if ADS.MarkWeaponAsDroppedBy then ADS.MarkWeaponAsDroppedBy(w, npc) end
        end
        pcall(function() npc:StripWeapon(cls) end)
    end
    -- Record for the scavenger's retrieve-own mode
    if dropped and ADS.RecordOwnWeaponDrop then
        ADS.RecordOwnWeaponDrop(npc, dropped, cls)
    end
    return dropped
end

-- Apply head stun with dual-path: VJ NPCs use VJ_ACT_PLAYACTIVITY with IsGuard lock,
-- native NPCs check model activity support first to avoid T-pose on unsupported models.
-- isSevere=true → 25% threshold (big flinch), false → 50% threshold (small flinch).
-- Timer key is shared so 25% stun always cancels any active 50% stun.
local function ApplyHeadStun(npc, isSevere)
    if not IsValid(npc) then return end
    local stunKey = "ads_limb_stun_" .. npc:EntIndex()
    timer.Remove(stunKey)

    local dur = isSevere and STN25_DUR:GetFloat() or STN50_DUR:GetFloat()

    if npc.IsVJBaseSNPC then
        -- VJ path: use VJ_ACT_PLAYACTIVITY with lockAnim=true to block AI during stun
        local prevGuard = npc.IsGuard
        npc.IsGuard = true
        pcall(function() npc:StopMoving() end)

        pcall(function()
            npc:VJ_ACT_PLAYACTIVITY(
                isSevere and ACT_BIG_FLINCH or ACT_SMALL_FLINCH,
                true,   -- lockAnim: blocks AI during animation
                dur,    -- lockAnimTime: duration of lock
                false   -- faceEnemy: no rotation needed
            )
        end)

        timer.Create(stunKey, dur, 1, function()
            if not IsValid(npc) then return end
            npc.IsGuard = prevGuard
        end)

        dprint(2, "event", npc:GetClass(), "stun_vj " .. (isSevere and "25" or "50") .. " dur=" .. dur)
        return
    end

    -- Native path: verify model supports a flinch activity before scheduling to avoid T-pose
    local activities = isSevere
        and {ACT_BIG_FLINCH, ACT_FLINCH_HEAD, ACT_SMALL_FLINCH, ACT_FLINCH_PHYSICS}
        or  {ACT_SMALL_FLINCH, ACT_FLINCH_HEAD, ACT_BIG_FLINCH, ACT_FLINCH_PHYSICS}

    local hasFlinch = false
    for _, act in ipairs(activities) do
        if npc:SelectWeightedSequence(act) >= 0 then
            hasFlinch = true
            break
        end
    end

    if hasFlinch then
        local sched = isSevere and SCHED_BIG_FLINCH or SCHED_SMALL_FLINCH
        npc:SetSchedule(sched)
        local repeats = math.ceil(dur / 0.3)
        timer.Create(stunKey, 0.3, repeats, function()
            if not IsValid(npc) then return end
            npc:SetSchedule(sched)
        end)
        dprint(2, "event", npc:GetClass(), "stun_native " .. (isSevere and "25" or "50") .. " dur=" .. dur)
    else
        -- Model has no flinch animation: briefly clear enemy to disrupt targeting
        pcall(function()
            npc:SetEnemy(NULL)
            npc:ClearEnemyMemory()
        end)
        dprint(2, "event", npc:GetClass(), "stun_noflinch " .. (isSevere and "25" or "50"))
    end
end

-- Central debuff application. Called after every pool change.
-- reason: "spawn" | "damage" | "heal"
local function ApplyLimbDebuffs(npc, reason)
    if not IsValid(npc) then return end
    if not npc.ADS_HP_HeadMax then return end  -- not initialized

    local r_head = safeRatio(npc.ADS_HP_Head, npc.ADS_HP_HeadMax)
    local r_armL = safeRatio(npc.ADS_HP_ArmL, npc.ADS_HP_ArmLMax)
    local r_armR = safeRatio(npc.ADS_HP_ArmR, npc.ADS_HP_ArmRMax)
    local r_legL = safeRatio(npc.ADS_HP_LegL, npc.ADS_HP_LegLMax)
    local r_legR = safeRatio(npc.ADS_HP_LegR, npc.ADS_HP_LegRMax)

    -- Accuracy penalty: Lerp(ratio, maxPenalty, 0) → 0 HP gives max penalty, full HP gives 0
    local maxPenArm  = ACC_ARM:GetFloat()
    local maxPenHead = ACC_HEAD:GetFloat()
    local totalPen   = Lerp(r_armL, maxPenArm, 0) + Lerp(r_armR, maxPenArm, 0)
                     + Lerp(r_head, maxPenHead, 0)
    npc.Weapon_Accuracy = (npc.ADS_WeaponAccuracyBase or 1) * (1 + totalPen)

    -- Speed multiplier: Lerp(ratio, minSpd, 1.0) → 0 HP gives minSpd, full HP gives 1.0.
    -- Both legs multiplied (0.5 * 0.5 = 0.25 when both destroyed).
    -- Mechanism 1: m_flGroundSpeed (works on some Source NPCs).
    -- Mechanism 2: ADS_LegSpeedMult stored for the recurring Think hook (SetLocalVelocity).
    local minSpd   = SPD_LEG:GetFloat()
    local multLegL = Lerp(r_legL, minSpd, 1.0)
    local multLegR = Lerp(r_legR, minSpd, 1.0)
    local finalSpd = multLegL * multLegR
    pcall(function() npc:SetSaveValue("m_flGroundSpeed", npc.ADS_GroundSpeedBase * finalSpd) end)
    npc.ADS_LegSpeedMult = finalSpd

    dprint(2, "debuff", npc:GetClass(),
        "acc_penalty=" .. string.format("%.2f", totalPen),
        "speed_mult="  .. string.format("%.2f", finalSpd))

    -- One-shot: arm L drop at 0 HP
    local hasWeapon = IsValid(npc:GetActiveWeapon()) and npc:GetActiveWeapon():GetClass() ~= "weapon_nothingfornpc"
    if r_armL == 0 and not npc.ADS_ArmL_Dropped then
        npc.ADS_ArmL_Dropped = true
        local pos = GetBonePos(npc, "ValveBiped.Bip01_L_Hand")
                 or GetBonePos(npc, "ValveBiped.Bip01_L_Forearm")
                 or npc:GetPos()
        TryDropWeapon(npc, pos)
        dprint(2, "event", npc:GetClass(), "drop_weapon_L")
    end
    if r_armL > 0 or hasWeapon then npc.ADS_ArmL_Dropped = false end

    -- One-shot: arm R drop at 0 HP
    if r_armR == 0 and not npc.ADS_ArmR_Dropped then
        npc.ADS_ArmR_Dropped = true
        local pos = GetBonePos(npc, "ValveBiped.Bip01_R_Hand")
                 or GetBonePos(npc, "ValveBiped.Bip01_R_Forearm")
                 or npc:GetPos()
        TryDropWeapon(npc, pos)
        dprint(2, "event", npc:GetClass(), "drop_weapon_R")
    end
    if r_armR > 0 or hasWeapon then npc.ADS_ArmR_Dropped = false end

    -- One-shot: head stun 25% (checked FIRST so it cancels/overrides the 50% stun)
    if r_head < 0.25 and not npc.ADS_HeadStun25_Fired then
        npc.ADS_HeadStun25_Fired = true
        npc.ADS_HeadStun50_Fired = true  -- prevent separate 50% fire
        ApplyHeadStun(npc, true)
    end
    if r_head >= 0.25 then npc.ADS_HeadStun25_Fired = false end

    -- One-shot: head stun 50%
    if r_head < 0.5 and not npc.ADS_HeadStun50_Fired then
        npc.ADS_HeadStun50_Fired = true
        ApplyHeadStun(npc, false)
    end
    if r_head >= 0.5 then npc.ADS_HeadStun50_Fired = false end

    hook.Run("ADS_LimbsUpdated", npc, reason or "damage")
end

-- Expose publicly for HealLimbs and external callers
ADS.ApplyLimbDebuffs = ApplyLimbDebuffs

-- Initialize limb pools on spawn
local function InitLimbs(npc)
    if not EN_LIMBS:GetBool() then return end
    if not IsValid(npc) or not npc:IsNPC() then return end
    local hp = npc:Health()
    if hp <= 0 then return end
    npc.ADS_SpawnHP = hp  -- guardado para reconstruir fracs en toolgun M2 y ResizeLimbPools

    local override = ADS.GetOverride and ADS.GetOverride(npc:GetClass())
    local hf = (override and tonumber(override.head_hp_frac)) or HEAD_FRAC:GetFloat()
    local af = (override and tonumber(override.arms_hp_frac)) or ARMS_FRAC:GetFloat()
    local lf = (override and tonumber(override.legs_hp_frac)) or LEGS_FRAC:GetFloat()

    local headMax = hp * hf
    local armMax  = hp * af
    local legMax  = hp * lf

    npc.ADS_HP_Head = headMax; npc.ADS_HP_HeadMax = headMax
    npc.ADS_HP_ArmL = armMax;  npc.ADS_HP_ArmLMax = armMax
    npc.ADS_HP_ArmR = armMax;  npc.ADS_HP_ArmRMax = armMax
    npc.ADS_HP_LegL = legMax;  npc.ADS_HP_LegLMax = legMax
    npc.ADS_HP_LegR = legMax;  npc.ADS_HP_LegRMax = legMax

    -- Base accuracy; read once at spawn, never updated (prevents drift)
    npc.ADS_WeaponAccuracyBase = npc.Weapon_Accuracy or 1

    -- Base ground speed for leg slowdown mechanism 1 (m_flGroundSpeed).
    -- pcall: un addon externo (Lua Patcher) detourea GetSaveValue y su wrapper
    -- puede fallar en algunas entidades; atrapamos aquí para no gatillar su log.
    -- El SetSaveValue equivalente (ApplyLimbDebuffs) ya está protegido igual.
    local okGSV, baseSpd = pcall(function() return npc:GetSaveValue("m_flGroundSpeed") end)
    npc.ADS_GroundSpeedBase = (okGSV and baseSpd and baseSpd > 0) and baseSpd or 1
    npc.ADS_LegSpeedMult    = 1.0

    -- Track HP for universal heal polling
    npc.ADS_LastKnownHP = hp

    -- One-shot event flags
    npc.ADS_ArmL_Dropped     = false
    npc.ADS_ArmR_Dropped     = false
    npc.ADS_HeadStun50_Fired = false
    npc.ADS_HeadStun25_Fired = false

    dprint(2, "init", npc:GetClass(),
        "max_head=" .. string.format("%.1f", headMax),
        "max_arms=" .. string.format("%.1f", armMax),
        "max_legs=" .. string.format("%.1f", legMax))

    ApplyLimbDebuffs(npc, "spawn")
end

-- Called from ads_core.lua ScaleNPCDamage hook (Option B: deterministic ordering)
-- Redimensiona pools de limbs en un NPC vivo. Usado por el toolgun debug (M1 con Apply Limbs).
-- current = newMax (cura completa al redimensionar). Usa ADS_SpawnHP para fracs fieles;
-- fallback a Health() si no está disponible.
function ADS.ResizeLimbPools(npc, hf, af, lf)
    if not IsValid(npc) or not npc.ADS_HP_HeadMax then return end
    hf = math.max(hf or 0.5, 0.01)
    af = math.max(af or 0.5, 0.01)
    lf = math.max(lf or 0.5, 0.01)
    local hp = npc.ADS_SpawnHP or npc:Health()
    if hp <= 0 then return end
    npc.ADS_HP_HeadMax = hp * hf; npc.ADS_HP_Head = npc.ADS_HP_HeadMax
    npc.ADS_HP_ArmLMax = hp * af; npc.ADS_HP_ArmL = npc.ADS_HP_ArmLMax
    npc.ADS_HP_ArmRMax = hp * af; npc.ADS_HP_ArmR = npc.ADS_HP_ArmRMax
    npc.ADS_HP_LegLMax = hp * lf; npc.ADS_HP_LegL = npc.ADS_HP_LegLMax
    npc.ADS_HP_LegRMax = hp * lf; npc.ADS_HP_LegR = npc.ADS_HP_LegRMax
    dprint(2, "ResizeLimbPools", npc:GetClass(),
        "head=" .. string.format("%.1f", npc.ADS_HP_HeadMax),
        "arms=" .. string.format("%.1f", npc.ADS_HP_ArmLMax),
        "legs=" .. string.format("%.1f", npc.ADS_HP_LegLMax))
end

function ADS.ProcessLimbHit(npc, hitgroup, dmginfo)
    if not EN_LIMBS:GetBool() then return end
    if not IsValid(npc) or not npc:IsNPC() then return end
    if not npc.ADS_HP_HeadMax then return end

    local dmg = dmginfo:GetDamage()
    if dmg <= 0 then return end

    local override = ADS.GetOverride and ADS.GetOverride(npc:GetClass())

    local zone, before, after, poolMax, xfer
    if hitgroup == HITGROUP_HEAD then
        xfer = (override and tonumber(override.limb_damage_transfer_head)) or DMG_XFER_HEAD:GetFloat()
        zone = "head";  before = npc.ADS_HP_Head
        npc.ADS_HP_Head = math.max(0, npc.ADS_HP_Head - dmg * xfer)
        after = npc.ADS_HP_Head;  poolMax = npc.ADS_HP_HeadMax
    elseif hitgroup == HITGROUP_LEFTARM then
        xfer = (override and tonumber(override.limb_damage_transfer_arms)) or DMG_XFER_ARMS:GetFloat()
        zone = "arm_l"; before = npc.ADS_HP_ArmL
        npc.ADS_HP_ArmL = math.max(0, npc.ADS_HP_ArmL - dmg * xfer)
        after = npc.ADS_HP_ArmL;  poolMax = npc.ADS_HP_ArmLMax
    elseif hitgroup == HITGROUP_RIGHTARM then
        xfer = (override and tonumber(override.limb_damage_transfer_arms)) or DMG_XFER_ARMS:GetFloat()
        zone = "arm_r"; before = npc.ADS_HP_ArmR
        npc.ADS_HP_ArmR = math.max(0, npc.ADS_HP_ArmR - dmg * xfer)
        after = npc.ADS_HP_ArmR;  poolMax = npc.ADS_HP_ArmRMax
    elseif hitgroup == HITGROUP_LEFTLEG then
        xfer = (override and tonumber(override.limb_damage_transfer_legs)) or DMG_XFER_LEGS:GetFloat()
        zone = "leg_l"; before = npc.ADS_HP_LegL
        npc.ADS_HP_LegL = math.max(0, npc.ADS_HP_LegL - dmg * xfer)
        after = npc.ADS_HP_LegL;  poolMax = npc.ADS_HP_LegLMax
    elseif hitgroup == HITGROUP_RIGHTLEG then
        xfer = (override and tonumber(override.limb_damage_transfer_legs)) or DMG_XFER_LEGS:GetFloat()
        zone = "leg_r"; before = npc.ADS_HP_LegR
        npc.ADS_HP_LegR = math.max(0, npc.ADS_HP_LegR - dmg * xfer)
        after = npc.ADS_HP_LegR;  poolMax = npc.ADS_HP_LegRMax
    else
        return  -- no pool for chest/stomach/generic/etc
    end

    -- One-shot stash for the ads_core trace (consumed and cleared by ScaleNPCDamage)
    npc.ADS_LastLimbHit = {
        zone    = zone,
        dmgPool = dmg * xfer,
        before  = before,
        after   = after,
        poolMax = poolMax,
    }

    -- Sync ADS_LastKnownHP on next tick so heal polling doesn't misread damage as a heal
    timer.Simple(0, function()
        if IsValid(npc) then npc.ADS_LastKnownHP = npc:Health() end
    end)

    ApplyLimbDebuffs(npc, "damage")
end

-- Public healing API for external integration (medic mods, etc.)
-- target: nil (proportional), "head", "arms", "legs", "all_limbs"
function ADS.HealLimbs(npc, amount, target)
    if not IsValid(npc) or not npc.ADS_HP_HeadMax then return end
    local function healPool(cur, max, amt) return math.min(cur + amt, max) end

    if target == nil then
        local totalMax = npc.ADS_HP_HeadMax + npc.ADS_HP_ArmLMax + npc.ADS_HP_ArmRMax
                       + npc.ADS_HP_LegLMax + npc.ADS_HP_LegRMax
        if totalMax <= 0 then return end
        npc.ADS_HP_Head = healPool(npc.ADS_HP_Head, npc.ADS_HP_HeadMax, amount * npc.ADS_HP_HeadMax / totalMax)
        npc.ADS_HP_ArmL = healPool(npc.ADS_HP_ArmL, npc.ADS_HP_ArmLMax, amount * npc.ADS_HP_ArmLMax / totalMax)
        npc.ADS_HP_ArmR = healPool(npc.ADS_HP_ArmR, npc.ADS_HP_ArmRMax, amount * npc.ADS_HP_ArmRMax / totalMax)
        npc.ADS_HP_LegL = healPool(npc.ADS_HP_LegL, npc.ADS_HP_LegLMax, amount * npc.ADS_HP_LegLMax / totalMax)
        npc.ADS_HP_LegR = healPool(npc.ADS_HP_LegR, npc.ADS_HP_LegRMax, amount * npc.ADS_HP_LegRMax / totalMax)
    elseif target == "head" then
        npc.ADS_HP_Head = healPool(npc.ADS_HP_Head, npc.ADS_HP_HeadMax, amount)
    elseif target == "arms" then
        npc.ADS_HP_ArmL = healPool(npc.ADS_HP_ArmL, npc.ADS_HP_ArmLMax, amount / 2)
        npc.ADS_HP_ArmR = healPool(npc.ADS_HP_ArmR, npc.ADS_HP_ArmRMax, amount / 2)
    elseif target == "legs" then
        npc.ADS_HP_LegL = healPool(npc.ADS_HP_LegL, npc.ADS_HP_LegLMax, amount / 2)
        npc.ADS_HP_LegR = healPool(npc.ADS_HP_LegR, npc.ADS_HP_LegRMax, amount / 2)
    elseif target == "all_limbs" then
        local each = amount / 5
        npc.ADS_HP_Head = healPool(npc.ADS_HP_Head, npc.ADS_HP_HeadMax, each)
        npc.ADS_HP_ArmL = healPool(npc.ADS_HP_ArmL, npc.ADS_HP_ArmLMax, each)
        npc.ADS_HP_ArmR = healPool(npc.ADS_HP_ArmR, npc.ADS_HP_ArmRMax, each)
        npc.ADS_HP_LegL = healPool(npc.ADS_HP_LegL, npc.ADS_HP_LegLMax, each)
        npc.ADS_HP_LegR = healPool(npc.ADS_HP_LegR, npc.ADS_HP_LegRMax, each)
    end
    ApplyLimbDebuffs(npc, "heal")
end

-- Spawn hook: slight delay after core's 0.2s to ensure HP is fully set
hook.Add("OnEntityCreated", "ADS_Limbs_Spawn", function(e)
    timer.Simple(0.3, function()
        if not IsValid(e) or e:IsPlayer() or not e:IsNPC() then return end
        if not EN_LIMBS:GetBool() then return end
        InitLimbs(e)
    end)
end)

-- Cleanup: remove stun timer when entity is removed
hook.Add("EntityRemoved", "ADS_Limbs_Cleanup", function(e)
    timer.Remove("ads_limb_stun_" .. e:EntIndex())
end)

-- Fix 1: Recurring leg slowdown via SetLocalVelocity (20 Hz, only NPCs with reduced speed)
local legThinkNext = 0
hook.Add("Think", "ADS_Limbs_LegSpeed", function()
    if not EN_LIMBS:GetBool() then return end
    local now = CurTime()
    if now < legThinkNext then return end
    legThinkNext = now + 0.05

    for _, npc in ipairs(ents.GetAll()) do
        if IsValid(npc) and npc:IsNPC() and npc.ADS_LegSpeedMult and npc.ADS_LegSpeedMult < 1.0 then
            local v = npc:GetVelocity()
            if v:LengthSqr() > 1 then
                pcall(function() npc:SetLocalVelocity(v * npc.ADS_LegSpeedMult) end)
            end
        end
    end
end)

-- Fix 2: Universal heal polling — detects HP increases and propagates proportionally to pools.
-- Also initializes pools on-the-fly for NPCs that spawned before ads_limbs_enabled was turned on.
timer.Create("ADS_Limbs_HealPoll", 0.5, 0, function()
    if not EN_LIMBS:GetBool() then return end

    for _, npc in ipairs(ents.GetAll()) do
        if not IsValid(npc) or not npc:IsNPC() or npc:Health() <= 0 then continue end

        -- Auto-repair: NPC without pools initialized → init now
        if not npc.ADS_HP_HeadMax then
            InitLimbs(npc)
            continue
        end

        local currentHP = npc:Health()
        if not npc.ADS_LastKnownHP then
            npc.ADS_LastKnownHP = currentHP
            continue
        end

        local delta = currentHP - npc.ADS_LastKnownHP
        if delta > 0 then
            local maxHP = npc:GetMaxHealth()
            if maxHP > 0 then
                local healRatio = delta / maxHP
                npc.ADS_HP_Head = math.min(npc.ADS_HP_Head + npc.ADS_HP_HeadMax * healRatio, npc.ADS_HP_HeadMax)
                npc.ADS_HP_ArmL = math.min(npc.ADS_HP_ArmL + npc.ADS_HP_ArmLMax * healRatio, npc.ADS_HP_ArmLMax)
                npc.ADS_HP_ArmR = math.min(npc.ADS_HP_ArmR + npc.ADS_HP_ArmRMax * healRatio, npc.ADS_HP_ArmRMax)
                npc.ADS_HP_LegL = math.min(npc.ADS_HP_LegL + npc.ADS_HP_LegLMax * healRatio, npc.ADS_HP_LegLMax)
                npc.ADS_HP_LegR = math.min(npc.ADS_HP_LegR + npc.ADS_HP_LegRMax * healRatio, npc.ADS_HP_LegRMax)
                ApplyLimbDebuffs(npc, "heal")
                dprint(2, "heal_poll", npc:GetClass(), "delta=" .. delta, "ratio=" .. string.format("%.2f", healRatio))
            end
        end

        npc.ADS_LastKnownHP = currentHP
    end
end)

-- Fix 3: Reset arm drop flags when NPC equips a new weapon (covers Give, scavenger, any source)
hook.Add("WeaponEquip", "ADS_Limbs_ResetDropFlags", function(weapon, owner)
    if not IsValid(owner) or not owner:IsNPC() then return end
    if not owner.ADS_HP_HeadMax then return end  -- pools not initialized, nothing to reset
    owner.ADS_ArmL_Dropped = false
    owner.ADS_ArmR_Dropped = false
    dprint(2, "equip_reset", owner:GetClass(), weapon:GetClass())
end)

-- TODO: if VJ stuns don't block shooting sufficiently with VJ_ACT_PLAYACTIVITY,
-- add a recurring Think hook that for stun duration calls:
--   npc:StopMoving()
--   npc:ClearEnemyMemory()
-- Activate via npc.ADS_StunActive = true at stun start, false at end.
