--!strict
-- Tour d'etages (phase 1b) : construit et retire les etages des bases, achat de l'etage suivant,
-- teleport entre les etages, apparition sur l'etage le plus haut, annexe (terrasse, salle "???").
--   * Base libre : Floors.Floor1 (ouvert, ameliorations de depart) + Floor2 ferme (coque bleue).
--   * Base d'un joueur charge : ses etages achetes (#Data.Floors) + le suivant ferme. Jamais une
--     tour vide de 10. Au depart du joueur, on revient a la base libre (l'etage 1 reste).
--   * Achat : prompt E sur la vitre rouge (Stairs.BuyGate) de l'etage ferme. Verifie : proprietaire,
--     c'est bien l'etage suivant, distance, delai, argent (MoneyService.TrySpend). Puis l'etage
--     ouvert remplace la coque (attribut BuildStamp : le client l'anime et montre "NEW FLOOR!").
--   * Etage 2 achete : la terrasse s'ouvre (TerraceGate retiree). Etage 10 : la vitre
--     de la salle "???" s'ouvre, son panneau devient "REBIRTH" ; E sur la machine ouvre le menu
--     Rebirth cote client (RebirthController). Le rebirth lui-meme : RebirthService, qui appelle
--     ResetForRebirth (tour remise a 1 etage, ascenseur a 0).
--   * Niveaux d'un etage neuf (achat, rebirth) : Upgrades.DefaultLevels(), modifiables par
--     SetNewFloorLevels (RebirthService : pass Rebirth Master = l'arbre garde son niveau).
--   * Remote FloorTeleport (numero d'etage) : fleches du selecteur d'etage en haut de l'ecran
--     (FloorController). Plus de panneaux FLOORS depuis le 2026-11-20.
-- Les autres services ne connaissent que des ETAGES : ils s'abonnent a OnFloorAdded (etage ouvert
-- cree, proprietaire ou non), OnFloorStarted / OnFloorStopped (etage d'un joueur charge : demarrer
-- / arreter arbre, production, ventes, employes) et OnFloorRemoving (etage detruit).
-- Seul module qui modifie la LONGUEUR de Data.Floors (ajout d'un etage) et les dossiers base.Floors.
-- Doc : docs/systems/tour-etages.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local FloorsConfig = require(Config:WaitForChild("Floors"))
local Gameplay = require(Config:WaitForChild("Gameplay"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Util = Shared:WaitForChild("Util")
local NumberFormat = require(Util:WaitForChild("NumberFormat"))
local Prompt = require(Util:WaitForChild("Prompt"))
local UpgradeTile = require(Util:WaitForChild("UpgradeTile"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))

local FloorAssembly = require(script.Parent.Parent.Lib.FloorAssembly)
local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local OwnerBadge = require(script.Parent.Parent.Lib.OwnerBadge)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local MoneyService = require(script.Parent.MoneyService)
local NotifyService = require(script.Parent.NotifyService)
local TutorialService = require(script.Parent.TutorialService)

local FloorService = {}

type AddedCallback = (floor: Model, index: number) -> ()
type PlayerCallback = (player: Player, floor: Model, index: number) -> ()

type Tower = {
	base: Model,
	folder: Folder, -- base.Floors
	floors: { [number]: Model }, -- etages ouverts (1..owned)
	closed: Model?, -- etage suivant ferme
	player: Player?, -- proprietaire dont les etages tournent (nil = base libre ou pas encore charge)
	hidden: { [Instance]: Instance }, -- portes de l'annexe retirees -> leur parent d'origine
	rebirthPrompt: ProximityPrompt?,
	rebirthSign: TextLabel?, -- panneau du fond de la salle du Rebirth ("???" fermee, "REBIRTH" ouverte)
	towerTiles: { [string]: { model: Model, tile: BasePart?, click: ClickDetector? } }, -- panneau Elevator (terrasse, clic)
}

local towers: { [Model]: Tower } = {}
local floorIndex: { [Model]: number } = {} -- etage ouvert -> numero
local floorBase: { [Model]: Model } = {} -- etage ouvert -> base
local addedCallbacks: { AddedCallback } = {}
local removingCallbacks: { AddedCallback } = {}
local startedCallbacks: { PlayerCallback } = {}
local stoppedCallbacks: { PlayerCallback } = {}
-- Etage ou se trouve chaque joueur dans sa tour (lot 5 : seul cet etage est dessine en entier)
local liveFloor: { [Player]: Model } = {}
local liveCallbacks: { (player: Player, old: Model?, new: Model?) -> () } = {}

local function run(list: { any }, label: string, ...: any)
	for _, callback in list do
		local ok, err = pcall(callback, ...)
		if not ok then
			warn(`[FloorService] Erreur dans {label} : {err}`)
		end
	end
end

local function getTemplate(): Model?
	local template = ServerStorage:FindFirstChild("FloorTemplate")
	if template == nil or not template:IsA("Model") then
		warn("[FloorService] ServerStorage.FloorTemplate manquant : relancer tools/build-map/02*.")
		return nil
	end
	return template
end

local function floorTitle(n: number): string
	return string.format(FloorsConfig.TitleFormat, n)
end

-- Premier PromptAnchor (BasePart) sous `parent`.
local function anchorIn(parent: Instance): BasePart?
	local anchor = parent:FindFirstChild("PromptAnchor", true)
	return if anchor and anchor:IsA("BasePart") then anchor else nil
end

---------------------------------------------------------------------------------------------
-- Construction / destruction

local onBuyPrompt: (player: Player, base: Model, n: number) -> ()

local function buildOpen(tower: Tower, n: number, stamp: boolean): Model?
	local template = getTemplate()
	if template == nil then
		return nil
	end
	local floor = FloorAssembly.Build(template, n, false, tower.base:GetPivot())
	if stamp then
		floor:SetAttribute("BuildStamp", workspace:GetServerTimeNow())
	end
	floor.Parent = tower.folder
	tower.floors[n] = floor
	floorIndex[floor] = n
	floorBase[floor] = tower.base
	run(addedCallbacks, "OnFloorAdded", floor, n)
	return floor
end

local function buildClosed(tower: Tower, n: number)
	if tower.closed then
		tower.closed:Destroy()
		tower.closed = nil
	end
	if n > FloorsConfig.MaxFloors then
		return
	end
	local template = getTemplate()
	if template == nil then
		return
	end
	local floor = FloorAssembly.Build(template, n, true, tower.base:GetPivot())
	local price = FloorsConfig.Price(n) or 0
	for _, item in floor:GetDescendants() do
		if item:IsA("TextLabel") then
			if item.Name == "FloorName" then
				item.Text = floorTitle(n)
			elseif item.Name == "Status" then
				item.Text = "$" .. NumberFormat.Abbreviate(price)
			end
		end
	end
	local gate = floor:FindFirstChild("BuyGate", true)
	local anchor = gate and anchorIn(gate)
	if anchor then
		local prompt = Prompt.Create(anchor, string.format(FloorsConfig.PromptBuyObject, n), `{Gameplay.PromptTexts.Buy} ${NumberFormat.Abbreviate(price)}`, {
			name = "BuyFloorPrompt",
			distance = Gameplay.PromptDistance,
			hold = Gameplay.BuyHoldSeconds,
		})
		local base = tower.base
		prompt.Triggered:Connect(function(player: Player)
			local ok, err = pcall(onBuyPrompt, player, base, n)
			if not ok then
				warn(`[FloorService] Erreur d'achat d'etage : {err}`)
			end
		end)
	else
		warn(`[FloorService] {tower.base.Name} : Stairs.BuyGate.PromptAnchor manquant (etage {n})`)
	end
	floor.Parent = tower.folder
	tower.closed = floor
end

local function destroyOpen(tower: Tower, n: number)
	local floor = tower.floors[n]
	if floor == nil then
		return
	end
	run(removingCallbacks, "OnFloorRemoving", floor, n)
	tower.floors[n] = nil
	floorIndex[floor] = nil
	floorBase[floor] = nil
	floor:Destroy()
end

local function ownedCount(tower: Tower): number
	return #tower.floors
end

---------------------------------------------------------------------------------------------
-- Annexe : terrasse (etage 2) et salle "???" (etage 10)

local function setShown(tower: Tower, item: Instance?, shown: boolean)
	if item == nil then
		return
	end
	if shown then
		local parent = tower.hidden[item]
		if parent then
			item.Parent = parent
			tower.hidden[item] = nil
		end
	elseif item.Parent ~= nil then
		tower.hidden[item] = item.Parent :: Instance
		item.Parent = nil
	end
end

local function findAnnex(tower: Tower, path: { string }): Instance?
	local current: Instance? = tower.base:FindFirstChild("Annex")
	for _, name in path do
		if current == nil then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

-- Les portes deja retirees ne sont plus dans le modele : on garde leur reference.
local function gateRef(tower: Tower, path: { string }): Instance?
	local found = findAnnex(tower, path)
	if found then
		return found
	end
	local last = path[#path]
	for item in tower.hidden do
		if item.Name == last then
			return item
		end
	end
	return nil
end

local refreshTowerBoard: (tower: Tower) -> () -- panneau Elevator (plus bas)

local function refreshAnnex(tower: Tower)
	local owned = if tower.player then ownedCount(tower) else 1
	local terraceOpen = owned >= 2
	setShown(tower, gateRef(tower, { "Terrace", "TerraceGate" }), not terraceOpen)
	-- (StreetGate et murs invisibles Blocker* de la terrasse retires le 2026-11-20 : terrasse ouverte)
	-- Cabine de l'ascenseur : visible des l'etage 2 (animee cote client)
	setShown(tower, gateRef(tower, { "ElevatorBase", "Cabin" }), terraceOpen)
	local rebirthOpen = owned >= FloorsConfig.MaxFloors
	setShown(tower, gateRef(tower, { "RebirthRoom", "RebirthGate" }), not rebirthOpen)
	Prompt.SetActive(tower.rebirthPrompt, rebirthOpen)
	if tower.rebirthSign then
		tower.rebirthSign.Text = if rebirthOpen then FloorsConfig.RebirthRoomOpenTitle else FloorsConfig.RebirthRoomTitle
	end
	tower.base:SetAttribute("FloorsOwned", if tower.player then owned else 0)
	if tower.player then
		TutorialService.OnFloorsOwned(tower.player, owned) -- etage 2 : tutoriel fini (2026-11-23)
	end
	refreshTowerBoard(tower)
	-- Logo du proprietaire au-dessus de l'etage le plus haut (l'etage ferme a acheter compte),
	-- avec son nombre de rebirths (rebirth : appele apres data.Rebirths + 1)
	local ownerData = if tower.player then DataService.GetData(tower.player) else nil
	OwnerBadge.Update(
		tower.base,
		tower.player,
		if owned < FloorsConfig.MaxFloors then owned + 1 else owned,
		if ownerData then ownerData.Rebirths else 0
	)
end

---------------------------------------------------------------------------------------------
-- Panneau Elevator de la terrasse (lot 5) : ameliorations de toute la tour (Data.TowerUpgrades).
-- Effet : plus d'argent par vente aux etages 2+ (Lib/FloorIncome.ElevatorBonus ; avant le
-- 2026-11-20 : clients plus rapides). La cabine reste animee plus vite / plus remplie (client).
-- Seul module qui modifie Data.TowerUpgrades.

local function towerLevel(tower: Tower, id: string): number
	local player = tower.player
	local data = if player then DataService.GetData(player) else nil
	return if data then data.TowerUpgrades[id] or 0 else 0
end

function refreshTowerBoard(tower: Tower)
	for id, tile in tower.towerTiles do
		local level = towerLevel(tower, id)
		local bonus = if id == "ElevatorSpeed" then FloorsConfig.ElevatorSpeedBonus else FloorsConfig.ElevatorCabinBonus
		local atMax = level >= FloorsConfig.TowerUpgradeMaxLevel
		local price = FloorsConfig.TowerUpgradePrice(id, level) or 0
		local priceText = if atMax then "MAX" else "$" .. NumberFormat.Abbreviate(price)
		for _, item in tile.model:GetDescendants() do
			if item:IsA("TextLabel") then
				if item.Name == "Value" then
					local now = math.floor(level * bonus * 100 + 0.5)
					local nextValue = math.floor((level + 1) * bonus * 100 + 0.5)
					item.Text = if atMax then `+{now}% MAX` else `+{now}%{UpgradeTile.ARROW}+{nextValue}%`
				elseif item.Name == "Level" then
					item.Text = `Lv {level}`
				elseif item.Name == "Price" then
					item.Text = priceText
				end
			end
		end
		if tile.click then
			local active = tower.player ~= nil and not atMax and ownedCount(tower) >= 2
			tile.click.MaxActivationDistance = if active then Gameplay.TileClickDistance else 0
		end
		tower.base:SetAttribute(id, level)
	end
end

local function onTowerUpgrade(player: Player, tower: Tower, id: string)
	local tile = tower.towerTiles[id]
	if tile == nil or tower.player ~= player or ownedCount(tower) < 2 then
		return
	end
	local data = DataService.GetData(player)
	if data == nil or not PlayerCheck.Cooldown(player, "TowerUpgrade", Gameplay.BuyCooldownSeconds) then
		return
	end
	local target = tile.tile
	if target == nil or not PlayerCheck.CanReach(player, target.Position, Gameplay.TileClickDistance + Gameplay.BuyClickExtraDistance) then
		return
	end
	local level = data.TowerUpgrades[id] or 0
	local price = FloorsConfig.TowerUpgradePrice(id, level)
	if price == nil or level >= FloorsConfig.TowerUpgradeMaxLevel then
		return
	end
	if not MoneyService.TrySpend(player, price, "Tower:" .. id) then
		NotifyService.Notify(player, FloorsConfig.Messages.NotEnoughMoney, true)
		return
	end
	data.TowerUpgrades[id] = level + 1
	local bumped = tile.model:GetAttribute("Bought")
	tile.model:SetAttribute("Bought", (if type(bumped) == "number" then bumped else 0) + 1)
	refreshTowerBoard(tower)
end

-- Niveaux d'un etage neuf (achat, rebirth, outils de test). RebirthService peut les changer
-- (pass Rebirth Master : l'arbre reprend son ancien niveau) via SetNewFloorLevels.
local newFloorResolver: ((player: Player, n: number) -> { [string]: number }?)? = nil

local function newFloorLevels(player: Player, n: number): { [string]: number }
	local resolver = newFloorResolver
	if resolver then
		local ok, levels = pcall(resolver, player, n)
		if ok and type(levels) == "table" then
			return levels
		elseif not ok then
			warn(`[FloorService] Erreur des niveaux d'un etage neuf : {levels}`)
		end
	end
	return Upgrades.DefaultLevels()
end

---------------------------------------------------------------------------------------------
-- Joueurs

local function setLive(player: Player, floor: Model?)
	local old = liveFloor[player]
	if old == floor then
		return
	end
	liveFloor[player] = floor
	local base = BaseService.GetBase(player)
	if base then
		base:SetAttribute("ActiveFloor", if floor then floorIndex[floor] else nil)
	end
	run(liveCallbacks, "OnLiveFloorChanged", player, old, floor)
end

local function stopTower(tower: Tower)
	local player = tower.player
	if player == nil then
		return
	end
	setLive(player, nil)
	tower.player = nil
	for n = ownedCount(tower), 1, -1 do
		local floor = tower.floors[n]
		if floor then
			run(stoppedCallbacks, "OnFloorStopped", player, floor, n)
		end
	end
end

-- Remet la base libre : etage 1 (vide) + etage 2 ferme.
local function resetTower(tower: Tower)
	stopTower(tower)
	for n = ownedCount(tower), 2, -1 do
		destroyOpen(tower, n)
	end
	local ground = tower.floors[1]
	local dynamic = ground and ground:FindFirstChild("Dynamic")
	if dynamic then
		dynamic:ClearAllChildren()
	end
	buildClosed(tower, 2)
	refreshAnnex(tower)
end

-- Point d'apparition d'un etage (Markers.SpawnPoint), un peu au-dessus du sol.
local function spawnCFrame(floor: Model?): CFrame?
	local markers = floor and floor:FindFirstChild("Markers")
	local point = markers and markers:FindFirstChild("SpawnPoint")
	if point and point:IsA("BasePart") and floor then
		-- Regard bien droit vers l'interieur de l'usine (axe +Z du modele d'etage : la porte est
		-- cote Z petit), quelle que soit la rotation de la piece SpawnPoint (tournee de 33 degres
		-- dans le .rbxl : vue de travers apres la cinematique).
		local rotation = floor:GetPivot().Rotation * CFrame.Angles(0, math.pi, 0)
		return CFrame.new(point.Position + Vector3.new(0, 3, 0)) * rotation
	end
	return nil
end

-- StreamingEnabled : on demande d'abord au client de charger l'etage d'arrivee, sinon le
-- personnage tombe a travers les dalles pas encore recues (vu en test : etage 10 -> etage 8).
local function teleportTo(player: Player, floor: Model?)
	local target = spawnCFrame(floor)
	if target == nil then
		return
	end
	pcall(function()
		player:RequestStreamAroundAsync(target.Position, FloorsConfig.StreamTimeout)
	end)
	local character = player.Character
	if character and PlayerCheck.GetRoot(player) then
		character:PivotTo(target)
	end
end

-- Construit la tour du joueur des qu'il a sa base ET sa sauvegarde.
local function tryStart(player: Player)
	local base = BaseService.GetBase(player)
	local data = DataService.GetData(player)
	local tower = base and towers[base]
	if tower == nil or data == nil or tower.player == player then
		return
	end
	if tower.player ~= nil then
		resetTower(tower)
	end
	local owned = math.clamp(DataService.FloorsOwned(data), 1, FloorsConfig.MaxFloors)
	if tower.closed then
		tower.closed:Destroy()
		tower.closed = nil
	end
	for n = 2, owned do
		if tower.floors[n] == nil then
			buildOpen(tower, n, false)
		end
	end
	buildClosed(tower, owned + 1)
	tower.player = player
	for n = 1, owned do
		local floor = tower.floors[n]
		if floor then
			run(startedCallbacks, "OnFloorStarted", player, floor, n)
		end
	end
	refreshAnnex(tower)
	-- Le personnage est peut-etre deja apparu au rez-de-chaussee : on le monte en haut.
	if owned > 1 then
		teleportTo(player, tower.floors[owned])
	end
end

function onBuyPrompt(player: Player, base: Model, n: number)
	local tower = towers[base]
	if tower == nil or tower.player ~= player or BaseService.GetBase(player) ~= base then
		return
	end
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	if not PlayerCheck.Cooldown(player, "BuyFloor", FloorsConfig.BuyCooldown) then
		return
	end
	local owned = DataService.FloorsOwned(data)
	if n ~= owned + 1 or n > FloorsConfig.MaxFloors or ownedCount(tower) ~= owned then
		NotifyService.Notify(player, FloorsConfig.Messages.NeedPreviousFloor, true)
		return
	end
	local closed = tower.closed
	local gate = closed and closed:FindFirstChild("BuyGate", true)
	local anchor = gate and anchorIn(gate)
	if anchor == nil or not PlayerCheck.CanReach(player, anchor.Position, Gameplay.PromptDistance + 4) then
		return
	end
	local price = FloorsConfig.Price(n)
	if price == nil or not MoneyService.TrySpend(player, price, "Floor:" .. n) then
		NotifyService.Notify(player, FloorsConfig.Messages.NotEnoughMoney, true)
		return
	end
	table.insert(data.Floors, { Upgrades = newFloorLevels(player, n) })
	if tower.closed then
		tower.closed:Destroy()
		tower.closed = nil
	end
	local floor = buildOpen(tower, n, true)
	buildClosed(tower, n + 1)
	if floor then
		run(startedCallbacks, "OnFloorStarted", player, floor, n)
	end
	refreshAnnex(tower)
	NotifyService.Notify(player, string.format(FloorsConfig.Messages.NewFloor, n))
end

local function onTeleport(player: Player, n: any)
	if type(n) ~= "number" or n ~= n or n % 1 ~= 0 then
		return
	end
	local base = BaseService.GetBase(player)
	local tower = base and towers[base]
	if tower == nil or tower.player ~= player then
		return
	end
	if n < 1 or n > ownedCount(tower) then
		return
	end
	if not PlayerCheck.Cooldown(player, "FloorTeleport", FloorsConfig.TeleportCooldown) then
		return
	end
	teleportTo(player, tower.floors[n])
end

---------------------------------------------------------------------------------------------

function FloorService:Init()
	Remotes.GetServerEvent("FloorTeleport").OnServerEvent:Connect(function(player: Player, n: any)
		local ok, err = pcall(onTeleport, player, n)
		if not ok then
			warn(`[FloorService] Erreur de FloorTeleport : {err}`)
		end
	end)
end

function FloorService:Start()
	for _, base in BaseService.GetBases() do
		local folder = base:FindFirstChild("Floors")
		if folder == nil then
			local created = Instance.new("Folder")
			created.Name = "Floors"
			created.Parent = base
			folder = created
		end
		local tower: Tower = {
			base = base,
			folder = folder :: Folder,
			floors = {},
			closed = nil,
			player = nil,
			hidden = {},
			rebirthPrompt = nil,
			rebirthSign = nil,
			towerTiles = {},
		}
		towers[base] = tower
		local board = findAnnex(tower, { "Terrace", "ElevatorBoard" })
		for _, tileModel in (if board then board:GetChildren() else {}) do
			local id = tileModel:GetAttribute("TowerUpgradeId")
			if not tileModel:IsA("Model") or type(id) ~= "string" or FloorsConfig.TowerUpgradeDefaults[id] == nil then
				continue
			end
			-- Clic sur le bouton vert (plus de prompt E, 2026-11-20) : Part BuyButton + ClickDetector (02j)
			local tilePart = tileModel:FindFirstChild("BuyButton") or tileModel:FindFirstChild("Tile")
			local tile = if tilePart and tilePart:IsA("BasePart") then tilePart else nil
			local click = tile and tile:FindFirstChildOfClass("ClickDetector")
			if click then
				local upgradeId: string = id
				click.MouseClick:Connect(function(player: Player)
					local ok, err = pcall(onTowerUpgrade, player, tower, upgradeId)
					if not ok then
						warn(`[FloorService] Erreur d'amelioration Elevator : {err}`)
					end
				end)
			else
				warn(`[FloorService] {base.Name} : tuile {id} du panneau Elevator sans bouton cliquable (relancer 02j)`)
			end
			tower.towerTiles[id] = { model = tileModel, tile = tile, click = click }
		end
		if board == nil then
			warn(`[FloorService] {base.Name} : Annex.Terrace.ElevatorBoard manquant (lancer tools/build-map/02j)`)
		end
		local room = findAnnex(tower, { "RebirthRoom" })
		local anchor = room and room:FindFirstChild("PromptAnchor")
		if anchor and anchor:IsA("BasePart") then
			-- E : le client ouvre le menu Rebirth (RebirthController). Rien a faire ici : le rebirth
			-- passe par le remote RebirthRequest, verifie par RebirthService.
			tower.rebirthPrompt = Prompt.Create(anchor, FloorsConfig.PromptRebirthObject, FloorsConfig.PromptRebirthAction, {
				name = "RebirthPrompt",
				distance = Gameplay.PromptDistance,
			})
		end
		local sign = room and room:FindFirstChild("Sign")
		local signLabel = sign and sign:FindFirstChildWhichIsA("TextLabel", true)
		tower.rebirthSign = if signLabel and signLabel:IsA("TextLabel") then signLabel else nil
		buildOpen(tower, 1, false)
		buildClosed(tower, 2)
		refreshAnnex(tower)
	end
	-- Apparition (connexion, mort) sur l'etage le plus haut
	BaseService.SetSpawnResolver(function(player: Player, base: Model): CFrame?
		local tower = towers[base]
		if tower == nil then
			return nil
		end
		local n = if tower.player == player then ownedCount(tower) else 1
		return spawnCFrame(tower.floors[n] or tower.floors[1])
	end)
	BaseService.OnBaseAssigned(function(player: Player)
		tryStart(player)
	end)
	DataService.OnPlayerLoaded(function(player: Player)
		tryStart(player)
	end)
	BaseService.OnBaseReleased(function(_player: Player, base: Model)
		local tower = towers[base]
		if tower then
			resetTower(tower)
		end
	end)
	-- Etage ou se trouve chaque joueur (lot 5) : seul celui-la a ses fruits, employes et clients
	task.spawn(function()
		while true do
			task.wait(FloorsConfig.ActiveCheckSeconds)
			for _, tower in towers do
				local player = tower.player
				if player and player.Parent ~= nil then
					local floor = FloorService.GetPlayerFloor(player)
					-- Mort / pas de personnage : on garde l'etage d'avant (pas de va-et-vient)
					if floor then
						local ok, err = pcall(setLive, player, floor)
						if not ok then
							warn(`[FloorService] Erreur d'etage actif : {err}`)
						end
					end
				end
			end
		end
	end)
end

---------------------------------------------------------------------------------------------
-- API

-- Appele pour chaque etage OUVERT cree (base libre comprise) ; aussi pour ceux deja la.
function FloorService.OnFloorAdded(callback: AddedCallback)
	table.insert(addedCallbacks, callback)
	for floor, n in floorIndex do
		task.spawn(callback, floor, n)
	end
end

-- Appele juste avant qu'un etage ouvert soit detruit (apres OnFloorStopped s'il tournait).
function FloorService.OnFloorRemoving(callback: AddedCallback)
	table.insert(removingCallbacks, callback)
end

-- Appele quand un etage d'un joueur charge doit tourner (arrivee, achat) ; aussi pour ceux deja la.
function FloorService.OnFloorStarted(callback: PlayerCallback)
	table.insert(startedCallbacks, callback)
	for _, tower in towers do
		local player = tower.player
		if player then
			for n, floor in tower.floors do
				task.spawn(callback, player, floor, n)
			end
		end
	end
end

-- Appele quand un etage arrete de tourner (depart du joueur, remise a zero) : arreter les boucles
-- et oublier son etat. Le dossier Dynamic de l'etage est vide (ou l'etage detruit) juste apres.
function FloorService.OnFloorStopped(callback: PlayerCallback)
	table.insert(stoppedCallbacks, callback)
end

-- Etage "vivant" : celui ou se trouve son proprietaire (fruits qui tombent, employes, clients).
-- Les autres etages de la tour tournent en nombres (Lib/FloorIncome).
function FloorService.IsLive(floor: Model): boolean
	local owner = FloorService.GetOwner(floor)
	return owner ~= nil and liveFloor[owner] == floor
end

-- Etage vivant du joueur (nil s'il n'a pas de tour qui tourne).
function FloorService.GetLiveFloor(player: Player): Model?
	return liveFloor[player]
end

-- Appele quand le joueur change d'etage (old / new peuvent etre nil : arrivee, depart).
function FloorService.OnLiveFloorChanged(callback: (player: Player, old: Model?, new: Model?) -> ())
	table.insert(liveCallbacks, callback)
end

-- Numero d'un etage ouvert (nil si ce n'est pas un etage ouvert connu).
function FloorService.GetIndex(floor: Model): number?
	return floorIndex[floor]
end

-- Base d'un etage ouvert.
function FloorService.GetBaseOf(floor: Model): Model?
	return floorBase[floor]
end

-- Joueur dont l'etage tourne (nil si base libre ou pas encore charge).
function FloorService.GetOwner(floor: Model): Player?
	local base = floorBase[floor]
	local tower = base and towers[base]
	return if tower then tower.player else nil
end

-- Etage n ouvert de la tour du joueur.
function FloorService.GetFloor(player: Player, n: number): Model?
	local base = BaseService.GetBase(player)
	local tower = base and towers[base]
	if tower == nil or tower.player ~= player then
		return nil
	end
	return tower.floors[n]
end

-- Etage 1 (table a argent, pads Collect Cash) d'une base.
function FloorService.GetGround(base: Model): Model?
	local tower = towers[base]
	return if tower then tower.floors[1] else nil
end

-- Nombre d'etages ouverts de la tour du joueur (0 s'il n'a pas de tour qui tourne).
function FloorService.GetOwnedCount(player: Player): number
	local base = BaseService.GetBase(player)
	local tower = base and towers[base]
	return if tower and tower.player == player then ownedCount(tower) else 0
end

-- Etage ou se trouve le joueur dans SA tour (d'apres la hauteur de son personnage), ou nil.
function FloorService.GetPlayerFloor(player: Player): (Model?, number?)
	local base = BaseService.GetBase(player)
	local tower = base and towers[base]
	local root = PlayerCheck.GetRoot(player)
	if tower == nil or tower.player ~= player or root == nil then
		return nil, nil
	end
	local y = (tower.base:GetPivot():PointToObjectSpace(root.Position)).Y
	local n = math.clamp(math.floor((y + 2) / FloorsConfig.FloorHeight) + 1, 1, ownedCount(tower))
	return tower.floors[n], n
end

---------------------------------------------------------------------------------------------
-- Rebirth (RebirthService)

-- Niveaux d'un etage neuf (nil = Upgrades.DefaultLevels()). Un seul resolver (RebirthService).
function FloorService.SetNewFloorLevels(resolver: (player: Player, n: number) -> { [string]: number }?)
	newFloorResolver = resolver
end

-- Rebirth : la tour du joueur repart a 1 etage neuf (ameliorations de depart, sauf ce que donne
-- SetNewFloorLevels), ascenseur a 0. ECRIT LA SAUVEGARDE (Data.Floors, Data.TowerUpgrades).
-- Tout ce qui tourne sur les etages est arrete puis relance (comptoir, tas d'argent, arbre, employes
-- repartent a zero). Le joueur est ramene au point de depart de l'etage 1 : la vitre de la salle du
-- Rebirth se referme (etage 10 perdu), il ne doit pas rester enferme dedans.
-- Ne fait pas attendre (le teleport attend dans son propre thread).
function FloorService.ResetForRebirth(player: Player): boolean
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	data.Floors = { { Upgrades = newFloorLevels(player, 1) } }
	data.TowerUpgrades = table.clone(FloorsConfig.TowerUpgradeDefaults)
	-- Tour pas encore construite (pas de base) : la sauvegarde suffit, tryStart la construira.
	local base = BaseService.GetBase(player)
	local tower = base and towers[base]
	if tower then
		resetTower(tower)
		tryStart(player)
		task.spawn(teleportTo, player, tower.floors[1])
	end
	return true
end

---------------------------------------------------------------------------------------------
-- Tests (DebugService en Studio, AdminService) : changer le nombre d'etages ECRIT LA SAUVEGARDE.

-- Met la tour du joueur a `count` etages (1..MaxFloors). Les nouveaux etages ont les ameliorations
-- de depart ; les etages retires sont perdus.
function FloorService.SetFloorCount(player: Player, count: number): boolean
	local data = DataService.GetData(player)
	local base = BaseService.GetBase(player)
	local tower = base and towers[base]
	if data == nil or tower == nil or type(count) ~= "number" then
		return false
	end
	count = math.clamp(math.floor(count), 1, FloorsConfig.MaxFloors)
	while #data.Floors > count do
		table.remove(data.Floors)
	end
	while #data.Floors < count do
		table.insert(data.Floors, { Upgrades = newFloorLevels(player, #data.Floors + 1) })
	end
	resetTower(tower)
	tryStart(player)
	teleportTo(player, tower.floors[ownedCount(tower)])
	return true
end

-- Teleporte le joueur a l'etage n de sa tour (sans delai).
function FloorService.DebugGoTo(player: Player, n: number): boolean
	local floor = FloorService.GetFloor(player, n)
	if floor == nil then
		return false
	end
	teleportTo(player, floor)
	return true
end

-- Etat lisible pour les tests.
function FloorService.DebugGet(player: Player): { [string]: any }?
	local base = BaseService.GetBase(player)
	local tower = base and towers[base]
	if tower == nil then
		return nil
	end
	local _, current = FloorService.GetPlayerFloor(player)
	return {
		Owned = ownedCount(tower),
		Running = tower.player == player,
		Closed = if tower.closed then tower.closed.Name else nil,
		Current = current,
		Studio = RunService:IsStudio(),
	}
end

return FloorService
