--!strict
-- Formatage des nombres pour l'interface (fonctions pures, aucun service Roblox).

local NumberFormat = {}

-- Suffixes par palier de 1000 (index 1 = K, 2 = M, ...)
local SUFFIXES: { string } = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- Abaisse (floor) a 2 decimales, sans jamais arrondir vers le haut
local function floor2(x: number): number
	return math.floor(x * 100 + 1e-9) / 100
end

-- Retire les zeros inutiles : "1.50" -> "1.5", "15.00" -> "15"
local function trim(x: number): string
	local s = string.format("%.2f", x)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

function NumberFormat.Abbreviate(n: number): string
	-- NaN (n ~= n) et infinis -> "0"
	if n ~= n or n == math.huge or n == -math.huge then
		return "0"
	end

	if n < 0 then
		local s = NumberFormat.Abbreviate(-n)
		if s == "0" then
			return s
		end
		return "-" .. s
	end

	if n < 1000 then
		return string.format("%d", math.floor(n))
	end

	-- Palier : 1 = K (1e3), 2 = M (1e6), ...
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES)
	-- Correction des erreurs de log10 aux bornes
	while tier > 1 and n < 1000 ^ tier do
		tier -= 1
	end
	while tier < #SUFFIXES and n >= 1000 ^ (tier + 1) do
		tier += 1
	end

	local value = floor2(n / 1000 ^ tier)
	-- Si on atteint 1000, passer au palier suivant
	if value >= 1000 and tier < #SUFFIXES then
		tier += 1
		value = floor2(n / 1000 ^ tier)
	end

	return trim(value) .. SUFFIXES[tier]
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

return NumberFormat
