--!strict
-- Carte et bases. Textes visibles par le joueur : en anglais.
-- Doc : docs/systems/carte-bases.md

local Map = {
	MaxBases = 6,
	OwnerSignFormat = "%s's Juice Factory",
	FreeSignText = "Free Factory",
	ServerFullMessage = "All factories are taken. Please join another server.",
	StandAssignedMessage = "A factory is free: it's yours now!", -- joueur en attente qui recoit une base
	MaxNotifyLength = 120, -- longueur max d'un message Notify (le client coupe au-dela)
}

return table.freeze(Map)
