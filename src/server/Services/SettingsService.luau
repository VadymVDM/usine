--!strict
-- Reglages du joueur (menu Settings) : musique, sons, mode basse qualite, touches de deplacement
-- (Key*, PC, 2026-11-27 : nom de KeyCode de GameConfig.RebindableKeys). Sauvegardes dans
-- Data.Settings (seul module qui ecrit ce champ). Le serveur recopie chaque reglage dans un
-- attribut du joueur "Setting<Cle>" (ex. SettingMusic = true) ; le client (SettingsController)
-- lit ces attributs et applique. Remote SetSetting (client -> serveur) : cle connue
-- (GameConfig.DefaultSettings), valeur du meme type que la defaut (booleen, ou volume : nombre fini
-- ramene dans 0..1 et arrondi au centieme, 2026-11-23), sauvegarde chargee ; demandes trop rapprochees
-- (< SettingCooldownSeconds) regroupees : la derniere valeur demandee est appliquee apres le delai.
-- Aucun effet sur l'argent ou la partie.
-- Doc : docs/systems/interface.md (Settings), docs/systems/sauvegarde.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))

local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local DataService = require(script.Parent.DataService)

local SettingsService = {}

local ATTRIBUTE_PREFIX = "Setting"

type Value = boolean | number | string

-- Valeur acceptee pour `key`, ou nil (cle inconnue, mauvais type, nombre non fini).
local function clean(key: any, value: any): Value?
	if typeof(key) ~= "string" then
		return nil
	end
	local default = GameConfig.DefaultSettings[key]
	if type(default) == "boolean" then
		return if typeof(value) == "boolean" then value else nil
	elseif type(default) == "number" then
		if typeof(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
			return nil
		end
		return math.round(math.clamp(value, 0, 1) * 100) / 100
	elseif type(default) == "string" then
		-- Touche de deplacement : seulement un nom de la liste GameConfig.RebindableKeys
		return if typeof(value) == "string" and GameConfig.RebindableKeys[value] == true then value else nil
	end
	return nil
end

local function publish(player: Player, settings: { [string]: Value })
	for key, default in GameConfig.DefaultSettings do
		local value = settings[key]
		player:SetAttribute(ATTRIBUTE_PREFIX .. key, if type(value) == type(default) then value else default)
	end
	player:SetAttribute("SettingsLoaded", true)
end

-- Demandes trop rapides : on garde la DERNIERE valeur demandee et on l'applique apres le delai
-- (le client a deja change l'interrupteur a l'ecran : il doit finir d'accord avec la sauvegarde).
local pending: { [Player]: { [string]: Value } } = {}
local flushScheduled: { [Player]: boolean } = {}

local function store(player: Player, key: string, value: Value)
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	data.Settings[key] = value
	player:SetAttribute(ATTRIBUTE_PREFIX .. key, value)
end

local function flush(player: Player)
	flushScheduled[player] = nil
	local wanted = pending[player]
	pending[player] = nil
	if wanted == nil or player.Parent ~= Players then
		return
	end
	PlayerCheck.ResetCooldown(player, "SetSetting")
	PlayerCheck.Cooldown(player, "SetSetting", GameConfig.SettingCooldownSeconds)
	for key, value in wanted do
		store(player, key, value)
	end
end

local function onSetSetting(player: Player, key: any, raw: any)
	local value = clean(key, raw)
	if value == nil then
		return
	end
	if PlayerCheck.Cooldown(player, "SetSetting", GameConfig.SettingCooldownSeconds) then
		store(player, key, value)
		return
	end
	local wanted = pending[player] or {}
	wanted[key] = value
	pending[player] = wanted
	if not flushScheduled[player] then
		flushScheduled[player] = true
		task.delay(GameConfig.SettingCooldownSeconds, flush, player)
	end
end

function SettingsService:Init()
	Remotes.GetServerEvent("SetSetting")
end

function SettingsService:Start()
	Remotes.GetServerEvent("SetSetting").OnServerEvent:Connect(onSetSetting)
	DataService.OnPlayerLoaded(function(player: Player, data)
		if player.Parent == Players then
			publish(player, data.Settings)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
		flushScheduled[player] = nil
	end)
end

return SettingsService
