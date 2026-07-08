# ADS 2.0 — Energy Shields — Documento de Arquitectura e Implementación

**Destinatario:** Fable 5 en Claude Code.
**Rol:** implementar según este diseño ya cerrado por Opus. No rediseñar. Cambiar solo lo que este documento especifica.
**Estado:** diseño cerrado. Este documento es autocontenido — no requiere el chat original.

---

## 0. Créditos (obligatorio en README)

La funcionalidad se reescribe reutilizando concepto y código de dos mods deprecados (2022), orientados al jugador (aplicaban sobre la armadura HL2). Sus autores permiten el uso de su código. Dar crédito explícito en el README:

- **Speedy Von Gofast** — *Halo Energy Shield*.
- **sora1d** — *Goofy Armor Effect* (base del HEV Charge Shield).

Se reutiliza **concepto y funcionalidad**, pero el wiring de red se reescribe: los mods originales eran single-target (jugador); ADS es multi-NPC.

---

## 1. Tarea previa obligatoria — revisar el mod del workshop

Antes de escribir código, Fable debe **abrir los dos mods originales en DEV** y entender:

- Cómo estaba cableado el **efecto visual** (render de la burbuja/capa) y su ciclo de vida.
- Cómo estaban cableados los **sonidos** (impacto, colapso, recarga, restauración).
- Cómo detectaban impacto/daño y estado (probablemente hooks client-side sobre la armadura HL2 del jugador).

El objetivo es **rescatar el efecto y el sonido**, NO copiar su lógica de red. Su net era player-oriented y single-target. Aquí se reescribe según el reparto server/NWVar/PVS de la sección 5. No copiar el modelo de red original tal cual.

---

## 2. Principios de dominio ya fijados (no violar)

- ADS lee valores EFT en vivo con `GetProcessedValue`, **nunca los escribe**: eso es del menú ARC9.
- La **armadura** de ADS es un pre-filtro zonal delante de `ads_limbs`. El pool de limbs no se altera para compensar.
- Penetración de armas no-EFT: **curada a mano** (patrón browser), no scrapeada de la base.
- El escudo es una **nueva capa pre-filtro delante de la armadura** (un nivel más arriba que la armadura).

Reglas de código para Claude Code / Fable:
- Cambiar **solo** lo explícitamente especificado aquí.
- **Preservar** comentarios y estilo de código existentes.
- **No refactorizar** código no relacionado.

---

## 3. Stack de 3 capas — columna vertebral de la modularidad

La funcionalidad se separa en tres capas independientes. Esta separación es lo que hace trivial "agregar un escudo nuevo" y permite que HEV (visualmente distinto) conviva con Spartan/Elite sin ramificar el motor.

### Capa 1 — Motor mecánico (`ads_shields.lua`, server)
Pool global, drain, recarga, bypass, EMP, colapso. **Idéntico para todos los escudos.** Engancha en `ScaleNPCDamage` **antes** del cálculo de armadura.

### Capa 2 — Registry de tipos de escudo
Tabla donde cada entrada = `{ sonidos, params visuales, defaults de fuerza/recarga }`. La mecánica NO cambia entre tipos; el tipo solo intercambia assets y valores por defecto.

- **Agregar escudo nuevo = agregar una entrada a esta tabla.** Toda la modularidad vive aquí.
- Tipos iniciales: `spartan`, `elite`, `hev`.
  - **Spartan / Elite**: mismo motor, cambian sonidos y (según el mod Halo) matices visuales.
  - **HEV Charge Shield**: reusa **el mismo motor** (pool, recarga, plasma, EMP). Visual y sonido más ligeros (Goofy Armor). Difiere solo en la capa de efectos, no en mecánica.

### Capa 3 — Capa de efectos (client + supresión)
Render de la burbuja, sonidos por tipo, y **bloqueo de decals y efectos del visceral dynamic blood base mientras el escudo esté arriba**. La supresión de blood/decal es una decisión **server-side** dentro del hook de daño (el hit fue shield-absorbed → matar efectos de ese hit). Reutilizar la integración de sangre ya existente en el código.

