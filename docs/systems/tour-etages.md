# Systeme : Tour d'etages et escalier

**Statut :** code (lots 0 a 6 faits le 2026-11-20, verifies dans Studio par script) ; en attente du
test en jeu de l'utilisateur. Restent : 2 vrais joueurs, vrai telephone, chiffres A VALIDER.
**Derniere mise a jour :** 2026-11-27 (dernier etage : plus d'escalier ni de lampes, toit sur la cage d'ascenseur)

## Role

Chaque base devient une **tour de 10 etages**, 10 fruits par etage (un par rarete, de Common a
Infinity : regle du 2026-11-20, voir `fruits.md`). Chaque etage est une
copie du meme modele d'usine (arbre, etagere, mixeurs, table a jus, comptoir, argent, employes) et
fonctionne tout seul. On passe d'un etage a l'autre par un **escalier qui part du milieu de
l'usine et monte vers le mur de droite**. Acheter l'etage suivant = ouvrir la vitre rouge en haut
de l'escalier. Decide le 2026-11-19 ; voir aussi `game-design.md` ("La tour d'etages").

## Regle d'or technique : un seul modele d'etage

Pour ne pas etre en galere plus tard, **tous les etages sont le meme modele** (`FloorTemplate`),
copie et monte de 36 studs a chaque fois. Ce qui change d'un etage a l'autre est seulement :

- le numero (les 10 fruits de l'arbre = ligne n du tableau des fruits, la couleur d'accent, le
  panneau ; depuis le 2026-11-20 le panneau ne doit plus dire une rarete, ex. "FLOOR 3") ;
- le cote de l'escalier (voie A ou voie B, un etage sur deux, voir plus bas) ;
- l'etage 1 a en plus la porte d'entree, la cour et les clients de la rue.

Le code ne connait jamais "le rez-de-chaussee" : il recoit un **etage** (`Model`) et y cherche
toujours les memes noms (`Tree`, `Production`, `Counter`, `Machines`, `Boards`, `Markers`,
`Dynamic`). Un etage 11 ajoute plus tard = une ligne de Config, zero code.

## Dimensions (mesurees dans Studio le 2026-11-19)

