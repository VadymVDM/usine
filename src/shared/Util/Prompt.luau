--!strict
-- Cree les ProximityPrompt du jeu (touche E, bouton X a la manette, appui sur mobile) toujours
-- de la meme facon. Le serveur ne change jamais `Enabled` : il pose l'attribut "Active" ; le client
-- (PromptController) montre le prompt seulement dans SA base et quand Active ~= false.
-- Le serveur verifie toujours chaque Triggered (proprietaire, distance, etat, delai).
-- Doc : docs/systems/interface.md (section Touche E)

local Prompt = {}

export type Options = {
	name: string?,
	distance: number?,
	hold: number?,
	offset: Vector2?,
}

function Prompt.Create(parent: Instance, objectText: string, actionText: string, options: Options?): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = if options and options.name then options.name else "Prompt"
	prompt.ObjectText = objectText
	prompt.ActionText = actionText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = if options and options.hold then options.hold else 0
	prompt.MaxActivationDistance = if options and options.distance then options.distance else 10
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	if options and options.offset then
		prompt.UIOffset = options.offset
	end
	prompt:SetAttribute("Active", true)
	prompt.Parent = parent
	return prompt
end

function Prompt.SetActive(prompt: ProximityPrompt?, active: boolean)
	if prompt and prompt:GetAttribute("Active") ~= active then
		prompt:SetAttribute("Active", active)
	end
end

function Prompt.SetAction(prompt: ProximityPrompt?, actionText: string)
	if prompt and prompt.ActionText ~= actionText then
		prompt.ActionText = actionText
	end
end

function Prompt.SetObject(prompt: ProximityPrompt?, objectText: string)
	if prompt and prompt.ObjectText ~= objectText then
		prompt.ObjectText = objectText
	end
end

return Prompt
