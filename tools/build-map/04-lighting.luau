--!strict
-- Eclairage "doux et pro" (2026-11-19, nuit) : moins flashy que la premiere version (Brightness 3,
-- ambiance tres claire = herbe menthe surexposee, peu de relief). Ici : soleil moins fort, ombres
-- un peu plus marquees et douces, brume legere qui donne de la profondeur, bloom discret, couleurs
-- legerement desaturees avec un peu plus de contraste, teinte chaude tres legere.
-- 2026-11-20 (utilisateur : couleurs des panneaux "trop sombres, ca donne pas envie", "c'est peut-etre
-- le lighting") : couleurs VIVES comme les tycoons de reference : saturation +0.12 (avant -0.08),
-- exposition 0 (avant -0.1), brume moins epaisse (Haze 0.25, avant 0.6 ; Density 0.2), pas de teinte chaude.
-- 2026-11-20 soir (utilisateur : "eclairage moins bleu") : sans toit, le ciel bleu (Sky Cartoon) teintait
-- murs et sol en cyan. Reflet du ciel coupe (EnvironmentDiffuseScale 0.6 -> 0.1, Specular 0.3 -> 0.1),
-- ambiances gris neutre plus claires (pour garder les murs clairs), brume grise, saturation 0.12 -> 0.05.
-- 2026-11-20 nuit (utilisateur : perso sombre, "on essaye de copier et on arrive pas") : le ciel
-- "Cartoon" (cyan) est SUPPRIME (ciel par defaut de Roblox), donc on peut rendre la lumiere du ciel
-- (EnvironmentDiffuseScale 0.6, Specular 1) sans teinte cyan : le perso et les murs sont eclaires de
-- face. Brightness 2.4, ambiances gris neutre, teinte tres legerement chaude pour retirer le bleu.
-- Ancien ciel si besoin : SkyboxUp rbxassetid://528484371, SkyboxFt rbxassetid://528481964.
-- A lancer une fois dans Studio (mode Edit). Relancable.
-- Doc : docs/systems/carte-bases.md, docs/style.md

local Lighting = game:GetService("Lighting")

-- 2026-11-20 (utilisateur : soleil tout en haut, ombres juste en dessous) : midi + latitude 23.5
-- = soleil au zenith, GetSunDirection() = (0, 1, 0) mesure dans Studio.
Lighting.ClockTime = 12
Lighting.GeographicLatitude = 23.5
Lighting.Brightness = 2.4
Lighting.Ambient = Color3.fromRGB(110, 110, 114)
Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 132)
Lighting.ExposureCompensation = 0
Lighting.ShadowSoftness = 0.5 -- 2026-11-27 : ombres plus douces ("super legeres"), avant 0.35
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 1
Lighting.GlobalShadows = true

local sky = Lighting:FindFirstChildOfClass("Sky")
if sky then
	sky:Destroy() -- ciel par defaut de Roblox (le ciel Cartoon teintait tout en cyan)
end

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
atmosphere.Density = 0.2
atmosphere.Offset = 0.15
atmosphere.Color = Color3.fromRGB(214, 220, 228)
atmosphere.Decay = Color3.fromRGB(166, 172, 184)
atmosphere.Glare = 0
atmosphere.Haze = 0.25
atmosphere.Parent = Lighting

local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
bloom.Intensity = 0.35
bloom.Size = 18
bloom.Threshold = 2.6
bloom.Parent = Lighting

local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
if sunRays then
	sunRays.Intensity = 0.02
end

local cc = Lighting:FindFirstChild("StyleColor") :: ColorCorrectionEffect?
if not cc then
	local created = Instance.new("ColorCorrectionEffect")
	created.Name = "StyleColor"
	created.Parent = Lighting
	cc = created
end
assert(cc)
cc.Brightness = 0.01
cc.Contrast = 0.06
cc.Saturation = 0.05
cc.TintColor = Color3.fromRGB(255, 244, 232) -- tres legerement chaud : retire le bleu

return "Lighting OK"