---

## 4. Modelo de daño

Orden de capas en cada impacto:

```
Hit → ESCUDO (pool global) → ARMADURA (zonal, aquí sí penetración) → LIMBS
```

Diferencia clave: el escudo es **pool global** (un solo HP para todo el NPC), a diferencia de la armadura que es zonal.

### Cálculo
- El escudo lleva **un** `shield_damage_mult` (cuánto drena un hit genérico). Un solo knob.
- `dmg_al_escudo = weapon_damage * shield_damage_mult` (× factores de flag, ver abajo).
- **Penetración NO toca el escudo.** Recién aplica en la capa de armadura, cuando el escudo cayó o el hit hizo bypass.

### Flags de arma (viven en la pestaña de weapons, junto a penetración)
Curados a mano, **siempre manuales** — plasma y EMP no existen en ninguna base de armas (ni EFT ni no-EFT):
- `plasma` → aplica un **factor global extra** al drain (saturación). Un solo número global, no por escudo.
- `emp` → **colapso total instantáneo** del escudo + **lockout de recarga** N segundos (canon: pistola de plasma sobrecargada deja sin escudo un rato).

### Bypass (melee / baja velocidad)
**Por damage type, no por flag manual.** `DMG_CLUB`, `DMG_SLASH` (melee, espada de energía) **saltan el escudo** y van directo a armadura/limbs sin tocar el pool. Cero curación manual, no ensucia el browser.

### No-overflow (canon clásico Halo)
Cuando un tiro con el escudo a 1 HP lo revienta, el exceso **NO** pasa a la armadura en ese mismo hit. El escudo absorbe el impacto completo; el siguiente tiro pega a la armadura/salud.
- `ProcessShield` retorna **"consumido, corta"** vs **"pasa el hit entero"** (bypass o escudo ya caído).
- Consecuencia gratis: mientras hay escudo, `ProcessLimbHit` **no** corre → ningún debuff de precisión/velocidad. El NPC con escudo pelea a full. Es canon puro. **Confirmar que `ProcessShield` retorna antes de `ProcessLimbHit`.**

### Recarga
- Timer que se **resetea con cualquier hit que afecte el escudo**, incluidos los de bypass (canon: casi cualquier daño frena la regen).
- Tras `recharge_delay` seg sin daño → regen a `recharge_rate`/seg hasta full.
- **Toggle `shield_can_regen`** (per-NPC, en el whitelist): si `false`, el pool drena y se queda caído, sin recarga. HEV trae su propio default, pero **cualquier** escudo puede tener regen off.
- El EMP impone `recharge_delay` extendido (lockout) por encima del normal.

---

## 5. Red — reparto para multi-NPC (crítico)

Regla madre: **la recarga NO debe generar tráfico de red.** El servidor simula; el cliente solo reacciona a **transiciones de estado**. Se replican eventos, no el estado continuo. Networkear el HP cada tick con muchos NPCs recargándose inundaría la red.

### Server-only (nunca sale a red)
- HP float exacto del escudo y timers de recarga/lockout.
- **Un solo Think hook** que itera únicamente los NPCs con escudo registrados — **mismo patrón que `ads_scavenger`** (single Think sobre NPCs registrados). No un timer por NPC. La recarga completa produce **cero** paquetes hasta que termina.

### NWVar per-NPC (replica solo on-change)
- Enum de estado del escudo: `UP / DOWN / CHARGING`.
- Es lo que el cliente lee para decidir si dibuja la burbuja.
- Por qué NWVar y no net message: escala a muchos NPCs (GMod solo networkea el cambio) y **sobrevive a late-joiners** (un jugador que entra a mitad de partida ve el estado correcto; un net message no le llegaría).

### net messages con filtro PVS (solo efectos transitorios one-shot)
- Flash al recibir hit, estallido al colapsar, pop al restaurarse full.
- Enviar con `CRecipientFilter:AddPVS(pos)` — solo a jugadores que pueden ver ese NPC. Nada de broadcast global.

