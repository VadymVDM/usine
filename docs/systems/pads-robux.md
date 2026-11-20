# Systeme : Pads Robux "Waiter Speed x10", "Billboard" et "Instant Sell"

**Statut :** en cours (teste en playtest Studio PC le 2026-11-20 avec les attributs poses a la main ;
passes pas crees sur Roblox, vrai achat pas teste)
**Derniere mise a jour :** 2026-11-20

## Role

Deux pads violets (style commun `Util/RobuxPad`, comme Auto Collect) qui vendent un Game Pass quand
on marche dessus :

- **Waiter Speed x10** (149 R$ A VALIDER, nomme "Speed x10" avant le 2026-11-20) : a cote du pad Take Juices, sur chaque etage. Il remplace le
  pad Auto Sell (demande du 2026-11-20 : "le truc juste a cote de prendre les boissons, tu fais
  speed fois 10"). Effet (depuis le 2026-11-20, demande "Oui, le serveur x10") : le **Waiter**
  (employe serveur) va x10 plus vite, sur tous les etages. Le joueur n'est plus accelere.
- **Billboard** (99 R$, comme la capture de reference) : dehors, dans la cour de l'etage 1, a cote du
  panneau FRESH JUICE!. Etiquette "Billboard / 2X Sell Price / R$ 99". Effet : prix de vente des jus x2.

- **Instant Sell** (199 R$ A VALIDER, 2026-11-21, ancien pass "Auto Sell") : pad violet juste a
  droite du pad Drop Juices, sur chaque etage (`Counter.InstantSellPad`, x 64.5-70.5, z 20-26).
  Effet (demande du 2026-11-21 : "quand tu deposes au comptoir, t'attends pas les clients, ca vend
  directement ; c'est pas directement du mixeur") : les jus poses par le joueur sont vendus des que
  l'animation de depot est finie (CustomerService, voir `clients.md`). Attribut joueur `InstantSell`.
  L'ancien Auto Sell (jus de la table -> comptoir tout seuls, `AutoSellService`) est supprime ; il
  ne compte plus pour "etage automatise" (Lib/FloorIncome).

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/PassPadService.luau` | serveur | Pads `Machines.SpeedBoost.Pad` / `Machines.Billboard.Pad` : contact, fenetre d'achat, possession (attributs joueur `SpeedBoost` / `Billboard`), etiquettes "R$ x" / "ACTIVE" |
| `src/server/Services/WorkerService.luau` | serveur | Effet Waiter Speed x10 (`applyStats` : marche et pauses du Waiter), remis a jour quand l'attribut change |
| `src/server/Lib/FloorIncome.luau` | serveur | Debit "en nombres" du Waiter x10 avec le pass (etages ou le joueur n'est pas) |
| `src/server/Services/CustomerService.luau` | serveur | Effet Billboard : `sellMultiplier` (rebirth x Billboard) sur les ventes dessinees et en nombres |
| `src/client/Controllers/HoverInfoController.luau` | client | "Sells for $X" tient compte du x2 |
| `src/shared/Util/RobuxPad.luau` | partage | Style du pad (ligne jaune optionnelle "2X Sell Price"), `SetPrice` |
| `src/shared/Config/Shop.luau` | partage | Passes `SpeedBoost`, `Billboard`, `InstantSell` (prix, `passId = 0`, cartes de la boutique) |
| `tools/build-map/02d-base-counter.luau` | Studio | Pad `Counter.InstantSellPad` (copie du pad Auto Collect deplacee) |
| `src/shared/Config/Gameplay.luau` | partage | `WaiterSpeedPassMultiplier`, `BillboardSellMultiplier`, messages |
| `tools/build-map/02e-base-machines.luau` | Studio | Dessine les deux pads dans `FloorTemplate.Machines` (Billboard dans `OnlyGround`) |

## Fonctionnement

- **Waiter Speed x10** : `FloorTemplate.Machines.SpeedBoost` (x 12, z 70), a la meme place que le pad vert
  du Waiter. Pieces `LookId = "Waiter"`, `LookLevel = 1` : invisible tant que le Waiter de l'etage
  n'est pas embauche, puis apparait en fondu (LevelLookController). Le serveur ignore le pad tant
  que l'attribut d'etage `Lv_Waiter` < 1 ; juste apres l'embauche, il faut descendre et remonter du
  pad pour ouvrir l'achat (pas de fenetre qui saute au visage).
- **Billboard** : `FloorTemplate.Machines.OnlyGround.Billboard` (pad centre x 89.5, z 8.5, sol 0.3)
  -> `Machines.Billboard` de l'etage 1 seulement. Toujours visible.
- Contact (serveur, `Gameplay.ContactCheckSeconds`) : on teste les pads de TOUS les etages du joueur
  (seulement les siens). A l'arrivee sur un pad : pass deja pris -> message "... is active!" ;
  `passId > 0` -> fenetre d'achat Roblox (`Lib/PurchasePrompt.GamePass`, effet d'ecran) ; sinon
  "Robux purchases: coming soon!".
- Possession : `UserOwnsGamePassAsync` a l'arrivee + `PromptGamePassPurchaseFinished` -> attribut
  joueur pose par le serveur. Le client ne peut pas le poser (un attribut change cote client ne
  remonte pas au serveur).
- Waiter avec le pass : vitesse `WaiterBaseSpeed` (0.5) x 10 = 5 -> marche 7.5 x 10 = 75 studs/s
  (comme `EmployeeWalkSpeed` x 5), pauses / 5 au lieu de x2. Hors etage : debit Waiter
  (`WaiterCarry / WaiterTripSeconds`) x10, puis le plus lent des maillons limite (souvent les clients).
- Prix de vente = valeur du fruit x rebirth x 2 (Billboard). `IncomePerSecond`, MONEY / HOUR et la
  production "en nombres" des autres etages en tiennent compte.

## Remotes

Aucun nouveau remote : le serveur teste lui-meme la position du joueur (pas de PadEnter pour ces
pads). Notifications par `NotifyService`.

## Donnees sauvegardees

Aucune : Roblox garde les passes.

## Configuration

`Config/Shop.Passes` (prix, `passId`), `Config/Gameplay` (`WaiterSpeedPassMultiplier = 10`,
`BillboardSellMultiplier = 2`, `Messages.SpeedBoostOn`, `Messages.BillboardOn`).

Tests Studio (serveur) : `player:SetAttribute("SpeedBoost", true)` / `player:SetAttribute("Billboard", true)` /
`player:SetAttribute("InstantSell", true)` (ou panneau admin, Passes).

Pads dans `Counter` (Instant Sell) : champ `counterPad` de `PADS` dans PassPadService.

## Problemes connus / a faire

- Instant Sell (2026-11-21) : pas teste en jeu ; les etiquettes "Drop Juices" et "Instant Sell"
  se touchent un peu vues de loin.
- Creer les 3 Game Passes sur Roblox et mettre leurs `passId` (prix a valider).
- Waiter x10 (75 studs/s) : pas vu en jeu. Il peut rater ses marqueurs ou sembler se teleporter ;
  si c'est moche, baisser `WaiterSpeedPassMultiplier`.
- Pas teste : telephone, 2 joueurs, vrai achat.
- Le pass Shop "SPEED MASTER" (2x walk speed, pas code) ne fait plus doublon (Waiter Speed x10 vise le Waiter).
