--!strict
-- Musiques de fond (MusicController), jouees l'une apres l'autre en boucle : 1, 2, 1, 2...
-- volume = volume de base du morceau ; le curseur Music du menu Settings le multiplie.
-- Doc : docs/systems/interface.md (Settings, Sons)

export type Track = { name: string, id: string, volume: number }

local Music: { Track } = {
	-- Musique du pack UI (avant : son "BGMusic" de Shared/Assets/UISounds, meme id et volume)
	{ name = "BGMusic", id = "rbxassetid://1839993539", volume = 0.25 },
	-- Ajoutee le 2026-11-23 (demande utilisateur), Creator Store, 2 min 48
	{ name = "NYOBORA", id = "rbxassetid://103300609979513", volume = 0.25 },
}

return table.freeze(Music)
