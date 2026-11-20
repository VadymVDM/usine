--!strict
-- Morceau 02k (2026-11-20, demande : "fais une sorte de chemin comme ca, simplement", captures d'un
-- sol d'usine avec des allees plus claires ; puis "fais-le bien comme le screenshot") : ALLEE
-- gris-bleu, une plaque (0.4) au-dessus du sol, a peine plus claire que lui, dans les passages
-- libres de chaque etage. Relancable : detruit et recree FloorTemplate.Building.Walkway.
-- A lancer apres 02a (qui recree FloorTemplate), puis 05, 06, 07 comme d'habitude.
-- Repere de l'etage (voir 02a) : sol a y = 0.5, vu de la route +X est a GAUCHE.
--   Entry    : de la porte (x 8-18, z 15) vers le fond, toute la largeur de la porte x 8-18
--              (le tapis des dons finit a x 7.5 depuis le 2026-11-20).
--   Corridor : couloir entre la vente et le bar a jus, x 8-60.5, z 52-62.
--   ToBack   : vers le verger et l'etagere, x 53.5-60.5 (mixeurs jusqu'a x 48.5, escalier a x 64),
--              jusqu'a z 107.5 (etagere a z 108).
--   ToSales  : du couloir vers le comptoir, x 49-55, z 33-52 (pad Auto Sell x 41-47).
--   SalesWalk: le long des pads du comptoir, x 49-82, z 27-33 (pad Drop Juices finit z 26, pad
--              Collect Cash commence x 84).
-- Les morceaux se touchent sans se chevaucher (anti z-fighting). Plus de sols de zone depuis le
-- 2026-11-20 (02a) : rien d'autre au ras du sol.
-- Solide (on marche DESSUS, la marche de 0.4 se monte toute seule), sans ombre ni contact.
-- Doc : docs/systems/carte-bases.md

local ServerStorage = game:GetService("ServerStorage")

local floorModel = ServerStorage:FindFirstChild("FloorTemplate") :: Model
local building = floorModel:FindFirstChild("Building") :: Folder
local old = building:FindFirstChild("Walkway")
if old then
	old:Destroy()
end

local PATH = Color3.fromRGB(74, 85, 108) -- un peu plus bleu que le sol (74, 80, 93), cale en jeu
local Y0, Y1 = 0.5, 0.9 -- une plaque (0.4) au-dessus du sol

local origin = floorModel:GetPivot()
local folder = Instance.new("Folder")
folder.Name = "Walkway"

local function slab(name: string, x0: number, x1: number, z0: number, z1: number)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true -- le sol du personnage (Humanoid) doit le voir
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Plastic
	p.Color = PATH
	p.TopSurface = Enum.SurfaceType.Studs -- comme les autres sols (07-floor-studs)
	p.BottomSurface = Enum.SurfaceType.Inlet
	p.Size = Vector3.new(x1 - x0, Y1 - Y0, z1 - z0)
	-- Le pivot de FloorTemplate est l'Origin (y 0.5) : coordonnees de 02a = pivot sans rotation, y - 0.5
	p.CFrame = origin * CFrame.new((x0 + x1) / 2, (Y0 + Y1) / 2 - 0.5, (z0 + z1) / 2)
	p.Parent = folder
end

slab("Entry", 8, 18, 15, 52) -- largeur de la porte (x 8-18), depuis le 2026-11-20
slab("Corridor", 8, 60.5, 52, 62)
slab("ToBack", 53.5, 60.5, 62, 107.5)
slab("ToSales", 49, 55, 33, 52)
slab("SalesWalk", 49, 82, 27, 33)

folder.Parent = building
return "Walkway OK : " .. #folder:GetChildren() .. " pieces"
