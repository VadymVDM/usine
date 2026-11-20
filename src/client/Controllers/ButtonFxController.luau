--!strict
-- Branche l'animation commune des boutons (UI/ButtonFx : survol, appui, rebond, sons) sur TOUS les
-- boutons de toutes les interfaces du joueur (PlayerGui), y compris celles creees plus tard
-- (Donations, Floors, Admin, confirmations d'achat, Welcome Back, offres...). Retour de test du
-- 2026-11-20 : "des fois il y a l'animation, des fois non, ca depend les interfaces".
-- MenuController branche aussi le HUD et les menus du ShopGUI (avec l'UIScale du pack) : ButtonFx
-- ne branche jamais deux fois le meme bouton.
-- Exception : les boutons decoratifs du menu Rebirth du pack (seuls RebirthButton / SkipButton
-- s'animent, comme avant). Pour exclure un bouton : attribut NoButtonFx = true.
-- Doc : docs/systems/interface.md (section Retour des boutons)

local Players = game:GetService("Players")

local ButtonFx = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("ButtonFx"))

local ButtonFxController = {}

local started = false

local function wanted(button: GuiButton): boolean
	local rebirth = button:FindFirstAncestor("Rebirth")
	if rebirth and rebirth.Parent and rebirth.Parent.Name == "MenuFrames" then
		return button.Name == "RebirthButton" or button.Name == "SkipButton"
	end
	return true
end

function ButtonFxController.Init() end

function ButtonFxController.Start()
	if started then
		return
	end
	started = true
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	ButtonFx.AutoBind(playerGui, wanted)
end

return ButtonFxController
