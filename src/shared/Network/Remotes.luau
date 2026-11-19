--!strict
-- Seul endroit qui liste les remotes du jeu. Le serveur les cree au demarrage dans
-- ReplicatedStorage.Remotes ; le client les attend avec un delai maximum.
-- Phase 1 : aucun remote client -> serveur (le serveur detecte lui-meme les contacts).
-- Doc : docs/architecture.md (section Remotes)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type RemoteName = "Notify"

-- Nom -> sens et role. Les verifications de chaque remote sont dans docs/architecture.md.
local EVENTS: { [string]: string } = {
	Notify = "serveur -> client : message court en anglais a afficher (ex. serveur plein)",
}

local FOLDER_NAME = "Remotes"
local CLIENT_TIMEOUT_SECONDS = 15

local Remotes = {}

-- Serveur : renvoie le RemoteEvent (le cree s'il n'existe pas encore).
function Remotes.GetServerEvent(name: RemoteName): RemoteEvent
	assert(RunService:IsServer(), "Remotes.GetServerEvent : serveur seulement")
	assert(EVENTS[name] ~= nil, "Remote inconnu : " .. tostring(name))
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		folder = created
	end
	assert(folder)
	local event = folder:FindFirstChild(name)
	if event == nil then
		local created = Instance.new("RemoteEvent")
		created.Name = name
		created.Parent = folder
		event = created
	end
	assert(event and event:IsA("RemoteEvent"), "Remotes : " .. name .. " n'est pas un RemoteEvent")
	return event :: RemoteEvent
end

-- Client : attend le RemoteEvent (nil + avertissement s'il n'arrive pas a temps).
function Remotes.WaitClientEvent(name: RemoteName): RemoteEvent?
	assert(RunService:IsClient(), "Remotes.WaitClientEvent : client seulement")
	assert(EVENTS[name] ~= nil, "Remote inconnu : " .. tostring(name))
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, CLIENT_TIMEOUT_SECONDS)
	local event = if folder then folder:WaitForChild(name, CLIENT_TIMEOUT_SECONDS) else nil
	if event == nil or not event:IsA("RemoteEvent") then
		warn(`[Remotes] {name} introuvable apres {CLIENT_TIMEOUT_SECONDS} s`)
		return nil
	end
	return event :: RemoteEvent
end

return table.freeze(Remotes)
