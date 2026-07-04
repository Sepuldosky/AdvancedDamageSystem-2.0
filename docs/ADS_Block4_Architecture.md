# ADS 2.0 — Block 4: Adiciones al documento de arquitectura

> Instrucciones de integración: este archivo documenta los cambios a añadir en
> `ADS_2_0_Architecture.md`. Copiar la sección §14 al final del doc (antes del pie),
> y aplicar los diffs de §13 indicados abajo.

---

## Cambios a §13

### Tabla de estado — reemplazar fila Block 4

```
| **Block 4** | UI browser: net de armor, editor de zonas, reemplazo right panel 1.x | 🔲 Pendiente |
```

### §7 (probe de hitgroups) — mover de "Fase 1" a "Fase 2"

En la lista de Fase 1, borrar:
```
- Cache de hitgroups por modelo (oportunista al spawn, persistido).
```

En "Fase 2 (backlog)", añadir:
```
- **Probe de hitgroups (§7):** spawn temporal + GetHitBoxHitGroup por modelo no
  cacheado; grisa zonas imposibles en la silueta del browser. Diferido porque la
  silueta de template humano fijo es funcional sin él (zonas sin impacto son dato
  muerto, costo cero en runtime).
```

---

## §14. Block 4 — Browser UI 2.0

### Alcance y archivos

Block 4 reemplaza la UI del right panel del browser y cablea el plumbing net de armor que la alimenta. **No toca el damage path.**

| Archivo | Cambios |
|---|---|
| `ads_core.lua` (server) | 4 net strings nuevos, `SanitizeArmor`, payload de `catalog_state`, cleanup de `Sanitize` WL |
| `cl_ads_browser.lua` (client) | `DPropertySheet` 2 tabs, Tab Armor completo, Tab Limbs/WL reescrito a campos 2.0 |
| `ads_armor.lua` | Sin cambios |

**§7 probe de hitgroups: diferido a Fase 2.** La silueta usa template humano fijo de 7 zonas. Una zona definida que el modelo no puede recibir es dato muerto sin costo de runtime (el resolver lee `trace.HitGroup` en vivo).

---

### 4a — ads_core.lua (server)

#### Net strings nuevos

Añadir junto al bloque existente de `util.AddNetworkString`:

```lua
util.AddNetworkString("ads_request_armor")  -- cliente solicita perfil de una clase
util.AddNetworkString("ads_armor_data")     -- server envía perfil (request + ACK de save)
util.AddNetworkString("ads_save_armor")     -- cliente envía perfil editado para persistir
```

#### SanitizeArmor(profile) → tabla limpia o nil

Nueva función local en `ads_core.lua`, misma zona que `Sanitize`. Espeja su patrón de validación.

```lua
local function SanitizeArmor(profile)
    if type(profile) ~= "table" then return nil end
    local out = {}

    -- Zonas (hitgroups "1".."7")
    if type(profile.zones) == "table" then
        local zones = {}
        for hg = 1, 7 do
            local key = tostring(hg)
            local z = profile.zones[key]
            if type(z) == "table" then
                local cls = math.floor(math.Clamp(tonumber(z.class)   or 3,   1, 8))
                local dur = math.floor(math.Clamp(tonumber(z.dur_max) or 80,  1, 200))
                local mat = (type(z.material) == "string" and ADS.Materials[z.material])
                            and z.material or "aramid"
                zones[key] = { class = cls, dur_max = dur, material = mat }
            end
        end
        if next(zones) then out.zones = zones end
    end

    -- Fallback generic
    if type(profile.fallback_generic) == "table" then
        local fg = profile.fallback_generic
        local cls = math.floor(math.Clamp(tonumber(fg.class)   or 3,   1, 8))
        local dur = math.floor(math.Clamp(tonumber(fg.dur_max) or 80,  1, 200))
        local mat = (type(fg.material) == "string" and ADS.Materials[fg.material])
                    and fg.material or "aramid"
        out.fallback_generic = { class = cls, dur_max = dur, material = mat }
    end

    -- coverage_profile: metadato opaco de UI, max 64 chars
    if type(profile.coverage_profile) == "string" then
        out.coverage_profile = string.sub(profile.coverage_profile, 1, 64)
    end

    -- Perfil vacío = nil (server borrará el perfil de la clase)
    if not out.zones and not out.fallback_generic then return nil end
    return out
end
```

#### Handler ads_request_armor

```lua
net.Receive("ads_request_armor", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local classname = net.ReadString()
    if not classname or classname == "" then return end
    net.Start("ads_armor_data")
    net.WriteString(classname)
    net.WriteTable(ADS.ArmorProfiles[classname] or {})
    net.Send(ply)
end)
```

