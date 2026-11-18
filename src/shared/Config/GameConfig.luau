--!strict
-- Valeurs partagees serveur/client. Le serveur reste la seule source de verite
-- pour l'argent, les prix et les recompenses : le client ne fait qu'afficher.
-- Doc : docs/game-design.md

local GameConfig = {
	GameName = "Mon usine de boissons",
	Version = "0.0.1",
	StartingMoney = 0,
}

return table.freeze(GameConfig)
