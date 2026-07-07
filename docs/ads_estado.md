# ADS 2.0 — Estado de HOY

> **Foto del AHORA**, volátil. Es lo primero que se lee al retomar el proyecto —
> **antes** que el doc de arquitectura. Se actualiza **en sitio** (no se agregan
> secciones ni historial). El historial vive en `git` + [`CHANGELOG.md`](CHANGELOG.md).
> Si crece de una pantalla, está mal redactado: recortar.

**Última actualización:** 2026-07-07

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
- **`ads_limbs`:** drop de arma al vaciarse el pool de **cualquier brazo** (L o R);
  el drop marca el arma para el scavenger (`MarkWeaponAsDroppedBy` +
  `RecordOwnWeaponDrop`).
- **`ads_scavenger`:** pesos auto (DPS o slot-fallback) + overrides por classname
  (JSON propio); **modo "recuperar arma propia"** (`ads_scavenger_retrieve_own`):
  armado nunca cambia de arma, desarmado prioriza la suya (delay/timeout convars) y
  cae al scavenger normal si falla; nunca-armados no recogen nada en ese modo.
- **Browser "ADS Configuration"** (`cl_ads_browser.lua`): 5 tabs
  (Armor silueta clickeable / Limbs-WL / Weapons / Scavenger / General), modelo de
  template, Copy Selected, doble-click, batch apply. Tab Scavenger edita los
  overrides de peso (contrato net propio, admin-gated).
- **Toolgun** (`ads_config.lua`): debug puro per-entity (M1/M2/Reload), no toca el JSON.
- **Feedback sonoro de armadura** (`ads_core.lua` `PlayArmorSounds`): clang metálico
  solo en materiales **duros** (`ADS.Materials[*].hard`); placas blandas (aramida /
  `electrified_aramid` / `m_stf`) en silencio. Bloqueo de cuerpo → `sound/ads/
  GunshotBlocked*`; cabeza blindada → `HeadshotHard` (bloquea) / `HeadshotLight`
  (penetra), reemplaza al sonido de bloqueo. Toggles `ads_sound_enabled` /
  `ads_gunshotblocked_enabled` / `ads_headshot_sound_enabled`.
- **Block 7 — Weapon Penetration Modifier:** tabla curada abierta a cualquier base,
  Ammo Fallback editable (6 buckets), tab Weapons, contrato de red completo. **Código
  aplicado** (presente en `ads_armor.lua` / `ads_core.lua` / `cl_ads_browser.lua`).

## Pendiente de verificar en juego

- **Sesión Limbs × VJ — Bloques A, B y C (3 parches `[PENDIENTE]`):**
  **A** — stun de cabeza VJ ahora fuerza el **flinch nativo** (`DMG_FORCE_FLINCH` sobre
  el dmginfo en `ApplyHeadStun`; fuera `IsGuard`/`VJ_ACT_PLAYACTIVITY`, que no
  interrumpían el FSM Lua de VJ). Confirmar con `ads_debug 2` (`stun_vj_flinch 50/25`)
  que la animación interrumpe ataque/movimiento y que no hay flinch aleatorio en NPCs
  con `CanFlinch=false`. Duración VJ = animación (convars `_stun_*` solo nativos).
  **B** — cojera VJ humano por **traducción de activities** (wrapper per-entity de
  `TranslateActivity`, run→walk + `ACT_WALK_HURT` si el modelo la tiene; umbral
  `ads_limb_vj_limp_threshold` 0.7). Confirmar `vj_limp_on/off`, correr→caminar con
  variante de arma, y recarga/ataque a velocidad normal. Creatures VJ sin cojera (deuda).
  **C** — animación de pickup del scavenger en VJ vía `VJ_ACT_PLAYACTIVITY` con lock
  (fuera `ResetSequence` crudo, que el FSM pisaba). Confirmar con `ads_scavenger_debug 1`
  la animación de agacharse + equip al 70%, y equip instantáneo en modelos sin anim.
- **Copy de armadura por doble-clic (browser):** `ads_request_armor` ahora cae a leer la
  armadura viva de una instancia blindada (`ADS.ReadArmorNWvars`) cuando la clase no tiene
  perfil en `ADS.ArmorProfiles` — así el doble-clic copia las placas sin exigir un whitelist
  previo. Confirmar en juego con `ads_debug 2` (`source=live` vs `source=profile`).
- **Block 7 — NPC disparando ARC9:** confirmar empíricamente cuál path ocurre
  (`path=stash` del detour vs. `path=inline_arc9`) cuando un NPC (scavenger /
  `arc9_givenpcweapon`) dispara ARC9. El código cubre ambos; falta la confirmación real
  con `ads_debug 3`. Ver §18 (caso borde abierto) del doc de arquitectura.
- **Sesión Feedback sonoro (5 parches `[PENDIENTE]` en CHANGELOG):** confirmar en juego
  los 3 sonidos por path (stash ARC9 / inline VJ) y material, el mapeo Hard/Light
  (bloqueo vs. penetración) del headshot y que las placas blandas quedan mudas.
  Case-sensitivity de `sound/ads/*.wav` en dedicado Linux (nombres capitalizados).
- **Sesión Scavenger (3 parches `[PENDIENTE]` en CHANGELOG):** recuperación feliz
  (VJ + nativo), fallback por arma tomada/timeout, no-upgrade armado, nunca-armados
  con `force_all 1`, y tab Scavenger (set/remove/eco). Con `ads_scavenger_debug 1`.
  Efecto colateral a confirmar en modo normal: armas de brazo roto ahora scavengeables
  por otros NPCs (dueño bloqueado 30 s).

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
