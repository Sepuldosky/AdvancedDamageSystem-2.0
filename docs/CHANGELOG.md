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

## PARCHES DE sesión Fix partículas colorables del escudo (CP4) — 2026-07-08

Sesión de fix: el color custom (`shield_color`) teñía la burbuja pero no las partículas.
El diagnóstico previo (Bloque B, PARCHE 4) concluyó **erróneamente** que el `.pcf` traía el
color horneado y había que reeditarlo en el editor de partículas de Source. Parseando el
árbol DMX del `speedy_energy_shield_colorable_pfx.pcf` (`format pcf 1`) se confirmó lo
contrario: los 14 emisores `spdy_halo_3_custom_*` SÍ son colorables — cada uno tiene un
operador `Remap Control Point to Vector` que escribe al campo 6 (Color) leyendo el
**control point 4** en rango **0-1**. El Lua escribía en **CP1** con rango **0-255** → un
canal que ningún operador lee → CP4 quedaba en cero (negro) → caía al fallback horneado. El
`.pcf` no se tocó; el fix es solo Lua.

- PARCHE 1 — Fix del tintado (`cl_ads_shields.lua`): helper `ApplyShieldColorCP` (única
  fuente del número de CP y la normalización) que setea el color en `SHIELD_COLOR_CP = 4`
  con RGB/255; `TintedParticle` migrado de `SetControlPoint(1, 0-255)` a
  `ApplyShieldColorCP` (cubre impacto y colapso, ya ruteados por el set colorable).
  **[APLICADO 2026-07-08]** — verificado en juego: impacto y estallido del colapso tiñen.

- PARCHE 2 — Recarga tintada (`cl_ads_shields.lua`): campo `customRecharge =
  "spdy_halo_3_custom_shield_recharge"` en los tipos spartan/elite (ya precacheado en
  `ads_shared.lua`); el loop de recarga del Think (CHARGING) usa el set colorable vía
  `CreateParticleSystem` + `ApplyShieldColorCP` cuando hay color custom (siguiendo el
  origen del NPC), con fallback al `ParticleEffectAttach` del set horneado. Antes la recarga
  NUNCA intentaba teñirse — usaba `def.recharge` con plain attach, que no devuelve handle.
  **[APLICADO 2026-07-08]** — verificado en juego: el loop de recarga tiñe del color custom.

- PARCHE 3 — Docs: comentario de `ads_shared.lua` corregido (CP1 → CP4); deuda cosmética
  previa de `ads_estado.md` movida a "pendiente de verificar"; este bloque. Reabre de facto
  el PARCHE 4 del Bloque B (cerrado 2026-07-07 como deuda con diagnóstico incorrecto).
  **[APLICADO 2026-07-08]**

- PARCHE 4 — Arcos del colapso tintados (`cl_ads_shields.lua`): los arcos eléctricos
  persistentes del estado DOWN (`def.arcs`) se adjuntaban con `ParticleEffectAttach` sin
  teñir (verificación de PARCHE 1/2 reveló que eran el único evento que seguía horneado).
  Campo `customArcs = "spdy_halo_3_custom_shield_deplete_arcs"` en spartan/elite (ya
  precacheado); el bloque de arcos del Think usa el set colorable vía `CreateParticleSystem`
  + `ApplyShieldColorCP` cuando hay color custom, con fallback al horneado; se recuerda el
  nombre atacheado (`fx.arcsName`) para que el `StopParticlesNamed` del apagado y `RemoveFX`
  detengan el sistema correcto (custom o baked). **[PENDIENTE]** — verificar en juego que los
  arcos del escudo caído salen del color custom.

Verificación en juego: NPC con `shield_color` bien distinto al default del tipo (p.ej.
spartan con verde puro) → impacto, estallido del colapso y loop de recarga tiñen (PARCHE
1/2, confirmado); NPC sin color custom conserva el set horneado; `ads_shield_fx_particles 0`
apaga todo. Pendiente: arcos persistentes del estado DOWN (PARCHE 4).

---

## PARCHES DE sesión Scavenger crouch + filtro por base + identidad por spawnmenu — 2026-07-08