- Salle d'un etage : x 1 -> 109, z 15 -> 135 (108 x 120), comme aujourd'hui.
- **Hauteur d'un etage : 36 studs** (on garde le "plafond 2 fois plus haut" choisi par
  l'utilisateur). Etage n : sol a `y = 36 * (n - 1)`. Dalle du plafond = sol de l'etage du dessus,
  de y 35 a 36 (relatif a l'etage).
- L'arbre au stade 5 monte a ~34.3 : il passe sous la dalle (35). **Ne jamais grandir l'arbre
  au-dela de 34.5** (sinon il traverse l'etage du dessus).
- Tour complete : 10 x 36 = 360 studs de haut. Espacement des bases (200) : suffisant.

## L'escalier (decide : "commence au milieu, monte vers le mur")

Place : la grande zone vide au milieu-droite de l'usine (verifiee vide dans Studio) : **x 60 -> 109,
z 50 -> 86**, entre la vente et le verger. La zone SALES est raccourcie de z 54 a z 50 (rien
dedans au-dela de z 34). Elle devient la zone **STAIRS** sur
tous les etages (sol de zone + panneau, comme les autres zones). Rien d'autre ne s'y pose.

```
 vu de dessus (route en bas ; +X a gauche vu de la route, comme dans carte-bases.md)

 z=86 +---------------------------------------------------------+ mur de droite (x 109)
      |  allee nord (z 78-86)                                    |
      |  [voie B] x 64 ===marches===> x 100 [palier B x 100-108] |
      |  -------- garde-corps (z 65-70) --------                 |
      |  [voie A] x 64 ===marches===> x 100 [palier A x 100-108] |
      |  allee sud (z 50-57)                                     |
 z=50 +---------------------------------------------------------+
      x=60 (milieu de l'usine)                          x=109 (mur)
```

- 2 voies paralleles de 8 de large : **voie A z 57-65**, **voie B z 70-78**.
- L'escalier qui monte de l'etage n vers n+1 est sur la voie **A si n est impair**, **B si n est
  pair**. Il part du milieu (x 64, sol de l'etage) et monte vers le mur (x 100, +36), puis un
  **palier** x 100-108 colle au mur, qui fait partie de l'etage du dessus.
- Pourquoi 2 voies : au-dessus d'un escalier il faut un **trou** dans la dalle (sinon on se cogne
  la tete). Si tous les escaliers etaient sur la meme voie, le trou de l'etage n+1 tomberait pile
  sur son propre escalier de depart. En alternant, a chaque etage : un trou (ou on arrive) sur une
  voie, l'escalier suivant sur l'autre.
- Parcours du joueur a chaque etage : il arrive au palier contre le mur, fait demi-tour par
  l'allee (sud ou nord), traverse un bout de l'etage (il le voit) et prend l'escalier suivant au
  milieu. Toujours le meme geste, toujours "du milieu vers le mur".
- Pente 45 degres : 24 marches de 1.5 de haut x 1.5 de profondeur (36 de long). Environ 3 s de
  montee. **Collision = une rampe invisible** (WedgePart) sous chaque volee ; les marches visibles
  sont sans collision (le personnage ne bute pas, pas de saut).
- Garde-corps tout autour du trou et entre les voies (pas de chute dans la cage d'escalier).
- Le trou dans la dalle : x 64 -> 100 sur la voie de l'escalier du dessous. Le palier (x 100-108)
  reste plein.
- A retirer / deplacer pour l'escalier : la fenetre du mur de droite en z 56-70 (le palier la
  cache), les panneaux suspendus SALES (z 50) et ORCHARD (z 86) restent hors des voies.

## Etage ferme (le suivant) et achat

- On construit seulement les **etages achetes + le suivant ferme**. Jamais une tour vide de 10.
- Etage suivant ferme : vu de dehors, **la vraie coque de l'etage teintee bleu clair avec un
  contour** (meme regle que les machines a acheter), sans l'interieur (peu de pieces).
- Dedans : l'escalier qui y mene existe deja ; en haut, sur le palier, une **vitre rouge
  transparente** (cadenas, "FLOOR 2 - UNCOMMON", prix), comme les salles fermees. E pour acheter.
- Achat : le serveur verifie (proprietaire, etage suivant, argent, delai) puis l'etage **se
  construit piece par piece** (effet comme les machines) ; "NEW FLOOR!" + son.
- L'ancien systeme `ZoneLocks` (Cocktail Bar / Terrace) devient ce verrou d'etage.

## Ce qui se passe sur les etages ou le joueur n'est pas (important pour le lag)

6 joueurs x 10 etages = 60 etages par serveur. Si chacun avait ses PNJ, ses fruits et ses
clients, le serveur s'effondre. Regle :

- **Le serveur calcule chaque etage avec des nombres** (fruits par seconde, jus, ventes, argent)
  a partir de ses ameliorations et employes. C'est cette meme formule qui sert aux gains hors ligne.
- **Les choses visibles** (fruits qui tombent, employes R6 qui marchent, clients, gobelets) ne
  sont creees **que sur l'etage ou se trouve le proprietaire** (et eventuellement celui juste
  en dessous). Quand il change d'etage, on les retire de l'ancien et on les cree sur le nouveau.
- Un etage pas encore automatise (pas d'employes) ne produit rien quand le joueur n'y est pas :
  ca pousse a embaucher avant de monter.
- Pieces : le modele de base actuel fait **1469 pieces**. Viser **~800 par etage** (decor
  simplifie en haut) ; StreamingEnabled est deja actif (les etages loin du joueur ne sont pas
  envoyes a son telephone).

## Argent des etages

**Change le 2026-11-20 (soir) : un tas d'argent PAR ETAGE** (demande : "a chaque etage, un truc
pour recuperer l'argent comme au premier ; il faut y aller et marcher sur le pad").

- Chaque etage a sa **table a argent** et son **pad Collect Cash** (meme place qu'a l'etage 1 :
  table x 82 -> 92, pad x 83.5 -> 90.5, z 24.5 -> 31.5). Les ventes d'un etage (dessinees ou "en
  nombres" quand le joueur n'y est pas) vont sur le tas de CET etage.
- Pour encaisser, il faut aller sur l'etage et marcher sur son pad (panneau Floors = teleport).
- Le pad Robux **Auto Collect** est sur chaque etage (depuis le 2026-11-21, avant : etage 1
  seulement) et vaut pour toute la tour : avec le pass, l'argent de tous les etages (ventes dessinees
  et "en nombres") va directement au joueur. A l'achat, tous les tas sont encaisses.
- Pads payants par etage : Auto Collect, Instant Sell, Waiter Speed x10 sur tous les etages ;
  Billboard seulement a l'etage 1 (dans la cour, choix de l'utilisateur le 2026-11-21).
- Rebirth : `CustomerService.CollectPile` encaisse les tas de tous les etages avant le calcul.
- Avant (decision du matin du 2026-11-20) : un seul tas, a l'etage 1, pour toute la tour.

## Clients des etages du haut

