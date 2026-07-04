# ADS 2.0 — Bloques A / B / C — Prompts Claude Code

**Orden de ejecución: CC-Core → CC-Browser → CC-Limbs → CC-Armor → CC-Config**

Cada sección es un prompt independiente para Claude Code sobre un archivo.
Pegar el prompt completo de cada sección; aplicar en orden.

---

## CC-Core — `lua/autorun/server/ads_core.lua`

### Cambio 1: Extender `ADS.InspectNPC` (línea ~424)

Reemplazar la función completa:

```
old_str:
function ADS.InspectNPC(ent)
    if not IsValid(ent) then return nil end
    local i={classname=ent:GetClass(),is_vj=ent.IsVJBaseSNPC==true,vj_class=nil,
             armor=(ent:IsPlayer() and ent:Armor() or 0),is_armored=ADS.IsArmored(ent),reason=ADS.GetArmorReason(ent),
             override=ADS.GetOverride(ent:GetClass())}
    if i.is_vj then
        local v=ent.VJ_NPC_Class
        if type(v)=="table" then i.vj_class=table.concat(v,", ")
        elseif type(v)=="string" then i.vj_class=v end
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
```

```
new_str:
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
```

---

### Cambio 2: Agregar 3 net strings al bloque existente (línea ~704)

```
old_str:
util.AddNetworkString("ads_save_armor_batch")
```

```
new_str:
util.AddNetworkString("ads_save_armor_batch")
util.AddNetworkString("ads_tool_apply")
util.AddNetworkString("ads_tool_copy")
util.AddNetworkString("ads_tool_copy_result")
```

---

### Cambio 3: Agregar dos net.Receive del toolgun al final del archivo (antes del `hook.Add("InitPostEntity"...)`)

```
old_str:
-- ARC9 compatibility: disable arc9_mod_bodydamagecancel because it inflates
```

```
new_str:
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

-- ARC9 compatibility: disable arc9_mod_bodydamagecancel because it inflates
```

---

## CC-Browser — `lua/autorun/client/cl_ads_browser.lua`

### Cambio 1: Reemplazar `durSlider` (DNumSlider → fila manual) en el zone editor

```
old_str:
    -- Durability slider
    local durSlider = vgui.Create("DNumSlider", editorPanel)
    durSlider:Dock(TOP)
    durSlider:SetTall(30)
    durSlider:DockMargin(0, 2, 0, 0)
    durSlider:SetText("Dur Max")
    durSlider:SetMin(10)
    durSlider:SetMax(250)
    durSlider:SetDecimals(0)
    durSlider:SetValue(ZONE_DEFAULTS.dur_max)
```

```
new_str:
    -- Durability row: fila manual (DNumSlider colapsa en DScrollPanel con SetTall fijo)
    local DUR_MIN, DUR_MAX = 10, 250
    local durRow = vgui.Create("DPanel", editorPanel)
    durRow:Dock(TOP)
    durRow:SetTall(20)
    durRow:DockMargin(0, 2, 0, 0)
    durRow.Paint = function() end

    local durLabel = vgui.Create("DLabel", durRow)
    durLabel:Dock(LEFT)
    durLabel:SetWide(52)
    durLabel:SetText("Dur Max")
    durLabel:SetFont("DermaDefault")

    local durEntry = vgui.Create("DTextEntry", durRow)
    durEntry:Dock(RIGHT)
    durEntry:SetWide(36)
    durEntry:SetNumeric(true)

    local durSlider = vgui.Create("DSlider", durRow)
    durSlider:Dock(FILL)

    local durUpdating = false
    local function durSetValue(v)
        v = math.Clamp(math.floor(v), DUR_MIN, DUR_MAX)
        durUpdating = true
        durSlider:SetSlideX((v - DUR_MIN) / (DUR_MAX - DUR_MIN))
        durEntry:SetText(tostring(v))
        durUpdating = false
    end
    durSetValue(ZONE_DEFAULTS.dur_max)
```

---

### Cambio 2: Actualizar `setControlsEnabled` para incluir `durEntry`

```
old_str:
    local function setControlsEnabled(en)
        for _, b in ipairs(classBtns) do b:SetEnabled(en) end
        matCombo:SetEnabled(en)
        durSlider:SetEnabled(en)
        clsInfoBtn:SetEnabled(en)
        matInfoBtn:SetEnabled(en)
    end
```

```
new_str:
    local function setControlsEnabled(en)
        for _, b in ipairs(classBtns) do b:SetEnabled(en) end
        matCombo:SetEnabled(en)
        durSlider:SetEnabled(en)
        durEntry:SetEnabled(en)
        clsInfoBtn:SetEnabled(en)
        matInfoBtn:SetEnabled(en)
    end
```

---

### Cambio 3: Actualizar `setEditor` — reemplazar `durSlider:SetValue` por `durSetValue`

```
old_str:
        if z then
            matCombo:SetValue(MAT_DISPLAY[z.material] or z.material
                              or MAT_DISPLAY[ZONE_DEFAULTS.material])
            durSlider:SetValue(z.dur_max or ZONE_DEFAULTS.dur_max)
        else
            matCombo:SetValue(MAT_DISPLAY[ZONE_DEFAULTS.material])
            durSlider:SetValue(ZONE_DEFAULTS.dur_max)
        end
        refreshing = false
    end
```

```
new_str:
        if z then
            matCombo:SetValue(MAT_DISPLAY[z.material] or z.material
                              or MAT_DISPLAY[ZONE_DEFAULTS.material])
            durSetValue(z.dur_max or ZONE_DEFAULTS.dur_max)
        else
            matCombo:SetValue(MAT_DISPLAY[ZONE_DEFAULTS.material])
            durSetValue(ZONE_DEFAULTS.dur_max)
        end
        refreshing = false
    end
```

---

### Cambio 4: Reemplazar `durSlider.OnValueChanged` y agregar handlers de `durEntry`

```
old_str:
    durSlider.OnValueChanged = function(_, v)
        if refreshing then return end
        local profile = ADS_Browser.ArmorEditor.profile
        if profile.zones and profile.zones[selectedZone] then
            profile.zones[selectedZone].dur_max = math.floor(v)
            markDirty()
            silPanel:InvalidateLayout(true)
        end
    end
```

```
new_str:
    durSlider.OnValueChanged = function(_, x)
        if refreshing or durUpdating then return end
        local v = math.floor(DUR_MIN + x * (DUR_MAX - DUR_MIN))
        durUpdating = true
        durEntry:SetText(tostring(v))
        durUpdating = false
        local profile = ADS_Browser.ArmorEditor.profile
        if profile.zones and profile.zones[selectedZone] then
            profile.zones[selectedZone].dur_max = v
            markDirty()
            silPanel:InvalidateLayout(true)
        end
    end

    durEntry.OnEnter = function(self)
        if refreshing then return end
        local v = math.Clamp(tonumber(self:GetText()) or DUR_MIN, DUR_MIN, DUR_MAX)
        durSetValue(v)
        local profile = ADS_Browser.ArmorEditor.profile
        if profile.zones and profile.zones[selectedZone] then
            profile.zones[selectedZone].dur_max = v
            markDirty()
            silPanel:InvalidateLayout(true)
        end
    end
    durEntry.OnLostFocus = durEntry.OnEnter
```

---

### Cambio 5: Reemplazar `fgDurSlider` (DNumSlider → fila manual) en el bloque fallback

