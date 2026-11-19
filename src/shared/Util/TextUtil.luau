--!strict
-- Petites fonctions de texte partagees serveur / client.

local TextUtil = {}

-- Coupe un texte a `maxChars` caracteres sans casser un caractere UTF-8 (string.sub coupe des
-- octets). Renvoie nil si le texte n'est pas de l'UTF-8 valide.
function TextUtil.Truncate(text: string, maxChars: number): string?
	if utf8.len(text) == nil then
		return nil
	end
	local cut = utf8.offset(text, maxChars + 1)
	if cut == nil then
		return text
	end
	return string.sub(text, 1, cut - 1)
end

return table.freeze(TextUtil)
