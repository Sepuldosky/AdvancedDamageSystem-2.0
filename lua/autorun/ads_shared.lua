-- Advanced Damage System - registro compartido (corre en server Y cliente)
-- game.AddDecal debe existir en ambos realms: el server emite el decal vía
-- util.Decal (networked) y el cliente lo pinta. Este archivo es la única
-- fuente de verdad del nombre y los materiales (si divergen entre realms,
-- el decal no se pinta o pinta otra cosa).
AddCSLuaFile()

-- Decal de impacto metálico para bloqueos de armadura (Block FX): se pinta
-- ENCIMA del gunshot de flesh que aplica el efecto Impact del cliente.
-- Materiales del grupo "Metal.Shot" de HL2; con tabla, el engine elige uno
-- al azar por aplicación. Elección final sujeta a verificación in-game
-- (alternativa: decal built-in "Impact.Metal").
game.AddDecal("ADS_Ricochet", {
    "decals/metal/shot1_subrect",
    "decals/metal/shot2_subrect",
    "decals/metal/shot3_subrect",
    "decals/metal/shot4_subrect",
    "decals/metal/shot5_subrect",
})
