--!strict
-- Formatage des nombres pour l'interface (fonctions pures, aucun service Roblox).

local NumberFormat = {}

-- Suffixes par palier de 1000 (index 1 = K, 2 = M, ...)
local SUFFIXES: { string } = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- Abaisse (floor) a 2 decimales, sans jamais arrondir vers le haut
local function floor2(x: number): number
	return math.floor(x * 100 + 1e-9) / 100
end

-- Monte (ceil) a 2 decimales : pour les PRIX (2026-11-23). L'argent du HUD est arrondi vers le bas :
-- avec un prix arrondi vers le haut, "argent affiche >= prix affiche" veut toujours dire "assez d'argent".
-- (Bug : prix 1 525 et argent 1 520 affichaient tous les deux "$1.52K" -> "Not enough money!".)
local function ceil2(x: number): number
	return math.ceil(x * 100 - 1e-9) / 100
end

-- Retire les zeros inutiles : "1.50" -> "1.5", "15.00" -> "15"
local function trim(x: number): string
	local s = string.format("%.2f", x)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

-- `up` : arrondi vers le haut (prix), sinon vers le bas (argent, gains).
local function abbreviate(n: number, up: boolean): string
	-- NaN (n ~= n) et infinis -> "0"
	if n ~= n or n == math.huge or n == -math.huge then
		return "0"
	end

	if n < 0 then
		local s = abbreviate(-n, not up)
		if s == "0" then
			return s
		end
		return "-" .. s
	end

	local round = if up then ceil2 else floor2
	if n < 1000 then
		local whole = if up then math.ceil(n - 1e-9) else math.floor(n)
		if whole < 1000 then
			return string.format("%d", whole)
		end
	end

	-- Palier : 1 = K (1e3), 2 = M (1e6), ...
	-- (au moins K : 999.5 arrondi vers le haut donne "1K")
	local tier = math.clamp(math.floor(math.log10(n) / 3), 1, #SUFFIXES)
	-- Correction des erreurs de log10 aux bornes
	while tier > 1 and n < 1000 ^ tier do
		tier -= 1
	end
	while tier < #SUFFIXES and n >= 1000 ^ (tier + 1) do
		tier += 1
	end

	local value = round(n / 1000 ^ tier)
	-- Si on atteint 1000, passer au palier suivant
	if value >= 1000 and tier < #SUFFIXES then
		tier += 1
		value = round(n / 1000 ^ tier)
	end

	return trim(value) .. SUFFIXES[tier]
end

-- Argent, gains : arrondi vers le bas (on n'affiche jamais plus que ce qu'on a).
function NumberFormat.Abbreviate(n: number): string
	return abbreviate(n, false)
end

-- Prix : arrondi vers le haut (on n'affiche jamais moins que ce qu'il faut payer).
function NumberFormat.AbbreviateUp(n: number): string
	return abbreviate(n, true)
end

-- Entier avec virgules : 50000 -> "50,000"
function NumberFormat.Commas(n: number): string
	local text = string.format("%d", math.floor(n))
	local count = 0
	repeat
		text, count = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return text
end

function NumberFormat.Money(n: number): string
	return "$" .. NumberFormat.Abbreviate(n)
end

-- Prix a payer ("$1.53K" pour 1 525) : a utiliser pour TOUT prix compare a l'argent du joueur.
function NumberFormat.Price(n: number): string
	return "$" .. NumberFormat.AbbreviateUp(n)
end

return NumberFormat
