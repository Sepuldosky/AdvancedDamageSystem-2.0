-- Advanced Damage System - Core
ADS = ADS or {}

local S_MIN  = CreateConVar("ads_min_arm",       "0",   FCVAR_REPLICATED + FCVAR_ARCHIVE)
local S_MAX  = CreateConVar("ads_max_arm",       "100", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local P_STR  = CreateConVar("ads_ply_arm",       "100", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local R_MIN  = CreateConVar("ads_red_min",       "15",  FCVAR_REPLICATED + FCVAR_ARCHIVE)
local R_MAX  = CreateConVar("ads_red_max",       "80",  FCVAR_REPLICATED + FCVAR_ARCHIVE)
local BLAST  = CreateConVar("ads_blast_mult",    "0.5", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local CRUSH  = CreateConVar("ads_crush_mult",    "0.5", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local HELMET = CreateConVar("ads_helmet_mult",   "0.5", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local SND_EN = CreateConVar("ads_sound_enabled", "1",   FCVAR_REPLICATED + FCVAR_ARCHIVE)
local GSB_EN = CreateConVar("ads_gunshotblocked_enabled", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local HS_EN  = CreateConVar("ads_headshot_sound_enabled", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local EN_NPC = CreateConVar("ads_enabled_npc",   "1",   FCVAR_REPLICATED + FCVAR_ARCHIVE)
local EN_PLY = CreateConVar("ads_enabled_ply",   "1",   FCVAR_REPLICATED + FCVAR_ARCHIVE)
local LM_H   = CreateConVar("ads_limb_mult_head","1.0", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local LM_C   = CreateConVar("ads_limb_mult_chest","1.0",FCVAR_REPLICATED + FCVAR_ARCHIVE)
local LM_A   = CreateConVar("ads_limb_mult_arm", "1.0", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local LM_L   = CreateConVar("ads_limb_mult_leg", "1.0", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local ENG_COMP = CreateConVar("ads_engine_hitgroup_compensation", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE,
    "Cancel Source engine native hitgroup scaling (0.25x limbs, 2.0x head) so ADS damage matches HP loss")
CreateConVar("ads_vj_autodetect",                "1",   FCVAR_REPLICATED + FCVAR_ARCHIVE)
local DBG        = CreateConVar("ads_debug",        "0", FCVAR_ARCHIVE,
    "0=off  1=compact (one line/hit)  2=verbose (block/hit + events)  3=full pipeline (detour DET + stash race + no_stash alerts)")
local DBG_FILTER = CreateConVar("ads_debug_filter", "", FCVAR_ARCHIVE,
    "Filter trace to this NPC classname. Empty = all.")

-- EntIndex of a picked NPC (ads_debug_pick sets this). 0 = off.
local _dbgPickIdx = 0

-- level: minimum ads_debug tier required to print (1 or 2).
local function dprint(level, ...)
    if DBG:GetInt() < level then return end
    print("[ADS]", ...)
end

-- Returns true when 'npc' passes the active filter (pick or classname).
-- Auto-clears the pick index if the picked entity is gone.
local function _dbgPass(npc)
    if not IsValid(npc) then return false end
    if _dbgPickIdx ~= 0 then
        local picked = Entity(_dbgPickIdx)
        if not IsValid(picked) then _dbgPickIdx = 0 end  -- auto-clear stale pick
        if IsValid(picked) then return npc == picked end
    end
    local f = DBG_FILTER:GetString()
    return f == "" or npc:GetClass() == f
end

-- ads_debug_pick: aim at an NPC and run to pin the trace filter to it.
-- Admin-only. Run again on empty space, or set ads_debug_filter "", to release.
concommand.Add("ads_debug_pick", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "[ADS] ads_debug_pick requires admin.")
        return
    end
    local tr = util.TraceLine({
        start  = IsValid(ply) and ply:EyePos()                    or Vector(0,0,0),
        endpos = IsValid(ply) and ply:EyePos() + ply:GetAimVector() * 2048 or Vector(0,0,0),
        filter = IsValid(ply) and ply or nil,
    })
    local ent = tr.Entity
    if IsValid(ent) and ent:IsNPC() then
        _dbgPickIdx = ent:EntIndex()
        local msg = "[ADS] debug pick -> " .. ent:GetClass() .. " (ent #" .. _dbgPickIdx .. ")"
        print(msg)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) end
    else
        _dbgPickIdx = 0
        local msg = "[ADS] debug pick cleared"
        print(msg)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) end
    end
end)

-- ── ads_test_vj_inject — valida punto de inyección PreDamage de VJ ──────────
-- Admin-only. Apunta a un NPC VJ y corre el comando.
-- El próximo daño que reciba ese NPC se fuerza a 999 vía CustomOnTakeDamage_BeforeDamage.
-- Loguea el valor que llegó al hook (post-engine) y el que se inyectó.
-- El parche se elimina solo después del primer hit.
concommand.Add("ads_test_vj_inject", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "[ADS TEST] requires admin.")
        return
    end
    local tr = util.TraceLine({
        start  = IsValid(ply) and ply:EyePos()                         or Vector(0,0,0),
        endpos = IsValid(ply) and ply:EyePos() + ply:GetAimVector() * 2048 or Vector(0,0,0),
        filter = IsValid(ply) and ply or nil,
    })
    local ent = tr.Entity
    if not IsValid(ent) or not ent:IsNPC() or not ent.IsVJBaseSNPC then
        local msg = "[ADS TEST] ads_test_vj_inject: aim at a VJ NPC."
        print(msg)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) end
        return
    end

    local msg = "[ADS TEST] inject armed -> " .. ent:GetClass() .. " (ent #" .. ent:EntIndex() .. ")"
    print(msg)
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) end

    -- Parchear CustomOnTakeDamage_BeforeDamage en la instancia (no en el prototipo)
    local prev = ent.CustomOnTakeDamage_BeforeDamage
    ent.CustomOnTakeDamage_BeforeDamage = function(self, dmginfo, hitgroup)
        local before = dmginfo:GetDamage()
        local forced = tonumber(args and args[1]) or 50
        dmginfo:SetDamage(forced)
        print(string.format(
            "[ADS TEST] PreDamage inject: hg=%d  engine_delivered=%.2f  forced=%g  frame=%d",
            hitgroup, before, forced, FrameNumber()))
        -- Restaurar después del primer hit
        self.CustomOnTakeDamage_BeforeDamage = prev
        if prev then return prev(self, dmginfo, hitgroup) end
    end
end)
-- ─────────────────────────────────────────────────────────────────────────────

-- ads_dump_vj_scale — dumpea campos de damage scale en un NPC VJ apuntado.
-- Busca campos conocidos de VJ Base + sweep numérico en rango [0.05, 0.75].
-- Admin-only.
concommand.Add("ads_dump_vj_scale", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "[ADS DUMP] requires admin.")
        return
    end
    local tr = util.TraceLine({
        start  = IsValid(ply) and ply:EyePos()                         or Vector(0,0,0),
        endpos = IsValid(ply) and ply:EyePos() + ply:GetAimVector() * 2048 or Vector(0,0,0),
        filter = IsValid(ply) and ply or nil,
    })
    local ent = tr.Entity
    if not IsValid(ent) or not ent:IsNPC() then
        print("[ADS DUMP] aim at an NPC.")
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, "[ADS DUMP] aim at an NPC.") end
        return
    end

    print(string.format("[ADS DUMP] === %s (ent #%d)  HP=%.1f ===",
        ent:GetClass(), ent:EntIndex(), ent:Health()))
    print(string.format("  IsVJBaseSNPC = %s", tostring(ent.IsVJBaseSNPC)))

    -- Campos conocidos de VJ Base y GMod nativos relacionados a damage scale
    local knownFields = {
        "BulletDamageScale", "VJ_DamageMultiplier", "VJC_AllDamageMultiplier",
        "AllDamageMultiplier", "BulletDamageMultiplier", "DamageMultiplier",
        "VJ_NPC_DmgMul", "VJ_NPC_BulletDmgMul", "VJ_AddDamageMul",
        "VJ_DmgMul_Bullet", "VJ_DmgMul_AllDamage",
    }
    print("  [known fields]")
    local anyKnown = false
    local etblKnown = ent:GetTable()
    for _, k in ipairs(knownFields) do
        local v = etblKnown[k]
        if v ~= nil then
            print(string.format("    ent.%s = %s", k, tostring(v)))
            anyKnown = true
        end
    end
    if not anyKnown then print("    (ninguno presente)") end

    -- Método nativo GMod NPC
    if ent.GetBulletDamageScale then
        print(string.format("  GetBulletDamageScale() = %s", tostring(ent:GetBulletDamageScale())))
    end

    -- Sweep: todos los campos numéricos en rango sospechoso [0.05, 0.75]
    -- Las entidades son userdata; sus campos Lua viven en ent:GetTable().
    print("  [numeric sweep 0.05-0.75]")
    local found = 0
    local etbl = ent:GetTable()
    for k, v in pairs(etbl) do
        if type(v) == "number" and v >= 0.05 and v <= 0.75 then
            print(string.format("    ent.%s = %g", tostring(k), v))
            found = found + 1
        end
    end
    if found == 0 then print("    (ninguno)") end
end)

-- ─────────────────────────────────────────────────────────────────────────────

ADS.HARDCODED_WHITELIST = {npc_combine_s=true,npc_metropolice=true,npc_citizen=true,npc_alyx=true,npc_barney=true}
ADS.HARDCODED_BLACKLIST = {npc_vj_cpriguarh=true}
ADS.VJ_CLASSNAME_PATTERNS = {"vj_hsold","vj_hs_","vj_combine","vj_metro","vj_metropolice","vj_cswat","vj_csold","vj_milit"}
ADS.VJ_ARMORED_CLASSES = {CLASS_COMBINE=true,CLASS_MILITARY=true,CLASS_METROPOLICE=true,CLASS_RESISTANCE=true,CLASS_UNITED_STATES=true,CLASS_POLICE=true,CLASS_SWAT=true,CLASS_SOLDIER=true}
ADS.UserWhitelist = {}
ADS.UserBlacklist = {}
ADS.ResolvedVJClass = {}

-- Source engine native hitgroup multipliers for NPCs (skill.cfg defaults).
-- Used to cancel engine scaling so ADS-calculated damage matches HP loss.
-- Some NPCs (VJ Base with custom resistances) may further modify damage in
-- their own OnTakeDamage; this compensation does not cover that case.
ADS.ENGINE_HG_MULT = {
    [HITGROUP_HEAD]     = 2.0,
    [HITGROUP_CHEST]    = 1.0,
    [HITGROUP_STOMACH]  = 1.0,
    [HITGROUP_GENERIC]  = 1.0,
    [HITGROUP_LEFTARM]  = 0.25,
    [HITGROUP_RIGHTARM] = 0.25,
    [HITGROUP_LEFTLEG]  = 0.25,
    [HITGROUP_RIGHTLEG] = 0.25,
    [HITGROUP_GEAR]     = 1.0,
}

local CONFIG_DIR="ads"
local CONFIG_PATH="ads/ads_config.json"

function ADS.SaveConfig()
    file.CreateDir(CONFIG_DIR)
    file.Write(CONFIG_PATH, util.TableToJSON({
        whitelist       = ADS.UserWhitelist,
        blacklist       = ADS.UserBlacklist,
        armor           = ADS.ArmorProfiles or {},
        curated_weapons = ADS.CuratedWeapons or {},
        ammo_fallback   = (ADS.GetAmmoFallbackOverrides and ADS.GetAmmoFallbackOverrides()) or {},
    }, true))
end

function ADS.LoadConfig()
    ADS.UserWhitelist={} ADS.UserBlacklist={}
    if not file.Exists(CONFIG_PATH,"DATA") then ADS.SaveConfig() return end
    local raw=file.Read(CONFIG_PATH,"DATA")
    local tbl=raw and util.JSONToTable(raw) or nil
    if type(tbl)~="table" then print("[ADS] config corrupto") return end
    if type(tbl.whitelist)=="table" then
        for c,d in pairs(tbl.whitelist) do if type(d)=="table" then ADS.UserWhitelist[c]=d end end
    end
    if type(tbl.blacklist)=="table" then
        for c,v in pairs(tbl.blacklist) do if v then ADS.UserBlacklist[c]=true end end
    end
    if ADS.LoadArmorData then ADS.LoadArmorData(tbl) end
end

function ADS.IsArmored(ent)
    if not IsValid(ent) then return false end
    if ent:IsPlayer() then return EN_PLY:GetBool() end
    if not ent:IsNPC() then return false end
    if not EN_NPC:GetBool() then return false end
    local c=ent:GetClass()
    if ADS.UserBlacklist[c] then return false end
    if ADS.UserWhitelist[c] then return true end
    if ADS.HARDCODED_BLACKLIST[c] then return false end
    if ADS.HARDCODED_WHITELIST[c] then return true end
    for _,p in ipairs(ADS.VJ_CLASSNAME_PATTERNS) do
        if string.find(c,p,1,true) then return true end
    end
    if GetConVar("ads_vj_autodetect"):GetBool() and ent.IsVJBaseSNPC then
        local v=ent.VJ_NPC_Class
        if type(v)=="table" then
            for _,cc in ipairs(v) do if ADS.VJ_ARMORED_CLASSES[cc] then return true end end
        elseif type(v)=="string" and ADS.VJ_ARMORED_CLASSES[v] then return true end
    end
    return false
end

function ADS.GetArmorReason(ent)
    if not IsValid(ent) then return "Invalid" end
    if ent:IsPlayer() then return EN_PLY:GetBool() and "Player" or "Player disabled" end
    if not ent:IsNPC() then return "Not NPC" end
    if not EN_NPC:GetBool() then return "NPC system disabled" end
    local c=ent:GetClass()
    if ADS.UserBlacklist[c] then return "Blacklisted (user)" end
    if ADS.UserWhitelist[c] then return "Whitelisted (user)" end
    if ADS.HARDCODED_BLACKLIST[c] then return "Hardcoded blacklist" end
    if ADS.HARDCODED_WHITELIST[c] then return "Hardcoded whitelist" end
    for _,p in ipairs(ADS.VJ_CLASSNAME_PATTERNS) do
        if string.find(c,p,1,true) then return "VJ pattern ("..p..")" end
    end
    if GetConVar("ads_vj_autodetect"):GetBool() and ent.IsVJBaseSNPC then
        local v=ent.VJ_NPC_Class
        if type(v)=="table" then
            for _,cc in ipairs(v) do if ADS.VJ_ARMORED_CLASSES[cc] then return "VJ auto ("..cc..")" end end
        elseif type(v)=="string" and ADS.VJ_ARMORED_CLASSES[v] then return "VJ auto ("..v..")" end
    end
    return "Not armored"
end

-- Resuelve el estado de un classname sin necesitar instancia viva.
-- Devuelve: "wl_user", "bl_user", "wl_hard", "bl_hard", "vj_pattern",
--          "vj_auto", "unknown" (candidato VJ no resuelto) o "none".
function ADS.GetClassStatus(classname)
    if not classname or classname == "" then return "none" end
    if ADS.UserBlacklist[classname]   then return "bl_user" end
    if ADS.UserWhitelist[classname]   then return "wl_user" end
    if ADS.HARDCODED_BLACKLIST[classname] then return "bl_hard" end
    if ADS.HARDCODED_WHITELIST[classname] then return "wl_hard" end
    for _, p in ipairs(ADS.VJ_CLASSNAME_PATTERNS) do
        if string.find(classname, p, 1, true) then return "vj_pattern" end
    end
    if GetConVar("ads_vj_autodetect"):GetBool() then
        local cached = ADS.ResolvedVJClass[classname]
        if cached == true then return "vj_auto" end
        if cached == false then return "none" end
        -- nil = nunca se ha visto una instancia de este classname
        if string.find(classname, "vj_", 1, true) or string.find(classname, "npc_vj_", 1, true) then
            return "unknown"
        end
    end
    return "none"
end

function ADS.GetOverride(class)
    local o=ADS.UserWhitelist[class]
    if type(o)=="table" and next(o)~=nil then return o end
    return nil
end

-- Consulta mult de zona: override > convar global > 1.0
local function GetZoneMult(override, key, convar)
    if override and override.dmg_mult and override.dmg_mult[key] ~= nil then
        return tonumber(override.dmg_mult[key]) or 1.0
    end
    return convar:GetFloat()
end


local function Sanitize(data)
    if type(data)~="table" then return {} end
    local c={}
    -- Limb HP fraction overrides (0-2 range, 2dp; >1 allowed for reinforced limbs)
    if tonumber(data.head_hp_frac) then c.head_hp_frac=math.Round(math.Clamp(tonumber(data.head_hp_frac),0,2)*100)/100 end
    if tonumber(data.arms_hp_frac) then c.arms_hp_frac=math.Round(math.Clamp(tonumber(data.arms_hp_frac),0,2)*100)/100 end
    if tonumber(data.legs_hp_frac) then c.legs_hp_frac=math.Round(math.Clamp(tonumber(data.legs_hp_frac),0,2)*100)/100 end
    -- limb damage transfer per zone (0-3 range; head can exceed 1.0 to ensure pools drain fast enough)
    if tonumber(data.limb_damage_transfer_head) then c.limb_damage_transfer_head=math.Round(math.Clamp(tonumber(data.limb_damage_transfer_head),0,3)*100)/100 end
    if tonumber(data.limb_damage_transfer_arms) then c.limb_damage_transfer_arms=math.Round(math.Clamp(tonumber(data.limb_damage_transfer_arms),0,3)*100)/100 end
    if tonumber(data.limb_damage_transfer_legs) then c.limb_damage_transfer_legs=math.Round(math.Clamp(tonumber(data.limb_damage_transfer_legs),0,3)*100)/100 end
    if type(data.dmg_mult)=="table" then
        local m={}
        for _,k in ipairs({"head","chest","arm","leg"}) do
            local v=tonumber(data.dmg_mult[k])
            if v then m[k]=math.Round(math.Clamp(v,0,10)*100)/100 end
        end
        -- Solo guardar si al menos un mult no es 1.0
        local anyNonUnit=false
        for _,v in pairs(m) do if v~=1.0 then anyNonUnit=true break end end
        if anyNonUnit then c.dmg_mult=m end
    end
    return c
end

-- Valida y clampa un perfil de armadura zonal antes de persistir.
-- Retorna tabla limpia, o nil si no hay zonas ni fallback válidos (= borrar perfil).
local function SanitizeArmor(profile)
    if type(profile) ~= "table" then return nil end
    local out = {}

    -- Zonas por hitgroup (keys "1".."7")
    if type(profile.zones) == "table" then
        local zones = {}
        for hg = 1, 7 do
            local key = tostring(hg)
            local z = profile.zones[key]
            if type(z) == "table" then
                local cls = math.floor(math.Clamp(tonumber(z.class)   or 3,   1, 8))
                local dur = math.floor(math.Clamp(tonumber(z.dur_max) or 80,  1, 200))
                local mat = (type(z.material) == "string" and ADS.Materials and ADS.Materials[z.material])
                            and z.material or "aramid"
                zones[key] = { class = cls, dur_max = dur, material = mat }
            end
        end
        if next(zones) then out.zones = zones end
    end

    -- Fallback para hitgroup GENERIC y zonas sin placa
    if type(profile.fallback_generic) == "table" then
        local fg = profile.fallback_generic
        local cls = math.floor(math.Clamp(tonumber(fg.class)   or 3,   1, 8))
        local dur = math.floor(math.Clamp(tonumber(fg.dur_max) or 80,  1, 200))
        local mat = (type(fg.material) == "string" and ADS.Materials and ADS.Materials[fg.material])
                    and fg.material or "aramid"
        out.fallback_generic = { class = cls, dur_max = dur, material = mat }
    end

    -- Metadato opaco de UI (no tiene efecto en runtime)
    if type(profile.coverage_profile) == "string" then
        out.coverage_profile = string.sub(profile.coverage_profile, 1, 64)
    end

    -- Perfil sin zonas ni fallback = nil → el handler borrará el perfil de la clase
    if not out.zones and not out.fallback_generic then return nil end
    return out
end

-- Variantes internas sin SaveConfig/broadcast, para operaciones batch
local function _WlAddNoSave(classname, data)
    if not classname or classname=="" then return end
    ADS.UserBlacklist[classname]=nil
    ADS.UserWhitelist[classname]=Sanitize(data)
end
local function _WlDelNoSave(classname)
    ADS.UserWhitelist[classname]=nil
end
local function _BlAddNoSave(classname)
    if not classname or classname=="" or ADS.UserBlacklist[classname] then return end
    ADS.UserWhitelist[classname]=nil
    ADS.UserBlacklist[classname]=true
end
local function _BlDelNoSave(classname)
    ADS.UserBlacklist[classname]=nil
end

function ADS.AddToWhitelist(classname,data)
    if not classname or classname=="" then return false end
    _WlAddNoSave(classname,data)
    ADS.SaveConfig() return true
end
function ADS.RemoveFromWhitelist(c)
    if not c or not ADS.UserWhitelist[c] then return false end
    _WlDelNoSave(c) ADS.SaveConfig() return true
end
function ADS.AddToBlacklist(c)
    if not c or c=="" or ADS.UserBlacklist[c] then return false end
    _BlAddNoSave(c)
    ADS.SaveConfig() return true
end
function ADS.RemoveFromBlacklist(c)
    if not c or not ADS.UserBlacklist[c] then return false end
    _BlDelNoSave(c) ADS.SaveConfig() return true
end
function ADS.ClearWhitelist() ADS.UserWhitelist={} ADS.SaveConfig() end
function ADS.ClearBlacklist() ADS.UserBlacklist={} ADS.SaveConfig() end

function ADS.InspectNPC(ent)
    if not IsValid(ent) then return nil end
    local i={classname=ent:GetClass(),is_vj=ent.IsVJBaseSNPC==true,vj_class=nil,
             armor=(ent:IsPlayer() and ent:Armor() or 0),is_armored=ADS.IsArmored(ent),reason=ADS.GetArmorReason(ent),
             override=ADS.GetOverride(ent:GetClass()),
             is_whitelisted=ADS.UserWhitelist[ent:GetClass()]~=nil}
    if i.is_vj then
        local v=ent.VJ_NPC_Class
        if type(v)=="table" then i.vj_class=table.concat(v,", ")
        elseif type(v)=="string" then i.vj_class=v end
    end
    -- Armor slots: NWvars pobladas por ads_armor.lua en InitArmorNWvars/ApplyArmorDirect
    if ent:GetNWBool("ADS_Armor_Init", false) then
        local slots = {}
        for hg = 0, 7 do
            local cls = ent:GetNWInt("ADS_Armor_Class_" .. hg, 0)
            if cls > 0 then
                slots[tostring(hg)] = {
                    class    = cls,
                    dur      = ent:GetNWInt("ADS_Armor_Dur_"    .. hg, 0),
                    dur_max  = ent:GetNWInt("ADS_Armor_MaxDur_" .. hg, 0),
                    material = ent:GetNWString("ADS_Armor_Mat_" .. hg, ""),
                }
            end
        end
        i.armor_slots   = slots
        i.armor_init    = true
        i.tool_override = ent.ADS_ToolArmorOverride == true
    end
    -- Limb HP pools (populated by ads_limbs.lua on spawn)
    if ent.ADS_HP_HeadMax then
        local function lr(cur,max) return (max and max>0) and math.Clamp(cur/max,0,1) or 0 end
        i.limbs={
            head  ={hp=ent.ADS_HP_Head, max=ent.ADS_HP_HeadMax, ratio=lr(ent.ADS_HP_Head, ent.ADS_HP_HeadMax)},
            arm_l ={hp=ent.ADS_HP_ArmL, max=ent.ADS_HP_ArmLMax, ratio=lr(ent.ADS_HP_ArmL, ent.ADS_HP_ArmLMax)},
            arm_r ={hp=ent.ADS_HP_ArmR, max=ent.ADS_HP_ArmRMax, ratio=lr(ent.ADS_HP_ArmR, ent.ADS_HP_ArmRMax)},
            leg_l ={hp=ent.ADS_HP_LegL, max=ent.ADS_HP_LegLMax, ratio=lr(ent.ADS_HP_LegL, ent.ADS_HP_LegLMax)},
            leg_r ={hp=ent.ADS_HP_LegR, max=ent.ADS_HP_LegRMax, ratio=lr(ent.ADS_HP_LegR, ent.ADS_HP_LegRMax)},
        }
    end
    -- Scavenger state (populated by ads_scavenger.lua; field exists even when false)
    if ent.ADS_CanScavenge ~= nil then
        i.scavenger = {
            can_scavenge       = ent.ADS_CanScavenge,
            cooldown_remaining = math.max(0, (ent.ADS_NextScavengerCheck or 0) - CurTime()),
            target_weapon      = IsValid(ent.ADS_ScavengerTargetWeapon)
                                     and ent.ADS_ScavengerTargetWeapon:GetClass() or nil,
        }
        local cur = ent:GetActiveWeapon()
        if IsValid(cur) then
            i.scavenger.current_weapon = cur:GetClass()
            if ADS.GetWeaponWeight then
                i.scavenger.current_weapon_weight = ADS.GetWeaponWeight(cur)
            end
        end
    end
    return i
end

-- BLOCKABLE: DMG_CRUSH(1), DMG_BULLET(2), DMG_SLASH(4), DMG_BLAST(64),
-- DMG_CLUB(128), DMG_BUCKSHOT(33554432), DMG_SNIPER(1073741824)
-- Nota: el comentario original era incorrecto — 16=DMG_VEHICLE, 1048576=DMG_PHYSGUN,
-- ninguno de los dos debe bloquearse. DMG_SLASH=4 y DMG_BUCKSHOT=33554432 son los reales.
local BLOCKABLE = bit.bor(
    1,           -- DMG_CRUSH
    2,           -- DMG_BULLET
    4,           -- DMG_SLASH
    64,          -- DMG_BLAST
    128,         -- DMG_CLUB
    33554432,    -- DMG_BUCKSHOT
    1073741824   -- DMG_SNIPER
)

hook.Add("OnEntityCreated","ADS_NPC_Init",function(e)
    timer.Simple(0.2,function()
        if not IsValid(e) or e:IsPlayer() or not e:IsNPC() then return end
        -- Poblar cache VJ si aplica, antes de IsArmored (así el browser se entera)
        if e.IsVJBaseSNPC and ADS.ResolvedVJClass[e:GetClass()] == nil then
            local v = e.VJ_NPC_Class
            local matched = false
            if type(v) == "table" then
                for _, cc in ipairs(v) do
                    if ADS.VJ_ARMORED_CLASSES[cc] then matched = true break end
                end
            elseif type(v) == "string" and ADS.VJ_ARMORED_CLASSES[v] then
                matched = true
            end
            ADS.ResolvedVJClass[e:GetClass()] = matched
            dprint(2, "vj cache resolved",e:GetClass(),"=",tostring(matched))
        end
        if ADS.InitArmorNWvars then ADS.InitArmorNWvars(e) end
    end)
end)



-- Fase 2: multiplicador de zona (solo NPCs, aplica aunque no haya armor)
local function ApplyDamageMultiplier(victim,hitgroup,dmginfo)
    if not victim:IsNPC() then return end
    if dmginfo:GetDamage()<=0 then return end
    local dt=dmginfo:GetDamageType()
    if bit.band(dt,BLOCKABLE)==0 then return end
    -- Explosiones y crush ignoran esta fase (ya gobernadas por blast_mult/crush_mult)
    if bit.band(dt,64)~=0 then return end
    if bit.band(dt,1)~=0  then return end

    local override=ADS.GetOverride(victim:GetClass())
    local mult
    if hitgroup==HITGROUP_HEAD then
        mult=GetZoneMult(override,"head",LM_H)
    elseif hitgroup==HITGROUP_CHEST or hitgroup==HITGROUP_STOMACH or hitgroup==HITGROUP_GENERIC then
        mult=GetZoneMult(override,"chest",LM_C)
    elseif hitgroup==HITGROUP_LEFTARM or hitgroup==HITGROUP_RIGHTARM then
        mult=GetZoneMult(override,"arm",LM_A)
    elseif hitgroup==HITGROUP_LEFTLEG or hitgroup==HITGROUP_RIGHTLEG then
        mult=GetZoneMult(override,"leg",LM_L)
    else
        return
    end
    if mult==1.0 then return end
    local d=dmginfo:GetDamage()
    dmginfo:SetDamage(d*mult)
end

-- Sonidos custom del addon (carpeta sound/ads/). Se referencian relativos a sound/.
local SND_BLOCKED  = { "ads/GunshotBlocked.wav", "ads/GunshotBlocked2.wav" }
local SND_HS_HARD  = "ads/HeadshotHard.wav"    -- casco detiene la bala
local SND_HS_LIGHT = "ads/HeadshotLight.wav"   -- bala penetra el casco
-- precache: evita que el primer disparo suene mudo
for _, s in ipairs(SND_BLOCKED) do util.PrecacheSound(s) end
util.PrecacheSound(SND_HS_HARD)
util.PrecacheSound(SND_HS_LIGHT)

-- Feedback sonoro de armadura. Se llama siempre que se resolvió armadura sobre el NPC.
--   hg       : hitgroup impactado
--   material : string del material de la placa (clave de ADS.Materials)
--   blocked  : true si la placa detuvo la bala; false si penetró
--   dur      : durabilidad de la placa (modula el volumen del clang metálico)
local function PlayArmorSounds(npc, hg, material, blocked, dur)
    -- Cabeza con armadura: el ding de headshot REEMPLAZA todo lo demás
    -- (Hard = casco aguanta, Light = casco penetrado). Suena aunque el material
    -- sea blando: la cabeza es la excepción a "blandas en silencio".
    if hg == HITGROUP_HEAD and HS_EN:GetBool() then
        npc:EmitSound(blocked and SND_HS_HARD or SND_HS_LIGHT, 75, math.random(96,104), 1)
        return
    end

    -- Resto del cuerpo: solo suena al BLOQUEAR
    if not blocked then return end

    -- Placas blandas (aramida/fluido no-newtoniano) = silencio: no clanguean
    local mat = ADS.Materials[material]
    if not (mat and mat.hard) then return end

    -- gunshotblocked: la bala fue detenida por la armadura
    if GSB_EN:GetBool() then
        npc:EmitSound(SND_BLOCKED[math.random(1, #SND_BLOCKED)], 75, math.random(95,110), 1)
    end
    -- clang metálico: solo materiales duros; volumen según durabilidad restante
    if SND_EN:GetBool() then
        local vol = math.Clamp((dur or 100)/100, 0.4, 1)
        npc:EmitSound("physics/metal/metal_solid_impact_bullet"..math.random(1,4)..".wav", 75, math.random(90,110), vol)
    end
end


-- Hitgroup index -> readable name, used by debug trace
local _HG_NAME = {
    [HITGROUP_HEAD]     = "head",    [HITGROUP_CHEST]   = "chest",
    [HITGROUP_STOMACH]  = "stomach", [HITGROUP_GENERIC] = "generic",
    [HITGROUP_LEFTARM]  = "arm_l",   [HITGROUP_RIGHTARM]= "arm_r",
    [HITGROUP_LEFTLEG]  = "leg_l",   [HITGROUP_RIGHTLEG]= "leg_r",
}

hook.Add("ScaleNPCDamage","ADS_Core_NPC",function(npc,hg,di)
    -- ── debug: trace variables (populated per-phase below) ──────────────────
    local dbgOn   = DBG:GetInt() >= 1
    local dbgFull = DBG:GetInt() >= 2
    local dbgThis = dbgOn and _dbgPass(npc)
    local dmg_in  = di:GetDamage()

    local armorPath  = "disabled"   -- stash / stash_MISS / no_stash / inline / no_zone / non_blockable / not_armored
    local armorSrc   = "-"          -- eft / arc9 / tfa / fallback
    local armorPen   = nil          -- true=penetrated, false=blocked, nil=no armor
    local armorClass = 0
    local armorDurBef= 0
    local armorDurAft= 0
    local armorPenPow    = 0
    local stashFrameDelta = -1   -- tier 3: frames entre deposit y consume; -1 = no aplica
    -- ────────────────────────────────────────────────────────────────────────

    -- Pre-filtro de armadura 2.0. ARC9: consume el stash depositado por el detour
    -- de AfterShotFunction. VJ/HL2/TFA: resolve inline como antes.
    if ADS.GetZone and ADS.ResolveArmor and ADS.ExtractBulletData then
        local atk = di:GetAttacker()
        local wep = (IsValid(atk) and atk.GetActiveWeapon) and atk:GetActiveWeapon() or nil
        local isARC9 = IsValid(wep) and wep.GetProcessedValue ~= nil
        if isARC9 then
            local stash = npc.ADS_ArmorStash
            if stash and (FrameNumber() - stash.frame) <= 1 then
                local d = di:GetDamage()
                if d > 0 then
                    di:SetDamage(d * stash.factor)
                    if stash.durKey ~= nil and stash.durKey ~= "" then
                        npc:SetNWInt("ADS_Armor_Dur_" .. stash.durKey, stash.newDur)
                    end
                    PlayArmorSounds(npc, hg, stash.material, not stash.penetra, stash.newDur)
                end
                -- debug: read enriched stash fields deposited by the ARC9 detour
                armorPath   = "stash"
                armorSrc    = stash.src        or "arc9"
                armorPen    = stash.penetra
                armorClass  = stash.armorClass or 0
                armorDurBef = stash.durBefore  or 0
                armorDurAft = stash.newDur      or 0
                armorPenPow    = stash.penPower    or 0
                stashFrameDelta = FrameNumber() - stash.frame
                npc.ADS_ArmorStash = nil
            else
                -- Defensivo: el detour de AfterShotFunction no depositó stash (p.ej.
                -- NPC disparando ARC9 vía NPC_PrimaryAttack, o timing de frame perdido).
                -- Resolver inline en vez de dejar pasar la bala sin filtrar por armadura.
                local zona = ADS.GetZone(npc, hg)
                if zona and bit.band(di:GetDamageType(), BLOCKABLE) ~= 0 then
                    local tuple = ADS.ExtractBulletData(wep, di)
                    local res   = ADS.ResolveArmor(zona, tuple, hg)
                    di:SetDamage(res.fleshDmg)
                    npc:SetNWInt("ADS_Armor_Dur_" .. zona.durKey, res.newDur)
                    PlayArmorSounds(npc, hg, zona.material, res.factorPenleft == 0, zona.durActual)
                    armorPath   = "inline_arc9"
                    armorSrc    = tuple.source  or "-"
                    armorPen    = (res.factorPenleft > 0)
                    armorClass  = zona.clase
                    armorDurBef = zona.durActual
                    armorDurAft = res.newDur    or zona.durActual
                    armorPenPow = tuple.penPower or 0
                else
                    armorPath = stash and "stash_MISS" or "no_stash"
                end
                -- Tier 3: segmento ARC9 llegó a SND sin pasar por el detour
                if DBG:GetInt() >= 3 and _dbgPass(npc) then
                    print(string.format(
                        "[ADS DET] !! NO_STASH  f=%d  %s  hg=%d(%s)  raw=%.2f  path=%s  (segmento ARC9 sin detour)",
                        FrameNumber(), npc:GetClass(), hg, (_HG_NAME[hg] or tostring(hg)), dmg_in, armorPath))
                end
            end
        else
            local zona = ADS.GetZone(npc, hg)
            if zona and bit.band(di:GetDamageType(), BLOCKABLE) ~= 0 then
                local tuple = ADS.ExtractBulletData(wep, di)
                local res   = ADS.ResolveArmor(zona, tuple, hg)
                di:SetDamage(res.fleshDmg)
                npc:SetNWInt("ADS_Armor_Dur_" .. zona.durKey, res.newDur)
                PlayArmorSounds(npc, hg, zona.material, res.factorPenleft == 0, zona.durActual)
                -- debug: inline resolve
                armorPath   = "inline"
                armorSrc    = tuple.source  or "-"
                armorPen    = (res.factorPenleft > 0)
                armorClass  = zona.clase
                armorDurBef = zona.durActual
                armorDurAft = res.newDur    or zona.durActual
                armorPenPow = tuple.penPower or 0
            elseif not zona then
                armorPath = (ADS.IsArmored and ADS.IsArmored(npc)) and "no_zone" or "not_armored"
            else
                armorPath = "non_blockable"
            end
        end
    end
    ApplyDamageMultiplier(npc,hg,di)
    -- Limb HP subsystem (ads_limbs.lua); guarded so missing file is harmless
    npc.ADS_LastLimbHit = nil  -- clear stash before call so stale data never leaks
    if ADS.ProcessLimbHit then ADS.ProcessLimbHit(npc,hg,di) end
    -- Engine hitgroup compensation: ALWAYS LAST. Cancels Source's native
    -- post-hook scaling (0.25x limbs, 2.0x head) so the HP loss matches the
    -- damage value ADS already computed. Skip when mult is 1.0 (no-op zones)
    -- or when damage is non-positive after armor/mults.
    local dmg_pre_comp = di:GetDamage()
    local compEM = 1.0
    if ENG_COMP:GetBool() then
        local d = di:GetDamage()
        if d > 0 then
            local em = ADS.ENGINE_HG_MULT[hg]
            if em and em ~= 1.0 then
                di:SetDamage(d / em)
                compEM = em
            end
        end
    end
    local dmg_final = di:GetDamage()

    -- ── debug trace emit ────────────────────────────────────────────────────
    if dbgThis then
        local hgStr  = _HG_NAME[hg] or tostring(hg)
        local penStr = armorPen == true and "PEN" or armorPen == false and "BLK" or "---"
        local lb     = npc.ADS_LastLimbHit
        if dbgFull then
            -- Tier 2: verbose block
            print(string.format("[ADS HIT] ── %s  hg=%d(%s) ──────────────────",
                npc:GetClass(), hg, hgStr))
            print(string.format("  [armor]  path=%-12s src=%-8s pen=%-3s  cls=%d  penPow=%.0f  dur=%.0f->%.0f  in=%.1f->%.1f",
                armorPath, armorSrc, penStr, armorClass, armorPenPow,
                armorDurBef, armorDurAft, dmg_in, dmg_pre_comp))
            if lb then
                print(string.format("  [limb]   zone=%-6s  dmgPool=%.1f  pool=%.1f->%.1f/%.1f",
                    lb.zone, lb.dmgPool, lb.before, lb.after, lb.poolMax))
            else
                print("  [limb]   no pool (chest/stomach/generic or limbs disabled)")
            end
            if compEM ~= 1.0 then
                print(string.format("  [engcomp] em=%.2f  %.1f -> %.1f", compEM, dmg_pre_comp, dmg_final))
            else
                print("  [engcomp] skip (em=1.0)")
            end
            print(string.format("  [FINAL]  %.1f", dmg_final))
        else
            -- Tier 1: compact single line
            local limbStr = lb and (lb.zone .. string.format(" %.1f->%.1f", lb.before, lb.after)) or "-"
            local compStr = compEM ~= 1.0 and string.format(" eng/%.2f", compEM) or ""
            print(string.format("[ADS] %s hg=%d(%s) src=%-8s path=%-12s %s cls=%d penPow=%.0f  in=%.1f->%.1f  limb=[%s]%s",
                npc:GetClass(), hg, hgStr, armorSrc, armorPath,
                penStr, armorClass, armorPenPow,
                dmg_in, dmg_final, limbStr, compStr))
        end
    end
    -- Tier 3: SND pipeline summary — completa el par DET+SND del full pipeline trace
    if DBG:GetInt() >= 3 and _dbgPass(npc) then
        local hgN    = _HG_NAME[hg] or tostring(hg)
        local ageStr = stashFrameDelta >= 0 and (stashFrameDelta .. "fr") or "-"
        print(string.format(
            "[ADS SND] f=%d  %s  hg=%d(%s)  path=%-12s  age=%s  in=%.1f  final=%.1f",
            FrameNumber(), npc:GetClass(), hg, hgN,
            armorPath, ageStr, dmg_in, dmg_final))
    end
end)

ADS.LoadConfig()
dprint(1, string.format("config loaded: wl=%d bl=%d",table.Count(ADS.UserWhitelist),table.Count(ADS.UserBlacklist)))

util.AddNetworkString("ads_request_lists")
util.AddNetworkString("ads_send_lists")
util.AddNetworkString("ads_modify_list")
util.AddNetworkString("ads_inspect_result")
util.AddNetworkString("ads_admin_action")
util.AddNetworkString("ads_request_catalog_state")
util.AddNetworkString("ads_catalog_state")
util.AddNetworkString("ads_scan_world")
util.AddNetworkString("ads_scan_world_result")
util.AddNetworkString("ads_request_armor")
util.AddNetworkString("ads_armor_data")
util.AddNetworkString("ads_save_armor")
util.AddNetworkString("ads_save_armor_batch")
util.AddNetworkString("ads_tool_apply")
util.AddNetworkString("ads_tool_copy")
util.AddNetworkString("ads_tool_copy_result")
util.AddNetworkString("ads_request_weapons_data")
util.AddNetworkString("ads_weapons_data")
util.AddNetworkString("ads_save_curated")
util.AddNetworkString("ads_save_ammo_fallback")
util.AddNetworkString("ads_request_scav_weights")
util.AddNetworkString("ads_scav_weights_data")
util.AddNetworkString("ads_save_scav_weight")

local function GetAdmins()
    local t = {}
    for _, p in ipairs(player.GetAll()) do
        if IsValid(p) and p:IsAdmin() then t[#t+1] = p end
    end
    return t
end

local function SerializeLists()
    local json = util.TableToJSON({whitelist=ADS.UserWhitelist,blacklist=ADS.UserBlacklist})
    return util.Compress(json)
end

local function SendListsTo(ply)
    if not IsValid(ply) then return end
    local data = SerializeLists()
    net.Start("ads_send_lists")
    net.WriteUInt(#data, 32)
    net.WriteData(data, #data)
    net.Send(ply)
end

local function BroadcastListsToAdmins()
    -- Debounce: coalesce múltiples llamadas en 0.1s en un solo envío
    timer.Create("ads_broadcast_debounce", 0.1, 1, function()
        local admins = GetAdmins()
        if #admins == 0 then return end
        local data = SerializeLists()
        net.Start("ads_send_lists")
        net.WriteUInt(#data, 32)
        net.WriteData(data, #data)
        net.Send(admins)
    end)
end

ADS.SendListsTo = SendListsTo
ADS.BroadcastListsToAdmins = BroadcastListsToAdmins

net.Receive("ads_request_lists",function(_,ply) if IsValid(ply) then SendListsTo(ply) end end)

net.Receive("ads_modify_list",function(_,ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local action=net.ReadString()

    -- Acciones individuales (toolgun, compatibilidad hacia atrás)
    if action=="wl_add" then
        local classname=net.ReadString()
        local data=net.ReadTable()
        ADS.AddToWhitelist(classname,data)
    elseif action=="wl_del" then
        ADS.RemoveFromWhitelist(net.ReadString())
    elseif action=="bl_add" then
        ADS.AddToBlacklist(net.ReadString())
    elseif action=="bl_del" then
        ADS.RemoveFromBlacklist(net.ReadString())

    -- Acciones batch (browser masivo): una sola SaveConfig + broadcast al final
    elseif action=="wl_add_batch" then
        local payload=net.ReadTable()
        local classes=net.ReadTable()
        for _,class in ipairs(classes) do _WlAddNoSave(class,payload) end
        ADS.SaveConfig()
    elseif action=="bl_add_batch" then
        local classes=net.ReadTable()
        for _,class in ipairs(classes) do _BlAddNoSave(class) end
        ADS.SaveConfig()
    elseif action=="del_batch" then
        local classes=net.ReadTable()
        for _,class in ipairs(classes) do _WlDelNoSave(class) _BlDelNoSave(class) end
        ADS.SaveConfig()
    end

    BroadcastListsToAdmins()
end)

net.Receive("ads_admin_action",function(_,ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local action=net.ReadString()
    if action=="clear_wl" then ADS.ClearWhitelist()
    elseif action=="clear_bl" then ADS.ClearBlacklist()
    elseif action=="reload" then ADS.LoadConfig()
    elseif action=="save" then ADS.SaveConfig() end
    BroadcastListsToAdmins()
end)

net.Receive("ads_request_catalog_state", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local classnames = net.ReadTable()
    if type(classnames) ~= "table" then return end

    -- Filtrar a un orden limpio (el cliente solo manda strings, pero por las dudas).
    local list = {}
    for _, class in ipairs(classnames) do
        if type(class) == "string" and class ~= "" then
            list[#list + 1] = class
        end
    end

    -- Respuesta como array paralelo al orden recibido: NO se repiten los classnames
    -- ni las keys de tabla. net.WriteTable los repetía por entrada -> overflow.
    net.Start("ads_catalog_state")
    net.WriteUInt(#list, 16)
    for _, class in ipairs(list) do
        net.WriteString(ADS.GetClassStatus(class))
        net.WriteBool(ADS.ArmorProfiles[class] ~= nil)
    end
    net.Send(ply)
end)

net.Receive("ads_scan_world", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local seen = {}
    for _, e in ipairs(ents.GetAll()) do
        if IsValid(e) and e:IsNPC() then
            seen[e:GetClass()] = true
        end
    end
    local out = {}
    for class, _ in pairs(seen) do table.insert(out, class) end
    net.Start("ads_scan_world_result")
    net.WriteTable(out)
    net.Send(ply)
end)

net.Receive("ads_request_armor", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local classname = net.ReadString()
    if not classname or classname == "" then return end
    net.Start("ads_armor_data")
    net.WriteString(classname)
    net.WriteTable(ADS.ArmorProfiles[classname] or {})
    net.Send(ply)
end)

net.Receive("ads_save_armor", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local classname = net.ReadString()
    local raw       = net.ReadTable()
    if not classname or classname == "" then return end

    local clean = SanitizeArmor(raw)
    ADS.ArmorProfiles[classname] = clean  -- nil borra el perfil de la clase
    ADS.SaveConfig()

    -- Re-init NWvars en instancias vivas de esa clase
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent:IsNPC() and ent:GetClass() == classname then
            ADS.InitArmorNWvars(ent)
        end
    end

    -- ACK: devolver perfil sanitizado para que el editor refresque
    net.Start("ads_armor_data")
    net.WriteString(classname)
    net.WriteTable(ADS.ArmorProfiles[classname] or {})
    net.Send(ply)
end)

-- Aplica el mismo perfil de armadura a un lote de clases en un solo SaveConfig.
-- Profile vacío ({}) -> SanitizeArmor devuelve nil -> borra armadura en todas las clases.
net.Receive("ads_save_armor_batch", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local classes = net.ReadTable()
    local raw     = net.ReadTable()
    if type(classes) ~= "table" or #classes == 0 then return end

    local clean = SanitizeArmor(raw)   -- nil si perfil vacío (borra armadura)
    for _, classname in ipairs(classes) do
        if type(classname) == "string" and classname ~= "" then
            ADS.ArmorProfiles[classname] = clean
        end
    end
    ADS.SaveConfig()

    -- Re-init NWvars en instancias vivas de las clases modificadas
    local classSet = {}
    for _, classname in ipairs(classes) do classSet[classname] = true end
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent:IsNPC() and classSet[ent:GetClass()] then
            ADS.InitArmorNWvars(ent)
        end
    end
end)

-- ── Debug toolgun: aplicar armadura/limbs per-entity (efímero, sin JSON) ────
net.Receive("ads_tool_apply", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local ent     = net.ReadEntity()
    local doArmor = net.ReadBool()
    local doLimbs = net.ReadBool()
    local profile = net.ReadTable()
    local hf      = net.ReadFloat()
    local af      = net.ReadFloat()
    local lf      = net.ReadFloat()
    if not IsValid(ent) or not ent:IsNPC() then return end
    if doArmor then
        if ADS.ApplyArmorDirect then ADS.ApplyArmorDirect(ent, profile) end
        ent.ADS_ToolArmorOverride = true
    end
    if doLimbs then
        if ADS.ResizeLimbPools then ADS.ResizeLimbPools(ent, hf, af, lf) end
    end
    local armorStr = doArmor and "armor applied" or "armor skipped"
    local limbStr  = doLimbs and "limbs resized" or "limbs skipped"
    ply:SendLua(string.format(
        "notification.AddLegacy('ADS: NPC updated (%s, %s)', NOTIFY_GENERIC, 4) surface.PlaySound('buttons/button14.wav')",
        armorStr, limbStr))
end)

-- ── Debug toolgun: leer armadura+limbs de un NPC vivo y devolver al cliente ──
net.Receive("ads_tool_copy", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local ent = net.ReadEntity()
    if not IsValid(ent) or not ent:IsNPC() then return end
    -- Leer NWvars de armadura
    local profile = {}
    if ent:GetNWBool("ADS_Armor_Init", false) then
        local zones = {}
        for hg = 1, 7 do
            local cls = ent:GetNWInt("ADS_Armor_Class_" .. hg, 0)
            if cls > 0 then
                zones[tostring(hg)] = {
                    class    = cls,
                    dur_max  = ent:GetNWInt("ADS_Armor_MaxDur_" .. hg, 0),
                    material = ent:GetNWString("ADS_Armor_Mat_" .. hg, "aramid"),
                }
            end
        end
        if next(zones) then profile.zones = zones end
        local gcls = ent:GetNWInt("ADS_Armor_Class_0", 0)
        if gcls > 0 then
            profile.fallback_generic = {
                class    = gcls,
                dur_max  = ent:GetNWInt("ADS_Armor_MaxDur_0", 0),
                material = ent:GetNWString("ADS_Armor_Mat_0", "aramid"),
            }
        end
    end
    -- Reconstruir fracs de limbs desde ADS_SpawnHP
    local hf, af, lf = 0.5, 0.5, 0.5
    local spawnHP = ent.ADS_SpawnHP
    if spawnHP and spawnHP > 0 and ent.ADS_HP_HeadMax then
        hf = math.Round(ent.ADS_HP_HeadMax / spawnHP, 2)
        af = math.Round(ent.ADS_HP_ArmLMax / spawnHP, 2)
        lf = math.Round(ent.ADS_HP_LegLMax / spawnHP, 2)
    end
    net.Start("ads_tool_copy_result")
    net.WriteTable(profile)
    net.WriteFloat(hf)
    net.WriteFloat(af)
    net.WriteFloat(lf)
    net.Send(ply)
end)

-- ── Weapons tab (ADS Configuration) — curated weapon penetration + ammo fallback ──

local function SendWeaponsDataTo(ply)
    if not IsValid(ply) then return end
    net.Start("ads_weapons_data")
    net.WriteTable(ADS.CuratedWeapons or {})
    net.WriteTable(ADS.AmmoFallback or {})
    net.Send(ply)
end

net.Receive("ads_request_weapons_data", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    SendWeaponsDataTo(ply)
end)

net.Receive("ads_save_curated", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local classname = net.ReadString()
    local raw       = net.ReadTable()
    if not classname or classname == "" then return end

    local clean = ADS.SanitizeCuratedWeapon and ADS.SanitizeCuratedWeapon(raw) or nil
    ADS.CuratedWeapons[classname] = clean  -- nil borra la entrada
    ADS.SaveConfig()
    SendWeaponsDataTo(ply)
end)

net.Receive("ads_save_ammo_fallback", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local raw = net.ReadTable()

    if ADS.SanitizeAmmoFallback then
        ADS.AmmoFallback = ADS.SanitizeAmmoFallback(raw)
    end
    ADS.SaveConfig()
    SendWeaponsDataTo(ply)
end)

-- ARC9 compatibility: disable arc9_mod_bodydamagecancel because it inflates
-- limb damage to NPCs ~32x and conflicts with ADS zonal damage handling.
-- Detection is generic via the global ARC9 table, so it works regardless of
-- which Workshop upload of ARC9 the server uses.
CreateConVar("ads_arc9_compat", "1", FCVAR_ARCHIVE,
    "Auto-disable arc9_mod_bodydamagecancel when ARC9 is detected (recommended)")

hook.Add("InitPostEntity", "ADS_ARC9_Compat", function()
    if not GetConVar("ads_arc9_compat"):GetBool() then return end
    if not istable(ARC9) then return end

    -- Shim 1: disable bodydamagecancel (inflates limb damage ~32x vs NPCs)
    local cv = GetConVar("arc9_mod_bodydamagecancel")
    if not cv then
        print("[ADS] ARC9 detected but arc9_mod_bodydamagecancel cvar not found, skipping compat shim")
        return
    end
    if cv:GetInt() ~= 0 then
        cv:SetInt(0)
        print("[ADS] ARC9 detected: forced arc9_mod_bodydamagecancel to 0 (limb damage compat)")
    end

    -- Shim 2: detour AfterShotFunction to roll armor pre-call and stash the
    -- result on the entity. ScaleNPCDamage consumes the stash (see above).
    -- We cannot hook post-line-846 (no official hook exists), and the
    -- Hook_BulletImpact observational hook is overwritten by line 846 anyway.
    local baseSwep = weapons.GetStored("arc9_base")
    if not baseSwep then
        print("[ADS] arc9_base not found, armor detour skipped")
        return
    end
    local origASF = baseSwep.AfterShotFunction
    if not origASF then
        print("[ADS] arc9_base.AfterShotFunction not found, armor detour skipped")
        return
    end

    baseSwep.AfterShotFunction = function(self, tr, dmg, range, penleft, alreadypenned, secondary)
        local ent = tr and tr.Entity
        if IsValid(ent) and ent:IsNPC()
            and ADS.GetZone and ADS.ExtractBulletData and ADS.ResolveArmor
            and ADS.IsArmored and ADS.IsArmored(ent)
        then
            local zona = ADS.GetZone(ent, tr.HitGroup)
            if zona and bit.band(dmg:GetDamageType(), BLOCKABLE) ~= 0 then
                local tuple = ADS.ExtractBulletData(self, dmg)
                tuple.damage = 1.0  -- normalize: res.fleshDmg becomes a pure factor
                local res = ADS.ResolveArmor(zona, tuple, tr.HitGroup)
                -- Tier 3: clasificar sobreescritura de stash antes de depositar (race detection)
                local _sv = "NEW"
                if DBG:GetInt() >= 3 and _dbgPass(ent) then
                    local prev = ent.ADS_ArmorStash
                    if prev then
                        _sv = (FrameNumber() - prev.frame == 0) and "OVERWRITE!" or "replace-stale"
                    end
                end
                ent.ADS_ArmorStash = {
                    factor     = res.fleshDmg,
                    newDur     = res.newDur,
                    durKey     = zona.durKey,
                    material   = zona.material,   -- lo consume PlayArmorSounds (clang por material)
                    frame      = FrameNumber(),
                    -- debug fields (consumed by ScaleNPCDamage trace only)
                    penetra    = (res.factorPenleft > 0),
                    armorClass = zona.clase,
                    durBefore  = zona.durActual,
                    penPower   = tuple.penPower,
                    src        = tuple.source,
                }
                -- Tier 3: log DET (deposito en detour)
                if DBG:GetInt() >= 3 and _dbgPass(ent) then
                    local hgN    = _HG_NAME[tr.HitGroup] or tostring(tr.HitGroup)
                    local penIn  = type(penleft) == "number" and string.format("%.2f", penleft) or tostring(penleft)
                    local penRes = res.factorPenleft == 0 and "STOP" or string.format("PEN(%.2f)", res.factorPenleft)
                    print(string.format(
                        "[ADS DET] f=%d  %s  hg=%d(%s)  alreadypen=%-5s  sec=%-5s  penleft=%s->%s  raw=%.2f",
                        FrameNumber(), ent:GetClass(), tr.HitGroup, hgN,
                        tostring(alreadypenned), tostring(secondary), penIn, penRes, dmg:GetDamage()))
                    print(string.format(
                        "          zona=cls%d/%s  factor=%.4f  penPow=%.0f  src=%s  stash=%s",
                        zona.clase, tostring(zona.durKey), res.fleshDmg,
                        tuple.penPower or 0, tuple.source or "-", _sv))
                end
                if res.factorPenleft == 0 then
                    penleft = 0  -- round stopped by plate; Penetrate exits at penleft<=0 guard
                end
            end
        end
        return origASF(self, tr, dmg, range, penleft, alreadypenned, secondary)
    end

    print("[ADS] ARC9 AfterShotFunction armor detour installed")
end)