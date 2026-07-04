# ADS 2.0 — Estado de HOY

> **Foto del AHORA**, volátil. Es lo primero que se lee al retomar el proyecto —
> **antes** que el doc de arquitectura. Se actualiza **en sitio** (no se agregan
> secciones ni historial). El historial vive en `git` + [`CHANGELOG.md`](CHANGELOG.md).
> Si crece de una pantalla, está mal redactado: recortar.

**Última actualización:** 2026-07-04

---

## Qué existe hoy (operativo en el código)

Fase 1 completa. Todo el pipeline de blindaje zonal está en el árbol (commit inicial):

- **Extractor** (`ads_armor.lua`): jerarquía de 3 branches — EFT en vivo → tabla curada
  (cualquier classname) → fallback por ammo type. Función pura.
- **Resolver** (`ads_armor.lua`): pasos 0–4 (doble compuerta → penChance → roll → blunt /
  post-pen → handoff). Función pura. Bloque de **auto-test comentado** al final del
  archivo (`ads_armor_deterministic 1`) para validar la matemática.
- **Rip-out 1.x completo:** `ADS_Armor` pool único, `ProcessArmor`, `RollArmor` **no
  existen**. La autoridad es `ADS.ArmorProfiles[classname]`.
- **Call sites:** VJ/HL2 vía `ScaleNPCDamage`; ARC9 vía detour de `AfterShotFunction`
  (+ fallback inline `inline_arc9` cuando falta el stash).
- **NWvars por zona** (`ADS_Armor_*_<hg>`), sync síncrono en el mismo tick.
  `InitArmorNWvars` idempotente.
- **Data model:** JSON `data/ads/ads_config.json` con `{whitelist, blacklist, armor,
  curated_weapons, ammo_fallback}`.
- **`ads_limbs`:** drop de arma solo en `HITGROUP_RIGHTARM`.
- **Browser "ADS Configuration"** (`cl_ads_browser.lua`): 4 tabs
  (Armor silueta clickeable / Limbs-WL / Weapons / General), modelo de template,
  Copy Selected, doble-click, batch apply.
- **Toolgun** (`ads_config.lua`): debug puro per-entity (M1/M2/Reload), no toca el JSON.
- **Block 7 — Weapon Penetration Modifier:** tabla curada abierta a cualquier base,
  Ammo Fallback editable (6 buckets), tab Weapons, contrato de red completo. **Código
  aplicado** (presente en `ads_armor.lua` / `ads_core.lua` / `cl_ads_browser.lua`).

## Pendiente de verificar en juego

- **Block 7 — NPC disparando ARC9:** confirmar empíricamente cuál path ocurre
  (`path=stash` del detour vs. `path=inline_arc9`) cuando un NPC (scavenger /
  `arc9_givenpcweapon`) dispara ARC9. El código cubre ambos; falta la confirmación real
  con `ads_debug 3`. Ver §18 (caso borde abierto) del doc de arquitectura.

## Remanentes / deuda conocida

- **`MakeSlider` del tab Limbs/WL** (`cl_ads_browser.lua`, ~L1246) sigue usando
  `DNumSlider` — no migrado al patrón de fila manual (`durRow`/`durEntry`/`durSlider`)
  que ya usan Armor tab, toolgun y Weapons tab. No confirmado si colapsa en runtime.
- **Front 4 — doble mult de zona ARC9:** ARC9 EFT aplica sus `BodyDamageMults` antes de
  `ScaleNPCDamage` y `ApplyDamageMultiplier` de ADS los vuelve a escalar → miembros
  reciben ~50% menos daño del esperado. Sin corregir (diferido a Fase 2).
- **Cache de hitgroups por modelo (§7):** diferido a Fase 2 — la silueta usa template
  humano fijo de 7 zonas; sin auto-grisado de zonas imposibles.

---

*Rumbo / qué sigue → [`ads_roadmap.txt`](ads_roadmap.txt). Diseño de referencia →
[`ADS_2_0_Architecture_updated.md`](ADS_2_0_Architecture_updated.md). Metodología →
[`ads_flujo_trabajo.txt`](ads_flujo_trabajo.txt).*