Sesión de diseño con tres frentes: (a) fallback de agacharse en el pickup del scavenger
para modelos sin animación de pickup (sets combine/metrocop, VJ y nativos); (b) filtro
por base de NPCs (ALL/HL2/GMOD/VJ/DRG/ZBase) en la lista del browser; (c) identidad por
key de spawnmenu — el sandbox taggea `ent.NPCName = <key de list.Get("NPC")>`
(`commands.lua:557`, preservado por duplicator; ZBase ídem), lo que permite configurar
NPCs de addon que spawnean con classname genérico (`npc_citizen`/`npc_combine_s` +
modelo custom). Precedencia: key con config > classname; entries se reemplazan, nunca
se mezclan.

- PARCHE 1 — Crouch fallback del scavenger (`ads_scavenger.lua`): convars
  `ads_scavenger_crouch_fallback` (default 1) y `ads_scavenger_crouch_time` (default
  1.2 s, clamp 0.3–3.0); `TryCrouchFallback` — rama VJ vía `VJ_ACT_PLAYACTIVITY` con
  `lockAnimTime` numérico fijo (las anims de cover/crouch son loop; `ACT_COVER_LOW` se
  traduce por set dentro de PlayAnim), rama nativa vía `SelectWeightedSequence`
  (`ACT_COVER_LOW`/`ACT_COVER_SMG1_LOW`/`ACT_CROUCHIDLE`) + `SCHED_IDLE_STAND`; los dos
  `return 0` de `TryPickupAnimation` ahora caen al fallback. **[APLICADO 2026-07-08]** —
  verificado en juego: VJ con set de animación combine hace la animación de COVER para
  tomar el arma.

- PARCHE 2 — Bugfix latente `BuildCatalog` rama `VJ.NPC_Spawner_Addons`
  (`cl_ads_browser.lua`): `ResolveIconPath(class, data)` usaba variables inexistentes
  del loop (`entry`) → `ResolveIconPath(entry.Class, entry)`. **[APLICADO 2026-07-08]** —
  verificado en juego.

- PARCHE 3 — Filtro por base en la lista de NPCs (`cl_ads_browser.lua`, client-only):
  `DetectBase(class, data, vjList, drgList)` clasifica cada entrada del catálogo
  (orden: ZBase por `ZBaseNPCs`/`ZBaseCategory` ANTES que scripted_ents → DRG por
  `DrGBaseNextbots`/`IsBasedOn drgbase_nextbot` → VJ por flag `IsVJBaseSNPC` del SENT
  o `VJBASE_SPAWNABLE_NPC` → HL2 por `Author == "VALVe"` → GMOD resto); campo
  `Filter.base`, chequeo primero en `RowMatchesFilter`; combobox "Base:" junto al de
  categorías; `RepopulateCategories()` factoriza el poblado del catCombo y lo hace
  base-aware (reemplaza el bloque inline de `Open()` y el add manual del receiver de
  scan-world). **[APLICADO 2026-07-08]** — verificado en juego con VJ/DRG/ZBase montadas.

- PARCHE 4 — Identidad por spawnmenu, núcleo (`ads_core.lua` + stool): helpers
  `ADS.GetConfigKey(ent)` (NPCName si esa key tiene config real, si no classname),
  `ADS.GetOverrideForEnt(ent)` (entry de key > entry de class, sin mezclar) y
  `ADS.IsUserBlacklisted(ent)`; `IsArmored`/`GetArmorReason` con chequeo en capas
  (key primero, luego classname; hardcoded/patrones VJ/autodetect intactos sobre el
  classname); `ApplyDamageMultiplier` e `InspectNPC` (campo nuevo `config_key`,
  impreso por el stool) vía `GetOverrideForEnt`; re-init vivo de `ads_save_armor`/
  `ads_save_armor_batch` y fallback live de `ads_request_armor` matchean también
  `NPCName`; `_dbgPass` acepta `ads_debug_filter <key>`. Contratos de red intactos
  (`GetClassStatus`/`GetOverride` siguen por string). **[APLICADO 2026-07-08]** —
  verificado en juego.

- PARCHE 5 — Identidad por spawnmenu, subsistemas: `InitArmorNWvars`
  (`ads_armor.lua`) resuelve perfil por `GetConfigKey` con fallback al classname
  (lectura pura, contrato intacto); `InitLimbs`/`ProcessLimbHit` (`ads_limbs.lua`) e
  `InitShield` (`ads_shields.lua`) vía `GetOverrideForEnt`; `RefreshShieldsForClass`
  matchea classname o `NPCName`; `RegisterNPC` del scavenger usa `IsUserBlacklisted`.
  **[APLICADO 2026-07-08]** — verificado en juego; ZBase cubierto gratis (clase de
  motor + `NPCName = key zb_*`).

