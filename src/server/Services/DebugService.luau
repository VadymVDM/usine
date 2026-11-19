--!strict
-- Outil de test, actif SEULEMENT dans Studio : permet aux tests (MCP, barre de commande) d'appeler
-- les vrais services du jeu. Un require depuis la barre de commande cree une copie separee des
-- modules : on passe donc par un BindableFunction serveur (invisible pour les clients).
-- Usage (serveur, en playtest) :
--   game.ServerStorage.Debug.Call:Invoke("Money", "Add", "<NomJoueur>", 100)
--   game.ServerStorage.Debug.Call:Invoke("Base", "SimulateFull", "<NomJoueur>")
-- Doc : docs/systems/argent.md (section Tests)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local MoneyService = require(script.Parent.MoneyService)

local DebugService = {}

type Handler = (player: Player, ...any) -> any

local handlers: { [string]: { [string]: Handler } } = {
	Money = {
		Add = function(player, amount)
			return MoneyService.Add(player, amount, "debug")
		end,
		TrySpend = function(player, amount)
			return MoneyService.TrySpend(player, amount, "debug")
		end,
		Get = function(player)
			return MoneyService.Get(player)
		end,
	},
	Base = {
		Get = function(player)
			local base = BaseService.GetBase(player)
			return if base then base.Name else nil
		end,
		-- Simule un serveur plein (7e joueur) puis revient a la normale
		SimulateFull = function(player)
			return BaseService.DebugSimulateFull(player)
		end,
		EndSimulation = function(player)
			return BaseService.DebugEndSimulation(player)
		end,
	},
	Data = {
		Get = function(player)
			local data = DataService.GetData(player)
			if data == nil then
				return nil
			end
			return {
				Money = data.Money,
				Upgrades = table.clone(data.Upgrades),
				DiscoveredFruits = table.clone(data.DiscoveredFruits),
				FirstVisit = DataService.IsFirstVisit(player),
				SavingEnabled = DataService.IsSavingEnabled(),
			}
		end,
	},
}

function DebugService:Init()
	if not RunService:IsStudio() then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Debug"
	local call = Instance.new("BindableFunction")
	call.Name = "Call"
	call.OnInvoke = function(system: string, action: string, playerName: string, ...: any): any
		local group = handlers[system]
		local handler = group and group[action]
		local player = Players:FindFirstChild(playerName)
		if handler == nil or player == nil or not player:IsA("Player") then
			return "unknown system/action/player"
		end
		return handler(player, ...)
	end
	call.Parent = folder
	folder.Parent = ServerStorage
end

return DebugService
