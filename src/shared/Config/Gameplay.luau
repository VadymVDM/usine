--!strict
-- Valeurs fixes de la boucle de la zone 1 (pas des ameliorations : voir Upgrades.luau).
-- Doc : docs/systems/chaine-production.md, docs/systems/clients.md

local Gameplay = {
	-- Arbre
	MaxGroundFruits = 30, -- au-dela, l'arbre s'arrete : "Tree full!"
	NewFruitGuaranteeDrops = 3, -- un fruit possible pas encore decouvert tombe au plus tard a cette chute
	FirstVisitApples = 3, -- pommes deja au sol pour un profil neuf

	-- Joueur
	CarryCapacity = 20, -- fruits + jus portes au-dessus de la tete (fixe en phase 1)
	PickupRadius = 4, -- studs autour du joueur pour ramasser un fruit
	ContactCheckSeconds = 0.1, -- frequence de detection des contacts par le serveur

	-- Presse
	PressSeconds = 1.5, -- 1 fruit -> 1 jus
	PresserSpeedMultiplier = 2, -- employe Presseur : presse 2 fois plus rapide

	-- Plaques d'achat
	BuyPlateCooldownSeconds = 0.5, -- delai minimum entre deux achats d'un meme joueur
}

return table.freeze(Gameplay)