- PARCHE 6 — Textos de la tab Energy Shield a inglés (`cl_ads_browser.lua`,
  `BuildShieldTab`): el label informativo, el checkbox "Can regenerate" y el botón
  "Reset Shield Template" quedaban en español; pasados a inglés (convención de UI del
  mod). Solo strings de UI, sin cambio de lógica. **[APLICADO 2026-07-08]**

- PARCHE 7 — Eliminar el panel "How to use" (`cl_ads.lua`): quitados `BuildHelpPanel`
  y su `spawnmenu.AddToolMenuOption("ADS_Help", ...)` del menú Q. **[APLICADO 2026-07-08]**

---

## PARCHES DE sesión Energy Shields — Bloque C: UI completa — 2026-07-07

Sesión de diseño: capa de configuración de Energy Shields en todas las superficies de
UI existentes, calcando patrones del árbol (filas manuales `manualRow`/
`StyleManualSlider`, nunca DNumSlider en scroll; payload piggyback en
`wl_add_batch`; badges de la tab Weapons). La columna y el copy leen el **cache del
whitelist** que ya llega completo por `ads_send_lists` — cero red nueva. Primer
precedente de `DColorMixer` en el addon (shield_color).

- PARCHE 1 — Columna "Shd" (`cl_ads_browser.lua`): header `cols` (+entrada x=555) y
  `row.PaintOver` (badge `[SHD]` cian cuando `Whitelist[class].shield_type` existe).
  **[APLICADO 2026-07-07]** — verificado en juego.

- PARCHE 2 — Tab "Energy Shield" (`cl_ads_browser.lua`, `BuildShieldTab` + 6º sheet en
  `BuildRightPanel`): checkbox master "Enable Energy Shield on whitelist"
  (client-only, decide si el payload lleva campos — apagado, re-whitelistear LIMPIA
  el escudo: advertido en el label), combo de tipo poblado lazy desde
  `ADS_ShieldFX.Types` (degrada a lista mínima si falta el archivo), filas manuales
  Shield HP [1,5000] / Regen delay [0,60] / Regen rate [0.1,1000], checkbox Can
  Regenerate, checkbox "Use type default color" + `DColorMixer` sin alpha (descarta
  `a`), botón Reset con defaults del tipo (espejo `CLIENT_SHIELD_DEFAULTS`); campos
  `shield_*` en `ADS_Browser.Template` (+"Reset All" del tab General) y en el payload
  de "Whitelist Selected"; `CopyFromClass` copia el escudo del entry (sin resetear
  valores si la clase no trae; `shield_enabled` refleja al copiado) + refresh in-place
  vía `ADS_Browser.ShieldTabRefresh`. **[APLICADO 2026-07-07]** — verificado en juego
  (batch a 2 clases, `[SHD]` en filas, doble-clic puebla el tab). Fix pre-verificación
  (2026-07-07): los setters
  de los 3 sliders llamaban `SetSlideX` → `OnValueChanged` → setter en bucle (stack
  overflow que abortaba `Open()` entero, browser vacío) — guard de reentrada
  `shdUpdating`, el mismo patrón `durUpdating` del tab Armor. Ajustes de la ronda 1
  de verificación (2026-07-07): texto informativo al gris legible del tab Scavenger
  (210,210,210) y combo de tipos con nombres bonitos vía `label` del registry
  ("Spartan" / "Elite Sangheili" / "HEV" — la key interna no cambia).
  **[APLICADO 2026-07-07]** — verificado en juego (batch, doble-clic, flags, browser,
  toolgun).

- PARCHE 3 — Flags en la tab Weapons (`cl_ads_browser.lua`): checkboxes "Plasma (extra
  shield drain)" / "EMP (shield collapse + lockout)" en el editor (se cargan de la
  entrada curada, viajan en `ads_save_curated` como `or nil`, "Reset to Fallback" los
  limpia), badges `P` (cian) / `E` (amarillo) per-row, nota EFT ampliada ("flags
  always apply"). **[APLICADO 2026-07-07]** — verificado en juego (cubre además la
  prueba empírica de plasma/emp arrastrada del Bloque A: drain ×2 con plasma,
  colapso+lockout con emp).

