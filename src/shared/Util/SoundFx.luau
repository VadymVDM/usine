--!strict
-- Joue un son de jeu (client seulement) : SoundFx.Play("Pickup"), SoundFx.PlayAt("Sale", position).
-- Les definitions sont dans Config/Sounds.luau. Chaque appel cree un Sound temporaire.
-- Doc : docs/systems/interface.md (section Sons)

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local Sounds = require(script.Parent.Parent:WaitForChild("Config"):WaitForChild("Sounds"))

local SoundFx = {}

-- Volume choisi dans Settings (curseurs, 2026-11-23) : attribut "Setting<key>" pose par
-- SettingsService, nombre 0..1 (ancien booleen false = 0). key = "Effects" (defaut) ou "Music".
function SoundFx.Volume(key: string?): number
	local player = Players.LocalPlayer
	local value = if player then player:GetAttribute("Setting" .. (key or "Effects")) else nil
	if type(value) == "number" then
		return math.clamp(value, 0, 1)
	elseif value == false then
		return 0
	end
	return 1
end

-- Faux si le joueur a mis les sons a 0 dans Settings.
function SoundFx.IsEnabled(): boolean
	return SoundFx.Volume() > 0
end

-- SoundGroup local dont le volume suit le curseur ("Effects" ou "Music") : tout son du jeu y est
-- range (sound.SoundGroup = SoundFx.Group()), meme les boucles deja lancees suivent le curseur.
local groups: { [string]: SoundGroup } = {}
function SoundFx.Group(key: string?): SoundGroup
	local name = key or "Effects"
	local existing = groups[name]
	if existing then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = name .. "Volume"
	group.Volume = SoundFx.Volume(name)
	group.Parent = SoundService
	groups[name] = group
	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal("Setting" .. name):Connect(function()
			group.Volume = SoundFx.Volume(name)
		end)
	end
	return group
end

local rng = Random.new()
local MAX_DISTANCE = 80 -- au-dela, un son place dans le monde n'est pas joue

local function make(name: string, volumeScale: number?, pitchScale: number?): Sound?
	local def = Sounds[name]
	if def == nil or not SoundFx.IsEnabled() then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = def.volume * (volumeScale or 1)
	local jitter = def.pitchJitter or 0
	sound.PlaybackSpeed = ((def.pitch or 1) + rng:NextNumber(-jitter, jitter)) * (pitchScale or 1)
	sound.SoundGroup = SoundFx.Group()
	return sound
end

local function playAndClean(sound: Sound)
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	-- Securite : un son qui ne se charge pas ne doit pas rester
	task.delay(6, function()
		if sound.Parent ~= nil then
			sound:Destroy()
		end
	end)
end

-- Son "a plat" (interface, actions du joueur). pitchScale : 1 = normal (ex. pops qui montent).
function SoundFx.Play(name: string, volumeScale: number?, pitchScale: number?)
	local sound = make(name, volumeScale, pitchScale)
	if sound == nil then
		return
	end
	sound.Parent = SoundService
	playAndClean(sound)
end

-- Son place dans le monde (s'attenue avec la distance).
function SoundFx.PlayAt(name: string, position: Vector3, volumeScale: number?, pitchScale: number?)
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - position).Magnitude > MAX_DISTANCE then
		return
	end
	local sound = make(name, volumeScale, pitchScale)
	if sound == nil then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Parent = workspace.Terrain
	holder.WorldPosition = position
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = MAX_DISTANCE
	sound.Parent = holder
	sound.Ended:Once(function()
		holder:Destroy()
	end)
	task.delay(6, function()
		if holder.Parent ~= nil then
			holder:Destroy()
		end
	end)
	sound:Play()
end

return SoundFx
