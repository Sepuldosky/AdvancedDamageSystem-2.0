# ADS 2.0 — Block 5: Adiciones al documento de arquitectura

> Integrar al final de ADS_2_0_Architecture.md (después de §14 Block 4).
> También actualizar la tabla de estado de §13: Block 5 → 🔲 Pendiente.

---

## §15. Block 5 — Browser Restructure: modelo de template + 3 tabs

### Motivación

Block 4 dejó el tab Armor como **editor por-NPC**: seleccionar uno cargaba su perfil
automáticamente (autoload en `UpdateSelectionCount`). Block 5 lo convierte en
**modelo de template**: el usuario construye un bundle (Armor + Limbs/WL) libremente
y lo aplica a los NPCs seleccionados en un solo paso. El autoload desaparece; la
fuente de datos pasa a ser **Copy Selected** (y su alias doble-click).

### Cambio de modelo

| Aspecto | Block 4 (old) | Block 5 (new) |
|---|---|---|
| Fuente del Armor tab | Autoload al seleccionar 1 NPC | Copy Selected / doble-click |
| Scope del perfil de armor | Por NPC seleccionado | Template global del browser |
| Aplicar a NPCs | Save Profile (1 clase) | Whitelist Selected (batch) |
| Tabs del right panel | Armor / Limbs/WL | **Armor / Limbs/WL / General** |
| Armor tab vacío + Whitelist Selected | N/A | Borra armadura de las clases aplicadas |

### Archivos modificados

| Archivo | Cambios |
|---|---|
| `ads_core.lua` (server) | +1 net string `ads_save_armor_batch`, handler batch |
| `cl_ads_browser.lua` (client) | Layout Armor tab, tab General, CopyFromClass, doble-click, UpdateSelectionCount |

---

### Server — ads_core.lua

#### Net string nuevo

```lua
util.AddNetworkString("ads_save_armor_batch")
```

#### Handler ads_save_armor_batch

Acepta una lista de classnames + un perfil (idéntico a `ads_save_armor`). Aplica el
mismo perfil a todas las clases, un solo `SaveConfig`, re-init NWvars en vivos.
Perfil vacío (`{}`) → `SanitizeArmor` devuelve nil → borra armadura en todas las clases.

```lua
net.Receive("ads_save_armor_batch", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local classes = net.ReadTable()
    local raw     = net.ReadTable()
    if type(classes) ~= "table" or #classes == 0 then return end

    local clean = SanitizeArmor(raw)   -- nil si perfil vacío
    for _, classname in ipairs(classes) do
        if type(classname) == "string" and classname ~= "" then
            ADS.ArmorProfiles[classname] = clean
        end
    end
    ADS.SaveConfig()

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent:IsNPC() then
            local cls = ent:GetClass()
            for _, classname in ipairs(classes) do
                if cls == classname then
                    ADS.InitArmorNWvars(ent)
                    break
                end
            end
        end
    end
end)
```

No hay ACK al cliente (el cliente recalcula su estado con el próximo `RequestState`
que se dispara al recibir el broadcast de listas).

---

### Client — cl_ads_browser.lua

#### Estado de template global (nuevas entradas)

```lua
ADS_Browser._lastClickTime  = 0     -- para detección de doble-click
ADS_Browser._lastClickClass = nil
ADS_Browser.ArmorSourceLabel = nil  -- referencia al DLabel de "Copied from:"
```

`ArmorEditor.profile` pasa a ser el **template de armor** (ya no está ligado a un
NPC). `ArmorEditor.classname` deja de usarse (puede quedar como nil siempre).

#### Doble-click en fila

`row.OnMousePressed` detecta doble-click por timing:

```lua
-- Al inicio de row.OnMousePressed, antes de la lógica de selección:
local now = SysTime()
local isDouble = (class == ADS_Browser._lastClickClass)
                 and (now - ADS_Browser._lastClickTime < 0.35)
ADS_Browser._lastClickTime  = now
ADS_Browser._lastClickClass = class

if isDouble and code == MOUSE_LEFT then
    ADS_Browser.CopyFromClass(class)
    return
end
```

#### ADS_Browser.CopyFromClass(classname)

Nueva función global. Copia armor (async) + limbs (sync del cache) al template.

