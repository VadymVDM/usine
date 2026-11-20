# Systeme : Rebirth

**Statut :** en cours (code et teste en playtest Studio a 1 joueur le 2026-11-20 ; produits Robux pas crees)
**Derniere mise a jour :** 2026-11-20

## Role

Quand le joueur a les **10 etages**, il peut **renaitre** dans la salle du Rebirth (annexe, ancien
bar a cocktails) : il perd son argent, ses etages et leurs ameliorations, et gagne un
**multiplicateur d'argent permanent** (x2, x3, x4...) sur toutes ses ventes de jus. Il recommence
plus vite. Regles de jeu : `game-design.md` (section Rebirth).

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/shared/Config/Rebirth.luau` | partage | Condition, prix, multiplicateur, paliers Robux "keep your cash", textes |
| `src/server/Services/RebirthService.luau` | serveur | Remote `RebirthRequest`, verifications, rebirth, recu Robux, pass Rebirth Master, nametag |
| `src/server/Lib/NameTag.luau` | serveur | Nametag au-dessus de la tete : pseudo + "Rebirth N", vu seulement par les autres |
| `src/client/Controllers/RebirthController.luau` | client | Menu Rebirth du pack (ShopGUI.MenuFrames.Rebirth) rempli par code, ouverture par E, fete du rebirth |
| `src/server/Services/FloorService.luau` | serveur | `ResetForRebirth` (tour a 1 etage, ascenseur a 0, joueur ramene au depart), `SetNewFloorLevels`, salle du Rebirth (prompt, panneau "???" -> "REBIRTH") |
| `src/server/Services/CustomerService.luau` | serveur | Multiplicateur applique au prix de chaque jus vendu et a la production "en nombres" ; `CollectPile` |
| `src/server/Services/ProductionService.luau` | serveur | `ClearCarried` : vide le plateau de fruits et les jus portes |
| `src/server/Services/DataService.luau` | serveur | Champs `KeptTrees`, `PurchaseIds` ; `GrantPurchaseOnce` (achat Robux applique une seule fois) |
| `src/server/Services/MoneyService.luau` | serveur | `SyncLeaderstats` (colonne Rebirths du classement) |
| `src/server/Services/AdminService.luau` + `src/client/Controllers/AdminController.luau` | les deux | Bouton de test "+1 Rebirth" |
| `src/server/Services/DebugService.luau` | serveur | `Debug.Call:Invoke("Rebirth", "Get" / "Do" / "Set" / "Master", nom, ...)` (Studio) |

## Fonctionnement

Cote joueur :

1. La salle du Rebirth est visible des le debut (vitre rouge "Reach Floor 10", panneau "???").
2. A l'achat de l'etage 10, la vitre s'ouvre et le panneau devient **REBIRTH**. E sur la machine
   doree ("Rebirth / Open") ouvre le **menu Rebirth**.
3. Le menu montre : **Now** "x1 Cash / Rebirth 0" -> **After** "x2 Cash / Rebirth 1" (texte
   colore + icone : billets verts, fleche Rebirth or ; plus des boutons du pack depuis le retour
   utilisateur "on dirait des boutons") ; une barre "argent / prix" ("$4.2B / $10B") ;
   "Resets your cash, floors and upgrades!".
4. Bouton vert **Rebirth** : 1er clic = "Sure?" (3 s), 2e clic = rebirth. S'il manque de l'argent,
   le serveur repond "Not enough money!".
5. Bouton violet **KEEP CASH** + [logo Robux] prix : rebirth tout de suite, sans payer le prix et
   en gardant tout son argent (produit Robux, pas encore cree : "coming soon").
6. Rebirth fait : flash blanc, **REBIRTH!** + "x2 CASH", confettis, feux d'artifice, son ; le joueur
   est ramene au point de depart de l'etage 1 (la vitre de la salle se referme). Message a tous les
   autres joueurs : "<Nom> reached Rebirth 2!".
7. **Nametag** (demande utilisateur du 2026-11-20) : au-dessus de la tete de chaque joueur, son
   pseudo (DisplayName) et, des le 1er rebirth, "Rebirth N" en or dessous. On voit celui des autres,
   jamais le sien (`BillboardGui.PlayerToHideFrom`), comme le nom de Roblox, qui est cache
   (`Humanoid.DisplayDistanceType = None`) pour ne pas avoir deux noms. `Lib/NameTag` (reutilisable
   pour un futur tag VIP), pose par RebirthService a chaque apparition et apres un rebirth.

Cote code :

- `RebirthRequest("Rebirth")` -> `RebirthService` : sauvegarde chargee, `RequiredFloors` etages
  (sauvegarde ET tour construite), joueur a moins de `ReachDistance` de la machine de SA base,
  delai `RequestCooldown`. Le tas d'argent de l'etage 1 est encaisse d'abord (`CollectPile`), puis
  argent >= `Rebirth.Price(rebirths)`.
- Rebirth (`performRebirth`) : d'abord les donnees (niveaux d'arbre notes dans `KeptTrees`, tout
  l'argent retire, `Rebirths + 1`), puis le monde dans un `pcall` : `ClearCarried`,
  `FloorService.ResetForRebirth` (Data.Floors = 1 etage neuf, TowerUpgrades a 0, tour arretee et
  relancee comme `SetFloorCount` : comptoir, tas d'argent, arbre, mixeurs, employes repartent a
  zero), attribut joueur `Rebirths`, leaderstats, titre, messages.
- **On perd** : argent, etages 2-10, ameliorations et employes des etages, niveaux de l'arbre,
  ascenseur, fruits et jus portes, contenu des
  machines. **On garde** : Index (`DiscoveredFruits`, `ClaimedFruits`), menu Upgrade
  (`PlayerUpgrades` : vitesse, plateaux ; decide le 2026-11-20 avec la session du menu Upgrade),
  reglages, statistiques (`JuicesSold`, `TimePlayed`), passes Robux, dons.
- **Multiplicateur** : `Rebirth.Multiplier(rebirths)` = 1 + `MultiplierPerRebirth` x rebirths.
  `CustomerService` le lit dans la sauvegarde (pas de require de RebirthService) : prix de chaque jus
  vendu (le "+$X" des clients le montre deja multiplie) et `incomeOf` (etages "en nombres",
  `IncomePerSecond` des offres, futurs gains hors ligne). Les recompenses CLAIM de l'Index ne sont
  pas multipliees.
- **"Keep cash"** (`RebirthRequest("KeepCash")`) : memes verifications sauf l'argent ; le serveur
  choisit le palier (`Rebirth.KeepCashProduct(rebirths)`) et ouvre la fenetre d'achat. Le rebirth
  est fait a la reception du paiement (`ReceiptService` -> `onKeepCashReceipt` ->
  `DataService.GrantPurchaseOnce`) : PurchaseId note dans la sauvegarde, recu "donne" seulement
  quand la sauvegarde qui le contient est ecrite. Le paiement est fait : le rebirth est donne meme si
  le joueur n'a plus ses 10 etages au moment du recu (rare).
- **Rebirth Master** (pass `Shop.Passes` "RebirthMaster", passId 0 = pas cree) : attribut joueur
  `RebirthMaster`. `KeptTrees[n]` = plus haut niveau d'arbre de l'etage n avant un rebirth (note
  pour tout le monde, a chaque rebirth). Avec le pass, un etage neuf (etage 1 du rebirth, ou etage
  rachete) demarre avec cet arbre (`FloorService.SetNewFloorLevels`). Acheter le pass plus tard
  rend donc aussi les anciens arbres.
- Client : `RebirthController` remplit le menu du pack (colonnes Before/After, barre `ProgressBar`,
  `Notification`, `RebirthButton`, `SkipButton` = keep cash), ouvre le menu sur le prompt
  `RebirthPrompt` de SA base, et fait la fete quand l'attribut `Rebirths` monte (pas au chargement).

## Remotes

| Nom | Sens | Arguments | Verifications serveur |
|---|---|---|---|
| `RebirthRequest` | client -> serveur | (action) "Rebirth" ou "KeepCash" | action connue (sinon ignore), delai `RequestCooldown` (1 s), sauvegarde chargee, 10 etages (sauvegarde et tour), distance a la machine de SA base (`ReachDistance` 30), argent >= prix (calcule par le serveur) pour "Rebirth". Le client n'envoie ni prix ni produit |

## Donnees sauvegardees

| Champ | Type | Defaut | Proprietaire |
|---|---|---|---|
| `Rebirths` | entier 0..`GameConfig.MaxRebirths` | 0 | RebirthService (existait deja) |
| `KeptTrees` | liste d'entiers (niveau Tree par etage, sans trou, max 10 cases) | `{}` | RebirthService (ajoute le 2026-11-20) |
| `PurchaseIds` | liste de chaines (50 derniers achats Robux appliques) | `{}` | DataService.GrantPurchaseOnce (ajoute le 2026-11-20, servira a tous les produits Robux) |

Champs ajoutes sans migration (Reconcile les ajoute aux anciens profils, `sanitize` les nettoie) ;
`SchemaVersion` reste 4. Le rebirth reecrit aussi `Money`, `Floors` et `TowerUpgrades`.

## Configuration

`src/shared/Config/Rebirth.luau` (prix et multiplicateur valides par l'utilisateur le 2026-11-20 ;
paliers Robux encore A VALIDER) :

- `RequiredFloors` = `Floors.MaxFloors` (10).
- Prix : `BasePrice` 10B x (1 + `PriceStep` 1 x rebirths) -> 10B, 20B, 30B... (plafond `MaxMoney`).
  Calcul : l'etage 10 coute 1.95B (~12 min de gains) ; etage 10 ameliore = tour ~x5 -> 10B en
  ~12-15 min. Le multiplicateur monte comme le prix : la derniere marche dure a peu pres pareil, les
  etages vont de plus en plus vite.
- `MultiplierPerRebirth` 1 -> x2, x3, x4...
- `KeepCashProducts` : 49 R$ (0-2 rebirths), 99 (3-9), 199 (10-24), 299 (25+), `productId` 0.
- `RequestCooldown` 1 s, `ReachDistance` 30, `ConfirmSeconds` 3, `ReceiptWaitSeconds` 10.
- Nametag : `TitleColor` (or), `NameTagWidth` 7 / `NameTagHeight` 1.8 / `NameTagLift` 2.4 studs,
  `NameTagMaxDistance` 100.
- Textes du menu / messages : `Rebirth.Texts`, `Rebirth.Messages`. Salle : `Floors.RebirthRoomTitle`
  ("???"), `Floors.RebirthRoomOpenTitle` ("REBIRTH"), `Floors.PromptRebirthObject` / `Action`.

## Problemes connus / a faire

- Produits Robux "keep cash" et pass Rebirth Master **pas crees** (prix a valider) : le bouton
  violet dit "coming soon". Un tricheur peut ouvrir lui-meme l'achat d'un palier moins cher (le
  client peut demander n'importe quel produit) : il paie quand meme en Robux, accepte.
- Option "Rebirth Master : rebirth 50 % moins cher" pas faite (decision ouverte).
- Pas de bouton Rebirth dans le HUD (il faut aller dans la salle) ; pas de badge "x2" a cote de
  l'argent ; l'arbre ne change pas de couleur avec les rebirths (idee du game design) : a decider.
- Guidage au premier rebirth (first-session.md) : pas fait (phase 2).
- Teste en playtest Studio a 1 joueur (2026-11-20) : menu rempli, "Sure?" puis rebirth au vrai
  clic, fete, sauvegarde apres rebirth (argent 0, 1 etage + etage 2 ferme, ascenseur 0, Rebirths 1,
  leaderstats, vitre refermee, panneau "???", mains vides), vente d'un jus x2 (pomme 5 -> 10),
  refus "Reach Floor 10 first!" / "Go to the Rebirth machine!" / "Not enough money!" / "coming
  soon", delai 1 s, arguments bidon ignores, Rebirth Master (etages 2-3 rachetes avec arbre 10),
  nametag (pseudo seul a 0, "Rebirth 3", cache pour soi, nom Roblox cache).
- Pas teste : 2 joueurs (nametag et message vus par un autre joueur), telephone (taille du menu),
  vrai achat Robux (`GrantPurchaseOnce` jamais execute), `CollectPile` (le tas etait vide au moment
  du test).
