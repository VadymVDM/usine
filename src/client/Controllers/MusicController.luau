--!strict
-- Musique de fond : les morceaux de Config/Music joues l'un apres l'autre (1, 2, 1, 2...).
-- Volume = curseur Music du menu Settings (attribut SettingMusic 0..1, SoundGroup de SoundFx) ;
-- a 0 la musique est en pause. SettingsController appelle SetVolume (meme valeur que l'attribut).
-- Ne commence qu'APRES la cinematique d'ouverture (2026-11-22) : on attend que le serveur ait pose
-- "IntroPending" (sauvegarde chargee), et rien ne joue tant que IntroPending ou IntroPlaying (local,
-- IntroController) est vrai. La musique part alors du debut.
-- Doc : docs/systems/interface.md, docs/systems/cinematique.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tracks = require(Shared:WaitForChild("Config"):WaitForChild("Music"))
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any

local MusicController = {}

local player = Players.LocalPlayer
local sounds: { Sound } = {}
local current = 1 -- morceau en cours
local volume = 1
local introFinished = false -- IntroPlaying est passe de vrai a faux (sans attendre le serveur)

local function introBlocks(): boolean
	if player:GetAttribute("IntroPlaying") == true then
		return true
	end
	-- nil = sauvegarde pas encore chargee : on ne sait pas encore si l'intro va jouer
	return player:GetAttribute("IntroPending") ~= false and not introFinished
end

local function applyState()
	local sound = sounds[current]
	if sound == nil then
		return
	end
	if volume > 0 and not introBlocks() then
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

-- Fin d'un morceau : le suivant part du debut
local function onEnded(index: number)
	if index ~= current or #sounds < 2 then
		return
	end
	sounds[index].TimePosition = 0
	current = index % #sounds + 1
	sounds[current].TimePosition = 0
	applyState()
end

function MusicController:Start()
	volume = SoundFx.Volume("Music")
	local folder = player:WaitForChild("PlayerGui")
	local group = SoundFx.Group("Music")
	for index, track in Tracks do
		local sound = Instance.new("Sound")
		sound.Name = "Music_" .. track.name
		sound.SoundId = track.id
		sound.Volume = track.volume
		sound.Looped = #Tracks == 1
		sound.SoundGroup = group
		sound.Parent = folder
		sound.Ended:Connect(function()
			onEnded(index)
		end)
		sounds[index] = sound
	end
	player:GetAttributeChangedSignal("IntroPending"):Connect(applyState)
	player:GetAttributeChangedSignal("IntroPlaying"):Connect(function()
		if player:GetAttribute("IntroPlaying") == false then
			introFinished = true
		end
		applyState()
	end)
	applyState()
end

-- Volume 0..1 (curseur Music). Le SoundGroup suit deja l'attribut ; ici : pause a 0, reprise sinon.
function MusicController.SetVolume(value: number)
	volume = math.clamp(value, 0, 1)
	applyState()
end

return MusicController