- PARCHE 4 — Página Q "Energy Shield Settings" (`cl_ads.lua`, 5ª entrada del menú):
  toggles `ads_shield_enabled`/`_sounds`/`_fx_bubble`/`_fx_particles` + sliders
  `_damage_mult`/`_plasma_mult`/`_emp_lockout`/`_think_interval` (este último pasó a
  `FCVAR_REPLICATED` en `ads_shields.lua` para que el slider funcione) + Reset con
  `Derma_Query`. **[APLICADO 2026-07-07]** — verificado en juego.

- PARCHE 5 — Toolgun inspect (`ads_config.lua`): bloque "--- Energy Shield ---" en el
  dump de consola de `ads_inspect_result` (type/state/pool/regen/regen_in/lockout_in
  — el lado server ya existía desde el Bloque A). **[APLICADO 2026-07-07]** —
  verificado en juego.

Verificación en juego (Bloque C): configurar elite/120 HP/color custom/delay 8/rate 25
→ "Whitelist Selected" sobre 2 clases → `[SHD]` en ambas filas, JSON con los campos, y
NPCs respawneados con esos valores (`ads_shield_status`); doble-clic sobre una de esas
clases puebla el tab Energy Shield (y sobre una clase sin escudo apaga el checkbox sin
tocar los valores); re-whitelistear con el checkbox off quita `[SHD]` y el escudo vivo;
flags plasma/emp desde la tab Weapons (badges P/E + drain ×2 / colapso con lockout —
cubre la prueba empírica pendiente del Bloque A); página Q operando en vivo (p.ej.
`ads_shield_damage_mult 5`); toolgun R muestra el bloque Energy Shield.

---

## PARCHES DE sesión Energy Shields — fixes de verificación del Bloque B — 2026-07-07

Sesión de fixes: 3 bugs + 1 ajuste reportados por el autor al verificar el Bloque B en
juego (enfrentamientos grandes, ~6 NPCs con escudo, FPS bajos).

- PARCHE 1 — Burbuja en T-pose lejos del modelo (`cl_ads_shields.lua`): con lag o
  dormancy el `SetParent` de la copia clientside se rompe y queda huérfana en T-pose
  hasta la muerte del NPC. Fix: re-afirmar `SetPos`/`SetParent`/`EF_BONEMERGE` **cada
  frame** (patrón del mod original, que hacía exactamente eso en su Think) + NPC
  dormant → burbuja oculta y sin attaches de partículas. **[PENDIENTE]**

- PARCHE 2 — Sonido de carga sobrevive a la muerte y salta al próximo NPC
  (`ads_shields.lua`): si el NPC muere y se remueve en el mismo tick, la purga del
  Think no llega a cortar el loop, y Source REUTILIZA el índice de entidad → el sonido
  quedaba pegado al índice y lo heredaba el siguiente spawn (hasta un clear total).
  Fix: `StopChargeSound` con la entidad AÚN VÁLIDA en `OnNPCKilled` (hook nuevo) y en
  `EntityRemoved`. **[PENDIENTE]**

- PARCHE 3 — Anillo del HEV ladeado ~45° (`cl_ads_shields.lua`): la normal se calculaba
  del centro del NPC al punto de impacto (hit al pecho alto → componente vertical).
  Fix: normal aplanada (`z=0`, guard contra vector cero) → perpendicular horizontal al
  disparo, como el Goofy original (que usaba el eje atacante→víctima). **[PENDIENTE]**

- PARCHE 4 — Tesla del colapso HEV −25% (`cl_ads_shields.lua`): `SetScale`/
  `SetMagnitude` 1→0.75 y `SetRadius` 1000→750 (pedido del autor). **[PENDIENTE]**

---

## PARCHES DE sesión Energy Shields — Bloque B: efectos visuales cliente — 2026-07-07

