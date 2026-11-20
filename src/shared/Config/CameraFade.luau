--!strict
-- Camera qui passe a travers les OBJETS et les rend transparents (CameraFadeController, client).
-- Demande du 2026-11-20 : "quand la camera est derriere un objet, l'objet devient transparent" et
-- "la camera peut passer a travers l'arbre".
-- Objet = un Model range dans un des dossiers ci-dessous (arbre, machines, comptoir, arbres de la
-- carte). Le reste (murs, sols, plafonds, escaliers, route, collines) ne s'efface jamais : la camera
-- de Roblox s'arrete devant comme avant (sinon on verrait a travers le plafond ou sous le sol).
-- Doc : docs/systems/camera.md

local CameraFade = {
	-- Objet devant le joueur : 80 % transparent (LocalTransparencyModifier, ce joueur seul). 0.7 teste
	-- le 2026-11-20 : camera dans le feuillage, les couches de feuilles laissaient un voile vert.
	Transparency = 0.8,
	FadeOutSeconds = 0.15, -- temps pour devenir transparent
	FadeInSeconds = 0.35, -- temps pour redevenir opaque
	HoldSeconds = 0.25, -- reste transparent encore un peu apres (pas de clignotement au bord)
	HeadRadius = 1, -- epaisseur de la ligne camera -> tete (studs)
	BodyRadius = 0.7, -- epaisseur de la ligne camera -> bassin
	BodyDrop = 1.2, -- bassin = HumanoidRootPart - X studs
	StartOffset = 0.8, -- les lignes commencent a X studs du joueur (pas l'objet contre lequel il se tient)
	PopMargin = 2, -- la ligne continue X studs derriere la camera : l'objet qui vient de la faire avancer
	MinHeight = 1.5, -- objet plus plat que X studs : jamais efface (tapis, dalles : la camera passerait sous le sol)
	FirstPersonDistance = 1.5, -- camera plus pres que X studs de la tete : vue a la 1re personne, rien a effacer
	RebuildSeconds = 0.5, -- recalcul des boites d'un dossier (objets ajoutes, qui bougent ou grandissent) au plus toutes les X s

	-- Dossiers de CHAQUE etage (Bases.BaseN.Floors.FloorK.<Nom>) dont les Models sont des objets.
	-- Pas Boards / Looks / Donations : panneaux couverts de SurfaceGui (le texte ne s'efface pas).
	FloorFolders = table.freeze({ "Tree", "Production", "Counter", "Machines" }),
	-- Dossiers de la carte (chemin depuis Workspace.Map) dont les Models sont des objets.
	MapFolders = table.freeze({ "Decor/Trees" }),
}

return table.freeze(CameraFade)
