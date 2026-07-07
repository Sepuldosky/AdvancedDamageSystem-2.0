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

## PARCHES DE sesión Limbs × VJ Base — Bloque C: animación de pickup del scavenger — 2026-07-07

Sesión de diseño: `TryPickupAnimation` (`ads_scavenger.lua`) usaba `ResetSequence`/
`SetCycle` crudos, que el FSM Lua de VJ (`RunAI`, 0.1 s) pisa al siguiente tick — en
NPCs VJ la animación de recogida no se veía. VJ no trae ningún schedule de "recoger
arma del piso" (0 hits de pickup para NPCs en su árbol; su sistema solo cubre players);
la palanca correcta es `PlayAnim` (vía alias `VJ_ACT_PLAYACTIVITY`): interrumpe el
schedule en curso (StopMoving + ClearSchedule), bloquea chase/idle/ataques con
lockAnim, valida con `VJ.AnimExists` (no-op puro con dur=0 si el modelo no tiene la
animación) y devuelve la duración real como segundo valor. `ACT_PICKUP_*` no colisiona
con la tabla run→walk del Bloque B (PlayAnim pasa por `TranslateActivity`, core.lua
L706, pero esas keys no están mapeadas).

- PARCHE 1 — Rama VJ en `TryPickupAnimation` (`ads_scavenger.lua`): tabla
  `PICKUP_ANIMS_VJ` ({ACT_PICKUP_GROUND, ACT_PICKUP_RACK, "pickup", "pickup_weapon",
  "physgun_pickup"}, mismo orden de preferencia que el path nativo); loop con
  `VJ_ACT_PLAYACTIVITY(anim, lockAnim=true, lockAnimTime=false, faceEnemy=false)` y
  primera duración > 0 gana; 0 = equipar de inmediato (contrato existente intacto:
  `doEquip` al 70% de la duración). Path nativo sin cambios. **[APLICADO 2026-07-07]**
  — verificado en juego por el autor. Criterios: NPC VJ desarmado llega al arma,
  reproduce la animación de agacharse (citizen/rebel con secuencia "pickup"), el
  equip aterriza durante la animación, y un modelo sin animación (Combine) equipa
  al instante sin trabarse; confirmar que el lock no deja al NPC pegado si el equip
  falla (cooldown post-drop de 8 s ya cubre el re-scan).

---

## PARCHES DE sesión Limbs × VJ Base — Bloque B: cojera por traducción de activities — 2026-07-07

Sesión de diseño: el slow de piernas era inefectivo en NPCs VJ — usan el motor de
pathing NATIVO (`TASK_RUN_PATH` como engine task real) cuya velocidad sale del root
motion de la animación de locomoción, recalculada por el motor en su propio tick; el
`SetLocalVelocity` a 20 Hz de ADS competía y perdía (jitter), y `m_flGroundSpeed` no
lo lee nada en VJ (0 hits en su árbol). `SetPlaybackRate` se descartó (propuesta
original del bloque): VJ lo detourea hacia `AnimPlaybackRate` (`funcs.lua` L872) y eso
escala TODAS las animaciones (recarga, ataque) y sus timers. Palanca elegida: el
sistema de **traducción de activities** de VJ (`ENT:TranslateActivity` +
`AnimationTranslations`, `npc_vj_human_base/init.lua` L2417) — degradar run→walk antes
de la traducción conserva las variantes de arma/aim (las ramas internas re-llaman
`self:TranslateActivity`), y el root motion baja la velocidad real sin pelear con nadie.

- PARCHE 1 — Cojera VJ (`ads_limbs.lua`): convar `ads_limb_vj_limp_threshold` (0.7);
  tabla `VJ_RUN_TO_WALK` (RUN/AIM/AGITATED/CROUCH/CROUCH_AIM/PROTECTED → walk
  equivalente); `InstallVJLimpTranslator` = wrapper per-entity de `TranslateActivity`
  (idempotente, inerte con `ADS_VJ_Limping=false`, sobrevive a
  `UpdateAnimationTranslations` porque no toca la tabla de VJ) con bonus: si VJ
  devuelve `ACT_WALK` pelado y el modelo tiene `ACT_WALK_HURT` (citizens HL2), usa la
  animación de herido — cojera visible. En `ApplyLimbDebuffs`: toggle edge-triggered
  bajo el umbral con nudge `StopMoving()` (re-traduce la locomoción en curso) y dprint
  `vj_limp_on/off`; `m_flGroundSpeed` y el Think de `SetLocalVelocity` quedan solo
  para NPCs no-VJ-humanos (creatures VJ = deuda conocida, sin cojera).
  **[APLICADO 2026-07-07]** — verificado en juego por el autor. Criterios:
  `vj_limp_on` al romper una pierna, el NPC
  pasa de correr a caminar (variante de arma correcta al apuntar), citizen con
  hurt-walk cojea, cura revierte (`vj_limp_off`), y recarga/ataque a velocidad normal.