```
old_str:
    local fgDurSlider = vgui.Create("DNumSlider", fgPanel)
    fgDurSlider:Dock(TOP)
    fgDurSlider:SetTall(30)
    fgDurSlider:DockMargin(0, 2, 0, 0)
    fgDurSlider:SetText("Dur Max")
    fgDurSlider:SetMin(10)
    fgDurSlider:SetMax(250)
    fgDurSlider:SetDecimals(0)
    fgDurSlider:SetValue(ZONE_DEFAULTS.dur_max)
```

```
new_str:
    -- Durability row fallback: misma fila manual que la zona (DUR_MIN/DUR_MAX ya definidos)
    local fgDurRow = vgui.Create("DPanel", fgPanel)
    fgDurRow:Dock(TOP)
    fgDurRow:SetTall(20)
    fgDurRow:DockMargin(0, 2, 0, 0)
    fgDurRow.Paint = function() end

    local fgDurLabel = vgui.Create("DLabel", fgDurRow)
    fgDurLabel:Dock(LEFT)
    fgDurLabel:SetWide(52)
    fgDurLabel:SetText("Dur Max")
    fgDurLabel:SetFont("DermaDefault")

    local fgDurEntry = vgui.Create("DTextEntry", fgDurRow)
    fgDurEntry:Dock(RIGHT)
    fgDurEntry:SetWide(36)
    fgDurEntry:SetNumeric(true)

    local fgDurSlider = vgui.Create("DSlider", fgDurRow)
    fgDurSlider:Dock(FILL)

    local fgDurUpdating = false
    local function fgDurSetValue(v)
        v = math.Clamp(math.floor(v), DUR_MIN, DUR_MAX)
        fgDurUpdating = true
        fgDurSlider:SetSlideX((v - DUR_MIN) / (DUR_MAX - DUR_MIN))
        fgDurEntry:SetText(tostring(v))
        fgDurUpdating = false
    end
    fgDurSetValue(ZONE_DEFAULTS.dur_max)
```

---

### Cambio 6: Actualizar `setFGEnabled` para incluir `fgDurEntry`

```
old_str:
    local function setFGEnabled(en)
        for _, b in ipairs(fgClassBtns) do b:SetEnabled(en) end
        fgMatCombo:SetEnabled(en)
        fgDurSlider:SetEnabled(en)
    end
```

```
new_str:
    local function setFGEnabled(en)
        for _, b in ipairs(fgClassBtns) do b:SetEnabled(en) end
        fgMatCombo:SetEnabled(en)
        fgDurSlider:SetEnabled(en)
        fgDurEntry:SetEnabled(en)
    end
```

---

### Cambio 7: Actualizar `fgCB.OnChange` — `fgDurSlider:SetValue` → `fgDurSetValue`

```
old_str:
            fgMatCombo:SetValue(MAT_DISPLAY[ZONE_DEFAULTS.material])
            fgDurSlider:SetValue(ZONE_DEFAULTS.dur_max)
        else
            profile.fallback_generic = nil
        end
        markDirty()
    end
```

```
new_str:
            fgMatCombo:SetValue(MAT_DISPLAY[ZONE_DEFAULTS.material])
            fgDurSetValue(ZONE_DEFAULTS.dur_max)
        else
            profile.fallback_generic = nil
        end
        markDirty()
    end
```

---

### Cambio 8: Reemplazar `fgDurSlider.OnValueChanged` y agregar handlers de `fgDurEntry`

```
old_str:
    fgDurSlider.OnValueChanged = function(_, v)
        if refreshing then return end
        local profile = ADS_Browser.ArmorEditor.profile
        if profile.fallback_generic then
            profile.fallback_generic.dur_max = math.floor(v)
            markDirty()
        end
    end
```

```
new_str:
    fgDurSlider.OnValueChanged = function(_, x)
        if refreshing or fgDurUpdating then return end
        local v = math.floor(DUR_MIN + x * (DUR_MAX - DUR_MIN))
        fgDurUpdating = true
        fgDurEntry:SetText(tostring(v))
        fgDurUpdating = false
        local profile = ADS_Browser.ArmorEditor.profile
        if profile.fallback_generic then
            profile.fallback_generic.dur_max = v
            markDirty()
        end
    end

    fgDurEntry.OnEnter = function(self)
        if refreshing then return end
        local v = math.Clamp(tonumber(self:GetText()) or DUR_MIN, DUR_MIN, DUR_MAX)
        fgDurSetValue(v)
        local profile = ADS_Browser.ArmorEditor.profile
        if profile.fallback_generic then
            profile.fallback_generic.dur_max = v
            markDirty()
        end
    end
    fgDurEntry.OnLostFocus = fgDurEntry.OnEnter
```

---

### Cambio 9: Actualizar `ArmorEditorRefresh` — dos llamadas `durSlider:SetValue` y dos `fgDurSlider:SetValue`

```
old_str:
            if z then
                matCombo:SetValue(MAT_DISPLAY[z.material] or z.material
                                  or MAT_DISPLAY[ZONE_DEFAULTS.material])
                durSlider:SetValue(z.dur_max or ZONE_DEFAULTS.dur_max)
            else
                matCombo:SetValue(MAT_DISPLAY[ZONE_DEFAULTS.material])
                durSlider:SetValue(ZONE_DEFAULTS.dur_max)
            end
```

```
new_str:
            if z then
                matCombo:SetValue(MAT_DISPLAY[z.material] or z.material
                                  or MAT_DISPLAY[ZONE_DEFAULTS.material])
                durSetValue(z.dur_max or ZONE_DEFAULTS.dur_max)
            else
                matCombo:SetValue(MAT_DISPLAY[ZONE_DEFAULTS.material])
                durSetValue(ZONE_DEFAULTS.dur_max)
            end
```

```
old_str:
            if fg then
                fgMatCombo:SetValue(MAT_DISPLAY[fg.material] or fg.material
                                    or MAT_DISPLAY[ZONE_DEFAULTS.material])
                fgDurSlider:SetValue(fg.dur_max or ZONE_DEFAULTS.dur_max)
            else
                fgMatCombo:SetValue(MAT_DISPLAY[ZONE_DEFAULTS.material])
                fgDurSlider:SetValue(ZONE_DEFAULTS.dur_max)
            end
```

```
new_str:
            if fg then
                fgMatCombo:SetValue(MAT_DISPLAY[fg.material] or fg.material
                                    or MAT_DISPLAY[ZONE_DEFAULTS.material])
                fgDurSetValue(fg.dur_max or ZONE_DEFAULTS.dur_max)
            else
                fgMatCombo:SetValue(MAT_DISPLAY[ZONE_DEFAULTS.material])
                fgDurSetValue(ZONE_DEFAULTS.dur_max)
            end
```

---

### Cambio 10: Rename — título del frame y concommand

```
old_str:
    f:SetTitle("ADS NPC Browser")
```

```
new_str:
    f:SetTitle("ADS Configuration")
```

```
old_str:
concommand.Add("ads_browser", function() ADS_Browser.Open() end)
```

```
new_str:
concommand.Add("ads_browser",    function() ADS_Browser.Open() end)  -- alias de compatibilidad
concommand.Add("ads_config_ui",  function() ADS_Browser.Open() end)
```

---

## CC-Limbs — `lua/autorun/server/ads_limbs.lua`

### Cambio 1: Guardar SpawnHP en `InitLimbs`

