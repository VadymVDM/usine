--!strict
-- Cinematique d'ouverture (2026-11-22) : seul module qui ecrit Data.IntroSeen.
-- Au chargement de la sauvegarde : attribut joueur "IntroPending" = vrai pour un profil neuf
-- (IntroSeen == false et Setup == 0) ; le client (IntroController) joue alors la cinematique une fois.
-- Remote IntroDone (client -> serveur, sans argument) : fin ou Skip -> IntroSeen = true (une fois,
-- sauvegarde chargee, delai). Aucun effet sur l'argent ni la partie : seulement "ne plus rejouer".
-- Sans sauvegarde chargee : pas d'attribut, pas d'intro.
-- Doc : docs/systems/cinematique.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))

local DataService = require(script.Parent.DataService)
local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)

local IntroService = {}

local DONE_COOLDOWN = 2

local function onDone(player: Player)
	if not PlayerCheck.Cooldown(player, "IntroDone", DONE_COOLDOWN) then
		return
	end
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	player:SetAttribute("IntroPending", false)
	data.IntroSeen = true
end

function IntroService:Init() end

function IntroService:Start()
	Remotes.GetServerEvent("IntroDone").OnServerEvent:Connect(onDone)
	DataService.OnPlayerLoaded(function(player: Player, data)
		player:SetAttribute("IntroPending", data.IntroSeen ~= true and data.Setup == 0)
	end)
end

return IntroService
