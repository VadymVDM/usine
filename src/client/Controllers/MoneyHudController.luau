--!strict
-- Affiche l'argent du joueur dans le HUD (PlayerGui.HUD.Canvas.Money.Cash.Money).
-- Le serveur est seul maitre de leaderstats.Cash ; ici on ne fait qu'afficher.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NumberFormat = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("NumberFormat") :: ModuleScript
) :: any

local POP_UP_TIME = 0.08
local POP_SCALE = 1.12
local WAIT_TIMEOUT = 10

local MoneyHudController = {}

local cashConnection: RBXScriptConnection? = nil
local started = false

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
	local label = current :: Instance
	if not label:IsA("TextLabel") then
		warn("[MoneyHudController] " .. label:GetFullName() .. " n'est pas un TextLabel.")
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

	-- UIScale pour l'effet "pop" (cree si absent)
	local scale = label:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = label
	end
	local uiScale = scale :: UIScale

	local popTween: Tween? = nil
	local function pop()
		if popTween then
			popTween:Cancel()
		end
		uiScale.Scale = 1
		local up = TweenService:Create(uiScale, TweenInfo.new(POP_UP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = POP_SCALE })
		local down = TweenService:Create(uiScale, TweenInfo.new(POP_UP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1 })
		popTween = up
		up.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				popTween = down
				down:Play()
			end
		end)
		up:Play()
	end

	local intValue = cash :: IntValue
	local lastValue = intValue.Value
	label.Text = NumberFormat.Money(lastValue)

	if cashConnection then
		cashConnection:Disconnect()
	end
	cashConnection = intValue.Changed:Connect(function(value: number)
		label.Text = NumberFormat.Money(value)
		if value > lastValue then
			pop()
		end
		lastValue = value
	end)
end

return MoneyHudController