```
old_str:
    local hp = npc:Health()
    if hp <= 0 then return end

    local override = ADS.GetOverride and ADS.GetOverride(npc:GetClass())
```

```
new_str:
    local hp = npc:Health()
    if hp <= 0 then return end
    npc.ADS_SpawnHP = hp  -- guardado para reconstruir fracs en toolgun M2 y ResizeLimbPools

    local override = ADS.GetOverride and ADS.GetOverride(npc:GetClass())
```

---

### Cambio 2: Agregar `ADS.ResizeLimbPools` justo después de `ADS.HealLimbs`

Buscar el final de la función `ADS.HealLimbs` (termina en la línea que tiene `ApplyLimbDebuffs(npc, "heal")`) y agregar después:

```
old_str:
function ADS.ProcessLimbHit(npc, hitgroup, dmginfo)
```

```
new_str:
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
```

---

## CC-Armor — `lua/autorun/server/ads_armor.lua`

### Cambio único: Agregar `ADS.ApplyArmorDirect` justo antes del bloque de auto-test

```
old_str:
-- ── Auto-test (uncomment in server console to verify math) ───────────────────
```

```
new_str:
-- Aplica un perfil de armadura directamente a las NWvars de la entidad sin consultar
-- ArmorProfiles (que es config por clase). Usado por el toolgun debug para armadura
-- per-entity efímera. Formato de profile idéntico a InitArmorNWvars.
function ADS.ApplyArmorDirect(ent, profile)
    if not IsValid(ent) then return end
    -- Limpiar todos los slots primero (igual que InitArmorNWvars)
    for hg = 0, 7 do
        ent:SetNWInt("ADS_Armor_Class_"  .. hg, 0)
        ent:SetNWInt("ADS_Armor_Dur_"    .. hg, 0)
        ent:SetNWInt("ADS_Armor_MaxDur_" .. hg, 0)
        ent:SetNWString("ADS_Armor_Mat_" .. hg, "")
    end
    if type(profile) ~= "table" or not next(profile) then
        ent:SetNWBool("ADS_Armor_Init", false)
        return
    end
    if type(profile.zones) == "table" then
        for k, z in pairs(profile.zones) do
            local hg = tonumber(k)
            if hg and type(z) == "table" and tonumber(z.class) and tonumber(z.dur_max) then
                ent:SetNWInt("ADS_Armor_Class_"  .. hg, z.class)
                ent:SetNWInt("ADS_Armor_Dur_"    .. hg, z.dur_max)
                ent:SetNWInt("ADS_Armor_MaxDur_" .. hg, z.dur_max)
                ent:SetNWString("ADS_Armor_Mat_" .. hg, z.material or "aramid")
            end
        end
    end
    local fg = profile.fallback_generic
    if type(fg) == "table" and tonumber(fg.class) and tonumber(fg.dur_max)
       and ent:GetNWInt("ADS_Armor_Class_0", 0) == 0 then
        ent:SetNWInt("ADS_Armor_Class_0",  fg.class)
        ent:SetNWInt("ADS_Armor_Dur_0",    fg.dur_max)
        ent:SetNWInt("ADS_Armor_MaxDur_0", fg.dur_max)
        ent:SetNWString("ADS_Armor_Mat_0", fg.material or "aramid")
    end
    ent:SetNWBool("ADS_Armor_Init", true)
    dprint(2, "[ADS] ApplyArmorDirect", ent:GetClass())
end

-- ── Auto-test (uncomment in server console to verify math) ───────────────────
```

---

## CC-Config — `lua/weapons/gmod_tool/stools/ads_config.lua`

**Este prompt reemplaza el archivo casi completo. Aplicar después de los otros cuatro.**

### Cambio 1: Reemplazar `TOOL.ClientConVar` y language strings

```
old_str:
TOOL.ClientConVar={
    armor_min="50", armor_max="80",
    red_min="15",   red_max="80",
    coverage="head_torso",
    mult_head="1.0", mult_chest="1.0", mult_arm="1.0", mult_leg="1.0",
    limbs_head_frac="0.5", limbs_arms_frac="0.5", limbs_legs_frac="0.5",
    limbs_damage_transfer_head="1.5", limbs_damage_transfer_arms="0.7", limbs_damage_transfer_legs="0.7",
}

if CLIENT then
    language.Add("tool.ads_config.name","ADS Config")
    language.Add("tool.ads_config.desc","Manage which NPCs carry armor and damage multipliers")
    language.Add("tool.ads_config.0","Left: whitelist NPC with slider values | Right: toggle blacklist | Reload: inspect NPC")
end
```

```
new_str:
TOOL.ClientConVar={
    apply_armor      = "1",
    apply_limbs      = "1",
    limb_head_frac   = "0.5",
    limb_arms_frac   = "0.5",
    limb_legs_frac   = "0.5",
}

if CLIENT then
    language.Add("tool.ads_config.name","ADS Debug")
    language.Add("tool.ads_config.desc","Apply ephemeral armor/limbs to NPCs for testing. Does not save to JSON.")
    language.Add("tool.ads_config.0","Left: Apply to NPC  |  Right: Copy from NPC  |  Reload: Inspect")
end
```

---

### Cambio 2: Reemplazar `TOOL:LeftClick`

```
old_str:
function TOOL:LeftClick(tr)
    local e,ply=Validate(self,tr)
    if not e then return false end
    if CLIENT then return true end
    local class=e:GetClass()
    local data={
        armor_min=self:GetClientNumber("armor_min",50),
        armor_max=self:GetClientNumber("armor_max",80),
        red_min=self:GetClientNumber("red_min",15),
        red_max=self:GetClientNumber("red_max",80),
        coverage=self:GetClientInfo("coverage"),
        head_hp_frac=self:GetClientNumber("limbs_head_frac",0.5),
        arms_hp_frac=self:GetClientNumber("limbs_arms_frac",0.5),
        legs_hp_frac=self:GetClientNumber("limbs_legs_frac",0.5),
        limb_damage_transfer_head=self:GetClientNumber("limbs_damage_transfer_head",1.5),
        limb_damage_transfer_arms=self:GetClientNumber("limbs_damage_transfer_arms",0.7),
        limb_damage_transfer_legs=self:GetClientNumber("limbs_damage_transfer_legs",0.7),
        dmg_mult={
            head=self:GetClientNumber("mult_head",1.0),
            chest=self:GetClientNumber("mult_chest",1.0),
            arm=self:GetClientNumber("mult_arm",1.0),
            leg=self:GetClientNumber("mult_leg",1.0),
        },
    }
    ADS.AddToWhitelist(class,data)
    Notify(ply,"ADS: whitelist set - "..class,false)
    ADS.SendListsTo(ply)
    return true
end
```

```
new_str:
function TOOL:LeftClick(tr)
    local e,ply=Validate(self,tr)
    if not e then return false end
    if CLIENT then
        -- El cliente envía el perfil completo; el servidor lo aplica via net.Receive("ads_tool_apply")
        net.Start("ads_tool_apply")
        net.WriteEntity(e)
        net.WriteBool(GetConVar("ads_config_apply_armor"):GetBool())
        net.WriteBool(GetConVar("ads_config_apply_limbs"):GetBool())
        net.WriteTable(toolState and toolState.armor or {})
        net.WriteFloat(GetConVar("ads_config_limb_head_frac"):GetFloat())
        net.WriteFloat(GetConVar("ads_config_limb_arms_frac"):GetFloat())
        net.WriteFloat(GetConVar("ads_config_limb_legs_frac"):GetFloat())
        net.SendToServer()
        return true
    end
    return true  -- servidor: manejado por net.Receive("ads_tool_apply") en ads_core.lua
end
```

