--!strict
-- Boutons "Rojo Shared" et "Rojo Unlock" du plugin UsineTools (barre "Usine").
--
-- Dans une place Team Create, le plugin Rojo pose un verrou a chaque Connect :
-- ServerStorage.__Rojo_SessionLock (ObjectValue, Value = le joueur dont Rojo est connecte).
-- Tant que ce joueur est dans la session, Connect echoue chez l'autre :
-- "Could not sync because user 'X' is already syncing". Rojo ne rend le verrou qu'au Disconnect.
--
-- "Rojo Shared" (on/off, choix d'Adam le 2026-11-27) : tant qu'il est allume, le verrou est vide des
-- que Rojo le prend, donc les deux devs peuvent rester connectes en meme temps. Reglage range dans la
-- place (attribut UsineRojoShared sur ServerStorage) : le meme pour tout le monde. Il suffit qu'un seul
-- Studio de la session ait ce plugin pour que ca marche.
--
-- "Rojo Unlock" : vide le verrou une fois, pour prendre la main. Rojo ne relit jamais le verrou une
-- fois connecte, donc le Rojo de l'autre reste connecte. Pour le prevenir, le bouton laisse une marque
-- (attribut) sur le verrou ; chez l'autre, ce module affiche un bandeau "Disconnect" (s'il a ce plugin).
--
-- Verifie dans le code du plugin Rojo 7.7.1 (plugin/src/App/init.lua : isSyncLockAvailable,
-- claimSyncLock, releaseSyncLock). Doc : docs/travailler-a-deux.md

local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local RojoLock = {}

-- Nom fixe dans le plugin Rojo. Champs publics seulement pour pouvoir tester sur un faux verrou.
RojoLock.LockName = "__Rojo_SessionLock"
-- Attribut de ServerStorage : true = mode partage (verrou vide en continu)
RojoLock.SharedAttribute = "UsineRojoShared"
-- Marque laissee sur le verrou : "<UserId de celui qui perd le verrou>|<pseudo de celui qui le prend>|<os.time()>"
RojoLock.MarkAttribute = "UsineUnlock"
local BANNER_NAME = "UsineRojoUnlockBanner"
local TAG = "[Rojo Unlock]"

local function findLock(): ObjectValue?
	local lock = ServerStorage:FindFirstChild(RojoLock.LockName)
	if lock and lock:IsA("ObjectValue") then
		return lock
	end
	return nil
end

-- Meme regle que Rojo (isSyncLockAvailable) : le verrou ne compte que si son joueur est encore la
local function holderOf(lock: ObjectValue): Player?
	local value = lock.Value
	if value and value:IsA("Player") and value.Parent then
		return value
	end
	return nil
end

function RojoLock.IsShared(): boolean
	return ServerStorage:GetAttribute(RojoLock.SharedAttribute) == true
end

function RojoLock.SetShared(on: boolean)
	ServerStorage:SetAttribute(RojoLock.SharedAttribute, if on then true else nil)
end

-- Mode partage : vide le verrou (sans marque ni bandeau). Rojo le croit alors libre a chaque Connect.
local function clearIfShared(lock: Instance)
	if RojoLock.IsShared() and lock:IsA("ObjectValue") and lock.Value ~= nil then
		lock.Value = nil
	end
end

-- Vide le verrou s'il appartient a quelqu'un d'autre. Renvoie le message a afficher et true si le
-- verrou a ete retire.
function RojoLock.Unlock(): (string, boolean)
	local me = Players.LocalPlayer
	if #Players:GetPlayers() == 0 or not me then
		return "No Team Create session here, so Rojo has no lock. Just do Rojo > Connect.", false
	end
	local lock = findLock()
	local holder = if lock then holderOf(lock) else nil
	if not lock or not holder then
		return "Rojo is free. Do Rojo > Connect.", false
	end
	if holder == me then
		return "The Rojo lock is already yours. Do Rojo > Connect (or Disconnect to free it for the other).",
			false
	end
	-- La marque d'abord, puis le verrou : chez l'autre, le bandeau part de la marque
	lock:SetAttribute(RojoLock.MarkAttribute, `{holder.UserId}|{me.Name}|{os.time()}`)
	lock.Value = nil
	return `Removed {holder.Name}'s Rojo lock. Do Rojo > Connect now. Their Rojo is still connected: `
		.. "tell them to click Rojo > Disconnect (a banner asks them to, if they have UsineTools).",
		true
end

