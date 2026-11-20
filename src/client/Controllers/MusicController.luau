--!strict
-- Musique de fond (son "BGMusic" du pack UI, dans Shared/Assets/UISounds).
-- Coupee / remise par le reglage Music (SettingsController -> SetEnabled ; attribut SettingMusic).
-- Doc : docs/systems/interface.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MusicController = {}

local music: Sound? = nil
local enabled = true

local function applyState()
	local sound = music
	if sound == nil then
		return
	end
	if enabled then
		if not sound.IsPlaying then
			if sound.TimePosition > 0 then
				sound:Resume()
			else
				sound:Play()
			end
		end
	else
		sound:Pause()
	end
end

function MusicController:Start()
	local player = Players.LocalPlayer
	enabled = player:GetAttribute("SettingMusic") ~= false
	local sounds = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets"):WaitForChild("UISounds")
	local template = sounds:WaitForChild("BGMusic") :: Sound
	local sound = template:Clone()
	sound.Looped = true
	sound.Parent = player:WaitForChild("PlayerGui")
	music = sound
	applyState()
end

function MusicController.SetEnabled(on: boolean)
	enabled = on
	applyState()
end

return MusicController