Sesión de diseño: Capa 3 del diseño de Energy Shields — assets visuales rescatados del
mod Halo, burbuja clientside, partículas por tipo y consumo de los one-shots net PVS
que el motor ya emitía desde el Bloque A. Incluye el fix del defecto de sonido
detectado en la verificación del Bloque A: los `recharge_*.wav` traen **loop embebido**
(cue de Source) y el motor los emitía como one-shot al COMPLETAR la carga → quedaban
sonando para siempre. Ahora son sonido de **carga**: arrancan al entrar a CHARGING con
pitch estirado al tiempo real de recarga (`SoundDuration`/tiempo restante, clamp
[30,255]) y se cortan con `StopSound` en TODA salida de CHARGING (completar, hit que
interrumpe, EMP, muerte, remove) — centralizado en `SetState`.

- PARCHE 1 — Fix sonido de carga (`ads_shields.lua`): registry `restore` →
  `charge` para spartan/elite; hev gana `charge` (hum `items/suitcharge1.wav`) y
  conserva `restore` (ding `suitchargeok1.wav`); helpers `StartChargeSound` (pitch
  estirado) / `StopChargeSound` integrados en `SetState` + `RemoveShield` + purge de
  muerte del Think; precache del campo `charge`. **[APLICADO 2026-07-07]** — verificado:
  el sweep acompaña la carga y cesa al completar. Bug residual encontrado en la
  verificación: si el NPC muere recargando, el loop sobrevive y SALTA al próximo NPC
  spawneado (Source reutiliza el índice de entidad) — corregido en la sesión de fixes.

- PARCHE 2 — Assets visuales + registro + créditos: 2 `.pcf` a `particles/` y 25
  vmt/vtf a `materials/models/shield/` + `materials/effects/shield/` (rutas
  originales — están horneadas dentro de los pcf y del material de la burbuja;
  colisión con el mod original montado = contenido idéntico, inofensiva);
  `ads_shared.lua` con `game.AddParticles` ×2 + `PrecacheParticleSystem` ×12
  (sets spartan/elite/custom); README: créditos obligatorios (§0 del diseño) a
  Speedy Von Gofast y sora1d + bullet de características. **[APLICADO 2026-07-07]** —
  verificado en juego (partículas y sonidos operativos en los tres tipos).

- PARCHE 3 — Capa de efectos (`cl_ads_shields.lua`, archivo NUEVO): registry espejo
  `ADS_ShieldFX.Types` (MISMAS keys que `ADS.ShieldTypes`); receptor `ads_shield_fx`
  (1=hit flash + partícula de impacto en el punto real, 2=colapso `deplete` — hev:
  `selection_ring`/20× `TeslaHitBoxes`, 3=pop de restauración); burbuja =
  `ClientsideModel` bonemergeada (material aditivo elite, `RENDERMODE_GLOW`,
  `ManipulateBoneScale` 1.05+swell al colapsar, alpha decayendo desde el último
  evento, color por NWVector con fallback al tipo); Think cliente único con early-out
  (arcs persistentes en DOWN vía `ParticleEffectAttach`/`StopParticlesNamed`, loop
  visual de recarga re-attach cada 0.7 s en CHARGING, purga por estado 0/inválidos);
  cleanup en `EntityRemoved`; convars cliente `ads_shield_fx_bubble` /
  `ads_shield_fx_particles`. Estado FX lazy per-NPC (late-joiner ve burbuja/estado
  correcto vía NWVars; arcs recién desde su próximo evento — limitación aceptada).
  **[APLICADO 2026-07-07]** — verificado en juego. 2 bugs encontrados (burbuja en
  T-pose lejos del modelo tras enfrentamientos grandes/bajos FPS; anillo del HEV
  ladeado ~45°) + 1 ajuste pedido (Tesla del HEV −25%) — corregidos en la sesión
  de fixes.

- PARCHE 4 — Color custom en partículas (mejor esfuerzo): con `shield_color` distinto
  al default del tipo se intenta el set colorable `spdy_halo_3_custom_*`
  (`CreateParticleSystem` + control point 1 = RGB normalizado) con fallback automático
  al set del tipo. **[PENDIENTE]** — verificar si el CP1 tiñe; si no responde, queda
  como deuda cosmética en `ads_estado.md` (la burbuja tintada por `SetColor` es la
  garantía mínima; precedente: decal overlay del Block FX). **[APLICADO —
  CERRADO COMO DEUDA COSMÉTICA 2026-07-07]**: ronda 1, la burbuja tiñe bien; las
  partículas caían al set del tipo. Se reintentó con `CreateParticleSystemNoEntity` +
  CP1 en rango 0-255 (los sistemas `custom_*` SÍ existen en el pcf, confirmado por
  strings) — verificación del autor tras el reintento: sigue sin teñir. Diagnóstico
  final: `spdy_halo_3_custom_*` son visualmente **idénticos** a los sets spartan/elite
  con el color horneado a mano en el propio pcf (por eso el autor original los separó
  en sistemas distintos en vez de parametrizarlos) — no responden a ningún control
  point de color en runtime. Requeriría reeditar el pcf en el editor de partículas de
  Source (fuera de alcance de este plan). Se acepta la burbuja tintada como única
  garantía de color custom; ver deuda en `ads_estado.md`.