#### Handler ads_save_armor

```lua
net.Receive("ads_save_armor", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local classname = net.ReadString()
    local raw       = net.ReadTable()
    if not classname or classname == "" then return end

    local clean = SanitizeArmor(raw)
    ADS.ArmorProfiles[classname] = clean  -- nil borra el perfil
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
```

#### catalog_state — payload extendido

En el handler `ads_request_catalog_state`, cambiar la construcción de `out`:

```lua
-- ANTES:
out[class] = ADS.GetClassStatus(class)

-- AHORA:
out[class] = {
    status  = ADS.GetClassStatus(class),
    armored = (ADS.ArmorProfiles[class] ~= nil),
}
```

El perfil completo no va en `catalog_state` (evita inflar el payload). Viaja on-demand por `ads_armor_data`.

#### Sanitize WL — borrar campos 1.x muertos

En la función `Sanitize` (líneas ~163-195), eliminar:

- La constante `VALID_COVERAGE` en línea 161 (`local VALID_COVERAGE = {...}`)
- Las ramas de `armor_min`, `armor_max`, `red_min`, `red_max` (líneas 166-169)
- La rama de `coverage` + uso de `VALID_COVERAGE` (líneas 171-173)
- Los swaps de min/max (líneas 174-175)

**Permanecen sin cambio:** `*_hp_frac`, `limb_damage_transfer_*`, `dmg_mult`. Esos ya están y son los únicos campos 2.0 de la whitelist.

---

### 4b — cl_ads_browser.lua (client)

#### ADS_Browser.Armored — nueva tabla de estado

Junto a las declaraciones existentes de `ADS_Browser.*`:

```lua
ADS_Browser.Armored = {}   -- { [classname] = bool }
```

Limpiar en `f.OnRemove` junto al resto de estado.

#### catalog_state — lectura actualizada

El `net.Receive("ads_catalog_state")` actual asigna `ADS_Browser.State = t` directamente.
Reemplazar por:

```lua
net.Receive("ads_catalog_state", function()
    local t = net.ReadTable() or {}
    dprint("catalog_state received | entries=", table.Count(t))
    for class, entry in pairs(t) do
        if type(entry) == "table" then
            ADS_Browser.State[class]   = entry.status
            ADS_Browser.Armored[class] = entry.armored or false
        else
            -- compat si server no actualizado
            ADS_Browser.State[class] = tostring(entry)
        end
    end
    if IsValid(ADS_Browser.Frame) and IsValid(ADS_Browser.Scroll) then
        RenderCatalog(ADS_Browser.Scroll)
    end
end)
```

#### Columnas del row — reemplazo

**En el header `colHeader` (PaintOver del DPanel de columnas):**

Borrar las columnas `Armor / Red% / H/C/A/L / Cov`.
Reemplazar por columna `Arm` a posición ~425:

```lua
local cols = {
    { x = 32,  label = "Name" },
    { x = 210, label = "Classname" },
    { x = 390, label = "St" },
    { x = 425, label = "Arm" },
    { x = 470, label = "H/C/A/L" },
}
```

**En el `PaintOver` de cada row (`BuildRow`):**

Borrar el bloque `if self.status == "wl_user" then ... end` que pinta `armor_min/armor_max/red_min/red_max/coverage`.

Reemplazar por:

```lua
-- Indicador de perfil de armadura
if ADS_Browser.Armored[self.data.class] then
    surface.SetFont("DermaDefaultBold")
    surface.SetTextColor(100, 180, 255, 255)
    surface.SetTextPos(425, 6)
    surface.DrawText("[ARM]")
end

-- dmg_mult sigue pintando (campo 2.0, ya existía)
if self.status == "wl_user" then
    local wl = ADS_Browser.Whitelist and ADS_Browser.Whitelist[self.data.class]
    if type(wl) == "table" and type(wl.dmg_mult) == "table" then
        local m = wl.dmg_mult
        local txt = string.format("%.1f/%.1f/%.1f/%.1f",
            m.head or 1.0, m.chest or 1.0, m.arm or 1.0, m.leg or 1.0)
        surface.SetFont("DermaDefault")
        surface.SetTextColor(200, 200, 200, 255)
        surface.SetTextPos(470, 6)
        surface.DrawText(txt)
    end
end
```

#### Right panel — reemplazo completo

`BuildRightPanel(parent)` se reescribe completa. Estructura:

