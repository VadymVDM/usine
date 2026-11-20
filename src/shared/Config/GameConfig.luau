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
	-- 2 (2026-11-19) : ancien employe "Presser" -> "Operator1" (operateur du mixeur 1).
	-- 3 (2026-11-19 soir) : TreeSpeed + TreeLuck -> "Tree" ; BowlSize -> niveau de chaque mixeur.
	-- 4 (2026-11-20) : tour d'etages : Upgrades -> Floors[1].Upgrades (Tree <= 10), TowerUpgrades.
	-- 5 (2026-11-20) : OfflineReward (gains hors ligne) ; LastLogout mis a jour a chaque sauvegarde.
	SchemaVersion = 5,
	-- Temps maximum pour ouvrir la session d'un joueur (verrou d'un autre serveur...). Doit depasser
	-- SESSION_STEAL de ProfileStore (40 s) : sinon un verrou abandonne (serveur plante, playtest
	-- coupe) n'est jamais repris et le joueur est renvoye a chaque fois (vu le 2026-11-19 soir).
	LoadTimeoutSeconds = 60,

	-- Reglages du joueur (menu Settings), sauvegardes (Data.Settings, SettingsService).
	-- Seules ces cles sont acceptees par le serveur ; valeurs = valeur par defaut.
	DefaultSettings = table.freeze({
		Music = true, -- musique de fond
		Effects = true, -- sons du jeu et de l'interface
		LowQuality = false, -- sans ombres ni effets (telephones lents)
	}),
	SettingCooldownSeconds = 0.25, -- delai minimum entre deux changements de reglage
	IndexClaimCooldown = 0.15, -- delai minimum entre deux CLAIM de l'Index (IndexService)

	-- Panneau admin (docs/systems/admin.md). Admins = le createur du jeu (s'il appartient a un
	-- compte, pas a un groupe) + ces UserId. En Studio, tout le monde est admin (tests).
	AdminUserIds = table.freeze({
		9061089590, -- Himoxil (demande du 2026-11-19)
	} :: { number }),
	AdminCooldownSeconds = 0.3, -- delai minimum entre deux actions admin (clics rapides pendant les tests)
}

return table.freeze(GameConfig)