Verificación en juego (Bloque B): spartan dorado — flash al hit con partícula en el
punto de impacto, estallido + arcs persistentes al colapsar, loop visual + sonido de
carga que CESA al completar, pop al restaurar; elite azul; hev ring+Tesla sin burbuja;
`shield_color` custom por JSON (¿partículas tintadas o fallback?); toggles
`ads_shield_fx_bubble 0` / `ads_shield_fx_particles 0` apagan cada capa; segundo
cliente fuera de PVS no recibe eventos y al reconectar ve el estado correcto. Pendiente
arrastrado del Bloque A: prueba empírica de flags `plasma`/`emp`.

---

## PARCHES DE sesión Energy Shields — Bloque A: motor mecánico server — 2026-07-07

Sesión de diseño: primera entrega de la funcionalidad **Energy Shields** (diseño cerrado
en [`ADS_EnergyShields_Arquitectura.md`](ADS_EnergyShields_Arquitectura.md); materializa
el tramo `[7]` del roadmap; plan por bloques A/B/C/D aprobado por el autor). Capa
pre-filtro de **pool global** delante de la armadura zonal: `Hit → ESCUDO → ARMADURA →
LIMBS`, no-overflow canon (absorción total = early-return del hook: la armadura no gasta
durabilidad y `ProcessLimbHit` no corre → cero debuffs con escudo arriba), bypass melee
por damage type (`DMG_CLUB`/`DMG_SLASH`, que SÍ resetean la regen), flags de arma
`plasma`/`emp` curados a mano, recarga server-only sin tráfico de red (Think único patrón
scavenger + NWVar de estado on-change + one-shots net PVS). Decisión del autor:
`shield_max_hp` = **valor fijo en HP** (no fracción estilo limbs). Bloque A = slice
mecánico completo verificable sin UI (`ads_shield_give` o JSON a mano); efectos visuales
cliente → Bloque B; UI → Bloque C. Assets/concepto rescatados de "Halo Energy Shield"
(Speedy Von Gofast) y "Goofy Armor Effect" (sora1d) — créditos a README en Bloque B.

- PARCHE 1 — Motor (`ads_shields.lua`, archivo NUEVO): registry `ADS.ShieldTypes`
  (spartan/elite/hev — hev 100% built-in engine, sin assets), convars
  `ads_shield_enabled`/`_damage_mult`/`_plasma_mult`/`_emp_lockout`/`_sounds`/
  `_think_interval`; `InitShield` idempotente (autoridad = `shield_type` en el whitelist
  entry, registro diferido 0.4 s) + `RemoveShield`; `ProcessShield` (drain global único,
  EMP = colapso + lockout, bypass melee) + `ShieldWillAbsorb` (consulta pura);
  NWVars `ADS_Shield_State/Type/Color` on-change; Think único de recarga sobre registry
  `ShieldNPCs` (estados UP/DOWN/CHARGING, `can_regen=false` queda caído); `EmitShieldFX`
  (net `ads_shield_fx` con `AddPVS`, throttle 1 hit-flash/frame); `PlayShieldSounds`
  por tier de drain; `RefreshShieldsForClass`/`RefreshAllShields`; concommands admin
  `ads_shield_give`/`ads_shield_clear`/`ads_shield_status`. **[APLICADO 2026-07-07]** —
  verificado en juego por el autor. Defecto detectado en la verificación: el sonido de
  recarga quedaba loopeando para siempre (wav con loop embebido, emitido como one-shot
  al completar) — corregido en la sesión Bloque B, PARCHE 1.