```lua
local function BuildRightPanel(parent)
    local sheet = vgui.Create("DPropertySheet", parent)
    sheet:Dock(FILL)
    sheet:DockMargin(0, 0, 0, 0)

    local armorScroll = vgui.Create("DScrollPanel")
    local wlScroll    = vgui.Create("DScrollPanel")

    sheet:AddSheet("Armor",      armorScroll, nil, false, false)
    sheet:AddSheet("Limbs / WL", wlScroll,    nil, false, false)

    BuildArmorTab(armorScroll)
    BuildWLTab(wlScroll)
end
```

---

#### BuildArmorTab(parent)

##### Estado local del editor

Declarar junto a las demás tablas `ADS_Browser.*`:

```lua
ADS_Browser.ArmorEditor = {
    classname = nil,   -- clase actualmente cargada en el editor
    profile   = {},    -- copia local del perfil (igual que lo guardado en server)
    dirty     = false, -- hay cambios sin guardar
}
```

Limpiar en `f.OnRemove`.

##### Hitgroups expuestos

Tabla fija en orden visual, de arriba a abajo:

```lua
local ZONE_LIST = {
    { hg = 1, label = "HEAD"       },
    { hg = 2, label = "CHEST"      },
    { hg = 3, label = "STOMACH"    },
    { hg = 4, label = "LEFT ARM"   },
    { hg = 5, label = "RIGHT ARM"  },
    { hg = 6, label = "LEFT LEG"   },
    { hg = 7, label = "RIGHT LEG"  },
}
```

##### Abreviaturas de material (hardcoded en cliente)

```lua
local MAT_ABBR = {
    aramid             = "AR",
    titanium           = "TI",
    ceramic            = "CE",
    poly_ceramic       = "PC",
    nano_titanium      = "NT",
    electrified_aramid = "EA",
    m_stf              = "MS",
    uranium_matrix     = "UM",
}
```

Los 8 códigos son de 2 chars y no colisionan. No requieren sync server→cliente (ambos tienen la misma tabla de materiales hardcoded).

##### Defaults de zona nueva

```lua
local ZONE_DEFAULTS = { class = 3, dur_max = 80, material = "aramid" }
```

##### Layout de BuildArmorTab

```
[DLabel] "Select a single NPC to edit its armor profile."
[DHorizontalLayout o dos DPanel side-by-side]
  Izquierda (~130px): SilhouettePanel (paint custom)
  Derecha (FILL):     ZoneEditorPanel (scroll)
[DButton] "Save Profile"   (BOTTOM, habilitado solo si dirty y classname ~= nil)
[DButton] "Clear Profile"  (BOTTOM)
```

##### Silueta (SilhouettePanel)

Panel `DPanel` con función `Paint` custom. Dibuja silueta humana esquemática con `surface.DrawRect` y `surface.DrawLine`. No requiere asset externo. El color de relleno de cada región refleja si la zona está activa (checkbox en el editor) — azul claro si activa, gris si inactiva.

Anclas estáticas de labels por zona (coordenadas px sobre panel de ~130×220px,
ajustar en implementación según resultado visual):

```
HG 1 HEAD      → x=45,  y= 5   (cabeza, arriba)
HG 2 CHEST     → x=40,  y=55   (tórax, centro-alto)
HG 3 STOMACH   → x=40,  y=85   (abdomen, centro-bajo)
HG 4 LEFT ARM  → x= 5,  y=65   (brazo izq, lateral izquierdo)
HG 5 RIGHT ARM → x=85,  y=65   (brazo der, lateral derecho)
HG 6 LEFT LEG  → x=25,  y=145  (pierna izq)
HG 7 RIGHT LEG → x=65,  y=145  (pierna der)
```

Label por zona activa: `<ABR>·c<N>·<dur>`
Ejemplo: zona HEAD con aramid clase 4 dur_max 80 → `AR·c4·80`

Zona activa: texto en `Color(100, 200, 255)`.
Zona inactiva: texto en `Color(80, 80, 80)`.
`fallback_generic` activo: pequeño `FG·c<N>·<dur>` en esquina inferior del panel.

La silueta es read-only. No es clickeable para editar — la edición va en el panel derecho.

##### Editor de zonas (ZoneEditorPanel)

Scroll con un bloque por hitgroup (orden de `ZONE_LIST`), más un bloque final para `fallback_generic`.

Cada bloque de zona:

```
[DCheckBox "HEAD (hg 1)"]                    ← checkbox de cobertura
  [DNumSlider "Class"   min=1 max=8  dec=0]  ← habilitado solo si checkbox marcado
  [DNumSlider "Dur Max" min=1 max=200 dec=0]
  [DComboBox  Material  opciones = keys(ADS.Materials)]
```

