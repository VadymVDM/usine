--!strict
-- Chaine de production de chaque ETAGE de la tour (touche E = ProximityPrompt, pads = marcher dessus) :
--   * fruit au sol : marcher dessus = ramasser (fruits a moins de WalkPickupRadius du joueur, test
--     serveur 10 fois / s) -> plateau sur la tete du joueur
--     (attribut TrayFruits "Apple;Orange;Apple" sur le personnage, dans l'ordre du ramassage : le
--     client TrayController dessine le plateau et empile les fruits en vrac ; aussi les attributs
--     joueur InvFruits "Apple=3;Orange=1" et InvMax) ;
--   * pad "Drop Fruits" devant l'etagere (Production.FruitDropPad.PadZone) : s'y tenir = tous les
--     fruits du plateau sont deposes ; chacun part dans les caisses de SON etage (on peut deposer
--     a n'importe quel etage, le fruit vole jusqu'au bon) (1 caisse par rarete, "x12") ;
--   * mixeurs (Production.Blenders.Blender1..4, le 1 est offert) : le tapis amene les fruits des
--     caisses au bol le moins plein des mixeurs possedes (vitesse = Upgrades "ConveyorSpeed" en
--     fruits / s ; trajet ConveyorTravelSeconds, plus court quand le tapis est plus rapide) jusqu'a
--     la taille du bol DE CE MIXEUR (Upgrades "BlenderN", 5 niveaux : 5 / 8 / 12 / 16 / 20) ;
--     "3/5" au-dessus. Attributs de Production pour le client : ConveyorTravel (s), ConveyorRate (fruits / s) ;
--     E sur le mixeur ("Blender / Blend") : mixage de BlendSeconds puis les jus sortent d'un coup
--     sur la table a jus, AUTANT QUE LA TABLE PEUT EN PRENDRE ; le reste reste dans le mixeur (jus
--     en attente, attribut HeldJuices) et coule tout seul des qu'il y a de la place. Tant qu'il
--     reste du jus, le mixeur ne recoit plus de fruits et ne peut pas remixer ;
--   * table a jus : se tenir sur le pad "Take Juices" (Production.TakeJuicePad) = prendre les jus dans les mains (pile devant le torse, attribut CarryPose
--     sur le personnage ; attributs joueur HandJuices / HandMax).
-- Attributs des mixeurs (BlenderN) lus par le client (BlenderFxController) : Pulse (+1) / PulseFruit
-- (un fruit part sur le tapis vers ce bol), BowlFruits ("Apple;Orange"), BowlCount, BowlMax, Owned,
-- Blending, BlendFruits, BlendStamp (+1 au demarrage), PopStamp (+1 quand les jus sortent),
-- HeldJuices (jus encore dans le mixeur, faute de place sur la table).
-- Les gobelets qui sortent ont l'attribut PopFrom (bec du mixeur) et PopIndex : le client les fait
-- sauter du bec jusqu'a leur place. Le contenu des bols n'est pas sauvegarde.
-- API pour le comptoir (CustomerService) et les employes (WorkerService) en bas du fichier.
-- Seul module qui modifie l'inventaire, les mains, les caisses et la table a jus (rien n'est sauvegarde).
-- Doc : docs/systems/chaine-production.md

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Fruits = require(Config:WaitForChild("Fruits"))
local Gameplay = require(Config:WaitForChild("Gameplay"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local FruitModels = require(Shared:WaitForChild("FruitModels"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local Util = Shared:WaitForChild("Util")
local WorldLabel = require(Util:WaitForChild("WorldLabel"))
local NumberFormat = require(Util:WaitForChild("NumberFormat"))
local Prompt = require(Util:WaitForChild("Prompt"))

local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local FloorService = require(script.Parent.FloorService)
local DataService = require(script.Parent.DataService)
local NotifyService = require(script.Parent.NotifyService)
local TreeService = require(script.Parent.TreeService)
-- Capacites du joueur (fruits / jus portes) : menu Upgrade du HUD (Config/PlayerUpgrades)
local PlayerUpgradeService = require(script.Parent.PlayerUpgradeService)
-- Usine a construire (profil neuf) : etagere (etape 2), mixeur 1 + table a jus (etape 3)
local SetupService = require(script.Parent.SetupService)

local ProductionService = {}

local TEXTS = Gameplay.PromptTexts
local MESSAGES = Gameplay.Messages
local CARRY_TAG = "CarryPoseRig" -- tag des personnages dont le client leve les bras (CarryPoseController)
local TRAY_ATTRIBUTE = "TrayFruits" -- sur le personnage : fruits du plateau (lu par TrayController)
local HANDS_ATTRIBUTE = "HandJuices" -- sur le personnage : jus portes (lu par HandStackController)
local MESSAGE_COOLDOWN = 1.2

type Inventory = {
	fruits: { [string]: number }, -- fruits du plateau, par sorte
	fruitTotal: number,
	tray: { string }, -- fruits du plateau dans l'ordre du ramassage (empilement du client)
	juices: { string }, -- jus dans les mains (id du fruit)
	characterConnection: RBXScriptConnection?,
}

type Bowl = {
	index: number,
	model: Model, -- Production.Blenders.BlenderN
	panel: BasePart?, -- panneau de commande (prompt E "Blend")
	spout: BasePart?, -- bec (les gobelets sautent de la)
	labelAnchor: BasePart?,
	fruits: { string }, -- fruits arrives dans le bol
	held: { string }, -- jus mixes qui attendent de la place sur la table (2026-11-20)
	incoming: number, -- fruits sur le tapis vers ce bol
	blending: boolean,
	lastChange: number, -- os.clock du dernier changement du bol (operateur)
	label: BillboardGui?,
	prompt: ProximityPrompt?,
}

type FloorState = {
	player: Player,
	floor: Model, -- etage (Floors.FloorN)
	index: number, -- numero de l'etage = rarete de ses fruits (caisses Bin1..10)
	folder: Folder, -- Dynamic.Production
	bins: { [string]: number }, -- fruits dans les caisses (id -> nombre)
	binParts: { [number]: BasePart }, -- rarete -> fond de la caisse (Bin<rarete>)
	binModels: { [number]: { id: string, model: Model } }, -- rarete -> fruit affiche dans la caisse
	binLabels: { [number]: BillboardGui }, -- rarete -> "x12" au-dessus de la caisse
	juices: { string }, -- table a jus (id du fruit), dans l'ordre de production
	juiceModels: { Model },
	juiceCols: number, -- colonnes de la grille des gobelets (la table s'agrandit avec JuiceLimit)
	juiceOrigin: CFrame?, -- coin de la table (repere de la grille des gobelets)
	juiceZone: BasePart?,
	juiceLabel: BillboardGui?,
	juiceValueLabel: BillboardGui?, -- "$1.2K" vert au-dessus du "n/max" : valeur de vente des jus poses
	dropZone: BasePart?, -- Production.FruitDropPad.PadZone : s'y tenir = deposer les fruits
	takeZone: BasePart?, -- Production.TakeJuicePad.PadZone : s'y tenir = prendre les jus de la table
	onTakePad: boolean, -- le proprietaire etait sur le pad au dernier test (messages a l'arrivee)
	bowls: { Bowl },
	feedThread: thread?,
	active: boolean,
}

local inventories: { [Player]: Inventory } = {}
local floorStates: { [Model]: FloorState } = {}
local feedbackEvent: RemoteEvent? = nil
local worldFxEvent: RemoteEvent? = nil

-- Niveaux des ameliorations de l'etage (nil si la sauvegarde n'est pas chargee).
local function levelsOf(player: Player, index: number): { [string]: number }?
	local data = DataService.GetData(player)
	return if data then DataService.FloorUpgrades(data, index) else nil
end

local function getJuiceLimit(player: Player, index: number): number?
	local levels = levelsOf(player, index)
	if levels == nil then
		return nil
	end
	return math.floor(Upgrades.GetValue("JuiceLimit", levels.JuiceLimit or 1))
end

local function message(player: Player, text: string)
	if PlayerCheck.Cooldown(player, "ProductionMessage", MESSAGE_COOLDOWN) then
		NotifyService.Notify(player, text, true)
	end
end

local function feedback(player: Player, kind: string, payload: { [string]: any })
	if feedbackEvent and player.Parent == Players then
		feedbackEvent:FireClient(player, kind, payload)
	end
end

---------------------------------------------------------------------------------------------
-- Inventaire et mains

local function getInventory(player: Player): Inventory
	local inventory = inventories[player]
	if inventory then
		return inventory
	end
	local created: Inventory = { fruits = {}, fruitTotal = 0, tray = {}, juices = {}, characterConnection = nil }
	inventories[player] = created
	return created
end

-- Plateau : la liste des fruits sur le personnage (le client dessine le plateau et les fruits).
local function syncTray(player: Player)
	local inventory = getInventory(player)
	local character = player.Character
	if character then
		local text = table.concat(inventory.tray, ";")
		if character:GetAttribute(TRAY_ATTRIBUTE) ~= text then
			character:SetAttribute(TRAY_ATTRIBUTE, text)
		end
	end
end

-- Ajoute des fruits au plateau (place libre deja verifiee par l'appelant).
local function addToTray(inventory: Inventory, ids: { string })
	for _, id in ids do
		inventory.fruits[id] = (inventory.fruits[id] or 0) + 1
		table.insert(inventory.tray, id)
	end
	inventory.fruitTotal += #ids
end

-- Ecrit l'inventaire : plateau (personnage) + attributs du joueur (tests, autres scripts).
local function syncInventory(player: Player)
	local inventory = getInventory(player)
	local parts: { string } = {}
	for _, fruit in Fruits.List do
		local count = inventory.fruits[fruit.id]
		if count and count > 0 then
			table.insert(parts, `{fruit.id}={count}`)
		end
	end
	player:SetAttribute("InvFruits", table.concat(parts, ";"))
	player:SetAttribute("InvMax", PlayerUpgradeService.GetValue(player, "FruitCarry"))
	player:SetAttribute("HandJuices", #inventory.juices)
	player:SetAttribute("HandMax", PlayerUpgradeService.GetValue(player, "JuiceCarry"))
	syncTray(player)
end

-- Jus portes : le serveur pose seulement l'attribut "HandJuices" ("Apple;Orange") sur le
-- personnage ; chaque client dessine un plateau de jus sur la tete (HandStackController : gobelets
-- ancres, rebond, vol depuis la table). Avant : pile soudee devant le torse, bras tendus.
local function rebuildHands(player: Player)
	local inventory = getInventory(player)
	local character = player.Character
	if character then
		character:SetAttribute("CarryPose", false) -- plateau sur la tete : bras normaux
		character:SetAttribute(HANDS_ATTRIBUTE, table.concat(inventory.juices, ";"))
	end
end

local function watchCharacter(player: Player)
	local inventory = getInventory(player)
	if inventory.characterConnection then
		return
	end
	local function onCharacter(character: Model)
		CollectionService:AddTag(character, CARRY_TAG)
		character:WaitForChild("HumanoidRootPart", 5)
		if inventories[player] == inventory then
			-- Les jus et les fruits restent apres une reapparition : on redessine les jus et le
			-- plateau sur le nouveau corps.
			rebuildHands(player)
			syncTray(player)
		end
	end
	inventory.characterConnection = player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

---------------------------------------------------------------------------------------------
-- Caisses de l'etagere

-- Une caisse par RARETE (Bin1..10) : elle recoit les fruits de cette rarete de TOUS les etages
-- (depot a n'importe quel etage, retour de test du 2026-11-20). "x12" = total de la caisse ; le
-- fruit montre = celui qu'elle contient le plus.
local function updateBin(state: FloorState, fruitId: string)
	local fruit = Fruits.ById[fruitId]
	if fruit == nil then
		return
	end
	local rarity = fruit.rarity
	local binPart = state.binParts[rarity]
	if binPart == nil then
		return
	end
	local count = 0
	local bestId: string? = nil
	local bestCount = 0
	for id, n in state.bins do
		local other = Fruits.ById[id]
		if other and other.rarity == rarity and n > 0 then
			count += n
			if n > bestCount then
				bestId, bestCount = id, n
			end
		end
	end
	local shown = state.binModels[rarity]
	if shown and shown.id ~= bestId then
		shown.model:Destroy()
		state.binModels[rarity] = nil
		shown = nil
	end
	if bestId and shown == nil then
		local model = FruitModels.CreateFruit(bestId, true)
		model:PivotTo(binPart.CFrame * CFrame.new(0, binPart.Size.Y / 2, 0))
		model.Parent = state.folder
		state.binModels[rarity] = { id = bestId, model = model }
	end
	local label = state.binLabels[rarity]
	if count > 0 then
		if label == nil then
			label = WorldLabel.Create(state.folder, binPart, "BinLabel" .. rarity, {
				maxDistance = Gameplay.BinLabelMaxDistance,
				size = UDim2.fromScale(2.4, 1),
				offset = Vector3.new(0, 2.2, 0),
			})
			state.binLabels[rarity] = label
		end
		WorldLabel.SetPlainText(label :: BillboardGui, "x" .. count)
	elseif label then
		label:Destroy()
		state.binLabels[rarity] = nil
	end
end

local function addToBins(state: FloorState, ids: { string })
	local touched: { [string]: boolean } = {}
	for _, fruitId in ids do
		state.bins[fruitId] = (state.bins[fruitId] or 0) + 1
		touched[fruitId] = true
	end
	for fruitId in touched do
		updateBin(state, fruitId)
	end
end

---------------------------------------------------------------------------------------------
-- Table a jus

local function juiceCupCFrame(state: FloorState, index: number): CFrame?
	local origin = state.juiceOrigin
	local zone = state.juiceZone
	if origin == nil or zone == nil then
		return nil
	end
	-- Bloc compact (juiceCols x JuicePileRows) centre sur la table, empile en couches. La table
	-- s'agrandit avec Juice Table (JuiceLimit) : plus de colonnes, donc une pile moins haute.
	local spacing = Gameplay.JuiceCupSpacing
	local cols = math.clamp(math.floor(zone.Size.X / spacing), 1, state.juiceCols)
	local rows = math.clamp(math.floor(zone.Size.Z / spacing), 1, Gameplay.JuicePileRows)
	local marginX = (zone.Size.X - cols * spacing) / 2
	local marginZ = (zone.Size.Z - rows * spacing) / 2
	local perLayer = cols * rows
	local i = index - 1
	local layer = i // perLayer
	local inLayer = i % perLayer
	local col = inLayer % cols
	local row = inLayer // cols
	return origin
		* CFrame.new(marginX + (col + 0.5) * spacing, layer * (FruitModels.CupHeight + 0.05), marginZ + (row + 0.5) * spacing)
end

-- Colonnes de la grille pour le niveau de Juice Table du proprietaire (paliers de Gameplay).
local function juiceColsFor(player: Player, index: number): number
	local levels = levelsOf(player, index)
	local level = if levels then levels.JuiceLimit or 1 else 1
	local tier = 1
	for i, minLevel in Gameplay.JuiceTableTierLevels do
		if level >= minLevel then
			tier = i
		end
	end
	return Gameplay.JuicePileColsByTier[tier] or Gameplay.JuicePileCols
end

-- La table vient de s'agrandir : les gobelets deja poses se replacent sur la nouvelle grille.
local function relayoutJuices(state: FloorState)
	local cols = juiceColsFor(state.player, state.index)
	if cols == state.juiceCols then
		return
	end
	state.juiceCols = cols
	for index, model in state.juiceModels do
		local cf = juiceCupCFrame(state, index)
		if cf and model.Parent then
			model:PivotTo(cf)
		end
	end
end

local function updateJuiceLabel(state: FloorState)
	relayoutJuices(state)
	local label = state.juiceLabel
	local limit = getJuiceLimit(state.player, state.index)
	if label and limit then
		WorldLabel.SetCount(label, #state.juices, limit)
		-- Table a jus pas encore construite (usine a construire) : pas de "0/10"
		WorldLabel.SetVisible(label, SetupService.Allows(state.floor, 3))
	end
	-- Prix de vente total des jus sur la table (meme prix qu'au comptoir : fruit.value).
	local valueLabel = state.juiceValueLabel
	if valueLabel then
		local total = 0
		for _, fruitId in state.juices do
			local fruit = Fruits.ById[fruitId]
			if fruit then
				total += fruit.value
			end
		end
		WorldLabel.SetVisible(valueLabel, total > 0)
		WorldLabel.SetPlainText(valueLabel, "$" .. NumberFormat.Abbreviate(total), Gameplay.JuiceValueColor)
	end
end

-- Retire les `count` derniers gobelets de la table (les plus hauts). Renvoie leurs ids et la
-- position de chaque gobelet retire (pour l'effet de vol vers les mains).
local function takeFromTable(state: FloorState, count: number): ({ string }, { Vector3 })
	local taken: { string } = {}
	local from: { Vector3 } = {}
	for _ = 1, math.min(count, #state.juices) do
		local index = #state.juices
		local fruitId = table.remove(state.juices) :: string
		local model = state.juiceModels[index]
		state.juiceModels[index] = nil
		if model then
			table.insert(from, model:GetPivot().Position)
			model:Destroy()
		else
			local cf = juiceCupCFrame(state, index)
			table.insert(from, if cf then cf.Position else Vector3.zero)
		end
		table.insert(taken, fruitId)
	end
	updateJuiceLabel(state)
	return taken, from
end

-- Ordre du tapis (2026-11-20, demande utilisateur) : les fruits les PLUS RARES d'abord, puis les
-- moins rares (pommes en dernier) ; a rarete egale, le plus cher (etage le plus haut) d'abord.
local RAREST_FIRST: { Fruits.Fruit } = table.clone(Fruits.List)
table.sort(RAREST_FIRST, function(a, b)
	if a.rarity ~= b.rarity then
		return a.rarity > b.rarity
	end
	if a.value ~= b.value then
		return a.value > b.value
	end
	return a.index < b.index
end)

-- Prend le fruit le plus rare des caisses (ordre RAREST_FIRST). Renvoie son id.
local function takeRarestFruit(state: FloorState): string?
	for _, fruit in RAREST_FIRST do
		local count = state.bins[fruit.id]
		if count and count > 0 then
			state.bins[fruit.id] = count - 1
			updateBin(state, fruit.id)
			return fruit.id
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------
-- Mixeurs : bol, tapis, mixage

local function isOwned(state: FloorState, index: number): boolean
	if index == 1 then
		return SetupService.Allows(state.floor, 3) -- offert, mais construit au pad "Build blender"
	end
	local levels = levelsOf(state.player, state.index)
	return levels ~= nil and (levels["Blender" .. index] or 0) >= 1
end

-- Taille du bol du mixeur `index` (son niveau ; un mixeur pas encore achete compte comme niveau 1).
local function bowlCapacity(state: FloorState, index: number): number
	local levels = levelsOf(state.player, state.index)
	local id = "Blender" .. index
	local level = if levels then levels[id] or 1 else 1
	return math.floor(Upgrades.GetValue(id, math.max(level, 1)))
end

-- Tapis : fruits envoyes par seconde (Upgrades "ConveyorSpeed") et duree du trajet d'un fruit.
local function conveyorRate(state: FloorState): number
	local levels = levelsOf(state.player, state.index)
	local level = if levels then levels.ConveyorSpeed or 1 else 1
	return Upgrades.GetValue("ConveyorSpeed", level)
end

local function conveyorTravel(rate: number): number
	local slowest = Upgrades.GetValue("ConveyorSpeed", 1)
	return math.max(Gameplay.ConveyorTravelMin, Gameplay.ConveyorTravelSeconds * (slowest / rate) ^ 0.6)
end

local function bump(instance: Instance, attribute: string)
	local value = instance:GetAttribute(attribute)
	instance:SetAttribute(attribute, (if type(value) == "number" then value else 0) + 1)
end

-- Ecrit l'etat d'un bol (attributs pour le client, texte "3/5" + pastille "!" quand il est plein).
local function syncBowl(state: FloorState, bowl: Bowl)
	local owned = isOwned(state, bowl.index)
	local capacity = bowlCapacity(state, bowl.index)
	local model = bowl.model
	model:SetAttribute("Owned", owned)
	model:SetAttribute("BowlCount", #bowl.fruits)
	model:SetAttribute("BowlMax", capacity)
	model:SetAttribute("Blending", bowl.blending)
	model:SetAttribute("HeldJuices", #bowl.held)
	local fruitsText = table.concat(bowl.fruits, ";")
	if model:GetAttribute("BowlFruits") ~= fruitsText then
		model:SetAttribute("BowlFruits", fruitsText)
	end
	if owned and bowl.label == nil and bowl.labelAnchor then
		bowl.label = WorldLabel.Create(state.folder, bowl.labelAnchor :: BasePart, "BowlLabel" .. bowl.index, {
			maxDistance = Gameplay.LabelMaxDistance,
			size = UDim2.fromScale(4.5, 1.5),
		})
	end
	local label = bowl.label
	if label then
		WorldLabel.SetVisible(label, owned)
		WorldLabel.SetCount(label, #bowl.fruits, capacity)
	end
end

-- Le tapis envoie le prochain fruit (le plus rare) au bol le moins rempli des mixeurs possedes
-- qui ne mixent pas, n'ont pas de jus en attente et ont encore de la place (fruits arrives +
-- fruits sur le tapis).
local function feedOnce(state: FloorState, travel: number)
	local best: Bowl? = nil
	local bestLoad = math.huge
	for _, bowl in state.bowls do
		if bowl.blending or #bowl.held > 0 or not isOwned(state, bowl.index) then
			continue
		end
		local load = #bowl.fruits + bowl.incoming
		if load < bowlCapacity(state, bowl.index) and load < bestLoad then
			best = bowl
			bestLoad = load
		end
	end
	if best == nil then
		return
	end
	local fruitId = takeRarestFruit(state)
	if fruitId == nil then
		return
	end
	local target = best :: Bowl
	target.incoming += 1
	target.model:SetAttribute("PulseFruit", fruitId)
	bump(target.model, "Pulse")
	task.delay(travel, function()
		if not state.active or floorStates[state.floor] ~= state then
			return
		end
		target.incoming = math.max(0, target.incoming - 1)
		-- Si le joueur a mixe pendant le trajet, le fruit attend dans le bol le prochain mixage
		table.insert(target.fruits, fruitId)
		target.lastChange = os.clock()
		syncBowl(state, target)
	end)
end

local function runFeed(state: FloorState)
	local production = state.floor:FindFirstChild("Production")
	while state.active do
		local rate = conveyorRate(state)
		local travel = conveyorTravel(rate)
		-- Pour l'animation (BlenderFxController : trajet ; LevelLookController : lattes du tapis)
		if production then
			production:SetAttribute("ConveyorTravel", travel)
			-- Tapis pas encore construit (usine a construire) : les lattes ne defilent pas
			production:SetAttribute("ConveyorRate", if SetupService.Allows(state.floor, 2) then rate else nil)
		end
		task.wait(1 / math.max(rate, 0.1))
		if not state.active then
			break
		end
		local ok, err = pcall(feedOnce, state, travel)
		if not ok then
			warn(`[ProductionService] Erreur du tapis ({state.floor.Name}) : {err}`)
		end
		-- La limite peut changer (amelioration) : le texte est remis a jour a chaque tour.
		updateJuiceLabel(state)
	end
end

-- Place libre sur la table a jus (0 si la sauvegarde n'est pas chargee).
local function tableRoom(state: FloorState): number
	local limit = getJuiceLimit(state.player, state.index)
	return if limit then math.max(0, limit - #state.juices) else 0
end

-- Pose des jus sur la table, depuis le bec du mixeur (le client les fait sauter un par un).
local function pourToTable(state: FloorState, bowl: Bowl, ids: { string })
	local spout = bowl.spout
	local from = if spout then spout.Position - Vector3.new(0, spout.Size.Y / 2, 0) else nil
	for k, fruitId in ids do
		table.insert(state.juices, fruitId)
		local cf = juiceCupCFrame(state, #state.juices)
		if cf then
			local cup = FruitModels.CreateCup(fruitId, true)
			cup:PivotTo(cf)
			if from then
				cup:SetAttribute("PopFrom", from)
				cup:SetAttribute("PopIndex", k)
				cup:SetAttribute("PopAt", workspace:GetServerTimeNow())
			end
			cup.Parent = state.folder
			state.juiceModels[#state.juices] = cup
		end
	end
	updateJuiceLabel(state)
end

-- Fin du mixage : les jus sortent d'un coup sur la table, autant qu'elle peut en prendre. Le reste
-- attend dans le mixeur (bowl.held) et coule des qu'il y a de la place (pourHeld). Avant le
-- 2026-11-20 : le mixage etait refuse ("Juice table is full!") des que le bol entier ne tenait pas
-- sur la table, meme quand la table etait vide (bol de 20 > table de 10).
local function finishBlend(state: FloorState, bowl: Bowl, batch: { string })
	if not state.active or floorStates[state.floor] ~= state then
		return
	end
	bowl.blending = false
	bowl.lastChange = os.clock()
	local room = tableRoom(state)
	local now: { string } = {}
	for k, fruitId in batch do
		if k <= room then
			table.insert(now, fruitId)
		else
			table.insert(bowl.held, fruitId)
		end
	end
	pourToTable(state, bowl, now)
	bump(bowl.model, "PopStamp")
	syncBowl(state, bowl)
	if #bowl.held > 0 then
		message(state.player, MESSAGES.JuiceTableFull)
	end
end

-- Jus en attente dans un mixeur : coulent sur la table des qu'il y a de la place (boucle 0.2 s).
local function pourHeld(state: FloorState, bowl: Bowl)
	if #bowl.held == 0 or bowl.blending then
		return
	end
	local room = tableRoom(state)
	if room <= 0 then
		return
	end
	local ids: { string } = {}
	for _ = 1, math.min(room, #bowl.held) do
		table.insert(ids, table.remove(bowl.held, 1) :: string)
	end
	pourToTable(state, bowl, ids)
	bowl.lastChange = os.clock()
	syncBowl(state, bowl)
end

-- Demarre un mixage. Renvoie (vrai) ou (faux, raison) : "Busy", "Empty", "Locked", "Holding"
-- (du jus du mixage precedent attend encore de la place sur la table).
local function startBlend(state: FloorState, bowl: Bowl): (boolean, string?)
	if bowl.blending then
		return false, "Busy"
	end
	if not isOwned(state, bowl.index) then
		return false, "Locked"
	end
	if #bowl.held > 0 then
		return false, "Holding"
	end
	if #bowl.fruits == 0 then
		return false, "Empty"
	end
	local batch = bowl.fruits
	bowl.fruits = {}
	bowl.blending = true
	bowl.lastChange = os.clock()
	bowl.model:SetAttribute("BlendFruits", table.concat(batch, ";"))
	bump(bowl.model, "BlendStamp")
	syncBowl(state, bowl)
	task.delay(Gameplay.BlendSeconds, function()
		local ok, err = pcall(finishBlend, state, bowl, batch)
		if not ok then
			warn(`[ProductionService] Erreur de mixage ({state.floor.Name}) : {err}`)
		end
	end)
	return true, nil
end

local function debugBowls(state: FloorState): { [number]: { [string]: any } }
	local bowls = {}
	for _, bowl in state.bowls do
		bowls[bowl.index] = {
			Owned = isOwned(state, bowl.index),
			Fruits = table.clone(bowl.fruits),
			Held = #bowl.held,
			Incoming = bowl.incoming,
			Blending = bowl.blending,
		}
	end
	return bowls
end

---------------------------------------------------------------------------------------------
-- Actions du joueur (touche E). Chaque handler verifie : proprietaire, distance, delai, etat.

local function ownerState(player: Player, floor: Model): FloorState?
	if FloorService.GetOwner(floor) ~= player then
		return nil
	end
	local state = floorStates[floor]
	if state == nil or state.player ~= player or DataService.GetData(player) == nil then
		return nil
	end
	return state
end

-- Ramassage en marchant (2026-11-19, avant : E sur chaque fruit) : le proprietaire ramasse les
-- fruits au sol tout pres de lui. Appele par la boucle des pads (position verifiee la-bas).
local function walkPickup(state: FloorState, position: Vector3)
	local player = state.player
	local floor = state.floor
	if DataService.GetData(player) == nil then
		return
	end
	local inventory = getInventory(player)
	local free = PlayerUpgradeService.GetValue(player, "FruitCarry") - inventory.fruitTotal
	if free <= 0 then
		-- Plein : prevenir seulement s'il marche sur un fruit
		local nearest = TreeService.FindNearest(floor, position, nil)
		if nearest then
			local p = nearest:GetPivot().Position
			if Vector3.new(p.X - position.X, 0, p.Z - position.Z).Magnitude <= Gameplay.WalkPickupRadius then
				message(player, MESSAGES.InventoryFull)
			end
		end
		return
	end
	local taken = TreeService.TakeNear(floor, position, Gameplay.WalkPickupRadius, free)
	if #taken == 0 then
		return
	end
	local ids: { string } = {}
	for _, item in taken do
		table.insert(ids, item.id)
	end
	addToTray(inventory, ids)
	syncInventory(player)
	feedback(player, "Pickup", { items = taken })
	-- Decouverte au ramassage (lot 4b) : premiere fois -> animation NEW FRUIT! chez le joueur
	for _, id in ids do
		TreeService.Discover(player, id, floor)
	end
end

-- Etat de production de l'etage `index` de ce joueur (nil si pas charge).
local function floorStateOf(player: Player, index: number): FloorState?
	for _, other in floorStates do
		if other.player == player and other.index == index and other.active then
			return other
		end
	end
	return nil
end

-- Pad "Drop Fruits" : tous les fruits du plateau vont dans les caisses. Appele par la boucle des
-- pads quand le proprietaire se tient sur Production.FruitDropPad.PadZone (position verifiee la-bas).
local function dropFruits(state: FloorState)
	local player = state.player
	if DataService.GetData(player) == nil or not SetupService.Allows(state.floor, 2) then
		return
	end
	local inventory = getInventory(player)
	if inventory.fruitTotal <= 0 or not PlayerCheck.Cooldown(player, "FruitDrop", Gameplay.PadActionSeconds) then
		return
	end
	-- TOUS les fruits du plateau, quel que soit leur etage d'origine (retour de test du 2026-11-20 :
	-- "un fruit recolte a n'importe quel etage se depose a n'importe quel etage"). Chaque fruit va
	-- dans la caisse de sa rarete (Bin<rarete>). Seul le serveur connait le plateau : le client
	-- n'envoie rien (pad = position du proprietaire verifiee par la boucle des pads).
	local ids: { string } = {}
	for _, id in inventory.tray do
		if Fruits.ById[id] then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return
	end
	table.clear(inventory.fruits)
	inventory.tray = {}
	inventory.fruitTotal = 0
	-- Chaque fruit va dans les caisses de SON etage (Fruits.floor) du meme joueur, meme si on le
	-- depose ailleurs (retour du 2026-11-20 soir) ; le client le fait voler jusque-la. Si l'etage
	-- n'est pas charge, il reste ici.
	local groups: { [FloorState]: { string } } = {}
	for _, id in ids do
		local target = floorStateOf(player, Fruits.ById[id].floor) or state
		local list = groups[target]
		if list == nil then
			list = {}
			groups[target] = list
		end
		table.insert(list, id)
	end
	for target, list in groups do
		addToBins(target, list)
	end
	syncInventory(player)
	feedback(player, "Deposit", { floor = state.floor, ids = ids })
end

-- Pad "Take Juices" : les jus de la table vont dans les mains (place libre). Appele par la boucle
-- des pads (position verifiee la-bas). `entered` = le joueur vient de monter sur le pad.
local function takeJuices(state: FloorState, entered: boolean)
	local player = state.player
	if DataService.GetData(player) == nil or not SetupService.Allows(state.floor, 3) then
		return
	end
	local inventory = getInventory(player)
	local room = PlayerUpgradeService.GetValue(player, "JuiceCarry") - #inventory.juices
	if #state.juices == 0 then
		if entered then
			message(player, MESSAGES.NoJuice)
		end
		return
	end
	if room <= 0 then
		if entered then
			message(player, MESSAGES.HandsFull)
		end
		return
	end
	if not PlayerCheck.Cooldown(player, "JuiceTable", Gameplay.PadActionSeconds) then
		return
	end
	local taken, from = takeFromTable(state, room)
	for _, fruitId in taken do
		table.insert(inventory.juices, fruitId)
	end
	rebuildHands(player)
	syncInventory(player)
	-- from[k] = d'ou part le jus taken[k] (il arrive a la place #inventory.juices - #taken + k)
	feedback(player, "TakeJuice", { count = #taken, from = from })
end

-- E sur un mixeur : demarre le mixage de tout le bol.
local function onBlend(player: Player, floor: Model, index: number)
	local state = ownerState(player, floor)
	local bowl = state and state.bowls[index]
	local panel = bowl and bowl.panel
	if state == nil or bowl == nil or panel == nil then
		return
	end
	if not PlayerCheck.Cooldown(player, "Blend", Gameplay.PromptCooldownSeconds) then
		return
	end
	if not PlayerCheck.CanReach(player, panel.Position, Gameplay.PromptDistance + 4) then
		return
	end
	local ok, reason = startBlend(state, bowl)
	if not ok and reason == "Holding" then
		message(player, MESSAGES.JuiceTableFull)
	end
end

-- Prompts actifs seulement quand l'action est possible (le client les cache sinon). Fait aussi
-- couler les jus en attente dans les mixeurs quand la table a de la place.
local function refreshPrompts(state: FloorState)
	for _, bowl in state.bowls do
		pourHeld(state, bowl)
		local owned = isOwned(state, bowl.index)
		Prompt.SetActive(bowl.prompt, owned and not bowl.blending and #bowl.held == 0 and #bowl.fruits > 0)
		-- Achat d'un mixeur ou d'un plus grand bol : texte et etiquette a jour
		if bowl.model:GetAttribute("Owned") ~= owned or bowl.model:GetAttribute("BowlMax") ~= bowlCapacity(state, bowl.index) then
			syncBowl(state, bowl)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Bases

local function startFloor(player: Player, floor: Model, floorNumber: number)
	if floorStates[floor] ~= nil then
		return
	end
	local production = floor:FindFirstChild("Production")
	local dynamic = floor:FindFirstChild("Dynamic")
	if production == nil or dynamic == nil then
		warn(`[ProductionService] {floor.Name} : Production ou Dynamic manquant`)
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Production"
	folder.Parent = dynamic

	-- Caisses Bin1..10, une par rarete (Bin1 = Common ... Bin10 = Infinity) ; les fruits de cette
	-- rarete de n'importe quel etage y vont
	local binParts: { [number]: BasePart } = {}
	local binsFolder = production:FindFirstChild("Bins")
	for rarity = 1, #Fruits.Rarities do
		local part = binsFolder and binsFolder:FindFirstChild("Bin" .. rarity)
		if part and part:IsA("BasePart") then
			binParts[rarity] = part
		end
	end

	local dropPad = production:FindFirstChild("FruitDropPad")
	local dropZone = dropPad and dropPad:FindFirstChild("PadZone")
	if dropZone == nil or not dropZone:IsA("BasePart") then
		warn(`[ProductionService] {floor.Name} : Production.FruitDropPad.PadZone manquant`)
	end
	local takePad = production:FindFirstChild("TakeJuicePad")
	local takeZone = takePad and takePad:FindFirstChild("PadZone")
	if takeZone == nil or not takeZone:IsA("BasePart") then
		warn(`[ProductionService] {floor.Name} : Production.TakeJuicePad.PadZone manquant`)
	end
	local juicePile = production:FindFirstChild("JuicePile")
	local pallet = production:FindFirstChild("JuicePallet")
	local juiceOrigin: CFrame? = nil
	local juiceZone: BasePart? = nil
	if juicePile and juicePile:IsA("BasePart") then
		juiceZone = juicePile
		-- Coin de la table, a la hauteur du dessus des planches.
		-- Dessus de la table = bas de la zone JuicePile (02c). Ancien modele (palette au sol, zone
		-- plus basse que les planches) : dessus de la palette.
		local topY = juicePile.Position.Y - juicePile.Size.Y / 2
		if pallet and pallet:IsA("Model") and pallet:GetAttribute("Raised") ~= true then
			local cf, size = pallet:GetBoundingBox()
			topY = cf.Position.Y + size.Y / 2
		end
		local corner = juicePile.CFrame * CFrame.new(-juicePile.Size.X / 2, 0, -juicePile.Size.Z / 2)
		juiceOrigin = corner + Vector3.new(0, topY - corner.Position.Y, 0)
	end

	local state: FloorState = {
		player = player,
		floor = floor,
		index = floorNumber,
		folder = folder,
		bins = {},
		binParts = binParts,
		binModels = {},
		binLabels = {},
		juices = {},
		juiceModels = {},
		juiceCols = juiceColsFor(player, floorNumber),
		juiceOrigin = juiceOrigin,
		juiceZone = juiceZone,
		juiceLabel = nil,
		juiceValueLabel = nil,
		dropZone = if dropZone and dropZone:IsA("BasePart") then dropZone else nil,
		takeZone = if takeZone and takeZone:IsA("BasePart") then takeZone else nil,
		onTakePad = false,
		bowls = {},
		feedThread = nil,
		active = true,
	}
	local blenders = production:FindFirstChild("Blenders")
	for index = 1, Gameplay.MaxBlenders do
		local model = blenders and blenders:FindFirstChild("Blender" .. index)
		if model == nil or not model:IsA("Model") then
			warn(`[ProductionService] {floor.Name} : Production.Blenders.Blender{index} manquant`)
			continue
		end
		local function findPart(name: string): BasePart?
			local found = model:FindFirstChild(name, true)
			return if found and found:IsA("BasePart") then found else nil
		end
		local bowl: Bowl = {
			index = index,
			model = model,
			panel = findPart("Panel"),
			spout = findPart("SpoutTip"),
			labelAnchor = findPart("BowlLabelAnchor"),
			fruits = {},
			held = {},
			incoming = 0,
			blending = false,
			lastChange = os.clock(),
			label = nil,
			prompt = nil,
		}
		if bowl.panel then
			local prompt = Prompt.Create(bowl.panel, TEXTS.BlenderObject, TEXTS.BlenderAction, {
				name = "BlendPrompt",
				distance = Gameplay.PromptDistance,
			})
			prompt.Triggered:Connect(function(who: Player)
				onBlend(who, floor, index)
			end)
			bowl.prompt = prompt
		end
		state.bowls[index] = bowl
	end
	local anchor = production:FindFirstChild("JuiceLabelAnchor")
	if anchor and anchor:IsA("BasePart") then
		state.juiceLabel = WorldLabel.Create(folder, anchor, "JuiceLabel", {
			maxDistance = Gameplay.LabelMaxDistance,
			size = UDim2.fromScale(6, 2),
		})
		state.juiceValueLabel = WorldLabel.Create(folder, anchor, "JuiceValueLabel", {
			maxDistance = Gameplay.LabelMaxDistance,
			size = UDim2.fromScale(7, 2.2),
			offset = Vector3.new(0, Gameplay.JuiceValueLabelLift, 0),
		})
	end
	floorStates[floor] = state
	watchCharacter(player)
	syncInventory(player)
	updateJuiceLabel(state)
	for _, bowl in state.bowls do
		syncBowl(state, bowl)
	end
	refreshPrompts(state)
	state.feedThread = task.spawn(runFeed, state)
end

local function stopFloor(floor: Model)
	local state = floorStates[floor]
	if state == nil then
		return
	end
	floorStates[floor] = nil
	state.active = false
	if state.feedThread and coroutine.status(state.feedThread) == "suspended" then
		task.cancel(state.feedThread)
	end
	-- Les prompts sont sur des pieces du modele (pas dans Dynamic) : on les retire ici.
	-- Bols vides pour le prochain proprietaire (le contenu n'est pas sauvegarde)
	for _, bowl in state.bowls do
		if bowl.prompt then
			bowl.prompt:Destroy()
		end
		bowl.model:SetAttribute("BowlFruits", "")
		bowl.model:SetAttribute("BlendFruits", "")
		bowl.model:SetAttribute("BowlCount", 0)
		bowl.model:SetAttribute("HeldJuices", 0)
		bowl.model:SetAttribute("Blending", false)
		bowl.model:SetAttribute("Owned", bowl.index == 1)
	end
	-- Les autres modeles sont dans le Dynamic de l'etage, vide (ou l'etage detruit) juste apres.
end

local function removePlayer(player: Player)
	local inventory = inventories[player]
	if inventory == nil then
		return
	end
	inventories[player] = nil
	if inventory.characterConnection then
		inventory.characterConnection:Disconnect()
	end
end

-- Remote PadEnter : le client vient de monter sur un pad de production (reaction immediate, sans
-- attendre la boucle des pads ni la position du personnage). Verifie : nom connu, son etage, position
-- (marge PadEnterMargin), delai. La boucle des pads continue tant qu'il reste dessus.
local function onPadEnter(player: Player, padName: any)
	if padName ~= "FruitDrop" and padName ~= "TakeJuice" then
		return
	end
	local floor = FloorService.GetPlayerFloor(player)
	local state = floor and ownerState(player, floor)
	local root = PlayerCheck.GetRoot(player)
	if state == nil or root == nil then
		return
	end
	if not PlayerCheck.Cooldown(player, "PadEnter" .. padName, 0.15) then
		return
	end
	local zone = if padName == "FruitDrop" then state.dropZone else state.takeZone
	if zone == nil or not PlayerCheck.IsOver(zone, root.Position, Gameplay.PadEnterMargin) then
		return
	end
	if padName == "FruitDrop" then
		dropFruits(state)
	else
		takeJuices(state, not state.onTakePad)
		state.onTakePad = true
	end
end

function ProductionService:Init()
	feedbackEvent = Remotes.GetServerEvent("Feedback")
	worldFxEvent = Remotes.GetServerEvent("WorldFx")
	Remotes.GetServerEvent("PadEnter")
end

function ProductionService:Start()
	FloorService.OnFloorStarted(startFloor)
	FloorService.OnFloorStopped(function(_player: Player, floor: Model)
		stopFloor(floor)
	end)
	Players.PlayerRemoving:Connect(removePlayer)
	Remotes.GetServerEvent("PadEnter").OnServerEvent:Connect(function(player: Player, padName: any)
		local ok, err = pcall(onPadEnter, player, padName)
		if not ok then
			warn(`[ProductionService] Erreur de PadEnter : {err}`)
		end
	end)

	-- Contacts du proprietaire de l'etage (10 fois par seconde) : fruits au sol sous ses pieds
	-- (ramassage en marchant) et pad "Drop Fruits"
	task.spawn(function()
		while true do
			task.wait(Gameplay.ContactCheckSeconds)
			for _, state in floorStates do
				local root = PlayerCheck.GetRoot(state.player)
				if root == nil then
					continue
				end
				local ok, err = pcall(walkPickup, state, root.Position)
				if not ok then
					warn(`[ProductionService] Erreur du ramassage : {err}`)
				end
				local zone = state.dropZone
				if zone and PlayerCheck.IsOver(zone, root.Position) then
					ok, err = pcall(dropFruits, state)
					if not ok then
						warn(`[ProductionService] Erreur du pad Drop Fruits : {err}`)
					end
				end
				local takeZone = state.takeZone
				local onTake = takeZone ~= nil and PlayerCheck.IsOver(takeZone, root.Position)
				if onTake then
					ok, err = pcall(takeJuices, state, not state.onTakePad)
					if not ok then
						warn(`[ProductionService] Erreur du pad Take Juices : {err}`)
					end
				end
				state.onTakePad = onTake
			end
		end
	end)

	-- Etat des prompts (actif / inactif) : 5 fois par seconde suffit
	task.spawn(function()
		while true do
			task.wait(0.2)
			for _, state in floorStates do
				local ok, err = pcall(refreshPrompts, state)
				if not ok then
					warn(`[ProductionService] Erreur de prompts : {err}`)
				end
			end
		end
	end)
end

---------------------------------------------------------------------------------------------
-- API (comptoir, employes, tests)

-- Nombre de jus dans les mains du joueur.
function ProductionService.GetHandCount(player: Player): number
	local inventory = inventories[player]
	return if inventory then #inventory.juices else 0
end

-- Retire jusqu'a `max` jus des mains du joueur (pour les poser sur le comptoir). Renvoie leurs ids.
function ProductionService.TakeFromHands(player: Player, max: number): { string }
	local inventory = inventories[player]
	local taken: { string } = {}
	if inventory == nil or max <= 0 then
		return taken
	end
	for _ = 1, math.min(max, #inventory.juices) do
		table.insert(taken, table.remove(inventory.juices) :: string)
	end
	if #taken > 0 then
		rebuildHands(player)
		syncInventory(player)
	end
	return taken
end

-- Vide le plateau de fruits et les jus portes (rebirth, RebirthService) : sinon des fruits ou des jus
-- de l'etage 10 suivraient le joueur sur son nouvel etage 1.
function ProductionService.ClearCarried(player: Player)
	local inventory = inventories[player]
	if inventory == nil then
		return
	end
	table.clear(inventory.fruits)
	inventory.tray = {}
	inventory.fruitTotal = 0
	inventory.juices = {}
	rebuildHands(player)
	syncInventory(player)
end

-- Nombre de jus sur la table a jus de l'etage.
function ProductionService.GetJuiceCount(floor: Model): number
	local state = floorStates[floor]
	return if state then #state.juices else 0
end

-- Le Waiter (WorkerService) prend jusqu'a `max` jus sur la table. Renvoie leurs ids et ou ils etaient
-- (pour les faire sauter jusqu'au comptoir).
function ProductionService.TakeJuices(floor: Model, max: number): ({ string }, { Vector3 })
	local state = floorStates[floor]
	if state == nil or max <= 0 then
		return {}, {}
	end
	return takeFromTable(state, max)
end

-- Pass Thief (ThiefService) : les `max` gobelets du haut de la table, SANS les retirer (la victime
-- ne perd rien, "assurance"). Renvoie les ids, leurs positions et les modeles (le client du voleur
-- les cache chez lui seulement).
function ProductionService.PeekJuices(floor: Model, max: number): ({ string }, { Vector3 }, { Model })
	local state = floorStates[floor]
	local ids: { string } = {}
	local from: { Vector3 } = {}
	local models: { Model } = {}
	if state == nil or max <= 0 then
		return ids, from, models
	end
	local last = #state.juices
	for index = last, math.max(1, last - max + 1), -1 do
		table.insert(ids, state.juices[index])
		local model = state.juiceModels[index]
		if model and model.Parent then
			table.insert(from, model:GetPivot().Position)
			table.insert(models, model)
		else
			local cf = juiceCupCFrame(state, index)
			table.insert(from, if cf then cf.Position else Vector3.zero)
		end
	end
	return ids, from, models
end

-- Nombre de jus poses sur la table a jus de l'etage (0 si l'etage ne tourne pas). Pass Thief.
function ProductionService.GetJuiceCount(floor: Model): number
	local state = floorStates[floor]
	return if state then #state.juices else 0
end

-- Nombre de jus que le joueur peut porter en tout (mains vides). Pass Thief : taille de la "photo".
function ProductionService.GetHandCapacity(player: Player): number
	return math.max(0, PlayerUpgradeService.GetValue(player, "JuiceCarry"))
end

-- Place libre dans les mains du joueur (jus).
function ProductionService.GetHandRoom(player: Player): number
	local inventory = inventories[player]
	local held = if inventory then #inventory.juices else 0
	return math.max(0, PlayerUpgradeService.GetValue(player, "JuiceCarry") - held)
end

-- Pass Thief : met des jus voles dans les mains du joueur (place libre verifiee ici). `from` =
-- positions des gobelets (effet de vol vers les mains), `models` = gobelets a cacher chez lui.
-- Renvoie le nombre de jus donnes.
function ProductionService.GiveJuices(player: Player, ids: { string }, from: { Vector3 }, models: { Model }): number
	if DataService.GetData(player) == nil then
		return 0
	end
	local inventory = getInventory(player)
	local count = math.min(#ids, ProductionService.GetHandRoom(player))
	if count <= 0 then
		return 0
	end
	local given: { Vector3 } = {}
	for k = 1, count do
		local fruitId = ids[k]
		if Fruits.ById[fruitId] then
			table.insert(inventory.juices, fruitId)
			table.insert(given, from[k] or Vector3.zero)
		end
	end
	rebuildHands(player)
	syncInventory(player)
	feedback(player, "TakeJuice", { count = #given, from = given })
	feedback(player, "StolenCups", { cups = table.move(models, 1, math.min(count, #models), 1, {}) })
	return #given
end

-- Le Fruit Picker pose des fruits dans les caisses (effet de vol vu par tous).
function ProductionService.AddFruitsToBins(floor: Model, ids: { string }, from: Vector3?)
	local state = floorStates[floor]
	if state == nil or #ids == 0 then
		return
	end
	addToBins(state, ids)
	if worldFxEvent and from then
		worldFxEvent:FireAllClients(floor, "FruitsToBins", { from = from, ids = ids })
	end
end

-- Nombre total de fruits dans les caisses de l'etage.
function ProductionService.GetBinsTotal(floor: Model): number
	local state = floorStates[floor]
	local total = 0
	if state then
		for _, count in state.bins do
			total += count
		end
	end
	return total
end

-- Etat d'un bol pour l'operateur de ce mixeur (WorkerService). nil si l'etage ne tourne pas.
export type BowlInfo = {
	owned: boolean,
	count: number,
	max: number,
	blending: boolean,
	held: number, -- jus encore dans le mixeur (table pleine) : on ne peut pas remixer
	idleSeconds: number,
}

function ProductionService.GetBowl(floor: Model, index: number): BowlInfo?
	local state = floorStates[floor]
	local bowl = if state then state.bowls[index] else nil
	if state == nil or bowl == nil then
		return nil
	end
	return {
		owned = isOwned(state, index),
		count = #bowl.fruits,
		max = bowlCapacity(state, index),
		blending = bowl.blending,
		held = #bowl.held,
		idleSeconds = os.clock() - bowl.lastChange,
	}
end

-- L'operateur appuie sur le bouton du mixeur (memes regles que le joueur, sans la distance).
function ProductionService.OperatorBlend(floor: Model, index: number): (boolean, string?)
	local state = floorStates[floor]
	local bowl = if state then state.bowls[index] else nil
	if state == nil or bowl == nil then
		return false, "Missing"
	end
	return startBlend(state, bowl)
end

-- Etat lisible pour les tests (DebugService).
function ProductionService.DebugGet(player: Player): { [string]: any }?
	local floor = FloorService.GetPlayerFloor(player)
	local state = floor and floorStates[floor]
	local inventory = inventories[player]
	if state == nil then
		return nil
	end
	return {
		Inventory = if inventory then table.clone(inventory.fruits) else {},
		Hands = if inventory then table.clone(inventory.juices) else {},
		Bins = table.clone(state.bins),
		Juices = table.clone(state.juices),
		Bowls = debugBowls(state),
		BowlMax = (function()
			local list = {}
			for _, bowl in state.bowls do
				list[bowl.index] = bowlCapacity(state, bowl.index)
			end
			return list
		end)(),
		ConveyorRate = conveyorRate(state),
		JuiceLimit = getJuiceLimit(player, state.index),
		Floor = state.index,
		Ground = TreeService.GetGroundCount(state.floor),
	}
end

-- Tests Studio : simule les actions E (sans la distance) et les pads (teleporte dessus).
function ProductionService.DebugAction(player: Player, action: string): boolean
	local floor = FloorService.GetPlayerFloor(player)
	if floor == nil then
		return false
	end
	local state = floorStates[floor]
	if state == nil then
		return false
	end
	local inventory = getInventory(player)
	if action == "PickAll" then
		local free = PlayerUpgradeService.GetValue(player, "FruitCarry") - inventory.fruitTotal
		local items: { TreeService.TakenFruit } = {}
		while free > 0 do
			local model = TreeService.FindNearest(floor, Vector3.zero, nil)
			if model == nil then
				break
			end
			local item = TreeService.TakeFruit(floor, model)
			if item == nil then
				break
			end
			table.insert(items, item)
			free -= 1
		end
		local ids: { string } = {}
		for _, item in items do
			table.insert(ids, item.id)
		end
		addToTray(inventory, ids)
		syncInventory(player)
		feedback(player, "Pickup", { items = items })
		for _, id in ids do
			TreeService.Discover(player, id, floor)
		end
		return #items > 0
	elseif action == "Shelf" then
		-- Teleporte sur le pad "Drop Fruits" : la boucle des pads fait le depot (~0.1 s plus tard)
		local zone = state.dropZone
		local root = PlayerCheck.GetRoot(player)
		if zone == nil or root == nil then
			return false
		end
		PlayerCheck.ResetCooldown(player, "FruitDrop")
		root.CFrame = CFrame.new(zone.Position.X, zone.Position.Y - zone.Size.Y / 2 + 3, zone.Position.Z)
		return true
	elseif action == "TakeJuice" then
		-- Teleporte sur le pad "Take Juices" : la boucle des pads prend les jus (~0.1 s plus tard)
		local zone = state.takeZone
		local root = PlayerCheck.GetRoot(player)
		if zone == nil or root == nil then
			return false
		end
		PlayerCheck.ResetCooldown(player, "JuiceTable")
		root.CFrame = CFrame.new(zone.Position.X, zone.Position.Y - zone.Size.Y / 2 + 3, zone.Position.Z)
		return true
	elseif string.sub(action, 1, 5) == "Blend" then
		-- "Blend1".."Blend4" : comme E sur le mixeur (teleporte devant son panneau)
		local index = tonumber(string.sub(action, 6))
		local bowl = if index then state.bowls[index] else nil
		local panel = bowl and bowl.panel
		local root = PlayerCheck.GetRoot(player)
		if bowl == nil or panel == nil or root == nil then
			return false
		end
		PlayerCheck.ResetCooldown(player, "Blend")
		root.CFrame = CFrame.lookAt(panel.Position + panel.CFrame.LookVector * 4, panel.Position)
		local before = bowl.blending
		onBlend(player, floor, bowl.index)
		return bowl.blending and not before
	elseif action == "FillBins" then
		-- 20 fruits (le premier de la rarete de l'etage) dans les caisses (comme un depot)
		addToBins(state, table.create(20, Fruits.OfFloor(state.index)[1].id))
		return true
	end
	return false
end

return ProductionService
