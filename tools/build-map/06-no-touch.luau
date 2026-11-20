--!strict
-- Morceau 06 (lot 6 de la tour d'etages, 2026-11-20) : allege la physique SANS rien changer a l'ecran.
-- Met CanTouch = false sur toutes les pieces de ServerStorage.FloorTemplate et BaseTemplate : le jeu
-- n'utilise jamais l'evenement Touched (pads, fruits, comptoir : le serveur teste la position du
-- joueur). Un etage a ~800 pieces "touchables" : autant de calculs de contact en moins quand un
-- personnage ou un employe bouge. Collisions (CanCollide), rayons (CanQuery) et ombres : inchanges.
-- A lancer en dernier (apres 05) : les scripts 02* recreent des pieces avec CanTouch = true.
-- Doc : docs/systems/carte-bases.md, docs/systems/tour-etages.md (Performance)

local ServerStorage = game:GetService("ServerStorage")

local changed = 0
for _, name in { "FloorTemplate", "BaseTemplate" } do
	local root = ServerStorage:FindFirstChild(name)
	if root == nil then
		warn("[06] " .. name .. " introuvable")
		continue
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.CanTouch then
			d.CanTouch = false
			changed += 1
		end
	end
end
print(`[06] CanTouch = false sur {changed} pieces`)
return changed