Único "evento de recarga" que cruza la red: la transición `CHARGING → UP` al completar (flip de NWVar).

---

## 6. Detección / integración con ADS existente

El escudo **cuelga del whitelist entry del NPC**. **No necesita detección propia** — usa la que ya tiene `ads_core` (whitelist/blacklist, patrones VJ, auto-detect). Un Elite se marca en el browser como cualquier NPC ADS y ahí se le asigna tipo de escudo y parámetros.

---

## 7. Config del subsistema (paralelo a limbs)

Campos por NPC en el whitelist (persistidos en `data/ads/ads_config.json`):
- `shield_type` (`spartan` / `elite` / `hev` / …)
- `shield_color`
- `shield_max_hp` (fuerza del escudo — fracción del HP del NPC o fijo, seguir convención de limbs)
- `shield_recharge_delay`
- `shield_recharge_rate`
- `shield_can_regen` (bool)

Globales (no per-NPC):
- `shield_damage_mult` base
- factor global de `plasma`
- duración de lockout de `emp`

---

## 8. Checklist de integración en el browser y menús

Paralelo exacto a las pestañas existentes (mismo estilo de sliders y texto):

- [ ] Nueva **columna "Shield"** en el browser (`cl_ads_browser.lua`).
- [ ] Nueva **pestaña "Energy Shield"** con customización: **tipo, color, fuerza del escudo, tiempo de recarga, toggle regen**.
- [ ] **Sliders y texto idénticos** en estilo a las otras pestañas.
- [ ] Datos de escudo en el **`.json`** (`ads_core` persistencia).
- [ ] **Debug/inspect** (`InspectNPC`) refleja que existe el escudo y su estado.
- [ ] **Copiar valores con doble clic** sobre NPC incluye los campos de Energy Shield.
- [ ] Flags `plasma` / `emp` agregados a la **pestaña de weapons** (donde vive penetración), curados a mano.
- [ ] Botones de reset del panel, coherentes con el resto.
- [ ] Estado del escudo sincronizado (NWVar) y consumido por `ADS_ListsUpdated` / `ads_catalog_state` según corresponda.

---

## 9. Archivos afectados

Rutas del codebase:

| Archivo | Acción |
|---|---|
| `lua\autorun\server\ads_shields.lua` | **NUEVO** — motor mecánico + registry de tipos + Think loop server-only |
| `lua\autorun\server\ads_core.lua` | Enganchar `ProcessShield` en `ScaleNPCDamage` **antes** de la armadura; persistencia JSON de campos de escudo; net.Receive de config de escudo; flags plasma/emp de arma |
| `lua\autorun\client\cl_ads.lua` | Nueva pestaña "Energy Shield" (sliders/checkboxes → convars); botones de reset |
| `lua\autorun\client\cl_ads_browser.lua` | Columna "Shield"; pestaña; copy on double-click; sliders; estado vía NWVar/hook |
| `lua\weapons\gmod_tool\stools\ads_config.lua` | Reflejar escudo en panel/inspect si aplica |
| Capa de efectos client | Render de burbuja + sonidos por tipo (rescatados del mod workshop); supresión decals/blood mientras escudo arriba |
| `README` | Créditos a Speedy Von Gofast y sora1d |

---

## 10. Resumen de decisiones cerradas

1. **No-overflow** — canon clásico, el escudo absorbe el hit completo.
2. **Canon** — cualquier daño frena/resetea la recarga; EMP con lockout.
3. **EMP y plasma** — flags de arma manuales en la pestaña de weapons.
4. **Sin penetración en el escudo** — un solo `shield_damage_mult`.
5. **Bypass por damage type** (`DMG_CLUB` / `DMG_SLASH`), no por flag.
6. **Toggle `shield_can_regen`** general (per-NPC), no exclusivo de HEV.
7. **Red**: server simula, NWVar para estado (on-change + late-join), net+PVS para efectos transitorios. Recarga = cero tráfico hasta completar.
8. **HEV** = mismo motor que Halo, difiere solo en capa de efectos (Goofy Armor, más ligero).
