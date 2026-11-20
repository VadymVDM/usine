# Systeme : Achats Robux (boutique, offres limitees, passes)

**Statut :** en cours (effets testes en Studio avec des recus simules le 2026-11-20 ; produits et passes pas encore crees sur Roblox)
**Derniere mise a jour :** 2026-11-20

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
| `src/client/Controllers/BoostHudController.luau` | client | Potions des boosts actifs (x2 + temps) au-dessus de l'argent ; tag "[VIP]" dans le chat |
| `src/client/Controllers/ShopController.luau` | client | Boutons d'achat -> `ShopBuy` ; montant des packs (attribut `Cash_<cle>`) |
| `src/client/Controllers/OffersController.luau` | client | Bouton Buy -> `ShopBuy` ; montant des offres d'argent (attribut `Cash_<cle>`) |
| `src/shared/Config/Shop.luau` | partage | Prix, ids, recompenses, `PassEffects`, `BoostStats`, messages |

## Fonctionnement

- **Clic d'achat** (boutique ou offre) -> remote `ShopBuy(kind, key, isGift)`. Le serveur verifie,
  note le montant d'argent affiche (garde `Shop.PendingSeconds`) puis ouvre la fenetre Roblox
  (`Lib/PurchasePrompt`, effet d'ecran). `productId` / `passId` = 0 : message "Robux purchases:
  coming soon!". Cadeau : "Gifts: coming soon!" (pas code). Pass deja possede : "You already own this pass!".
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
- **Gains hors ligne** (`CustomerService.GetIncomePerSecond`) : passes compris, boosts temporaires NON.
- **Montants d'argent** (packs et offres) : base = le plus grand de (gains reels des dernieres minutes,
  panneaux MONEY / HOUR) et (gains theoriques des etages automatises). Pack = base x minutes,
  minimum `minFloorShare` x prix du prochain etage. Offre = base x minutes, plafonne a `floorShare`
  x prix du prochain etage, minimum `minAmount` (Starter Pack : $1K). Le serveur publie les montants
  dans les attributs joueur `Cash_<cle>` (toutes les `Gameplay.IncomeAttributeSeconds`) ; le client
  les affiche. Le recu donne le montant affiche au clic (s'il date de moins de 2 min), sinon recalcule.
- **Autres passes** : AutoCollect (CustomerService), Instant Sell (PassPadService + CustomerService), Waiter Speed x10 et
  Billboard (PassPadService), Thief (ThiefService), Rebirth Master (RebirthService) : `ShopBuy` ouvre
  seulement leur fenetre ; leur service donne l'effet. x2 gains hors ligne : OfflineService.

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

## Configuration

`src/shared/Config/Shop.luau` : prix, `productId` / `passId`, `rewards` des offres, `minFloorShare`
des packs [A VALIDER : 0.25 / 0.5 / 1 / 2.5 prix du prochain etage], `PassEffects`,
`BoostMaxSeconds`, `PendingSeconds`, `ReceiptWaitSeconds`, `BuyCooldownSeconds`, `Messages`.

## Tests (Studio)

```
game.ServerStorage.Debug.Call:Invoke("Shop", "Get", "<Nom>")
game.ServerStorage.Debug.Call:Invoke("Shop", "Grant", "<Nom>", "Boost", "Money_15", "id-optionnel")
game.ServerStorage.Debug.Call:Invoke("Shop", "Grant", "<Nom>", "CashPack" | "Offer", "Cash5m" | "OfferStarter")
game.ServerStorage.Debug.Call:Invoke("Shop", "Pass", "<Nom>", "Cash3x", true)
game.ServerStorage.Debug.Call:Invoke("Shop", "ClearBoosts", "<Nom>")
game.ServerStorage.Debug.Call:Invoke("Shop", "ClearOffers", "<Nom>") -- oublie le Starter Pack achete (pour le retester)
```

## Problemes connus / a faire

- Creer les produits et passes sur Roblox, remplir les ids dans `Shop.luau`. Aucun vrai achat teste.
- Cadeaux (bouton cadeau de la boutique) : pas codes, message "coming soon".
- La boutique ne montre pas encore "OWNED" sur un pass possede (le serveur refuse le 2e achat).
- Montant minimum des packs (`minFloorShare`) a valider par l'utilisateur.
- Si un pass est cree plus tard, verifier qu'aucun ancien attribut de test ne reste (attributs = par session).
- Pas teste : telephone, 2 joueurs, chance (DRINK MASTER / Luck) mesuree sur beaucoup de fruits.
