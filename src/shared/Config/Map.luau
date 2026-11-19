--!strict
-- Carte et bases. Textes visibles par le joueur : en anglais.
-- Doc : docs/systems/carte-bases.md

local Map = {
	MaxBases = 6,
	OwnerSignFormat = "%s's Juice Stand",
	FreeSignText = "Free Stand",
	ServerFullMessage = "All stands are taken. Please join another server.",
	StandAssignedMessage = "A stand is free: it's yours now!", -- joueur en attente qui recoit une base
	LockedZoneText = "Coming soon",
	LockedZoneMessage = "%s: coming soon!", -- clic sur une zone fermee (%s = nom de la zone)
	LockedClickCooldown = 1, -- secondes minimum entre deux messages de zone fermee
	MaxNotifyLength = 120, -- longueur max d'un message Notify (le client coupe au-dela)
	-- Noms des zones fermees (cartes rouges au-dessus des zones 2 et 3)
	LockedZoneNames = table.freeze({
		Zone2 = "Cocktail Bar",
		Zone3 = "Terrace",
	}),
}

return table.freeze(Map)
