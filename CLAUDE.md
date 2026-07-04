# CLAUDE.md

Guía para trabajar en **Advanced Damage System 2.0** (addon GLua para Garry's Mod). Léela antes de tocar código.

## Qué es

Sistema de blindaje **zonal** estilo Escape from Tarkov para NPCs y jugadores. Reemplaza —no extiende— la capa de armadura de ADS 1.x. La lógica 1.x (`ADS_Armor` pool único, `ProcessArmor`, `RollArmor`) **no existe en 2.0**; no la reintroduzcas.

**Regla cardinal:** la armadura ADS 2.0 es un **pre-filtro** que se sienta delante de `ads_limbs`. El pool de HP de extremidades NO se modifica para compensar el blindaje. La bala impacta → el resolver calcula penetración/daño a carne/pérdida de energía → el resultado entra a `ads_limbs`/HP nativo como lo haría el daño crudo.

## Idioma

Comentarios y mensajes de commit en **español**; los `<tipo>` de commit van en inglés (ver convenciones). El código existente mezcla comentarios en español e inglés — **iguala el estilo del archivo que estás editando**, no impongas uno nuevo.

## Mapa de archivos

| Archivo | Rol |
|---|---|
| `lua/autorun/server/ads_core.lua` | Núcleo: hook `ScaleNPCDamage`, whitelist/blacklist, multiplicadores de hitgroup, persistencia JSON, `net.Receive`, compat ARC9 (detour `AfterShotFunction` + fallback inline). |
| `lua/autorun/server/ads_armor.lua` | **Funciones puras**: extractor + resolver. Tablas estáticas (materiales, ammo fallback, curated weapons). NWvars de armadura por zona. Sin hooks, sin call sites. |
| `lua/autorun/server/ads_limbs.lua` | HP por extremidad: pools head/arms/legs, debuffs, drop de arma, stun, API de healing. |
| `lua/autorun/server/ads_scavenger.lua` | NPCs recogen armas del suelo. |
| `lua/autorun/client/cl_ads.lua` | Paneles del menú Q (spawnmenu `Options`). |
| `lua/autorun/client/cl_ads_browser.lua` | Browser "ADS Configuration": 4 tabs (Armor / Limbs WL / Weapons / General). |
| `lua/weapons/gmod_tool/stools/ads_config.lua` | Stool de debug efímero (no toca el JSON). |

## Contratos que no debes romper

1. **`ads_armor.lua` es puro.** Solo funciones y tablas. Nada de hooks, `net`, ni escritura de NWvars fuera de las funciones `Init*/Apply*`. Si necesitas un side-effect, va en `ads_core.lua`.
2. **No inyectes campos en `dmginfo`.** Es userdata C++; `dmginfo.ADS_x = y` falla silenciosamente. El tuple viaja como variable local en el call site.
3. **Sync de durabilidad en el mismo tick.** `SetNWInt("ADS_Armor_Dur_"..hg, ...)` se llama en el mismo tick que el cálculo, sin timers — así el perdigón 2 lee la durabilidad tras el perdigón 1.
4. **ARC9 EFT es solo-lectura.** `GetProcessedValue` ya incluye lo que el usuario configuró en el menú ARC9. ADS lee en vivo, nunca escribe. Una sola fuente de verdad.
5. **La autoridad de armadura es `ADS.ArmorProfiles[classname]`.** Su presencia es la única condición que activa el sistema sobre un NPC.

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

**NWvars por entidad:** `ADS_Armor_Class_<hg>`, `ADS_Armor_Dur_<hg>`, `ADS_Armor_MaxDur_<hg>`, `ADS_Armor_Mat_<hg>`, flag `ADS_Armor_Init`. Slot `0` = GENERIC/fallback. `InitArmorNWvars` es **idempotente** (limpia slots 0–7 antes de repoblar).

## Contrato de red (tab Weapons)

| net string | Dirección | Payload |
|---|---|---|
| `ads_request_weapons_data` | cliente→server | (vacío) |
| `ads_weapons_data` | server→cliente | `CuratedWeapons`, luego `AmmoFallback` (orden importa) |
| `ads_save_curated` | cliente→server | classname + tabla (`{}` vacía = borrar) |
| `ads_save_ammo_fallback` | cliente→server | tabla de buckets |

Todos los `net.Receive` del server están gated por `ply:IsAdmin()`. Todo `AddNetworkString` va en `ads_core.lua`.

## Debug

`ads_debug`: `1` compacto (una línea/hit), `2` verbose (bloque por hit), `3` pipeline completo (traza DET del detour + carrera de stash + alertas no_stash). Filtra con `ads_debug_filter <classname>` o `ads_debug_pick` (apunta a un NPC). Comandos de validación: `ads_test_vj_inject`, `ads_dump_vj_scale`.

En el path ARC9, `path=stash` = resuelto por el detour de `AfterShotFunction`; `path=inline_arc9` = fallback inline cuando el stash faltó.

## Git / commits

Sigue [`docs/ads_convenciones_commits.txt`](docs/ads_convenciones_commits.txt): `<tipo>(<alcance>): <descripción>` — tipo en inglés, descripción en español, minúscula inicial, sin punto final, imperativo. Alcances: `core`, `armor`, `limbs`, `scavenger`, `weapons`, `browser`, `hud`, `toolgun`, `config`, `docs`.

Remote: `origin` → `github.com/Sepuldosky/AdvancedDamageSystem-2.0`. Rama principal: `main`. No hagas push ni commit salvo que se pida.

## Verificación

No hay test runner automatizado (es un addon GMod). Para validar cambios:
- Matemática del resolver → bloque de auto-test comentado en `ads_armor.lua`.
- Comportamiento en juego → cargar mapa, `ads_debug 2`, disparar contra NPC blindado y leer la consola del servidor.
- Al editar código con superficie de runtime, prefiere confirmar el flujo real en juego antes que asumir.
