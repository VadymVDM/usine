--!strict
-- Ombres par etage (client seulement, rien n'est envoye au serveur). Demande du 2026-11-27 :
-- "ajoute des ombres super legeres et simples, juste pour rendre le jeu plus joli".
--
-- Probleme : les sols des etages ne projettent pas d'ombre (sinon tout l'interieur serait a l'ombre
-- du soleil). Donc les objets d'un etage (comptoir, arbre, machines, PNJ) projettent AUSSI leur ombre
-- dans les etages du dessous : taches sur le haut des murs, PNJ fantomes qui marchent au sol.
-- Solution : seul l'etage ou se trouve le joueur (meme hauteur, dans chaque tour) garde ses ombres.
-- Les autres etages sont coupes localement (CastShadow = false pour ce joueur seul) et rendus quand
-- le joueur y arrive. Les pieces sans ombre au depart (murs, sols, petites pieces : 05-shadows)
-- ne sont jamais touchees.
-- Doc : docs/systems/carte-bases.md (section Ombres)

local Players = game:GetService("Players")

local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))

local CHECK_SECONDS = 0.25 -- frequence du test "a quel etage est le joueur"
local GHOST_TRANSPARENCY = 0.5 -- piece devenue fantome entre-temps : on ne lui rend pas son ombre

type FloorState = {
	base: Model,
	index: number,
	lit: boolean, -- vrai = ombres actives (etage du joueur)
	muted: { [BasePart]: boolean }, -- pieces dont on a coupe l'ombre
}

local ShadowController = {}

local player = Players.LocalPlayer
local floors: { [Model]: FloorState } = {}

local function mute(part: BasePart, state: FloorState)
	if part.CastShadow then
		part.CastShadow = false
		state.muted[part] = true
	end
end

local function setLit(floor: Model, state: FloorState, lit: boolean)
	if state.lit == lit then
		return
	end
	state.lit = lit
	if lit then
		for part in state.muted do
			if part.Parent ~= nil and part.Transparency < GHOST_TRANSPARENCY then
				part.CastShadow = true
			end
		end
		table.clear(state.muted)
	else
		for _, item in floor:GetDescendants() do
			if item:IsA("BasePart") then
				mute(item, state)
			end
		end
	end
end

-- Hauteur du joueur, nil si pas de personnage (chargement, mort) : on garde l'etat actuel.
local function playerHeight(): number?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position.Y
	end
	return nil
end

local function wantsLit(state: FloorState, y: number?): boolean
	if y == nil then
		return state.index == 1
	end
	return FloorWatch.FloorOfPosition(state.base, y) == state.index
end

local function onFloor(floor: Model, base: Model)
	local state: FloorState = {
		base = base,
		index = FloorWatch.IndexOf(floor),
		lit = true, -- etat du serveur au depart : ombres du moule
		muted = {},
	}
	floors[floor] = state
	-- Pieces ajoutees plus tard (arbre qui grandit, machine construite, PNJ, gobelets)
	local added = floor.DescendantAdded:Connect(function(item: Instance)
		if not state.lit and item:IsA("BasePart") then
			mute(item, state)
		end
	end)
	FloorWatch.OnRemoved(floor, function()
		added:Disconnect()
		floors[floor] = nil
	end)
	setLit(floor, state, wantsLit(state, playerHeight()))
end

function ShadowController:Init() end

function ShadowController:Start()
	FloorWatch.Watch(onFloor)
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			local y = playerHeight()
			if y ~= nil then
				for floor, state in floors do
					setLit(floor, state, wantsLit(state, y))
				end
			end
		end
	end)
end

return ShadowController
