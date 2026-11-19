--!strict
-- Musique de fond (son "BGMusic" du pack UI, dans Shared/Assets/UISounds).
-- Doc : docs/systems/interface.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MusicController = {}

local music: Sound? = nil

function MusicController:Start()
	local sounds = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets"):WaitForChild("UISounds")
	local template = sounds:WaitForChild("BGMusic") :: Sound
	local sound = template:Clone()
	sound.Looped = true
	sound.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	music = sound
	sound:Play()
end

function MusicController.SetEnabled(enabled: boolean)
	if not music then
		return
	end
	if enabled then
		music:Resume()
	else
		music:Pause()
	end
end

return MusicController
