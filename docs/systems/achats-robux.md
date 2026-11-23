# Systeme : Achats Robux (boutique, offres limitees, passes)

**Statut :** en cours (effets testes en Studio avec des recus simules le 2026-11-20 ; 45 produits et passes crees sur Roblox le 2026-11-21)
**Derniere mise a jour :** 2026-11-23 (revue des prix : packs, offres, Mega Cash, Lucky Cash, Drink / Rebirth Master, Keep Cash ; montants sans boosts)

## Role

Donne l'effet de ce qu'on achete en Robux dans la boutique (Shop) et dans les offres limitees a
droite de l'ecran : boosts x2 temporaires, packs d'argent, offres, passes 3X CASH, DRINK MASTER,
GREEDY CUSTOMERS, SPEED MASTER, VIP. Le serveur decide de tout (montants, effets) ; le client
affiche et envoie seulement "je veux acheter X". Le jeu reste complet sans payer.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/RobuxShopService.luau` | serveur | Remote `ShopBuy`, recus des produits (boosts, packs, offres), passes VIP / 3X CASH / DRINK MASTER / GREEDY / SPEED MASTER, temps des boosts, montants d'argent |
| `src/server/Lib/Perks.luau` | serveur | Lit les effets (attributs joueur) : argent, chance, vitesse des clients, jus par client, marche |
| `src/server/Services/CustomerService.luau` | serveur | Ventes : argent x Perks, clients plus rapides, 2 jus par client ; `GetRecentIncomePerSecond` |
| `src/server/Lib/FloorIncome.luau` | serveur | Production en nombres : parametre `perks` (chance, debit des clients) |
| `src/server/Services/TreeService.luau` | serveur | Tirage des fruits : Luck de l'arbre x Perks.LuckMultiplier |
| `src/server/Services/PlayerUpgradeService.luau` | serveur | Vitesse de marche x2 (Speed Master) |
| `src/server/Lib/NameTag.luau` | serveur | "[VIP]" dore devant le pseudo |
| `src/server/Lib/GamePass.luau` | serveur | Seul appel a `UserOwnsGamePassAsync` ; toujours non pour le createur du jeu (2026-11-21) |
| `src/client/Controllers/BoostHudController.luau` | client | Potions des boosts actifs (x2 + temps) en ligne tout en bas a droite (telephone : a gauche du bouton de saut) ; tag "[VIP]" dans le chat |
| `src/client/Controllers/ShopController.luau` | client | Boutons d'achat -> `ShopBuy` ; montant des packs (attribut `Cash_<cle>`) |
| `src/client/Controllers/OffersController.luau` | client | Bouton Buy -> `ShopBuy` ; montant des offres d'argent (attribut `Cash_<cle>`) |
| `src/shared/Config/Shop.luau` | partage | Prix, ids, recompenses, `PassEffects`, `BoostStats`, messages |

## Fonctionnement

- **Clic d'achat** (boutique ou offre) -> remote `ShopBuy(kind, key, isGift)`. Le serveur verifie,
  note le montant d'argent affiche (garde `Shop.PendingSeconds`) puis ouvre la fenetre Roblox
  (`Lib/PurchasePrompt`, effet d'ecran). `productId` / `passId` = 0 : message "Robux purchases:
  coming soon!". Cadeau : remote `ShopGift` (GiftService, `cadeaux.md`) ; `isGift` vrai d'un ancien client : "Choose a player to gift!". Pass deja possede (ou recu en cadeau) : "You already own this pass!".
- **Recu** (`ReceiptService` -> `RobuxShopService`) : un recu = un effet, une seule fois
  (`DataService.GrantPurchaseOnce` ; PurchaseId deja vu = deja donne). Joueur absent ou sauvegarde
  pas chargee apres 20 s : recu laisse en attente, Roblox le redonne.
- **Boosts** (Money, Luck, Speed) : `Data.Boosts[stat]["x<mult>"] = secondes restantes`. Meme stat et
  meme multiplicateur : les temps s'additionnent (15 + 15 = 30 min). Plusieurs multiplicateurs sur
  une stat (x2 boutique + x3 Money Rush) : le plus fort tourne d'abord, les autres attendent (rien
  n'est perdu). Le temps ne descend que pendant le jeu (sauvegarde chargee), pas hors ligne.
- **Effets** (multiplications) :
  - argent des ventes = rebirth x Billboard x **3X CASH (x3)** x **boost Money** (ventes dessinees et
    etages en nombres) ;
  - chance des rares = Luck de l'arbre x **DRINK MASTER (x2)** x **boost Luck** (Rare Rain x5) ;
  - temps entre deux ventes / (**SPEED MASTER x2** x **boost Speed**) ;
  - **GREEDY CUSTOMERS** : chaque client achete 2 jus (un seul effet de vente, montant total) ;
  - **SPEED MASTER** : marche x2 (plafond `Gameplay.MaxWalkSpeed`) ;
  - **VIP** : "[VIP]" dore sur le nametag (vu par les autres) et dans le chat.
- **Boost gratuit** (`Shop.FreeBoost`, 2026-11-22) : 2x SPEED (clients 2x plus rapides) offert
  5 min, 3 min de jeu apres le debut du tuto (le compte a rebours est en pause tant que l'attribut
  `IntroPending` est vrai, c.-a-d. pendant la cinematique ; pour un profil deja fait : 3 min apres
  l'arrivee). Ensuite 10 min de pause, puis 5 min de boost, etc. (un toutes les 15 min). Le temps
  s'ajoute au boost Speed x2 sauvegarde (meme potion "x2" + minuteur dans le HUD, BoostHudController)
  + message "FREE SPEED x2 for 5 min!". Aucune proposition d'achat liee. Compte a rebours par session
  (pas sauvegarde : il repart a 3 min a chaque arrivee).
- **Gains hors ligne** (`CustomerService.GetIncomePerSecond`) : passes compris, boosts temporaires NON.
- **Montants d'argent** (packs et offres) : base = le plus grand de (gains reels des dernieres minutes,
  panneaux MONEY / HOUR, **divises par les boosts Money et Speed en cours**, 2026-11-23 : sinon un boost x3
  puis un pack donnait un pack x3) et (gains theoriques des etages automatises). Garde NaN / infini. Pack = base x minutes,
  minimum `minFloorShare` x prix du prochain etage (2026-11-22 : minimum OBLIGATOIRE sur chaque
  recompense Cash, `minAmount` ou `minFloorShare`, verifie au demarrage ; Mega Cash 0.25 ; jamais $0). Offre = base x minutes, plafonne a `floorShare`
  x prix du prochain etage, minimum `minAmount` (Starter Pack : $1K). Le serveur publie les montants
  dans les attributs joueur `Cash_<cle>` (toutes les `Gameplay.IncomeAttributeSeconds`) ; le client
  les affiche. Le recu donne le montant affiche au clic (s'il date de moins de 2 min), sinon recalcule.
- **Autres passes** : AutoCollect (CustomerService), Instant Sell (PassPadService + CustomerService), Waiter Speed x10 et
  Billboard (PassPadService), Thief (ThiefService), Rebirth Master (RebirthService) : `ShopBuy` ouvre
  seulement leur fenetre ; leur service donne l'effet. x2 gains hors ligne : OfflineService.

## Offres au bon moment, essai 3X CASH, lot de passes (2026-11-23)

- **"Almost there!"** : achat d'etage refuse faute d'argent (FloorService) -> Feedback `"NeedCash"`
  `{ floor, missing }`, au plus une fois par `Shop.NeedCash.cooldownSeconds` (180 s). `DealController`
  (client) propose le plus petit pack (`Shop.CashPacks`, montants `Cash_<cle>`) qui couvre ce qui manque
  (sinon le plus gros) ; bouton -> `ShopBuy("CashPack", cle)` (meme chemin que la boutique).
- **Essai gratuit 3X CASH** (`Shop.Cash3xTrial`) : une fois par session, 9 min de jeu apres l'arrivee
  (en pause pendant la cinematique), ventes x3 pendant 3 min, message "FREE 3X CASH for 3 min!".
  Attribut joueur `Cash3xTrialEnd` (fin, `GetServerTimeNow`) ; `Perks.MoneyMultiplier` le compte comme un
  boost (pas hors ligne, retire de la base des packs). Chaque vente (`CustomerService.OnSale`) ajoute
  vente x (1 - 1/3) au surplus. A la fin, si surplus > 0 et pas de pass : Feedback `"TrialEnd"`
  `{ pass, earned }` -> fenetre "Free Trial Over! 3X CASH earned you +$X. Keep it forever?" + bouton 399.
  Pass achete pendant l'essai : essai arrete, pas de fenetre. Pas pour ceux qui ont deja le pass.
- **Ultimate Bundle** (`Shop.Bundles`, Developer Product D50, 499 R$ depuis le 2026-11-23, avant 799) : 3X CASH + Greedy Customers +
  Auto Collect + Instant Sell (946 R$ separes, "SAVE 47%" vrai). Recu -> `Data.GiftedPasses` (comme un
  cadeau, une fois par PurchaseId) + `GamePass.FireGranted` pour chaque pass. Vendu seulement si le
  joueur n'a AUCUN de ces passes (`ShopBuy("Bundle", cle)` refuse : "You already own a pass from this
  bundle!") ; attribut `BundleBlocked_<cle>` -> la carte de la boutique affiche OWNED. Grande carte en
  haut de la section PASSES (`ShopController.buildBundles`), meme largeur que la rangee des passes :
  un logo par pass (sans fond derriere) avec son nom dessous (`labels`), "+" entre les logos. Pas de bouton
  cadeau. Instant Sell a son propre logo (eclair `Lightning`) depuis le 2026-11-23 (avant : celui de Greedy).
- Fenetres : `DealController` (menu "Deal", copie de OfflineEarnings), attend la fermeture d'un autre
  menu ouvert (au plus 5 min). Textes : `Shop.DealTexts`.
- Tests : `Debug.Call("Shop", "Trial", nom, 0, 20)` (essai dans 0 s, qui dure 20 s) ;
  `Debug.Call("Shop", "Bundle", nom, "Ultimate", "id")` (recu simule, ECRIT la sauvegarde ; nettoyer
  avec `Gift Remove` pour chaque pass).

## Remotes

| Nom | Sens | Arguments | Verifications serveur |
|---|---|---|---|
| `ShopBuy` | client -> serveur | (kind : "Boost" / "Pass" / "CashPack" / "Offer", key, isGift) | chaines courtes, cle connue du catalogue, delai 0.5 s ; montants et produit choisis par le serveur ; effet donne seulement a la reception du recu |

Attributs joueur poses par le serveur : `VIP`, `Cash3x`, `DrinkMaster`, `GreedyCustomers`,
`SpeedMaster` (passes) ; `BoostMoney` / `BoostLuck` / `BoostSpeed` (multiplicateur actif) et
`Boost<Stat>End` (fin, `workspace:GetServerTimeNow`) ; `Cash_<cle>` (montants) ;
`OfferBought` = `"<cle>#<n>"` a chaque offre limitee remise (OffersController retire l'offre de l'ecran) ;
`Bought_<cle>` = true pour une offre unique deja achetee (sauvegarde `BoughtOffers`).

**Offres uniques** (`oneTime = true` dans `Config/Shop`, 2026-11-21 : Starter Pack) : a la remise,
la cle est sauvegardee dans `BoughtOffers`. `ShopBuy` refuse ensuite d'ouvrir la fenetre de
paiement (message "You already got this offer!"). Un recu qui arrive quand meme (2 achats tres
rapproches) est donne normalement : le joueur a paye.

## Donnees sauvegardees

- `Boosts` : `{ [stat]: { ["x2"]: secondes } }`, par defaut `{}`. Ajoute sans migration (Reconcile).
  `sanitize` : stats connues (`Shop.BoostStats`), cles `x2`..`x100`, secondes > 0 plafonnees a
  `Shop.BoostMaxSeconds` (7 jours).
- `PurchaseIds` (deja existant) : recus deja donnes.
- Passes : rien (Roblox les garde, `UserOwnsGamePassAsync` a l'arrivee).
- Createur du jeu (`game.CreatorId`) : Roblox lui donne tous ses passes ; `Lib/GamePass` repond non pour lui (partout, Studio et vrai jeu) pour qu'il joue comme un joueur normal. Il les active dans le panneau admin (docs/systems/admin.md).

## Configuration

`src/shared/Config/Shop.luau` : prix, `productId` / `passId`, `rewards` des offres, `minFloorShare`
des packs (0.5 / 1 / 2 / 4 x prix du prochain etage, 2026-11-23), `FreeBoost` (boost gratuit), `PassEffects`,
`BoostMaxSeconds`, `PendingSeconds`, `ReceiptWaitSeconds`, `BuyCooldownSeconds`, `Messages`.

## Produits Roblox (ids)

Liste complete du 2026-11-21 (grep `productId` / `passId` / `ProductId` dans `src`) : **11 Game
Passes + 34 Developer Products = 45**, tous **crees le 2026-11-21** par Open Cloud (outil
`open_cloud_invoke` du MCP Studio, univers 10777527378, sans cle API) et en vente. Ids reportes dans
la Config. Icones envoyees depuis `assets/icons/` (le dossier ICONSPACK n'est pas autorise pour
l'envoi par le MCP). Le prix sur Roblox DOIT rester egal au prix de la Config (le jeu affiche le prix
de la Config) : changer l'un = changer l'autre (Creator Hub > Monetization).

### Game Passes (11)

| # | Nom Roblox | Prix | Description | Icone | Config (cle) | Id |
|---|---|---|---|---|---|---|
| P1 | VIP | 149 | Golden [VIP] tag on your name and in chat. | `vip.png` | `Shop.Passes` VIP || 2092883003 |
| P2 | 3X Cash | 399 | Earn 3x money from every sale, forever. | `cash.png` | `Shop.Passes` Cash3x || 2097328717 |
| P3 | Drink Master | 199 | 2x chance to get rare fruits. | `clover.png` | `Shop.Passes` DrinkMaster || 2092763123 |
| P4 | Greedy Customers | 199 | Every customer buys 2 drinks at a time. | `customers.png` | `Shop.Passes` GreedyCustomers || 2093182972 |
| P5 | Speed Master | 99 | 2x walk speed and 2x faster customers. | `shoe.png` | `Shop.Passes` SpeedMaster || 2093482922 |
| P6 | Auto Collect (All Floors) | 149 | Your cash goes straight to your wallet. | `magnet.png` | `Shop.Passes` AutoCollect || 2092570991 |
| P7 | Instant Sell (All Floors) | 199 | Juices sell as soon as you drop them on the counter. | `lightning.png` | `Shop.Passes` InstantSell || 2093680945 |
| P8 | Waiter Speed x10 (All Floors) | 149 | Your waiter works 10x faster, forever. | `shoe.png` | `Shop.Passes` SpeedBoost || 2092415019 |
| P9 | Billboard | 99 | Your billboard doubles your sell price, forever. | `cash.png` | `Shop.Passes` Billboard || 2093464945 |
| P10 | Thief | 149 | Steal ready drinks from other stands! | `thief.png` | `Shop.Passes` Thief || 2097082802 |
| P11 | Rebirth Master | 199 | Keep your tree level when you rebirth. | `rebirth.png` | `Shop.Passes` RebirthMaster || 2096880861 |

### Developer Products (35 + 14 ajoutes ensuite)

| # | Nom Roblox | Prix | Description | Icone | Config (cle) | Id |
|---|---|---|---|---|---|---|
| D1 | 2x Speed (15 min) | 9 | Customers come 2x faster for 15 minutes. | `potion_purple.png` | `Shop.Boosts` CustomerSpeed 15 || 3734031035 |
| D2 | 2x Speed (30 min) | 16 | Customers come 2x faster for 30 minutes. | `potion_purple.png` | `Shop.Boosts` CustomerSpeed 30 || 3734031053 |
| D3 | 2x Money (15 min) | 9 | Earn 2x money for 15 minutes. | `potion_green.png` | `Shop.Boosts` Money 15 || 3734031057 |
| D4 | 2x Money (30 min) | 16 | Earn 2x money for 30 minutes. | `potion_green.png` | `Shop.Boosts` Money 30 || 3734031061 |
| D5 | 2x Luck (15 min) | 9 | 2x chance of rare fruits for 15 minutes. | `potion_blue.png` | `Shop.Boosts` Luck 15 || 3734031066 |
| D6 | 2x Luck (30 min) | 16 | 2x chance of rare fruits for 30 minutes. | `potion_blue.png` | `Shop.Boosts` Luck 30 || 3734031073 |
| D7 | Cash - 15 minutes | 19 | Get 15 minutes of your earnings right now. | `cash.png` | `Shop.CashPacks` Cash5m || 3734031076 |
| D8 | Cash - 1 hour | 49 | Get 1 hour of your earnings right now. | `cash.png` | `Shop.CashPacks` Cash30m || 3734031080 |
| D9 | Cash - 4 hours | 129 | Get 4 hours of your earnings right now. | `cash.png` | `Shop.CashPacks` Cash3h || 3734031084 |
| D10 | Cash - 12 hours | 299 | Get 12 hours of your earnings right now. Best value! | `cash.png` | `Shop.CashPacks` Cash10h || 3734031092 |
| D11 | Double Offline Earnings | 9 | Double the cash you earned while away. | `clock.png` | `Shop.OfflineDouble` || 3734031096 |
| D12 | Starter Pack | 19 | 2x money for 15 minutes plus a bag of cash. One time only. | `gift.png` | `Shop.LimitedOffers.FirstOffer` OfferStarter || 3734031104 |
| D13 | Money Rush | 15 | Earn 3x money for 15 minutes. | `cash.png` | `Pool` OfferMoneyRush || 3734031113 |
| D14 | Lucky Hour | 19 | 2x chance of rare fruits for 1 hour. | `clover.png` | `Pool` OfferLuckyHour || 3734031128 |
| D15 | Customer Rush | 15 | Customers come 3x faster for 15 minutes. | `shoe.png` | `Pool` OfferRush || 3734031132 |
| D16 | Mega Cash | 49 | A huge bag of cash: enough for your next floor! | `cash.png` | `Pool` OfferMegaCash || 3734031138 |
| D17 | Triple Boost | 35 | 2x money, 2x luck and 2x speed for 30 minutes. | `potion_purple.png` | `Pool` OfferTriple || 3734031141 |
| D18 | Rare Rain | 19 | 5x chance of rare fruits for 10 minutes. | `clover.png` | `Pool` OfferRareRain || 3734031150 |
| D19 | Lucky Cash | 19 | You found a secret cash stash! Take it all. | `cash.png` | `LuckyCash.Products[2]` (2+ etages) || 3734031154 |
| D36 | Machine Upgrade I | 5 | +1 level on the upgrade you picked. | `upgrade_arrow.png` | `Upgrades.RobuxProducts[5]` (tuiles, cree le 2026-11-23) || 3734912690 |
| D37 | Machine Upgrade II | 8 | +1 level on the upgrade you picked. | `upgrade_arrow.png` | `Upgrades.RobuxProducts[8]` || 3734912738 |
| D38 | Machine Upgrade III | 9 | +1 level on the upgrade you picked. | `upgrade_arrow.png` | `Upgrades.RobuxProducts[9]` || 3734912752 |
| D39 | Gift - VIP | 149 | Gift the VIP pass to another player. | `vip.png` | `Shop.Passes` VIP `giftProductId` (cadeau, 2026-11-23) || 3734927628 |
| D40 | Gift - 3X Cash | 399 | Gift the 3X Cash pass to another player. | `cash.png` | `Shop.Passes` Cash3x `giftProductId` (cadeau, 2026-11-23) || 3734927641 |
| D41 | Gift - Drink Master | 199 | Gift the Drink Master pass to another player. | `clover.png` | `Shop.Passes` DrinkMaster `giftProductId` (cadeau, 2026-11-23) || 3734927655 |
| D42 | Gift - Greedy Customers | 199 | Gift the Greedy Customers pass to another player. | `customers.png` | `Shop.Passes` GreedyCustomers `giftProductId` (cadeau, 2026-11-23) || 3734927668 |
| D43 | Gift - Speed Master | 99 | Gift the Speed Master pass to another player. | `shoe.png` | `Shop.Passes` SpeedMaster `giftProductId` (cadeau, 2026-11-23) || 3734927675 |
| D44 | Gift - Auto Collect | 149 | Gift the Auto Collect pass to another player. | `magnet.png` | `Shop.Passes` AutoCollect `giftProductId` (cadeau, 2026-11-23) || 3734927684 |
| D45 | Gift - Instant Sell | 199 | Gift the Instant Sell pass to another player. | `lightning.png` | `Shop.Passes` InstantSell `giftProductId` (cadeau, 2026-11-23) || 3734927692 |
| D46 | Gift - Waiter Speed x10 | 149 | Gift the Waiter Speed x10 pass to another player. | `shoe.png` | `Shop.Passes` SpeedBoost `giftProductId` (cadeau, 2026-11-23) || 3734927704 |
| D47 | Gift - Billboard | 99 | Gift the Billboard pass to another player. | `cash.png` | `Shop.Passes` Billboard `giftProductId` (cadeau, 2026-11-23) || 3734927718 |
| D48 | Gift - Thief | 149 | Gift the Thief pass to another player. | `thief.png` | `Shop.Passes` Thief `giftProductId` (cadeau, 2026-11-23) || 3734927725 |
| D49 | Gift - Rebirth Master | 199 | Gift the Rebirth Master pass to another player. | `rebirth.png` | `Shop.Passes` RebirthMaster `giftProductId` (cadeau, 2026-11-23) || 3734927736 |
| D35 | Lucky Cash (Floor 1) | 9 | You found a secret cash stash! Take it all. | `cash.png` | `LuckyCash.Products[1]` (etage 1 seul, cree le 2026-11-22) || 3734874589 |
| D20 | Rebirth & Keep Cash I | 49 | Rebirth and keep all your cash. | `rebirth.png` | `Rebirth.KeepCashProducts[1]` (1er rebirth) || 3734031157 |
| D21 | Rebirth & Keep Cash II | 99 | Rebirth and keep all your cash. | `rebirth.png` | `Rebirth.KeepCashProducts[2]` (1+) || 3734031163 |
| D22 | Rebirth & Keep Cash III | 199 | Rebirth and keep all your cash. | `rebirth.png` | `Rebirth.KeepCashProducts[3]` (5+) || 3734031169 |
| D23 | Rebirth & Keep Cash IV | 299 | Rebirth and keep all your cash. | `rebirth.png` | `Rebirth.KeepCashProducts[4]` (15+) || 3734031171 |
| D24 | Speed Upgrade | 9 | +1 level of walk speed. | `shoe.png` | `PlayerUpgrades` WalkSpeed || 3734031179 |
| D25 | Fruit Tray Upgrade | 9 | Carry more fruits (+1 level). | `upgrade_arrow.png` | `PlayerUpgrades` FruitCarry || 3734031231 |
| D26 | Juice Tray Upgrade | 9 | Carry more juices (+1 level). | `potion_blue.png` | `PlayerUpgrades` JuiceCarry || 3734031188 |
| D27 | Tip 5 | 5 | Thank you for supporting the game! | `robux_gold.png` | `Donations` 5 || 3734031236 |
| D28 | Tip 10 | 10 | Thank you for supporting the game! | `robux_gold.png` | `Donations` 10 || 3734031243 |
| D29 | Tip 25 | 25 | Thank you for supporting the game! | `robux_gold.png` | `Donations` 25 || 3734031246 |
| D30 | Tip 50 | 50 | Thank you for supporting the game! | `robux_gold.png` | `Donations` 50 || 3734031251 |
| D31 | Tip 100 | 100 | Thank you for supporting the game! | `robux_gold.png` | `Donations` 100 || 3734031256 |
| D32 | Tip 500 | 500 | Thank you for supporting the game! | `robux_gold.png` | `Donations` 500 || 3734031263 |
| D33 | Tip 1000 | 1000 | Thank you for supporting the game! | `robux_gold.png` | `Donations` 1000 || 3734031268 |
| D34 | Tip 10000 | 10000 | Thank you for supporting the game! | `robux_gold.png` | `Donations` 10000 || 3734031277 |
| D50 | Ultimate Bundle | 499 | 3X Cash + Greedy Customers + Auto Collect + Instant Sell. Save 47%! | `gift.png` | `Shop.Bundles` Ultimate (cree le 2026-11-23) || 3734946982 |

Renommes le 2026-11-23 : P6, P7, P8 finissent par "(All Floors)" sur Roblox (Open Cloud PATCH, icone renvoyee identique) et dans les titres de `Shop.Passes`. Les etiquettes des pads violets restent sans "(All Floors)" (choix utilisateur).

Notes : l'ancien "Auto Sell" s'appelle **Instant Sell** depuis le 2026-11-21. Les pads violets
(PassPadService) lisent les ids de `Shop.Passes`, pas de la table de `PassPadService`.

## Tests (Studio)

```
game.ServerStorage.Debug.Call:Invoke("Shop", "Get", "<Nom>")
game.ServerStorage.Debug.Call:Invoke("Shop", "Grant", "<Nom>", "Boost", "Money_15", "id-optionnel")
game.ServerStorage.Debug.Call:Invoke("Shop", "Grant", "<Nom>", "CashPack" | "Offer", "Cash5m" | "OfferStarter")
game.ServerStorage.Debug.Call:Invoke("Shop", "Pass", "<Nom>", "Cash3x", true)
game.ServerStorage.Debug.Call:Invoke("Shop", "ClearBoosts", "<Nom>")
game.ServerStorage.Debug.Call:Invoke("Shop", "ClearOffers", "<Nom>") -- oublie le Starter Pack achete (pour le retester)
game.ServerStorage.Debug.Call:Invoke("Shop", "FreeBoost", "<Nom>", 0) -- boost gratuit dans 0 s (renvoie l'ancien delai)
```

## Problemes connus / a faire

- **Revue des prix du 2026-11-23 (fait) :** packs 15 min / 1 h / 4 h / 12 h a 19 / 49 / 129 / 299
  (BEST VALUE sur le 12 h), minimum 0.5 / 1 / 2 / 4 x prochain etage ; Money / Customer Rush 15 min,
  Lucky Hour 19, Triple Boost 30 min, Rare Rain 10 min ; Mega Cash 49 R$ (90 min, plafond 1.5, minimum
  0.8 x prochain etage) ; Lucky Cash 19 R$ (plafond 0.8) ; Drink Master et Rebirth Master 199 (+ cadeaux) ;
  Keep Cash 49 seulement au 1er rebirth. 15 produits / passes changes sur Roblox (Open Cloud PATCH),
  verifies par GetProductInfo. Recus d'amelioration sans rien a donner : corrige (autre amelioration ou argent).
- **Relecture securite du 2026-11-23 (corrige) :**
  - `Lib/GamePass.OnPurchased` est le seul branchement sur `PromptGamePassPurchaseFinished` : le
    "purchased" du client n'est plus cru, la possession est redemandee a Roblox (`Owns`) avant
    l'effet. Utilise par RobuxShop, Customer (Auto Collect), PassPad, Rebirth (Master), Thief.
  - `GamePass.Owns` : 3 nouveaux essais (1 s, 2 s, 4 s) si Roblox ne repond pas, et un "oui" est
    garde en memoire pour la session (avant : un seul echec = pass perdu jusqu'au retour).
  - Keep Cash : un recu d'un palier moins cher que celui du joueur ne donne plus de rebirth
    (message `KeepCashWrongTier`, avertissement console).
- **Relecture du 2026-11-23, pas encore corrige :**
  - Keep Cash : le rebirth (code du monde) tourne dans `GrantPurchaseOnce` ; risque de rebirth
    donne 2 fois si le serveur plante au mauvais moment.
  - Cadeau : le destinataire choisi n'est garde qu'en memoire ; si le 1er essai du recu echoue et
    que l'acheteur part, le pass va a l'acheteur.

- Produits et passes crees (2026-11-21). Verifie en Studio : les 45 ids existent, sont en vente et
  ont le prix de la Config (`GetProductInfo`) ; boost, pack, offre et Lucky Cash ouvrent la fenetre
  d'achat (Feedback `PurchasePrompt`, plus de "coming soon"). La fenetre Roblox elle-meme n'apparait
  pas dans les captures MCP. Aucun vrai achat fait.
- **Le compte createur possede automatiquement tous ses passes** : en Studio, le profil de test a
  donc tous les effets (ventes x3, Billboard x2, marche x2, Auto Collect...). Les mesures d'economie
  faites avec ce compte sont faussees ; tester les passes avec un autre compte (ou couper les effets).
- Cadeaux de passes : faits le 2026-11-23, voir `cadeaux.md` (11 produits "Gift - <pass>", meme prix que le pass).
- Boutons violets des tuiles d'amelioration : vrais achats depuis le 2026-11-23 (voir `ameliorations-employes.md`).
- La boutique ne montre pas encore "OWNED" sur un pass possede (le serveur refuse le 2e achat).
- (Ancien, remplace le 2026-11-23) Packs revus le 2026-11-22 : 6 min / 35 min / 4 h / 10 h, minimum 0.3 / 0.6 / 1.2 / 3 x le prochain etage,
  22 / 75 / 189 / 479 R$, "BEST VALUE" sur le 4 h (vrai meilleur rapport minutes / Robux). Prix,
  noms et descriptions changes aussi sur Roblox (Open Cloud PATCH, verifie par GetProductInfo).
- Si un pass est cree plus tard, verifier qu'aucun ancien attribut de test ne reste (attributs = par session).
- Pas teste : telephone, 2 joueurs, chance (DRINK MASTER / Luck) mesuree sur beaucoup de fruits.
