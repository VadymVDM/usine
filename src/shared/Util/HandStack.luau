--!strict
-- Plateau de jus sur la tete (comme le plateau des fruits) : place de chaque gobelet.
-- Partage : le serveur s'en sert pour dire d'ou partent les jus poses au comptoir, le client
-- (HandStackController) pour dessiner le plateau. Doc : docs/systems/chaine-production.md (Mains)

local Config = script.Parent.Parent:WaitForChild("Config")
local Gameplay = require(Config:WaitForChild("Gameplay")) :: any
local FruitModels = require(script.Parent.Parent:WaitForChild("FruitModels")) :: any

local HandStack = {}

HandStack.LayerHeight = FruitModels.CupHeight + 0.02
HandStack.TrayThick = 0.2
HandStack.TraySize = Gameplay.JuiceCupSpacing * 3 + 0.4 -- 3 x 3 gobelets + marge

-- Haut de la tete -> dessus du plateau. `hasFruits` : le plateau des fruits est deja sur la tete,
-- le plateau de jus passe au-dessus de son tas.
function HandStack.TrayOffset(head: BasePart, hasFruits: boolean): CFrame
	local lift = if hasFruits then Gameplay.JuiceTrayFruitLift else 0
	return CFrame.new(0, head.Size.Y / 2 + Gameplay.TrayAboveHead + HandStack.TrayThick + lift, 0)
end

-- Pied du gobelet n (1 = en bas) dans le repere du dessus du plateau : couches de 3 x 3.
function HandStack.SlotOffset(index: number): CFrame
	local spacing = Gameplay.JuiceCupSpacing
	local layer = (index - 1) // 9
	local slot = (index - 1) % 9
	local col = slot % 3 - 1
	local row = slot // 3 - 1
	return CFrame.new(col * spacing, layer * HandStack.LayerHeight, row * spacing)
end

-- Position monde du gobelet n sur la tete d'un personnage (nil sans tete).
function HandStack.WorldSlot(character: Model, index: number): CFrame?
	local head = character:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return nil
	end
	local fruits = character:GetAttribute("TrayFruits")
	local hasFruits = type(fruits) == "string" and fruits ~= ""
	return head.CFrame * HandStack.TrayOffset(head, hasFruits) * HandStack.SlotOffset(index)
end

-- Ids portes, lus depuis l'attribut "HandJuices" du personnage ("Apple;Orange").
function HandStack.Decode(value: any): { string }
	local ids: { string } = {}
	if type(value) ~= "string" or value == "" then
		return ids
	end
	for id in string.gmatch(value, "[^;]+") do
		table.insert(ids, id)
		if #ids >= 40 then
			break
		end
	end
	return ids
end

return HandStack
