# ADS 2.0 — CHANGELOG de parches

> Registro de parches al código y a la documentación, por sesión de diseño.
> **Disciplina (heredada de Kontrol):**
> - Un parche nace `[PENDIENTE]` y pasa a `[APLICADO YYYY-MM-DD]` cuando se aplica y
>   verifica. Para código de addon GMod, "verificado" = confirmado en juego (ver
>   [`ads_flujo_trabajo.txt`](ads_flujo_trabajo.txt)).
> - **Nunca** se borra una entrada. **Nunca** se renumera un parche existente.
> - Cada sesión de diseño abre su **propia subsección**, con numeración de parches
>   independiente de otras sesiones.
> - Estado vivo del proyecto → [`ads_estado.md`](ads_estado.md). Lo `[PENDIENTE]` acá
>   debe coincidir con lo pendiente allá.

---

## Pre-changelog — Fase 1 (bloques históricos)

Los bloques de diseño de Fase 1 se cerraron **antes** de existir este CHANGELOG y se
consolidaron en el commit inicial del repo (`27a11ac`, 2026-07-04, "estructura inicial
del addon ADS 2.0 con blindaje zonal EFT"). Se registran aquí como `[APLICADO]` para
dejar traza; el detalle de diseño de cada uno vive en las secciones citadas del doc de
arquitectura.

- PARCHE 1 — Block 1: tablas estáticas, convars, `ExtractBulletData`, `ResolveArmor`
  (arquitectura §5, §11). **[APLICADO 2026-07-04]**
- PARCHE 2 — Block 2: rip-out capa 1.x + capa de datos (`LoadArmorData`,
  `InitArmorNWvars`, `GetZone`) + cableado VJ en `ScaleNPCDamage` (§12). **[APLICADO 2026-07-04]**
- PARCHE 3 — Block 3: call site ARC9 (detour de `AfterShotFunction` + consumo de stash
  en `ScaleNPCDamage`) (§12). **[APLICADO 2026-07-04]**
- PARCHE 4 — Block 4: browser UI, net de armor, editor de zonas, tabs Armor + Limbs/WL
  (§14). **[APLICADO 2026-07-04]**
- PARCHE 5 — Block 5: restructure a 3 tabs, modelo de template, Copy Selected,
  doble-click, batch armor (§15). **[APLICADO 2026-07-04]**
- PARCHE 6 — Block 5.2: Armor tab a silueta clickeable, editor único, info popups,
  imágenes de material (§16). **[APLICADO 2026-07-04]**
- PARCHE 7 — Sesión UI Cleanup: Dur Max fila manual global, Inspect extendido, Toolgun
  a debug puro, rename a "ADS Configuration" (§17). **[APLICADO 2026-07-04]**

---

## PARCHES DE sesión Block 7 — Weapon Penetration Modifier

Sesión de diseño: Curated Weapons abierta a cualquier base + Ammo Fallback editable +
tab Weapons + fallback inline `inline_arc9`. Detalle: arquitectura §18.

- PARCHE 1 — Código: `AmmoFallbackDefaults`/`AmmoFallback`, `ExtractBulletData`
  rehierarquizado (Branch 2 sin guard ARC9), `SanitizeAmmoFallback`,
  `GetAmmoFallbackOverrides`, `SanitizeCuratedWeapon`, `LoadArmorData` con overrides;
  4 net strings + handlers en `ads_core.lua`; tab Weapons en `cl_ads_browser.lua`.
  **[APLICADO 2026-07-04]** — presente en el árbol, consolidado en `27a11ac`.

- PARCHE 2 — Verificación en juego: confirmar con `ads_debug 3` qué path resuelve un
  NPC disparando ARC9 (`path=stash` vs. `path=inline_arc9`) — scavenger /
  `arc9_givenpcweapon`. **[PENDIENTE]** — ver caso borde abierto en §18 y
  [`ads_estado.md`](ads_estado.md).

---

## PARCHES DE sesión Scavenger — Retrieve Own Weapon + UI de pesos — 2026-07-06

Sesión de diseño: modo "recuperar arma propia" (toggle) para el scavenger + cierre del
gap de integración limbs↔scavenger + pestaña Scavenger en el browser para editar los
overrides de peso por classname (antes solo por concommand).

- PARCHE 1 — Integración limbs↔scavenger: `TryDropWeapon` (`ads_limbs.lua`) ahora marca
  el arma dropeada con `ADS.MarkWeaponAsDroppedBy` (ambos intentos: drop real y copia)
  y la registra con `ADS.RecordOwnWeaponDrop`; devuelve la entidad dropeada. Cumple la
  nota de integración que estaba pendiente al final de `ads_scavenger.lua`.
  **[PENDIENTE]** — verificar en juego (efecto colateral esperado en modo normal: armas
  de brazo roto pasan a ser scavengeables por otros NPCs; dueño bloqueado 30s).

- PARCHE 2 — Modo "recuperar arma propia" (`ads_scavenger.lua`): convars
  `ads_scavenger_retrieve_own` (0), `_retrieve_delay` (2 s), `_retrieve_timeout` (20 s,
  cuenta desde el drop). Con el modo activo: NPC armado nunca cambia de arma; NPC
  desarmado prioriza recuperar SU arma (registro `ADS_OwnWeaponDrop` con referencia de
  entidad, reemisión de movimiento cada 1.5 s); si falla (tomada/desaparecida/timeout)
  cae al scavenger normal; NPC que nunca tuvo arma (`ADS_EverArmed`) no recoge nada ni
  con `force_all`. `RecordOwnWeaponDrop` acorta el cooldown post-drop pendiente solo en
  este modo. Toggle + sliders en el panel Scavenger de `cl_ads.lua`. **[PENDIENTE]**

- PARCHE 3 — UI de pesos del scavenger: 3 net strings nuevos en `ads_core.lua`
  (`ads_request_scav_weights` / `ads_scav_weights_data` / `ads_save_scav_weight`, con
  flag `remove` explícito porque peso 0 es legítimo), `ADS.ClearWeaponWeight` público +
  handlers admin-gated en `ads_scavenger.lua` (eco tras guardar), pestaña "Scavenger"
  en `cl_ads_browser.lua` (lista con badge W=/Auto, filtro Overridden only, estimación
  cliente del peso auto, entrada manual de classname server-only). **[PENDIENTE]**

---

## PARCHES DE sesión Metodología de trabajo — 2026-07-04

Portación de la forma de trabajar de Kontrol a ADS: docs vivos (estado/rumbo/changelog)
+ CLAUDE.md como índice + doc de metodología. Adaptado a GLua/GMod.

- PARCHE 1 — Docs nuevos: `ads_estado.md`, `ads_roadmap.txt`, `CHANGELOG.md`,
  `ads_flujo_trabajo.txt`. **[APLICADO 2026-07-04]**
- PARCHE 2 — `CLAUDE.md`: bloque de índice con jerarquía de lectura (estado antes que
  arquitectura). **[APLICADO 2026-07-04]**
- PARCHE 3 — `ADS_2_0_Architecture_updated.md` §13: puntero "estado vigente →
  ads_estado.md". **[APLICADO 2026-07-04]**
