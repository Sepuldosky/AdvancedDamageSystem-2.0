# Advanced Damage System 2.0

**Versión 1.0.0**

Sistema de blindaje zonal estilo **Escape from Tarkov** para NPCs y jugadores en **Garry's Mod**. Reemplaza la capa de armadura de ADS 1.x con un modelo de placas por zona (hitgroup): cada placa tiene durabilidad propia, probabilidad de penetración modulada por desgaste, daño romo al bloquear y daño reducido al perforar.

---

## Características

- **Blindaje por zona (hitgroup)**, no por entidad entera. Cobertura asimétrica: un brazo puede tener placa clase 6 y el otro clase 2.
- **Durabilidad de placa** independiente del HP de la zona; se desgasta con cada impacto.
- **Penetración estilo EFT** modulada por durabilidad de placa y clase de armadura.
- **Daño romo (blunt)** cuando la placa bloquea; **daño post-penetración reducido** cuando la placa es perforada.
- La bala pierde `penleft` al perforar (ARC9/TFA).
- **Materiales configurables** (aramid, titanium, ceramic, y perfiles sci-fi como nano-titanium o uranium-matrix).
- **Subsistema de HP por extremidad** (head/arms/legs) con debuffs, stun y drop de arma.
- **Escudos de energía** por NPC (spartan / elite / hev): pool global recargable delante de la armadura zonal, con bypass melee, flags de arma plasma/EMP y efectos estilo Halo.
- **Scavenger**: los NPCs recogen armas del suelo.
- **Browser visual de configuración** ("ADS Configuration") con 4 pestañas.

## Compatibilidad de bases de armas

ADS normaliza los datos de distintas bases a un tuple común mediante una escalera de extracción (mejor dato primero):

| Nivel | Fuente | `source` |
|---|---|---|
| 1 | **ARC9** con round EFT de Darsu (lee `GetProcessedValue` en vivo) | `eft` |
| 2 | **Tabla curada ADS** por classname (cualquier base: ARC9 / VJ / TFA) | `curated` |
| 3 | **Fallback por tipo de munición** (VJ Base, HL2 vanilla, TFA sin curar) | `fallback` / `tfa` |

## Instalación

1. Copia la carpeta del addon a `garrysmod/addons/` (o directamente sobre `garrysmod/`, respetando `lua/`, `materials/`).
2. Reinicia el servidor o el mapa.
3. La configuración se genera sola en `data/ads/ads_config.json` (no se versiona; se recrea desde cero).

## Uso

### Browser de configuración (admin)

Abre "ADS Configuration" desde la consola:

```
ads_config_ui
```

(alias: `ads_browser`). Pestañas disponibles:

- **Armor** — perfiles de armadura por zona sobre una silueta clickeable.
- **Limbs / WL** — whitelist/blacklist de NPCs y tuning de HP por extremidad.
- **Weapons** — penetración curada por arma + ajuste de los 6 buckets de ammo fallback.
- **General** — catálogo, refresh y scan de NPCs del mundo.

### Menú Q (spawnmenu)

`Options → Advanced Damage System`: Armor Settings, Limb HP Settings, Scavenger Settings, How to use.

### Toolgun

Stool **ADS Config** (debug puro, efímero, sin tocar el JSON):
- **M1** sobre NPC — aplica armadura/limbs per-entity.
- **M2** sobre NPC — copia el perfil de un NPC vivo.
- **Reload (R)** sobre NPC — inspecciona en consola de cliente.

## ConVars principales

| ConVar | Default | Descripción |
|---|---|---|
| `ads_enabled_npc` | `1` | Sistema de armadura sobre NPCs |
| `ads_enabled_ply` | `1` | Sistema de armadura sobre jugadores |
| `ads_engine_hitgroup_compensation` | `1` | Cancela el escalado nativo de hitgroups de Source |
| `ads_pen_over_adj` | `0.5` | Bonus de penetración por ratio penPower/armorClass sobre 1.0 |
| `ads_dur_adj` | `0.25` | Bonus de penetración según la placa pierde durabilidad |
| `ads_armor_deterministic` | `0` | 1 = roll determinista (penChance≥0.5 penetra); 0 = probabilístico |
| `ads_sound_enabled` | `1` | Sonido al impactar armadura |
| `ads_vj_autodetect` | `1` | Auto-detección de NPCs VJ blindados |
| `ads_arc9_compat` | `1` | Auto-desactiva `arc9_mod_bodydamagecancel` cuando hay ARC9 |
| `ads_debug` | `0` | 0=off · 1=compacto · 2=verbose · 3=pipeline completo |

## Estructura del proyecto

```
lua/
  autorun/
    server/
      ads_core.lua        Núcleo: ScaleNPCDamage, whitelist/blacklist, JSON, net, compat ARC9
      ads_armor.lua       Extractor + Resolver puros, materiales, ammo fallback, curated weapons
      ads_limbs.lua       HP por extremidad
      ads_scavenger.lua   Recogida de armas por NPCs
    client/
      cl_ads.lua          Paneles del menú Q
      cl_ads_browser.lua  Browser "ADS Configuration" (4 tabs)
  weapons/gmod_tool/stools/
      ads_config.lua      Stool de debug
materials/ads/            Iconos de materiales de placa
docs/                     Arquitectura y convenciones de commits
```

## Documentación

- [`docs/ADS_2_0_Architecture_updated.md`](docs/ADS_2_0_Architecture_updated.md) — arquitectura autocontenida (§1–§19).
- [`docs/ads_convenciones_commits.txt`](docs/ads_convenciones_commits.txt) — convenciones de git commits del proyecto.
- [`CLAUDE.md`](CLAUDE.md) — guía para asistencia con Claude Code.

## Requisitos

- Garry's Mod (servidor o singleplayer).
- Opcional: **ARC9** (para datos EFT en vivo), **VJ Base**, **TFA Base**. ADS degrada con gracia si no están.

## Créditos

La funcionalidad de **Energy Shields** reutiliza concepto, efectos y sonidos de dos mods deprecados (2022), con permiso de sus autores. El wiring de red se reescribió (los originales eran single-target sobre la armadura HL2 del jugador; ADS es multi-NPC):

- **Speedy Von Gofast** — *Halo Energy Shield*: burbuja de energía, partículas (`spdy_*`) y sonidos de hit/colapso/recarga.
- **sora1d** — *Goofy Armor Effect*: base del **HEV Charge Shield** (efectos y sonidos built-in del engine).
