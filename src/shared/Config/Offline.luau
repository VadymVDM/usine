--!strict
-- Gains hors ligne (ecran "Welcome Back!") : reglages. Le serveur calcule tout (OfflineService).
-- Montant = argent/s de la tour en nombres (CustomerService.GetIncomePerSecond : seulement les
-- etages automatises) x temps absent (plafonne a MaxSeconds) x Rate (< 1 : jouer reste mieux).
-- Valeurs A VALIDER (2026-11-20).
-- Doc : docs/systems/gains-hors-ligne.md

local Offline = {}

Offline.Rate = 0.5 -- part de l'argent/s gagnee hors ligne (50 %)
Offline.MaxSeconds = 8 * 3600 -- plafond du temps compte (docs/game-design.md : ~8 h)
Offline.MinAwaySeconds = 5 * 60 -- absence plus courte : rien (pas d'ecran apres un simple rejoin)
Offline.MinAmount = 10 -- montant plus petit : rien (pas d'ecran pour "$2")

-- Achat x2 qui arrive alors que le x2 a deja ete donne (2e achat, recu tres en retard) : on redonne
-- le dernier montant hors ligne, ou au moins FallbackMinutes de gains actuels (jamais 0 contre des Robux).
Offline.FallbackMinutes = 10

Offline.ActionCooldownSeconds = 0.5 -- delai minimum entre deux demandes du client
-- L'offre est calculee au plus tard ce temps apres le chargement, meme sans "Ready" du client :
-- sinon un client qui retient "Ready" pourrait d'abord acheter des ameliorations (argent/s plus haut).
Offline.ComputeDeadlineSeconds = 8
Offline.ReceiptWaitSeconds = 15 -- attente max de la sauvegarde a la reception d'un recu

Offline.Messages = table.freeze({
	ComingSoon = "Robux purchases: coming soon!",
})

return table.freeze(Offline)
