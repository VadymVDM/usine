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
	-- 6 (2026-11-21) : Setup (usine a construire ; anciens profils = tout construit).
	SchemaVersion = 7, -- 7 : TutorialStep + FreeSpeedUsed (2026-11-22)
	-- Temps maximum pour ouvrir la session d'un joueur (verrou d'un autre serveur...). Doit depasser
	-- SESSION_STEAL de ProfileStore (40 s) : sinon un verrou abandonne (serveur plante, playtest
	-- coupe) n'est jamais repris et le joueur est renvoye a chaque fois (vu le 2026-11-19 soir).
	LoadTimeoutSeconds = 60,

	-- Reglages du joueur (menu Settings), sauvegardes (Data.Settings, SettingsService).
	-- Seules ces cles sont acceptees par le serveur ; valeurs = valeur par defaut. Le TYPE de la
	-- valeur par defaut fixe le type accepte : nombre = volume 0..1 (curseur), booleen = interrupteur.
	-- (Music et Effects etaient des booleens jusqu'au 2026-11-23 : DataService convertit les anciens.)
	DefaultSettings = table.freeze({
		Music = 1, -- volume de la musique de fond (0 = coupee)
		Effects = 1, -- volume des sons du jeu et de l'interface (0 = coupes)
		LowQuality = false, -- sans ombres ni effets (telephones lents)
		-- Touches de deplacement (PC seulement, 2026-11-27) : nom d'un Enum.KeyCode de RebindableKeys.
		-- KeyCode = position physique de la touche (W = Z sur un clavier AZERTY). MovementKeysController.
		KeyForward = "W",
		KeyBack = "S",
		KeyLeft = "A",
		KeyRight = "D",
		KeyJump = "Space",
	} :: { [string]: boolean | number | string }),
	-- Touches acceptees pour les reglages Key* (le reste est pris par Roblox ou par le jeu :
	-- E = prompts, I / O = zoom camera, Echap, Tab, /, chiffres = barre d'objets...).
	RebindableKeys = table.freeze({
		A = true, B = true, C = true, D = true, F = true, G = true, H = true, J = true, K = true,
		L = true, M = true, N = true, P = true, Q = true, R = true, S = true, T = true, U = true,
		V = true, W = true, X = true, Y = true, Z = true,
		Up = true, Down = true, Left = true, Right = true,
		Space = true, LeftShift = true, RightShift = true, LeftControl = true, RightControl = true,
	} :: { [string]: boolean }),
	SettingCooldownSeconds = 0.25, -- delai minimum entre deux changements de reglage
	IndexClaimCooldown = 0.15, -- delai minimum entre deux CLAIM de l'Index (IndexService)

	-- Panneau admin (docs/systems/admin.md). Admins = le createur du jeu (s'il appartient a un
	-- compte, pas a un groupe) + ces UserId. En Studio, tout le monde est admin (tests).
	-- Le jeu appartient a un groupe depuis la publication : le createur doit etre dans cette liste.
	AdminUserIds = table.freeze({
		3050299402, -- PROVADNIKE_ROBLOX, createur (jeu passe a un groupe, 2026-11-23)
		9061089590, -- Himoxil (demande du 2026-11-19)
	} :: { number }),
	AdminCooldownSeconds = 0.3, -- delai minimum entre deux actions admin (clics rapides pendant les tests)
}

return table.freeze(GameConfig)