---

### Cambio 3: Reemplazar `TOOL:RightClick`

```
old_str:
function TOOL:RightClick(tr)
    local e,ply=Validate(self,tr)
    if not e then return false end
    if CLIENT then return true end
    local class=e:GetClass()
    if ADS.UserBlacklist[class] then
        ADS.RemoveFromBlacklist(class)
        Notify(ply,"ADS: removed from blacklist - "..class,false)
    else
        ADS.AddToBlacklist(class)
        Notify(ply,"ADS: added to blacklist - "..class,false)
    end
    ADS.SendListsTo(ply)
    return true
end
```

```
new_str:
function TOOL:RightClick(tr)
    local e,ply=Validate(self,tr)
    if not e then return false end
    if CLIENT then
        -- Solicita leer armadura+limbs del NPC; respuesta llega en ads_tool_copy_result
        net.Start("ads_tool_copy")
        net.WriteEntity(e)
        net.SendToServer()
        return true
    end
    return true  -- servidor: manejado por net.Receive("ads_tool_copy") en ads_core.lua
end
```

---

### Cambio 4: Reemplazar el bloque `if CLIENT then` completo (desde `if CLIENT then` hasta el final del archivo)

```
old_str:
if CLIENT then

local cached={whitelist={},blacklist={}}

net.Receive("ads_send_lists",function()
    local len = net.ReadUInt(32)
    local data = net.ReadData(len)
    local json = util.Decompress(data)
    cached = (json and util.JSONToTable(json)) or {whitelist={},blacklist={}}
    ADS = ADS or {}
    ADS.ClientLists = cached  -- cache global para otros componentes cliente
    hook.Run("ADS_ListsUpdated")
end)

net.Receive("ads_inspect_result",function()
    local info=net.ReadTable() if not info then return end
    notification.AddLegacy(string.format("ADS: %s | %s | armor=%s",
        info.classname or "?",
        info.is_armored and "ARMORED" or "not armored",
        tostring(info.armor or 0)),NOTIFY_GENERIC,6)
    surface.PlaySound("buttons/button14.wav")
    print("======== ADS NPC Inspect ========")
    print("classname  : "..tostring(info.classname))
    print("is_vj      : "..tostring(info.is_vj))
    print("vj_class   : "..tostring(info.vj_class))
    print("armor      : "..tostring(info.armor))
    print("is_armored : "..tostring(info.is_armored))
    print("reason     : "..tostring(info.reason))
    if info.override then
        print("override   :")
        for k,v in pairs(info.override) do
            if type(v)=="table" then
                print("  "..k.." :")
                for k2,v2 in pairs(v) do print("    "..k2.." = "..tostring(v2)) end
            else
                print("  "..k.." = "..tostring(v))
            end
        end
    else
        print("override   : (none, uses globals)")
    end
    if info.limbs then
        print("--- Limb HP ---")
        local order = {"head","arm_l","arm_r","leg_l","leg_r"}
        for _,k in ipairs(order) do
            local l = info.limbs[k]
            if l then
                print(string.format("  %-6s : %.1f / %.1f  (%.0f%%)", k, l.hp, l.max, l.ratio*100))
            end
        end
    end
    if info.scavenger then
        print("--- Scavenger ---")
        print("  can_scavenge       = " .. tostring(info.scavenger.can_scavenge))
        print(string.format("  cooldown_remaining = %.1fs", info.scavenger.cooldown_remaining or 0))
        print("  target_weapon      = " .. tostring(info.scavenger.target_weapon or "(none)"))
        print("  current_weapon     = " .. tostring(info.scavenger.current_weapon or "(none)"))
        if info.scavenger.current_weapon_weight then
            print(string.format("  weapon_weight      = %.2f", info.scavenger.current_weapon_weight))
        end
    end
    print("=================================")
end)

function TOOL.BuildCPanel(cp)
    cp:Help("ADS Config Tool")
    cp:Help("Left click: whitelist NPC with values below | Right: toggle blacklist | Reload: inspect")

    cp:Button("Open NPC Browser").DoClick = function()
        if ADS_Browser and ADS_Browser.Open then
            ADS_Browser.Open()
        else
            RunConsoleCommand("ads_browser")
        end
    end

    cp:Help("Armor values applied on Left Click")
    cp:NumSlider("Armor Min","ads_config_armor_min",0,100,0)
    cp:NumSlider("Armor Max","ads_config_armor_max",0,100,0)
    cp:NumSlider("Reduction Min %","ads_config_red_min",0,100,0)
    cp:NumSlider("Reduction Max %","ads_config_red_max",0,100,0)
    cp:Help("Coverage (zones that block damage)")
    local covCombo = vgui.Create("DComboBox", cp)
    covCombo:SetTall(22)
    local currentCov = GetConVar("ads_config_coverage") and GetConVar("ads_config_coverage"):GetString() or "head_torso"
    local coverageChoices = {
        {"Vest only","torso"},
        {"Helmet only","head"},
        {"Helmet + Vest (default)","head_torso"},
        {"Full body","full"},
    }
    for _, entry in ipairs(coverageChoices) do
        covCombo:AddChoice(entry[1], entry[2], entry[2] == currentCov)
    end
    covCombo.OnSelect = function(_, _, _, data)
        RunConsoleCommand("ads_config_coverage", data)
    end
    cp:AddItem(covCombo)

    cp:Help("Limb HP Overrides (per classname, applied on Left Click)")
    cp:NumSlider("Head HP fraction","ads_config_limbs_head_frac",0,2,2)
    cp:NumSlider("Arms HP fraction (per arm)","ads_config_limbs_arms_frac",0,2,2)
    cp:NumSlider("Legs HP fraction (per leg)","ads_config_limbs_legs_frac",0,2,2)
    cp:NumSlider("Head damage transfer","ads_config_limbs_damage_transfer_head",0,3,2)
    cp:NumSlider("Arms damage transfer","ads_config_limbs_damage_transfer_arms",0,3,2)
    cp:NumSlider("Legs damage transfer","ads_config_limbs_damage_transfer_legs",0,3,2)

    cp:Help("Damage multipliers applied on Left Click (1.0 = neutral, not saved)")
    cp:NumSlider("Head mult","ads_config_mult_head",0,5,2)
    cp:NumSlider("Chest mult","ads_config_mult_chest",0,5,2)
    cp:NumSlider("Arm mult","ads_config_mult_arm",0,5,2)
    cp:NumSlider("Leg mult","ads_config_mult_leg",0,5,2)

    cp:Help("User Lists")
    local list=vgui.Create("DListView",cp)
    list:SetMultiSelect(false)
    list:AddColumn("T"):SetFixedWidth(22)
    list:AddColumn("Classname")
    list:AddColumn("Armor"):SetFixedWidth(48)
    list:AddColumn("Red%"):SetFixedWidth(48)
    list:AddColumn("H/C/A/L"):SetFixedWidth(90)
    list:AddColumn("Cov"):SetFixedWidth(50)
    list:SetTall(260)
    cp:AddItem(list)

    local function fmtRange(a,b) if a and b then return a.."-"..b end return "-" end
    local function fmtMults(m)
        if not m then return "-" end
        local h=m.head  and string.format("%.1f",m.head)  or "1.0"
        local c=m.chest and string.format("%.1f",m.chest) or "1.0"
        local a=m.arm   and string.format("%.1f",m.arm)   or "1.0"
        local l=m.leg   and string.format("%.1f",m.leg)   or "1.0"
        return h.."/"..c.."/"..a.."/"..l
    end

    local COV_ABBR = {torso="T", head="H", head_torso="HT", full="F"}
    local function Refresh()
        list:Clear()
        for c,d in pairs(cached.whitelist or {}) do
            local hasData = type(d)=="table" and next(d)~=nil
            if hasData then
                list:AddLine("WL", c,
                    fmtRange(d.armor_min, d.armor_max),
                    fmtRange(d.red_min, d.red_max),
                    fmtMults(d.dmg_mult),
                    COV_ABBR[d.coverage or "head_torso"] or "HT")
            else
                list:AddLine("WL", c, "-", "-", "-", "HT")
            end
        end
        for c,_ in pairs(cached.blacklist or {}) do
            list:AddLine("BL", c, "", "", "", "")
        end
    end
    hook.Add("ADS_ListsUpdated","ADS_Panel_"..tostring(list),Refresh)

    cp:Button("Reset Tool Sliders to Default").DoClick=function()
        RunConsoleCommand("ads_config_armor_min","50")
        RunConsoleCommand("ads_config_armor_max","80")
        RunConsoleCommand("ads_config_red_min","15")
        RunConsoleCommand("ads_config_red_max","80")
        RunConsoleCommand("ads_config_coverage","head_torso")
        RunConsoleCommand("ads_config_limbs_head_frac","0.5")
        RunConsoleCommand("ads_config_limbs_arms_frac","0.5")
        RunConsoleCommand("ads_config_limbs_legs_frac","0.5")
        RunConsoleCommand("ads_config_limbs_damage_transfer_head","1.5")
        RunConsoleCommand("ads_config_limbs_damage_transfer_arms","0.7")
        RunConsoleCommand("ads_config_limbs_damage_transfer_legs","0.7")
        RunConsoleCommand("ads_config_mult_head","1.0")
        RunConsoleCommand("ads_config_mult_chest","1.0")
        RunConsoleCommand("ads_config_mult_arm","1.0")
        RunConsoleCommand("ads_config_mult_leg","1.0")
    end

    cp:Button("Refresh from Server").DoClick=function()
        net.Start("ads_request_lists") net.SendToServer()
    end

    cp:Button("Remove Selected").DoClick=function()
        local ln=list:GetSelectedLine() if not ln then return end
        local row=list:GetLine(ln) if not row then return end
        local typ,class=row:GetValue(1),row:GetValue(2)
        net.Start("ads_modify_list")
        net.WriteString(typ=="WL" and "wl_del" or "bl_del")
        net.WriteString(class)
        net.SendToServer()
    end

    cp:Button("Clear Whitelist").DoClick=function()
        Derma_Query("Clear user whitelist?","ADS","Yes",function()
            net.Start("ads_admin_action") net.WriteString("clear_wl") net.SendToServer()
        end,"No")
    end
    cp:Button("Clear Blacklist").DoClick=function()
        Derma_Query("Clear user blacklist?","ADS","Yes",function()
            net.Start("ads_admin_action") net.WriteString("clear_bl") net.SendToServer()
        end,"No")
    end
    cp:Button("Save Config").DoClick=function()
        net.Start("ads_admin_action") net.WriteString("save") net.SendToServer()
    end
    cp:Button("Reload Config from Disk").DoClick=function()
        net.Start("ads_admin_action") net.WriteString("reload") net.SendToServer()
    end

    net.Start("ads_request_lists") net.SendToServer()
    timer.Simple(0.2,Refresh)
end

end
```