-- Bandeau rouge en haut de la vue 3D (CoreGui : visible en mode Edit, jamais sauvegarde)
function RojoLock.ShowBanner(byName: string)
	local old = CoreGui:FindFirstChild(BANNER_NAME)
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = BANNER_NAME
	gui.Archivable = false
	gui.DisplayOrder = 1000
	gui.IgnoreGuiInset = true

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 12)
	frame.Size = UDim2.fromOffset(560, 96)
	frame.BackgroundColor3 = Color3.fromRGB(190, 40, 40)
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(14, 8)
	label.Size = UDim2.new(1, -110, 1, -16)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = `{byName} took over Rojo in this place.\nClick Rojo > Disconnect now, `
		.. "or your Rojo keeps writing your files over theirs."
	label.Parent = frame

	local ok = Instance.new("TextButton")
	ok.AnchorPoint = Vector2.new(1, 0.5)
	ok.Position = UDim2.new(1, -14, 0.5, 0)
	ok.Size = UDim2.fromOffset(76, 40)
	ok.BackgroundColor3 = Color3.new(1, 1, 1)
	ok.Font = Enum.Font.GothamBold
	ok.TextSize = 18
	ok.TextColor3 = Color3.fromRGB(190, 40, 40)
	ok.Text = "OK"
	ok.Parent = frame
	local okCorner = Instance.new("UICorner")
	okCorner.CornerRadius = UDim.new(0, 8)
	okCorner.Parent = ok
	ok.Activated:Connect(function()
		gui:Destroy()
	end)

	gui.Parent = CoreGui
end

-- Ecoute la marque : si c'est moi qui viens de perdre le verrou, bandeau + message dans la Sortie.
-- Seuls les changements comptent (une vieille marque deja presente a l'ouverture est ignoree).
local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function watch(lock: Instance)
	if watched[lock] or not lock:IsA("ObjectValue") then
		return
	end
	watched[lock] = true
	-- Mode partage : Rojo vient de prendre le verrou (Connect) -> on le vide aussitot
	lock:GetPropertyChangedSignal("Value"):Connect(function()
		clearIfShared(lock)
	end)
	clearIfShared(lock)
	lock:GetAttributeChangedSignal(RojoLock.MarkAttribute):Connect(function()
		local mark = lock:GetAttribute(RojoLock.MarkAttribute)
		local me = Players.LocalPlayer
		if typeof(mark) ~= "string" or not me then
			return
		end
		local victimId, byName = string.match(mark, "^(%d+)|([^|]+)|")
		if victimId and byName and tonumber(victimId) == me.UserId then
			warn(`{TAG} {byName} took over Rojo in this place. Click Rojo > Disconnect now.`)
			RojoLock.ShowBanner(byName)
		end
	end)
end

function RojoLock.Watch()
	local lock = ServerStorage:FindFirstChild(RojoLock.LockName)
	if lock then
		watch(lock)
	end
	ServerStorage.ChildAdded:Connect(function(child)
		if child.Name == RojoLock.LockName then
			watch(child)
		end
	end)
	-- Mode partage allume (ici ou chez l'autre) : vider tout de suite le verrou en place
	ServerStorage:GetAttributeChangedSignal(RojoLock.SharedAttribute):Connect(function()
		local current = ServerStorage:FindFirstChild(RojoLock.LockName)
		if current then
			clearIfShared(current)
		end
	end)
end

function RojoLock.Start(toolbar: PluginToolbar)
	local shared = toolbar:CreateButton(
		"RojoShared",
		"Team Create: on = both devs can stay connected to Rojo at the same time. Always git pull before Connect.",
		"rbxasset://textures/ui/icon_friends_16.png",
		"Rojo Shared"
	)
	shared.ClickableWhenViewportHidden = true
	local function refreshShared()
		shared:SetActive(RojoLock.IsShared())
	end
	shared.Click:Connect(function()
		local on = not RojoLock.IsShared()
		RojoLock.SetShared(on)
		if on then
			warn(
				"[Rojo Shared] ON for everyone in this place: both devs can Rojo > Connect at the same time. "
					.. "Always git pull before Connect, and read Rojo's change list before Accept."
			)
		else
			print("[Rojo Shared] OFF: Rojo's normal lock is back (one dev connected at a time).")
		end
		refreshShared()
	end)
	ServerStorage:GetAttributeChangedSignal(RojoLock.SharedAttribute):Connect(refreshShared)
	refreshShared()
	if RojoLock.IsShared() then
		print("[Rojo Shared] ON in this place: both devs can stay connected to Rojo.")
	end

	local button = toolbar:CreateButton(
		"RojoUnlock",
		"Team Create: free the Rojo lock held by the other dev, so you can do Rojo > Connect",
		"rbxasset://textures/ui/mouseLock_off@2x.png",
		"Rojo Unlock"
	)
	button.ClickableWhenViewportHidden = true
	button.Click:Connect(function()
		local message, removed = RojoLock.Unlock()
		if removed then
			warn(`{TAG} {message}`)
		else
			print(`{TAG} {message}`)
		end
		button:SetActive(false)
	end)
	RojoLock.Watch()
end

return RojoLock