---

## PARCHES DE sesión Limbs × VJ Base — Bloque A: head stun por flinch nativo — 2026-07-07

Sesión de diseño: investigación de la arquitectura real de VJ Base (fuente en
`vjbaseactual/`, copia de referencia — no se carga en juego) concluyó que el stun de
cabeza de `ads_limbs` era inefectivo en NPCs VJ: `RunAI()` de VJ es un FSM Lua propio
que ignora `SetSchedule` nativo; `IsGuard` solo afecta la PRÓXIMA selección de schedule
(no interrumpe nada en curso); y `VJ_ACT_PLAYACTIVITY(ACT_*_FLINCH)` falla mudo si el
modelo no tiene esa activity. VJ trae un sistema de flinch nativo por hitgroup
(`ENT:Flinch`, `vj_base/ai/core.lua` L2594, llamado automáticamente en su
`OnTakeDamage`) con constante de bypass a propósito: `VJ.DMG_FORCE_FLINCH`
("Causes NPCs to always flinch", `enums.lua` L44). Bloques B (cojera de piernas) y
C (animación de pickup del scavenger) diseñados pero fuera de esta sesión.

- PARCHE 1 — Rama VJ de `ApplyHeadStun` (`ads_limbs.lua`) reescrita: fuera
  `IsGuard`/`StopMoving`/`VJ_ACT_PLAYACTIVITY` + timer de restore; ahora marca el
  daño con `dmginfo:SetDamageCustom(VJ.DMG_FORCE_FLINCH)` (llamada a método, no
  inyección de campo — contrato intacto) para que el propio `Flinch()` de VJ ejecute
  la animación correcta del modelo (`FlinchHitGroupMap`/`AnimTbl_Flinch`) con lock
  real de schedule/ataques. Detalles: habilita `CanFlinch` si estaba apagado con
  `FlinchChance = 1e9` (el roll aleatorio queda inerte, solo dispara el forzado);
  limpia `NextFlinchT` (el guard de cooldown corre ANTES del bypass); el stun severo
  (25%) además limpia `Flinching`/`AnimLockTime` para pisar un flinch activo; no pisa
  un `DamageCustom` ajeno (DMG_BLEED). `dmginfo` viaja `ProcessLimbHit` →
  `ApplyLimbDebuffs(npc, reason, dmginfo)` → `ApplyHeadStun` (spawn/heal pasan nil →
  no stun, correcto). Las convars `ads_limb_head_stun_*_duration` quedan solo para
  NPCs nativos: en VJ la duración la manda la animación de flinch.
  **[APLICADO 2026-07-07]** — verificado en juego por el autor. Criterios: buscar
  `stun_vj_flinch 50/25` al cruzar
  umbrales de cabeza en un NPC VJ, confirmar que la animación interrumpe ataque y
  movimiento, y que NPCs con `CanFlinch=false` de fábrica no flinchean aleatoriamente
  con daño normal.

---

## PARCHES DE sesión Fix copy de armadura por doble-clic — 2026-07-07

Sesión de fix: el doble-clic sobre un NPC en la lista del browser no copiaba las **placas
de armadura** de un NPC ya blindado al template (solo funcionaba tras guardar armadura vía
"Whitelist Selected"). Causa: `ads_request_armor` devuelve `ADS.ArmorProfiles[classname]`
(perfil de **clase**), no la armadura viva del NPC; si la clase no tiene perfil vigente al
momento del copy, respondía vacío y la silueta quedaba sin zonas.

- PARCHE 1 — `ADS.ReadArmorNWvars(ent)` (`ads_armor.lua`): función pura nueva que lee la
  armadura viva de una entidad desde sus NWvars a tabla de perfil (`zones` +
  `fallback_generic`, usando MaxDur para arrancar con placas llenas). Factoriza el bloque
  inline que ya usaba `ads_tool_copy`. `ads_request_armor` (`ads_core.lua`) ahora cae a esa
  lectura sobre una instancia viva blindada (`ents.FindByClass`) cuando
  `ADS.ArmorProfiles[classname]` está vacío, con `dprint(2)` (`source=profile|live`);
  `ads_tool_copy` reutiliza el helper. **[PENDIENTE]** — verificar en juego con `ads_debug 2`
  que el doble-clic copia las zonas sin whitelist previo (`source=live`).

