--!strict
-- Effets de l'argent encaisse (client seulement, le serveur a deja credite l'argent) :
--   * Feedback "Cash" { amount, from, bills } : des billets 2D sortent du tas d'argent (position 3D
--     projetee a l'ecran), font un petit saut puis volent en courbe, l'un apres l'autre, jusqu'au
--     montant d'argent du HUD (en bas a gauche). A chaque arrivee : un "pop" de plus en plus aigu,
--     le montant du HUD monte d'autant en comptant (MoneyHudController Hold / Release) avec un petit
--     rebond, et le "+$X" juste a droite du montant grimpe. A la fin : gros rebond (plus de "ding" depuis le 2026-11-20), puis
--     le "+$X" monte et s'efface. Deux encaissements rapproches s'additionnent dans le meme "+$X".
--   * Feedback "AutoCash" { amount, from } (pass Auto Collect) : petit "+$5" a cote du montant
--     (un seul texte : les montants rapproches s'y additionnent).
--   * Feedback "InstantSell" { amount, count } (pass Instant Sell) : "pop" de vente (les billets
--     apparaissent sur le tas, ou "+$X" avec Auto Collect).
-- Doc : docs/systems/clients.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local Util = Shared:WaitForChild("Util")
local NumberFormat = require(Util:WaitForChild("NumberFormat"))
local SoundFx = require(Util:WaitForChild("SoundFx"))

local CashController = {}

local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local TextPop = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("TextPop"))
local FONT = PackStyle.FONT -- police commune de l'interface
local CASH_GREEN = PackStyle.MONEY_GREEN
local CASH_STROKE = PackStyle.MONEY_STROKE -- meme contour que le montant du HUD
local BILL_COLORS = { Color3.fromRGB(150, 220, 120), Color3.fromRGB(118, 196, 96) }
local BILL_LIGHT = Color3.fromRGB(205, 245, 180) -- ovale du "$" au milieu du billet
local BILL_DARK = Color3.fromRGB(40, 112, 40) -- contour et "$" du billet
local MAX_BILLS = 24
local BILL_GAP = 0.045 -- secondes entre deux billets (ils arrivent dans l'ordre)
local MIN_SPREAD = 0.4 -- tous les billets partent en 0.4 a 0.9 s : le HUD compte ~0.7 a 1.2 s
local MAX_SPREAD = 0.9
local BILL_HOP = 0.16 -- petit saut hors du tas
local BILL_FLIGHT = 0.5 -- vol jusqu'au montant du HUD (accelere a la fin)
local BILL_HEIGHT = 0.045 -- hauteur d'un billet, en part de la hauteur de l'ecran
local POP_MIN_GAP = 0.03 -- pas deux pops a moins de 30 ms
local POP_STEPS = 14 -- la note monte pendant 14 billets puis reste en haut
local POP_PITCH_STEP = 0.045 -- +4.5 % de hauteur par billet (1.0 -> ~1.6)
local HUD_BUMP = 0.05 -- rebond du montant du HUD a chaque billet
local HUD_BUMP_BIG = 0.2 -- rebond final
local COUNTER_HOLD = 0.9 -- temps d'affichage du "+$X" apres le dernier billet

local player = Players.LocalPlayer
local started = false
local screen: ScreenGui? = nil
local rng = Random.new()
local lastPop = 0
local insetsCopied = false

-- Pont vers MoneyHudController (montant du HUD) : charge a la demande.
type MoneyHud = {
	GetMoneyLabel: () -> TextLabel?,
	Hold: (amount: number) -> number,
	Release: (id: number, amount: number?) -> (),
	Bump: (strength: number) -> (),
}
local moneyHud: MoneyHud? = nil

local function getMoneyHud(): MoneyHud?
	if moneyHud == nil then
		local module = script.Parent:FindFirstChild("MoneyHudController")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				moneyHud = result :: any
			end
		end
	end
	return moneyHud
end

local function isFiniteVector(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local v = value :: Vector3
	for _, c in { v.X, v.Y, v.Z } do
		if c ~= c or math.abs(c) == math.huge then
			return false
		end
	end
	return true
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- Ou est le texte du montant du HUD, dans le repere de notre ScreenGui (memes marges que le HUD) :
-- centre du texte, bord droit du texte, hauteur de la ligne. Sans HUD : coin en bas a gauche.
type MoneySpot = { center: Vector2, right: number, height: number }

local function moneySpot(): MoneySpot
	local gui = screen
	local size = if gui then gui.AbsoluteSize else Vector2.new(1280, 720)
	local hud = getMoneyHud()
	local label = if hud then hud.GetMoneyLabel() else nil
	if label == nil then
		return {
			center = Vector2.new(size.X * 0.1, size.Y * 0.92),
			right = size.X * 0.14,
			height = size.Y * 0.06,
		}
	end
	if gui and not insetsCopied then
		local hudGui = label:FindFirstAncestorOfClass("ScreenGui")
		if hudGui then
			gui.ScreenInsets = hudGui.ScreenInsets
			insetsCopied = true
		end
	end
	local pos, box = label.AbsolutePosition, label.AbsoluteSize
	local width = math.min(label.TextBounds.X, box.X)
	local left = pos.X
	if label.TextXAlignment == Enum.TextXAlignment.Center then
		left += (box.X - width) / 2
	elseif label.TextXAlignment == Enum.TextXAlignment.Right then
		left += box.X - width
	end
	return {
		center = Vector2.new(left + width / 2, pos.Y + box.Y / 2),
		right = left + width,
		height = box.Y,
	}
end

-- Point du monde -> point de notre ScreenGui (nil si derriere la camera).
local function toScreen(world: Vector3): Vector2?
	local camera = workspace.CurrentCamera
	local gui = screen
	if camera == nil or gui == nil then
		return nil
	end
	local point = camera:WorldToViewportPoint(world)
	if point.Z <= 0 then
		return nil
	end
	local p = Vector2.new(point.X, point.Y) - gui.AbsolutePosition
	local size = gui.AbsoluteSize
	return Vector2.new(math.clamp(p.X, 0, size.X), math.clamp(p.Y, 0, size.Y))
end

---------------------------------------------------------------------------------------------
-- Compteur "+$X" a droite du montant du HUD.
type Counter = {
	label: TextLabel,
	stroke: UIStroke,
	scale: UIScale,
	height: number, -- hauteur du texte (px), fixee a la creation
	shown: number, -- montant affiche
	token: number, -- change a chaque mise a jour : annule une disparition deja prevue
}
local counter: Counter? = nil

-- Billets en vol (tous animes par une seule boucle).
type Bill = {
	frame: Frame,
	scale: UIScale,
	start: Vector2, -- sortie du tas (ecran)
	hop: Vector2, -- fin du petit saut
	bend: Vector2, -- decalage du point de controle de la courbe
	rot0: number,
	spin: number,
	flight: number,
	age: number,
	onArrive: () -> (),
}
local bills: { Bill } = {}
local runner: RBXScriptConnection? = nil

local function placeCounter(c: Counter, spot: MoneySpot)
	c.label.Position = UDim2.fromOffset(spot.right + c.height * 0.3, spot.center.Y)
end

local function step(dt: number)
	local spot = moneySpot()
	local target = spot.center
	for i = #bills, 1, -1 do
		local bill = bills[i]
		bill.age += dt
		if bill.age < BILL_HOP then
			-- Saut hors du tas (ralentit en haut)
			local t = bill.age / BILL_HOP
			local e = 1 - (1 - t) * (1 - t)
			local pos = bill.start:Lerp(bill.hop, e)
			bill.frame.Position = UDim2.fromOffset(pos.X, pos.Y)
			bill.scale.Scale = 0.3 + 0.85 * e
			bill.frame.Rotation = bill.rot0 * e
		else
			-- Vol en courbe jusqu'au montant (lent au depart, accelere a l'arrivee)
			local t = math.min((bill.age - BILL_HOP) / bill.flight, 1)
			local e = t * t
			local control = Vector2.new(bill.hop.X + bill.bend.X, math.min(bill.hop.Y, target.Y) + bill.bend.Y)
			local pos = bill.hop:Lerp(control, e):Lerp(control:Lerp(target, e), e)
			bill.frame.Position = UDim2.fromOffset(pos.X, pos.Y)
			bill.scale.Scale = 1.15 - 0.6 * e
			bill.frame.Rotation = (bill.rot0 + bill.spin * t) * (1 - t)
			if t >= 1 then
				table.remove(bills, i)
				bill.frame:Destroy()
				bill.onArrive()
			end
		end
	end
	local c = counter
	if c ~= nil and c.label.Parent ~= nil then
		placeCounter(c, spot)
	end
	if #bills == 0 and counter == nil and runner then
		runner:Disconnect()
		runner = nil
	end
end

local function wake()
	if runner == nil then
		runner = RunService.RenderStepped:Connect(step)
	end
end

local function getCounter(): Counter?
	local current = counter
	if current ~= nil and current.label.Parent ~= nil then
		return current
	end
	local gui = screen
	if gui == nil then
		return nil
	end
	local spot = moneySpot()
	local height = math.max(spot.height * 0.85, 16)
	local label = Instance.new("TextLabel")
	label.Name = "CashCounter"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Size = UDim2.fromOffset(height * 6, height)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.Text = "+$0"
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = CASH_GREEN -- meme vert uni que le montant du HUD (pas de degrade)
	local stroke = PackStyle.stroke(label, 3, CASH_STROKE)
	-- UIScale gardee pour les petits rebonds (bump) ; l'apparition se fait en fondu, sans grossir
	-- depuis 0.2 (sur telephone un texte qui grossit clignote : UI/TextPop)
	local scale = Instance.new("UIScale")
	scale.Parent = label
	local created: Counter = { label = label, stroke = stroke, scale = scale, height = height, shown = 0, token = 0 }
	placeCounter(created, spot)
	label.Parent = gui
	TextPop.FadeIn(label)
	counter = created
	wake() -- le compteur suit le bord droit du montant (qui s'allonge en comptant)
	return created
end

-- Rebond du compteur (petit a chaque billet, grand a la fin) + legere bascule.
local function bump(c: Counter, strength: number)
	c.scale.Scale = 1 + strength
	TweenService:Create(c.scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	c.label.Rotation = rng:NextNumber(-1, 1) * strength * 20
	TweenService:Create(c.label, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Rotation = 0 }):Play()
end

local function counterAdd(value: number)
	local c = getCounter()
	if c == nil then
		return
	end
	c.shown += value
	c.token += 1
	c.label.Text = "+$" .. NumberFormat.Abbreviate(math.floor(c.shown + 0.5))
	bump(c, 0.12)
end

-- Fin de la gerbe : gros rebond, puis le compteur monte et s'efface (sauf si un autre
-- encaissement arrive entre-temps : il continue de compter).
local function counterFinish()
	local c = counter
	if c == nil or c.label.Parent == nil then
		return
	end
	c.token += 1
	local myToken = c.token
	bump(c, 0.35)
	task.delay(COUNTER_HOLD, function()
		if c.token ~= myToken or c.label.Parent == nil then
			return
		end
		if counter == c then
			counter = nil -- ne suit plus le montant : il s'envole
		end
		local fade = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(c.label, fade, {
			Position = c.label.Position - UDim2.fromOffset(0, c.height),
			TextTransparency = 1,
		}):Play()
		TweenService:Create(c.stroke, fade, { Transparency = 1 }):Play()
		TweenService:Create(c.scale, fade, { Scale = 0.7 }):Play()
		task.delay(0.5, function()
			c.label:Destroy()
		end)
	end)
end

-- Petit texte "+$5" (Auto Collect), a droite du montant du HUD. Un seul a la fois (2026-11-23) :
-- les ventes qui arrivent pendant qu'il est affiche s'ajoutent a son montant (avec Auto Collect,
-- chaque etage automatise verse son argent a part : sinon plusieurs textes se superposaient).
type AutoText = { label: TextLabel, stroke: UIStroke, scale: UIScale, height: number, sum: number, token: number }
local autoText: AutoText? = nil
local AUTO_HOLD = 0.6 -- secondes d'affichage apres le dernier ajout
local AUTO_POP_GAP = 0.25 -- pas plus d'un "pop" Auto Collect tous les 0.25 s
local lastAutoPop = 0

local function autoCashText(amount: number)
	local gui = screen
	if gui == nil then
		return
	end
	local current = autoText
	if current and current.label.Parent then
		current.sum += amount
		current.label.Text = "+$" .. NumberFormat.Abbreviate(math.floor(current.sum + 0.5))
		current.scale.Scale = 1.12
		TweenService:Create(current.scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	else
		local spot = moneySpot()
		local height = math.max(spot.height * 0.7, 14)
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.fromOffset(spot.right + height * 0.3, spot.center.Y)
		label.Size = UDim2.fromOffset(height * 5, height)
		label.BackgroundTransparency = 1
		label.FontFace = FONT
		label.Text = "+$" .. NumberFormat.Abbreviate(math.floor(amount + 0.5))
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = CASH_GREEN
		local stroke = PackStyle.stroke(label, 2.5, CASH_STROKE)
		-- UIScale gardee pour le petit rebond quand le montant augmente ; apparition en fondu
		local scale = Instance.new("UIScale")
		scale.Parent = label
		label.Parent = gui
		TextPop.FadeIn(label)
		current = { label = label, stroke = stroke, scale = scale, height = height, sum = amount, token = 0 }
		autoText = current
	end
	local text = current :: AutoText
	text.token += 1
	local myToken = text.token
	task.delay(AUTO_HOLD, function()
		if text.token ~= myToken or text.label.Parent == nil then
			return
		end
		if autoText == text then
			autoText = nil -- le prochain montant ouvre un nouveau texte
		end
		local rise = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(text.label, rise, {
			Position = text.label.Position - UDim2.fromOffset(0, text.height * 1.2),
			TextTransparency = 1,
		}):Play()
		TweenService:Create(text.stroke, rise, { Transparency = 1 }):Play()
		task.delay(0.65, function()
			text.label:Destroy()
		end)
	end)
end

local function makeBill(height: number, color: Color3): (Frame, UIScale)
	local bill = Instance.new("Frame")
	bill.Name = "FlyingBill"
	bill.AnchorPoint = Vector2.new(0.5, 0.5)
	bill.Size = UDim2.fromOffset(height * 2.1, height)
	bill.BackgroundColor3 = color
	bill.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.18, 0)
	corner.Parent = bill
	local stroke = Instance.new("UIStroke")
	stroke.Color = BILL_DARK
	stroke.Thickness = math.max(1, height * 0.07)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = bill
	local mark = Instance.new("TextLabel")
	mark.Name = "Mark"
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.Size = UDim2.fromScale(0.38, 0.76)
	mark.BackgroundColor3 = BILL_LIGHT
	mark.BorderSizePixel = 0
	mark.FontFace = FONT
	mark.Text = "$"
	mark.TextScaled = true
	mark.TextColor3 = BILL_DARK
	local markCorner = Instance.new("UICorner")
	markCorner.CornerRadius = UDim.new(0.5, 0)
	markCorner.Parent = mark
	mark.Parent = bill
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = bill
	return bill, scale
end

local function launchBill(from: Vector3, index: number, onArrive: () -> ())
	local gui = screen
	if gui == nil then
		onArrive()
		return
	end
	local size = gui.AbsoluteSize
	local world = from + Vector3.new(rng:NextNumber(-1.5, 1.5), 0.5, rng:NextNumber(-1.2, 1.2))
	local start = toScreen(world) or Vector2.new(size.X * 0.5, size.Y * 0.6)
	local h = size.Y
	local frame, scale = makeBill(math.max(h * BILL_HEIGHT, 12), BILL_COLORS[(index % 2) + 1])
	local bill: Bill = {
		frame = frame,
		scale = scale,
		start = start,
		hop = start + Vector2.new(rng:NextNumber(-0.07, 0.07) * h, -rng:NextNumber(0.04, 0.11) * h),
		bend = Vector2.new(rng:NextNumber(-0.1, 0.05) * size.X, -rng:NextNumber(0.08, 0.2) * h),
		rot0 = rng:NextNumber(-35, 35),
		spin = rng:NextNumber(-180, 180),
		flight = BILL_FLIGHT + rng:NextNumber(-0.04, 0.04),
		age = 0,
		onArrive = onArrive,
	}
	frame.Position = UDim2.fromOffset(start.X, start.Y)
	frame.Parent = gui
	table.insert(bills, bill)
	wake()
end

-- Gerbe de billets : du tas jusqu'au montant du HUD, l'un apres l'autre.
-- Renvoie faux si elle n'a pas pu partir (pas d'ecran d'effets).
local function cashBurst(from: Vector3, billCount: number, amount: number): boolean
	if screen == nil then
		return false
	end
	local hud = getMoneyHud()
	local holdId = if hud then hud.Hold(amount) else 0
	local count = math.clamp(billCount, 6, MAX_BILLS)
	local spread = math.clamp((count - 1) * BILL_GAP, MIN_SPREAD, MAX_SPREAD)
	local gap = spread / (count - 1)
	local perBill = amount / count
	local arrived = 0
	local function onArrive()
		arrived += 1
		-- Pop dont la note monte a chaque billet (jamais deux pops colles)
		local now = os.clock()
		if now - lastPop >= POP_MIN_GAP then
			lastPop = now
			local stepIndex = math.min(arrived - 1, POP_STEPS)
			SoundFx.Play("CashPop", nil, 1 + stepIndex * POP_PITCH_STEP)
		end
		counterAdd(perBill)
		if arrived == count then
			if hud then
				hud.Release(holdId)
				hud.Bump(HUD_BUMP_BIG)
			end
			counterFinish() -- pas de son de fin (retire le 2026-11-20) : les pops suffisent
		elseif hud then
			hud.Release(holdId, perBill)
			hud.Bump(HUD_BUMP)
		end
	end
	for i = 1, count do
		task.delay((i - 1) * gap, launchBill, from, i, onArrive)
	end
	return true
end

local function onFeedback(kind: any, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local amount = payload.amount
	if not isFiniteNumber(amount) or amount < 0 then
		return
	end
	if kind == "Cash" then
		local from = payload.from
		local billCount = payload.bills
		local burst = false
		if isFiniteVector(from) then
			burst = cashBurst(from, if isFiniteNumber(billCount) then math.floor(billCount) else 8, amount)
		end
		if not burst then
			-- Pas de gerbe possible : le compteur affiche tout d'un coup (le HUD monte seul)
			counterAdd(amount)
			SoundFx.Play("CashPop")
			counterFinish()
		end
	elseif kind == "Paid" then
		-- Achat paye (pad, tuile, etage, menu Upgrades) : son de paiement
		SoundFx.Play("Paid")
	elseif kind == "AutoCash" then
		local now = os.clock()
		if now - lastAutoPop >= AUTO_POP_GAP then
			lastAutoPop = now
			SoundFx.Play("CashPop", nil, 1.2)
		end
		autoCashText(amount)
	elseif kind == "InstantSell" then
		SoundFx.Play("CashPop", nil, 1.05)
	end
end

function CashController.Init() end

function CashController.Start()
	if started then
		return
	end
	started = true
	local gui = Instance.new("ScreenGui")
	gui.Name = "CashFx"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5 -- au-dessus du HUD (0), sous les menus (ShopGUI >= 10)
	gui.IgnoreGuiInset = true -- comme le HUD (DeviceSafeInsets) ; recopie du HUD des qu'il est pret
	gui.Parent = player:WaitForChild("PlayerGui")
	screen = gui
	task.spawn(function()
		local event = Remotes.WaitClientEvent("Feedback")
		if event then
			event.OnClientEvent:Connect(onFeedback)
		end
	end)
end

return CashController
