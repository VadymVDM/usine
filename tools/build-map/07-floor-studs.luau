--!strict
-- Morceau 07 (2026-11-20, demande de l'utilisateur : "pour le sol utilise les autres studs, les studs
-- comme sur la route") : le DESSUS de tout ce sur quoi on marche passe de Inlet (creux) a Studs
-- (bosses, comme la route). Change seulement TopSurface = Inlet -> Studs ; le dessous des pieces
-- (BottomSurface = Inlet) ne bouge pas.
-- Concerne ServerStorage.FloorTemplate, ServerStorage.BaseTemplate et Workspace.Map (herbe, trottoirs).
-- A lancer en DERNIER (apres 06) : les scripts 01-05 posent encore Inlet sur les sols.
-- Doc : docs/style.md (Regle des 2 studs)

local ServerStorage = game:GetService("ServerStorage")

local roots: { Instance? } = {
	ServerStorage:FindFirstChild("FloorTemplate"),
	ServerStorage:FindFirstChild("BaseTemplate"),
	workspace:FindFirstChild("Map"),
}
local changed = 0
for _, root in roots do
	if root == nil then
		continue
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.TopSurface == Enum.SurfaceType.Inlet then
			d.TopSurface = Enum.SurfaceType.Studs
			changed += 1
		end
	end
end
print(`[07] sols en Studs : {changed} pieces`)
return changed