El dropdown de material lista los 8 materiales con su nombre completo (no la abreviatura).

Al marcar el checkbox: si la zona no existía en el perfil → crea entrada con `ZONE_DEFAULTS`.
Al desmarcar: borra la entrada de `ADS_Browser.ArmorEditor.profile.zones[tostring(hg)]`.
Cualquier cambio de valor: actualiza `profile`, marca `dirty = true`, invalida la silueta.

Bloque `fallback_generic` al final del scroll, misma estructura de 3 controles, con label "Fallback / GENERIC".

##### net.Receive "ads_armor_data" (nuevo)

```lua
net.Receive("ads_armor_data", function()
    local classname = net.ReadString()
    local profile   = net.ReadTable() or {}
    ADS_Browser.ArmorEditor.classname = classname
    ADS_Browser.ArmorEditor.profile   = profile
    ADS_Browser.ArmorEditor.dirty     = false
    -- Señal para que el editor refresque sus controles (función definida en BuildArmorTab)
    if ADS_Browser.ArmorEditorRefresh then
        ADS_Browser.ArmorEditorRefresh()
    end
end)
```

`ADS_Browser.ArmorEditorRefresh` es función definida dentro de `BuildArmorTab` que recorre los controles y les asigna los valores actuales del perfil. Se sobreescribe cada vez que se reconstruye el tab.

##### Botones Save / Clear

**Save Profile:**
```lua
saveBtn.DoClick = function()
    local ed = ADS_Browser.ArmorEditor
    if not ed.classname then return end
    net.Start("ads_save_armor")
    net.WriteString(ed.classname)
    net.WriteTable(ed.profile)
    net.SendToServer()
    ed.dirty = false
    -- saveBtn:SetEnabled(false) hasta recibir ACK (ads_armor_data)
end
```

Habilitado solo si `ADS_Browser.ArmorEditor.dirty == true` y `classname ~= nil`.
Se re-habilita al recibir `ads_armor_data` con cambios pendientes.

**Clear Profile:**
```lua
clearBtn.DoClick = function()
    local classname = ADS_Browser.ArmorEditor.classname
    if not classname then return end
    net.Start("ads_save_armor")
    net.WriteString(classname)
    net.WriteTable({})   -- vacío → SanitizeArmor devuelve nil → perfil borrado
    net.SendToServer()
    ADS_Browser.ArmorEditor.profile = {}
    ADS_Browser.ArmorEditor.dirty   = false
    if ADS_Browser.ArmorEditorRefresh then ADS_Browser.ArmorEditorRefresh() end
end
```

##### Carga automática al seleccionar

En `ADS_Browser.UpdateSelectionCount` (o al final del handler de click de row), añadir:

```lua
local sel = {}
for c in pairs(ADS_Browser.Selected) do sel[#sel+1] = c end
if #sel == 1 and IsValid(ADS_Browser.Frame) then
    net.Start("ads_request_armor")
    net.WriteString(sel[1])
    net.SendToServer()
elseif IsValid(ADS_Browser.Frame) then
    -- 0 o más de 1 seleccionados → limpiar editor sin request
    ADS_Browser.ArmorEditor.classname = nil
    ADS_Browser.ArmorEditor.profile   = {}
    ADS_Browser.ArmorEditor.dirty     = false
    if ADS_Browser.ArmorEditorRefresh then ADS_Browser.ArmorEditorRefresh() end
end
```

---

#### BuildWLTab(parent)

Reescribir completo. Borra sliders y template 1.x. Construye sliders 2.0.

##### Template 2.0

Reemplazar la declaración de `ADS_Browser.Template` (líneas ~41-46):

```lua
ADS_Browser.Template = {
    head_hp_frac              = 0.30,
    arms_hp_frac              = 0.20,
    legs_hp_frac              = 0.20,
    limb_damage_transfer_head = 1.50,
    limb_damage_transfer_arms = 0.80,
    limb_damage_transfer_legs = 0.60,
    mult_head                 = 1.0,
    mult_chest                = 1.0,
    mult_arm                  = 1.0,
    mult_leg                  = 1.0,
}
```

##### Sliders del tab

