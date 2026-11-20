--!strict
-- Verifications serveur communes a toutes les actions du joueur (prompts E, pads, contacts) :
-- personnage vivant, distance, position au-dessus d'une zone, delai entre deux actions.
-- Doc : docs/architecture.md (section Remotes et interactions)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gameplay = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Gameplay"))

local PlayerCheck = {}

local lastAction: { [Player]: { [string]: number } } = {}

-- HumanoidRootPart d'un joueur vivant (nil sinon).
function PlayerCheck.GetRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	local humanoid = (character :: Model):FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	return root
end

-- Vrai si `position` est au-dessus de la zone `part` (boite invisible du modele de base).
-- `margin` (studs, a plat, optionnel) : tolerance en plus autour de la zone.
function PlayerCheck.IsOver(part: BasePart, position: Vector3, margin: number?): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local extra = margin or 0
	return math.abs(localPos.X) <= half.X + extra
		and math.abs(localPos.Z) <= half.Z + extra
		and localPos.Y >= -half.Y - 1
		and localPos.Y <= half.Y + Gameplay.PadHeightAbove
end

-- Joueur valide et vivant, a moins de `range` (+ marge) de `position`.
function PlayerCheck.CanReach(player: any, position: Vector3, range: number): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false
	end
	local root = PlayerCheck.GetRoot(player)
	return root ~= nil and (root.Position - position).Magnitude <= range + Gameplay.BuyClickExtraDistance
end

-- Vrai si l'action `key` est permise (au moins `seconds` depuis la derniere) ; enregistre l'action.
function PlayerCheck.Cooldown(player: Player, key: string, seconds: number): boolean
	local now = os.clock()
	local byKey = lastAction[player]
	if byKey == nil then
		byKey = {}
		lastAction[player] = byKey
	end
	local last = byKey[key]
	if last and now - last < seconds then
		return false
	end
	byKey[key] = now
	return true
end

-- Oublie le delai de l'action `key` (tests Studio).
function PlayerCheck.ResetCooldown(player: Player, key: string)
	local byKey = lastAction[player]
	if byKey then
		byKey[key] = nil
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastAction[player] = nil
end)

return PlayerCheck
