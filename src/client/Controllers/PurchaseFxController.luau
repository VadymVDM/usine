--!strict
-- Ecoute le Feedback "PurchasePrompt" (le serveur vient d'ouvrir une fenetre d'achat Robux pour ce
-- joueur : pads Auto Collect / Auto Sell / Thief, Upgrade, Keep Cash, Lucky Cash) et lance l'effet
-- d'ecran Fx/PurchaseFx (contour arc-en-ciel + zoom). Les fenetres ouvertes par le client (dons,
-- offres) appellent PurchaseFx.Show() elles-memes.
-- Doc : docs/systems/interface.md (section "Envie d'acheter")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"):WaitForChild("Remotes"))
local PurchaseFx = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("PurchaseFx"))

local PurchaseFxController = {}

function PurchaseFxController.Init() end

function PurchaseFxController.Start()
	task.spawn(function()
		local event = Remotes.WaitClientEvent("Feedback")
		if event then
			event.OnClientEvent:Connect(function(kind: unknown)
				if kind == "PurchasePrompt" then
					PurchaseFx.Show()
				end
			end)
		end
	end)
end

return PurchaseFxController
