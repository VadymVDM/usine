--!strict
-- Valeurs partagees serveur/client. Le serveur reste la seule source de verite
-- pour l'argent, les prix et les recompenses : le client ne fait qu'afficher.
-- Doc : docs/game-design.md, docs/systems/sauvegarde.md

local GameConfig = {
	GameName = "Mon usine de boissons",
	Version = "0.1.0",
	StartingMoney = 0,
	-- Plafond de l'argent : au-dela de 2^53 (~9e15) les entiers ne sont plus exacts.
	MaxMoney = 1e15,
	-- Plafond de securite des rebirths (une sauvegarde abimee ne doit rien casser).
	MaxRebirths = 1000,

	-- Sauvegarde (docs/systems/sauvegarde.md).
	-- Les tests en Studio (avec l'acces API) ecrivent dans ce DataStore : changer le nom
	-- (ex. "PlayerData_v2") avant le lancement pour repartir a zero.
	DataStoreName = "PlayerData_v1",
	SchemaVersion = 1,
	-- Temps maximum pour ouvrir la session d'un joueur (verrou d'un autre serveur...).
	LoadTimeoutSeconds = 30,
}

return table.freeze(GameConfig)
