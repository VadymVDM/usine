--!strict
-- Aspect "a construire" d'un groupe de pieces, cote serveur (vu par tous ; GhostVisibilityController
-- le cache chez les autres joueurs) : chaque piece garde sa forme, sa couleur melangee a du bleu
-- clair, transparente, sans collision ni ombre ; textes, effets et lumieres coupes. Meme rendu que
-- les machines fantomes d'UpgradeService. Restore remet exactement l'etat d'origine.
-- Hide / Show : cache completement un groupe (pads pas encore utiles), puis le remet.
-- Utilise par SetupService (usine a construire) et TreeService (arbre pas encore plante).
-- Doc : docs/systems/usine-a-construire.md

local Ghost = {}

local GHOST_COLOR = Color3.fromRGB(150, 205, 255)
local GHOST_TINT = 0.72
local GHOST_TRANSPARENCY = 0.18

type PartLook = {
	color: Color3,
	material: Enum.Material,
	transparency: number,
	canCollide: boolean,
	castShadow: boolean,
}

export type Group = {
	root: Instance,
	looks: { [BasePart]: PartLook },
	effects: { [Instance]: boolean }, -- Enabled d'origine (SurfaceGui, BillboardGui, emetteurs, lumieres)
	prompts: { [ProximityPrompt]: boolean },
	clicks: { [ClickDetector]: number },
	mode: "Normal" | "Ghost" | "Hidden",
}

local function isEffect(item: Instance): boolean
	return item:IsA("SurfaceGui")
		or item:IsA("BillboardGui")
		or item:IsA("ParticleEmitter")
		or item:IsA("Light")
		or item:IsA("Beam")
		or item:IsA("Trail")
		or item:IsA("Highlight")
end

-- Lit l'etat d'origine du groupe (a appeler quand il est encore "normal").
function Ghost.Capture(root: Instance): Group
	local group: Group = { root = root, looks = {}, effects = {}, prompts = {}, clicks = {}, mode = "Normal" }
	local items = root:GetDescendants()
	if root:IsA("BasePart") then
		table.insert(items, root)
	end
	for _, item in items do
		if item:IsA("BasePart") then
			group.looks[item] = {
				color = item.Color,
				material = item.Material,
				transparency = item.Transparency,
				canCollide = item.CanCollide,
				castShadow = item.CastShadow,
			}
		elseif isEffect(item) then
			group.effects[item] = (item :: any).Enabled
		elseif item:IsA("ProximityPrompt") then
			group.prompts[item] = item.Enabled
		elseif item:IsA("ClickDetector") then
			group.clicks[item] = item.MaxActivationDistance
		end
	end
	return group
end

local function setInteractive(group: Group, on: boolean)
	for effect, enabled in group.effects do
		(effect :: any).Enabled = on and enabled
	end
	for prompt, enabled in group.prompts do
		prompt.Enabled = on and enabled
	end
	for click, range in group.clicks do
		click.MaxActivationDistance = if on then range else 0
	end
end

function Ghost.SetMode(group: Group, mode: "Normal" | "Ghost" | "Hidden")
	if group.mode == mode then
		return
	end
	group.mode = mode
	for part, look in group.looks do
		if part.Parent == nil then
			continue
		end
		if mode == "Normal" then
			part.Color = look.color
			part.Material = look.material
			part.Transparency = look.transparency
			part.CanCollide = look.canCollide
			part.CastShadow = look.castShadow
		elseif mode == "Ghost" then
			part.Color = look.color:Lerp(GHOST_COLOR, GHOST_TINT)
			part.Material = Enum.Material.SmoothPlastic
			-- Pieces deja invisibles (zones, marqueurs) : le restent
			part.Transparency = if look.transparency >= 1 then 1 else math.max(look.transparency, GHOST_TRANSPARENCY)
			part.CanCollide = false
			part.CastShadow = false
		else
			part.Color = look.color
			part.Material = look.material
			part.Transparency = 1
			part.CanCollide = false
			part.CastShadow = false
		end
	end
	setInteractive(group, mode == "Normal")
	-- Lus par le client : GhostVisibilityController (fantome cache chez les autres), SetupController
	group.root:SetAttribute("SetupGhost", mode == "Ghost")
	group.root:SetAttribute("SetupHidden", mode == "Hidden")
end

return Ghost
