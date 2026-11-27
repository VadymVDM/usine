# Systeme : Machines, ameliorations et employes

**Statut :** en cours (achats, pad de l'arbre, panneaux, mixeurs a 5 niveaux, decor par niveau,
employes R15 : playtest Studio du 2026-11-27 a 1 joueur ; 2 joueurs et telephone non testes)
**Derniere mise a jour :** 2026-11-27 (tous les employes en R15 ; gestes Press / Deposit de l'operateur dessines par le client)

## Role

> **Tour d'etages (2026-11-20, phase 1b lot 3)** : chaque etage a ses machines, panneaux, pads et
> employes, avec ses propres niveaux (`Data.Floors[n].Upgrades`, memes ids). Les prix d'un etage n
> sont ceux de `Config/Upgrades` x 25^(n-1) (`Config/Floors.UpgradePrice`, A VALIDER). Le serveur
> trouve l'etage par la hauteur du joueur (achat par tuile / pad / remote `BuyUpgrade`).
> `UpgradeService.OnBought(cb(player, id, level, floor))`.

Tout ce qui s'achete avec l'argent du jeu dans l'usine. Regle du jeu (voir `game-design.md`,
"Regle d'or du ressenti") : **acheter = construire**. Une machine pas encore achetee est la **vraie
machine teintee bleu clair** (presque opaque, on voit ses details) avec un contour clair qui pulse
par-dessus (comme sur la capture de reference de l'utilisateur) ; au premier achat, elle se
construit piece par piece. Les employes sont de **vrais personnages R15** (comme les joueurs) qui marchent, prennent et
posent les objets.

Refonte du 2026-11-19 soir (demande : "le truc luck, le truc H2O, le Juice Cooler, le Fast
Register, on comprend pas a quoi ca sert" ; "quand on ameliore, on ne voit pas de changement") :
- les machines qu'on ne comprenait pas sont retirees (Sprinkler, Lucky Fertilizer, Juice Cooler,
  Fast Register, Billboard a acheter) ;
- l'arbre s'ameliore sur **un seul pad** a cote de lui ("Upgrade Tree") ;
- le reste s'ameliore sur des **panneaux muraux** a cote de ce qu'ils ameliorent, avec une phrase
  qui dit a quoi ca sert ("Fruits reach blenders faster", "Holds more juices"...) ;
- **chaque mixeur a 5 niveaux** (son bol), achete sur un panneau suspendu au-dessus de lui ;
- **chaque niveau se voit** : l'arbre change de modele, les fruits debloques pendent dedans ; le
  tapis, les mixeurs, la table a jus, le comptoir et le panneau FRESH JUICE! gagnent des pieces.

> **2026-11-21 : le pass Auto Sell est remplace par "Instant Sell"** (pad a droite de Drop Juices,
> jus poses = vendus tout de suite ; voir `pads-robux.md`). `AutoSellService` est supprime. Les
> notes ci-dessous sur Auto Sell sont l'historique.

> **Auto Sell (2026-11-20, demandes : "le waiter retire, tu met un pad payant qui s'appelle auto
> sell", puis "199 robux")** : l'employe Waiter n'existe plus. A sa place (x 44, z 31) : un pad vert
> **"Auto Sell" a 199 R$** = meme forme que les pads verts, en violet (`src/shared/Util/RobuxPad.luau`, commun avec Auto Collect) = Game Pass `Shop.Passes` "AutoSell" (aussi dans la boutique, `passId = 0`
> tant qu'il n'est pas cree sur Roblox : le pad dit alors "coming soon"). Ce n'est plus une
> amelioration : modele `Machines.AutoSell` sans `UpgradeId` (FloorTemplate), gere par
> `AutoSellService` (marcher dessus = fenetre d'achat Roblox ; etiquette "R$ 199" ou "ACTIVE").
> Avec le pass (attribut joueur `AutoSell`, pose seulement par le serveur), toutes les
> `Gameplay.AutoSellSeconds` (0.5 s), jusqu'a `AutoSellBatch` (2) jus sautent de la table au comptoir
> (animation + son de pose), sur l'etage ou est le joueur, tous etages confondus. L'ancien id
> `Server` est retire de `Config/Upgrades` (DataService l'efface des sauvegardes).

> **Waiter + pad violet Auto Sell (2026-11-20, plus tard, demande : "le pad a cote de la ou on prend
> les boissons ; d'abord un pad en argent : on paye l'employe lent qui ramene les boissons au
> comptoir ; des qu'on l'achete, le pad se transforme en pad violet Auto Sell")** : a cote du pad
> Take Juices (FloorTemplate x 12, z 70, cote mur) il y a DEUX pads a la meme place :
> 1. `Machines.Waiter` : pad vert **"Waiter $400"** (nouvel id `Waiter`, employe, argent du jeu) ;
> 2. `Machines.AutoSell` : le pad violet Robux, pieces `LookId = "Waiter"`, `LookLevel = 1` : invisible
>    et sans collision (client, `LevelLookController`) tant que le Waiter n'est pas embauche ; a
>    l'embauche le pad vert disparait (UpgradeService) et le violet apparait en fondu + etincelles.
>    `AutoSellService` ignore le pad tant que l'attribut d'etage `Lv_Waiter` < 1 ; juste apres
>    l'embauche, le joueur encore dessus doit descendre et remonter pour ouvrir l'achat Robux.
> Le pass reste achetable dans la boutique a tout moment. Raison : sans vendeur en argent du jeu, un
> etage ne pouvait pas etre automatise sans payer de Robux (FloorIncome).

> **2026-11-20 (soir) : le pad violet ne vend plus Auto Sell mais "Speed x10"** (demande : "le truc
> juste a cote de prendre les boissons, tu fais speed fois 10"). Modele renomme
> `Machines.SpeedBoost` (meme place, meme apparition apres l'embauche du Waiter), gere par
> `PassPadService` ; voir `pads-robux.md`. Auto Sell reste un pass de la boutique (`AutoSellService`
> ne gere plus de pad). Renomme "Waiter Speed x10" le meme soir : il accelere le **Waiter** x10
> (`WorkerService.applyStats`, `Gameplay.WaiterSpeedPassMultiplier`, et `FloorIncome`), plus le joueur.

> **Usine a construire (2026-11-21, `usine-a-construire.md`)** : sur l'etage 1 d'un profil neuf, chaque
> id n'existe qu'a partir de son etape FREE (`Config/Setup.UpgradeStep`) : pad cache, panneau cache
> (tuile `Unbuilt`, panneaux Conveyor / Juice Table / Customers / Fruit Picker maintenant
> `HideWhenLocked`), machine `Hidden` (invisible cote serveur), achat refuse sans message. Le mixeur 1
> est invisible (pas de fantome) jusqu'au pad "Build blender", puis se construit (BuildStamp).
> **Pour tous les profils** : une machine verrouillee (mixeur 3 avant le 2, 4 avant le 3) est cachee
> (seule la prochaine est en bleu, demande "le transparent c'est que pour les prochaines machines") ;
> le panneau Fruit Picker n'apparait qu'a l'embauche du Fruit Picker ; panneaux et pads qui
> apparaissent font un "pop" (`Fx/Reveal`, LevelLookController / SetupController).

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/UpgradeService.luau` | serveur | Seul a modifier `Data.Floors[n].Upgrades` (niveaux par etage ; prix x `Floors.UpgradePriceFactor`^(n-1), A VALIDER). Fantomes, prompt E + etiquette des machines, pads des employes, tuiles, achats, verifications |
| `src/server/Services/WorkerService.luau` | serveur | Employes R15 : apparition a l'embauche, boucles de travail |
| `src/server/Services/PassPadService.luau` | serveur | Pad violet `Machines.SpeedBoost` (a la place du Waiter embauche) et pad `Billboard` de la cour : voir `pads-robux.md` |
| `src/server/Lib/NpcRig.luau` | serveur | Rigs R15 (HumanoidDescription), animations R15 des joueurs, marche (`MoveTo` + Pathfinding), objets portes, gestes (`Press`, `Deposit`, `Pick`, `Dump`), groupes de collision |
| `src/client/Controllers/CarryPoseController.luau` | client | Bras sous le plateau / objets portes, et pose R15 du Fruit Picker pendant le ramassage et le depot |
| `src/server/Services/ProductionService.luau` | serveur | Mixeurs possedes, taille du bol ; API caisses / table a jus / bols (`GetBowl`, `OperatorBlend`) pour les employes |
| `src/shared/Util/MachineModels.luau` | partage | Liste des modeles achetables d'une base : `Machines.<id>` + `Production.Blenders.BlenderN` et `BlenderN.Operator` |
| `src/client/Controllers/BuyController.luau` | client | Appui long sur tuiles / pads (jauge "HOLD"), pop-up "Buy X?" YES / NO au premier achat d'une machine ou d'un employe, remote `BuyUpgrade` |
| `src/client/Controllers/MachineFxController.luau` | client | Construction animee (pieces qui tombent puis "boing" gelee via `Fx/Jelly`), boing + etincelles a chaque amelioration d'une machine deja construite, contour bleu des fantomes (Highlight), pieces qui tournent (en pause pendant un boing), etiquettes des autres bases cachees, etiquette du pad "Upgrade Tree" tant qu'il n'est pas au max |
| `src/client/Controllers/GhostVisibilityController.luau` | client | Cache en local (et sans collision) les "choses a construire" des autres bases : machines fantomes, pads d'achat, vitre rouge de l'etage ferme (ses dalles `Floor` restent : plafond de l'etage du dessous) |
| `src/client/Controllers/LevelLookController.luau` | client | Decor par niveau : montre / cache les pieces `LookId` / `LookLevel` / `LookMaxLevel` selon l'attribut d'etage `Lv_<id>` (fondu + etincelles quand une piece apparait), cache le panneau d'un mixeur verrouille (`HideWhenLocked`), fait defiler les lattes du tapis (plus vite quand il est ameliore) et donne aux bandes `Belt` / `RowBelt` la meme vitesse de surface (le joueur qui monte dessus est emporte, 2026-11-27) |
| `src/shared/Config/Upgrades.luau` | partage | Effets, prix (`prices` pour les mixeurs), phrase `desc`, format de l'effet (`format`), `builtAt`, `repeatPad`, prix Robux + `RobuxProducts` (produits des tuiles), messages ; `TreeDropSeconds`, `FormatValue`, `BuiltAt` |
| `src/shared/Config/Npcs.luau` | partage | Tenues des PNJ R15 (vetements gratuits du catalogue Roblox), couleurs et noms des postes |
| `src/shared/Util/R15Walk.luau` | partage | Melange marche / course des PNJ R15 selon la vitesse (formule du script Animate) : employes (NpcRig) et clients (CustomerController) |
| `tools/build-map/02e-base-machines.luau` | Studio | Pads verts : "Upgrade Tree" (reste apres l'achat), Fruit Picker, pad Robux Auto Sell (ex-Waiter, sans UpgradeId) ; dossier `Looks` (panneau FRESH JUICE! qui grandit avec More Customers) |
| `tools/build-map/02c-base-production.luau` | Studio | Les 4 mixeurs (UpgradeId Blender1..4, decor des niveaux 2 a 5), le pad de l'operateur de chaque mixeur, le decor du tapis par niveau, la table a jus en 3 tailles |
| `tools/build-map/02d-base-counter.luau` | Studio | Panneau "MONEY / HOUR", decor du comptoir par niveau de Faster Customers |
| `tools/build-map/02g-base-boards.luau` | Studio | Panneaux d'ameliorations : Conveyor, Juice Table, Customers, BlenderSign1..4 (tuiles en surface Weld, cadre bois a studs, en-tete titre + icone) |
| `src/client/Controllers/BoardFxController.luau` | client | BOUTONS des tuiles de SA base (pas la tuile) : survol souris (+12 %, UIScale "Scale"), appui (-10 %, son `TileClick`) puis rebond, rebond du bouton vert a l'achat (`Bought`), bouton vert rouge au refus (`Denied`) ; curseur fleche normale (au lieu de la main) sur tous les ClickDetector des bases |
| `src/shared/Util/UpgradeTile.luau` | partage | Dessin d'une tuile (SurfaceGui "Display") : voile de couleur vive, contour noir, titre, icone + fleche verte, "a → b", bouton vert (prix), bouton violet (Robux). Utilise par 02g et 02j ; `ARROW` sert aussi au serveur |

## Fonctionnement

- **Sortie d'un pad (2026-11-20)** : on entre sur un pad avec le test exact de la zone, mais une
  fois dessus on n'en sort qu'a `Gameplay.PadExitMargin` (1.5) studs du bord ou
  `PadExitHeight` (12) studs au-dessus (un saut ne compte pas). Meme regle cote client
  (`PadController` : son / effet, remote `PadEnter`) et serveur (`UpgradeService.checkPads` :
  achat). Avant, rester au bord ou sauter refaisait l'achat et le "clic".

- **Ou s'achete quoi** (2026-11-19 soir) :
  - **Arbre** : pad vert "Upgrade Tree" devant la jardiniere (x 87, z 93). Se tenir dessus = 1 niveau
    (nouveau fruit possible + chute plus rapide), puis 1 de plus toutes les `PadRepeatSeconds`
    (0.8 s) tant qu'on reste dessus ; s'arrete au premier refus (argent, max) : il faut descendre et
    remonter. Etiquette : "Upgrade Tree", "Lv 3 > 4", prix. Le pad reste jusqu'au max
    (`repeatPad`, attribut `Repeat`).
  - **Tapis** : panneau **Conveyor** sur le mur du fond, a cote de la boite du tapis (x 15).
  - **Table a jus** : panneau **Juice Table** sur le mur de droite (vu de la route), a cote de la
    table (x 1.3, z 78.5).
  - **Clients** : panneau **Customers** sur la facade, a cote de la fenetre du comptoir (x 38.8) :
    Faster Customers + More Customers.
  - **Mixeurs** : le mixeur 1 est offert (niveau 1). Les mixeurs 2 a 4 sont la vraie machine
    teintee bleu : prompt E "Blender 2 / Buy $250" + pop-up, et RIEN d'autre (2026-11-20, retour de
    test : "enleve les panneaux pour les trucs d'achat, pour les machines il faut s'approcher et
    appuyer sur E"). Ensuite chaque mixeur s'ameliore (niveaux 2 a 5) sur **son panneau suspendu**
    au-dessus de lui (`Boards.BlenderSignN`), cache tant que le mixeur est verrouille OU pas encore
    achete : UpgradeService pose `Unbuilt = true` sur la tuile, met son ClickDetector a 0 et refuse
    l'achat par la tuile ; LevelLookController cache le panneau (et coupe ses collisions en local). Le prompt E de la machine ne
    sert qu'au premier achat (sinon il serait sur le meme mixeur que "Blend").
  - **Employes** : pads verts (inchange).
  - **Fruit Picker** (2026-11-20, demande : "un panneau sur le mur a cote du fruit picker qui permet
    de l'accelerer, avec des Robux ou de l'argent, comme les autres") : panneau **Fruit Picker**
    (`Boards.PickerBoard`, tuile Picker Speed verte, et dessous la tuile **Picker Hands** = fruits
    portes, 2026-11-20) sur le mur du fond, partie pleine x 62 -> 76
    (centre x 67, z 134.7), entre l'etagere a fruits et l'arbre, la ou il travaille. C'est le seul
    mur present a tous les etages pres de son pad (x 70, z 91 : le cote de l'escalier change selon
    la voie A / B). Bouton vert = argent ; bouton violet = Robux comme les autres
    tuiles. Achat refuse tant que le Fruit Picker n'est pas embauche ("Buy Fruit Picker first!").
- **Tuile d'un panneau** (style refait le 2026-11-20 d'apres les captures de l'utilisateur, tuile
  7.2 x 4) : couleur pure et saturee, palette des captures (violet 180,50,235 ; rouge 235,35,45 ;
  cyan 35,190,245 ; jaune 250,225,35), Part en surface Weld (traits en X) + voile de la meme
  couleur sans eclairage (transparence 0.15) dans la SurfaceGui (sinon la couleur parait sombre ;
  le pastel a ete refuse), contour noir epais, titre
  en haut, grosse icone a gauche avec une **fleche verte** (dessinee en Frames), effet
  "actuel → suivant" (ex. "4.5s → 4s", "NEW!" pour un mixeur pas encore achete, "MAX"), bouton vert
  (prix) et violet (Robux). Plus de phrase `desc` ni de "Lv" sur la tuile. En-tete du
  panneau : titre en gros + icone de la premiere tuile a droite.
- **CLIQUER le bouton vert = acheter un niveau** (demandes du 2026-11-20 : "on doit CLIQUER dessus
  et pas avec E", puis "c'est les boutons qui doivent hover, pas toute l'interface") : Part
  invisible `BuyButton` + ClickDetector juste devant le bouton dessine (`UpgradeTile.BUY_RECT`), un
  clic / tap = une demande `BuyUpgrade` (pas d'appui long). Le reste de la tuile ne fait rien. Le
  bouton violet a sa Part invisible `RobuxButton` (ClickDetector serveur, BuyController l'ignore).
  Panneau ELEVATOR de la terrasse : pareil (`BuyButton`, `BUY_RECT_WIDE`), le clic va au
  ClickDetector (FloorService), plus de prompt E.
- **Animations des boutons** (2026-11-20, `BoardFxController`, ressorts de `Fx/Jelly`) : seuls les
  boutons vert / violet bougent (survol, appui, rebond d'achat, rouge au refus) ; la tuile reste
  fixe. Plus de "pop" de taille ni de rouge dans MachineFxController pour les tuiles (il garde les
  etincelles + son Purchase).
- **Effet des pads verts** (2026-11-20, client seulement, `PadController`) : quand on monte sur un
  pad vert visible (Upgrade Tree, Fruit Picker, Auto Sell, operateurs `BlenderN.Operator`), le bloc
  (`PadTop` seul, le neon `PadGlow` reste en place) descend doucement de 0.2 stud, sans rebond, et remonte doucement quand on
  descend ; son `GreenPadStep` ("Switch Click On Or Off Toggle Button 2", 9119717523). Pads caches : rien.
- **Employes** : seulement un **pad vert** a leur poste (style des captures de reference depuis le
  2026-11-19 : dalle epaisse vert fonce = bord, dessus vert vif a studs, 4 baguettes neon autour ;
  pieces `PadBase`, `PadTop` + `Tag`, `PadGlow` sans requete, `PadZone`) (marcher dessus = embaucher ; nom +
  prix au-dessus). Plus de silhouette d'employe en blocs ni de chariot de fruits / gobelets
  decoratifs (retires le 2026-11-19 soir : "il sert a rien", confondus avec de vrais fruits). A
  l'embauche le pad disparait et le vrai employe R15 apparait a son poste (`Markers.<Role>Home`).
- Fantome (serveur) : chaque piece garde sa forme, sa couleur est melangee a 72 % avec du bleu
  clair (150, 205, 255), transparence 0.18, sans collision. Contour (client, Highlight, seulement
  dans SA base) : contour bleu tres clair + un peu de bleu qui pulse.
- **Fantomes et pads seulement dans SA base** (demande du 2026-11-20, `GhostVisibilityController`) :
  dans les autres bases (et les bases libres), les machines fantomes (`Built` ~= true) et tous les
  pads d'achat / d'embauche (Upgrade Tree compris) sont caches en local (`LocalTransparencyModifier`).
  Une machine construite reapparait normalement ; ses pieces de decor de niveau (`LookId`) gardent
  le choix de LevelLookController, le jus du mixeur celui de BlenderFxController. Depuis le
  2026-11-20 ("murs invisibles sur les bases vides") : une piece cachee ici n'a plus de collision
  pour ce joueur (CanCollide = false en local, valeur d'origine remise quand elle reapparait). Le pad Auto Sell (sans `UpgradeId`) n'est pas concerne.
- **Achat = appui long, SAUF les tuiles des panneaux** (appui long demande le 2026-11-19 ; tuiles
  au simple clic depuis le 2026-11-20) :
  - machine : prompt E **maintenu** `Gameplay.BuyHoldSeconds` (0.6 s, jauge native Roblox) ;
  - tuile d'un panneau : **simple clic** / tap (`BuyController`) ;
  - dessus d'un pad : clic / doigt **maintenu** 0.6 s, une jauge "HOLD"
    se remplit sous le pointeur ; relacher ou glisser (> 28 px) annule (`BuyController`) ;
  - **premier achat** (modele `Built` = false : machine fantome ou employe pas embauche) :
    pop-up "Buy Blender 2?" / "Hire Fruit Picker?" + prix, YES / NO (copie du menu
    OfflineEarnings, ouverte par MenuController). YES -> remote `BuyUpgrade`. Pour le prompt E d'une
    machine fantome (attribut `Confirm` = true), le serveur ignore `Triggered` et attend ce remote ;
  - tuile au max / "coming soon" : la demande part tout de suite (le serveur affiche le message) ;
  - marcher sur un pad (employe, Upgrade Tree) achete toujours directement (sans pop-up).
- Achat (serveur) : joueur valide, **sa** base, assez pres (portee du prompt / du clic + 8), delai 0.25 s
  (`BuyCooldownSeconds`, baisse pour les clics rapides),
  niveau < max, `MoneyService.TrySpend`. Puis niveau + 1, machine construite si c'etait un
  fantome, textes mis a jour, `OnBought` (WorkerService fait apparaitre l'employe). Refus : message
  (Notify) + pad / bouton rouge 0.6 s.
- **Joueur dans un fantome** : un fantome n'a pas de collision, on peut etre dedans en l'achetant.
  Quand il se construit, le serveur sort chaque joueur qui touche la boite de ses pieces solides
  par le cote le plus proche, a `BuildPushMargin` (2 studs) du bord (avant : bloque dans le mixeur
  ou pousse sous le sol ; corrige le 2026-11-19).
- Plus de fleche jaune "prochain achat" (retiree le 2026-11-19 soir : on ne comprenait pas a quoi
  elle servait et elle rentrait dans les panneaux). Le guidage viendra en phase 2.

| Id | Ou l'acheter (repere local de la base) | Effet |
|---|---|---|
| Tree | pad "Upgrade Tree" (x 87, z 93) | +1 fruit possible ET chute plus rapide ; l'arbre change a chaque niveau |
| ConveyorSpeed | panneau Conveyor (mur du fond, x 15) | fruits envoyes par seconde par le tapis (trajet plus court aussi) ; icone eclair jaune `Icons.Lightning` (2026-11-20, avant la chaussure) |
| JuiceLimit | panneau Juice Table (mur de droite, z 78.5) | jus max sur la table a jus ; la table grandit |
| CustomerSpeed | panneau Customers (facade, x 38.8) | secondes entre deux passages de clients |
| CustomerCount | panneau Customers | clients qui achetent a chaque passage |
| Collector | Fruit Picker (pad x 70, z 91) | ramasse les fruits DEJA DECOUVERTS et les porte a l'etagere (un nouveau fruit reste au sol pour le joueur, 2026-11-20) |
| PickerSpeed | panneau Fruit Picker (mur du fond, x 67) | vitesse du Fruit Picker : marche x (0.7 x valeur), pauses / (0.7 x valeur) ; debit en nombres (FloorIncome.PickerRate) ; demande Collector |
| PickerCarry | panneau Fruit Picker, tuile du bas ("Picker Hands") | fruits portes par le Fruit Picker avant l'etagere (2 -> 9 depuis le 2026-11-21) ; demande Collector |
| Blender1 | panneau suspendu au-dessus du mixeur 1 | taille de son bol (5 / 8 / 12 / 16 / 20) |
| Blender2..4 | la machine teintee bleu (achat), puis son panneau suspendu | un mixeur de plus, puis son bol ; a acheter dans l'ordre (`requires`) |
| Operator1..4 | Blender Operator (pad 5 x 5 devant le panneau de son mixeur, marcher dessus) | allee devant la rangee (z 84-89) | appuie sur le bouton de son mixeur quand le bol est plein (~1 s de reaction) |

### Employes R15 (WorkerService, serveur)

- Rigs : `Players:CreateHumanoidModelFromDescription(..., R15)` avec les tenues de `Npcs.luau`
  (t-shirt Roblox + jean noir), tablier et casquette de la couleur du poste, nom au-dessus
  ("Fruit Picker", "Blender Operator" x 4, "Waiter"). Animations R15 des joueurs (marche, attente)
  jouees par l'Animator du serveur (vues par tous). **La marche ne joue que pendant un trajet**
  (`NpcRig.MoveTo` la lance et l'arrete ; avant, l'evenement `Humanoid.Running` la lancait aussi a
  l'arret ou pendant un blocage : marche sur place, corrige le 2026-11-19 soir). Trajets calcules par
  **PathfindingService** autour des meubles (rayon 1.4, sans saut). Trajet verifie a chaque frame ;
  l'employe vise le point de passage suivant des qu'il est a `Npcs.WaypointLookAhead` (2.5 studs)
  du point en cours (sinon le Humanoid s'arrete net sur chaque point : marche a-coups, corrige le
  2026-11-20). Groupe de collision "Npc" : ils
  ne bloquent pas les joueurs. N'avance plus depuis `Npcs.StuckSeconds` (1.2 s) ou trajet plus long
  que `NpcMoveTimeout` (7 s) : pose a l'arrivee. Sans travail, l'employe retourne a son poste et
  regarde son travail (arbre, boite du tapis, comptoir) au lieu de marcher sur place.
- **Fruit Picker en R15 depuis le 2026-11-27** (demande : "animation de marche et de recolte plus
  naturelle, comme un vrai perso Roblox"). `Npcs.Employees.Collector.r15 = true` : rig R15 (comme
  les joueurs), tablier sur `UpperTorso`. Animations R15 par defaut de Roblox (`Npcs.AnimationsR15` :
  attente, marche, course) ; marche et course jouees ensemble et melangees selon `WalkSpeed`, avec
  la meme formule que le script Animate (`Util/R15Walk`, partage avec les clients).
- **Tous les employes en R15 depuis le 2026-11-27** (Blender Operator et Waiter ensuite ; demande :
  "passer TOUS les PNJ en R15, comme les joueurs"). Plus aucun rig R6 ni animation R6 (`Npcs.Animations`,
  `Npcs.WalkAnimSpeed` et le drapeau `Employees.<role>.r15` supprimes). Tablier sur `UpperTorso`.
  Waiter : plateau sur la tete (`HandJuices`, `HandStackController`, `HandStack.WorldSlot` lit la
  tete) et bras leves dessous (`CarryPoseController`) : verifie en Play.
  - **Ramassage** (`NpcRig.Pick`) : il s'arrete a `Gameplay.PickerReach` (2.1) studs du fruit, du
    cote d'ou il arrive (`NpcRig.ReachPoint` ; avant : il marchait SUR le fruit puis pivotait d'un
    coup), se tourne en douceur, puis geste de `PickerPickSeconds` (0.65 s) / vitesse : il reste
    **debout**, bras droit tendu vers le fruit puis vers le plateau (l'accroupi, genoux plies et buste
    penche, est retire depuis le 2026-11-27, demande : "enleve l'animation qui fait se baisser le
    fruit picker"). A `Npcs.PickGrabAt` le fruit quitte le sol (`TakeFruit`) et une
    copie est soudee a sa main droite ; a `Npcs.PickTrayAt` elle arrive sur le plateau (`TrayFruits`).
  - **Depot** (`NpcRig.Dump`) : a l'etagere il se tourne vers les caisses (centre de
    `Production.Bins`), pousse le plateau vers l'avant en penchant la tete (le plateau, soude a la
    tete, bascule) avec une petite flexion ; a `Npcs.DumpReleaseAt` les fruits s'envolent du
    plateau vers leurs caisses (`AddFruitsToBins`, point de depart = au-dessus de sa tete), puis il
    baisse les bras. Duree `PickerDumpSeconds` (0.8 s) / vitesse (remplace la pause).
  - La pose est dessinee par chaque client (`CarryPoseController`, Transform des articulations R15
    apres les animations) a partir de l'heure de depart (attributs `PickStart`/`PickTime`,
    `DumpStart`/`DumpTime`, horloge `GetServerTimeNow`) : rien n'est replique image par image.
- **Fruit Picker** (vitesse : `EmployeeWalkSpeed` x `PickerBaseSpeed` (0.7 : 30 % plus lent depuis
  le 2026-11-20) x PickerSpeed, pauses `EmployeePauseSeconds` / meme facteur, changee tout de suite a
  l'achat) : va au fruit au sol le plus proche (`TreeService.FindNearest`, fruits reserves),
  le pose sur **un plateau au-dessus de sa tete, comme le joueur** (2026-11-20, demande : "il ramasse
  les fruits pareil avec le plateau" ; avant : fruits tenus devant, bras tendus) : le serveur pose
  l'attribut `TrayFruits` sur son modele, `TrayController` dessine le meme plateau (sans "x/20") et
  `CarryPoseController` leve ses bras dessous. Jusqu'a PickerCarry (2 au depart, 6 au max ; avant le
  2026-11-20 : toujours 6), puis marche jusqu'a l'etagere
  (`Markers.ShelfDrop`) : les fruits volent dans leurs caisses (`WorldFx` "FruitsToBins").
- **Blender Operator** (refonte du 2026-11-19 ; avant : un seul, qui portait les fruits de
  l'etagere au tapis et rendait le mixeur 2x plus rapide) : **un par mixeur** (`Operator1..4`,
  modele R15 `Npcs.Employees.Operator`). Il reste debout a sa place (`BlenderNOperator`, dans
  l'allee devant le bouton vert), face au panneau. Quand son bol est plein (ou a des fruits mais ne
  bouge plus depuis `OperatorIdleBlendSeconds` = 8 s), il attend `OperatorReactSeconds` (1 s, geste
  compris), leve le bras droit vers le bouton (`NpcRig.Press`, voir "Gestes de l'operateur") et
  lance le mixage (`ProductionService.OperatorBlend`, memes regles que le joueur). Table pleine :
  il reessaie 1.5 s plus tard. Le joueur peut toujours appuyer lui-meme.
- **Depot des jus par l'operateur** (2026-11-27, demande "petite animation pour le blender operator
  qui depose les jus sur la table") : quand les jus de SON mixeur sortent (fin de mixage ou jus en
  attente qui coulent), `ProductionService.pourToTable` appelle `WorkerService.onPour` (branche par
  `ProductionService.SetPourHandler`). Si l'operateur est a sa place et libre : `NpcRig.Deposit` le
  tourne en douceur vers la table (0.3 s, `DepositTurnSeconds`) en tendant les deux bras, petit lancer
  (bras qui montent, easing Back) pendant que les gobelets sautent DE SES MAINS (`PopFrom` =
  `NpcRig.HandsPoint`, `PopDelay` = 0.3 s : le client les garde invisibles jusque-la), puis il baisse
  les bras et se retourne vers son bouton. `busyUntil` empeche sa boucle de le retourner ou d'appuyer
  pendant le geste. Pas d'operateur (ou pas a sa place, ou deja occupe) : les gobelets sortent du bec
  comme avant. Les gobelets sont deja sur la table cote serveur : le geste ne ralentit rien.
- **Gestes de l'operateur en R15 (2026-11-27)** : avant, `Press` et `Deposit` tournaient le C0 des
  epaules R6 avec des tweens serveur (repliques image par image). Maintenant le serveur pose
  seulement l'heure de depart (attributs `PressStart` / `PressTime`, `DepositStart` / `DepositTime`
  / `DepositToss`, horloge `GetServerTimeNow`) et chaque client dessine les bras
  (`CarryPoseController`, comme `Pick` / `Dump` du Fruit Picker). Le serveur tourne toujours le corps
  (vers la table puis vers le bouton). Memes durees et angles qu'avant (`Npcs.PressSeconds` 0.65,
  `PressReachSeconds` 0.3, `DepositTurnSeconds` 0.3 ; bras a 80 deg puis 65 deg pour l'appui,
  85 deg puis 110 deg pour le lancer) : `BlenderFxController` (`PopDelay`) et `WorkerService.onPour`
  (`busyUntil`) n'ont pas change. Appui : bras droit leve coude plie, coude qui se tend sur le
  bouton, puis il redescend. Verifie en Play (mixeur 1, etage 2) : appui sur le bouton, puis 2.8 s
  plus tard il se tourne, lance les gobelets depuis ses mains et revient.
- **Embauche d'un operateur** : pad vert 5 x 5 devant le panneau (`BlenderN.Operator`) :
  **marcher dessus = embaucher**, comme les autres pads (2026-11-19, demande utilisateur : "un pad,
  on se met dessus, pas de E"). Plus de prompt E sur aucun pad ; l'ancien attribut `HirePrompt`
  encore present dans le .rbxl est ignore. Pad cache et inactif tant que le mixeur n'est pas
  achete (`Locked`). Risque accepte : on peut l'acheter en passant dans l'allee.
- **Machines verrouillees** (`Upgrades.requires`) : Blender3 demande Blender2, Blender4 demande
  Blender3, OperatorN demande BlenderN. Attribut `Locked` : fantome sans etiquette ni contour,
  prompt inactif, pad cache (marcher dessus ne fait rien) ; achat refuse "Buy Blender 2 first!".
- **Waiter** (`Waiter`, de retour le 2026-11-20, $400 A VALIDER) : volontairement **lent**
  (`Gameplay.WaiterBaseSpeed` 0.5 x 15 = 7.5 studs/s, pauses plus longues ; x10 avec le pass Robux
  "Waiter Speed x10", attribut joueur `SpeedBoost`). Il attend a
  `Markers.ServerHome` (x 30, z 66, a cote de la table a jus). Des qu'il y a `WaiterCarry` (9) jus sur
  la table, ou des jus qui attendent depuis `WaiterWaitSeconds` (3 s), il va a `ServerPallet`, prend
  jusqu'a 9 jus (`ProductionService.TakeJuices`) sur un **plateau sur la tete** (attribut `HandJuices`
  sur son modele + `TakeFrom` = d'ou les gobelets sautent ; `HandStackController` dessine aussi le
  plateau des employes), marche jusqu'a `ServerCounter` et les pose (`CustomerService.AddToCounter`,
  memes sauts que pour le joueur). Mesure en playtest : 9 jus, ~9.5 s table -> comptoir. Il continue
  de travailler meme avec le pass Auto Sell (il trouvera rarement des jus).

### Ce qui se voit a chaque niveau (2026-11-19 soir)

Le serveur pose sur chaque base l'attribut `Lv_<id>` (niveau du proprietaire, niveau de depart si
la base est libre). Les pieces de decor ont `LookId` (id), `LookLevel` (niveau minimum) et
parfois `LookMaxLevel` (variante remplacee plus tard, ex. rail jaune -> bleu -> dore) ;
`LevelLookController` (client) les montre / cache (LocalTransparencyModifier + collision locale) et
les fait apparaitre en fondu avec des etincelles et un "boing" quand le niveau monte.
`check-zfighting.luau` ignore deux variantes qui ne sont jamais visibles ensemble.

| Id | Niveaux et ce qui change |
|---|---|
| Tree | l'arbre change nettement a chaque niveau (construit par code, theme de l'etage, l'etage n repart du max de l'etage n-1) : voir `fruits.md` |
| ConveyorSpeed | lattes du tapis qui defilent plus vite a chaque niveau (et le joueur pose sur le tapis est emporte plus vite) ; 2 = baguettes neon vertes sous les rails ; 4 = moteur turbo (bande rouge, 2 tuyaux) sur la boite ; 6 = rails bleus ; 8 = panneau TURBO sur la boite ; 10 = rails et coins dores + etincelles |
| Blender1..4 | 2 = montants chromes aux coins du meuble ; 3 = anneau neon bleu sous le bol ; 4 = bandeau et rebord du bol dores ; 5 = bol en verre dore + etincelles. Le "3/5" au-dessus montre la taille du bol |
| JuiceLimit | table surelevee en 3 tailles : niveaux 1-3 (11 de long, bois), 4-6 (16, bandeau rose + rebord), 7-9 (21, bandeau et rebord dores + 2 lampes) ; les gobelets s'etalent (6 / 9 / 12 colonnes) |
| CustomerSpeed | comptoir : 3 = sonnette ; 5 = caisse enregistreuse ; 12 = guirlande lumineuse ; 15 = bord dore |
| CustomerCount | panneau FRESH JUICE! dans la cour (rez-de-chaussee seulement, dossier `Looks.OnlyGround`) : apparait au niveau 2 ; 3 = lampes ; 4 = orange geante ; 5 = pomme geante (plus de cadre neon depuis le 2026-11-20) |

## Remotes

`BuyUpgrade` (client -> serveur, id) : envoye par `BuyController` apres un appui long ou le YES de
la pop-up ; verifie par UpgradeService (id connu, sa base, pres d'un point d'achat de cet id,
delai, niveau max, argent). Prompt E des machines construites : `Triggered` cote serveur. Contact
(pads) verifie par le serveur. `WorldFx` "FruitsToBins" (serveur -> tous) pour l'effet du Fruit Picker.

## Donnees sauvegardees

`Upgrades` : niveau de chaque id (employes : 0 ou 1 ; mixeurs 2-4 : 0 = pas achete). Proprietaire :
`UpgradeService`. SchemaVersion 3 (2026-11-19 soir) : `TreeSpeed` + `TreeLuck` -> `Tree`, `BowlSize`
-> niveau de chaque mixeur (migration dans DataService, voir `sauvegarde.md`).

> **Prix affiches (2026-11-23)** : tuiles, pads, prompts et pop-up affichent le prix arrondi vers le
> HAUT (`NumberFormat.Price` : 1 525 -> "$1.53K"), l'argent du HUD vers le bas. Avant, les deux
> vers le bas : "$1.52K" des deux cotes et "Not enough money!" (panneau Customers). Voir `argent.md`.

## Configuration

`Config/Upgrades.luau` (effets, prix, `desc`, `format`, `machine`, `comingSoon`, `Messages`) ;
`Config/Gameplay.luau` : `BuyCooldownSeconds`, `BuyHoldSeconds`, `PadRepeatSeconds`, `BuyClickExtraDistance`, `BuildPushMargin`, `PadDenyFlashSeconds`,
`PromptDistance`, `PromptTexts`, `PickerCarry`, `AutoSellSeconds`, `AutoSellBatch`, `EmployeeWalkSpeed`,
`EmployeePauseSeconds`, `NpcMoveTimeout` ; `Config/Npcs.luau` (tenues, animations).

## Valeurs de depart (a equilibrer en test)

| Id | Effet niv. 1 | Par niveau | Niv. max | Prix du niveau suivant |
|---|---|---|---|---|
| Tree | 1 chute / 2.5 s, Luck x1 | chute x0.885 (min 0.6 s ; niv. 10 : 0.83 s), Luck +0.055 (niv. 10 : x1.5) | 10 (par etage) | 15 x 1.32^(niv-1) (niv. 29 -> 30 : ~35K) |
| ConveyorSpeed | 2.2 fruits / s (trajet 1.6 s) | x1.15 (trajet x (2.2 / vitesse)^0.6, min 0.75 s) | 10 (7.7 / s) | 60 x 1.3^(niv-1) (avant x1.55, revue du 2026-11-20) |
| JuiceLimit | 10 jus | +5 | 9 (50) | 30 x 1.5^(niv-1) |
| CustomerSpeed | 1 vente / 1.8 s (avant 2.5 s) | x0.942 (niv. 15 : ~0.78 s) | 15 | 80 x 1.25^(niv-1) (avant x1.45) |
| CustomerCount | 1 client | +1 | 5 | 150 x 2^(niv-1) : 150 / 300 / 600 / 1 200 (avant 300 x 2.5) |
| Collector | - | - | 1 | 25 |
| PickerSpeed | vitesse x1 (marche 15 x 0.7 = 10.5) | +0.2 | 11 (x3.0, marche ~31 ; 8 avant le 2026-11-21) | 40 x 1.6^(niv-1) (10 -> 11 : ~2.7K) |
| PickerCarry | 2 fruits portes | +1 | 8 (9 fruits ; 5 avant le 2026-11-21) | 50 x 1.9^(niv-1) : 50 / 95 / 181 / 343 / 652 / 1.2K / 2.4K (A VALIDER) |
| Blender1..4 | bol de 5 fruits | 8 / 12 / 16 / 20 | 5 | achat : - / 250 / 500 / 1 000 ; niveaux 2-5 : 100 / 200 / 400 / 800 x 1 / 1.2 / 1.4 / 1.6 (mixeur 1 / 2 / 3 / 4) (avant : 1 200 / 5 000 ; 120 / 500 / 2 000 / 8 000 x 1 / 1.5 / 2.5 / 4) |
| Operator1 / 2 / 3 / 4 | appuie au bouton | - | 1 | 150 / 300 / 500 / 800 (avant 150 / 400 / 1 500 / 5 000) |

Prix Robux : 5 + 3 x (niv-1), plafonne a **9 R$** (`Upgrades.RobuxMax`, demande du 2026-11-23) :
5 R$ (niveau 1), 8 R$ (niveau 2), puis 9 R$.

**Achat Robux d'une tuile (bouton violet, 2026-11-23) :** 3 Developer Products (Roblox : un prix fixe
par produit), `Upgrades.RobuxProducts` : "Machine Upgrade I" 5 R$ (3734912690), "II" 8 R$
(3734912738), "III" 9 R$ (3734912752). Clic sur le bouton violet (ClickDetector serveur : proprietaire,
pres de la tuile, delai `Gameplay.BuyCooldownSeconds`, tuile pas `Unbuilt`) -> memes verifications
qu'un achat en argent (`checkBuyable` : id revele, pas au max, pas verrouille) -> le serveur note la
tuile (etage, id) pour ce produit et ouvre la fenetre Roblox. Au recu (`ReceiptService`,
`DataService.GrantPurchaseOnce`, une fois par PurchaseId) : +1 niveau a la tuile notee, puis les memes
effets qu'un achat en argent (`afterBought` : etage rafraichi, `Bought`, `OnBought`). Tuile notee perdue
(autre serveur, plus de `Upgrades.RobuxPendingSeconds` = 10 min) ou deja au max : +1 niveau a la
premiere amelioration construite avec une tuile au meme prix Robux, etage le plus haut d'abord (ordre
`Upgrades.List`). Rien au meme prix (2026-11-23) : n'importe quelle amelioration encore possible, etage le plus haut d'abord. Plus rien du tout (tout au max) : argent = `Upgrades.RobuxRefundFloorShare` (0.1) x prix du prochain etage (min $100), message "Everything is maxed! +$X cash instead". Les Robux ne sont jamais perdus. Chaque recu donne est ecrit dans la
sortie (`[UpgradeService] Recu ...`). Joueur parti / sauvegarde pas chargee : recu laisse en attente.
Au demarrage, `Config/Upgrades` verifie que chaque prix Robux possible a son produit.
Test : `Debug.Call:Invoke("Upgrade", "RobuxBuy", "<Nom>", "<id>" ou "", "<PurchaseId>")` (ecrit la sauvegarde).

**Revue de l'economie (2026-11-20)** : l'arbre plafonne chaque etage (au max 1.2 fruit/s, etage 1 :
~9.4 $/s). Le mixeur 1 (bol 12 + operateur : 1.34 jus/s) suit deja l'arbre au max, le tapis aussi
(2.2/s des le niveau 1), et ~2 clients toutes les 1.65 s suffisent. Tout le reste fait a peine monter
l'argent : tout maxer a l'etage 1 coutait ~159K (32 x l'etage 2) et un joueur qui achete tout ce qui
brille restait coince a l'etage 1. Prix de cette fin baisses (catalogue de l'etage 1 : ~27K, rien
retire) ; clients plus rapides au depart (sinon les premiers "Upgrade Tree" ne rapportaient rien).
Pour que chaque machine serve vraiment, il faudrait un arbre qui monte plus haut (A DECIDER).

## Tests (Studio)

```
game.ServerStorage.Debug.Call:Invoke("Upgrade", "Buy", "<Nom>", "Tree")       -- achat comme un clic
game.ServerStorage.Debug.Call:Invoke("Tree", "SetLevel", "<Nom>", 18)          -- arbre au niveau 18 (ecrit la sauvegarde !)
game.ServerStorage.Debug.Call:Invoke("Upgrade", "SetLevel", "<Nom>", "Blender2", 0) -- annuler un achat de test (ecrit la sauvegarde !)
game.ServerStorage.Debug.Call:Invoke("Upgrade", "Reset", "<Nom>")              -- niveaux de depart (ecrit la sauvegarde !)
```

## Problemes connus / a faire

- **Employes invisibles loin de la camera (2026-11-27)** : `NpcRig.Spawn` pose le tag
  `Npcs.FarHideTag` ; le client les rend invisibles au-dela de `Gameplay.NpcMaxDistance` (260
  studs, 120 sur telephone ou en Low Quality, la hauteur comptant 2.5 fois). Rien ne change cote
  serveur. Detail et mesures : `docs/perf-mobile.md`. Verifie sur les PNJ de l'apercu, pas encore
  sur de vrais employes en mouvement.

- Waiter (2026-11-20) : teste en Studio (1 joueur, PC) : pad vert a cote de Take Juices, achat en
  marchant dessus, pad violet qui apparait, pas de fenetre Robux a l'embauche, fenetre apres
  descendre / remonter, 9 jus portes, vitesse 7.5. Pas teste : telephone, 2 joueurs, etages 2+,
  regard en jeu sur le fondu du pad (seulement l'etat avant / apres). Prix ($400) et debit A VALIDER.

- Auto Sell (2026-11-20) : pass pas encore cree sur Roblox (`passId = 0`) ; teste en Studio avec
  l'attribut `AutoSell` pose a la main (table 5 -> 0 en 1.5 s, etiquette "ACTIVE"). Pas teste : vrai
  achat Robux, 2 joueurs, telephone. Debit (4 jus/s) A VALIDER.

- Teste le 2026-11-19 : les 3 employes apparaissent et travaillent (fruits portes, jus au comptoir,
  ventes). Pas teste : 2 joueurs, telephone, longue duree (employe bloque ?).
- Rythme du Fruit Picker (marche + 6 fruits) a equilibrer en jeu reel.
- Teste le 2026-11-19 soir (Studio, 1 joueur) : achats de tous les nouveaux ids, pad de l'arbre qui
  repete (niveau 5 -> 9 en 3 s), panneaux et textes, decor par niveau (captures). Pas teste :
  telephone (taille des textes des tuiles), 2 joueurs, achat au vrai clic sur les nouvelles tuiles
  (achats faits avec l'outil de test).
- Les prix (arbre, tapis, mixeurs) sont a equilibrer en jouant.
- `Tree.SetLevel` (test) ne remet pas a jour l'etiquette du pad tout de suite (prochaine arrivee).