```
-- Sección "Limb HP Pools"
Head HP Frac:   slider 0.0..2.0, 2dp  → head_hp_frac
Arms HP Frac:   slider 0.0..2.0, 2dp  → arms_hp_frac
Legs HP Frac:   slider 0.0..2.0, 2dp  → legs_hp_frac

-- Sección "Damage Transfer"
Head Transfer:  slider 0.0..3.0, 2dp  → limb_damage_transfer_head
Arms Transfer:  slider 0.0..3.0, 2dp  → limb_damage_transfer_arms
Legs Transfer:  slider 0.0..3.0, 2dp  → limb_damage_transfer_legs

-- Sección "Damage Multipliers"
Head mult:      slider 0.0..5.0, 2dp  → mult_head
Chest mult:     slider 0.0..5.0, 2dp  → mult_chest
Arm mult:       slider 0.0..5.0, 2dp  → mult_arm
Leg mult:       slider 0.0..5.0, 2dp  → mult_leg
```

Borrar: sliders `Armor Min`, `Armor Max`, `Reduction Min %`, `Reduction Max %`, dropdown `Coverage`.

##### Payload wl_add_batch (actualizado)

En el botón "Apply Whitelist Template":

```lua
local t = ADS_Browser.Template
local payload = {
    head_hp_frac              = t.head_hp_frac,
    arms_hp_frac              = t.arms_hp_frac,
    legs_hp_frac              = t.legs_hp_frac,
    limb_damage_transfer_head = t.limb_damage_transfer_head,
    limb_damage_transfer_arms = t.limb_damage_transfer_arms,
    limb_damage_transfer_legs = t.limb_damage_transfer_legs,
    dmg_mult = {
        head  = t.mult_head,
        chest = t.mult_chest,
        arm   = t.mult_arm,
        leg   = t.mult_leg,
    },
}
-- net.Start("ads_modify_list") ... (sin cambio estructural)
```

##### "Copy values from selected" (actualizado)

Borrar las líneas que leen `wl.armor_min/max`, `wl.red_min/max`, `wl.coverage`.
Añadir lectura de campos 2.0:

```lua
local wl = ADS_Browser.Whitelist and ADS_Browser.Whitelist[class]
if type(wl) ~= "table" then return end
local t = ADS_Browser.Template
if wl.head_hp_frac              then t.head_hp_frac              = wl.head_hp_frac              end
if wl.arms_hp_frac              then t.arms_hp_frac              = wl.arms_hp_frac              end
if wl.legs_hp_frac              then t.legs_hp_frac              = wl.legs_hp_frac              end
if wl.limb_damage_transfer_head then t.limb_damage_transfer_head = wl.limb_damage_transfer_head end
if wl.limb_damage_transfer_arms then t.limb_damage_transfer_arms = wl.limb_damage_transfer_arms end
if wl.limb_damage_transfer_legs then t.limb_damage_transfer_legs = wl.limb_damage_transfer_legs end
if type(wl.dmg_mult) == "table" then
    t.mult_head  = wl.dmg_mult.head  or 1.0
    t.mult_chest = wl.dmg_mult.chest or 1.0
    t.mult_arm   = wl.dmg_mult.arm   or 1.0
    t.mult_leg   = wl.dmg_mult.leg   or 1.0
else
    t.mult_head, t.mult_chest, t.mult_arm, t.mult_leg = 1.0, 1.0, 1.0, 1.0
end
-- Reconstruir tab (patrón existente)
ADS_Browser.RightPanel:Clear()
BuildRightPanel(ADS_Browser.RightPanel)
```

##### "Reset sliders to default" (actualizado)

```lua
ADS_Browser.Template = {
    head_hp_frac              = 0.30,
    arms_hp_frac              = 0.20,
    legs_hp_frac              = 0.20,
    limb_damage_transfer_head = 1.50,
    limb_damage_transfer_arms = 0.80,
    limb_damage_transfer_legs = 0.60,
    mult_head = 1.0, mult_chest = 1.0, mult_arm = 1.0, mult_leg = 1.0,
}
ADS_Browser.RightPanel:Clear()
BuildRightPanel(ADS_Browser.RightPanel)
```

---

### Resumen de net messages Block 4

| Mensaje | Dirección | Contenido |
|---|---|---|
| `ads_request_armor` | cliente → server | `WriteString(classname)` |
| `ads_armor_data` | server → cliente | `WriteString(classname)` + `WriteTable(profile)` |
| `ads_save_armor` | cliente → server | `WriteString(classname)` + `WriteTable(profile)` |
| `ads_catalog_state` | server → cliente | payload extendido con campo `armored` |

---

*Documento Block 4 generado post-diseño con Opus. Refleja: silueta de template fijo (§7 probe diferido), editor de zonas por hitgroup, net de armor par request/save/ACK, cleanup de Sanitize 1.x, y reescritura del tab Limbs/WL a campos 2.0.*