```
new_str:
if CLIENT then

-- Estado local del toolgun: armadura a aplicar y zona seleccionada en el panel
local toolState = {
    armor        = {},   -- {zones={["1"]={class,dur_max,material},...}, fallback_generic={...}}
    selectedZone = "2",  -- hitgroup string; "2"=chest por defecto
}
local toolRefresh = nil  -- función asignada por BuildCPanel; llamada al recibir copy result

-- ── Listas (mantenidas para que ADS_ListsUpdated no rompa otros hooks) ───────
net.Receive("ads_send_lists", function()
    local len  = net.ReadUInt(32)
    local data = net.ReadData(len)
    local json = util.Decompress(data)
    local tbl  = (json and util.JSONToTable(json)) or {whitelist={}, blacklist={}}
    ADS = ADS or {}
    ADS.ClientLists = tbl
    hook.Run("ADS_ListsUpdated")
end)

-- ── Inspect (R) — notificación breve + dump completo en consola ───────────────
net.Receive("ads_inspect_result", function()
    local info = net.ReadTable()
    if not info then return end
    -- Notificación: Armored + Whitelisted únicamente
    local armedStr = info.is_armored and "ARMORED" or "not armored"
    local wlStr    = info.is_whitelisted and "WL:yes" or "WL:no"
    notification.AddLegacy(string.format("ADS: %s | %s | %s",
        info.classname or "?", armedStr, wlStr), NOTIFY_GENERIC, 6)
    surface.PlaySound("buttons/button14.wav")
    -- Dump completo a consola
    print("======== ADS NPC Inspect ========")
    print("classname      : " .. tostring(info.classname))
    print("is_vj          : " .. tostring(info.is_vj))
    print("vj_class       : " .. tostring(info.vj_class))
    print("is_armored     : " .. tostring(info.is_armored))
    print("is_whitelisted : " .. tostring(info.is_whitelisted))
    print("reason         : " .. tostring(info.reason))
    if info.override then
        print("override       :")
        for k, v in pairs(info.override) do
            if type(v) == "table" then
                print("  " .. k .. " :")
                for k2, v2 in pairs(v) do print("    " .. k2 .. " = " .. tostring(v2)) end
            else
                print("  " .. k .. " = " .. tostring(v))
            end
        end
    else
        print("override       : (none, uses globals)")
    end
    if info.armor_slots then
        print("--- Armor Slots ---")
        if info.tool_override then print("  [MANUAL OVERRIDE ACTIVE]") end
        local ZONE_NAMES = {["0"]="Generic",["1"]="Head",["2"]="Chest",["3"]="Stomach",
                            ["4"]="L.Arm",["5"]="R.Arm",["6"]="L.Leg",["7"]="R.Leg"}
        for _, hg in ipairs({"0","1","2","3","4","5","6","7"}) do
            local s = info.armor_slots[hg]
            if s then
                print(string.format("  slot %-2s %-10s : cls=%d  dur=%d/%d  mat=%s",
                    hg, "(" .. (ZONE_NAMES[hg] or hg) .. ")",
                    s.class, s.dur, s.dur_max, s.material))
            end
        end
    else
        print("armor_slots    : (not initialized)")
    end
    if info.limbs then
        print("--- Limb HP ---")
        for _, k in ipairs({"head","arm_l","arm_r","leg_l","leg_r"}) do
            local l = info.limbs[k]
            if l then
                print(string.format("  %-6s : %.1f / %.1f  (%.0f%%)", k, l.hp, l.max, l.ratio * 100))
            end
        end
    end
    if info.scavenger then
        print("--- Scavenger ---")
        print("  can_scavenge       = " .. tostring(info.scavenger.can_scavenge))
        print(string.format("  cooldown_remaining = %.1fs", info.scavenger.cooldown_remaining or 0))
        print("  target_weapon      = " .. tostring(info.scavenger.target_weapon or "(none)"))
        print("  current_weapon     = " .. tostring(info.scavenger.current_weapon or "(none)"))
        if info.scavenger.current_weapon_weight then
            print(string.format("  weapon_weight      = %.2f", info.scavenger.current_weapon_weight))
        end
    end
    print("=================================")
end)

-- ── Copy result (M2) — popula toolState y refresca el panel ──────────────────
net.Receive("ads_tool_copy_result", function()
    local armor = net.ReadTable()
    local hf    = net.ReadFloat()
    local af    = net.ReadFloat()
    local lf    = net.ReadFloat()
    toolState.armor = armor or {}
    if toolRefresh then toolRefresh(hf, af, lf) end
    notification.AddLegacy("ADS: Copied from NPC", NOTIFY_GENERIC, 3)
    surface.PlaySound("buttons/button14.wav")
end)

-- ── BuildCPanel ───────────────────────────────────────────────────────────────
function TOOL.BuildCPanel(cp)
    local MAT_LIST    = {"aramid","titanium","ceramic","poly_ceramic",
                         "nano_titanium","electrified_aramid","m_stf","uranium_matrix"}
    local MAT_DISPLAY = {
        aramid             = "Aramid",
        titanium           = "Titanium",
        ceramic            = "Ceramic",
        poly_ceramic       = "Poly-Ceramic",
        nano_titanium      = "Nano-Titanium",
        electrified_aramid = "Elec. Aramid",
        m_stf              = "M-STF",
        uranium_matrix     = "Uranium Matrix",
    }
    local ZONE_DEFAULTS = {class = 3, dur_max = 80, material = "aramid"}
    local ZONE_OPTIONS  = {
        {"1","HEAD (1)"}, {"2","CHEST (2)"}, {"3","STOMACH (3)"},
        {"4","L. ARM (4)"}, {"5","R. ARM (5)"}, {"6","L. LEG (6)"}, {"7","R. LEG (7)"},
    }
    local DUR_MIN, DUR_MAX = 10, 250

    cp:Help("ADS Debug Tool  (admin only)")
    cp:Help("Left: Apply to NPC  |  Right: Copy from NPC  |  Reload: Inspect")

    cp:Button("Open Configuration").DoClick = function()
        if ADS_Browser and ADS_Browser.Open then ADS_Browser.Open()
        else RunConsoleCommand("ads_browser") end
    end

    -- Gate checkboxes
    cp:CheckBox("Apply Armor on Left Click",  "ads_config_apply_armor")
    cp:CheckBox("Apply Limbs on Left Click",  "ads_config_apply_limbs")

    -- ── ARMOR ────────────────────────────────────────────────────────────────
    cp:Help("Armor  (per-entity, ephemeral — not saved to JSON)")

    -- Zone selector
    local zoneSelRow = vgui.Create("DPanel", cp)
    zoneSelRow:SetTall(24)
    zoneSelRow.Paint = function() end
    local zoneSelLabel = vgui.Create("DLabel", zoneSelRow)
    zoneSelLabel:Dock(LEFT)
    zoneSelLabel:SetWide(38)
    zoneSelLabel:SetText("Zone:")
    zoneSelLabel:SetFont("DermaDefault")
    local zoneCombo = vgui.Create("DComboBox", zoneSelRow)
    zoneCombo:Dock(FILL)
    for _, opt in ipairs(ZONE_OPTIONS) do
        zoneCombo:AddChoice(opt[2], opt[1], opt[1] == toolState.selectedZone)
    end
    cp:AddItem(zoneSelRow)

    -- Armored checkbox
    local zoneCB = vgui.Create("DCheckBoxLabel", cp)
    zoneCB:SetTall(20)
    zoneCB:SetText("Armored")
    zoneCB:SetValue(false)
    cp:AddItem(zoneCB)

    -- Class buttons
    local clsRow = vgui.Create("DPanel", cp)
    clsRow:SetTall(26)
    clsRow:DockMargin(0, 2, 0, 2)
    clsRow.Paint = function() end
    local clsLabel = vgui.Create("DLabel", clsRow)
    clsLabel:Dock(LEFT)
    clsLabel:SetWide(38)
    clsLabel:SetText("Class:")
    clsLabel:SetFont("DermaDefault")
    local classBtns     = {}
    local clsContainer  = vgui.Create("DPanel", clsRow)
    clsContainer:Dock(FILL)
    clsContainer.Paint = function() end
    clsContainer.PerformLayout = function(self, w, h)
        local bw = math.floor(w / 8)
        for i, btn in ipairs(classBtns) do
            btn:SetPos((i - 1) * bw, 0)
            btn:SetSize(bw - 1, h)
        end
    end
    for i = 1, 8 do
        local btn = vgui.Create("DButton", clsContainer)
        btn:SetText(tostring(i))
        btn:SetFont("DermaDefault")
        classBtns[i] = btn
    end
    cp:AddItem(clsRow)

    -- Material
    local matRow = vgui.Create("DPanel", cp)
    matRow:SetTall(24)
    matRow:DockMargin(0, 2, 0, 2)
    matRow.Paint = function() end
    local matLabel = vgui.Create("DLabel", matRow)
    matLabel:Dock(LEFT)
    matLabel:SetWide(52)
    matLabel:SetText("Material:")
    matLabel:SetFont("DermaDefault")
    local matCombo = vgui.Create("DComboBox", matRow)
    matCombo:Dock(FILL)
    for _, mat in ipairs(MAT_LIST) do
        matCombo:AddChoice(MAT_DISPLAY[mat] or mat, mat, mat == ZONE_DEFAULTS.material)
    end
    cp:AddItem(matRow)

    -- Dur Max — fila manual (misma solución que el browser tras el fix)
    local durRow = vgui.Create("DPanel", cp)
    durRow:SetTall(20)
    durRow:DockMargin(0, 2, 0, 2)
    durRow.Paint = function() end
    local durLabel = vgui.Create("DLabel", durRow)
    durLabel:Dock(LEFT)
    durLabel:SetWide(52)
    durLabel:SetText("Dur Max")
    durLabel:SetFont("DermaDefault")
    local durEntry = vgui.Create("DTextEntry", durRow)
    durEntry:Dock(RIGHT)
    durEntry:SetWide(36)
    durEntry:SetNumeric(true)
    local durSlider = vgui.Create("DSlider", durRow)
    durSlider:Dock(FILL)
    local durUpdating  = false
    local toolRefreshing = false
    local function durSetValue(v)
        v = math.Clamp(math.floor(v), DUR_MIN, DUR_MAX)
        durUpdating = true
        durSlider:SetSlideX((v - DUR_MIN) / (DUR_MAX - DUR_MIN))
        durEntry:SetText(tostring(v))
        durUpdating = false
    end
    durSetValue(ZONE_DEFAULTS.dur_max)
    cp:AddItem(durRow)

    -- Enable/disable zone controls
    local function setZoneControlsEnabled(en)
        for _, b in ipairs(classBtns) do b:SetEnabled(en) end
        matCombo:SetEnabled(en)
        durSlider:SetEnabled(en)
        durEntry:SetEnabled(en)
    end
    setZoneControlsEnabled(false)

    -- Carga datos de una zona en los controles
    local function loadZone(hgKey)
        toolRefreshing = true
        local zones   = type(toolState.armor.zones) == "table" and toolState.armor.zones or {}
        local z       = zones[hgKey]
        zoneCB:SetValue(z ~= nil)
        setZoneControlsEnabled(z ~= nil)
        local activeCls = z and (z.class or ZONE_DEFAULTS.class) or ZONE_DEFAULTS.class
        for i, btn in ipairs(classBtns) do
            local active = (i == activeCls)
            btn:SetFont(active and "DermaDefaultBold" or "DermaDefault")
            btn:SetTextColor(active and Color(255, 255, 255) or Color(180, 180, 180))
        end
        if z then
            matCombo:SetValue(MAT_DISPLAY[z.material] or z.material or MAT_DISPLAY[ZONE_DEFAULTS.material])
            durSetValue(z.dur_max or ZONE_DEFAULTS.dur_max)
        else
            matCombo:SetValue(MAT_DISPLAY[ZONE_DEFAULTS.material])
            durSetValue(ZONE_DEFAULTS.dur_max)
        end
        toolRefreshing = false
    end

    -- Wire zone combo
    zoneCombo.OnSelect = function(_, _, _, data)
        toolState.selectedZone = data
        loadZone(data)
    end

    -- Wire armored checkbox
    zoneCB.OnChange = function(_, val)
        if toolRefreshing then return end
        toolState.armor.zones = toolState.armor.zones or {}
        if val then
            toolState.armor.zones[toolState.selectedZone] = {
                class = ZONE_DEFAULTS.class, dur_max = ZONE_DEFAULTS.dur_max, material = ZONE_DEFAULTS.material,
            }
            setZoneControlsEnabled(true)
            loadZone(toolState.selectedZone)
        else
            toolState.armor.zones[toolState.selectedZone] = nil
            if not next(toolState.armor.zones) then toolState.armor.zones = nil end
            setZoneControlsEnabled(false)
        end
    end

    -- Wire class buttons
    for i, btn in ipairs(classBtns) do
        btn.DoClick = function()
            if toolRefreshing then return end
            local zones = toolState.armor.zones
            if zones and zones[toolState.selectedZone] then
                zones[toolState.selectedZone].class = i
                for j, b in ipairs(classBtns) do
                    b:SetFont(j == i and "DermaDefaultBold" or "DermaDefault")
                    b:SetTextColor(j == i and Color(255, 255, 255) or Color(180, 180, 180))
                end
            end
        end
    end

    -- Wire material combo
    matCombo.OnSelect = function(_, _, _, data)
        if toolRefreshing then return end
        local zones = toolState.armor.zones
        if zones and zones[toolState.selectedZone] then
            zones[toolState.selectedZone].material = data
        end
    end

    -- Wire dur slider
    durSlider.OnValueChanged = function(_, x)
        if toolRefreshing or durUpdating then return end
        local v = math.floor(DUR_MIN + x * (DUR_MAX - DUR_MIN))
        durUpdating = true
        durEntry:SetText(tostring(v))
        durUpdating = false
        local zones = toolState.armor.zones
        if zones and zones[toolState.selectedZone] then
            zones[toolState.selectedZone].dur_max = v
        end
    end

    -- Wire dur entry
    durEntry.OnEnter = function(self)
        if toolRefreshing then return end
        local v = math.Clamp(tonumber(self:GetText()) or DUR_MIN, DUR_MIN, DUR_MAX)
        durSetValue(v)
        local zones = toolState.armor.zones
        if zones and zones[toolState.selectedZone] then
            zones[toolState.selectedZone].dur_max = v
        end
    end
    durEntry.OnLostFocus = durEntry.OnEnter

    -- ── Separator ─────────────────────────────────────────────────────────────
    local sep = vgui.Create("DPanel", cp)
    sep:SetTall(6)
    sep.Paint = function(self, w, h)
        surface.SetDrawColor(70, 70, 70)
        surface.DrawRect(0, 3, w, 1)
    end
    cp:AddItem(sep)

    -- ── Fallback Generic ──────────────────────────────────────────────────────
    local fgCB = vgui.Create("DCheckBoxLabel", cp)
    fgCB:SetTall(20)
    fgCB:SetText("Fallback / GENERIC  (non-humanoid or unmatched hitgroups)")
    fgCB:SetValue(false)
    cp:AddItem(fgCB)

    local fgClassBtns    = {}
    local fgClsRow       = vgui.Create("DPanel", cp)
    fgClsRow:SetTall(26)
    fgClsRow:DockMargin(0, 2, 0, 2)
    fgClsRow.Paint = function() end
    local fgClsLabel = vgui.Create("DLabel", fgClsRow)
    fgClsLabel:Dock(LEFT)
    fgClsLabel:SetWide(38)
    fgClsLabel:SetText("Class:")
    fgClsLabel:SetFont("DermaDefault")
    local fgContainer = vgui.Create("DPanel", fgClsRow)
    fgContainer:Dock(FILL)
    fgContainer.Paint = function() end
    fgContainer.PerformLayout = function(self, w, h)
        local bw = math.floor(w / 8)
        for i, btn in ipairs(fgClassBtns) do
            btn:SetPos((i - 1) * bw, 0)
            btn:SetSize(bw - 1, h)
        end
    end
    for i = 1, 8 do
        local btn = vgui.Create("DButton", fgContainer)
        btn:SetText(tostring(i))
        btn:SetFont("DermaDefault")
        fgClassBtns[i] = btn
    end
    cp:AddItem(fgClsRow)

    local fgMatRow = vgui.Create("DPanel", cp)
    fgMatRow:SetTall(24)
    fgMatRow:DockMargin(0, 2, 0, 2)
    fgMatRow.Paint = function() end
    local fgMatLabel = vgui.Create("DLabel", fgMatRow)
    fgMatLabel:Dock(LEFT)
    fgMatLabel:SetWide(52)
    fgMatLabel:SetText("Material:")
    fgMatLabel:SetFont("DermaDefault")
    local fgMatCombo = vgui.Create("DComboBox", fgMatRow)
    fgMatCombo:Dock(FILL)
    for _, mat in ipairs(MAT_LIST) do
        fgMatCombo:AddChoice(MAT_DISPLAY[mat] or mat, mat, mat == ZONE_DEFAULTS.material)
    end
    cp:AddItem(fgMatRow)

    local fgDurRow = vgui.Create("DPanel", cp)
    fgDurRow:SetTall(20)
    fgDurRow:DockMargin(0, 2, 0, 2)
    fgDurRow.Paint = function() end
    local fgDurLabel = vgui.Create("DLabel", fgDurRow)
    fgDurLabel:Dock(LEFT)
    fgDurLabel:SetWide(52)
    fgDurLabel:SetText("Dur Max")
    fgDurLabel:SetFont("DermaDefault")
    local fgDurEntry = vgui.Create("DTextEntry", fgDurRow)
    fgDurEntry:Dock(RIGHT)
    fgDurEntry:SetWide(36)
    fgDurEntry:SetNumeric(true)
    local fgDurSlider = vgui.Create("DSlider", fgDurRow)
    fgDurSlider:Dock(FILL)
    local fgDurUpdating = false
    local function fgDurSetValue(v)
        v = math.Clamp(math.floor(v), DUR_MIN, DUR_MAX)
        fgDurUpdating = true
        fgDurSlider:SetSlideX((v - DUR_MIN) / (DUR_MAX - DUR_MIN))
        fgDurEntry:SetText(tostring(v))
        fgDurUpdating = false
    end
    fgDurSetValue(ZONE_DEFAULTS.dur_max)
    cp:AddItem(fgDurRow)

    local function setFGEnabled(en)
        for _, b in ipairs(fgClassBtns) do b:SetEnabled(en) end
        fgMatCombo:SetEnabled(en)
        fgDurSlider:SetEnabled(en)
        fgDurEntry:SetEnabled(en)
    end
    setFGEnabled(false)

    fgCB.OnChange = function(_, val)
        if toolRefreshing then return end
        setFGEnabled(val)
        if val then
            toolState.armor.fallback_generic = {
                class = ZONE_DEFAULTS.class, dur_max = ZONE_DEFAULTS.dur_max, material = ZONE_DEFAULTS.material,
            }
            for j, b in ipairs(fgClassBtns) do
                b:SetFont(j == ZONE_DEFAULTS.class and "DermaDefaultBold" or "DermaDefault")
                b:SetTextColor(j == ZONE_DEFAULTS.class and Color(255, 255, 255) or Color(180, 180, 180))
            end
            fgMatCombo:SetValue(MAT_DISPLAY[ZONE_DEFAULTS.material])
            fgDurSetValue(ZONE_DEFAULTS.dur_max)
        else
            toolState.armor.fallback_generic = nil
        end
    end

    for i, btn in ipairs(fgClassBtns) do
        btn.DoClick = function()
            if toolRefreshing then return end
            if toolState.armor.fallback_generic then
                toolState.armor.fallback_generic.class = i
                for j, b in ipairs(fgClassBtns) do
                    b:SetFont(j == i and "DermaDefaultBold" or "DermaDefault")
                    b:SetTextColor(j == i and Color(255, 255, 255) or Color(180, 180, 180))
                end
            end
        end
    end

    fgMatCombo.OnSelect = function(_, _, _, data)
        if toolRefreshing then return end
        if toolState.armor.fallback_generic then
            toolState.armor.fallback_generic.material = data
        end
    end

    fgDurSlider.OnValueChanged = function(_, x)
        if toolRefreshing or fgDurUpdating then return end
        local v = math.floor(DUR_MIN + x * (DUR_MAX - DUR_MIN))
        fgDurUpdating = true
        fgDurEntry:SetText(tostring(v))
        fgDurUpdating = false
        if toolState.armor.fallback_generic then
            toolState.armor.fallback_generic.dur_max = v
        end
    end

    fgDurEntry.OnEnter = function(self)
        if toolRefreshing then return end
        local v = math.Clamp(tonumber(self:GetText()) or DUR_MIN, DUR_MIN, DUR_MAX)
        fgDurSetValue(v)
        if toolState.armor.fallback_generic then
            toolState.armor.fallback_generic.dur_max = v
        end
    end
    fgDurEntry.OnLostFocus = fgDurEntry.OnEnter

    -- ── LIMBS ─────────────────────────────────────────────────────────────────
    cp:Help("Limbs  (pool resize per-entity, current set to max on apply)")
    cp:NumSlider("Head HP frac",  "ads_config_limb_head_frac", 0, 2, 2)
    cp:NumSlider("Arms HP frac",  "ads_config_limb_arms_frac", 0, 2, 2)
    cp:NumSlider("Legs HP frac",  "ads_config_limb_legs_frac", 0, 2, 2)

    -- Reset
    cp:Button("Reset to defaults").DoClick = function()
        RunConsoleCommand("ads_config_limb_head_frac", "0.5")
        RunConsoleCommand("ads_config_limb_arms_frac", "0.5")
        RunConsoleCommand("ads_config_limb_legs_frac", "0.5")
        toolState.armor        = {}
        toolState.selectedZone = "2"
        toolRefreshing = true
        zoneCB:SetValue(false)
        setZoneControlsEnabled(false)
        durSetValue(ZONE_DEFAULTS.dur_max)
        matCombo:SetValue(MAT_DISPLAY[ZONE_DEFAULTS.material])
        fgCB:SetValue(false)
        setFGEnabled(false)
        fgDurSetValue(ZONE_DEFAULTS.dur_max)
        fgMatCombo:SetValue(MAT_DISPLAY[ZONE_DEFAULTS.material])
        toolRefreshing = false
    end

    -- Callback para net.Receive("ads_tool_copy_result")
    toolRefresh = function(hf, af, lf)
        -- Actualizar fracs (convars)
        RunConsoleCommand("ads_config_limb_head_frac", tostring(math.Round(hf, 2)))
        RunConsoleCommand("ads_config_limb_arms_frac", tostring(math.Round(af, 2)))
        RunConsoleCommand("ads_config_limb_legs_frac", tostring(math.Round(lf, 2)))
        -- Refrescar zona actual
        loadZone(toolState.selectedZone)
        -- Refrescar fallback
        toolRefreshing = true
        local fg = toolState.armor.fallback_generic
        fgCB:SetValue(fg ~= nil)
        setFGEnabled(fg ~= nil)
        if fg then
            local fgCls = fg.class or ZONE_DEFAULTS.class
            for j, b in ipairs(fgClassBtns) do
                b:SetFont(j == fgCls and "DermaDefaultBold" or "DermaDefault")
                b:SetTextColor(j == fgCls and Color(255, 255, 255) or Color(180, 180, 180))
            end
            fgMatCombo:SetValue(MAT_DISPLAY[fg.material] or fg.material or MAT_DISPLAY[ZONE_DEFAULTS.material])
            fgDurSetValue(fg.dur_max or ZONE_DEFAULTS.dur_max)
        else
            fgMatCombo:SetValue(MAT_DISPLAY[ZONE_DEFAULTS.material])
            fgDurSetValue(ZONE_DEFAULTS.dur_max)
        end
        toolRefreshing = false
    end

    -- Estado inicial del panel
    loadZone(toolState.selectedZone)
end

end
```