- Etage 1 : comme aujourd'hui (la rue, le comptoir dans la fenetre de la facade).
- Etages 2+ : le comptoir est au meme endroit, il donne sur un **balcon** (z 0 -> 14, au-dessus de
  la cour). Decide le 2026-11-20 : les clients arrivent par un **ascenseur vitre exterieur** sur le cote ouest
  de la tour (la place de l'ancien bar a cocktails et de la terrasse, x -46 -> 0, maintenant libre) :
  on les voit monter de la rue, ils sortent sur le balcon, achetent, repartent. Purement visuel
  (le serveur decide des ventes), et seulement sur l'etage ou est le joueur.

## Annexe ouest : terrasse et ancien bar a cocktails (decide le 2026-11-20)

L'annexe (x -46 -> 0) n'existe qu'au rez-de-chaussee : la tour ne monte que sur la grande salle.

**Terrasse -> hall de l'ascenseur des clients.**
- Pas d'achat a part : elle **s'ouvre toute seule a l'achat de l'etage 2** (un etage 2 sans
  clients ne vendrait rien). (Le panneau "Opens with Floor 2" a ete retire le 2026-11-23.) On voit
  deja la cage vide de l'ascenseur le long du mur ouest de la tour.
- A l'achat de l'etage 2, dans la meme animation : l'etage se construit, l'ascenseur vitre
  apparait, la barriere de la terrasse s'ouvre.
- Ensuite les clients de la rue se repartissent : une partie va au comptoir du rez-de-chaussee,
  l'autre fait la queue sur la terrasse et monte dans l'ascenseur vers les balcons.
- Panneau d'ameliorations **"Elevator"** sur la terrasse (argent du jeu) : **Elevator Speed** et
  **Bigger Cabin**. Effet serveur : **+4 % d'argent par vente et par niveau** pour **tous les
  etages 2+** (depuis le 2026-11-20 ; avant : vitesse des clients, presque toujours sans effet). L'ascenseur lui-meme reste visuel (cabine qui monte plus vite / plus de clients).
  Ces deux niveaux sont globaux (pas par etage) et remis a 0 au rebirth.

**Bar a cocktails -> salle du Rebirth.**
- Garde sa vitre rouge, texte **"Reach Floor 10"**. Dedans, visible des la premiere minute : une
  grande machine / statue doree qui brille (le but a long terme).
- A l'etage 10 achete, la vitre s'ouvre ; le rebirth se fait la (E, confirmation, gros effet).
- Le rebirth lui-meme (multiplicateur, remise a zero) : code le 2026-11-20, voir
  [rebirth.md](rebirth.md). Salle ouverte : panneau "???" -> "REBIRTH", prompt "Rebirth / Open"
  (menu Rebirth). Au rebirth, `FloorService.ResetForRebirth` remet la tour a 1 etage neuf et
  ramene le joueur au point de depart (la vitre se referme).

## Deplacements du joueur

- Il apparait (connexion, mort) sur son **etage le plus haut** : il ne refait pas 9 escaliers.
- Sur chaque palier : un panneau **"Floors"** (E) pour aller directement a un etage achete
  (teleport). L'escalier sert la premiere fois et pour les petits trajets.
- Camera : 36 de plafond laisse de la place a la camera ; a verifier dans la cage d'escalier
  (rampes et dalles avec collision camera normale, garde-corps fins).

## Lumiere

- Aujourd'hui l'usine n'a pas de toit (ciel ouvert, puits de lumiere au-dessus du verger).
- Avec les etages : chaque etage a un plafond (la dalle du dessus) -> les lampes neon existantes
  eclairent. **Seul le dernier etage achete** garde le ciel ouvert. Le dernier etage de la tour
  (10) aura un vrai toit / enseigne.

## Dernier etage de la tour (etage MaxFloors = 10, depuis le 2026-11-27)

Demande utilisateur : "supprimer ce qui sert a aller a l'etage superieur, l'ascenseur s'arrete au
dernier etage". Rien dans le modele `FloorTemplate` ne change, tout se fait a l'assemblage :
- `Config/Floors.Tags(MaxFloors)` ne met plus de tag `StairA/B` : l'escalier qui monte est detruit,
  sa voie garde la dalle pleine (`OnlySolid*`). Nouveaux tags `Top` (n = MaxFloors) / `NotTop`,
  libres pour de futures variantes `OnlyTop` / `OnlyNotTop` dans le modele.
- `Lib/FloorAssembly` (`trimTopFloor`, etage ouvert seulement) : retire `Building.Lamps` et
  `Building.Beams` (poutres du plafond, demande du 2026-11-27 ; ciel ouvert, rien au-dessus) et pose un toit `Building.Elevator.ShaftRoof` sur les 4 poteaux de la cage
  vitree (meme couleur / matiere que les poteaux, debord 0.4, epaisseur 0.6).
- Garde : garde-corps du trou d'arrivee. Les fils des panneaux des mixeurs (`Boards.BlenderSign*.Wire`)
  et les chaines des panneaux de zones (`Zones.*.SignChain`) restent : sans poutres, ils montent
  dans le vide (a decider).
- `FloorAssembly.Build(..., floorsConfig?)` : les apercus Edit (`preview-factory`, `preview-tower`)
  passent une copie fraiche de `Config/Floors` (sinon le cache de require de Studio garde l'ancienne). Pas d'etage 11 ferme (deja le cas : FloorService s'arrete a MaxFloors).

## Modeles dans Studio (lot 1, fait le 2026-11-20)

- `ServerStorage.BaseTemplate` (267 pieces) : ce qui n'existe qu'une fois par base : terrain, cour,
  `Annex` (terrasse fermee + bas de la cage d'ascenseur `ElevatorBase`, salle du Rebirth
  `RebirthRoom`), `Entrance` (panneau du proprietaire, enseigne), `Floors` (vide : les etages y sont
  clones en jeu), `Dynamic`.
- `ServerStorage.FloorTemplate` : UN etage (`Building`, `Stairs`, `Tree`, `Production`, `Counter`,
  `Machines`, `Looks`, `Boards`, `Markers`, `Dynamic`). Pivot = `Origin` (0, 0.5, 0), comme la base.
- **Variantes** : dossiers `Only<Tag>` n'importe ou. Au clonage (`FloorAssembly.Build`), un dossier
  dont le tag est actif disparait et son contenu remonte d'un niveau ; sinon il est detruit. Tags de
  l'etage n (`Config/Floors.Tags`) : `Ground` (n = 1) / `Upper`, `StairA` / `StairB` (voie de
  l'escalier qui monte), `HoleA` / `HoleB` (trou d'arrivee, n >= 2), `SolidA` / `SolidB` (voie sans
  trou : dalle pleine), `Open` / `Closed`.
  - `Building.Walls.OnlyGround` / `OnlyUpper` : mur x 0 avec les portes de l'annexe / avec des fenetres.
  - (`Counter.OnlyGround` retire le 2026-11-21 : le pad `AutoCollectPad` est maintenant sur tous les
    etages, comme la table a argent, `CashPad` et `InstantSellPad`.)
  - `Machines.OnlyGround` : pad Robux `Billboard` de la cour (2026-11-20, `pads-robux.md`).
  - `Markers.OnlyGround.CustomerEntry` (trottoir) / `Markers.OnlyUpper.CustomerEntry` (sortie de
    l'ascenseur sur le balcon).
  - `Building.Balcony.OnlyUpper` (balcon z 0 -> 14, garde-corps, plus de murs invisibles depuis le 2026-11-20 : on peut sauter dans la cour),
    `Building.Elevator.OnlyUpper` (cage vitree x -9 -> -1, z 3 -> 11, ouverte cote balcon).
  - `Stairs.OnlyStairA/B` (escalier), `OnlySolidA/B` (dalle de la voie), `OnlyHoleA/B` (garde-corps
    vitres autour du trou ; `OnlyClosed` : vitre d'achat `BuyGate`
    + murs invisibles autour du trou et au-dessus de la vitre, seulement sur l'etage a acheter depuis le 2026-11-20). Plus de panneaux `FloorsPanel` depuis le 2026-11-20 (selecteur d'etage en haut
    de l'ecran, voir plus bas).
- **Etage ferme** (remplace le 2026-11-20 soir, voir "Retours de test") : ANCIEN : on ne garde que ce qui a l'attribut `Shell = true` (murs, dalle, balcon, cage,
  garde-corps du trou, vitre d'achat ; `Shell = false` exclut un detail), tout est teinte bleu clair
  (`Config/Floors.Closed*`, memes valeurs que les machines a acheter), sans ombre, sauf ce qui a
  `KeepLook = true` (la vitre rouge). Contour : `Highlight` "ClosedGlow" (contour seulement).
- Textes de la vitre d'achat (`FloorName`, `Status`) et prompts E (`PromptAnchor`) : a remplir par
  FloorService (lot 4). Le modele contient "FLOOR 2 - UNCOMMON" / "$?" en exemple.
- **Escalier** (mesure en jeu, R15) : rampe invisible = `WedgePart` decalee de 0.75 vers le bas de
  l'escalier (elle passe au milieu de chaque marche), marches et corps sans collision. Montee de
  l'etage 1 au palier de l'etage 2 en 3.8 s sans aucun saut ; voie B idem.
- **Lumiere** (demande utilisateur du 2026-11-20 : "aussi lumineux dans chaque etage, que le soleil
  passe a travers") : la dalle `Floor` et le balcon n'ont **pas d'ombre** (`05-shadows`) : le soleil
  traverse les etages comme quand l'usine n'avait pas de toit. Les gros objets d'un etage peuvent
  donc ombrer un peu l'etage du dessous (a verifier a l'oeil).
- **Pieces** (apercu du 2026-11-20) : base seule 267, etage 1 : 1149, etage 2+ : 1230, etage
  ferme : 396. Objectif ~800 pas atteint : les gros postes sont les murs (275 : 23 fenetres avec
  cadres), les 4 mixeurs (228), le tapis (78), l'escalier (81), le balcon (49). Voir "Problemes".
- **Apercu dans Studio** : `tools/build-map/preview-tower.luau` (OWNED etages + le suivant ferme,
  dans `Workspace._PreviewBase` a l'emplacement de la Base1). Le retirer apres (REMOVE = true).
- (Le "depliage" transitoire de l'etage 1 dans la base a ete retire au lot 4 : les etages sont dans
  `base.Floors`.)

## En jeu : FloorService et services par etage (lots 3 et 4, 2026-11-20)

- **Une base** : `Floors.Floor1..N` (ouverts) + l'etage suivant ferme. Base libre : Floor1 (niveaux de
  depart) + Floor2 ferme. A l'arrivee d'un joueur charge : ses `#Data.Floors` etages + le suivant
  ferme ; il est teleporte sur son etage le plus haut. A son depart : retour a la base libre (Floor1
  reste, son `Dynamic` est vide ; les etages 2+ sont detruits). Attribut de base `FloorsOwned`.
- **Attributs d'un etage ouvert** : `FloorIndex`, `Closed = false`, `Rarity`, `BuildStamp` (achat :
  le client anime la construction et montre "NEW FLOOR!"), `Lv_<id>`, `CounterJuices`,
  `CustomerSlots`, `IncomePerHour`.
- **Abonnements serveur** (`FloorService`) : `OnFloorAdded(floor, n)` (etage ouvert cree, base libre
  comprise : UpgradeService prepare fantomes et tuiles), `OnFloorStarted(player, floor, n)` /
  `OnFloorStopped` (Tree, Production, Customer, Worker, Upgrade demarrent / arretent l'etage),
  `OnFloorRemoving`. Aussi `GetPlayerFloor(player)` (etage ou il est, d'apres la hauteur de son
  personnage : jamais un numero envoye par le client), `GetFloor`, `GetGround`, `GetOwner`,
  `GetIndex`, `GetBaseOf`, `GetOwnedCount`, `SetFloorCount` (tests, ecrit la sauvegarde).
- **Achat** : prompt E "Floor N / Buy $2.5K" (appui long `BuyHoldSeconds`) sur `Stairs.BuyGate` de
  l'etage ferme. Verifie : proprietaire de la base, `n == #Floors + 1`, distance, delai
  `Floors.BuyCooldown`, argent (`MoneyService.TrySpend`). Puis `table.insert(data.Floors, defaut)`,
  l'etage ouvert remplace la coque, le suivant ferme apparait, message "Floor N unlocked!".
- **Annexe** : etage 2 -> la cabine de l'ascenseur apparait. Plus de vitre rouge
  `Terrace.TerraceGate` ("Opens with Floor 2") depuis le 2026-11-23 (sans utilite ; FloorService la
  detruit si le .rbxl l'a encore). La terrasse n'a plus de cloture, de portail cote rue ni de murs invisibles depuis le
  2026-11-20 : on y passe librement depuis la rue et la cour) ; etage 10 -> `RebirthRoom.RebirthGate` retiree, panneau `RebirthRoom.Sign` "REBIRTH",
  prompt "Rebirth / Open" sur `RebirthRoom.PromptAnchor` -> menu Rebirth (2026-11-20, `rebirth.md`).
- **Niveaux d'un etage neuf** (achat, rebirth, `SetFloorCount`) : `Upgrades.DefaultLevels()`, sauf
  ce que renvoie le resolver `FloorService.SetNewFloorLevels` (RebirthService : arbre garde avec
  Rebirth Master).
- **Arbre** (lot 4b) : etage n = la ligne n (`Fruits.OfFloor`, une rarete de chaque), niveau Tree
  1..10 de l'etage = Luck + vitesse. Voir `fruits.md` > "Dans le code". Pommes de la premiere visite : etage 1 seulement.
- **Argent** : chaque etage a son tas (2026-11-20 soir ; avant : tout sur le tas de l'etage 1).
- **Prix des ameliorations** : x `Floors.UpgradePriceFactor` (5)^(n-1) sur l'etage n (A VALIDER ; 25 avant le lot 4b).
- **Teleport** : StreamingEnabled -> `RequestStreamAroundAsync` avant chaque teleport / apparition
  (sans ca, vu en test : on tombait de l'etage 10 a l'etage 8 a travers des dalles pas encore recues).
- **Client** : `src/client/Util/FloorWatch.luau` (suivi des etages ouverts) ; tous les controleurs
  travaillent par etage (TreeFx, BlenderFx, Inventory, LevelLook, MachineFx, Customer, HandStack, Pad,
  Buy) ; `FloorController` (selecteur d'etage "< Floor N >" en haut de l'ecran a partir de 3 etages :
  depuis le 2026-11-20, sans fond, triangles pleins blancs (image `Icons.FloorArrow`, gris
  transparent au premier / dernier etage), barre dans la bande du haut de Roblox au niveau du bouton
  parametres (`ScreenInsets.None`, y = 0, hauteur 0.11 de l'ecran, rapport 5.6, max 549 x 98 px) ;
  un clic sur une fleche ne joue que le "Click" commun des boutons (son `PadStep` du changement
  d'etage retire le 2026-11-20), "NEW FLOOR!", construction par couches).

## Production en nombres et etage actif (lot 5, 2026-11-20)

- **Etage actif** : `FloorService` regarde toutes les `Floors.ActiveCheckSeconds` (0.4 s) l'etage ou
  est le joueur (hauteur du personnage) : `FloorService.IsLive(floor)`, `GetLiveFloor(player)`,
  `OnLiveFloorChanged(cb(player, old, new))`, attribut de base `ActiveFloor`.
- **Seul l'etage actif est dessine** : l'arbre ne fait tomber des fruits que la (`TreeService`), les
  employes R6 n'existent que la (`WorkerService` les retire / recree au changement d'etage ; ce qu'ils
  portaient est perdu, au plus 6), les clients ne sont dessines que la (`WorldFx "Sale"` seulement pour
  l'etage actif ; client : `CustomerController`). Les fruits au sol, caisses, jus et comptoirs des
  autres etages restent (rien n'est perdu).
- **Production en nombres** (`src/server/Lib/FloorIncome.luau`) : un etage **automatise** (Fruit
  Picker + vendeur (Waiter en argent du jeu ; le pass Auto Sell ne compte plus depuis le 2026-11-21) + operateur du mixeur 1) ou le joueur n'est pas verse
  `debit x valeur moyenne` sur le tas de CET etage (depuis le 2026-11-20 soir ; avant : etage 1) toutes les `Floors.IncomeTickSeconds` (2 s).
  Debit = le plus lent de : arbre, Fruit Picker (`FloorIncome.PickerRate` : fruits portes / (`PickerTripSeconds` 3 + fruits x
  `PickerFruitSeconds` 0.75), x 0.7 x PickerSpeed ; ~0.31 fruit/s au depart, ~1.34 au max), tapis, mixeurs avec
  operateur (cycle = remplissage + trajet sur le tapis + reaction + mixage + `BlendCycleExtraSeconds` 0.5 :
  mesure en playtest le 2026-11-20, bol de 12 au tapis 2.53/s = ~11 s, ~1.1 jus/s ; avant la formule
  oubliait le trajet et donnait 1.46), Waiter (`WaiterCarry` / `WaiterTripSeconds` = 9 / 21, x10 avec le pass Waiter Speed x10), clients. Valeur
  moyenne = fruits de l'etage ponderes par leurs chances (Luck), x bonus de l'ascenseur aux etages 2+
  (+4 % d'argent par niveau, depuis le 2026-11-20). Un etage pas automatise ne produit
  rien sans le joueur. `CustomerService.GetIncomePerSecond(player)` (toute la tour, pour les gains
  hors ligne plus tard) et `DebugIncome(player)` (detail par etage). Chiffres A VALIDER.
- **Panneau ELEVATOR** (sur la cage de l'ascenseur depuis le 2026-11-20, `tools/build-map/02j-base-elevator.luau`) : 2 tuiles (Elevator
  Speed, Bigger Cabin) au style des autres panneaux (`Util/UpgradeTile`) : on CLIQUE la tuile
  (ClickDetector `Tile`, `MouseClick` dans FloorService ; plus de prompt E depuis le 2026-11-20),
  actif des l'etage 2 (portee `Gameplay.TileClickDistance` = 36, 0 si inactif).
  Verifie par `FloorService` (proprietaire, distance, delai, niveau max 25, argent). Ecrit
  `Data.TowerUpgrades`. Effet : +4 % d'argent par vente aux etages 2+ par niveau (`FloorIncome.ElevatorBonus` : ventes
  reelles `CustomerService.sellOne` et en nombres `FloorIncome.Compute`), max x3 (25 + 25 niveaux).
  Prix `Floors.ElevatorUpgrades` (400 x1.75^n, 600 x1.75^n ; avant 2K / 3K x1.6^n), A VALIDER. Attributs de
  base `ElevatorSpeed` / `ElevatorCabin` (le client anime la cabine plus vite / plus remplie).
- **Cabine** : `Annex.ElevatorBase.Cabin` (02j), retiree tant que la tour a 1 etage ; animee cote
  client avec les clients de la terrasse (file en zigzag -> cabine -> balcon).

## Performance (lot 6, mesure dans Studio le 2026-11-20)

Studio sur PC (le serveur et le client tournent sur la meme machine ; memoire de Studio comprise,
donc seules les differences comptent). Battement serveur = duree moyenne / pire d'un Heartbeat.

| Cas | Pieces dans Workspace | Serveur (moy / pire) | Client | Memoire (difference) |
|---|---|---|---|---|
| 1 joueur, 1 etage | 12 500 | 4.2 / 7.2 ms | 60 fps | reference |
| 1 joueur, 10 etages (en haut) | 23 200 | 4.2 / 7.0 ms | 60 fps (pire image 19 ms) | +100 MB |
| 6 bases x 10 etages (5 simulees, decor seul) | 76 600 | 5.0 / 61 ms (pic pendant la construction) | 54 fps (pire image 24 ms) | +660 MB |

- Les 5 bases simulees n'ont que le decor (pas de services) ; avec de vrais joueurs, chaque tour fait
  tourner en plus son etage actif (arbre, employes, clients) et des calculs en nombres (tres legers).
- Un etage = ~1 230 pieces (objectif ~800 pas atteint) ; une tour de 10 etages ~10 700 pieces.
- StreamingEnabled : `StreamingTargetRadius` = 1024 (la carte entiere sur PC) ; sur telephone Roblox
  reduit tout seul selon la memoire. Pistes si besoin : baisser le rayon (~400), alleger les fenetres
  / cadres des etages, mixeurs en MeshPart. A decider avec l'utilisateur.
- **Allegement sans changement a l'ecran (2026-11-20, accord de l'utilisateur)** :
  `tools/build-map/06-no-touch.luau` met `CanTouch = false` sur les 1 080 pieces des modeles (le jeu
  n'utilise jamais Touched : tout passe par la position du joueur). Moins de calculs de contact.
  Baisser le NOMBRE de pieces (~1 230 -> ~800) n'est pas possible sans changement visible : il ne
  reste presque rien a fusionner sans risque (murs deja en grands morceaux, ~3.8 pieces par fenetre ;
  les gros postes sont les fenetres et leurs cadres, les 4 mixeurs, les garde-corps, l'escalier).
  Pistes visibles a decider : moins de fenetres sur les etages du haut, mixeurs en MeshPart.
- Pas mesure : vrai telephone, 6 vrais joueurs (Studio : Test > Clients and Servers, pas pilotable ici).

## Relecture (lot 6)

- **Securite** : achat d'etage (prompt : proprietaire, `n == #Floors + 1`, distance, delai, argent,
  `TrySpend` puis ajout sans attente), `FloorTeleport` (entier, NaN refuse, 1..etages achetes, delai),
  panneau ELEVATOR (proprietaire, etage 2+, distance, delai, niveau max, argent), salle "???"
  (proprietaire, 10 etages), `BuyUpgrade` / pads / `PadEnter` (etage deduit de la position, jamais
  envoye), decouverte et ventes decidees par le serveur. Rien de trouve a corriger.
- **Connexions / nettoyage** : etats par etage retires a `OnFloorStopped` / `OnFloorRemoving`,
  employes retires au changement d'etage, `liveFloor` vide au depart ; client : `FloorWatch.OnRemoved`
  dans chaque controleur. Prompts des etages detruits avec l'etage.

## Code qui suppose un seul etage par base (inventaire du lot 0, 2026-11-20)

A passer "par etage" au lot 3 (le serveur recoit un etage au lieu d'une base) :

- Serveur : `BaseService` (ZoneLocks / LockedZone : a supprimer ; apparition sur `Markers.SpawnPoint`),
  `TreeService` (`base.Tree`, `base.Dynamic`, niveau borne par `Fruits.MaxLuck(rebirths)`),
  `ProductionService` (`base.Production`, `Bins.Bin<index 1..100>`, `base.Dynamic`),
  `CustomerService` (`base.Counter`, `MoneyPile`, markers clients), `WorkerService` (`base.Markers`,
  `base.Machines`, `base.Tree`, `base.Production`, `base.Counter`), `UpgradeService` (`base.Boards`,
  machines, `GetBase(player) ~= base`), `DebugService` (`data.Upgrades.Tree`, `MaxLevel(..., Rebirths)`).
- Partage : `Config/Fruits` (`StartRarities`, `MaxLuck`), `Config/Upgrades` (maxLevel de Tree =
  `Fruits.MaxLuck`), `Config/Map` (`LockedZone*`), `Util/MachineModels` (`base.Machines`,
  `base.Production`).
- Client (cherchent la base par `OwnerUserId` puis un dossier) : `TreeFxController` (`Tree`),
  `BlenderFxController` (`Dynamic`, `Production`), `InventoryController` (`Production.Bins.Bin<index>`),
  `LevelLookController` (`Production`, `Boards`), `MachineFxController` (`Boards`, `Production`),
  `CustomerController` (`Markers`, `Counter`), `HandStackController` (`Dynamic.Counter`),
  `PadController` (pads dans `Production` / `Counter`), `BuyController` (`Machines`),
  `PromptController`. Avec StreamingEnabled : ne jamais supposer qu'un autre etage existe cote client.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/shared/Config/Floors.luau` | partage | **Fait (lot 1)** : hauteur 36, MaxFloors 10, zone STAIRS, voies, `StairLane(n)`, `HoleLane(n)`, `Tags(n, closed)`, couleurs de l'etage ferme, textes. Lot 3 : `Prices` (A VALIDER), `UpgradePriceFactor`, messages, prompts, delais |
| `src/server/Lib/FloorAssembly.luau` | serveur | **Fait (lot 1)** : `Build(template, n, closed, basePivot)` : clone, variantes, coque bleue, place l'etage. |
| `tools/build-map/02a` ... `02h`, `preview-tower` | Studio | **Fait (lot 1)** : BaseTemplate + FloorTemplate, escalier (`02h-floor-stairs`), annexe (`02f-base-annex-markers`) |
| `src/server/Services/FloorService.luau` | serveur | **Fait (lot 4)** : construire / retirer les etages d'une base, achat de l'etage suivant, terrasse / salle "???", etage ou se trouve le joueur, teleport, apparition en haut, outils de test |
| `src/server/Services/BaseService.luau` | serveur | Garde l'attribution des bases ; la base devient un dossier `Floors.Floor1..N` |
| `TreeService`, `ProductionService`, `CustomerService`, `WorkerService`, `UpgradeService` | serveur | **Fait (lot 3)** : travaillent **par etage** (recoivent l'etage). A faire (lot 5) : production en nombres hors de l'etage actif |
| `src/client/Controllers/FloorController.luau` | client | **Fait (lot 4)** : selecteur d'etage en haut de l'ecran (fleches, a partir de 3 etages ; remplace la fenetre FLOORS le 2026-11-20), effet de construction, "NEW FLOOR!" |
| `src/client/Util/FloorWatch.luau` | client | **Fait (lot 3)** : suivi des etages ouverts pour tous les controleurs |
| `src/client/Controllers/GhostVisibilityController.luau` | client | Etage ferme d'une autre base (ou libre) : vitre rouge + textes caches en local, sans collision ; les dalles `Floor` (plafond de l'etage du dessous) restent |
| `tools/build-map/02*-floor-*.luau` | Studio | `ServerStorage.FloorTemplate` + la zone STAIRS (2 voies, rampes, garde-corps, palier, vitre rouge) |

## Remotes

| Nom | Sens | Arguments | Verifications serveur |
|---|---|---|---|
| (prompt E `BuyFloorPrompt`) achat d'etage | client -> serveur | aucun (ProximityPrompt) | proprietaire, c'est bien l'etage suivant, distance, argent, delai `BuyCooldown` |
| `FloorTeleport` | client -> serveur | numero d'etage | nombre entier, 1..etages achetes de SA tour, delai `TeleportCooldown` (0.5 s) ; envoye par les fleches du selecteur |

## Donnees sauvegardees (SchemaVersion 4, fait le 2026-11-20 : voir `sauvegarde.md`)

```
Floors = {                           -- une case par etage achete ; nombre d'etages = #Floors
  [1] = { Upgrades = { Tree = 1, Blender2 = 0, ... } },   -- ameliorations / employes de l'etage
  [2] = { Upgrades = { ... } },
}
TowerUpgrades = { ElevatorSpeed = 0, ElevatorCabin = 0 }   -- toute la tour
```
Decide le 2026-11-20 : pas de champ `FloorsOwned` (une seule source : la liste).

- Migration 3 -> 4 : les `Upgrades` deviennent `Floors[1].Upgrades` (Tree borne a 10).
- Restent globaux : argent, Index (fruits decouverts), rebirths, passes / boosts.
- Rebirth : remet `Floors = { [1] = defaut }` et `TowerUpgrades` a 0.

## Configuration

`Config/Floors.luau` : `FloorHeight = 36`, `MaxFloors = 10`, par etage `rarity` (a retirer : regle du 2026-11-20),
`price`, `accentColor`, `title`. Prix (decide le 2026-11-20) : un etage coute **environ 10 a 15
minutes de gains** de la tour quand l'etage d'en dessous est bien ameliore. Un jus de l'etage n+1
vaut environ x5 celui de l'etage n (valeurs de `Fruits.luau`). Chiffres exacts a regler en test.

**Rebirth (decide le 2026-11-20) : possible seulement quand l'etage 10 est achete** (+ un montant
d'argent). Il remet la tour a 1 etage et donne le multiplicateur permanent.

## Retours de test du 2026-11-20 (soir)

- **Etage ferme = juste la porte rouge** (demande : "pas de truc bleu transparent pour les etages,
  juste la porte rouge fermee") : `FloorAssembly` ne garde plus que les dalles `Floor` (plafond de
  l'etage du dessous) et l'escalier du trou (garde-corps, murs invisibles, vitre rouge `BuyGate`),
  avec leurs vraies couleurs. Plus de murs / balcon / cage d'ascenseur teintes, plus de contour
  `ClosedGlow`. Etage ferme : ~70 pieces (396 avant). Le bleu transparent reste pour les machines.
  `Config/Floors.Closed*` ne sert plus (garde pour l'instant).
- **Murs invisibles de la terrasse** : retires le 2026-11-20 (avec la cloture blanche et le
  portail cote rue). Cote client, ce que
  `GhostVisibilityController` / `LevelLookController` cachent n'a plus de collision pour ce joueur.
  Restent solides et invisibles : la rampe et les garde-corps de l'escalier (necessaires).
- **Terrasse** : la file des clients serpente dans toute la longueur (4 allees nord-sud, voir
  `clients.md`) ; le couloir x -15 -> 0 reste libre pour le joueur.
- **Panneau ELEVATOR** : deplace de la terrasse (mur de l'usine, z 46-60) sur la cage de
  l'ascenseur, face nord (z 11.35 -> 12.1), cote couloir. Depuis le 2026-11-20 (fin de journee) :
  **vertical**, de la largeur de la cage (x -8.8 -> -1.2, y 1.5 -> 13.7) : titre en haut, Speed au
  milieu, Cabin en bas (avant horizontal x -13.5 -> 0.5, il depassait de la cage).
- **Vitre rouge de la terrasse** : retiree le 2026-11-23 (avant : "???" + "Opens with Floor 2",
  `TerraceTitle` / `TerraceLockedText` supprimes de `Config/Floors`).
- **"Objet en haut de l'ascenseur qui cache les avatars"** : cause pas reproduite avec certitude.
  Corrige : la cage teintee presque opaque de l'etage ferme (juste au-dessus du dernier etage) n'existe
  plus, et la cage / la cabine ne sont plus en materiau Glass (SmoothPlastic, transparence 0.7 /
  0.65 ; le Glass de Roblox masque ce qui est transparent derriere lui). A reverifier par l'utilisateur.
- **Fruits** : depot a n'importe quel etage (voir `chaine-production.md`).

## Problemes connus / a faire

- **Prix des etages (A VALIDER)** : 0 / 1.5K / 11K / 62K / 350K / 2M / 11.5M / 66M / 380M / 2.2B
  (`Config/Floors.Prices` ; courbe progressive du 2026-11-20 : x5.5 puis jusqu'a x5.8 par etage alors
  que les jus font x5, donc les etages durent un peu plus en montant ; avec l'ascenseur, simulation :
  etage 2 ~10 min, puis ~11-16 min par etage, attente max ~2-3.5 min, rebirth vers 1 h 55 pour un
  joueur qui achete bien). Playtest chronometre (robot, 2026-11-20, etage 2 a 2K) : etage 2 a 12:07
  (avec 2 fruits tres rares, sinon ~14:55 et ~6.5 min sans achat), etage 3 a 29:07 : etage 2 -> 1.5K. Prix des ameliorations d'un etage x5^(n-1). Etape precedente :
  Divises par 2 le 2026-11-20 (revue de l'economie) : avec 5K, l'arbre plafonnait l'etage 1 vers
  7-9 min et le joueur attendait ~8.5 min sans rien d'utile a acheter. Simulation : etage 2 vers
  11 min, attente max ~4.5 min, etage 10 vers 1 h 25, rebirth (10B) vers 1 h 40 (joueur qui achete
  bien ; un vrai joueur sera plus lent). A regler en jouant.
- Avec 10 etages achetes, la base fait ~12 600 pieces et chaque etage fait tourner arbre, employes et
  ventes : a alleger au lot 5 (visuels seulement sur l'etage du joueur) et mesurer au lot 6.
- "NEW FLOOR!" s'affiche aussi si les etages sont reconstruits plus de 6 s apres l'arrivee du joueur
  (outils admin "+1 Floor" / "10 Floors") : sans gravite.

- Lots 2 a 6 a faire (`roadmap.md`, phase 1b). En jeu aujourd'hui : etage 1 seulement (transitoire).
- Pieces par etage (~1150-1230) au-dessus de l'objectif ~800 : a decider avec l'utilisateur (alleger
  les fenetres / cadres des etages, mixeurs en MeshPart, ...).
- Le corps de l'escalier est un grand triangle plein (vu de cote, mur a studs) : a valider a l'oeil.
- Ascenseur : x -9 -> -1, z 3 -> 11 (coin avant de la terrasse, colle au balcon). File des clients
  en zigzag (demande utilisateur, 2026-11-20) : portail cote rue x -44 -> -37, 3 allees entre des
  cordes (z 1-4.5, 4.5-8, 8-11.5), points de passage `Annex.Terrace.QueuePath.Point1..6`.
- Salle du Rebirth : nom affiche "???" (`Config/Floors.RebirthRoomTitle`), plafond + 2 neons
  (2026-11-20). Visuel du lot 1 valide par l'utilisateur le 2026-11-20.
- Reste a regler les chiffres en jeu (prix, gains par etage).

- 2026-11-23 : achat d'etage refuse faute d'argent -> FloorService envoie aussi Feedback "NeedCash"
  `{ floor, missing }` (au plus 1 fois / 3 min) : fenetre "Almost there!" (DealController, voir achats-robux.md).
