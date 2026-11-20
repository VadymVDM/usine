--!strict
-- Affiche l'argent du joueur dans le HUD (PlayerGui.HUD.Canvas.Money.Cash.Money).
-- Le serveur est seul maitre de leaderstats.Cash ; ici on ne fait qu'afficher.
-- Le montant affiche MONTE en comptant, il ne saute jamais vers le haut :
--   * encaissement (CashController) : le montant encaisse est retenu (Hold) puis relache billet
--     par billet (Release) quand chaque billet touche le compteur ; le texte compte en suivant ;
--   * autre hausse (Auto Collect, gains hors ligne, admin) : petite montee rapide + rebond ;
--   * baisse (achat) : immediate.
-- Rebond du texte : un ressort (Bump), petit a chaque billet, gros a la fin.
-- Doc : docs/systems/argent.md, docs/systems/clients.md (encaissement)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NumberFormat = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("NumberFormat") :: ModuleScript
) :: any
local Jelly = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Jelly"))

local WAIT_TIMEOUT = 10
local COUNT_RATE = 12 -- vitesse de la montee : ~95 % de l'ecart rattrape en 0.25 s
local RISE_DELAY = 0.12 -- hausse inattendue : on attend un peu (l'encaissement peut arriver juste apres)
local HOLD_TIMEOUT = 4 -- securite : un montant retenu est relache au plus tard apres 4 s
local POP_STRENGTH = 0.12 -- rebond d'une hausse hors encaissement
local BUMP_KICK = 34 -- vitesse donnee au ressort par point de rebond (pic ~ force)
local SCALE_MIN = -0.15
local SCALE_MAX = 0.35

local MoneyHudController = {}

local started = false
local cashConnection: RBXScriptConnection? = nil
local runner: RBXScriptConnection? = nil
local moneyLabel: TextLabel? = nil
local uiScale: UIScale? = nil

local realValue = 0 -- argent du serveur (leaderstats.Cash)
local shown = 0 -- argent affiche (monte en comptant vers realValue - argent retenu)
local shownText = ""
local riseAfter = 0 -- os.clock() avant lequel une hausse inattendue ne commence pas
local popPending = false -- rebond a faire au debut d'une hausse hors encaissement
local holds: { [number]: number } = {} -- id -> montant encore retenu (billets en vol)
local nextHoldId = 0
local spring = Jelly.Spring(420, 16)

local function heldTotal(): number
	local total = 0
	for _, amount in holds do
		total += amount
	end
	return total
end

local function render()
	local label = moneyLabel
	if label == nil then
		return
	end
	local text = NumberFormat.Money(math.floor(shown + 1e-6))
	if text ~= shownText then
		shownText = text
		label.Text = text
	end
end

local function stopRunner()
	if runner then
		runner:Disconnect()
		runner = nil
	end
end

local function step(dt: number)
	-- Montee du nombre affiche vers (argent reel - argent encore en vol). Jamais de baisse ici.
	local goal = math.max(realValue - heldTotal(), 0)
	local counting = false
	if goal > shown then
		counting = true
		if os.clock() >= riseAfter then
			if popPending then
				popPending = false
				if next(holds) == nil then
					spring.v += POP_STRENGTH * BUMP_KICK
				end
			end
			local gap = goal - shown
			local move = gap * (1 - math.exp(-COUNT_RATE * dt))
			if gap - move < 0.5 then
				shown = goal
				counting = false
			else
				shown += move
			end
			render()
		end
	else
		popPending = false
	end
	-- Rebond (ressort)
	Jelly.Step(spring, dt)
	spring.x = math.clamp(spring.x, SCALE_MIN, SCALE_MAX)
	local scale = uiScale
	if scale then
		scale.Scale = 1 + spring.x
	end
	if not counting and Jelly.Resting(spring, 0.001) then
		spring.x = 0
		spring.v = 0
		if scale then
			scale.Scale = 1
		end
		stopRunner()
	end
end

local function wake()
	if runner == nil and moneyLabel ~= nil then
		runner = RunService.RenderStepped:Connect(step)
	end
end

local function onCashChanged(value: number)
	local old = realValue
	realValue = value
	if value < old then
		-- Baisse (achat) : tout de suite
		shown = math.min(shown, math.max(value - heldTotal(), 0))
		render()
	elseif value > old then
		riseAfter = os.clock() + RISE_DELAY
		popPending = true
	end
	wake()
end

-- Le TextLabel du montant (nil tant que le HUD n'est pas pret). Les billets visent son texte.
function MoneyHudController.GetMoneyLabel(): TextLabel?
	local label = moneyLabel
	if label and label.Parent ~= nil then
		return label
	end
	return nil
end

-- Retient `amount` : le HUD ne le montre qu'au fil des Release (billets qui arrivent).
-- Renvoie un identifiant a passer a Release.
function MoneyHudController.Hold(amount: number): number
	nextHoldId += 1
	local id = nextHoldId
	if type(amount) == "number" and amount > 0 and amount < math.huge then
		holds[id] = amount
		task.delay(HOLD_TIMEOUT, function()
			MoneyHudController.Release(id)
		end)
	end
	return id
end

-- Relache `amount` (tout ce qui reste si nil) : le nombre affiche monte d'autant en comptant.
function MoneyHudController.Release(id: number, amount: number?)
	local left = holds[id]
	if left == nil then
		return
	end
	local give = if amount ~= nil and amount == amount then math.clamp(amount, 0, left) else left
	left -= give
	if left > 1e-6 then
		holds[id] = left
	else
		holds[id] = nil
	end
	wake()
end

-- Petit rebond du montant (0.05 = petit, 0.2 = gros).
function MoneyHudController.Bump(strength: number)
	if type(strength) ~= "number" or strength ~= strength then
		return
	end
	spring.v += math.clamp(strength, 0, 0.4) * BUMP_KICK
	wake()
end

function MoneyHudController.Init() end

function MoneyHudController.Start()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local current: Instance? = playerGui:WaitForChild("HUD", 30)
	if not current then
		warn("[MoneyHudController] HUD introuvable dans PlayerGui, argent non affiche.")
		return
	end
	for _, name in { "Canvas", "Money", "Cash", "Money" } do
		local child = (current :: Instance):WaitForChild(name, WAIT_TIMEOUT)
		if not child then
			warn("[MoneyHudController] Element '" .. name .. "' introuvable dans " .. (current :: Instance):GetFullName() .. ".")
			return
		end
		current = child
	end
	local found = current :: Instance
	if not found:IsA("TextLabel") then
		warn("[MoneyHudController] " .. found:GetFullName() .. " n'est pas un TextLabel.")
		return
	end

	local leaderstats = player:WaitForChild("leaderstats", 30)
	if not leaderstats then
		warn("[MoneyHudController] leaderstats introuvable, argent non affiche.")
		return
	end
	local cash = leaderstats:WaitForChild("Cash", WAIT_TIMEOUT)
	if not cash or not cash:IsA("IntValue") then
		warn("[MoneyHudController] leaderstats.Cash introuvable (IntValue attendu).")
		return
	end

	-- UIScale pour le rebond (cree si absent)
	local scale = found:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = found
	end
	uiScale = scale :: UIScale
	moneyLabel = found :: TextLabel

	local intValue = cash :: IntValue
	realValue = intValue.Value
	shown = math.max(realValue - heldTotal(), 0)
	shownText = ""
	render()

	if cashConnection then
		cashConnection:Disconnect()
	end
	cashConnection = intValue.Changed:Connect(onCashChanged)
	wake()
end

return MoneyHudController