```lua
function ADS_Browser.CopyFromClass(classname)
    -- Limbs: copiar del cache de whitelist si existe
    local wl = ADS_Browser.Whitelist and ADS_Browser.Whitelist[classname]
    if type(wl) == "table" then
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
        end
    end

    -- Armor: async; ads_armor_data receive actualiza ArmorEditor.profile + refresca
    net.Start("ads_request_armor")
    net.WriteString(classname)
    net.SendToServer()

    -- Actualizar label de fuente si el panel está abierto
    if IsValid(ADS_Browser.Frame) and ADS_Browser.ArmorSourceLabel then
        ADS_Browser.ArmorSourceLabel:SetText("Copied from: " .. classname)
        ADS_Browser.ArmorSourceLabel:SetTextColor(Color(180, 210, 180))
    end
    -- Reconstruir tab WL para reflejar los valores de limbs copiados
    if IsValid(ADS_Browser.RightPanel) then
        ADS_Browser.RightPanel:Clear()
        BuildRightPanel(ADS_Browser.RightPanel)
    end
end
```

#### UpdateSelectionCount — sacar autoload de armor

Eliminar el bloque que dispara `ads_request_armor` y llama a `ArmorEditorRefresh`.
La función queda solo con `UpdateCopyButton` y el `InvalidateLayout` del scroll.

#### Tab Armor — nuevo layout

Layout vertical: silueta centrada arriba (TOP, fixed height) → label de fuente (TOP)
→ scroll de controles de zona (FILL). Sin Save/Clear buttons (movidos a General).

Silueta centrada: un `DPanel` contenedor de ancho completo y altura fija. Dentro,
el `silPanel` de 130px se posiciona dinámicamente en `PerformLayout`:

```lua
silContainer.PerformLayout = function(self, w, h)
    silPanel:SetPos(math.floor((w - 130) / 2), 5)
end
```

`instrLabel` pasa a ser `ADS_Browser.ArmorSourceLabel` (referencia global para que
`CopyFromClass` la actualice). Texto inicial: "Armor Template  (use Copy Selected)".

Los controles de zona (checkboxes/sliders/dropdown) usan el ancho completo del scroll
— sin el layout horizontal de 130+FILL que apretaba los sliders.

#### Tab General — BuildGeneralTab(parent)

Nueva función local. Contiene todos los botones movidos de BuildWLTab con renames:

| Nombre antiguo | Nombre nuevo |
|---|---|
| Apply Whitelist Template | **Whitelist Selected** |
| Blacklist Selected | Blacklist Selected (sin cambio) |
| Remove from Lists | **Remove Selected** |
| Copy values from selected | **Copy Selected** |
| Reset sliders to default | **Reset All to Default** |
| Select all visible | **Select All** |
| Deselect all | **Deselect All** |
| Invert selection | **Invert Selection** |
| Refresh from server | Refresh from server (sin cambio) |
| Scan world for extra NPCs | Scan world for extra NPCs (sin cambio) |

**Whitelist Selected:** envía dos mensajes:
1. `ads_save_armor_batch` con las clases seleccionadas + `ArmorEditor.profile`
2. `ads_modify_list` / `wl_add_batch` con payload de limbs + clases seleccionadas

Sin confirm de "vas a borrar armadura" — vacío = borrar es el comportamiento querido
(el flujo normal arranca con Copy Selected que prellena armor).

**Reset All to Default:** defaultea limbs template + limpia `ArmorEditor.profile`
+ llama `ArmorEditorRefresh`.

**Copy Selected:** llama `ADS_Browser.CopyFromClass(ADS_Browser.LastClicked)` si
hay un `LastClicked` válido.

`CopyButton` (referencia global) apunta al botón Copy Selected en General.
`UpdateCopyButton` lo habilita solo si `LastClicked` es `wl_user`.

#### BuildRightPanel — 3 tabs

```lua
local generalScroll = vgui.Create("DScrollPanel")
sheet:AddSheet("Armor",      armorScroll,   nil, false, false)
sheet:AddSheet("Limbs / WL", wlScroll,      nil, false, false)
sheet:AddSheet("General",    generalScroll, nil, false, false)
BuildArmorTab(armorScroll)
BuildWLTab(wlScroll)
BuildGeneralTab(generalScroll)
```

`BuildWLTab` queda solo con los sliders de Limbs HP / Transfer / Multipliers.
Los botones de acción + selection utilities + catalog pasan a `BuildGeneralTab`.

---

### Block 6 — Templates con nombre (diferido)

Templates nombrados persistidos en `data/ads/ads_templates.json`. Un template =
bundle `{ armor_profile, limbs_template }`. UI en tab General: dropdown de templates
+ botones Save Template (con prompt de nombre) / Load Template / Delete Template.
Diseño a cerrar en sesión futura una vez Block 5 esté testeado.