---

## Notas de implementación

- **Orden obligatorio:** CC-Core → CC-Browser → CC-Limbs → CC-Armor → CC-Config.
- **CC-Core Cambio 3** usa la línea `-- ARC9 compatibility:` como ancla; asegurarse que el bloque de net.Receive quede antes de ese comentario.
- **CC-Browser Cambio 1** define `DUR_MIN, DUR_MAX` en el bloque de la zona. El bloque fallback (Cambio 5) reutiliza esas variables porque están en el mismo scope de `BuildArmorTab`.
- **CC-Config**: el `toolRefresh` que `net.Receive("ads_tool_copy_result")` llama se asigna dentro de `BuildCPanel`. Si el panel no está abierto cuando llega el resultado, `toolRefresh` es nil y el guard `if toolRefresh then` lo ignora silenciosamente.
- **Volatilidad del override**: si `InitArmorNWvars` se re-dispara (respawn de NPC), el override de armadura se borra. `ent.ADS_ToolArmorOverride` también se borra. El Reload (R) mostrará `[MANUAL OVERRIDE ACTIVE]` mientras el override esté activo.
- **Convars viejas** (`ads_config_armor_min`, `ads_config_coverage`, `ads_config_mult_*`, etc.) quedan huérfanas en GMod pero no causan errores. Si molestan, se pueden borrar manualmente del archivo `cfg/`.
