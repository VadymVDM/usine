--!strict
-- Tutoriel etape par etape (2026-11-22) : seul module qui ecrit Data.TutorialStep (etapes faites,
-- Config/Tutorial.Phases ; Tutorial.Done = fini). Attribut joueur "TutorialStep" pour le client
-- (TutorialController), qui guide et demande le passage a l'etape suivante.
-- Remote TutorialProgress (client -> serveur, numero de l'etape suivante) : entier, exactement
-- l'etape actuelle + 1, sauvegarde chargee, delai. Aucun effet sur l'argent ni la partie (le guidage
-- seulement) : un client modifie ne gagne rien a sauter des etapes. La vitesse gratuite est decidee a
-- part (PlayerUpgradeService, Data.FreeSpeedUsed).
-- Doc : docs/systems/tutoriel.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tutorial = require(Shared:WaitForChild("Config"):WaitForChild("Tutorial"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))

local DataService = require(script.Parent.DataService)
local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)

local TutorialService = {}

local PROGRESS_COOLDOWN = 0.3

local function onProgress(player: Player, step: any)
	if type(step) ~= "number" or step ~= step or step % 1 ~= 0 then
		return
	end
	if not PlayerCheck.Cooldown(player, "TutorialProgress", PROGRESS_COOLDOWN) then
		return
	end
	local data = DataService.GetData(player)
	if data == nil or step ~= data.TutorialStep + 1 or step > Tutorial.Done then
		return
	end
	data.TutorialStep = step
	player:SetAttribute("TutorialStep", step)
end

function TutorialService:Init() end

function TutorialService:Start()
	Remotes.GetServerEvent("TutorialProgress").OnServerEvent:Connect(onProgress)
	DataService.OnPlayerLoaded(function(player: Player, data)
		player:SetAttribute("TutorialStep", data.TutorialStep)
	end)
end

-- Etage Tutorial.StopAtFloor possede (FloorService.refreshAnnex) : tutoriel fini pour de bon
-- (2026-11-23, demande : "apres l'etage 2 ne plus montrer de tuto"). Reste fini apres un rebirth.
function TutorialService.OnFloorsOwned(player: Player, owned: number)
	if owned < Tutorial.StopAtFloor then
		return
	end
	local data = DataService.GetData(player)
	if data == nil or data.TutorialStep >= Tutorial.Done then
		return
	end
	data.TutorialStep = Tutorial.Done
	player:SetAttribute("TutorialStep", data.TutorialStep)
end

-- Tests Studio (DebugService) : met l'etape du tutoriel (ECRIT la sauvegarde).
function TutorialService.DebugSet(player: Player, step: number): boolean
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	data.TutorialStep = math.clamp(math.floor(step), 0, Tutorial.Done)
	player:SetAttribute("TutorialStep", data.TutorialStep)
	return true
end

return TutorialService
