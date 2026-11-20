--!strict
-- Trouve les modeles achetables d'une base (attribut UpgradeId) :
--   * Machines.<id> (machines et pads d'employes, tools/build-map/02e) ;
--   * Production.Blenders.BlenderN (mixeurs 2 a 4) et BlenderN.Operator (operateur de chaque
--     mixeur), tools/build-map/02c.
-- Utilise par UpgradeService (serveur), MachineFxController et BuyController (client).
-- Doc : docs/systems/ameliorations-employes.md

local MachineModels = {}

function MachineModels.List(base: Instance): { Model }
	local found: { Model } = {}
	local machines = base:FindFirstChild("Machines")
	for _, item in (if machines then machines:GetChildren() else {}) do
		if item:IsA("Model") and type(item:GetAttribute("UpgradeId")) == "string" then
			table.insert(found, item)
		end
	end
	local production = base:FindFirstChild("Production")
	local blenders = production and production:FindFirstChild("Blenders")
	for _, blender in (if blenders then blenders:GetChildren() else {}) do
		if blender:IsA("Model") and type(blender:GetAttribute("UpgradeId")) == "string" then
			table.insert(found, blender)
		end
		local operator = blender:FindFirstChild("Operator")
		if operator and operator:IsA("Model") and type(operator:GetAttribute("UpgradeId")) == "string" then
			table.insert(found, operator)
		end
	end
	return found
end

function MachineModels.Find(base: Instance, id: string): Model?
	for _, model in MachineModels.List(base) do
		if model:GetAttribute("UpgradeId") == id then
			return model
		end
	end
	return nil
end

return MachineModels
