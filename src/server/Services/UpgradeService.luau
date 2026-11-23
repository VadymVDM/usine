--!strict
-- Achats des ameliorations et des employes avec l'argent du jeu. Seul module qui modifie
-- Data.Floors[n].Upgrades : chaque ETAGE a ses niveaux (memes ids) ; les prix sont x
-- Floors.UpgradePriceFactor^(n-1) (Config/Floors). Dans chaque etage ouvert :
--   * Machines.<id> / Production.Blenders.BlenderN : fantome bleu tant que le niveau est sous
--     Upgrades.BuiltAt(id), construite ensuite. Les machines (kind "Upgrade") ont un prompt E
--     "Buy $250" et une etiquette flottante nom + prix tant qu'elles sont fantomes ; une fois
--     construites, leurs niveaux s'achetent sur leur panneau (prompt inactif) ;
--   * Machines.<id>.Pad : pad vert des employes (marcher dessus = embaucher), cache une fois
--     l'employe embauche. Les pieces "GhostOnly" (silhouette bleue de l'employe) disparaissent :
--     le vrai employe R6 apparait (WorkerService) ;
--   * pad "repeatPad" (Machines.Tree.Pad, "Upgrade Tree") : il reste la ; se tenir dessus achete
--     1 niveau, puis 1 de plus toutes les Gameplay.PadRepeatSeconds tant qu'on reste dessus ;
--   * Boards.<Board>.<id> : tuile d'un panneau (CLIQUER la tuile = acheter un niveau, bouton
--     violet = Robux, voir plus bas). Textes mis a jour : Value ("8 → 12"), Price, Robux.
-- Attribut d'etage "Lv_<id>" = niveau du proprietaire (niveau de depart si libre) : le client
-- (LevelLookController) montre les pieces de decor de chaque niveau.
-- Achat = APPUI LONG, sauf les tuiles des panneaux (simple clic, demande du 2026-11-20) :
--   * machine construite : prompt E maintenu (HoldDuration = Gameplay.BuyHoldSeconds) -> achat direct ;
--   * machine fantome (premier achat) : prompt E maintenu, puis pop-up de confirmation cote client
--     (BuyController) ; le serveur ignore ce Triggered et attend le remote BuyUpgrade ;
--   * dessus des pads : appui long souris / doigt (BuyController) -> BuyUpgrade ;
--   * tuiles des panneaux : simple clic / tap (BuyController) -> BuyUpgrade.
-- Bouton violet d'une tuile (Robux, 2026-11-23) : clic (ClickDetector serveur, joueur proprietaire et
-- pres de la tuile) -> memes verifications qu'un achat (sauf l'argent) -> le serveur note la tuile
-- (etage, id) et ouvre le Developer Product du prix affiche (Upgrades.RobuxProducts : 5 / 8 / 9 R$).
-- Le niveau n'est donne qu'au recu (ReceiptService -> DataService.GrantPurchaseOnce : une fois par
-- PurchaseId). Tuile notee perdue (autre serveur, plus de 10 min) ou deja au max : +1 niveau a la
-- premiere amelioration construite au meme prix Robux (etage le plus haut d'abord). Rien a donner :
-- recu accepte, avertissement dans la sortie.
-- Remote BuyUpgrade (client -> serveur, id) : id connu, etage ou se trouve le joueur
-- (hauteur de son personnage, FloorService.GetPlayerFloor), proprietaire, joueur pres d'un point
-- d'achat de cet id (machine, tuile, pad), delai, niveau max, argent via MoneyService.TrySpend.
-- Marcher sur un pad d'employe embauche toujours directement (contact verifie par le serveur).
-- Modeles achetables : Machines.<id>, et pour les mixeurs Production.Blenders.BlenderN (2 a 4) +
-- BlenderN.Operator (pad de l'operateur : marcher dessus = embaucher, comme les autres pads ;
-- l'ancien attribut HirePrompt est ignore). Voir Util/MachineModels.
-- Upgrades.requires : un id qui demande un autre achat (Blender3 -> Blender2, Operator2 -> Blender2)
-- est "verrouille" (attribut Locked) : prompt inactif, etiquette et pad caches, achat refuse.
-- Attributs lus par le client (MachineFxController) :
--   machine : Built, Level, BuildStamp (+1 quand elle se construit), Locked ;
--   machine et tuile : Price (-1 = max), ComingSoon, Bought (+1 a chaque achat), Denied (+1 si refuse).
-- Usine a construire (2026-11-21, SetupService / Config/Setup.UpgradeStep) : sur l'etage 1 d'un profil
-- neuf, un id n'existe qu'a partir de son etape FREE : avant, pad cache, panneau cache (tuile
-- Unbuilt), machine cachee (attribut Hidden ; le mixeur 1, Setup.UpgradeBuild, se construit au pad
-- "Build blender") et achat refuse.
-- Doc : docs/systems/ameliorations-employes.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Gameplay = require(Config:WaitForChild("Gameplay"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local NumberFormat = require(Shared:WaitForChild("Util"):WaitForChild("NumberFormat"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local Prompt = require(Shared:WaitForChild("Util"):WaitForChild("Prompt"))
local MachineModels = require(Shared:WaitForChild("Util"):WaitForChild("MachineModels"))
local UpgradeTile = require(Shared:WaitForChild("Util"):WaitForChild("UpgradeTile"))

local Floors = require(Config:WaitForChild("Floors"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local DataService = require(script.Parent.DataService)
local FloorService = require(script.Parent.FloorService)
local MoneyService = require(script.Parent.MoneyService)
local NotifyService = require(script.Parent.NotifyService)
local SetupService = require(script.Parent.SetupService)
local SetupConfig = require(Config:WaitForChild("Setup"))
local PurchasePrompt = require(script.Parent.Parent.Lib.PurchasePrompt)
local ReceiptService = require(script.Parent.ReceiptService)

local UpgradeService = {}

-- Aspect "fantome" (machine pas encore achetee)
local GHOST_COLOR = Color3.fromRGB(150, 205, 255)
local GHOST_TINT = 0.72 -- part de bleu dans la couleur de chaque piece (le reste : sa vraie couleur)
local GHOST_TRANSPARENCY = 0.18
local TAG_FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local NOTIFY_COOLDOWN = 0.6 -- secondes entre deux messages d'achat pour un joueur

type PartLook = {
	color: Color3,
	material: Enum.Material,
	transparency: number,
	canCollide: boolean,
	castShadow: boolean,
}

type Machine = {
	id: string,
	model: Model,
	looks: { [BasePart]: PartLook },
	ghostOnly: { [BasePart]: boolean }, -- pieces visibles seulement en fantome (silhouette d'employe)
	effects: { [Instance]: boolean }, -- emetteurs / SurfaceGui et leur Enabled d'origine
	anchor: BasePart?, -- point du prompt E et de l'etiquette des machines
	prompt: ProximityPrompt?,
	machineTag: BillboardGui?,
	built: boolean?,
	hidden: boolean?, -- usine a construire : machine pas encore la (invisible pour tous)
	padLooks: { [BasePart]: PartLook },
	repeatPad: boolean, -- pad "Upgrade Tree" : reste visible apres l'achat
	padZone: BasePart?,
	padTop: BasePart?,
	tag: BillboardGui?,
	click: ClickDetector?,
	clickRange: number,
}

type Tile = {
	id: string,
	model: Model,
	buy: BasePart?,
	robux: BasePart?,
	valueLabel: TextLabel?,
	levelLabel: TextLabel?,
	priceLabel: TextLabel?,
	robuxLabel: TextLabel?,
	clickRange: number?, -- portee d'origine du ClickDetector (0 tant que la machine n'est pas construite)
}

type FloorState = {
	floor: Model,
	index: number, -- numero de l'etage (prix x Floors.UpgradePriceFactor^(n-1))
	player: Player?, -- proprietaire dont les niveaux sont affiches (nil = base libre)
	machines: { [string]: Machine },
	tiles: { [string]: { Tile } },
}

type BoughtCallback = (Player, string, number, Model) -> () -- (joueur, id, nouveau niveau, etage)

local states: { [Model]: FloorState } = {}
local lastBuy: { [Player]: number } = {}
local lastNotify: { [Player]: number } = {}
local padInside: { [Player]: string } = {} -- "Floor2/Tree" : pad ou se tient le joueur
local padNext: { [Player]: number } = {} -- pad repeatPad : heure du prochain achat si on reste dessus
local boughtCallbacks: { BoughtCallback } = {}
-- Bouton violet clique : [joueur][productId] = tuile notee (etage n, id, heure)
type RobuxIntent = { index: number, id: string, at: number }
local robuxIntents: { [Player]: { [number]: RobuxIntent } } = {}
local lastRobuxClick: { [Player]: number } = {}

local function lookOf(part: BasePart): PartLook
	return {
		color = part.Color,
		material = part.Material,
		transparency = part.Transparency,
		canCollide = part.CanCollide,
		castShadow = part.CastShadow,
	}
end

local function restore(part: BasePart, look: PartLook)
	part.Color = look.color
	part.Material = look.material
	part.Transparency = look.transparency
	part.CanCollide = look.canCollide
	part.CastShadow = look.castShadow
end

local function notify(player: Player, message: string, isError: boolean?)
	local now = os.clock()
	local last = lastNotify[player]
	if last and now - last < NOTIFY_COOLDOWN then
		return
	end
	lastNotify[player] = now
	NotifyService.Notify(player, message, isError)
end

local function bump(instance: Instance, attribute: string)
	local value = instance:GetAttribute(attribute)
	instance:SetAttribute(attribute, (if type(value) == "number" then value else 0) + 1)
end

-- Vrai si `position` est au-dessus de la zone `part`.
local function isOver(part: BasePart, position: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Z) <= half.Z
		and localPos.Y >= -half.Y - 1
		and localPos.Y <= half.Y + Gameplay.PadHeightAbove
end

-- Deja sur ce pad : marge pour en sortir (bord, saut), sinon chaque petit pas au bord = un achat
local function isStillOver(part: BasePart, position: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local margin = Gameplay.PadExitMargin
	return math.abs(localPos.X) <= half.X + margin
		and math.abs(localPos.Z) <= half.Z + margin
		and localPos.Y >= -half.Y - 1 - margin
		and localPos.Y <= half.Y + Gameplay.PadExitHeight
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local humanoid = (character :: Model):FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			return root
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------
-- Affichage : fantome / construit, pad, textes

-- Une machine fantome n'a pas de collision : un joueur peut etre dedans au moment ou elle se
-- construit. Sans correction, la physique le coince dans la machine ou le pousse sous le sol.
-- On sort donc chaque personnage qui touche la boite des pieces solides, par le cote le plus proche.
local function pushPlayersOut(machine: Machine)
	local minV, maxV = nil :: Vector3?, nil :: Vector3?
	for part, look in machine.looks do
		if not look.canCollide or machine.ghostOnly[part] then
			continue
		end
		-- Coins de la piece (boite alignee sur les axes du monde)
		local half = part.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = part.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
					minV = if minV then minV:Min(corner) else corner
					maxV = if maxV then maxV:Max(corner) else corner
				end
			end
		end
	end
	if minV == nil or maxV == nil then
		return
	end
	local margin = Gameplay.BuildPushMargin
	for _, player in Players:GetPlayers() do
		local root = getRoot(player)
		local character = player.Character
		if root == nil or character == nil then
			continue
		end
		local pos = root.Position
		-- Le personnage fait ~5 studs de haut, la racine est a ~3 studs du sol
		local inside = pos.X > minV.X - margin
			and pos.X < maxV.X + margin
			and pos.Z > minV.Z - margin
			and pos.Z < maxV.Z + margin
			and pos.Y + 2.5 > minV.Y
			and pos.Y - 3 < maxV.Y
		if not inside then
			continue
		end
		-- Cote horizontal le plus proche
		local exits = {
			{ dist = pos.X - minV.X, target = Vector3.new(minV.X - margin, pos.Y, pos.Z) },
			{ dist = maxV.X - pos.X, target = Vector3.new(maxV.X + margin, pos.Y, pos.Z) },
			{ dist = pos.Z - minV.Z, target = Vector3.new(pos.X, pos.Y, minV.Z - margin) },
			{ dist = maxV.Z - pos.Z, target = Vector3.new(pos.X, pos.Y, maxV.Z + margin) },
		}
		table.sort(exits, function(a, b)
			return a.dist < b.dist
		end)
		local target = exits[1].target + Vector3.new(0, 0.5, 0)
		character:PivotTo(CFrame.new(target) * root.CFrame.Rotation)
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function setBuilt(machine: Machine, built: boolean, hidden: boolean?)
	local isHidden = hidden == true
	if machine.built == built and (machine.hidden == true) == isHidden then
		return
	end
	local wasGhost = machine.built == false
	machine.built = built
	machine.hidden = isHidden
	for part, look in machine.looks do
		-- Cachee (usine a construire, mixeur verrouille) ou silhouette d'employe embauche : invisible
		if isHidden or (built and machine.ghostOnly[part]) then
			part.Transparency = 1
			part.CanCollide = false
			part.CastShadow = false
		elseif built then
			restore(part, look)
		else
			-- Fantome : la vraie machine, teintee bleu clair et presque opaque (on voit ses details) ;
			-- le client ajoute un contour clair par-dessus (MachineFxController).
			part.Color = look.color:Lerp(GHOST_COLOR, GHOST_TINT)
			part.Material = Enum.Material.SmoothPlastic
			part.Transparency = math.max(look.transparency, GHOST_TRANSPARENCY)
			part.CanCollide = false
			part.CastShadow = false
		end
	end
	for effect, enabled in machine.effects do
		(effect :: any).Enabled = built and enabled and not isHidden
	end
	if built and wasGhost then
		pushPlayersOut(machine)
	end
	machine.model:SetAttribute("Built", built)
end

local function setPadVisible(machine: Machine, visible: boolean)
	for part, look in machine.padLooks do
		part.Transparency = if visible then look.transparency else 1
		part.CanCollide = visible and look.canCollide
	end
	if machine.tag then
		machine.tag.Enabled = visible
	end
	if machine.click then
		machine.click.MaxActivationDistance = if visible then machine.clickRange else 0
	end
end


-- Niveaux de l'etage `index` du joueur (nil = base libre ou sauvegarde pas chargee).
local function levelsOf(player: Player?, index: number): { [string]: number }?
	local data = if player then DataService.GetData(player) else nil
	return if data then DataService.FloorUpgrades(data, index) else nil
end

-- Prix d'un niveau sur l'etage `index` (les etages du haut coutent plus cher, Config/Floors).
local function priceAt(id: string, level: number, index: number): number
	return Floors.UpgradePrice(Upgrades.GetPrice(id, level), index)
end

-- Niveau, niveau max et prix (-1 au max) sur cet etage pour ce joueur (ou une base libre).
local function getLevelInfo(id: string, player: Player?, index: number): (number, number, number)
	local upgrade = Upgrades.ById[id]
	local data = if player then DataService.GetData(player) else nil
	local levels = levelsOf(player, index)
	local level = if levels then levels[id] or upgrade.startLevel else upgrade.startLevel
	local maxLevel = Upgrades.GetMaxLevel(id, if data then data.Rebirths else 0)
	local price = if level >= maxLevel then -1 else priceAt(id, level, index)
	return level, maxLevel, price
end

local function isLocked(id: string, player: Player?, index: number): boolean
	return Upgrades.IsLocked(id, levelsOf(player, index))
end

-- Usine a construire : l'id existe-t-il deja sur cet etage (etape FREE faite) ?
local function isRevealed(state: FloorState, id: string): boolean
	return SetupService.Allows(state.floor, SetupConfig.UpgradeStep[id] or 0)
end

local function refreshUpgrade(state: FloorState, id: string, player: Player?)
	local upgrade = Upgrades.ById[id]
	local level, maxLevel, price = getLevelInfo(id, player, state.index)
	local locked = isLocked(id, player, state.index)
	local priceText = if upgrade.comingSoon
		then "Soon"
		elseif price < 0 then "MAX"
		else "$" .. NumberFormat.Abbreviate(price)
	local comingSoon = upgrade.comingSoon == true

	local builtAt = Upgrades.BuiltAt(id)
	-- Niveau visible par tous les clients (decor de chaque niveau, LevelLookController)
	state.floor:SetAttribute("Lv_" .. id, level)
	-- Usine a construire : pas encore la (cache) ou machine a construire par un pad FREE (fantome)
	local revealed = isRevealed(state, id)
	-- Pas encore la : cachee (le mixeur 1 aussi, pas de fantome avant "Build blender", 2026-11-21) ;
	-- une machine verrouillee (mixeur 3 avant le 2...) est cachee : seule la prochaine est en bleu.
	local setupGhost = false
	local hidden = not revealed or locked

	local machine = state.machines[id]
	if machine then
		setBuilt(machine, level >= builtAt and revealed, hidden)
		machine.model:SetAttribute("Hidden", hidden)
		machine.model:SetAttribute("SetupGhost", setupGhost)
		machine.model:SetAttribute("Level", level)
		machine.model:SetAttribute("Price", price)
		machine.model:SetAttribute("ComingSoon", comingSoon)
		machine.model:SetAttribute("Locked", locked)
		machine.model:SetAttribute("Repeat", machine.repeatPad)
		if machine.prompt then
			-- Le prompt E sert seulement au premier achat (machine fantome) ; ensuite les niveaux
			-- s'achetent sur le panneau de la machine (sinon 2 prompts E l'un sur l'autre avec Blend).
			local verb = if upgrade.kind == "Employee" then Gameplay.PromptTexts.Hire else Gameplay.PromptTexts.Buy
			Prompt.SetAction(machine.prompt, if price < 0 then Gameplay.PromptTexts.Max else `{verb} {priceText}`)
			Prompt.SetObject(machine.prompt, upgrade.machine)
			Prompt.SetActive(machine.prompt, not machine.built and price >= 0 and not comingSoon and not locked and revealed)
			-- Premier achat (machine fantome) : le client demande une confirmation
			machine.prompt:SetAttribute("Confirm", not machine.built)
		end
		if machine.machineTag then
			machine.machineTag.Enabled = not machine.built and not locked and revealed
			local priceLabel = machine.machineTag:FindFirstChild("Price", true)
			if priceLabel and priceLabel:IsA("TextLabel") then
				priceLabel.Text = priceText
			end
		end
		if machine.padTop then
			local padWanted = if machine.repeatPad then price >= 0 else not machine.built
			setPadVisible(machine, padWanted and not locked and revealed)
			local priceLabel = machine.tag and machine.tag:FindFirstChild("Price")
			if priceLabel and priceLabel:IsA("TextLabel") then
				priceLabel.Text = priceText
			end
			local levelLabel = machine.tag and machine.tag:FindFirstChild("Level")
			if levelLabel and levelLabel:IsA("TextLabel") then
				levelLabel.Text = if price < 0 then `Lv {level} MAX` else `Lv {level} > {level + 1}`
			end
		end
	end

	-- Machine pas encore construite (mixeur fantome) : son panneau est cache et ne vend rien,
	-- le premier achat se fait seulement au prompt E de la machine (demande du 2026-11-20 :
	-- "enleve les panneaux pour les trucs d'achat").
	local unbuilt = (machine ~= nil and machine.built == false) or not revealed
	for _, tile in state.tiles[id] or {} do
		tile.model:SetAttribute("Price", price)
		tile.model:SetAttribute("ComingSoon", comingSoon)
		tile.model:SetAttribute("Locked", locked)
		tile.model:SetAttribute("Unbuilt", unbuilt)
		tile.model:SetAttribute("Level", level)
		local click = tile.buy and tile.buy:FindFirstChildOfClass("ClickDetector")
		if click then
			if tile.clickRange == nil then
				tile.clickRange = click.MaxActivationDistance
			end
			click.MaxActivationDistance = if unbuilt then 0 else tile.clickRange :: number
		end
		if tile.valueLabel then
			local current = Upgrades.FormatValue(id, Upgrades.GetValue(id, level))
			tile.valueLabel.Text = if level < builtAt
				then "NEW!"
				elseif level >= maxLevel then current .. " MAX"
				else current .. UpgradeTile.ARROW .. Upgrades.FormatValue(id, Upgrades.GetValue(id, level + 1))
		end
		if tile.levelLabel then
			tile.levelLabel.Text = if level < builtAt then "Buy" elseif level >= maxLevel then "MAX" else `Lv {level}`
		end
		if tile.priceLabel then
			tile.priceLabel.Text = priceText
		end
		if tile.robuxLabel then
			tile.robuxLabel.Text = if price < 0 then "-" else tostring(Upgrades.GetRobuxPrice(id, level))
		end
	end
end

local function refreshFloor(floor: Model, player: Player?)
	local state = states[floor]
	if state == nil then
		return
	end
	state.player = player
	for _, upgrade in Upgrades.List do
		refreshUpgrade(state, upgrade.id, player)
	end
end

---------------------------------------------------------------------------------------------
-- Achat

local function denyFx(state: FloorState, id: string)
	local machine = state.machines[id]
	if machine then
		bump(machine.model, "Denied")
	end
	for _, tile in state.tiles[id] or {} do
		bump(tile.model, "Denied")
	end
end

-- Verifications communes (argent et Robux) : renvoie (niveaux de l'etage, niveau actuel) si cet id
-- peut monter d'un niveau sur cet etage, sinon nil + message de refus (pas de message = refus muet).
local function checkBuyable(player: Player, state: FloorState, id: string): ({ [string]: number }?, number, string?)
	local upgrade = Upgrades.ById[id]
	if upgrade == nil or FloorService.GetOwner(state.floor) ~= player or not isRevealed(state, id) then
		return nil, 0, nil -- pas encore construit (pad FREE pas fait) : rien a acheter, pas de message
	end
	if upgrade.comingSoon then
		return nil, 0, Upgrades.Messages.ComingSoon
	end
	local data = DataService.GetData(player)
	local levels = if data then DataService.FloorUpgrades(data, state.index) else nil
	if data == nil or levels == nil then
		return nil, 0, nil
	end
	local level = levels[id] or upgrade.startLevel
	if level >= Upgrades.GetMaxLevel(id, data.Rebirths) then
		return nil, level, Upgrades.Messages.MaxLevel
	end
	if Upgrades.IsLocked(id, levels) then
		local required = Upgrades.ById[upgrade.requires :: string]
		return nil, level, string.format(Upgrades.Messages.NeedsFirst, required.machine)
	end
	return levels, level, nil
end

-- Apres un niveau donne (argent ou recu Robux) : machine construite, etage rafraichi, effets, rappels.
local function afterBought(player: Player, state: FloorState, id: string, newLevel: number, wasBuilt: boolean?)
	local machine = state.machines[id]
	if machine and wasBuilt == false then
		bump(machine.model, "BuildStamp")
	end
	-- Tout l'etage : un achat peut deverrouiller d'autres ids (mixeur suivant, son operateur)
	refreshFloor(state.floor, player)
	if machine then
		bump(machine.model, "Bought")
	end
	for _, tile in state.tiles[id] or {} do
		bump(tile.model, "Bought")
	end
	for _, callback in boughtCallbacks do
		local ok, err = pcall(callback, player, id, newLevel, state.floor)
		if not ok then
			warn(`[UpgradeService] Erreur dans OnBought : {err}`)
		end
	end
end

local function tryBuy(player: Player, floor: Model, id: string): boolean
	local state = states[floor]
	if state == nil or Upgrades.ById[id] == nil or FloorService.GetOwner(floor) ~= player then
		return false
	end
	local now = os.clock()
	local last = lastBuy[player]
	if last and now - last < Gameplay.BuyCooldownSeconds then
		return false
	end
	lastBuy[player] = now

	local levels, level, refusal = checkBuyable(player, state, id)
	if levels == nil then
		if refusal then
			notify(player, refusal, true)
			denyFx(state, id)
		end
		return false
	end
	local price = priceAt(id, level, state.index)
	if not MoneyService.TrySpend(player, price, "Upgrade:" .. id) then
		notify(player, Upgrades.Messages.NotEnoughMoney, true)
		denyFx(state, id)
		return false
	end
	local machine = state.machines[id]
	local wasBuilt = if machine then machine.built else nil
	levels[id] = level + 1
	afterBought(player, state, id, level + 1, wasBuilt)
	return true
end

---------------------------------------------------------------------------------------------
-- Achat en Robux (bouton violet des tuiles)

local function onRobuxClick(player: Player, state: FloorState, tile: Tile)
	local now = os.clock()
	local last = lastRobuxClick[player]
	if last and now - last < Gameplay.BuyCooldownSeconds then
		return
	end
	lastRobuxClick[player] = now
	-- Tuile cachee (machine pas construite) : le bouton ne vend rien
	if tile.model:GetAttribute("Unbuilt") == true then
		return
	end
	local id = tile.id
	local levels, level, refusal = checkBuyable(player, state, id)
	if levels == nil then
		if refusal then
			notify(player, refusal, true)
			denyFx(state, id)
		end
		return
	end
	local productId = Upgrades.RobuxProductFor(id, level)
	if productId == nil then
		notify(player, Upgrades.Messages.RobuxSoon)
		return
	end
	local intents = robuxIntents[player]
	if intents == nil then
		intents = {}
		robuxIntents[player] = intents
	end
	intents[productId] = { index = state.index, id = id, at = now }
	PurchasePrompt.Product(player, productId)
end

-- Ou donner le niveau paye : la tuile notee si elle peut encore monter, sinon la premiere
-- amelioration construite (avec une tuile) au meme prix Robux, etage le plus haut d'abord.
local function robuxTarget(player: Player, productId: number): (FloorState?, string?)
	local intents = robuxIntents[player]
	local intent = intents and intents[productId]
	if intents then
		intents[productId] = nil
	end
	if intent and os.clock() - intent.at <= Upgrades.RobuxPendingSeconds then
		local floor = FloorService.GetFloor(player, intent.index)
		local state = floor and states[floor]
		if state and checkBuyable(player, state, intent.id) then
			return state, intent.id
		end
	end
	for n = FloorService.GetOwnedCount(player), 1, -1 do
		local floor = FloorService.GetFloor(player, n)
		local state = floor and states[floor]
		if state == nil then
			continue
		end
		for _, upgrade in Upgrades.List do
			local machine = state.machines[upgrade.id]
			if state.tiles[upgrade.id] == nil or (machine and machine.built == false) then
				continue
			end
			local levels, level = checkBuyable(player, state, upgrade.id)
			if levels and Upgrades.RobuxProductFor(upgrade.id, level) == productId then
				return state, upgrade.id
			end
		end
	end
	-- 2026-11-23 : rien au meme prix -> n'importe quelle amelioration encore possible (etage le plus
	-- haut d'abord). Le joueur a paye : il recoit toujours quelque chose (sinon : argent, voir le recu).
	for n = FloorService.GetOwnedCount(player), 1, -1 do
		local floor = FloorService.GetFloor(player, n)
		local state = floor and states[floor]
		if state == nil then
			continue
		end
		for _, upgrade in Upgrades.List do
			local machine = state.machines[upgrade.id]
			if state.tiles[upgrade.id] == nil or (machine and machine.built == false) then
				continue
			end
			if checkBuyable(player, state, upgrade.id) then
				return state, upgrade.id
			end
		end
	end
	return nil, nil
end

-- Argent donne quand un recu n'a plus aucune amelioration a donner (tout est au max) :
-- Upgrades.RobuxRefundFloorShare x prix du prochain etage (ou du dernier x5 apres l'etage 10).
local function robuxRefundAmount(player: Player): number
	local n = FloorService.GetOwnedCount(player) + 1
	local price = Floors.Price(n) or (Floors.Prices[#Floors.Prices] * Floors.UpgradePriceFactor)
	return math.max(math.floor(price * Upgrades.RobuxRefundFloorShare), 100)
end

type Applied = { state: FloorState, id: string, level: number, wasBuilt: boolean? }

local function onRobuxReceipt(receipt: ReceiptService.Receipt): boolean
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return false -- parti : Roblox redonnera le recu a sa prochaine arrivee
	end
	local deadline = os.clock() + Upgrades.ReceiptWaitSeconds
	while DataService.GetData(player) == nil and player.Parent == Players and os.clock() < deadline do
		task.wait(0.25)
	end
	local applied: Applied? = nil
	local refunded = 0
	local granted = DataService.GrantPurchaseOnce(player, receipt.PurchaseId, function(data): boolean
		local state, id = robuxTarget(player, receipt.ProductId)
		if state == nil or id == nil then
			-- Tout est au max : on donne de l'argent au lieu de rien (les Robux ne sont jamais perdus)
			refunded = robuxRefundAmount(player)
			data.Money = math.min(data.Money + refunded, GameConfig.MaxMoney)
			warn(`[UpgradeService] Recu {receipt.PurchaseId} ({receipt.ProductId}) : aucune amelioration, +{refunded} $`)
			return true
		end
		local levels = DataService.FloorUpgrades(data, state.index)
		if levels == nil then
			return false
		end
		local level = levels[id] or Upgrades.ById[id].startLevel
		local machine = state.machines[id]
		levels[id] = level + 1
		applied = { state = state, id = id, level = level + 1, wasBuilt = if machine then machine.built else nil }
		print(`[UpgradeService] Recu {receipt.PurchaseId} : {id} niveau {level + 1}, etage {state.index} ({player.UserId})`)
		return true
	end)
	-- Le niveau est deja dans la sauvegarde en memoire (meme si l'ecriture attend encore) : on l'affiche
	local done: Applied? = applied
	if done then
		afterBought(player, done.state, done.id, done.level, done.wasBuilt)
	elseif refunded > 0 then
		MoneyService.SyncLeaderstats(player)
		notify(player, string.format(Upgrades.Messages.RobuxRefund, NumberFormat.Abbreviate(refunded)))
	end
	return granted
end

-- Clic sur un bouton ou un pad : joueur valide, proprietaire de l'etage, assez pres.
local function validClicker(clicker: any, floor: Model, part: BasePart, range: number): boolean
	if typeof(clicker) ~= "Instance" or not clicker:IsA("Player") or clicker.Parent ~= Players then
		return false
	end
	if FloorService.GetOwner(floor) ~= clicker then
		return false
	end
	local root = getRoot(clicker)
	return root ~= nil and (root.Position - part.Position).Magnitude <= range + Gameplay.BuyClickExtraDistance
end

local function connectClick(floor: Model, part: BasePart, onClick: (Player) -> ())
	local click = part:FindFirstChildOfClass("ClickDetector")
	if click == nil then
		return
	end
	local range = click.MaxActivationDistance
	click.MouseClick:Connect(function(clicker: Player)
		if validClicker(clicker, floor, part, range) then
			onClick(clicker)
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Machines : prompt E au centre de la machine + etiquette "nom / prix" au-dessus (fantome)

local function tagLabel(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = pos
	label.Size = size
	label.FontFace = TAG_FONT
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 30, 60)
	stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	stroke.Thickness = 0.09
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function createMachinePrompt(floor: Model, machine: Machine, build: Model)
	local cf, size = build:GetBoundingBox()
	local anchor = Instance.new("Part")
	anchor.Name = "PromptAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(cf.Position)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Parent = machine.model
	machine.anchor = anchor

	local upgrade = Upgrades.ById[machine.id]
	local reach = Gameplay.PromptDistance + math.max(size.X, size.Z) / 2
	local prompt = Prompt.Create(anchor, upgrade.machine, Gameplay.PromptTexts.Buy, {
		name = "BuyPrompt",
		distance = reach,
		hold = Gameplay.BuyHoldSeconds,
	})
	prompt:SetAttribute("UpgradeId", machine.id)
	prompt.Triggered:Connect(function(player: Player)
		-- Fantome : achat seulement apres la pop-up de confirmation (remote BuyUpgrade)
		if machine.built and validClicker(player, floor, anchor, reach) then
			tryBuy(player, floor, machine.id)
		end
	end)
	machine.prompt = prompt

	-- Etiquette flottante (fantome seulement) : nom + prix dans une pastille verte
	local tag = Instance.new("BillboardGui")
	tag.Name = "MachineTag"
	tag.Size = UDim2.fromScale(8, 3.4)
	tag.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 2.4, 0)
	tag.MaxDistance = 70
	tag.LightInfluence = 0
	tag.Adornee = anchor
	tagLabel(tag, "Title", upgrade.machine, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.5), Color3.new(1, 1, 1))
	local pill = Instance.new("Frame")
	pill.Name = "PricePill"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.fromScale(0.5, 0.52)
	pill.Size = UDim2.fromScale(0.5, 0.44)
	pill.BackgroundColor3 = Color3.fromRGB(70, 200, 70)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 80, 20)
	stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	stroke.Thickness = 0.06
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = pill
	tagLabel(pill, "Price", "$0", UDim2.fromScale(0.08, 0.08), UDim2.fromScale(0.84, 0.84), Color3.new(1, 1, 1))
	pill.Parent = tag
	tag.Parent = anchor
	machine.machineTag = tag
end

---------------------------------------------------------------------------------------------
-- Preparation d'un etage ouvert (FloorService.OnFloorAdded : base libre comprise)

local function prepareFloor(floor: Model, index: number)
	if states[floor] ~= nil then
		return
	end
	local state: FloorState = { floor = floor, index = index, player = nil, machines = {}, tiles = {} }

	for _, model in MachineModels.List(floor) do
		local id = model:GetAttribute("UpgradeId")
		if type(id) ~= "string" or Upgrades.ById[id] == nil then
			continue
		end
		local machine: Machine = {
			id = id,
			model = model,
			looks = {},
			ghostOnly = {},
			effects = {},
			anchor = nil,
			prompt = nil,
			machineTag = nil,
			built = nil,
			padLooks = {},
			repeatPad = Upgrades.ById[id].repeatPad == true,
			padZone = nil,
			padTop = nil,
			tag = nil,
			click = nil,
			clickRange = 0,
		}
		local build = model:FindFirstChild("Build")
		for _, item in (if build then build:GetDescendants() else {}) do
			if item:IsA("BasePart") then
				machine.looks[item] = lookOf(item)
				local ghostModel = item:FindFirstAncestorWhichIsA("Model")
				if item:GetAttribute("GhostOnly") or (ghostModel and ghostModel:GetAttribute("GhostOnly")) then
					machine.ghostOnly[item] = true
				end
			elseif item:IsA("ParticleEmitter") or item:IsA("SurfaceGui") then
				machine.effects[item] = item.Enabled
			end
		end
		-- Prompt E "Buy" seulement pour une vraie machine (pas pour le pad "Upgrade Tree", Build vide)
		if Upgrades.ById[id].kind == "Upgrade" and build and build:IsA("Model") and next(machine.looks) ~= nil then
			createMachinePrompt(floor, machine, build)
		end
		local pad = model:FindFirstChild("Pad")
		if pad then
			for _, item in pad:GetChildren() do
				if item:IsA("BasePart") and item.Name ~= "PadZone" then
					machine.padLooks[item] = lookOf(item)
				end
			end
			local zone = pad:FindFirstChild("PadZone")
			local top = pad:FindFirstChild("PadTop")
			machine.padZone = if zone and zone:IsA("BasePart") then zone else nil
			if top and top:IsA("BasePart") then
				machine.padTop = top
				local tag = top:FindFirstChild("Tag")
				machine.tag = if tag and tag:IsA("BillboardGui") then tag else nil
				local click = top:FindFirstChildOfClass("ClickDetector")
				machine.click = click
				machine.clickRange = if click then click.MaxActivationDistance else 0
				-- Achat : marcher dessus (checkPads) ou appui long (BuyController -> BuyUpgrade).
				-- Plus de prompt E sur les pads (un pad = on marche dessus), meme si l'ancien
				-- attribut HirePrompt est encore dans le .rbxl.
			end
		end
		state.machines[id] = machine
	end

	local boards = floor:FindFirstChild("Boards")
	for _, item in (if boards then boards:GetDescendants() else {}) do
		local id = item:GetAttribute("UpgradeId")
		if not item:IsA("Model") or type(id) ~= "string" or Upgrades.ById[id] == nil then
			continue
		end
		local function findPart(name: string): BasePart?
			local p = item:FindFirstChild(name)
			return if p and p:IsA("BasePart") then p else nil
		end
		-- Libelles : n'importe ou dans la tuile (style 2026-11-20 : tout est dessine sur Tile.Display)
		local function findLabel(labelName: string): TextLabel?
			local label = item:FindFirstChild(labelName, true)
			return if label and label:IsA("TextLabel") then label else nil
		end
		local tile: Tile = {
			id = id,
			model = item,
			-- Bouton d'achat = la tuile entiere (clic) ; "BuyButton" pour un ancien panneau
			buy = findPart("BuyButton") or findPart("Tile"),
			robux = findPart("RobuxButton"),
			valueLabel = findLabel("Value"),
			levelLabel = findLabel("Level"),
			priceLabel = findLabel("Price"),
			robuxLabel = findLabel("Robux"),
		}
		local list = state.tiles[id]
		if list == nil then
			list = {}
			state.tiles[id] = list
		end
		table.insert(list, tile)
		-- tile.buy : achat par simple clic (BuyController -> remote BuyUpgrade, 2026-11-20)
		if tile.robux then
			connectClick(floor, tile.robux, function(player: Player)
				onRobuxClick(player, state, tile)
			end)
		end
	end

	states[floor] = state
	refreshFloor(floor, nil)
end

---------------------------------------------------------------------------------------------
-- Remote BuyUpgrade : appui long sur une tuile / un pad, ou "Yes" de la pop-up de confirmation

-- Vrai si le joueur est assez pres d'un point d'achat de cet id sur cet etage.
local function nearBuyPoint(player: Player, state: FloorState, id: string): boolean
	local machine = state.machines[id]
	local floor = state.floor
	if machine then
		local anchor = machine.anchor
		local prompt = machine.prompt
		if anchor and prompt and validClicker(player, floor, anchor, prompt.MaxActivationDistance) then
			return true
		end
		local top = machine.padTop
		if top and (not machine.built or machine.repeatPad) and validClicker(player, floor, top, machine.clickRange) then
			return true
		end
	end
	for _, tile in state.tiles[id] or {} do
		local buy = tile.buy
		local click = buy and buy:FindFirstChildOfClass("ClickDetector")
		if buy and click and validClicker(player, floor, buy, click.MaxActivationDistance) then
			return true
		end
	end
	return false
end

-- Le serveur trouve l'etage tout seul (hauteur du personnage) : jamais un numero envoye par le client.
local function onBuyRequest(player: Player, id: unknown)
	if type(id) ~= "string" or #id > 40 or Upgrades.ById[id] == nil then
		return
	end
	local floor = FloorService.GetPlayerFloor(player)
	local state = floor and states[floor]
	if floor == nil or state == nil or not nearBuyPoint(player, state, id) then
		return
	end
	tryBuy(player, floor, id)
end

---------------------------------------------------------------------------------------------
-- Pads : marcher dessus = acheter (une fois par entree sur le pad). Pad "repeatPad" (Upgrade
-- Tree) : si on reste dessus, 1 niveau de plus toutes les PadRepeatSeconds, jusqu'a un refus
-- (argent, max) ; il faut alors descendre et remonter.

local function checkPads(player: Player)
	local floor = FloorService.GetPlayerFloor(player)
	local state = floor and states[floor]
	local root = getRoot(player)
	if floor == nil or state == nil or root == nil then
		padInside[player] = nil
		padNext[player] = nil
		return
	end
	local inside: string? = nil
	local current = padInside[player]
	for id, machine in state.machines do
		local locked = machine.model:GetAttribute("Locked") == true or not isRevealed(state, id)
		local active = not machine.built or (machine.repeatPad and machine.model:GetAttribute("Price") ~= -1)
		local zone = machine.padZone
		local already = current == floor.Name .. "/" .. id
		if zone and active and not locked and (if already then isStillOver(zone, root.Position) else isOver(zone, root.Position)) then
			inside = id
			break
		end
	end
	-- Cle = etage + id : le meme pad a l'etage du dessus est une nouvelle entree
	local key = if inside then floor.Name .. "/" .. inside else nil
	local now = os.clock()
	if key ~= padInside[player] then
		padInside[player] = key
		padNext[player] = nil
		if inside then
			local ok = tryBuy(player, floor, inside)
			if ok and state.machines[inside].repeatPad then
				padNext[player] = now + Gameplay.PadRepeatSeconds
			end
		end
	elseif inside and padNext[player] and now >= (padNext[player] :: number) then
		lastBuy[player] = nil -- le delai entre deux achats est deja garanti par PadRepeatSeconds
		local ok = tryBuy(player, floor, inside)
		padNext[player] = if ok then now + Gameplay.PadRepeatSeconds else nil
	end
end

function UpgradeService:Init()
	Remotes.GetServerEvent("BuyUpgrade").OnServerEvent:Connect(onBuyRequest)
	-- Un handler par produit "Machine Upgrade" (prix differents, meme effet : +1 niveau a la tuile notee)
	for _, productId in Upgrades.RobuxProducts do
		ReceiptService.Register(productId, onRobuxReceipt)
	end
end

function UpgradeService:Start()
	-- Chaque etage ouvert (base libre comprise) : fantomes, prompts, tuiles
	FloorService.OnFloorAdded(prepareFloor)
	FloorService.OnFloorRemoving(function(floor: Model)
		states[floor] = nil
	end)
	-- Etage d'un joueur charge : ses niveaux ; arret (depart) : niveaux de depart (base libre)
	FloorService.OnFloorStarted(function(player: Player, floor: Model, index: number)
		prepareFloor(floor, index)
		refreshFloor(floor, player)
	end)
	-- Etape FREE faite : ce qui apparait (pads, panneaux, mixeurs) ; le mixeur 1 se construit
	-- (BuildStamp avant le changement, comme un achat)
	SetupService.OnStepDone(function(player: Player, step: number, floor: Model)
		local state = states[floor]
		if state == nil then
			return
		end
		for id, at in SetupConfig.UpgradeBuild do
			local machine = state.machines[id]
			if at == step and machine and machine.built == false then
				bump(machine.model, "BuildStamp")
			end
		end
		refreshFloor(floor, player)
	end)
	FloorService.OnFloorStopped(function(player: Player, floor: Model)
		padInside[player] = nil
		padNext[player] = nil
		if floor.Parent ~= nil then
			refreshFloor(floor, nil)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastBuy[player] = nil
		lastNotify[player] = nil
		robuxIntents[player] = nil
		lastRobuxClick[player] = nil
		padInside[player] = nil
		padNext[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Gameplay.ContactCheckSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(checkPads, player)
				if not ok then
					warn(`[UpgradeService] Erreur de pad pour {player.UserId} : {err}`)
				end
			end
		end
	end)
end

-- Appele apres chaque achat reussi : (joueur, id, nouveau niveau, etage).
function UpgradeService.OnBought(callback: BoughtCallback)
	table.insert(boughtCallbacks, callback)
end

-- Tests Studio (DebugService) : achat comme un vrai clic, sans la distance (etage ou est le joueur).
function UpgradeService.DebugBuy(player: Player, id: string): boolean
	local floor = FloorService.GetPlayerFloor(player)
	if floor == nil then
		return false
	end
	lastBuy[player] = nil
	return tryBuy(player, floor, id)
end

-- Tests Studio : bouton violet de l'id (sans distance ni fenetre) puis recu simule. id "" : recu sans
-- tuile notee (produit 9 R$). Renvoie { granted, productId, level }.
function UpgradeService.DebugRobuxBuy(player: Player, id: string, purchaseId: string): { [string]: any }
	local floor = FloorService.GetPlayerFloor(player)
	local state = floor and states[floor]
	local productId = Upgrades.RobuxProducts[Upgrades.RobuxMax]
	if state and id ~= "" then
		local levels, level = checkBuyable(player, state, id)
		local found = if levels then Upgrades.RobuxProductFor(id, level) else nil
		if found == nil then
			return { granted = false }
		end
		productId = found
		robuxIntents[player] = robuxIntents[player] or {}
		robuxIntents[player][productId] = { index = state.index, id = id, at = os.clock() }
	end
	local granted = onRobuxReceipt({
		PlayerId = player.UserId,
		ProductId = productId,
		PurchaseId = purchaseId,
		CurrencySpent = 0,
		PlaceIdWherePurchased = game.PlaceId,
	})
	local levels = if state then levelsOf(player, state.index) else nil
	return { granted = granted, productId = productId, level = if levels and id ~= "" then levels[id] else nil }
end

-- Prix d'un niveau d'une amelioration sur l'etage n (WorkerService, tests).
function UpgradeService.PriceAt(id: string, level: number, n: number): number
	return priceAt(id, level, n)
end

return UpgradeService
