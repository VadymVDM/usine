# Systeme : Chaine de production (arbre, ramassage, bacs, mixeurs, jus)

**Statut :** en cours (boucle complete en playtest Studio le 2026-11-19 : E sur les fruits ->
inventaire -> etagere -> mixeur -> table a jus -> mains -> comptoir ; 2 joueurs et telephone non testes)
**Derniere mise a jour :** 2026-11-20 (animation des fruits sur le tapis ; le tapis prend les fruits les plus rares d'abord ; etagere contre le mur)

## Role

> **Tour d'etages (2026-11-20, phase 1b lot 3)** : toute cette chaine existe sur CHAQUE etage
> (`Floors.FloorN`), avec ses ameliorations (`Floors[n].Upgrades`). L'arbre de l'etage n ne fait
> tomber que les 10 fruits de la rarete n ; l'etagere a 10 caisses `Bin1..10` = ces 10 fruits, sur UNE
> rangee (etagere ramenee a la profondeur d'une caisse le 2026-11-20 : la partie vide derriere est retiree ;
> puis reculee contre le mur du fond, plancher allonge jusqu'a elle). Caisses dans l'ordre des raretes :
> `Bin10` (la plus rare) au bout cote tapis (boite d'alimentation), `Bin1` (communs) au bout le plus loin
> (`Fruits.LocalIndex`). **Depuis le 2026-11-20 (retour de test)** : le pad Drop Fruits de
> n'importe quel etage prend TOUS les fruits du plateau, quel que soit leur etage d'origine ; chaque
> fruit va dans la caisse de sa rarete (`Bin<rarete>`) **de SON etage** (`Fruits.floor`, 2026-11-20 soir) :
> deposer a l'etage 1 un fruit de l'etage 3 le fait voler jusqu'a la caisse de l'etage 3 (si cet
> etage n'est pas charge, il reste ici). "x12" = total, le fruit montre = celui qu'elle contient le plus. Le jus garde la
> valeur de SON fruit (`Fruits.FloorValues[fruit.floor]`). Le serveur trouve l'etage du
> joueur par la hauteur de son personnage (`FloorService.GetPlayerFloor`). Voir `tour-etages.md`.

L'arbre fait tomber des fruits ; le joueur les ramasse **en marchant dessus** (ils volent jusqu'a un **plateau
sur sa tete** et s'y empilent en vrac), les depose en se tenant sur le **pad "Drop Fruits"** devant
l'etagere (1 caisse par fruit) ; le tapis
remplit le bol des mixeurs ; **E sur un mixeur** = tous les fruits du bol deviennent des jus d'un
coup (1 fruit = 1 jus) ; le joueur prend les jus sur le pad "Take Juices" (pile dans les mains,
bras tendus) et les pose sur le pad "Drop Juices" du comptoir (voir `clients.md`). Tirage des fruits et Index : voir aussi `fruits.md`.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/TreeService.luau` | serveur | Chute, tirage selon Luck, garantie, "Tree full!", pommes de la premiere visite, decouvertes (seul a ecrire `DiscoveredFruits`), stade de l'arbre (`Tree.Body`) |
| `src/client/Controllers/FruitFxController.luau` | client | Anime la chute des fruits (le serveur les pose deja a leur place) + effets d'apparition |
| `src/server/Services/ProductionService.luau` | serveur | Inventaire (attributs joueur), prompts E de l'etagere, de la table et des mixeurs, caisses ("x12"), tapis -> bols, mixage, table a jus, jus dans les mains ; API pour le comptoir et les employes |
| `src/server/Services/WorkerService.luau` | serveur | Employes R6 (Fruit Picker, operateurs des mixeurs) : voir `ameliorations-employes.md` |
| `src/client/Controllers/InventoryController.luau` | client | Fruits qui volent (sol -> plateau, plateau -> caisses), texte "+3 Apple" ; cache la barre Roblox (Backpack) |
| `src/client/Controllers/TrayController.luau` | client | Plateau sur la tete de chaque joueur (attribut `TrayFruits`), fruits empiles en vrac, "12/20" / "FULL!" pour le joueur local |
| `src/client/Controllers/CarryPoseController.luau` | client | Pose des bras : bras leves sous le plateau quand `TrayFruits` ou `HandJuices` n'est pas vide (joueurs), bras tendus devant si `CarryPose` (employes, clients) ; transition douce |
| `src/client/Controllers/HandStackController.luau` | client | Plateau de jus sur la tete (attribut personnage `HandJuices`) : plateau + gobelets ancres qui suivent la tete, penchent et rebondissent ; vol table -> plateau et plateau -> comptoir, "pop" de plus en plus aigu |
| `src/shared/Util/HandStack.luau` | partage | Place d'un gobelet sur le plateau de jus (`TrayOffset`, `SlotOffset`, `WorldSlot`), lecture de `HandJuices` |
| `src/client/Controllers/PadController.luau` | client | Detecte localement l'arrivee sur les 4 pads d'action de sa base et envoie `PadEnter` (pas de delai avant l'animation) ; effet local du pad (voir plus bas) |
| `src/shared/FruitModels.luau` | partage | Modeles des fruits (`CreateFruit` : boule + creux + queue + feuille, provisoire) et des gobelets (`CreateCup`, voir "Modele du gobelet"), generes depuis la Config |
| `src/shared/Util/WorldLabel.luau` | partage | Textes 3D ("n/max" + "!" rouge, "Tree full!") au style du jeu |
| `src/shared/Config/Fruits.luau` | partage | 100 fruits |
| `src/shared/Config/Gameplay.luau` | partage | Plafonds, capacites, mixeurs (`MaxBlenders`, `BlendSeconds`, `ConveyorTravelSeconds` / `ConveyorTravelMin`, operateurs), table a jus (`JuicePileColsByTier`, `JuiceTableTierLevels`), positions d'affichage (`TreeHang*` retires le 2026-11-20 : plus de fruits accroches a l'arbre) |
| `src/client/Controllers/BlenderFxController.luau` | client | Animation des 4 mixeurs : fruits qui roulent sur le tapis et s'empilent dans le bol, demarrage en "gelee", jus qui monte (couleur melangee), lame, moteur, "pop", gobelets qui sautent du bec a la table |
| `tools/build-map/02c-base-production.luau` | Studio | Etagere, tapis, `buildBlender(index, origin)` x 4, table a jus |
| `src/client/Controllers/TreeFxController.luau` | client | Animation de l'arbre qui s'ameliore (elan, pop, rebonds, feuilles qui volent) |
| `src/client/Fx/Jelly.luau` | client | Deformation "gelee" (squash & stretch + pliage) d'un groupe de pieces, ressorts, `Boing()` |

## Fonctionnement

- **Sortie d'un pad (2026-11-20)** : on entre sur un pad avec le test exact de la zone, mais une
  fois dessus on n'en sort qu'a `Gameplay.PadExitMargin` (1.5) studs du bord ou
  `PadExitHeight` (12) studs au-dessus (un saut ne compte pas). Meme regle cote client
  (`PadController` : son / effet, remote `PadEnter`) et serveur (`UpgradeService.checkPads` :
  achat). Avant, rester au bord ou sauter refaisait l'achat et le "clic".

- L'arbre et la production d'une base demarrent quand le joueur a sa base (`BaseService.OnBaseAssigned`)
  ET sa sauvegarde (`DataService.OnPlayerLoaded`), dans n'importe quel ordre ; ils s'arretent dans
  `OnBaseReleased`. Tout ce qui est cree va dans `Base.Dynamic` (`GroundFruits`, `Production`,
  `TreeFullLabel`).
- Chute : 1 fruit toutes les `Upgrades.TreeDropSeconds(niveau)` secondes (2.5 s au niveau 1, x0.885
  par niveau, ~0.83 s au niveau 10 ; niveau = Upgrades `Tree`, pad "Upgrade Tree"),
  a un point au hasard sous le feuillage du stade actuel (anneau `trunkClear`..`dropRadius` de
  `Config/Tree`, dans `Tree.FruitArea`). Depuis le 2026-11-19 le serveur pose le fruit **a sa place
  finale** et met les attributs `DropStart` (heure serveur), `DropHeight`, `DropTime` (+ `NewFruit`) ;
  le client (`FruitFxController`) le fait tomber du feuillage en tournant puis rebondir, image par
  image (fluide), avec les effets. Duree = `FruitFallSeconds * sqrt(hauteur / FruitFallHeight)`.
  Un fruit qui tombe ne peut pas encore etre ramasse (ramassable apres `DropTime`).
- A `Gameplay.MaxGroundFruits` (30) au sol : l'arbre s'arrete et "Tree full!" s'affiche dans le
  feuillage, **toujours au premier plan** (plus cache par les poutres : le verger est sous un puits
  de lumiere).
- Juste sous "Tree full!", toujours visible : **"<Nom> Lv N"**, ex. "Golden Tree Lv 15"
  (`TreeLevelLabel`, meme style, `Gameplay.TreeLevelText`, decalage `TreeLevelLabelDrop`). Nom =
  `Tree.Names[etage]` (`Config/Tree.luau`) : un rang qui monte avec l'etage (Fruit, Lucky, Golden,
  Crystal, Magic, Royal, Mystic, Cosmic, Galaxy, Divine + " Tree") ; pas un nom de fruit (l'arbre
  donne les 10 raretes) ni de rarete. "Tree" si l'etage n'a pas de nom. N = niveau de l'arbre (Upgrades `Tree`),
  remis a jour par `updateStage` (achat sur le pad, rebirth, boucle de l'arbre).
- **L'arbre change a chaque niveau** (2026-11-19 soir) : modele du stade, agrandi selon le niveau,
  et les fruits debloques pendent dedans. Voir `fruits.md` (Arbre qui grandit).
- Tirage, garantie, decouverte, premiere visite : inchanges (voir `fruits.md`).
- **Ramasser en marchant dessus** (2026-11-19 ; avant : prompt E "Apple / Pick up" sur chaque
  fruit, retire) : 10 fois par seconde, le serveur prend les fruits au sol (pas en chute) a moins de
  `WalkPickupRadius` (3.2, a plat) du proprietaire de la base (`TreeService.TakeNear`, les plus
  proches d'abord), dans la limite du plateau (`CarryCapacity` 20 au depart, puis amelioration FruitCarry du menu Upgrade, `ameliorations-joueur.md`). Le client fait voler chaque
  fruit jusqu'au plateau + son "pop" (`Sounds.Pickup` = "cartoon_pop") (`Feedback` "Pickup").
  Plateau plein et fruit sous les pieds : message "Your inventory is full!".
- **Plateau sur la tete** (2026-11-19, remplace la barre Roblox et ses outils "Apple x5") : le
  serveur pose sur le **personnage** l'attribut `TrayFruits` ("Pear;Apple;Orange", ordre du
  ramassage, remis apres une reapparition). Le Fruit Picker (employe) a le meme attribut et le
  meme plateau depuis le 2026-11-20 (TrayController suit aussi les modeles tagues `CarryPoseRig`).
  `TrayController` (client) dessine pour CHAQUE joueur un
  plateau en bois (3.4 x 3.4, bords) soude a la tete et les fruits a `TrayFruitScale` (0.5) :
  20 places en tas (couches 9 / 4 / 4 / 2 / 1), position et inclinaison tirees au hasard une fois
  (graine = numero de la place : meme tas pour tous, il ne bouge pas). Un nouveau fruit tombe sur
  sa place avec un rebond et le plateau plonge un peu ; pour le joueur local il apparait a la fin
  du vol depuis le sol (0.35 s + 0.05 s par fruit). Joueur local : "12/20" au-dessus, "FULL!"
  rouge quand c'est plein. Plateau vide = plus de plateau. Pieces locales (rien cote serveur),
  sans collision ni masse. La barre Roblox (Backpack) est cachee. Attributs joueur `InvFruits`
  ("Apple=3;Orange=1", ordre de la Config) et `InvMax` toujours poses (tests).
- **Effet des pads d'action** (2026-11-19, client seulement, `PadController`) : en montant sur un
  des 4 pads de sa base, le dessus (`PadTop`) s'enfonce de 0.16 stud avec un rebond (ressort), le
  contour (`PadGlow`) flashe blanc puis pulse tant qu'on reste dessus, un cadre lumineux s'agrandit
  et s'efface (copies du contour dans la camera), son `PadStep`. En descendant, le dessus remonte
  avec un rebond puis tout revient exactement a l'etat d'origine. Reglages en haut de la section
  "Effet visuel du pad" du fichier.
- **Pad "Drop Fruits"** (orange, `Production.FruitDropPad`, sur le plancher devant l'etagere) :
  se tenir dessus (`PadZone`, detection immediate par le client `PadController` -> remote
  `PadEnter`, puis test serveur 10 fois / s tant qu'il reste dessus ; proprietaire seulement, delai
  `PadActionSeconds`) = tous les fruits du plateau vont dans leur caisse (`BinN`, N = rarete du
  fruit, sur l'etage DU FRUIT meme si on depose ailleurs) ; les fruits volent du plateau vers les caisses,
  y compris vers un autre etage (client `InventoryController`). Plus de prompt E a l'etagere.
  Chaque caisse non vide montre son fruit et **"x12"** au-dessus (`BinLabelMaxDistance`).
- **Mixeurs** (refonte du 2026-11-19 : avant, un seul mixeur `Production.Press` pressait tout seul
  1 fruit toutes les 1.5 s ; le joueur n'avait rien a faire). `Production.Blenders.Blender1..4`
  (`Gameplay.MaxBlenders` = 4) : le 1 est offert, les 2 a 4 s'achetent dans l'ordre (Upgrades
  `Blender2..4`, voir `ameliorations-employes.md`). **Chaque mixeur a 5 niveaux** (2026-11-19 soir,
  Upgrades `Blender1..4`, panneau suspendu au-dessus de lui) : son bol prend 5 / 8 / 12 / 16 / 20
  fruits (avant : "Bigger Bowl", la meme taille pour tous les bols), et son look change.
  - **Bol** : le tapis envoie `ConveyorSpeed` fruits par seconde (2.2 / s au niveau 1, panneau
    Conveyor ; avant : `FeedSeconds` fixe 0.45 s). Il prend le fruit **le plus rare** des caisses
    (2026-11-20 ; avant : le moins cher) : rarete 10 d'abord, pommes et autres communs en dernier ;
    a rarete egale, le plus cher (etage le plus haut) d'abord (`RAREST_FIRST`), et l'envoie au bol **le moins rempli** des mixeurs possedes qui ne mixent pas (fruits arrives +
    fruits sur le tapis < taille de CE bol). Le fruit arrive apres le trajet : `ConveyorTravelSeconds`
    (1.6 s) x (2.2 / vitesse)^0.6, au moins `ConveyorTravelMin` (0.75 s). Le serveur pose sur
    `Production` les attributs `ConveyorTravel` (meme duree pour l'animation) et `ConveyorRate`
    (les lattes du tapis defilent plus vite, LevelLookController).
    Au-dessus du bol (au-dessus du panneau du mixeur) : "3/5" (WorldLabel) + pastille "!" quand il est plein.
  - **Mixer (E)** : prompt "Blender / Blend" sur le panneau (`Panel`), actif si le mixeur est
    possede, ne tourne pas et a au moins 1 fruit. Serveur : proprietaire de la base, distance
    (`PlayerCheck.CanReach`, portee + 4), delai (`PromptCooldownSeconds`), etat. Le mixage dure
    toujours `BlendSeconds` (2.5 s), 1 ou 20 fruits ; puis les jus arrivent d'un coup sur la
    table (grille, couches). Un fruit qui arrive pendant le mixage attend le mixage suivant.
  - **Table trop petite (2026-11-20, retour de test)** : avant, le mixage etait refuse ("Juice
    table is full!") des que le bol entier ne tenait pas sur la table, meme table vide (bol de 20,
    table de 10 au niveau 1) : le message mentait. Maintenant le mixage demarre toujours ; a la fin,
    le mixeur pose sur la table **autant de jus qu'elle peut en prendre** et garde le reste
    (`bowl.held`, attribut `HeldJuices`) : message "Juice table is full!" (vrai cette fois). Le jus
    en attente **coule tout seul** des que la table a de la place (boucle 0.2 s, `pourHeld`, gobelets
    qui sautent du bec). Tant qu'il reste du jus dans un mixeur : le tapis ne lui envoie plus de
    fruits, le prompt E est cache et `startBlend` refuse ("Holding" ; l'operateur attend). Client :
    le jus reste visible dans le bol a la hauteur `HeldJuices / BowlMax` (au moins 20 %), petit
    hoquet a chaque versement. Non sauvegarde (comme les bols).
  - Le contenu des bols n'est pas sauvegarde (vide a chaque arrivee dans la base).
- **Table a jus : pad "Take Juices"** (rose, `Production.TakeJuicePad`, devant la table ; avant
  le 2026-11-19 : prompt E "Juice Table / Take juices"). Se tenir dessus (`PadZone`, `PadEnter`
  a l'arrivee puis test serveur 10 fois / s, proprietaire seulement, delai `PadActionSeconds`) : les jus du haut de la table
  (`Production.JuicePile`) vont dans les mains ; messages "No juice to take yet!" / "Your hands are
  full!" seulement en montant sur le pad. **Table surelevee** (2026-11-19 soir, "la c'est par
  terre" : avant, une palette au sol) : dessus a 3.4, 3 tailles selon Juice Table (JuiceLimit
  1-3 / 4-6 / 7-9, voir `ameliorations-employes.md`). Gobelets en bloc compact centre sur la table,
  `JuicePileColsByTier` (6 / 9 / 12) colonnes x `JuicePileRows` (4), en couches ; quand la table
  grandit, les gobelets deja poses se replacent (`relayoutJuices`). Les gobelets se posent sur le
  bas de `Production.JuicePile` (attribut `Raised` de `JuicePallet`). Au-dessus de la table : "16/24" (+ "!" rouge quand elle est pleine) et,
  plus haut, le **prix de vente total des jus poses** en vert ("$1.31B", somme des `value` des fruits,
  meme prix qu'au comptoir ; cache si la table est vide ; `JuiceValueLabel`, `Gameplay.JuiceValueLabelLift`,
  `JuiceValueColor`, ajoute le 2026-11-19). Jus portes (`JuiceCarryCapacity` 18 au depart, soit 2 couches de 3 x 3 ; 12 avant le 2026-11-20 ; plus avec JuiceCarry du menu Upgrade) : **plateau sur la tete**, comme les
  fruits (demande du 2026-11-19 ; avant : pile devant le torse, bras tendus). Le serveur pose
  seulement l'attribut personnage `HandJuices` ("Apple;Orange", ordre de la pile), `CarryPose` reste
  faux (bras leves sous le plateau par `CarryPoseController` des qu'un plateau est porte, 2026-11-20) ; chaque client dessine le plateau (`HandStackController`, couches de 3 x 3, gobelets ANCRES,
  aucune physique). Si le plateau des fruits est aussi sur la tete, le plateau de jus passe
  au-dessus (`JuiceTrayFruitLift` 2.4). Prendre : Feedback "TakeJuice" avec
  `from` (position de chaque gobelet retire) -> les gobelets sautent un par un jusqu'aux mains,
  la pile s'ecrase a chaque arrivee. Poser au comptoir : `CustomerService` met `PopFrom` (place
  sur le plateau, `HandStack.WorldSlot`), `PopIndex`, `PopAt` sur chaque gobelet du comptoir ; ils
  sautent du plateau au comptoir, la pile se vide au meme rythme. Attributs joueur
  `HandJuices` / `HandMax` (compteur). Les jus portes restent apres une mort (redessines).
- Comptoir et ventes : `clients.md`. Employes (Fruit Picker qui ramasse, operateurs qui appuient
  sur le bouton de leur mixeur), Waiter (porte 9 jus de la table au comptoir sur un plateau sur la tete,
  dessine par `HandStackController` comme celui du joueur) et pad Auto Sell : `ameliorations-employes.md`.

### Animations (client seulement, 2026-11-19)

Tout est dessine par le client ; le serveur ne voit rien et ne decide rien. Au-dela de 150 studs
(170 pour l'arbre) de la camera : pas d'animation.

- **Gelee (`Fx/Jelly`)** : on capture les pieces une fois (position, rotation, taille dans le repere
  d'un pivot = pied de l'objet), puis a chaque image : etirement `sy` / `sxz` (volume garde :
  `sxz = 1 / sqrt(sy)`), pliage `bend` (le sommet se decale, courbe en h^2, chaque piece s'incline
  sur la courbe), `grow` par piece. `Restore()` remet exactement la forme de depart. Ressorts
  (`Spring`, `Step`, `Resting`) et `Boing(cle, pieces, pivot, force)` tout fait.
- **Mixeurs (`BlenderFxController`)**, une animation par mixeur, sur les attributs de `BlenderN` :
  - `Pulse` / `PulseFruit` : le fruit roule de `ConveyorStart` a `ConveyorTurn` (montee), longe la
    rangee jusqu'a `FeedPoint` de son mixeur puis saute dans le bol (total `ConveyorTravelSeconds`).
    Depuis le 2026-11-20 : il sort de la boite en "pop" (petit -> grand avec depassement, petite
    chute), accelere au depart, sautille sur les lattes, tourne en douceur dans les virages
    (coins arrondis), puis saute dans le prolongement du tapis en continuant de tourner et en
    gonflant un peu ; petites gouttes de sa couleur a l'arrivee dans le bol. Reglages en haut du
    module (`SPAWN_*`, `BUMP_*`, `CORNER_*`, `HOP_*`).
  - `BowlFruits` : les fruits restent **empiles** dans le bol (grille 3 x 3 par couche, couches
    decalees, a partir du marqueur `BowlFloor` ; ils suivent la machine quand elle se deforme).
    Petit plop + son a chaque fruit, rebond plus fort quand le bol est plein.
  - `BlendStamp` : gros demarrage (ecrasement + torsion), gouttes, le jus monte (0.55 s) avec la
    couleur moyenne des fruits, la machine se plie / se deplie en rythme pendant `BlendSeconds`,
    lame, moteur. Le jus (`Juice`) est cache au repos (`LocalTransparencyModifier`, client).
  - `PopStamp` : "pop" (la machine s'etire vers le haut), le jus redescend ; les gobelets crees
    avec `PopFrom` / `PopIndex` / `PopAt` sautent tous du bec (`SpoutTip`) jusqu'a leur place sur
    la table, un par un tres vite (0.06 s d'ecart). Gobelets sortis il y a plus de 1.5 s (arrivee
    dans la partie) : pas d'animation.
  - Pendant la construction d'un mixeur achete (`BuildStamp`, MachineFx), pas de deformation 4 s.
  L'utilisateur veut que l'animation porte sur la machine elle-meme (valide le 2026-11-19).
- **Arbre (`TreeFxController`)**, sur l'attribut `TreeLevel` du dossier `Tree` quand il monte
  (achat sur le pad "Upgrade Tree" ; le serveur vient de reposer l'arbre du nouveau niveau) : le
  modele part 20 % plus petit (35 % si le stade change, nouveau modele), puis pop (jaillit plus haut
  que sa taille, vague de feuillage qui gonfle du bas vers le haut, 16 feuilles qui volent,
  etincelles, onde au sol, eclair de lumiere, "boing" + "ding"), il se balance et rebondit ~1.3 s.
  Le mode "upgrade" (elan 0.32 s : se tasse, s'elargit, frisson) reste pour `TreeFxController.Play`.
  Pieces animees : `Tree.Body` (Model) s'il existe, sinon les pieces de `Tree` sauf le sol ;
  feuillage = attribut `Leaf` ou nom `Leaves*` (plus de pommes ni de fruits accroches depuis le 2026-11-20).
- Sons : `BlenderMotor` (rbxassetid 365965609, "Blender" de Roblox), `BlenderPlop`, `TreeBoing`,
  `TreeChime`, `MachineBoing` dans `Config/Sounds.luau` ; coupes si le reglage Sons est off.

## Remotes

| Nom | Sens | Contenu |
|---|---|---|
| `Feedback` | serveur -> le joueur | "Pickup" { items = { {id, pos} } }, "Deposit" { floor, ids }, "TakeJuice" { count } |
| (attributs) | serveur -> tous | `BlenderN` : `Pulse`, `PulseFruit`, `BowlFruits`, `BowlCount`, `BowlMax`, `Owned`, `Blending`, `BlendFruits`, `BlendStamp`, `PopStamp`, `HeldJuices` ; gobelets : `PopFrom`, `PopIndex`, `PopAt` |
| `WorldFx` | serveur -> tous | (etage, "FruitsToBins", { from, ids }) : fruits du Fruit Picker qui volent vers les caisses |

Actions : prompts E (`Triggered` serveur), dont "Blend" sur chaque mixeur. Verifications serveur :
proprietaire de la base, distance (`PlayerCheck.CanReach`), delai (`PlayerCheck.Cooldown`), etat
(place libre, fruits, jus, mixeur possede et a l'arret).

## Donnees sauvegardees

`DiscoveredFruits` (TreeService). Niveaux `Tree`/`ConveyorSpeed`/`JuiceLimit`/
`Blender1..4`/`Operator1..4` lus dans `Upgrades`. Ne sont PAS sauvegardes : fruits au sol,
inventaire, jus dans les mains, caisses, bols des mixeurs, table a jus.

## Configuration

`Config/Fruits.luau`, `Config/Gameplay.luau` (arbre, joueur, presse, affichage), `Config/Upgrades.luau`.
Couleurs des corps de fruits : table `BODY_COLORS` de `FruitModels.luau` (visuel seulement).

## Tests (Studio)

```
game.ServerStorage.Debug.Call:Invoke("Tree", "Drop", "<Nom>", 5)          -- 5 chutes tout de suite
game.ServerStorage.Debug.Call:Invoke("Tree", "SetLevels", "<Nom>", 1, 2)  -- Speed 1, Luck 2 (ecrit la sauvegarde !)
game.ServerStorage.Debug.Call:Invoke("Production", "Get", "<Nom>")        -- inventaire, mains, caisses, jus, sol
game.ServerStorage.Debug.Call:Invoke("Production", "Do", "<Nom>", "PickAll")   -- ramasser comme avec E
game.ServerStorage.Debug.Call:Invoke("Production", "Do", "<Nom>", "Shelf")     -- deposer (teleporte sur le pad Drop Fruits)
game.ServerStorage.Debug.Call:Invoke("Production", "Do", "<Nom>", "TakeJuice") -- teleporte sur le pad Take Juices
game.ServerStorage.Debug.Call:Invoke("Production", "Do", "<Nom>", "FillBins")  -- 20 pommes dans les caisses
game.ServerStorage.Debug.Call:Invoke("Production", "Do", "<Nom>", "Blend2")    -- E sur le mixeur 2 (teleporte devant)
```
`Production.Get` renvoie aussi `Bowls` (fruits, sur le tapis, mixage) et `BowlMax`.

## Problemes connus / a faire

- Modeles de fruits provisoires (boule + queue + feuille) : de vrais fruits viendront (prompt a
  venir de l'utilisateur).
- Le serveur fait confiance a la position du personnage (normal sur Roblox) : un tricheur qui se
  teleporte ne ramasse que plus vite dans SA base (pas d'argent ni d'objet d'une autre base).
- Fruits au-dela du 30e : pas de caisse (affichage), mais ils seraient comptes et mixes.
- Mixeurs (2026-11-19) : teste en Studio a 1 joueur (bol qui se remplit 1 fruit / 0.45 s, operateur
  qui mixe, 5 jus d'un coup sur la table, fruits empiles et jus qui monte mesures cote client). Pas
  vu en mouvement par l'utilisateur ; telephone non teste.
- Jus en attente dans le mixeur (2026-11-20) : pas teste en Studio (seulement build Rojo + Selene).
- Les mixeurs voisins sont a 1.5 stud : pendant un gros mixage, les bols qui se plient peuvent se
  toucher un instant (visuel seulement).
- Le pad Auto Sell et le joueur prennent les jus sur la meme table (normal).
- Le jus des mixeurs (`Juice`) est opaque dans 02c (une piece transparente derriere du verre Glass
  n'est pas dessinee par Roblox) ; le client le cache au repos et le montre pendant le mixage.
- Animations (mixeur, arbre, boing des machines a l'achat) : validees par l'utilisateur en jeu le
  2026-11-19 ("parfaites") ; telephone non teste (cout des mises a jour de taille chaque image, a
  surveiller).
- Non teste : 2 joueurs, telephone, manette.

## Modele du gobelet (`FruitModels.CreateCup`, refait le 2026-11-19)

Brique a studs, 8 pieces : pied blanc (0.78, Inlet dessous), jus bas (0.88) et jus haut (1.0, piece
principale `Cup`) a studs sur les 4 cotes (couleur `juiceColor`), bord blanc a studs (1.04),
couvercle, paille rose coudee, et le **fruit voxel en miniature** (0.3 de haut, clone de
`ReplicatedStorage.FruitAssets.<FruitId>` ; boule de la couleur du fruit s'il manque) sur le couvercle.
- Pivot au sol (centre-bas). Hauteur totale = `CupHeight` 1.6 : la pile ne s'interpenetre pas.
- Largeur max 1.04 : grille `JuiceCupSpacing` 1.1 ; plateau de jus : meme grille (3 x 3) ;
  employes : gobelets a +-0.55 (`NpcRig`). Etages de largeurs differentes : pas de face commune.
- Non ancre : toutes les pieces (et le mini fruit) soudees a `Cup`.
- `ModelStreamingMode = Atomic` (fruits aussi) : avec StreamingEnabled, les pieces arrivaient une
  par une chez le client ; un effet qui fait `PivotTo` trop tot (saut du bec) laissait les pieces en
  retard a 10-16 studs = "morceaux de jus par terre dans tous les sens" (34 gobelets casses en 1 min
  de test, 0 apres la correction, 2026-11-19).
- Limite connue : jus blanc (Coconut) = gobelet presque tout blanc.
