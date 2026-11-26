--!strict
-- Camera a l'apparition (connexion, retour sur le serveur, mort). Doc : docs/systems/camera.md

local SpawnCamera = {}

-- Saut de position (studs, d'une image a l'autre) qui veut dire "le serveur m'a pose dans ma base"
SpawnCamera.TeleportDistance = 15
-- Duree pendant laquelle on guette ce saut apres l'apparition du personnage (secondes)
SpawnCamera.WatchSeconds = 15
-- Camera placee derriere le personnage (memes valeurs que la sortie de la cinematique)
SpawnCamera.Distance = 12
SpawnCamera.Height = 3.5

return SpawnCamera
