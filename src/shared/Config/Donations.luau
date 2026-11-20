--!strict
-- Dons (pourboires en Robux) : urne + tableau "Top donors" a l'etage 1 de chaque base.
-- Un Developer Product par montant. `productId` = 0 tant que le produit n'est pas cree sur Roblox
-- (Creator Dashboard > Monetization > Developer Products, prix = `robux`) : le bouton affiche alors
-- "Coming soon!" et rien n'est achete.
-- Textes visibles par le joueur : en anglais.
-- Doc : docs/systems/dons.md

export type Amount = { robux: number, productId: number }

local Donations = {}

-- 8 boutons (2 colonnes x 4 lignes), du plus petit au plus grand.
Donations.Amounts = table.freeze({
	table.freeze({ robux = 5, productId = 0 }),
	table.freeze({ robux = 10, productId = 0 }),
	table.freeze({ robux = 25, productId = 0 }),
	table.freeze({ robux = 50, productId = 0 }),
	table.freeze({ robux = 100, productId = 0 }),
	table.freeze({ robux = 500, productId = 0 }),
	table.freeze({ robux = 1000, productId = 0 }),
	table.freeze({ robux = 10000, productId = 0 }),
}) :: { Amount }

-- Sauvegarde (DataStore a part, pas dans le profil du joueur) :
--   StoreName   : cle "u<UserId>" -> { Total = Robux donnes depuis toujours, Receipts = { PurchaseId... } }
--   RankingName : OrderedDataStore, cle "<UserId>" -> Total (classement de tous les serveurs)
Donations.StoreName = "Donations_v1"
Donations.RankingName = "DonationRanking_v1"
Donations.ReceiptsKept = 50 -- derniers achats gardes pour ne jamais compter deux fois le meme

Donations.BoardRows = 8 -- lignes du tableau (= lignes construites par tools/build-map/02i)
Donations.RefreshSeconds = 60 -- relecture du classement (OrderedDataStore : quota par minute)
Donations.RefreshAfterGiftSeconds = 3 -- relecture plus tot juste apres un don

-- Textes
Donations.PromptObject = "Donations"
Donations.PromptAction = "Leave a tip"
Donations.WindowTitle = "DONATIONS"
Donations.WindowSubtitle = "Optional tips - lifetime leaderboard"
Donations.WindowFooter = "Every tip helps the factory squeeze more juice!"
Donations.YourTipsFormat = "Your tips: %s"
Donations.ComingSoon = "Donations: coming soon!"
Donations.ThanksFormat = "Thank you for your %s R$ tip!"
Donations.BroadcastFormat = "%s tipped %s R$!"
Donations.BoardTitle = "TOP DONORS"
Donations.EmptyRow = "Be the first!"
Donations.JarLabel = "Donations!"

-- 14355 -> "14,355"
function Donations.Format(value: number): string
	local text = tostring(math.floor(value))
	local formatted = text
	while true do
		local nextText, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = nextText
		if count == 0 then
			break
		end
	end
	return formatted
end

return table.freeze(Donations)
