# Systeme : Ameliorations du joueur (bouton UPGRADE)

**Statut :** passe en Robux le 2026-11-20 (pas encore teste dans Studio ; produits Roblox pas crees)
**Derniere mise a jour :** 2026-11-20

## Role

Bouton vert **UPGRADE** en bas au centre de l'ecran. Il ouvre le menu
"Upgrades" : le joueur achete **5 fois maximum : les 3 premiers achats avec l'argent du jeu, les 2 suivants en Robux (9 R$ chacun)** de la **vitesse de marche**, plus de **fruits sur
son plateau** et plus de **jus portes**. Ces niveaux suivent le joueur partout (tous les etages),
contrairement aux ameliorations des machines (`ameliorations-employes.md`, une serie par etage).

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/shared/Config/PlayerUpgrades.luau` | partage | Liste des 3 ameliorations, effets, prix Robux, productId, messages |
| `src/server/Services/PlayerUpgradeService.luau` | serveur | Demande d'achat (remote) -> fenetre Robux, recu (ReceiptService), seul a ecrire `Data.PlayerUpgrades`, vitesse du Humanoid, attributs ; premier achat de vitesse gratuit une fois (2026-11-22, tutoriel : `Data.FreeSpeedUsed`, attribut `FreeSpeed`, "FREE" dans le menu) |
| `src/server/Services/ProductionService.luau` | serveur | Lit les capacites (`PlayerUpgradeService.GetValue`) au lieu de `Gameplay.CarryCapacity` / `JuiceCarryCapacity` |
| `src/client/Controllers/UpgradeMenuController.luau` | client | Affiche le bouton UPGRADE du HUD et remplit le menu |
| `src/gui/HUD.rbxm` / `src/gui/ShopGUI.rbxm` | client | Bouton `Canvas.Buttons.UpgradeButton` et menu `MenuFrames.Upgrade` du pack (inchanges, caches/remplis par code) |

## Fonctionnement

- Le bouton UPGRADE du pack (`Canvas.Buttons.UpgradeButton`, cache dans le `.rbxm`) est rendu
  visible par `UpgradeMenuController`, sorti de la colonne Shop / Index (trop etroite : il debordait
  de l'ecran et cachait "Index") et pose en bas au centre (`HUD_BUTTON_*`). Attribut `MenuName` =
  "Upgrade" : `MenuController` le relie au menu. Il descend hors de l'ecran quand un menu est ouvert.
- Menu : une ligne par amelioration, copie de la ligne "Speed" du pack : icone avec "Lv 2" jaune
  dessus, nom, "18 → 20 speed" en vert, bouton vert avec le prix ("MAX" au dernier niveau). Les
  3 lignes tiennent sans defiler (rapport 5.2), marge de 20 px en haut ; le bas de la liste passe
  sous le bord epais de la fenetre, donc le reste fait le meme espace visible en bas. Nom et effet = `PackStyle.label` crees par code :
  les textes du pack repassaient en taille fixe 14 apres l'ouverture (cause non trouvee). Bouton violet Robux cache. Icones : chaussure
  (vitesse), pomme 3D (plateau de fruits), potion bleue (jus).
- Retouches du modele du pack faites par code : zone de defilement 5.5 fois trop haute (lignes
  perdues en bas) remise en automatique ; texte entre l'icone et le prix elargi (il etait minuscule) ;
  marge du bas du bouton prix retiree (elle decalait le liseré blanc, retour utilisateur).
- Sur l'icone : "Lv 0/5" a "Lv 5/5" (achats faits / possibles), en jaune.
- Bouton de prix : **vert** "$40" / "$140" / "$490" pour les 3 premiers achats (argent du jeu), puis **violet** avec l'icone
  Robux et "9" (`PackStyle.priceRow`), "MAX" au bout. Couleur changee par `setButtonColors`.
- Clic -> remote `BuyPlayerUpgrade` -> le serveur verifie (id, delai, niveau < max). Niveaux 1 a 3 :
  `MoneyService.TrySpend(PlayerUpgrades.GetCashPrice)` ("Not enough money!" sinon). Ensuite il ouvre la
  fenetre d'achat du Developer Product (`productId` 0 : message "Robux upgrades: coming soon!").
  A la reception du recu (`ReceiptService`), `DataService.GrantPurchaseOnce` donne +1 niveau une
  seule fois par achat. Recu deja au max (2026-11-23) : +1 niveau a une autre amelioration du joueur pas au max ; tout au max : argent = `Upgrades.RobuxRefundFloorShare` x prochain etage + message (jamais rien). Le client ne connait le
  resultat que par l'attribut joueur `PUp_<id>` : la ligne se met a jour. Si le niveau MONTE et
  que le menu est ouvert : effet "c'est paye" (son "Cute level up", rebond de la
  ligne, eclair clair, "-$40" rouge si paye en argent, "LEVEL UP!" / "MAXED!" jaune, etincelles
  autour de l'icone, "Lv" qui grossit en vert, effet en jaune). Textes et etincelles dans le
  calque `UpgradeBuyFx` (ScreenGui au-dessus de ShopGUI). Un niveau qui baisse : affichage seul. Pas assez d'argent (achats 1 a 3) : message "Not enough money!" du serveur, plus de bouton rouge.
- Effets :
  - `WalkSpeed` : `Humanoid.WalkSpeed` pose par le serveur a chaque apparition et apres l'achat ;
    **boost route** : sur la route et les trottoirs (pieces `Asphalt`, `Sidewalk`, `Curb` de
    `Workspace.Map.Road`, liste `Gameplay.RoadPartNames`), vitesse x3.5 (`Gameplay.RoadSpeedMultiplier`). Le serveur verifie la position toutes les 0.1 s
    (`RoadCheckSeconds`, jusqu'a `RoadMaxHeight` = 8 studs au-dessus pour les sauts) ;
    ordre : niveau x route, puis plafond `Gameplay.MaxWalkSpeed` (400). Le pass Robux "Waiter
    Speed x10" n'accelere plus le joueur depuis le 2026-11-20 (il accelere le Waiter, `pads-robux.md`) ;
  - `FruitCarry` : limite du plateau (ramassage, "Pick All" de test) + attribut `InvMax` ("12/25") ;
  - `JuiceCarry` : limite des jus pris au pad Take Juices + attribut `HandMax`.

## Remotes

| Nom | Sens | Arguments | Verifications serveur |
|---|---|---|---|
| `BuyPlayerUpgrade` | client -> serveur | `id` (chaine) | id connu, sauvegarde chargee, delai 0.5 s, niveau < max ; niveaux 1-3 : argent (`TrySpend`, prix de la config) ; sinon `PromptProductPurchase` (le niveau n'est donne qu'au recu) |

## Donnees sauvegardees

- `Data.PlayerUpgrades = { WalkSpeed = 1, FruitCarry = 1, JuiceCarry = 1 }` (niveau 1 = profil neuf).
- Achats Robux : `Data.PurchaseIds` (deja existant, via `GrantPurchaseOnce`).
- Max passe de 9 a 6 le 2026-11-20 : un ancien profil au niveau 7-9 est ramene a 6 par `sanitize`
  (comptes de test seulement).
- Ajoute le 2026-11-20 **sans migration** (pas de changement de `SchemaVersion`) : `Reconcile`
  pose la valeur par defaut pour les anciens profils ; `sanitize` garde seulement les cles connues,
  entiers entre 1 et `maxLevel`.
- Garde au rebirth (decision de la session Rebirth du 2026-11-20).

## Configuration

`Config/PlayerUpgrades.luau` (effets A VALIDER en jouant) :

- Prix : achats 1 a 3 `cashPrices` en argent (Speed 40 / 140 / 490 $, Fruit Tray et Juice Tray
  30 / 105 / 370 $) ; achats 4 et 5 : `RobuxPrice = 9` R$ (18 R$ par amelioration). Niveau 1 -> 6.
- Un Developer Product par amelioration (`productId`, **0 = a creer** sur le site Roblox, prix 9 R$).

| Id | Effet niv. 1 | + par niveau | Max (niv. 6) |
|---|---|---|---|
| WalkSpeed | 20.24 (16 x 1.15 x 1.1, demandes du 2026-11-20) | +3 | 35.24 |
| FruitCarry | 20 | +8 | 60 |
| JuiceCarry | 18 | +5 | 43 |

- `FruitCarry` ne doit pas depasser 60 : `TrayController.MAX_FRUITS` (fruits dessines sur le plateau).
- Le menu arrondit la vitesse a l'affichage (20, 23, 26...).

## Problemes connus / a faire

- Teste en playtest (2026-11-20, PC) : bouton en bas au centre, cache pendant Welcome Back, menu
  ouvert, achat Speed 1 -> 2 (vitesse 16 -> 18, 40 $ retires, prix suivant 140 $), liseré blanc
  regulier une fois la marge retiree (essai en direct).
- 2e playtest (2026-11-20) : "Lv" jaune sur l'icone, textes lisibles, 3 lignes entieres ; achat
  Fruit Tray 1 -> 2 (InvMax 20 -> 25) et Juice Tray 1 -> 2 (HandMax 18 -> 21) ; niveaux gardes apres
  redemarrage du playtest (sauvegarde).
- **Pas verifie** : ramasser vraiment 25 fruits / prendre 21 jus en jeu, bouton rouge et "Not
  enough money!" (compte de test a l'argent max), "MAX" au niveau 9, telephone.
- Pas d'icone dans l'en-tete du menu (l'icone `assets/icons/upgrade_arrow.png` n'est pas en ligne).
- **A faire par l'utilisateur** : creer 3 Developer Products a 9 R$ (Speed, Fruit Tray, Juice Tray)
  et mettre leurs ids dans `productId`. Tant que c'est 0 : "coming soon".
- Passage en Robux (2026-11-20) **pas teste dans Studio** : bouton violet, "MAX", fenetre d'achat,
  recu (tester avec un vrai produit : en Studio l'achat est simule, sans Robux).
- Pile de 43 jus sur la tete pas regardee en jeu.