- PARCHE 2 — Enganche (`ads_core.lua`): call site de `ProcessShield` al tope de
  `ScaleNPCDamage` (antes del guard de armadura; cubre los 3 paths — el dmginfo aún trae
  el daño crudo), con supresión de sangre vía `ApplyBlockedHitFX(..., bloodOnly=true)`
  (6º parámetro nuevo retrocompatible: sin chispa ni decal de armadura), descarte
  defensivo del `ADS_ArmorStash` fresco y early-return; línea `[shield]` en la traza
  tier 1/2 (+ nota `shd=bypass|down` en hits que pasan); `AddNetworkString
  "ads_shield_fx"`; refresh de escudos vivos tras `wl_add`/`wl_del`/`bl_add`/batches
  (`ads_modify_list`) y tras `reload`/`clear_wl` (`ads_admin_action`); bloque `i.shield`
  en `ADS.InspectNPC` (el print cliente del toolgun llega en Bloque C — mientras tanto
  `ads_shield_status`). **[APLICADO 2026-07-07]** — verificado en juego.

- PARCHE 3 — Detour ARC9 shield-aware (`ads_core.lua`): con escudo arriba
  (`ShieldWillAbsorb`), el detour corta `penleft = 0` y retorna SIN resolver armadura ni
  depositar stash (la placa no participa; el round no sigue penetrando geometría —
  consistente con no-overflow). Traza tier 3 `[ADS DET] SHIELD-STOP`. El drain real
  ocurre siempre en `ScaleNPCDamage` (una sola autoridad). Caso borde esperado:
  perdigones interlaceados de escopeta contra escudo casi caído → `path=inline_arc9`
  ocasional (daño correcto, solo pierde el hitPos del trace). **[APLICADO 2026-07-07]** —
  verificado en juego.

- PARCHE 4 — Saneamiento/persistencia (`ads_core.lua` `Sanitize`): campos `shield_type`
  (gate maestro contra el registry; inválido → se descartan todos los `shield_*`),
  `shield_max_hp` (int [1,5000]), `shield_color` ({r,g,b} [0,255]),
  `shield_recharge_delay` ([0,60] 1dp), `shield_recharge_rate` ([0.1,1000] 1dp HP/s),
  `shield_can_regen` (bool, `false` legítimo — resolver con `~= nil`). Viajan en los
  payloads existentes de `wl_add`/`wl_add_batch` y persisten solos vía `SaveConfig`
  (cero cambios en Save/LoadConfig). **[APLICADO 2026-07-07]** — verificado en juego
  (JSON a mano + reload).

- PARCHE 5 — Flags plasma/emp backend (`ads_armor.lua` `SanitizeCuratedWeapon`): campos
  opcionales `plasma`/`emp` (solo persistidos si `true`) en la entrada curada; extractor
  y resolver intactos (los flags los lee `ProcessShield` directo de
  `ADS.CuratedWeapons`, independiente del tuple → una entrada con flags jamás shadowea
  el branch EFT). **[APLICADO 2026-07-07]** — código en el árbol; la prueba empírica de
  `plasma`/`emp` en juego quedó pendiente del autor (ver `ads_estado.md`).

- PARCHE 6 — Assets de sonido: 26 wav rescatados del mod Halo a `sound/ads/shield/`
  ({light|medium|heavy}/hit1-7, break1-3, recharge_spartan, recharge_elite — lowercase,
  precache en carga). HEV sin assets. **[APLICADO 2026-07-07]** — verificado en juego
  (hits/break OK; los recharge_* pasan a ser sonido de CARGA en el Bloque B).

Verificación en juego (Bloque A, `ads_debug 2`): `ads_shield_give spartan 70` → print
`[shield]` con drain/pool y HP+limbs intactos; colapso (`reason=break` + sonido) y el
siguiente disparo vuelve a `path=inline…`; recarga con dprints charging/full y
`ads_shield_status`; crowbar bypassa pero re-estira `regen_in`; ARC9 con `ads_debug 3` →
`SHIELD-STOP` sin stash y durabilidad de placa intacta; sangre suprimida en hit absorbido
(sin chispa/decal); JSON a mano (`shield_type`) + `reload` → escudo por clase; flags
`plasma`/`emp` en una entrada curada → drain ×2 / colapso+lockout; `shield_type` basura →
warning sin errores lua.

---

## PARCHES DE sesión Block FX — feedback visual de bloqueo — 2026-07-07

