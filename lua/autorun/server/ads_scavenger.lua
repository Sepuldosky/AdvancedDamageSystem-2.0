-- Advanced Damage System – Weapon Scavenger Subsystem (server-side)
-- Loaded after ads_core.lua and ads_limbs.lua (alphabetical order guaranteed)
if CLIENT then return end

-- ============================================================
-- ConVars
-- ============================================================
local SCAV_EN      = CreateConVar("ads_scavenger_enabled",              "1",   FCVAR_REPLICATED + FCVAR_ARCHIVE)
local DROP_LIFE    = CreateConVar("ads_scavenger_drop_lifetime",        "60",  FCVAR_REPLICATED + FCVAR_ARCHIVE)
local SEARCH_RAD   = CreateConVar("ads_scavenger_search_radius",        "800", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local PICKUP_DIST  = CreateConVar("ads_scavenger_pickup_distance",      "40",  FCVAR_REPLICATED + FCVAR_ARCHIVE)
local THINK_INT    = CreateConVar("ads_scavenger_think_interval",       "0.5", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local INT_COMBAT   = CreateConVar("ads_scavenger_interrupt_combat",     "0",   FCVAR_REPLICATED + FCVAR_ARCHIVE)
local WORLD_WEPS   = CreateConVar("ads_scavenger_allow_world_weapons",  "0",   FCVAR_REPLICATED + FCVAR_ARCHIVE)
local FORCE_ALL    = CreateConVar("ads_scavenger_force_all_npcs",       "0",   FCVAR_REPLICATED + FCVAR_ARCHIVE)
local MOVE_MODE    = CreateConVar("ads_scavenger_movement_mode",        "run", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local SCAV_DBG     = CreateConVar("ads_scavenger_debug",                "0",   FCVAR_REPLICATED + FCVAR_ARCHIVE)
local POST_DROP_CD = CreateConVar("ads_scavenger_post_drop_cooldown",   "8",   FCVAR_REPLICATED + FCVAR_ARCHIVE)
local DROP_OWN_T   = CreateConVar("ads_scavenger_drop_ownership_time",  "30",  FCVAR_REPLICATED + FCVAR_ARCHIVE)

local function dprint(...) if SCAV_DBG:GetBool() then print("[ADS Scavenger]", ...) end end

-- ============================================================
-- Public API table (ADS already exists; ads_core.lua runs first)
-- ============================================================
ADS = ADS or {}
ADS.ScavengerWeightOverrides = {}

-- Registered scavenger NPCs: [entity] = true.
-- Maintained proactively to avoid iterating all entities each Think tick.
local ScavengerNPCs = {}

-- Hold types that are problematic/unusable for NPCs
local BAD_HOLD_TYPES = {
    physgun = true,
    camera  = true,
    magic   = true,
    grenade = true,
}

local OVERRIDES_PATH = "ads/scavenger_weight_overrides.json"

-- ============================================================
-- Persistence: weight overrides
-- ============================================================
local function LoadOverrides()
    ADS.ScavengerWeightOverrides = {}
    if not file.Exists(OVERRIDES_PATH, "DATA") then return end
    local raw = file.Read(OVERRIDES_PATH, "DATA")
    local tbl = raw and util.JSONToTable(raw) or nil
    if type(tbl) ~= "table" then return end
    for k, v in pairs(tbl) do
        if type(k) == "string" and tonumber(v) then
            ADS.ScavengerWeightOverrides[k] = tonumber(v)
        end
    end
end

local function SaveOverrides()
    file.CreateDir("ads")
    file.Write(OVERRIDES_PATH, util.TableToJSON(ADS.ScavengerWeightOverrides, true))
end

-- ============================================================
-- Weapon marking
-- ============================================================

-- Public: mark a weapon as scavengeable, tracking which NPC dropped it.
-- permanent=true → never expires (math.huge timestamp, used for world weapons).
-- npc parameter is optional; when set, the ownership cooldown prevents that NPC
-- from picking the weapon back up for ads_scavenger_drop_ownership_time seconds.
function ADS.MarkWeaponAsDroppedBy(weapon, npc, permanent)
    if not IsValid(weapon) or not weapon:IsWeapon() then return end
    weapon.ADS_WasDropped = true
    weapon.ADS_DropTime   = permanent and math.huge or CurTime()
    if IsValid(npc) then
        weapon.ADS_DroppedBy     = npc:EntIndex()
        weapon.ADS_DroppedByTime = CurTime()
    end
    dprint("mark", weapon:GetClass(), "permanent=" .. tostring(permanent == true),
           IsValid(npc) and ("dropper=" .. npc:GetClass()) or "")
end

-- Backward-compatible wrapper: no dropper tracking, other NPCs can pick up immediately.
function ADS.MarkWeaponAsDropped(weapon, permanent)
    ADS.MarkWeaponAsDroppedBy(weapon, nil, permanent)
end

-- Returns true if the weapon is currently eligible for pickup.
local function IsScavengeable(weapon)
    if not IsValid(weapon) then return false end
    if not weapon:IsWeapon() then return false end
    if not weapon.ADS_WasDropped then return false end
    if IsValid(weapon:GetOwner()) then return false end
    if weapon:IsPlayerHolding() then return false end
    if weapon:GetClass() == "weapon_nothingfornpc" then return false end
    if BAD_HOLD_TYPES[weapon:GetHoldType()] then return false end
    -- Lifetime: math.huge means permanent (world weapons)
    if weapon.ADS_DropTime ~= math.huge then
        if (CurTime() - weapon.ADS_DropTime) > DROP_LIFE:GetFloat() then return false end
    end
    return true
end

-- ============================================================
-- Weapon weight
-- ============================================================

-- Slot fallback weights for weapons with no Primary.Damage defined
local SLOT_WEIGHTS = {[0]=1, [1]=5, [2]=8, [3]=12, [4]=15}

local function GetWeaponWeight(weapon)
    if not IsValid(weapon) then return 0 end
    -- Return cached value if available
    if weapon.ADS_AutoWeight then return weapon.ADS_AutoWeight end
    -- Manual override has priority
    local cls  = weapon:GetClass()
    local over = ADS.ScavengerWeightOverrides[cls]
    if over then
        weapon.ADS_AutoWeight = over
        return over
    end
    -- Auto-calculate from weapon properties
    local dmg   = tonumber(weapon.Primary and weapon.Primary.Damage)   or 0
    local delay = tonumber(weapon.Primary and weapon.Primary.Delay)    or 1
    local clip  = tonumber(weapon.Primary and weapon.Primary.ClipSize) or 1
    local w
    if dmg <= 0 then
        local slot = tonumber(weapon:GetSlot()) or -1
        w = SLOT_WEIGHTS[slot] or (slot >= 5 and 10 or 3)
    else
        w = dmg * (1 / math.max(delay, 0.05)) * math.sqrt(math.max(clip, 1)) / 10
    end
    w = math.Clamp(w, 0.1, 100)
    weapon.ADS_AutoWeight = w
    return w
end

-- Set a manual weight override for a weapon class.
function ADS.SetWeaponWeight(class, weight)
    if not class or not tonumber(weight) then return end
    weight = math.Clamp(tonumber(weight), 0, 1000)
    ADS.ScavengerWeightOverrides[class] = weight
    SaveOverrides()
    -- Invalidate cache on all currently-spawned weapons of this class
    for _, wep in ipairs(ents.FindByClass(class)) do
        if IsValid(wep) then wep.ADS_AutoWeight = nil end
    end
    print("[ADS Scavenger] Weight override set:", class, "=", weight)
end

function ADS.GetWeaponWeightOverride(class)
    return ADS.ScavengerWeightOverrides[class]
end

-- Expose weight calculation publicly for inspect and external integrations
ADS.GetWeaponWeight = GetWeaponWeight

-- Apply post-drop cooldown: NPC won't scavenge again for POST_DROP_CD seconds.
-- Called after any weapon equip attempt (success or failure) to prevent re-scan loops.
local function ApplyPostDropCooldown(npc)
    if not IsValid(npc) then return end
    npc.ADS_NextScavengerCheck = CurTime() + POST_DROP_CD:GetFloat()
end

-- ============================================================
-- NPC registration
-- ============================================================

local function RegisterNPC(npc)
    if not IsValid(npc) or not npc:IsNPC() then return end

    -- ADS blacklisted NPCs don't scavenge (combatants that intentionally have no armor)
    if ADS.UserBlacklist and ADS.UserBlacklist[npc:GetClass()] then
        npc.ADS_CanScavenge = false
        dprint("register", npc:GetClass(), "can_scavenge=false (ADS blacklist)")
        return
    end

    if FORCE_ALL:GetBool() then
        npc.ADS_CanScavenge = true
    else
        -- Auto-detect: NPCs that spawned with a real weapon are considered "armed by trade"
        local wep = npc:GetActiveWeapon()
        npc.ADS_CanScavenge = IsValid(wep) and wep:GetClass() ~= "weapon_nothingfornpc"
    end

    npc.ADS_NextScavengerCheck    = 0
    npc.ADS_ScavengerTargetWeapon = nil

    if npc.ADS_CanScavenge then
        ScavengerNPCs[npc] = true
    end

    dprint("register", npc:GetClass(), "can_scavenge=" .. tostring(npc.ADS_CanScavenge))
end

-- ============================================================
-- Pickup animation
-- ============================================================

local function TryPickupAnimation(npc)
    if not IsValid(npc) then return 0 end

    -- Approach 1: native Source pickup activities (Combine, Citizen, Metropolice support these)
    local activities = {ACT_PICKUP_GROUND, ACT_PICKUP_RACK}
    for _, act in ipairs(activities) do
        local seq = npc:SelectWeightedSequence(act)
        if seq and seq >= 0 then
            local ok = pcall(function()
                npc:ResetSequence(seq)
                npc:SetCycle(0)
                npc:SetPlaybackRate(1)
            end)
            if ok then
                local dur = npc:SequenceDuration(seq) or 0
                return dur > 0 and dur or 1.0
            end
        end
    end

    -- Approach 2: fallback to named sequences for legacy or custom models
    local sequences = {"pickup", "pickup_weapon", "physgun_pickup"}
    for _, seqName in ipairs(sequences) do
        local seq = npc:LookupSequence(seqName)
        if seq and seq >= 0 then
            local ok = pcall(function()
                npc:ResetSequence(seq)
                npc:SetCycle(0)
                npc:SetPlaybackRate(1)
            end)
            if ok then
                local dur = npc:SequenceDuration(seq) or 0
                return dur > 0 and dur or 1.0
            end
        end
    end

    return 0  -- no animation available, equip immediately
end

-- ============================================================
-- NPC movement toward weapon
-- ============================================================

local function MoveNPCToWeapon(npc, weapon)
    if not IsValid(npc) or not IsValid(weapon) then return end
    npc:SetLastPosition(weapon:GetPos())

    if npc.IsVJBaseSNPC then
        -- VJ Base: use SCHEDULE_GOTO_POSITION with native task name
        local taskName = MOVE_MODE:GetString() == "walk" and "TASK_WALK_PATH" or "TASK_RUN_PATH"
        local ok = pcall(function()
            npc:SCHEDULE_GOTO_POSITION(taskName, function(x)
                x.CanShootWhenMoving = true
                x.TurnData = {Type = VJ.FACE_ENEMY}
            end)
        end)
        if not ok then
            dprint("VJ schedule failed, fallback to native for", npc:GetClass())
            local sched = MOVE_MODE:GetString() == "walk" and SCHED_FORCED_GO or SCHED_FORCED_GO_RUN
            pcall(function() npc:SetSchedule(sched) end)
        end
    else
        local sched = MOVE_MODE:GetString() == "walk" and SCHED_FORCED_GO or SCHED_FORCED_GO_RUN
        pcall(function() npc:SetSchedule(sched) end)
    end
end

-- ============================================================
-- Equip weapon
-- ============================================================

local function EquipWeapon(npc, newWeapon)
    if not IsValid(npc) or not IsValid(newWeapon) then return end
    local newClass = newWeapon:GetClass()

    -- Drop current weapon before equipping new one so it stays in the world
    local current = npc:GetActiveWeapon()
    if IsValid(current) and current:GetClass() ~= "weapon_nothingfornpc" then
        local dropPos = npc:GetPos() + npc:GetForward() * 20 + Vector(0, 0, 30)
        local dropped = current
        pcall(function() npc:DropWeapon(current, dropPos, Vector(0, 0, 50)) end)
        -- Mark with ownership so this NPC won't immediately re-pick it up
        timer.Simple(0.05, function()
            if IsValid(dropped) then
                ADS.MarkWeaponAsDroppedBy(dropped, npc)
            end
        end)
    end

    -- Try pickup animation; returns duration in seconds (0 = no animation, equip immediately)
    local animDuration = TryPickupAnimation(npc)

    local function doEquip()
        if not IsValid(npc) or not IsValid(newWeapon) then return end
        pcall(function() npc:Give(newClass) end)

        -- Validate that the NPC actually received the weapon (some NPC types cannot hold any)
        timer.Simple(0.1, function()
            if not IsValid(newWeapon) then return end
            if not IsValid(npc) then return end

            local equipped = false
            for _, w in ipairs(npc:GetWeapons()) do
                if IsValid(w) and w:GetClass() == newClass then
                    equipped = true
                    break
                end
            end

            if equipped then
                newWeapon:Remove()
                dprint("equip", npc:GetClass(), "<-", newClass)
            else
                -- Give failed: NPC cannot hold weapons. Leave world entity intact for others.
                npc.ADS_CanScavenge = false
                ScavengerNPCs[npc]  = nil  -- stop Think from processing this NPC
                dprint("equip FAILED for", npc:GetClass(),
                       "leaving weapon in world, marking as non-scavenger")
            end
        end)
    end

    if animDuration > 0 then
        timer.Simple(animDuration * 0.7, doEquip)
    else
        doEquip()
    end

    -- Clear target and apply cooldown regardless of equip outcome
    npc.ADS_ScavengerTargetWeapon = nil
    ApplyPostDropCooldown(npc)
end

-- ============================================================
-- Find best weapon
-- ============================================================

local function HasNoWeapon(npc)
    local wep = npc:GetActiveWeapon()
    return not IsValid(wep) or wep:GetClass() == "weapon_nothingfornpc"
end

local function FindBestWeapon(npc)
    if not IsValid(npc) then return nil end

    -- Baseline: must strictly beat what NPC currently has
    local curWep    = npc:GetActiveWeapon()
    local curWeight = 0
    if IsValid(curWep) and curWep:GetClass() ~= "weapon_nothingfornpc" then
        curWeight = GetWeaponWeight(curWep)
    end

    local bestWep    = nil
    local bestWeight = curWeight

    for _, ent in ipairs(ents.FindInSphere(npc:GetPos(), SEARCH_RAD:GetFloat())) do
        if not IsValid(ent) then continue end
        if not ent:IsWeapon() then continue end
        if not IsScavengeable(ent) then continue end
        if not npc:Visible(ent) then continue end  -- avoids weapons through walls
        -- Skip weapons this NPC dropped recently (ownership window prevents self re-pick)
        if ent.ADS_DroppedBy == npc:EntIndex() then
            local elapsed = CurTime() - (ent.ADS_DroppedByTime or 0)
            if elapsed < DROP_OWN_T:GetFloat() then continue end
        end
        local w = GetWeaponWeight(ent)
        if w > bestWeight then
            bestWeight = w
            bestWep    = ent
        end
    end

    return bestWep
end

-- ============================================================
-- Per-NPC processing (called from Think)
-- ============================================================

local function ProcessScavengerNPC(npc)
    if not IsValid(npc) then return end
    if npc:Health() <= 0 then return end

    -- Combat interrupt gate: unarmed NPCs always bypass; others respect convar
    if IsValid(npc:GetEnemy()) and not INT_COMBAT:GetBool() then
        if not HasNoWeapon(npc) then return end
    end

    -- If already tracking a target, check it first
    local target = npc.ADS_ScavengerTargetWeapon
    if IsValid(target) then
        if not IsScavengeable(target) then
            -- Target expired or removed; fall through to find a new one
            npc.ADS_ScavengerTargetWeapon = nil
        else
            local dist = npc:GetPos():Distance(target:GetPos())
            if dist <= PICKUP_DIST:GetFloat() then
                EquipWeapon(npc, target)
            end
            -- Still en-route; MoveNPCToWeapon was already called, don't repeat
            return
        end
    end

    -- No current target: scan for a better weapon
    local best = FindBestWeapon(npc)
    if not best then return end

    local dist = npc:GetPos():Distance(best:GetPos())
    dprint("target", npc:GetClass(), "->", best:GetClass(),
        "dist="    .. string.format("%.0f", dist),
        "weight="  .. string.format("%.1f", GetWeaponWeight(best)))

    if dist <= PICKUP_DIST:GetFloat() then
        EquipWeapon(npc, best)
    else
        npc.ADS_ScavengerTargetWeapon = best
        MoveNPCToWeapon(npc, best)
    end
end

-- ============================================================
-- Global Think loop — single hook, no per-NPC Think overhead
-- ============================================================

hook.Add("Think", "ADS_Scavenger_Think", function()
    if not SCAV_EN:GetBool() then return end
    if not next(ScavengerNPCs) then return end  -- early exit when world is empty

    local now = CurTime()
    for npc, _ in pairs(ScavengerNPCs) do
        if not IsValid(npc) then
            ScavengerNPCs[npc] = nil
            continue
        end
        if not npc.ADS_CanScavenge then
            ScavengerNPCs[npc] = nil
            continue
        end
        if now < (npc.ADS_NextScavengerCheck or 0) then continue end
        npc.ADS_NextScavengerCheck = now + THINK_INT:GetFloat()
        ProcessScavengerNPC(npc)
    end
end)

-- ============================================================
-- Drop detection: NPC death
-- ============================================================

hook.Add("OnNPCKilled", "ADS_Scavenger_NPCKilled", function(npc, attacker, inflictor)
    -- Record what weapon class the NPC had before it was killed
    local wep = npc:GetActiveWeapon()
    if not IsValid(wep) then return end
    local wclass = wep:GetClass()
    if wclass == "weapon_nothingfornpc" then return end

    local lastPos = npc:GetPos()
    -- Small delay: Source creates the dropped weapon entity slightly after the kill event
    timer.Simple(0.15, function()
        for _, ent in ipairs(ents.FindInSphere(lastPos, 120)) do
            if not IsValid(ent) then continue end
            if not ent:IsWeapon() then continue end
            if ent:GetClass() ~= wclass then continue end
            if ent.ADS_WasDropped then continue end  -- already marked by another source
            if IsValid(ent:GetOwner()) then continue end
            -- Pass the dead NPC as dropper: it can't pick it up (it's dead), but
            -- using MarkWeaponAsDroppedBy lets other code distinguish source if needed.
            ADS.MarkWeaponAsDroppedBy(ent, npc, false)
        end
    end)
end)

-- ============================================================
-- Drop detection: Player drops weapon
-- ============================================================

hook.Add("PlayerDroppedWeapon", "ADS_Scavenger_PlayerDrop", function(ply, weapon)
    if not IsValid(weapon) then return end
    ADS.MarkWeaponAsDropped(weapon, false)
end)

-- ============================================================
-- Entity creation: NPC registration + world weapon marking
-- ============================================================

hook.Add("OnEntityCreated", "ADS_Scavenger_EntityCreated", function(ent)
    if not IsValid(ent) then return end

    if ent:IsWeapon() then
        -- World weapon: mark as permanent if the convar is enabled.
        -- Deferred one frame so PlayerDroppedWeapon/OnNPCKilled can mark first;
        -- if another source already set ADS_WasDropped, we skip.
        if WORLD_WEPS:GetBool() then
            timer.Simple(0, function()
                if not IsValid(ent) then return end
                if ent.ADS_WasDropped then return end     -- already claimed by NPC/player drop
                if IsValid(ent:GetOwner()) then return end  -- currently owned
                ADS.MarkWeaponAsDropped(ent, true)
            end)
        end
        return
    end

    if not ent:IsNPC() then return end
    -- Delay > ads_core's 0.2s and ads_limbs's 0.3s; also lets VJ finish arming the NPC
    timer.Simple(0.5, function()
        RegisterNPC(ent)
    end)
end)

-- ============================================================
-- Cleanup
-- ============================================================

hook.Add("EntityRemoved", "ADS_Scavenger_Cleanup", function(ent)
    ScavengerNPCs[ent] = nil
end)

-- ============================================================
-- Console commands (admin-only)
-- ============================================================

concommand.Add("ads_scavenger_set_weight", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local class  = args[1]
    local weight = tonumber(args[2])
    if not class or not weight then
        print("[ADS Scavenger] Usage: ads_scavenger_set_weight <class> <weight>")
        return
    end
    ADS.SetWeaponWeight(class, weight)
end)

concommand.Add("ads_scavenger_clear_weight", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local class = args[1]
    if not class then
        print("[ADS Scavenger] Usage: ads_scavenger_clear_weight <class>")
        return
    end
    ADS.ScavengerWeightOverrides[class] = nil
    SaveOverrides()
    for _, wep in ipairs(ents.FindByClass(class)) do
        if IsValid(wep) then wep.ADS_AutoWeight = nil end
    end
    print("[ADS Scavenger] Weight override cleared for:", class)
end)

concommand.Add("ads_scavenger_list_weights", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    print("[ADS Scavenger] Weight overrides:")
    local count = 0
    for class, weight in pairs(ADS.ScavengerWeightOverrides) do
        print(string.format("  %-40s = %.2f", class, weight))
        count = count + 1
    end
    if count == 0 then print("  (none)") end
end)

-- ============================================================
-- Startup
-- ============================================================

LoadOverrides()
print(string.format("[ADS Scavenger] Loaded. Weight overrides: %d", table.Count(ADS.ScavengerWeightOverrides)))

-- ============================================================
-- NOTE FOR INTEGRATION WITH ADS LIMBS
-- ============================================================
-- To integrate weapon drops from the limb system, add the following
-- call inside TryDropWeapon() in ads_limbs.lua, after a successful drop.
-- Use MarkWeaponAsDroppedBy (not MarkWeaponAsDropped) so the NPC that
-- lost its arm cannot immediately re-scavenge its own weapon:
--
--   if ADS.MarkWeaponAsDroppedBy then
--       ADS.MarkWeaponAsDroppedBy(wep, npc)
--   end
--
-- Place it just after the pcall that calls npc:DropWeapon() succeeds,
-- AND after the fallback world-weapon-spawn block. Both paths should mark.
-- The check "if ADS.MarkWeaponAsDroppedBy then" is safe even if
-- ads_scavenger.lua is not installed.
-- Without this call, a broken-arm NPC will re-pick up its own dropped
-- weapon on the next scavenger tick (Repair 1 won't cover this case).
