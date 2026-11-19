--!strict
-- Eclairage : soleil d'apres-midi, couleurs naturelles un peu plus contrastees, brume bleutee au
-- loin. A lancer une fois dans Studio (mode Edit). Relancable.
-- Doc : docs/systems/carte-bases.md

local Lighting = game:GetService("Lighting")

Lighting.ClockTime = 14
Lighting.Brightness = 2.4
Lighting.Ambient = Color3.fromRGB(70, 70, 78)
Lighting.OutdoorAmbient = Color3.fromRGB(128, 130, 142)
Lighting.ExposureCompensation = 0
Lighting.GlobalShadows = true

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
atmosphere.Density = 0.24
atmosphere.Offset = 0.2
atmosphere.Color = Color3.fromRGB(200, 222, 240)
atmosphere.Decay = Color3.fromRGB(110, 136, 170)
atmosphere.Glare = 0
atmosphere.Haze = 0.6
atmosphere.Parent = Lighting

local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
bloom.Intensity = 0.6
bloom.Size = 20
bloom.Threshold = 2.2
bloom.Parent = Lighting

local cc = Lighting:FindFirstChild("StyleColor") :: ColorCorrectionEffect?
if not cc then
	local created = Instance.new("ColorCorrectionEffect")
	created.Name = "StyleColor"
	created.Parent = Lighting
	cc = created
end
assert(cc)
cc.Brightness = 0
cc.Contrast = 0.12
cc.Saturation = 0.04
cc.TintColor = Color3.fromRGB(255, 251, 244)

return "Lighting OK"
