# Advanced Damage System 2.0 — Documento de Arquitectura

> **Uso de este documento:** Referencia autocontenida para sesiones futuras de planificación (Claude Opus) e implementación (Claude Code). Cada sección es independiente. No se requiere el chat de diseño original.

---

## Índice

1. [Codebase existente](#1-codebase-existente)
2. [Objetivo de ADS 2.0](#2-objetivo-de-ads-20)
3. [Propiedad de dominios](#3-propiedad-de-dominios)
4. [Compatibilidad de bases de armas](#4-compatibilidad-de-bases-de-armas)
5. [El Extractor — tuple normalizado](#5-el-extractor--tuple-normalizado)
6. [Cobertura por hitgroup](#6-cobertura-por-hitgroup)
7. [Detección de hitgroups por modelo](#7-detección-de-hitgroups-por-modelo)
8. [Data model — JSON y NWvars](#8-data-model--json-y-nwvars)
9. [Cambios a ads_limbs](#9-cambios-a-ads_limbs)
10. [Materiales y perfiles](#10-materiales-y-perfiles)
11. [El Resolver — matemática de penetración](#11-el-resolver--matemática-de-penetración)
12. [Puntos de enganche por base](#12-puntos-de-enganche-por-base)
13. [Scope fase 1 / backlog fase 2](#13-scope-fase-1--backlog-fase-2)
14. [Block 4 — Browser UI 2.0](#14-block-4--browser-ui-20)
15. [Block 5 — Browser Restructure: modelo de template + 3 tabs](#15-block-5--browser-restructure-modelo-de-template--3-tabs)
16. [Block 5.2 — Armor Tab: refactor a silueta clickeable](#16-block-52--armor-tab-refactor-a-silueta-clickeable)
17. [Sesión — UI Cleanup: Dur Max global, Inspect extendido, Toolgun debug puro, Rename](#17-sesión--ui-cleanup-dur-max-global-inspect-extendido-toolgun-debug-puro-rename)
18. [Block 7 — Weapon Penetration Modifier: Curated Weapons + Ammo Fallback](#18-block-7--weapon-penetration-modifier-curated-weapons--ammo-fallback)

---

## 1. Codebase existente

Siete archivos Lua en el proyecto. Leer con `view` cuando se necesite; las descripciones son índice, no contenido en memoria.

| Archivo | Rol |
|---|---|
| `ads_core.lua` (server) | Núcleo: autoridad de armadura 2.0, whitelist/blacklist, multiplicadores hitgroup, persistencia JSON, net.Receive (incl. Weapons tab, ver §18) |
| `ads_armor.lua` (server) | Extractor + Resolver puros. Tablas estáticas de materiales, ammo fallback (editable, ver §18), curated weapons (cualquier classname, ver §18). Init NWvars por zona. **Block 1 completo.** |
| `ads_limbs.lua` (server) | Subsistema de HP por extremidad: pools head/arms/legs, debuffs, drop de arma, stun, healing API |
| `ads_scavenger.lua` (server) | NPCs recogen armas del suelo |
| `cl_ads.lua` (client) | Paneles del menú Q |
| `cl_ads_browser.lua` (client) | Browser visual "ADS Configuration": 4 tabs (Armor/Limbs WL/Weapons/General), modelo de template, Copy Selected, doble-click, batch actions |
| `ads_config.lua` (toolgun) | Stool de debug puro: M1 aplica armor/limbs per-entity efímero, M2 copia de NPC, Reload inspecciona. Refactor completo, ver §17. |

**Regla cardinal:** la lógica de armadura ADS 2.0 es un **pre-filtro** que se sienta delante de `ads_limbs`. El pool de HP de extremidades **no se modifica** para compensar el blindaje. Los cambios a `ads_limbs` son los mínimos descritos en §9.

---

## 2. Objetivo de ADS 2.0

ADS 2.0 **reemplaza** la capa de armadura del mod original (ADS 1.x) con un sistema de blindaje zonal estilo Escape from Tarkov. No es una adición sobre el stack existente — es un refactor: la capa de armadura 1.x se elimina completamente y 2.0 la sustituye. El JSON se recrea desde cero; no hay migración de datos.

El pipeline de daño resultante: la bala impacta → el resolver de blindaje calcula si penetra, qué daño pasa a carne y cuánta energía pierde la bala → el resultado entra a `ads_limbs`/HP nativo exactamente como lo haría el daño crudo hoy.

Características principales:
- Blindaje por zona (hitgroup), no por entidad entera.
- Durabilidad de placa independiente del HP de la zona.
- Probabilidad de penetración EFT modulada por durabilidad.
- Daño romo (blunt) cuando la placa bloquea.
- Daño post-penetración reducido cuando la placa es perforada.
- La bala pierde `penleft` al perforar una placa (ARC9/TFA).
- Materiales de coeficiente configurable, incluyendo perfiles sci-fi.
- Cobertura asimétrica por hitgroup (un brazo blindado, el otro no).

---

## 3. Propiedad de dominios

| Dominio | Propietario | Regla |
|---|---|---|
| Penetración de round EFT (penPower, armorDamage, penetrationChance) | **Menú ARC9** | ADS solo lee. Nunca escribe. |
| Penetración de armas no-EFT | **Tabla curada ADS** (browser-style) | ADS posee. Curation manual por autor del servidor. |
| Toda la armadura (clase, durabilidad, material, cobertura) | **ADS** | ADS posee. Persiste en JSON y NWvars. |
| HP de extremidades, debuffs, drop de arma | **`ads_limbs`** | Sin cambios estructurales salvo los de §9. |

**Regla de autoridad runtime:** la presencia de un perfil en `ADS.ArmorProfiles[classname]` es la única condición que activa el sistema de armadura sobre un NPC. El pool único `ADS_Armor`, la función `ProcessArmor` y `RollArmor` de ADS 1.x **no existen en 2.0**.

**Regla derivada:** `GetProcessedValue` de ARC9 en el momento del impacto ya incluye lo que el usuario configuró en el menú ARC9. ADS lo lee en vivo — una sola fuente de verdad, sin sync.

---

## 4. Compatibilidad de bases de armas

### Escalera de extracción (de mejor a peor dato)

**Nivel 1 — Round EFT de Darsu (ARC9)**
Detección: el attachment trae `HasAmmoooooooo = true` y `EFTRoundName`. Datos disponibles directamente del round: `penetrationPower`, `armorDamage`, `penetrationChance`, `ricochetChance`. Son valores reales de Tarkov. Se leen con `wep:GetProcessedValue(stat, true)` en el callback de la bala. ADS no infiere nada.

**Nivel 2 — Tabla curada (cualquier arma, no solo ARC9)**
El stat de penetración del SWEP (`Primary.PenetrationMultiplier` en TFA, `Penetration` en ARC9 genérico) **no es comparable entre packs**. Un valor de MW2019 ARC9 y uno de EFT ARC9 viven en escalas distintas. Regla: no scrapearlo como verdad. En su lugar, el autor del servidor lo cura a mano en la tabla de ADS por classname, vía el tab **Weapons** de ADS Configuration (ver §18). Desde ese bloque la tabla curada ya no requiere que el arma sea ARC9 — un `weapon_vj_ak47` o `tfa_m4a1` también pueden curarse directamente, cerrando el gap donde antes caían sin remedio al fallback por ammo type.

**Nivel 3 — VJ Base / HL2 vanilla (fallback por ammo type)**
Las armas VJ usan ammo nativo (`Pistol`, `SMG1`, `SniperRound`, `ar2`, `buckshot`). No traen ningún dato de penetración. El fallback es la tabla por ammo type de ADS. Granularidad máxima: ~6 buckets. Imprecisión asumida y documentada.

Tabla de ammo type → equivalente EFT (valores iniciales, todos convars/ajustables):

| AmmoType GMod | Alias normalizado | penPower EFT eq. | armorDamage | penetrationChance base |
|---|---|---|---|---|
| `Pistol` | pistol | 20 | 25 | 0.20 |
| `SMG1` | smg | 28 | 30 | 0.30 |
| `AR2` / `GenericRifle` | rifle | 42 | 45 | 0.50 |
| `357` | magnum | 38 | 55 | 0.40 |
| `buckshot` | shotgun | 12 | 20 | 0.10 |
| `SniperRound` / `SniperPenetratedRound` | sniper | 60 | 70 | 0.75 |

**Alias de normalización:** strings no uniformes entre frameworks. `SniperRound` (VJ) = `SniperPenetratedRound` (TFA) = bucket "sniper". La capa de alias resuelve esto antes de que el fallback consulte la tabla.

### Tuple normalizado

El extractor escupe siempre la misma estructura al resolver, independiente del origen:

```lua
{
    damage          = number,   -- daño base de la bala
    penPower        = number,   -- poder de penetración, escala EFT 0-70+
    armorDamage     = number,   -- daño al material de la placa, escala EFT
    penChanceBase   = number,   -- probabilidad base 0..1
    source          = string,   -- "eft" | "curated" | "tfa" | "fallback"
}
```

El resolver no sabe ni le importa qué base generó el tuple.

---

## 5. El Extractor — tuple normalizado

Función pura `ADS.ExtractBulletData(wep, dmginfo) → tuple`. Tres branches:

```
1. ¿wep trae HasAmmoooooooo == true?
   → Lee GetProcessedValue de ARC9 EFT. source = "eft".

2. ¿IsValid(wep)? (cualquier base, no solo ARC9 — ver §18)
   → Consulta tabla curada ADS por wep:GetClass(). Si no existe en tabla → fallback.
     source = "curated".

3. Fallback:
   → ammoName = game.GetAmmoName(dmginfo:GetAmmoType())
   → Alias normalizado → consulta tabla fallback (editable, ver §18).
   → damage = dmginfo:GetDamage().
   source = "fallback" | "tfa".
```

**Nota sobre `dmginfo`:** es userdata C++, no acepta claves arbitrarias Lua. No se pueden inyectar campos (`dmginfo.ADS_Pen = x` silencia o rompe). El tuple viaja como variable local en el call site, nunca dentro de `dmginfo`.

---

## 6. Cobertura por hitgroup

### Hitgroups de Source vs zonas de EFT

| Constante GMod | Valor | Zona EFT equivalente | Blindable fase 1 |
|---|---|---|---|
| `HITGROUP_GENERIC` | 0 | Cuerpo completo (fallback) | Sí |
| `HITGROUP_HEAD` | 1 | HEAD | Sí |
| `HITGROUP_CHEST` | 2 | THORAX | Sí |
| `HITGROUP_STOMACH` | 3 | STOMACH | Sí |
| `HITGROUP_LEFTARM` | 4 | LEFT ARM | Sí (superset sci-fi) |
| `HITGROUP_RIGHTARM` | 5 | RIGHT ARM | Sí (superset sci-fi) |
| `HITGROUP_LEFTLEG` | 6 | LEFT LEG | Sí (superset sci-fi) |
| `HITGROUP_RIGHTLEG` | 7 | RIGHT LEG | Sí (superset sci-fi) |

EFT real no blinda extremidades. ADS 2.0 lo permite para armaduras sci-fi (Juggernauts, power armor). Las extremidades sin placa siguen al pool de HP de `ads_limbs` directamente.

### NPCs generic-only

Modelos no humanoides (bestias, headcrabs, mutantes VJ) a menudo solo tienen `HITGROUP_GENERIC`. El perfil de armadura incluye un campo explícito `fallback_generic` con los valores que se aplican cuando el impacto cae en `HITGROUP_GENERIC` o cuando el hitgroup impactado no tiene zona específica definida. El sistema no colapsa ni infiere — usa ese campo. El browser indica visualmente a qué NPCs se aplicó cobertura por zona vs fallback generic.

### Asimetría izquierda/derecha

El sistema guarda durabilidad por hitgroup — la asimetría es nativa y gratuita. Un Juggernaut puede tener placa clase 6 en el brazo derecho y clase 2 en el izquierdo. La UI del browser (silueta) lo muestra y permite configurarlo.

---

## 7. Detección de hitgroups por modelo

**Diferido a Fase 2.** La silueta del browser usa template humano fijo de 7 zonas. Una zona definida que el modelo no puede recibir es dato muerto sin costo de runtime (el resolver lee `trace.HitGroup` en vivo).

~~**Prerequisito para la UI del browser:** saber qué hitgroups tiene un modelo antes de dibujar la silueta (7 regiones o 1 sola).~~

**Implementación futura (Fase 2):** probe oportunista al spawn — `GetHitBoxCount`/`GetHitBoxHitGroup` por hitbox set 0, cache por ruta de modelo (no por clase) en `data/ads/hitgroup_cache.json`. Permite auto-grisar zonas imposibles en la silueta. Spawn temporal de **una** entidad si la clase no está cacheada cuando el browser la necesita.

**Impacto en runtime:** ninguno. El resolver lee `trace.HitGroup` del impacto en vivo. El cache es solo para la UI.

---

## 8. Data model — JSON y NWvars

### JSON — `data/ads/ads_config.json`

El JSON de ADS 2.0 se crea desde cero. No hay migración desde el formato 1.x. La estructura es top-level con cuatro claves independientes:

```json
{
    "whitelist": {
        "npc_combine_s": {
            "head_hp_frac": 0.30,
            "arms_hp_frac": 0.20,
            "legs_hp_frac": 0.20,
            "limb_damage_transfer_head": 1.5,
            "limb_damage_transfer_arms": 0.8,
            "limb_damage_transfer_legs": 0.6,
            "dmg_mult": { "head": 1.5, "chest": 1.0, "arm": 0.8, "leg": 0.8 }
        }
    },
    "blacklist": {
        "npc_vj_cpriguarh": true
    },
    "armor": {
        "npc_combine_s": {
            "zones": {
                "1": { "class": 4, "dur_max": 80,  "material": "titanium" },
                "2": { "class": 3, "dur_max": 120, "material": "aramid"   },
                "3": { "class": 3, "dur_max": 100, "material": "aramid"   },
                "5": { "class": 4, "dur_max": 80,  "material": "titanium" }
            },
            "fallback_generic": { "class": 3, "dur_max": 100, "material": "aramid" },
            "coverage_profile": "head_torso"
        }
    },
    "curated_weapons": {
        "weapon_tfa_m4a1": {
            "penPower": 42,
            "armorDamage": 45,
            "penChanceBase": 0.50,
            "note": "5.56x45mm equivalente, curado manualmente"
        }
    },
    "ammo_fallback": {
        "sniper": { "penPower": 65, "armorDamage": 75, "penChanceBase": 0.80 }
    }
}
```

**`ammo_fallback` (Block 7, §18):** overrides parciales de los 6 buckets de `ADS.AmmoFallbackDefaults`. Solo se persisten los buckets que el admin modificó — los demás heredan el default hardcoded en `ads_armor.lua` y no aparecen en el JSON. Poblado/leído por `ADS.SanitizeAmmoFallback` + `ADS.GetAmmoFallbackOverrides`.

**Reglas de formato:**
- Claves de zona en `armor.*.zones`: string del valor entero del hitgroup (`"1"` = HEAD, `"2"` = CHEST, etc.). Solo las zonas con placa existen — las que faltan son carne directa.
- `fallback_generic`: se aplica cuando `HITGROUP_GENERIC` recibe el impacto, o cuando el hitgroup impactado no tiene entrada en `zones`. Si el perfil no tiene `fallback_generic`, los hits en zonas sin placa pasan directo a carne.
- `coverage_profile`: metadato de UI opaco. No lo lee el resolver en runtime; solo lo consume el browser para dibujar la silueta.
- `whitelist` ya **no** contiene `armor_min`, `armor_max`, `red_min`, `red_max`, `coverage`. Solo lleva campos de tuning de limbs y multiplicadores de zona.
- `blacklist` y `whitelist` conviven con `armor`: un NPC puede tener perfil de armadura 2.0 sin estar en whitelist. Son sistemas ortogonales.

### NWvars — estado runtime por entidad

Durabilidad actual viaja como NWvar para que la UI (browser, HUD futuro) la lea sin red extra. El estado de zona se indexa por hitgroup.

```lua
-- Por cada zona blindada activa:
ent:SetNWInt("ADS_Armor_Class_" .. hitgroup,   class)
ent:SetNWInt("ADS_Armor_Dur_"   .. hitgroup,   durActual)   -- se actualiza cada impacto
ent:SetNWInt("ADS_Armor_MaxDur_".. hitgroup,   durMax)
ent:SetNWString("ADS_Armor_Mat_".. hitgroup,   material)

-- Flag de inicialización:
ent:SetNWBool("ADS_Armor_Init", true)
```

**Regla de sync:** `SetNWInt` de durabilidad se llama **en el mismo tick** que el cálculo (paso 3 del resolver), sin timers. Garantiza que el perdigón 2 lee la durabilidad correcta tras el perdigón 1.

**`InitArmorNWvars` es idempotente (FIX-B):** al entrar, limpia los slots 0–7 incondicionalmente (`Class/Dur/MaxDur/Mat` a cero, `Init` a false). Luego repuebla si hay perfil. Sin esto, re-init sobre un NPC vivo (p.ej. tras editar o borrar un perfil en el browser) dejaba NWvars viejas activas hasta el respawn. No afecta el path de spawn (slots ya vacíos sobre un ent nuevo).

### JSON — tabla curada de armas no-EFT

Ver `curated_weapons` en el ejemplo de arriba. `ADS.CuratedWeapons` se puebla en `ADS.LoadArmorData(parsed)` desde esta clave. El campo `note` es solo documentación, no lo lee el extractor.

---

## 9. Cambios a ads_limbs

`ads_limbs` no se reescribe. Los cambios son mínimos y aditivos.

### Placa por extremidad (estado nuevo)

Cada extremidad blindada tiene durabilidad de placa **separada del HP pool**. La placa se rompe antes que la carne. Estado guardado en NWvars (§8).

El pre-filtro de armadura corre antes de que el daño entre al pool. El pool en sí, los debuffs de precisión/velocidad, y la lógica de healing **no cambian**.

### Drop de arma — brazo dominante

Regla actual: drop cuando cualquier brazo llega a HP 0.
Regla nueva: drop solo cuando `HITGROUP_RIGHTARM` (brazo gatillo) llega a HP 0.

`HITGROUP_LEFTARM` destruido solo baja precisión (Lerp con HP, como hoy).
`HITGROUP_RIGHTARM` destruido baja precisión **y** ejecuta el drop.

Sin tiradores zurdos en GMod. `HITGROUP_RIGHTARM` es la etiqueta consistente, independiente de si el modelo tiene el brazo físicamente a la derecha.

### Daño que entra al pool

El pre-filtro entrega `fleshDmg` (sea daño romo o post-penetración). Ese valor entra al pool de HP del hitgroup exactamente igual que hoy — con su multiplicador de hitgroup nativo. `ads_limbs` no sabe que vino filtrado.

---

## 10. Materiales y perfiles

### Materiales base (coeficiente de destructibilidad y blunt factor)

Un material es **solo dos números**: `coefDestruc` (cuánto daña al blindaje cada impacto) y `blunt` (qué fracción del daño base pasa como daño romo al bloquear).

| Material | `coefDestruc` | `blunt` base | Notas |
|---|---|---|---|
| `aramid` | 0.25 | 0.30 | Kevlar textil, muy durable, se repara fácil |
| `titanium` | 0.50 | 0.20 | Equilibrado |
| `ceramic` | 0.85 | 0.15 | Absorbe bien el primero, se destruye en 2-3 impactos |
| `poly_ceramic` | 0.10 | 0.05 | Sci-fi: campo de energía reactivo (HEV cargado) |
| `nano_titanium` | 0.35 | 0.00 | Sci-fi: gel hidrostático, romo nulo (ver §11 piso) |
| `electrified_aramid` | 0.25 | 0.30 | PCV de HECU, base aramid con capa eléctrica |
| `m_stf` | 0.15 | 0.45 | Sci-fi: fluido no-newtoniano, romo MUY alto sin placa rígida |
| `uranium_matrix` | 0.75 | 0.10 | Sci-fi: clase altísima, se agrieta rápido una vez que cede |

### Abreviaturas de material (UI browser — hardcoded cliente)

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

Los 8 códigos son de 2 chars y no colisionan. No requieren sync server→cliente.

### Perfiles condicionales (power armor, escudos)

Un perfil puede tener un **trigger runtime** que swapea el tuple `{clase, material, durMax}` activo. El resolver recibe el tuple ya resuelto — no sabe que es condicional.

Ejemplos:
- **HEV Mark V:** trigger `ply:Armor() > 0` (*nota: usar NWvar propia, no `ply:Armor()` nativo — ver §3*). Cargado → clase 5, `poly_ceramic`. Descargado → clase 3, `poly_ceramic` con `coefDestruc = 0.60`.
- **Escudo recargable:** NWvar de escudo > 0 → clase extra delante de la placa física (fase 2).
- **Juggernaut MW:** sin trigger, clase 6, `titanium`, cobertura completa 7 hitgroups.

### Clases sobre 7 — advertencia de diseño

La fórmula de penetración usa `clase × 10` como umbral. Los rounds EFT más altos tienen `penPower ≈ 70`. Una clase 8 → umbral 80 → **ninguna bala del arsenal normal penetra**. Arriba de clase 7 el sistema se comporta como esponja de HP + daño romo, no como simulación de penetración. Uso intencional para jefes y exotrajes pesados, no accidental.

---

## 11. El Resolver — matemática de penetración

Función pura: `ADS.ResolveArmor(zona, tuple, hitgroup) → {fleshDmg, newDur, factorPenleft}`

### Entradas

- `zona`: `{clase, durActual, durMax, material}` leído de las NWvars del hitgroup impactado por `ADS.GetZone(ent, hitgroup)`.
- `tuple`: del extractor (§5): `{damage, penPower, armorDamage, penChanceBase}`.
- `hitgroup`: constante numérica del hitgroup impactado.

### Paso 0 — Doble compuerta

```
¿GetZone devuelve nil para este hitgroup?            → retorna fleshDmg = damage completo.
¿El tipo de daño está en el set BLOCKABLE?           → No: retorna fleshDmg = damage completo.
```

El bitmask `BLOCKABLE` (definido en `ads_core`) incluye `DMG_BULLET`, `DMG_SLASH`, `DMG_CLUB`, `DMG_BUCKSHOT`, `DMG_SNIPER`. **Sobrevive el refactor intacto.** Explosiones (`DMG_BLAST`) y aplastamiento (`DMG_CRUSH`) son **no-bloqueables** en 2.0 — el special-casing que tenían en 1.x (convars `ads_blast_mult`/`ads_crush_mult`) se eliminó junto con `ProcessArmor`. El daño explosivo pasa directamente a carne sin reducción de armadura.

### Paso 1 — Cálculo de probabilidad de penetración

```lua
DurFactor        = zona.durActual / zona.durMax          -- 0..1
ArmaduraEfectiva = zona.clase * 10
ratio            = tuple.penPower / ArmaduraEfectiva      -- ratio, no resta

-- Ancla: cuando ratio==1 y DurFactor==1, penChance == penChanceBase (valor real EFT)
penChance = tuple.penChanceBase
          + ADS_PEN_OVER_ADJ  * (ratio - 1)              -- sobrepenetración sube chance
          + ADS_DUR_ADJ       * (1 - DurFactor)          -- placa dañada protege menos
penChance = math.Clamp(penChance, 0, 1)
```

Convars de ajuste (valores iniciales):
- `ads_pen_over_adj` = 0.5
- `ads_dur_adj` = 0.25

**El kernel de probabilidad es swappable.** Todo lo que cambia si se afina con datos reales son estas tres líneas. El resolver no se entera.

### Paso 2 — Roll de penetración

```lua
if GetConVar("ads_armor_deterministic"):GetBool() then
    penetra = (penChance >= 0.5)
else
    penetra = (math.random() <= penChance)
end
```

`ads_armor_deterministic 0` por default (probabilístico, fiel a EFT).
`ads_armor_deterministic 1` para debug sin varianza.

### Paso 3a — BLOQUEA

```lua
-- Piso de romo: HARDCODED 5%. Ningún perfil lo baja.
bluntFactor = math.max(0.05, zona.material.blunt * (1 - (zona.clase - 1) * 0.1))
fleshDmg    = tuple.damage * bluntFactor

factorPenleft = 0          -- bala muerta en el chaleco

-- Desgaste de placa: bloquear daña MÁS que perforar
ΔD       = tuple.armorDamage * zona.material.coefDestruc * (1.2 - DurFactor)
newDur   = math.max(0, zona.durActual - ΔD)
-- → caller llama SetNWInt inmediato
```

### Paso 3b — PENETRA

```lua
resistRatio     = math.Clamp(ArmaduraEfectiva / tuple.penPower, 0, 1)
penDamageFactor = math.max(0.4, 1 - resistRatio * 0.5)   -- energía que sobrevive

fleshDmg        = tuple.damage * penDamageFactor

-- Mismo factor para daño a carne y para penleft: coherencia energética
factorPenleft   = penDamageFactor

-- Perforar daña la placa la mitad que bloquear (EFT real)
ΔD     = tuple.armorDamage * zona.material.coefDestruc * (1.2 - DurFactor) * 0.5
newDur = math.max(0, zona.durActual - ΔD)
-- → caller llama SetNWInt inmediato
```

### Paso 4 — Handoff

`fleshDmg` entra a `ads_limbs`/HP nativo con su multiplicador de hitgroup nativo. El resolver no toca el pool. `factorPenleft` lo aplica el call site sobre el `penleft` de la bala (§12).

### Casos borde resueltos por el diseño

| Caso | Comportamiento |
|---|---|
| Perdigones múltiples (escopeta) | El resolver es función pura por perdigón. SetNWInt en paso 3 garantiza que perdigón 2 lee durabilidad correcta. Sin timers. |
| Durabilidad 0 | `DurFactor = 0` sube `penChance` en `+ads_dur_adj`. La placa rota aún puede bloquear raramente (fiel a EFT). Si se prefiere bypass total: `if zona.durActual <= 0 then return carne directa end` — una línea, convar. |
| NPC generic-only | Usa `fallback_generic` del perfil. Misma función, tuple distinto. |
| Tipo de daño no bloqueable | Paso 0 lo filtra. Cero overhead en daño explosivo, fuego, etc. |

---

## 12. Puntos de enganche por base

La matemática es una. Los call sites son específicos de la base.

### VJ Base / HL2 vanilla — `ScaleNPCDamage` (Block 2)

- **Punto:** hook `ScaleNPCDamage "ADS_Core_NPC"` en `ads_core.lua`.
- **Pipeline refactorizado (reemplaza `ProcessArmor`):**
  1. `ADS.ExtractBulletData(wep, dmginfo)` → tuple. El attacker se extrae de `dmginfo:GetAttacker():GetActiveWeapon()` o similar.
  2. `ADS.GetZone(npc, hg)` → zona o nil.
  3. Gate tipo de daño (bitmask BLOCKABLE en ads_core). Si no pasa → continúa sin modificar.
  4. `ADS.ResolveArmor(zona, tuple, hg)` → resultado.
  5. `dmginfo:SetDamage(resultado.fleshDmg)`.
  6. `npc:SetNWInt("ADS_Armor_Dur_" .. hg, resultado.newDur)` — inmediato.
  7. `factorPenleft` se ignora en este call site (balas VJ/HL2 no tienen penleft propio).
- **Sobreviven sin cambio:** `ApplyDamageMultiplier`, handoff a `ADS.ProcessLimbHit`, compensación de engine `engine_comp`. Estos van después del resolver en el mismo hook.
- **Sound:** el sonido de impacto de placa se emite desde el call site cuando `resultado.factorPenleft == 0` (bloqueó) o cuando `zona ~= nil` (penetró pero había placa).

### ARC9 — detour de `AfterShotFunction` (Block 3)

**Mecanismo: detour + stash en dos fases.** El core de ARC9 (`sh_shoot.lua`, `sh_physbullet.lua`, `sh_penetration.lua`) **no se toca** — actualizaciones mensuales lo reescribirían.

**Por qué no `Hook_BulletImpact`:** ese hook (línea 760 de `sh_shoot.lua`) es observacional puro. AfterShotFunction no re-lee `runHook.dmgv` después del hook; su `dmgv` local se sobreescribe con `dmg:SetDamage(dmgv)` en línea 846. Cualquier `SetDamage` emitido desde el hook es pisado.

**Implementación (en `ads_core.lua`, dentro de `InitPostEntity "ADS_ARC9_Compat"`):**

**Fase A — detour pre-call:**
```lua
local origASF = weapons.GetStored("arc9_base").AfterShotFunction
weapons.GetStored("arc9_base").AfterShotFunction = function(self, tr, dmg, range, penleft, ...)
    if IsValid(tr.Entity) and tr.Entity:IsNPC() and ADS.IsArmored(tr.Entity) then
        local zona = ADS.GetZone(tr.Entity, tr.HitGroup)
        if zona and bit.band(dmg:GetDamageType(), BLOCKABLE) ~= 0 then
            local tuple = ADS.ExtractBulletData(self, dmg)
            tuple.damage = 1.0   -- normalizar: res.fleshDmg = factor puro
            local res = ADS.ResolveArmor(zona, tuple, tr.HitGroup)
            tr.Entity.ADS_ArmorStash = { factor=res.fleshDmg, newDur=res.newDur,
                                         durKey=zona.durKey, frame=FrameNumber() }
            if res.factorPenleft == 0 then penleft = 0 end  -- bala muerta en placa
        end
    end
    return origASF(self, tr, dmg, range, penleft, ...)
end
```

**Fase B — consume en `ScaleNPCDamage` (rama `isARC9`):**
- Guard de staleness: `FrameNumber() - stash.frame <= 1` (AfterShotFunction y su ScaleNPCDamage resultante ocurren dentro del mismo frame o el inmediato siguiente).
- `di:SetDamage(di:GetDamage() * stash.factor)` — el factor ya incorpora el resultado del roll.
- `npc:SetNWInt("ADS_Armor_Dur_" .. stash.durKey, stash.newDur)` — mismo tick.
- Sonido de impacto si `stash.factor < 1.0`. `npc.ADS_ArmorStash = nil`.
- `ApplyDamageMultiplier`, `ProcessLimbHit` y `engine_comp` siguen normales después.

**Tratamiento de `penleft` — binario (no multiplicativo):**
`penleft` modula `dmgv` vía `pendelta` (línea 766) **antes** de `SetDamage(846)`. Escalarlo multiplicativamente pre-call corrompería pendelta. Decisión: si la placa bloquea → `penleft = 0` (ARC9's `Penetrate()` retorna inmediato en su guard `penleft <= 0`). Si penetra → `penleft` intacto (ARC9 modela la pérdida de energía por su propio pen-trace). Costo asumido fase 1: bala que penetra conserva todo su `penleft`, sin descuento por la placa.

**Cobertura:** hitscan (`DoProjectileAttack`) y físicas (`ProgressPhysBullet`) convergen ambas en `AfterShotFunction`. Un solo detour cubre todo.

**Front 4 — doble mult de zona ARC9 (diferido a Fase 2):** ARC9 EFT aplica mults de zona propios (`BodyDamageMults`: Head/Chest/Arm/Leg) en líneas 785-796 de `sh_shoot.lua`. `ApplyDamageMultiplier` de ADS los vuelve a escalar → doble mult de zona real. Efecto net: miembros reciben ~50% menos daño del esperado. No se corrige en Block 3 porque el `dmg_mult` de ADS cumple rol de supervivencia de extremidades que no puede eliminarse sin ajustar simultáneamente pools y transfer (ver §13 Fase 2).

### TFA (backlog fase 2)

- **Punto:** hook `TFA_Bullet_Penetrate` o desvío de `SWEP.MainBullet.Callback` en `bullet.lua`.
- **Misma lógica** que ARC9: extractor → resolver → modifica `dmginfo` → modifica `self.PenetrationPower` del bullet.
- Si bloquea: `self.PenetrationPower = 0`.

---

## 13. Scope fase 1 / backlog fase 2

### Convars eliminados en el refactor (no referenciar como activos)

Los siguientes convars existían en ADS 1.x y **no existen en 2.0:**

| ConVar | Razón de eliminación |
|---|---|
| `ads_min_arm` | Pool único de armadura eliminado |
| `ads_max_arm` | Pool único de armadura eliminado |
| `ads_ply_arm` | Armadura de jugador en backlog fase 2 |
| `ads_red_min` | Reducción porcentual 1.x eliminada |
| `ads_red_max` | Reducción porcentual 1.x eliminada |
| `ads_helmet_mult` | Reemplazado por clase/material por zona |
| `ads_blast_mult` | Explosión es no-bloqueable en 2.0 |
| `ads_crush_mult` | Crush es no-bloqueable en 2.0 |

### Estado de implementación

> **Estado vigente → [`ads_estado.md`](ads_estado.md)** (foto de HOY, fuente viva). La tabla siguiente es el registro de cierre de diseño de cada bloque; para saber qué está aplicado/pendiente HOY, manda `ads_estado.md`.

| Bloque | Contenido | Estado |
|---|---|---|
| **Block 1** | `ads_armor.lua`: tablas estáticas, convars, `ExtractBulletData`, `ResolveArmor` | ✅ Completo |
| **Block 2** | Rip-out capa 1.x + capa de datos (`LoadArmorData`, `InitArmorNWvars`, `GetZone`) + cableado VJ en `ScaleNPCDamage` | ✅ Completo |
| **Block 3** | Call site ARC9: detour de `AfterShotFunction` via `arc9_base` + consume stash en `ScaleNPCDamage` | ✅ Completo |
| **Block 4** | Browser UI: net de armor, editor de zonas por hitgroup, tab Armor + Limbs/WL | ✅ Completo |
| **Block 5** | Browser restructure: 3 tabs (Armor/Limbs/WL/General), modelo de template, Copy Selected, doble-click, batch armor | ✅ Completo |
| **Block 5.2** | Armor tab: silueta clickeable, editor único, info popups, imágenes de material | ✅ Completo |
| **Sesión UI Cleanup** | Dur Max fila manual global, Inspect extendido, Toolgun refactor a debug puro, Rename a "ADS Configuration" (ver §17) | ✅ Completo |
| **Block 7** | Weapon Penetration Modifier: tabla curada sin guard ARC9, Ammo Fallback editable, tab Weapons, fallback inline `inline_arc9` (ver §18) | ✅ Prompts generados — pendiente de aplicar y verificar en juego |

### Fase 1 — completada

- ✅ Extractor con 3 niveles (EFT, curado, fallback ammo).
- ✅ Resolver con pasos 0-4 descritos en §11.
- ✅ Rip-out completo de la capa de armadura ADS 1.x.
- ✅ Cobertura por hitgroup (7 zonas), incluyendo superset sci-fi (extremidades).
- ✅ NWvars por zona, sync síncrono. `InitArmorNWvars` idempotente (FIX-B).
- ✅ JSON con estructura top-level `{whitelist, blacklist, armor, curated_weapons}`.
- ✅ Cambios a `ads_limbs`: drop solo en `HITGROUP_RIGHTARM`.
- ✅ Call sites VJ/HL2 (`ScaleNPCDamage`) y ARC9 (`AfterShotFunction`).
- ✅ Materiales base + perfiles sci-fi estáticos (sin trigger).
- ✅ `ads_armor_deterministic` convar.
- ✅ Browser UI: editor de zonas, modelo de template, 4 tabs (Armor/Limbs-WL/Weapons/General), batch apply.
- ✅ Refactor toolgun `ads_config.lua` a debug puro (M1/M2/Reload) — ver §17.
- ✅ Inspect extendido (`armor_slots`, `is_whitelisted`, `tool_override`) — ver §17.
- ✅ Weapon Penetration Modifier: tabla curada abierta + Ammo Fallback editable — ver §18.
- ⏳ Cache de hitgroups por modelo → diferido a Fase 2 (§7).
- ⏳ `MakeSlider` del tab Limbs/WL sigue en `DNumSlider` (no migrado en la sesión de §17) — flaggeado, ver §17.

### Fase 2 (backlog)

- **Front 4 — skip de `ApplyDamageMultiplier` para ARC9:** ARC9 EFT ya aplica mults de zona propios antes de `ScaleNPCDamage`. ADS los duplica → miembros reciben ~50% menos daño. Solución: extender el guard `isARC9` para saltar `ApplyDamageMultiplier` y calibrar supervivencia de extremidades con `ads_limb_damage_transfer_arms`, `ads_limb_arms_frac`. Condición de entrada: verificar en juego el feel de supervivencia de miembros ajustando dichos sliders.
- **Probe de hitgroups (§7):** spawn temporal + GetHitBoxHitGroup por modelo no cacheado; grisa zonas imposibles en la silueta del browser.
- **Templates con nombre (Block 6):** bundle `{armor_profile, limbs_template}` guardado con nombre en `data/ads/ads_templates.json`. UI en tab General: dropdown + Save Template / Load Template / Delete Template. Diseño a cerrar en sesión futura.
- **Armadura de jugador:** misma lógica que NPCs. Perfil guardado por playermodel. `ply:SetArmor()` siempre 0, todo en NWvars propias. No usar `ply:Armor()` nativo. Requiere backend nuevo — pestaña propia en ADS Configuration (junto a Weapons).
- **Perfiles condicionales runtime:** trigger de batería/escudo en NWvar propia.
- **Escudos recargables:** zona-escudo separada que se resuelve antes de la placa física.
- **Multi-zona intra-NPC en un tiro:** `penleft` transferido entre dos zonas del mismo NPC.
- **Afinar kernel de penetración** con datos del Excel de curvas EFT reales.
- **Call site TFA.**
- **Penalización de movimiento** para armaduras pesadas (uranium_matrix: -40% velocidad).
- **NPC disparando ARC9 (scavenger):** confirmar empíricamente si `path=stash` o `path=inline_arc9` en el trace — ver §18 caso borde.
- **Migrar `MakeSlider` del tab Limbs/WL** a fila manual (mismo patrón que Armor tab) — único remanente de `DNumSlider` en ADS tras §17.

### Regresión esperada e interina

Entre Block 2 y la implementación de armadura de jugador (fase 2): los jugadores no tienen armadura ADS. Solo el `ply:Armor()` nativo de GMod queda activo. `ScalePlayerDamage "ADS_Core_Player"` se elimina junto con el rip-out. Comportamiento esperado y documentado.

---

## 14. Block 4 — Browser UI 2.0

### Alcance

Net de armor + editor de zonas + reemplazo del right panel 1.x. No toca el damage path.

| Archivo | Cambios |
|---|---|
| `ads_core.lua` | +3 net strings (`ads_request_armor`, `ads_armor_data`, `ads_save_armor`), `SanitizeArmor`, payload `catalog_state` extendido, cleanup `Sanitize` 1.x, handlers `ads_request_armor` / `ads_save_armor` |
| `cl_ads_browser.lua` | `DPropertySheet` 2 tabs (Armor / Limbs/WL), Tab Armor con silueta + editor por zona, Tab Limbs/WL con sliders 2.0 |
| `ads_armor.lua` | `InitArmorNWvars` idempotente: loop limpia slots 0–7 antes de repoblar, `Init=false` si no hay perfil |

### Net strings

| Mensaje | Dirección | Contenido |
|---|---|---|
| `ads_request_armor` | cliente → server | `WriteString(classname)` |
| `ads_armor_data` | server → cliente | `WriteString(classname)` + `WriteTable(profile)` |
| `ads_save_armor` | cliente → server | `WriteString(classname)` + `WriteTable(profile)` |
| `ads_catalog_state` | server → cliente | array paralelo: `WriteUInt(count)` + por entrada `WriteString(status)` + `WriteBool(armored)` (sin repetir classnames — evita overflow con catálogos grandes) |

### catalog_state — array paralelo (FIX-C)

El server responde con un array paralelo al orden que el cliente mandó (sin keys ni classnames), evitando el overflow de 64KB que producía `net.WriteTable` con el payload extendido. El cliente guarda el orden en `ADS_Browser._stateOrder` antes de enviar y lo usa en el receive.

### SanitizeArmor(profile)

Función local en `ads_core.lua`. Valida y clampa perfiles antes de persistir. Retorna `nil` si no hay zonas ni fallback_generic válidos (= borrar perfil de la clase). Campos validados por zona (keys `"1"`.."7" string): `class` (clamp 1-8), `dur_max` (clamp 1-200), `material` (∈ keys de `ADS.Materials`, fallback "aramid"). `coverage_profile` almacenado opaco (max 64 chars).

### Bugs encontrados y corregidos (FIX-A, FIX-B, FIX-C)

| Fix | Bug | Solución |
|---|---|---|
| FIX-A/1 | Forward-reference de `BuildRightPanel`: crash en botones Copy/Reset dentro de `BuildWLTab` | `local BuildRightPanel` forward-declarado antes de `BuildArmorTab`; definición sin `local` asigna al upvalue |
| FIX-A/2 | Re-entrancy en `ArmorEditorRefresh`: `SetValue` disparaba callbacks que mutaban el profile con valores stale (material corrupto, dirty falso) | `local refreshing = false` como upvalue; 4 callbacks hacen early-return si activo; refresh activa y limpia el flag |
| FIX-B | `InitArmorNWvars` no idempotente: editar/borrar perfil en NPCs vivos no surtía efecto hasta respawn | Loop limpia slots 0-7 incondicionalmente al entrar; `Init=false` si no hay perfil |
| FIX-C/1 | Panel derecho invisible: `DPropertySheet Dock(FILL)` dentro de `DScrollPanel` colapsaba a altura 0 | Contenedor `right` cambiado de `DScrollPanel` a `DPanel` |
| FIX-C/2 | Net overflow en `catalog_state`: `WriteTable({[class]={status,armored}})` reventaba 64KB con catálogos VJ grandes | Reescrito como array paralelo (ver tabla de net strings arriba) |

### Limitación conocida

Copy Selected y Reset All to Default reconstruyen el `DPropertySheet` entero (`BuildRightPanel`), lo que resetea el tab activo de vuelta a Armor. Aceptable para Fase 1; corrección quirúrgica diferida a Fase 2 (refrescar solo los sliders del tab WL sin rebuild total).

---

## 15. Block 5 — Browser Restructure: modelo de template + 3 tabs

### Motivación

Block 4 dejó el tab Armor como editor por-NPC (autoload al seleccionar). Block 5 lo convierte en **modelo de template**: el usuario construye un bundle (Armor + Limbs/WL) y lo aplica a los seleccionados en un paso. El autoload desaparece; la fuente de datos es **Copy Selected** (y su alias doble-click).

### Cambio de modelo

| Aspecto | Block 4 | Block 5 |
|---|---|---|
| Fuente del Armor tab | Autoload al seleccionar 1 NPC | Copy Selected / doble-click |
| Scope del perfil de armor | Por NPC seleccionado | Template global del browser |
| Aplicar a NPCs | Save Profile (1 clase) | Whitelist Selected (batch, N clases) |
| Tabs del right panel | Armor / Limbs/WL | **Armor / Limbs/WL / General** |
| Armor tab vacío + Whitelist Selected | N/A | Borra armadura de las clases aplicadas |

### Archivos modificados

| Archivo | Cambios |
|---|---|
| `ads_core.lua` | +1 net string `ads_save_armor_batch`, handler batch |
| `cl_ads_browser.lua` | Layout Armor tab (vertical), tab General, `CopyFromClass`, doble-click, `UpdateSelectionCount` sin autoload |

### Server — ads_save_armor_batch

Acepta lista de classnames + perfil. Aplica el mismo perfil a todas las clases, un `SaveConfig`, re-init NWvars en vivos. Perfil vacío → `SanitizeArmor` nil → borra armadura en todas las clases.

### Client — cambios clave

**`ADS_Browser.CopyFromClass(classname)`:** copia armor (async, `ads_request_armor`) + limbs (sync del cache WL) al template. Actualiza `ArmorSourceLabel`. Reconstruye el tab WL para reflejar los valores de limbs copiados.

**Doble-click:** detectado por timing en `row.OnMousePressed` (mismo class, < 0.35s, sin ctrl/shift). Llama `CopyFromClass` y retorna sin procesar selección.

**Tab Armor — layout vertical:** `srcLabel` (TOP) → `silContainer` centrado con `PerformLayout` dinámico → editor de zona. El layout detallado del Armor tab fue reemplazado en Block 5.2 (ver §16); la descripción aquí corresponde al modelo Block 5 original (7 bloques apilados), ya obsoleto.

**Tab Limbs/WL:** solo sliders (HP fracs, transfers, mults). Sin botones de acción.

**Tab General:** todos los botones de acción + selection utilities + catalog. Renames:

| Nombre anterior | Nombre nuevo |
|---|---|
| Apply Whitelist Template | **Whitelist Selected** |
| Remove from Lists | **Remove Selected** |
| Copy values from selected | **Copy Selected** |
| Reset sliders to default | **Reset All to Default** |
| Select all visible | **Select All** |
| Deselect all | **Deselect All** |
| Invert selection | **Invert Selection** |

**Whitelist Selected:** envía `ads_save_armor_batch` (armor) + `ads_modify_list/wl_add_batch` (limbs) para todas las clases seleccionadas. Sin confirm de "vas a borrar armadura" (vacío = borrar es el comportamiento querido; el flujo normal arranca con Copy Selected).

**Reset All to Default:** defaultea limbs template + limpia `ArmorEditor.profile` + llama `ArmorEditorRefresh` + resetea `ArmorSourceLabel`.

**`UpdateSelectionCount`:** bloque de autoload de armor eliminado. Seleccionar ahora solo marca; Copy/doble-click llenan el template.

### Diseño diferido — Refactor toolgun (ads_config.lua)

**Rol nuevo (opción B, cerrado):** mini-panel con convars `armor_class`/`armor_dur`/`armor_mat`. M1 aplica armadura efímera a la entidad viva como `fallback_generic` slot-0 (no persiste JSON). M2 limpia NWvars slots 0-7 de esa entidad. Reload/inspect se mantiene. Manejo de listas (WL/BL, save/reload) sale del toolgun — eso es del browser. **Caveat:** el override es volátil; `InitArmorNWvars` lo pisa en cualquier re-init (p.ej. si se guarda el perfil de esa clase desde el browser).

### Diseño diferido — Templates con nombre (Block 6)

Bundle `{armor_profile, limbs_template}` guardado con nombre en `data/ads/ads_templates.json`. UI en tab General: dropdown de templates + botones Save Template (prompt de nombre) / Load Template / Delete Template. Diseño a cerrar en sesión futura una vez Block 5 esté testeado.

---

---

## 16. Block 5.2 — Armor Tab: refactor a silueta clickeable

### Motivación

Block 5 dejó el Armor tab como 7 bloques apilados: un `DCheckBoxLabel` + 2 `DNumSlider` + `DComboBox` por zona, generados en loop sobre `ZONE_LIST`. Los `DNumSlider` de Clase y Dur Max con `SetTall(22)` colapsaban visualmente — el DNumSlider necesita ≥ 30 px para renderizar su track interno. Resultado: los controles de clase y durabilidad eran invisibles en todas las zonas. Adicionalmente el slider de clase era continuo (arrastre) a pesar de `SetDecimals(0)`, y el combo mostraba el key interno (`poly_ceramic`) en lugar del nombre legible.

La migración resuelve los tres bugs como efecto colateral: el modelo nuevo no usa DNumSlider para clase.

### Alcance

Cambio **client-only**. Únicamente `cl_ads_browser.lua`. Sin cambios en server, JSON, net strings, o cualquier otro archivo.

### Constante nueva — MAT_DISPLAY

Añadida después de `MAT_LIST`, antes del forward declaration de `BuildRightPanel`:

```lua
local MAT_DISPLAY = {
    aramid             = "Aramid",
    titanium           = "Titanium",
    ceramic            = "Ceramic",
    poly_ceramic       = "Poly Ceramic",
    nano_titanium      = "Nano Titanium",
    electrified_aramid = "Electrified Aramid",
    m_stf              = "M-STF Fluid",
    uranium_matrix     = "Uranium Matrix",
}
```

Usada en `DComboBox:AddChoice(MAT_DISPLAY[mat], mat)` para mostrar nombre legible sin perder el key interno como `data` en `OnSelect`.

### Modelo nuevo — BuildArmorTab

**Silhouette panel (130 × 207 px):**

`ZONE_RECTS` mapea hgKey → `{x, y, w, h}` a escala 0.65× del viewBox 200×320 del prototipo SVG:

| hgKey | Zona | x | y | w | h |
|---|---|---|---|---|---|
| "1" | HEAD | 51 | 5 | 28 | 35 |
| "2" | CHEST | 42 | 48 | 46 | 38 |
| "3" | STOMACH | 44 | 87 | 42 | 27 |
| "4" | LEFT ARM | 26 | 49 | 13 | 66 |
| "5" | RIGHT ARM | 91 | 49 | 13 | 66 |
| "6" | LEFT LEG | 43 | 116 | 21 | 86 |
| "7" | RIGHT LEG | 66 | 116 | 21 | 86 |

`silPanel.Paint` usa `draw.RoundedBox` por zona (r=14 para cabeza, r=4 para el resto). Color de relleno: `DurColor(z.dur_max)` si la zona está blindada, `Color(46,46,46)` si no. Texto: `C{class}` + abreviatura de material (solo en zonas anchas). Borde ámbar `DrawOutlinedRect` en la zona seleccionada.

`silPanel:SetMouseInputEnabled(true)`. `OnMouseReleased` (MOUSE_LEFT) itera `ZONE_RECTS` con hit-test de cursor, actualiza `selectedZone` (upvalue local), llama `setEditor(hgKey)`.

**DurColor(dur_max):**

Interpolación lineal en dos tramos. Verde = alta durabilidad (sano/máximo). Morado = baja durabilidad (casi destruida). Dirección invertida respecto al instinto "verde = lleno" porque `dur_max` es capacidad configurada de la placa, no HP actual.

```
morado (139,127,232) ──── azul (55,138,221) ──── verde (63,185,80)
       dur=10                  dur=125                 dur=250
```

Si en el futuro se implementa un HUD live de durabilidad en combate, la escala se invierte (morado = llena, verde = casi rota).

**Editor de zona único (compartido):**

Un solo `editorPanel` que se recarga al clickear una zona. Controles:

| Control | Tipo GMod | Detalle |
|---|---|---|
| Título de zona | `DLabel` | `"CHEST  (zone 2)"` — actualizado por `setEditor` |
| Toggle blindado | `DCheckBoxLabel` | OnChange crea/borra `profile.zones[selectedZone]` |
| Selector de clase | 8 × `DButton` en fila | `PerformLayout` divide el ancho en 8. Activo: bold + blanco. DoClick escribe `profile.zones[selectedZone].class` |
| Info de clase | `DButton "?"` | Abre `ShowInfoPopup` con trivia de texto |
| Material | `DComboBox` | `AddChoice(MAT_DISPLAY[mat], mat)` — OnSelect usa `data` (key interno) |
| Info de material | `DButton "?"` | Abre `ShowInfoPopup` con imagen + trivia |
| Dur Max | `DNumSlider` | `SetTall(30)`, min=10, max=250, decimals=0 |

`setEditor(hgKey)` — forward-declared como upvalue local, definida después de crear los controles. Carga datos del perfil activo en los controles con `refreshing = true` para bloquear callbacks.

**Fallback generic block:**

Estructura idéntica al editor de zona (clase botones + combo + slider). Siempre visible debajo del separador. No ligado a `selectedZone`.

**ADS_Browser.ArmorEditorRefresh:**

Reescrita para refrescar el editor único (zona seleccionada actualmente) + el bloque fallback_generic. Sigue siendo el punto de entrada de `net.Receive("ads_armor_data")` y del botón Reset All to Default en General tab. Invariantes preservados:
- `ADS_Browser.ArmorSourceLabel` asignado en la primera línea de `BuildArmorTab`.
- `ADS_Browser.ArmorEditorRefresh` asignado al final de `BuildArmorTab`.
- Firma pública sin cambios — ningún caller externo tuvo que modificarse.

### Info popups — ShowInfoPopup(title, body, imgPath)

`DFrame` flotante (260 × 185 con imagen, 260 × 110 sin imagen), draggable, `SetDeleteOnClose(true)`. Abre sobre click del botón `"?"`.

**Trivia de clase (CLS_TRIVIA, texto en inglés):**
8 entradas, una por clase. Incluye umbral de penetración, descripción de lo que detiene, equivalente NIJ aproximado donde aplica. Sin imagen.

**Trivia de material (MAT_TRIVIA, texto en inglés):**
8 entradas. Cada entrada: `name` (display), `body` (descripción + stats `coefDestruc`/`blunt`), `img` (path sin extensión para `DImage:SetImage`).

### Imágenes de material

8 pares VTF/VMT en `materials/ads/`. Generadas con Midjourney (proporción 13:4, redimensionadas a 512×128 antes de importar a VTFEdit). `.vmt` usa shader `UnlitGeneric` + `$translucent 1`.

| Key | Archivo | Concepto visual |
|---|---|---|
| aramid | `mat_aramid` | Tejido Kevlar amarillo, macro |
| titanium | `mat_titanium` | Metal cepillado azulado |
| ceramic | `mat_ceramic` | Plato gris B&N agrietado, polvo |
| poly_ceramic | `mat_poly_ceramic` | Placas hexagonales negras íntegras con venas cian (HEV) |
| nano_titanium | `mat_nano_titanium` | Slab de gel translúcido plateado semi-sólido |
| electrified_aramid | `mat_electrified_aramid` | Tejido amarillo con arco eléctrico azul |
| m_stf | `mat_m_stf` | Fluido oscuro viscoso a media salpicadura |
| uranium_matrix | `mat_uranium_matrix` | Placa facetada verdosa estilo sci-fi (Halo), agrietada en segmentos |

`DImage:SetImage(tr.img)` — path relativo a `materials/`, sin extensión. Source encuentra el `.vmt` automáticamente.

### Bugs resueltos por la migración

| Bug | Causa raíz | Solución |
|---|---|---|
| Sliders Clase y Dur Max invisibles | `DNumSlider` colapsa a < 30 px con `SetTall(22)` | Clase → 8 DButton; Dur Max → DNumSlider `SetTall(30)` |
| Clase no snapeaba a enteros | Drag continuo de DNumSlider ignora `SetDecimals(0)` visualmente | 8 DButton son discretos por diseño |
| Material mostraba key interno | `AddChoice(mat, mat)` | `AddChoice(MAT_DISPLAY[mat], mat)` |

**Nota de corrección (sesión §17):** la fila "Dur Max" de esta tabla describe el fix *intermedio* (`DNumSlider` a `SetTall(30)`). Ese fix quedó superado en la sesión de §17: `DNumSlider` fue eliminado también de Dur Max (zona + fallback_generic), reemplazado por el patrón `DPanel` + `DLabel` + `DTextEntry` numérico + `DSlider` (`durRow`/`durEntry`/`durSlider`, con función `durSetValue(v)` y flag `durUpdating` para evitar loops de callback entre el slider y el entry). El mismo patrón se usa en el toolgun (`ads_config.lua`) y en el tab Weapons (§18). Ver §17 para el detalle y para el remanente conocido (`MakeSlider` del tab Limbs/WL aún no migrado).

---

## 17. Sesión — UI Cleanup: Dur Max global, Inspect extendido, Toolgun debug puro, Rename

Cuatro bloques cerrados y verificados en una misma sesión, documentados aquí en conjunto por tamaño (ninguno individualmente justificaba una sección propia).

### A — Dur Max fila manual en todo ADS

`DNumSlider` reemplazado en el editor de zona y el bloque `fallback_generic` del Armor tab (`cl_ads_browser.lua`), y espejado en el editor de armadura del toolgun (`ads_config.lua`). Patrón final:

```lua
local durRow = vgui.Create("DPanel", editorPanel)
durRow:Dock(TOP) durRow:SetTall(20) durRow:DockMargin(0, 2, 0, 0)
durRow.Paint = function() end
local durLabel = vgui.Create("DLabel", durRow)
durLabel:Dock(LEFT) durLabel:SetWide(52) durLabel:SetText("Dur Max")
local durEntry = vgui.Create("DTextEntry", durRow)
durEntry:Dock(RIGHT) durEntry:SetWide(36) durEntry:SetNumeric(true)
local durSlider = vgui.Create("DSlider", durRow)
durSlider:Dock(FILL)
```

`durSetValue(v)` clampa y sincroniza `SetSlideX` + texto del entry; `durUpdating` evita que `OnValueChanged` del slider y `OnEnter`/`OnLostFocus` del entry se disparen entre sí en loop. Este patrón es el que usan Prompt 3 de §18 (Weapons tab) y el resto de sliders numéricos nuevos de ADS.

**Remanente conocido:** `MakeSlider` en `BuildWLTab` (tab Limbs/WL del browser — `head_hp_frac`, `arms_hp_frac`, `legs_hp_frac`, `limb_damage_transfer_*`, `mult_*`) **no fue migrado** en esta sesión y sigue usando `DNumSlider`. No confirmado en juego si colapsa (depende del `SetTall` real en runtime); flaggeado en backlog §13.

### B — Inspect extendido (Reload / tecla R)

`ADS.InspectNPC` (`ads_core.lua`) agrega tres campos:

| Campo | Tipo | Origen |
|---|---|---|
| `is_whitelisted` | bool | `ADS.UserWhitelist[classname] ~= nil` |
| `armor_slots` | tabla `[hgString] = {class, dur, dur_max, material}` | NWvars, uno por slot 0-7 con `class > 0`. Solo presente si `ADS_Armor_Init` |
| `tool_override` | bool | `ent.ADS_ToolArmorOverride == true` (ver §C) |

Cliente (`ads_config.lua`, `net.Receive("ads_inspect_result")`): notificación en pantalla acotada a Armored + Whitelisted; dump completo (incluyendo `armor_slots` por zona con nombre legible y flag `[MANUAL OVERRIDE ACTIVE]`) va a consola.

### C — Toolgun refactor: debug puro

`ads_config.lua` pierde whitelist/blacklist/save/reload/JSON — todo eso vive ahora solo en el browser. Rol nuevo: panel de debug per-entity, efímero.

| Net string | Dirección | Función |
|---|---|---|
| `ads_tool_apply` (M1) | cliente → server | Lee `ent`, flags `doArmor`/`doLimbs`, `profile` del panel, `hf/af/lf`. Si `doArmor`: `ADS.ApplyArmorDirect(ent, profile)` + `ent.ADS_ToolArmorOverride = true`. Si `doLimbs`: `ADS.ResizeLimbPools(ent, hf, af, lf)`. **No persiste a JSON.** |
| `ads_tool_copy` (M2) | cliente → server | Lee NWvars de armadura + fracciones de limbs del NPC apuntado |
| `ads_tool_copy_result` | server → cliente | Responde a M2; puebla `toolState.armor` y refresca el panel |

**Caveat vigente:** `ADS_ToolArmorOverride` es volátil — `InitArmorNWvars` lo pisa en cualquier re-init (p. ej. si el browser guarda perfil de esa clase mientras el override manual sigue activo en esa instancia).

### Rename

Frame renombrado de "ADS NPC Browser" a **"ADS Configuration"** — shell de pestañas pensado para alojar subsistemas futuros. El toolgun abre el mismo frame vía botón "Open Configuration" → `ADS_Browser.Open()`. La pestaña Weapons (§18) es el primer subsistema nuevo alojado en este shell desde el rename.

---

## 18. Block 7 — Weapon Penetration Modifier: Curated Weapons + Ammo Fallback

### Motivación

Hasta este bloque, la tabla curada (`ADS.CuratedWeapons`) solo se consultaba para armas ARC9 sin data EFT (`istable(ARC9)` como guard en `ExtractBulletData`). Un `weapon_vj_ak47` o `tfa_m4a1` nunca llegaba a esa rama — caían directo al fallback por ammo type (Branch 3), con la granularidad gruesa de 6 buckets. Ejemplo real: `weapon_vj_ak47` declara `Primary.Ammo = "SMG1"`, resolviendo al bucket `smg` (penPower 28) cuando debería comportarse como rifle (~42). El pedido explícito de Matías fue: un modificador de penetración de armas en ADS Configuration que afecte **tanto a jugador como a NPC portando la misma arma**, dado que ambos casos convergen en el mismo `wep:GetClass()` leído por `ScaleNPCDamage`/el detour de ARC9 — no hace falta un pipeline separado.

### Investigación previa a cerrar el diseño

- **`weapon_vj_base` (`shared.lua`):** dispara vía `owner:FireBullets(bullet)` con `bullet.AmmoType = Primary.Ammo`. Confirma que el fix de rehierarquización de `ExtractBulletData` corrige el AK47 VJ sin tocar el arma.
- **ARC9 en manos de NPC (`sh_npc.lua`, base ARC9):** `NPC_PrimaryAttack` llama `self:DoProjectileAttack(...)` — el mismo path de disparo que el jugador. El detour de `AfterShotFunction` (Block 3, §12) debería depositar el stash igual para NPCs portando ARC9 (vía scavenger o `arc9_givenpcweapon`). No confirmado empíricamente en esta sesión — ver caso borde abajo.
- **Página de features de ARC9 + `cl_npc.lua`/`sv_npc.lua`:** confirman soporte NPC nativo de ARC9 (`ARC9.AttemptGiveNPCWeapon`, `ARC9.ReplaceSpawnedWeapon`, `ARC9.PopulateWeaponClasses` filtra por `NotForNPCs`).

### Archivos modificados

| Archivo | Cambios |
|---|---|
| `ads_armor.lua` | `ADS.AmmoFallbackDefaults` (inmutable) + `ADS.AmmoFallback` (copia viva). `ExtractBulletData` rehierarquizado: Branch 2 (curada) ya no requiere `istable(ARC9)`, `source` pasa de `"arc9"` a `"curated"`. Nuevas: `ADS.SanitizeAmmoFallback`, `ADS.GetAmmoFallbackOverrides`, `ADS.SanitizeCuratedWeapon`. `LoadArmorData` resetea y aplica overrides de `ammo_fallback` |
| `ads_core.lua` | `SaveConfig` agrega key `ammo_fallback`. +4 net strings (`ads_request_weapons_data`, `ads_weapons_data`, `ads_save_curated`, `ads_save_ammo_fallback`) + `SendWeaponsDataTo` + 3 handlers. `ScaleNPCDamage`: fallback inline (`inline_arc9`) cuando la rama `isARC9` no tiene stash válido |
| `cl_ads_browser.lua` | 4ta pestaña **Weapons** en `BuildRightPanel`: catálogo client-side vía `weapons.GetList()`, editor compartido (Pen. Power / Armor Dmg / Pen. Chance, fila manual — mismo patrón que §17-A), sección Ammo Defaults (6 buckets editables) |

### Jerarquía del extractor (post-Block 7)

```
1. ¿wep trae HasAmmoooooooo == true?  → EFT en vivo. source = "eft". (sin cambios — ARC9 sigue siendo dueño)
2. ¿IsValid(wep)?  → tabla curada por wep:GetClass(). Cualquier base. source = "curated".
3. Fallback por ammo type (bucket editable). source = "fallback" | "tfa".
```

EFT sigue ganando siempre que el round lo traiga — coherente con el principio de dominio de §3 (ADS lee EFT, nunca escribe). Una entrada curada sobre un arma ARC9 actúa como *fallback mejorado* para cuando esa arma no porta munición EFT, no como override de EFT.

### Rangos de clamp

| Campo | Rango | Notas |
|---|---|---|
| `penPower` | 1–115 | Techo alineado a la escala EFT extendida confirmada (.50 BMG SLAP ≈ 115) |
| `armorDamage` | 1–120 | |
| `penChanceBase` | 0–1 (2 decimales) | |

### Net strings

| Mensaje | Dirección | Contenido |
|---|---|---|
| `ads_request_weapons_data` | cliente → server | (vacío) |
| `ads_weapons_data` | server → cliente | `WriteTable(CuratedWeapons)` + `WriteTable(AmmoFallback)` — también sirve de ACK tras `ads_save_curated`/`ads_save_ammo_fallback` |
| `ads_save_curated` | cliente → server | `WriteString(classname)` + `WriteTable(data)` (`{}` = borra la entrada) |
| `ads_save_ammo_fallback` | cliente → server | `WriteTable(payload)` — los 6 buckets completos; el server sanitiza y reemplaza `ADS.AmmoFallback` entero |

### Tab Weapons — UI

Catálogo construido client-side desde `weapons.GetList()` (sin net) — clasificado por base (`arc9`/`vj`/`other` vía `weapons.IsBasedOn`, `tfa` vía prefijo de classname, ya que no hay confirmación de un classname base único de TFA en este proyecto). Filtro por búsqueda + base. Click en una fila carga el editor compartido (mismo patrón "click → editor único" que el Armor tab de §16). Badge por fila: `Curated` (verde) o `Fallback` (gris). Nota contextual cuando la fila seleccionada es ARC9, aclarando que EFT en vivo sigue ganando.

Sección **Ammo Defaults**: los 6 buckets con fila manual (Pen/Arm/Chn) + botón global de guardado + botón de reset a `CLIENT_AMMO_DEFAULTS` (espejo del lado cliente, sin round-trip de red para el reset visual — el guardado real sigue yendo al server).

### Caso borde abierto — NPC disparando ARC9

Si un NPC dispara ARC9 (scavenger o `arc9_givenpcweapon`) y el detour de `AfterShotFunction` no llega a depositar stash a tiempo (timing de frame, o el path de NPC no pasa por ahí como se asume), `ScaleNPCDamage` caía antes en `no_stash`/`stash_MISS` y la bala pasaba sin filtrar por armadura. El fallback inline (`armorPath = "inline_arc9"`) resuelve la armadura en ese caso igual que el branch no-ARC9, sin zeroing de `penleft` (degradación aceptada: la bala penetrante sigue atravesando paredes con toda su energía aunque la placa haya bloqueado el daño a carne). Pendiente de confirmar en juego cuál de los dos paths (`stash` vs `inline_arc9`) ocurre realmente — ver test sugerido en el handoff de esta sesión.

---

 Refleja: editor de zonas por hitgroup, modelo de template con Copy Selected y doble-click, 4 tabs (Armor/Limbs-WL/Weapons/General), batch apply de armor, idempotencia de `InitArmorNWvars`, fix de overflow de catalog_state, refactor del Armor tab a silueta clickeable, toolgun refactorizado a debug puro, inspect extendido, rename a "ADS Configuration", Weapon Penetration Modifier (tabla curada abierta + Ammo Fallback editable), y diseños diferidos (Block 6, Front 4, probe de hitgroups, armadura de jugador, migración pendiente de `MakeSlider`/Limbs-WL).*