Sesión de diseño: cuando la armadura zonal BLOQUEA un balazo (invariante
`factorPenleft == 0`), el hit debe LEERSE como bloqueo: sin sangre (engine, VJ y
addon Visceral Dynamic Blood base si está montado — integración sin dependencia,
workshop 3652351390, repack de zippy/NGBR "animated blood"), chispa metálica
(`MetalSpark`) y decal de impacto metálico pintado ENCIMA del gunshot de flesh
(sin `RemoveAllDecals` — rechazado por parpadeo/borrado total; si el overlay no
cubre, queda el decal de flesh). Si penetra, todo normal. Palancas:
`SetBloodColor(DONT_BLEED)` dentro de `ScaleNPCDamage` (corre en TraceAttack
ANTES de SpawnBlood/TraceBleed — verificado contra el SDK) con restore en
`timer.Simple(0)` + `IsValid`; token per-hit `npc.ADS_BlockedHitToken =
FrameNumber()` para el detour de metatable de Visceral (su `hasRedBlood()`
bypasea el blood color en NPCs VJ); `npc.Bleeds = false` per-hit para la sangre
propia de VJ (`DoBleed` no consulta `GetBloodColor` — verificado en
`vjbaseactual`, `npc_vj_human_base/init.lua` L3966/L4000). Escopetas:
`ScaleNPCDamage` corre por perdigón y `EntityTakeDamage` (donde escucha
Visceral) una vez con daño agregado → blocked/clear por perdigón; la rama
penetrada restaura en el MISMO frame para que la ráfaga mixta sangre.

- PARCHE 1 — Decal compartido (`lua/autorun/ads_shared.lua`, archivo NUEVO):
  `game.AddDecal("ADS_Ricochet", decals/metal/shot1..5_subrect)` en ambos realms
  (`AddCSLuaFile`). Fila nueva en el mapa de archivos de CLAUDE.md.
  **[APLICADO 2026-07-07]** — carga sin errores, pero el overlay no llega a
  verse sobre el modelo (deuda cosmética, ver `ads_estado.md`).

- PARCHE 2 — Núcleo Block FX (`ads_core.lua`): convars `ads_block_noblood_enabled`
  / `ads_block_spark_enabled` / `ads_block_decal_enabled` (default 1, replicated+
  archive); `ADS.ApplyBlockedHitFX(npc, di, hg, hitPos, hitNormal)` (token + stash
  único de bloodColor/Bleeds con guard anti-doble-stash + chispa + decal
  ADS_Ricochet) y `ADS.ClearBlockedHitFX(npc)` (restore inmediato + limpia token);
  llamadas en los 3 sites (stash / inline_arc9 / inline), rama bloqueada Y
  penetrada; stash del detour ARC9 enriquecido con `hitPos`/`hitNormal` del trace.
  Fix durante verificación: el 4º arg de `util.Decal` es el FILTRO del trace
  (entidades a ignorar), no el objetivo — pasar el npc impedía pintar sobre él.
  **[APLICADO 2026-07-07]** — verificado en juego por el autor: bloqueo sin
  sangre + chispa OK; penetración sangra normal. La rama decal, aun con el fix
  del filtro, no se ve sobre el modelo → queda como deuda cosmética
  (`ads_block_decal_enabled` inerte en la práctica).

- PARCHE 3 — Compat Visceral/Animated Blood (`ads_core.lua`): bloque
  `InitPostEntity` "ADS_AnimBlood_Compat" gateado por `ANIMATED_SPLATTER_EFFECT`;
  detour de `RealisticBlood_BulletDamage`/`_OtherDamage`/`_PhysDamage`
  (early-return con token fresco ≤1 frame, respeta `ads_block_noblood_enabled`
  per-hit) + hook `CreateEntityRagdoll` que copia el token fresco al ragdoll
  (Visceral re-ejecuta el último daño sobre el rag vía
  `RealisticBlood_LastDMGINFO`). Sin tocar su `EntityFireBullets` (se re-lanza a
  sí mismo con flag interna). **[APLICADO 2026-07-07]** — verificado en juego
  por el autor con el addon montado: hits bloqueados sin efectos de sangre.

- PARCHE 4 — UI (`cl_ads.lua`): 3 checkboxes "Block FX" en la sección Effects del
  panel Armor + resets. **[APLICADO 2026-07-07]**

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
