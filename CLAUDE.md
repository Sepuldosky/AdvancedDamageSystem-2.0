# CLAUDE.md

Guía para trabajar en **Advanced Damage System 2.0** (addon GLua para Garry's Mod). Léela antes de tocar código.

## Qué es

Sistema de blindaje **zonal** estilo Escape from Tarkov para NPCs y jugadores. Reemplaza —no extiende— la capa de armadura de ADS 1.x. La lógica 1.x (`ADS_Armor` pool único, `ProcessArmor`, `RollArmor`) **no existe en 2.0**; no la reintroduzcas.

**Regla cardinal:** la armadura ADS 2.0 es un **pre-filtro** que se sienta delante de `ads_limbs`. El pool de HP de extremidades NO se modifica para compensar el blindaje. La bala impacta → el resolver calcula penetración/daño a carne/pérdida de energía → el resultado entra a `ads_limbs`/HP nativo como lo haría el daño crudo.

## Docs del proyecto — jerarquía de lectura

Antes de tocar código, lee en este orden (los tres primeros son **docs vivos**):

1. **Estado de HOY** → [`docs/ads_estado.md`](docs/ads_estado.md). Foto del AHORA, ≤1 pantalla. **Léelo ANTES** que la arquitectura — dice qué existe hoy, qué está pendiente de verificar y qué deuda hay.
2. **Rumbo** → [`docs/ads_roadmap.txt`](docs/ads_roadmap.txt). Qué sigue y en qué orden. `estado` dice dónde estamos dentro de él.
3. **Historial de parches** → [`docs/CHANGELOG.md`](docs/CHANGELOG.md). `[PENDIENTE]`/`[APLICADO YYYY-MM-DD]`, nunca se borra ni renumera.
4. **Metodología de trabajo** → [`docs/ads_flujo_trabajo.txt`](docs/ads_flujo_trabajo.txt). Planificación densa por bloques, vertical slice, orden de ejecución de parches.
5. **Arquitectura de referencia** (autocontenida, §1-§19) → [`docs/ADS_2_0_Architecture_updated.md`](docs/ADS_2_0_Architecture_updated.md). Diseño estable; se consulta por sección cuando se necesita.
6. **Convenciones de commit** → [`docs/ads_convenciones_commits.txt`](docs/ads_convenciones_commits.txt).

## Idioma

Comentarios y mensajes de commit en **español**; los `<tipo>` de commit van en inglés (ver convenciones). El código existente mezcla comentarios en español e inglés — **iguala el estilo del archivo que estás editando**, no impongas uno nuevo.

## Mapa de archivos

| Archivo | Rol |
|---|---|
| `lua/autorun/server/ads_core.lua` | Núcleo: hook `ScaleNPCDamage`, whitelist/blacklist, multiplicadores de hitgroup, persistencia JSON, `net.Receive`, compat ARC9 (detour `AfterShotFunction` + fallback inline). |
| `lua/autorun/server/ads_armor.lua` | **Funciones puras**: extractor + resolver. Tablas estáticas (materiales, ammo fallback, curated weapons). NWvars de armadura por zona. Sin hooks, sin call sites. |
| `lua/autorun/server/ads_limbs.lua` | HP por extremidad: pools head/arms/legs, debuffs, drop de arma, stun, API de healing. |
| `lua/autorun/server/ads_scavenger.lua` | NPCs recogen armas del suelo. |
| `lua/autorun/server/ads_shields.lua` | Escudos de energía: pool global pre-armadura, registry de tipos (`ADS.ShieldTypes`), Think único de recarga (patrón scavenger). |
| `lua/autorun/ads_shared.lua` | Registro compartido (ambos realms): decals del addon (`game.AddDecal "ADS_Ricochet"`), partículas del escudo (`game.AddParticles`). |
| `lua/autorun/client/cl_ads.lua` | Paneles del menú Q (spawnmenu `Options`). |
| `lua/autorun/client/cl_ads_browser.lua` | Browser "ADS Configuration": 6 tabs (Armor / Limbs WL / Weapons / Energy Shield / Scavenger / General). |
| `lua/autorun/client/cl_ads_shields.lua` | Capa de efectos del escudo: burbuja bonemergeada, partículas por tipo (`ADS_ShieldFX.Types`), receptor `ads_shield_fx`. |
| `lua/weapons/gmod_tool/stools/ads_config.lua` | Stool de debug efímero (no toca el JSON). |

## Contratos que no debes romper

1. **`ads_armor.lua` es puro.** Solo funciones y tablas. Nada de hooks, `net`, ni escritura de NWvars fuera de las funciones `Init*/Apply*`. Si necesitas un side-effect, va en `ads_core.lua`.
2. **No inyectes campos en `dmginfo`.** Es userdata C++; `dmginfo.ADS_x = y` falla silenciosamente. El tuple viaja como variable local en el call site.
3. **Sync de durabilidad en el mismo tick.** `SetNWInt("ADS_Armor_Dur_"..hg, ...)` se llama en el mismo tick que el cálculo, sin timers — así el perdigón 2 lee la durabilidad tras el perdigón 1.
4. **ARC9 EFT es solo-lectura.** `GetProcessedValue` ya incluye lo que el usuario configuró en el menú ARC9. ADS lee en vivo, nunca escribe. Una sola fuente de verdad.
5. **La autoridad de armadura es `ADS.ArmorProfiles[key]` con `key = ADS.GetConfigKey(ent)`** (key de spawnmenu con config > classname; `ent.NPCName` lo taggea el sandbox al spawnear). Su presencia es la única condición que activa el sistema sobre un NPC. Los entries de key y de classname se **reemplazan**, nunca se mezclan; los puntos entity-facing resuelven vía `ADS.GetOverrideForEnt`/`ADS.IsUserBlacklisted`.
6. **El escudo de energía es un pre-filtro de pool GLOBAL delante de la armadura**, nunca zonal. `Hit → ESCUDO → ARMADURA → LIMBS`. Absorción total = early-return de `ScaleNPCDamage` **antes** de resolver armadura y **antes** de `ProcessLimbHit` — un hit absorbido no gasta durabilidad de placa ni dispara debuffs de limbs. La autoridad del escudo es `shield_type` en el whitelist entry (`ADS.GetOverride`), igual que limbs.
7. **La recarga del escudo nunca genera tráfico de red.** Server simula (Think único sobre NPCs registrados, patrón `ads_scavenger`); solo NWVars on-change (`ADS_Shield_State/Type/Color`) y one-shots `net "ads_shield_fx"` con `CRecipientFilter:AddPVS` cruzan la red.
8. **`ADS.ShieldTypes` (server) y `ADS_ShieldFX.Types` (client) deben tener las mismas keys.** Agregar un tipo de escudo nuevo = una entrada en cada tabla; la mecánica no cambia entre tipos, solo assets/defaults.

## Extractor — jerarquía de 3 branches (`ADS.ExtractBulletData`)

Mejor dato primero. **EFT siempre gana**; la tabla curada aplica a cualquier classname (no requiere ARC9):

1. `wep:GetProcessedValue("HasAmmoooooooo", true)` → round EFT. `source = "eft"`.
2. `ADS.CuratedWeapons[wep:GetClass()]` → tabla curada. `source = "curated"`.
3. Fallback por ammo type vía `ADS.AmmoAlias` → `ADS.AmmoFallback[bucket]`. `source = "fallback"` (o `"tfa"` si el classname trae prefijo `tfa_`).

## Resolver — `ADS.ResolveArmor(zona, tuple, hitgroup)`

Función pura. Devuelve `{ fleshDmg, newDur, factorPenleft }`. Pasos:
- **Paso 0:** sin zona → passthrough (`fleshDmg = damage`, `factorPenleft = 1`).
- **Paso 1:** `penChance = penChanceBase + ads_pen_over_adj*(ratio-1) + ads_dur_adj*(1-durFactor)`, clamp 0..1.
- **Paso 2:** roll (determinista si `ads_armor_deterministic`, si no `math.random`).
- **Paso 3a (bloqueado):** daño romo con floor 5%; la placa se desgasta más.
- **Paso 3b (penetrado):** daño reducido por `resistRatio`; desgaste a la mitad.

Hay un bloque de auto-test comentado al final de `ads_armor.lua` con valores esperados — úsalo para validar cambios a la matemática.

## Ammo fallback editable (Block 7)

- `ADS.AmmoFallbackDefaults` es **inmutable** (nunca se muta en runtime).
- `ADS.AmmoFallback` es la copia viva que lee el extractor; `LoadArmorData` la reconstruye desde defaults + overrides del JSON en cada carga.
- Se persiste **solo lo que difiere** del default (`ADS.GetAmmoFallbackOverrides`).
- Saneamiento server-side: `ADS.SanitizeAmmoFallback`, `ADS.SanitizeCuratedWeapon`, `ClampAmmoBucket`.
- Rangos: penPower `[1,115]`, armorDamage `[1,120]`, penChanceBase `[0,1]` (2 decimales).

## Data model

**JSON** `data/ads/ads_config.json` (no versionado; se recrea). Claves top-level: `whitelist`, `blacklist`, `armor`, `curated_weapons`, `ammo_fallback`. Zonas indexadas por string del hitgroup (`"1"`=HEAD … `"7"`). Ver §8 de la arquitectura.

**NWvars por entidad (armadura):** `ADS_Armor_Class_<hg>`, `ADS_Armor_Dur_<hg>`, `ADS_Armor_MaxDur_<hg>`, `ADS_Armor_Mat_<hg>`, flag `ADS_Armor_Init`. Slot `0` = GENERIC/fallback. `InitArmorNWvars` es **idempotente** (limpia slots 0–7 antes de repoblar).

**Whitelist entry — campos de escudo (Energy Shields, ver §19):** `shield_type` (gate maestro: string, key de `ADS.ShieldTypes`), `shield_max_hp` (int fijo `[1,5000]` — NO fracción como limbs), `shield_color` (`{r,g,b}`), `shield_recharge_delay`/`shield_recharge_rate` (float), `shield_can_regen` (bool, `false` legítimo). Saneados en `Sanitize()` de `ads_core.lua`.

**NWvars por entidad (escudo):** `ADS_Shield_State` (int: 0=sin escudo, 1=UP, 2=DOWN, 3=CHARGING), `ADS_Shield_Type` (string), `ADS_Shield_Color` (vector). Escritas solo por `ads_shields.lua`, solo on-change.

## Contrato de red (tab Weapons)

| net string | Dirección | Payload |
|---|---|---|
| `ads_request_weapons_data` | cliente→server | (vacío) |
| `ads_weapons_data` | server→cliente | `CuratedWeapons`, luego `AmmoFallback` (orden importa) |
| `ads_save_curated` | cliente→server | classname + tabla (`{}` vacía = borrar; incluye flags `plasma`/`emp` opcionales) |
| `ads_save_ammo_fallback` | cliente→server | tabla de buckets |

## Contrato de red (Energy Shields)

| net string | Dirección | Payload |
|---|---|---|
| `ads_shield_fx` | server→cliente | `WriteUInt(ev,2)` (1=hit, 2=collapse, 3=restore) + entidad + `WriteVector` (solo si ev=1) |

Enviado con `CRecipientFilter:AddPVS`, nunca broadcast. Es el único net string del subsistema — la config per-NPC viaja piggyback en `ads_modify_list`/`ads_save_curated` ya existentes.

Todos los `net.Receive` del server están gated por `ply:IsAdmin()`. Todo `AddNetworkString` va en `ads_core.lua`.

## Debug

`ads_debug`: `1` compacto (una línea/hit), `2` verbose (bloque por hit), `3` pipeline completo (traza DET del detour + carrera de stash + alertas no_stash). Filtra con `ads_debug_filter <classname>` o `ads_debug_pick` (apunta a un NPC). Comandos de validación: `ads_test_vj_inject`, `ads_dump_vj_scale`.

En el path ARC9, `path=stash` = resuelto por el detour de `AfterShotFunction`; `path=inline_arc9` = fallback inline cuando el stash faltó.

## Git / commits

Sigue [`docs/ads_convenciones_commits.txt`](docs/ads_convenciones_commits.txt): `<tipo>(<alcance>): <descripción>` — tipo en inglés, descripción en español, minúscula inicial, sin punto final, imperativo. Alcances: `core`, `armor`, `limbs`, `scavenger`, `weapons`, `browser`, `hud`, `toolgun`, `config`, `docs`.

Remote: `origin` → `github.com/Sepuldosky/AdvancedDamageSystem-2.0`. Rama principal: `main`. No hagas push ni commit salvo que se pida.

**No agregues el trailer `Co-Authored-By: Claude` (ni ninguna atribución de co-autoría a Claude/Anthropic) en los mensajes de commit.** Esto sobreescribe el comportamiento por defecto del harness.

## Verificación

No hay test runner automatizado (es un addon GMod). Para validar cambios:
- Matemática del resolver → bloque de auto-test comentado en `ads_armor.lua`.
- Comportamiento en juego → cargar mapa, `ads_debug 2`, disparar contra NPC blindado y leer la consola del servidor.
- Al editar código con superficie de runtime, prefiere confirmar el flujo real en juego antes que asumir.

Al cerrar un cambio con superficie de runtime: refresca [`docs/ads_estado.md`](docs/ads_estado.md) en sitio y actualiza [`docs/CHANGELOG.md`](docs/CHANGELOG.md) (`[PENDIENTE]` → `[APLICADO YYYY-MM-DD]`, sin borrar ni renumerar). El orden completo de ejecución de parches está en [`docs/ads_flujo_trabajo.txt`](docs/ads_flujo_trabajo.txt) §1.