- PARCHE 2 — Normalización de claves de zonas al cargar del JSON (`ads_armor.lua`
  `LoadArmorData`): la verificación en juego del PARCHE 1 (2026-07-07) reveló el caso
  restante — el **primer** doble-clic sobre una clase ya whitelisted (perfil persistido)
  seguía copiando vacío y funcionaba recién tras re-guardar. Causa: `util.JSONToTable`
  convierte las claves numéricas de objeto JSON (`"1"`.."7"`) en **números** de Lua, y
  `LoadArmorData` guardaba el perfil verbatim → `ads_request_armor` mandaba `zones[1]`
  numérico y el browser (que indexa `zones["1"]` string, igual que `SanitizeArmor` y el
  data model §8) renderizaba nada; al guardar, `SanitizeArmor` re-normalizaba a string y
  por eso los copies siguientes sí funcionaban. El runtime nunca lo notó porque
  `InitArmorNWvars`/`ApplyArmorDirect` hacen `tonumber(k)` tolerante. Fix:
  `LoadArmorData` reconstruye `profile.zones` con `tostring(k)` al ingerir `parsed.armor`.
  **[PENDIENTE]** — verificar en juego: recargar mapa (perfiles desde JSON), primer
  doble-clic sobre clase whitelisted con armadura puebla la silueta (`ads_debug 2`,
  `source=profile`, y las zonas aparecen sin re-guardar).

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

## PARCHES DE sesión Feedback sonoro de armadura por material — 2026-07-06

Sesión de diseño: el "efecto metálico" al impactar armadura (único: sonido, sin
partículas) pasa a depender del **material** de la placa; se añaden sonidos de
**headshot** estilo CS y de **gunshotblocked**, cada uno con su toggle. Sonidos custom
del usuario movidos a `sound/ads/`. Todo dentro del alcance NPC-only existente
(`ScaleNPCDamage`). Decisiones: cuerpo → solo materiales **duros** suenan (blandas =
aramida/`electrified_aramid`/`m_stf` = silencio); cabeza blindada → **reemplaza** el
sonido de bloqueo por el ding de headshot; Hard/Light por **bloqueo vs. penetración**.

- PARCHE 1 — Flag `hard` por material (`ads_armor.lua`): campo estático nuevo en
  `ADS.Materials` (duros: titanium/ceramic/poly_ceramic/nano_titanium/uranium_matrix;
  blandos: aramid/electrified_aramid/m_stf). No lo usa la matemática del resolver, solo
  el feedback sonoro. Respeta el contrato de pureza (tabla estática). **[PENDIENTE]**

- PARCHE 2 — Orquestador `PlayArmorSounds` (`ads_core.lua`): reemplaza `PlayHitSound`.
  Recibe `(npc, hg, material, blocked, dur)` y decide qué suena. Clang metálico
  (`physics/metal/metal_solid_impact_bullet*`) ahora gateado por `mat.hard` — placas
  blandas mudas. Se añade `material = zona.material` al `ADS_ArmorStash` del detour ARC9
  para que el path stash conozca el material. Los 3 call sites (stash / inline_arc9 /
  inline) llaman al orquestador **siempre que se resolvió armadura** (antes solo en
  bloqueo), y esto **normaliza** la asimetría previa (el path stash sonaba también en
  penetración de cuerpo; ahora el cuerpo solo suena al bloquear en los 3 paths).
  **[PENDIENTE]**

- PARCHE 3 — Sonido gunshotblocked (`ads_core.lua`): al bloquear con placa dura suena
  `sound/ads/GunshotBlocked.wav` / `GunshotBlocked2.wav` (aleatorio). Convar
  `ads_gunshotblocked_enabled` (1). **[PENDIENTE]**

- PARCHE 4 — Sonido de headshot (`ads_core.lua`): impacto a **cabeza con armadura**
  reproduce `sound/ads/HeadshotHard.wav` si el casco bloquea o `HeadshotLight.wav` si
  penetra, y **reemplaza** gunshotblocked+clang en la cabeza (suena aunque el casco sea
  material blando). Convar `ads_headshot_sound_enabled` (1); con el toggle off, la
  cabeza cae a la lógica normal de cuerpo. **[PENDIENTE]**

- PARCHE 5 — UI + assets: checkboxes "Enable Gunshot-Blocked Sound" y "Enable Headshot
  Sound" (+ resets) en el panel Armor de `cl_ads.lua`; los 4 `.wav` movidos de `sound/`
  a `sound/ads/` (referenciados como `ads/<archivo>.wav`, precache en carga).
  **[PENDIENTE]**

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
