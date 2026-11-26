# Systeme : Fruits, raretes, arbre et index

**Statut :** en cours (Config, arbre construit par code qui change a chaque niveau, 100 fruits voxel + effets, Index avec CLAIM)
**Derniere mise a jour :** 2026-11-23 (bonus de chance etages 1 et 2) ; 2026-11-20 soir (arbre : 91 paliers, theme par etage ; avant : Index range par rarete + chance "1 in X")

## Role

Definit les 100 fruits (10 etages x 10 raretes), comment l'arbre de chaque etage les fait tomber,
comment on les decouvre (animation + Index).

> **Changement du 2026-11-20** : chaque etage a les 10 raretes (Common a Infinity), on lit le
> tableau des fruits par ligne. Remplace "1 etage = 1 rarete" (2026-11-19). Le code suit encore
> l'ancienne regle.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/shared/Config/Fruits.luau` | partage | 100 fruits : id, nom, rarete, valeur, couleur du jus, poids (fait le 2026-11-19) |
| `src/server/Services/TreeService.luau` | serveur | Tirage des fruits, garantie, decouvertes, pose l'arbre du niveau (Tree.Body), attributs de chute (voir `chaine-production.md`) |
| `src/server/Lib/TreeBuilder.luau` | serveur | Construit l'arbre d'un etage pour un niveau (pieces, theme, ornements, couronne) + ses mesures (rayon / hauteur de chute, texte) (2026-11-20 soir) |
| `src/shared/Config/Tree.luau` | partage | Taille de l'arbre par palier (`Growth`, `LateGrowth`), theme de chaque etage (`Themes`), niveau ou chaque partie change (`Slots`), noms des arbres |
| `src/shared/FruitModels.luau` | partage | `CreateFruit` clone le fruit voxel `ReplicatedStorage.FruitAssets.<Id>` + effets de rarete ; repli sur l'ancienne boule s'il manque. `GetBodyColor` |
| `src/client/Controllers/FruitFxController.luau` | client | Chute fluide + effets d'apparition (feuilles, cubes, anneau, colonne de lumiere, "NEW!") |
| `tools/build-assets/fruits-voxel.luau` | Studio | Dessine les 100 fruits en cubes et les range dans `ReplicatedStorage.FruitAssets` (a relancer apres un changement de dessin) |
| `tools/build-map/02b-base-tree.luau` | Studio | Jardiniere, `FruitArea`, `TreeRoot`, `TreeLabelAnchor` (+ les 5 anciens modeles `ServerStorage.TreeStages.Stage1..5`, **plus utilises** depuis le 2026-11-20 soir) |
| `src/client/Controllers/IndexController.luau` | client | Menu Index : grille des 100 fruits, bouton CLAIM (2026-11-20) |
| `src/server/Services/IndexService.luau` | serveur | Etat de l'Index envoye au joueur, recompense CLAIM (seul a ecrire `ClaimedFruits`) |

## Fonctionnement

> **Regle du 2026-11-20 (remplace "1 etage = 1 rarete")** : **chaque etage a les 10 raretes**.
> Code a jour (lot 4b, 2026-11-20) : voir "Dans le code" plus bas. Pas encore teste en jeu par l'utilisateur.

### Quels fruits a quel etage

- On garde les 100 fruits du tableau plus bas (noms, raretes, modeles, effets : rien ne change).
- **Etage n = la ligne n du tableau** : le n-ieme fruit de chaque rarete. Exemple, etage 1 :
  Apple (Common), Strawberry (Uncommon), Dragon Fruit (Rare), Mangosteen (Epic), Golden Apple
  (Legendary), Fire Mango (Mythic), Angel Apple (Godly), Moon Melon (Celestial), Error Apple
  (Glitched), Rainbow Apple (Infinity).
- Les ids ne changent pas : les fruits deja decouverts dans les sauvegardes restent valables.

### Chances (A VALIDER en jeu)

Les 10 fruits de l'etage peuvent tomber des le debut, avec une chance qui baisse selon la rarete.
Exemple de depart (Luck niveau 1) :

| Rarete | Chance environ |
|---|---|
| Common | presque toujours (~68 %) |
| Uncommon | 1 sur 4 |
| Rare | 1 sur 20 |
| Epic | 1 sur 75 |
| Legendary | 1 sur 300 |
| Mythic | 1 sur 1 000 |
| Godly | 1 sur 3 000 |
| Celestial | 1 sur 8 000 |
| Glitched | 1 sur 20 000 |
| Infinity | 1 sur 50 000 |

Rendues plus rares le 2026-11-20 soir (avant : 3, 10, 30, 100, 300, 1 000, 3 000, 10 000, 50 000 ;
"on peut pas l'avoir facilement", tout l'Index = au moins 10 h). Simulation (arbre monte au niveau
10 en ~20 min, puis au max), temps median pour voir chaque rarete **sur un etage** : Rare ~40 s,
Epic ~2 min, Legendary ~6 min, Mythic ~13 min, Godly ~25 min, Celestial ~55 min, Glitched ~2 h,
Infinity ~4.5 h ; tout l'etage ~6 h. On ne decouvre que sur l'etage ou on est : les 100 fruits
demandent bien plus de 10 h (sans boost de chance Robux).

- La chance est affichee "1 in 3,000" dans l'Index et au-dessus d'un fruit rare (Rare+) qui tombe.
- **Luck** (amelioration de l'arbre, par etage) : rend les raretes Uncommon+ plus frequentes
  (x1 au niveau 1 jusqu'a x1.5 au niveau 10 ; x5 puis x4 avant le 2026-11-20 nuit : l'arbre mise
  maintenant sur la vitesse, voir "Arbre qui grandit" ; A VALIDER). Les boosts de chance Robux
  multiplient pareil (regle : on vend de la chance, pas des fruits).
- Garde-fou : le Common reste le plus frequent meme avec tous les bonus.
- **Bonus des premiers etages** (2026-11-23, `Fruits.FloorLuck`, A VALIDER) : etage 1 = Rare+ x2,
  etage 2 = Rare+ x1.5 (s'ajoute a la Luck et aux boosts). But : voir plus vite des fruits
  differents au debut. Etage 1 a Luck 1 : Rare 1 sur 11, Epic 1 sur 40, Legendary 1 sur 160,
  Mythic 1 sur 534 ; Common ~64 %. Etage 2 : Rare 1 sur 14, Epic 1 sur 52. Le "1 in X" de l'Index
  et de l'animation de decouverte en tient compte (`Fruits.FloorLuckFor`). Pris aussi dans
  l'argent calcule des etages automatises (`FloorIncome.AverageValue`).

### Valeurs (A VALIDER)

- **Valeur = valeur de l'etage x bonus de rarete.**
- Valeur de l'etage : environ x5 par etage (comme les jus, voir `tour-etages.md`).
- Bonus de rarete (bien plus petit que la rarete, sinon un Infinity casse l'economie) : Common x1,
  Uncommon x2, Rare x3, Epic x5, Legendary x8, Mythic x15, Godly x30, Celestial x60, Glitched x120,
  Infinity x250.
- Avec ces chiffres, un fruit moyen vaut environ x1.6 un Common : l'argent vient surtout de l'etage,
  les fruits rares sont des petits jackpots.

### Production en nombres (lot 5)

Les etages ou le joueur n'est pas sont calcules en nombres (valeur moyenne des fruits). **On ne
decouvre un fruit que sur l'etage ou le joueur se trouve** (fruit visible ramasse) : ca donne une
raison de visiter ses etages.

### Decouverte et Index

- Un fruit jamais ramasse apparait en silhouette "???" dans l'Index, avec sa chance.
- **La premiere fois qu'on le ramasse** (le joueur ou un employe de son etage) : animation de
  decouverte (client, `DiscoveryController`, a creer) :
  1. le fond s'assombrit un peu ; le fruit en 3D (ViewportFrame, modele de `FruitAssets`) arrive au
     centre de l'ecran en grossissant et tourne ;
  2. au-dessus : "NEW FRUIT!" ; en dessous : le nom, la rarete dans sa couleur, la chance "1 in X" ;
  3. confettis aux couleurs de la rarete (reutiliser `Fx/Celebration.luau`) + son ; plus fort pour
     les raretes hautes (Legendary+ : rayons qui tournent derriere le fruit) ;
  4. apres ~2 s, le fruit rapetisse et **vole jusqu'au bouton Index** a gauche ; le bouton
     rebondit et prend la pastille rouge.
  - Duree totale ~2.5 s, un clic la passe, le joueur peut toujours bouger, plusieurs decouvertes
    passent l'une apres l'autre (file d'attente). Pas sur l'ecran si le fruit est ramasse ailleurs.
  - Le serveur decide de la decouverte (liste `Discovered` dans la sauvegarde) et previent le client.
- L'Index : **10 pages, une par etage** (10 fruits par page, de Common a Infinity). Etage pas encore
  achete : page fermee "Buy Floor N". Fruit decouvert : image, nom, rarete, valeur, chance actuelle.
- Recompense par fruit : bouton **CLAIM** (voir "Index (fait le 2026-11-20)" plus bas).
- Recompense d'etage complet : pas decidee (idee : etage complet = +10 % d'argent sur cet etage).
- Annonce serveur pour les tres rares (Godly+) : idee, pas decidee.

### Index (fait le 2026-11-20)

Demande : "trop gros", retirer les boutons de rarete a droite, mettre seulement tous les fruits, et
un CLAIM qui donne de l'argent coherent avec le reste (ni 1 $, ni 40 milliards).

- Menu du pack `ShopGUI.MenuFrames.Index` gardé (en-tete, ouverture), contenu refait par
  `IndexController` : filtres `Rarities` et cartes d'exemple retires au demarrage. Grille de 100
  petites cartes, **5 par ligne** (2026-11-20, demande "5 par 5" ; 4 juste avant). **Rangees par
  rarete** (2026-11-20, demande "range les fruits par rarete") : les 10 Common en haut (etage 1 -> 10),
  puis les 10 Uncommon... Infinity en bas. Chaque rarete = 2 lignes pile (`Spacer` reste dans le code
  si une rarete n'avait pas un multiple de 5 fruits). Avant : rangees par etage. Marge de 16 px en haut
  (`TOP_GAP`, le contour des cartes touchait le haut).
  Titre : "Index  12/100".
- Carte : fruit 3D (ViewportFrame, sans particules), nom, rarete dans sa couleur, **chance de base**
  (Luck 1, `Fruits.OneIn`) : "1 in 3,000", Common en pourcentage ("68%"), visible meme si le fruit
  n'est pas decouvert. Fond en degrade de la couleur de la rarete. Pas decouvert : silhouette noire,
  "???", fond sombre. La chance affichee ne tient pas compte du bonus Luck de l'arbre.
- Fruit decouvert pas encore recompense : bouton vert **"+$X"** qui pulse a la place de la rarete
  et de la chance.
  Clic -> remote `IndexClaim` -> le serveur verifie et paie -> "+$X" vert qui monte + son
  (confettis pour Legendary+). Pastille rouge sur le bouton Index tant qu'il reste un CLAIM.
- **Montant** = `FloorValues[etage] x ClaimBonus[rarete]`, `ClaimBonus` = 2, 4, 6, 10, 15, 25, 40,
  60, 90, 150 (`Fruits.ClaimReward`). On ne decouvre un fruit que sur l'etage ou on est, donc le
  montant suit l'etage du joueur. **Regle (2026-11-20 soir)** : les 10 CLAIM d'un etage ensemble =
  ~40 % du prix de l'etage suivant (~80 % depuis les prix des etages / 2 du 2026-11-20 ; le plus gros,
  Infinity, = 30 % ; avant l'etage 2 on ne trouve en pratique que Common -> Legendary, ~7 %). Avant (3 ... 2 000) : ~3.8 fois ce prix, un Glitched de l'etage 1
  (5 000 $) payait a lui seul l'etage 2. Exemples : etage 1 Apple 10 $, Dragon Fruit 30 $, Golden
  Apple 75 $, Rainbow Apple 750 $ (~2 min des gains de l'etage 1 au max) ; etage 2 Orange 50 $ ;
  etage 10 Apricot ~20 M$, Juice God Fruit ~1.5 B$. **A VALIDER en jeu.**
- Apple (decouverte d'office) : CLAIM de 10 $ des le debut. Anciennes sauvegardes : tous les fruits
  deja decouverts ont leur CLAIM.
- Cartes construites a la premiere ouverture (10 par image). 100 ViewportFrames : a surveiller sur
  telephone.

### Dans le code (lot 4b, fait le 2026-11-20)

- `Config/Fruits` : chaque fruit a `floor` (sa ligne) et `value` = `FloorValues[floor]` x
  `RarityBonus[rarity]` (les valeurs ecrites a la main sont retirees). `OfFloor(n)` (les 10 fruits de
  l'etage, de Common a Infinity), `OfRarity(r)`. Chances : `OneInByRarity` (4, 20, 75... 50 000),
  `CommonWeight` (calcule : le reste, ~0.68), `RollWeights(luck)`, `OneIn(rarity, luck)` ("1 in X"). Luck :
  `LuckMultiplier(niveau Tree)` = x1 -> x`LuckMax` (1.5), seulement pour Rare+ (`LuckFromRarity` = 3 :
  sinon l'Uncommon depasse vite le Common) ; garde-fou `CommonLead` : le Common garde toujours le plus
  gros poids. Tout A VALIDER. `StartRarities`, `MaxLuck`, `LocalIndex`, poids par fruit : supprimes.
- `TreeService` : tirage parmi `OfFloor(n)` avec `RollWeights(LuckMultiplier(Tree))` ; plus de
  garantie "fruit nouveau en 3 chutes" (`Gameplay.NewFruitGuaranteeDrops` retire : il ferait tomber
  un Infinity). Plus aucun fruit accroche dans l'arbre depuis le 2026-11-20 (voir "Arbre qui grandit").
  Attribut `NewFruit` sur un fruit qui tombe s'il n'est pas encore decouvert (effet "NEW!").
- Caisses : `Bin<rarete>` (Bin1 = Common ... Bin10 = Infinity) ; le pad Drop Fruits ne prend que les
  fruits de l'etage (`fruit.floor`).
- Decouverte : `TreeService.Discover(player, id, floor)` au ramassage (pas a la chute) : par le
  JOUEUR seulement (`ProductionService.walkPickup`). Depuis le 2026-11-20, le Fruit Picker ne prend
  jamais un fruit pas encore decouvert (`TreeService.FindNearest(..., knownOnly = true)`) : il le
  laisse au sol pour que le joueur le ramasse et voie "NEW FRUIT!". Ecrit
  `DiscoveredFruits`, Feedback `"Discover"` { fruit } -> `DiscoveryController` (client).
- Panneaux : "FLOOR 3" (plus de nom de rarete), selecteur d'etage "Floor 3".
- Pas fait : "1 in X" au-dessus d'un fruit rare qui tombe ; l'Index (phase 2).

### Rebirth

Rebirth a l'etage 10 (phase 4, voir `tour-etages.md`). Les rebirths n'ouvrent plus de raretes.

## Les 100 fruits

Noms en anglais (affiches en jeu). **Colonne = rarete, ligne (#) = etage** (depuis le 2026-11-20).

| # | Common | Uncommon | Rare | Epic | Legendary |
|---|---|---|---|---|---|
| 1 | Apple | Strawberry | Dragon Fruit | Mangosteen | Golden Apple |
| 2 | Orange | Cherry | Star Fruit | Jabuticaba | Diamond Pear |
| 3 | Banana | Blueberry | Lychee | Cherimoya | Ruby Cherry |
| 4 | Pear | Raspberry | Passion Fruit | Snake Fruit | Emerald Kiwi |
| 5 | Lemon | Kiwi | Papaya | Horned Melon | Sapphire Berry |
| 6 | Lime | Pineapple | Pomegranate | Buddha's Hand | Crystal Grape |
| 7 | Grape | Mango | Guava | Miracle Berry | Pearl Coconut |
| 8 | Plum | Coconut | Fig | Cloudberry | Amber Peach |
| 9 | Peach | Melon | Rambutan | Finger Lime | Silver Plum |
| 10 | Apricot | Watermelon | Durian | Ackee | Platinum Banana |

| # | Mythic | Godly | Celestial | Glitched | Infinity |
|---|---|---|---|---|---|
| 1 | Fire Mango | Angel Apple | Moon Melon | Error Apple | Rainbow Apple |
| 2 | Ice Berry | Holy Grape | Sun Orange | Pixel Berry | Time Berry |
| 3 | Thunder Lemon | Phoenix Fruit | Star Berry | Lag Lemon | Void Fruit |
| 4 | Lava Melon | Dragon Heart | Comet Cherry | Bug Banana | Quantum Mango |
| 5 | Storm Grape | Unicorn Berry | Meteor Mango | 404 Fruit | Multiverse Melon |
| 6 | Shadow Plum | Kraken Melon | Nebula Grape | Corrupted Grape | Eternal Peach |
| 7 | Frost Peach | Titan Banana | Galaxy Plum | Null Melon | Big Bang Berry |
| 8 | Toxic Apple | Griffin Pear | Aurora Kiwi | Static Cherry | Omega Fruit |
| 9 | Magma Orange | Pegasus Peach | Saturn Peach | Binary Mango | Infinity Fruit |
| 10 | Volcano Pineapple | Hydra Cherry | Eclipse Apple | Glitch Kiwi | Juice God Fruit |

## Modeles voxel (2026-11-19)

Demande de l'utilisateur : des fruits "en petits cubes" comme les oeufs du jeu de reference (style
seulement), puis le soir "plus comprehensibles, moins voxel, un peu plus gros". Chaque fruit est une
seule `UnionOperation` faite de cubes de 0.1 stud (~16 cubes de large ; dessin agrandi x1.3 :
une pomme fait ~1.7 de haut, `FruitModels.FruitSize = 1.9`), ~2 400 triangles en moyenne
(max ~4 500 pour les motifs tres bruites). Queues, feuilles et petits details font 2 cubes
d'epaisseur ; peu de cubes "au hasard" (lisibilite). Chaque fruit a :

- une **forme** par famille : pomme, rond, prune, peche, poire, citron, ovale (mangue, papaye),
  banane, grappe, baie a couronne, framboise (petites boules), fraise, cerises (2 ou 3), kiwi coupe
  (face coupee vers le haut), ananas, melon, pasteque, fruit du dragon, carambole (etoile), goutte
  (figue), pique (ramboutan, durian, kiwano), main de Bouddha, cube ("404 Fruit"), coeur, infini,
  cosse ouverte (ackee), grappe de 3 baies ;
- un **motif** : points, rayures, filet de melon, losanges d'ananas, joue rouge, degrade, taches,
  fissures de lave, etoiles, pixels "glitch", damier (texture manquante), neige de tele, binaire,
  arc-en-ciel, eclairs, deux moities, bord dore (eclipse), equateur, tourbillon ;
- un **ombrage 3 tons** (clair en haut a gauche, sombre en bas) + quelques cubes au hasard + un
  reflet blanc, comme dans les captures ;
- des **ajouts** pour les raretes hautes : aureole, ailes, corne, anneau (Saturn), couronne, rayons.

Les raretes Legendary+ reprennent la forme du fruit de base avec une matiere : or, diamant, rubis,
emeraude, saphir, cristal, perle, ambre, argent, platine (Legendary), feu, glace, foudre, lave...
(Mythic), etc. Tout est dans le tableau `DEFS` de `tools/build-assets/fruits-voxel.luau`.

Construction : dans Studio (mode edition), `require` d'une copie du script (il remplace les
anciens fruits ; `_G.FRUIT_ONLY = { "Apple" }` pour n'en refaire que quelques-uns), puis
sauvegarder la place. Les fruits sont dans `ReplicatedStorage.FruitAssets` (hors Rojo).
Pas d'ombre sur les fruits (`CastShadow = false`).

## Effets

- **Rarete** (`FruitModels`, sur chaque fruit : au sol, dans les mains, sur le tapis) : voir le
  tableau des valeurs plus haut. Textures Roblox (`rbxasset://textures/particles/...`) : etincelles
  `sparkles_main`, flammes `fire_main`, halo `explosion01_core_main`. Regle trouvee en test (plein
  jour, fond clair) : etincelles `Brightness 3`, `ZOffset 0.8` (devant le fruit) ; halo
  `LightEmission 0.3`, `Brightness 2`, taille 3.2 ; `forcefield_glow` ne se voyait pas.
- **Apparition** (`FruitFxController`, client) : le serveur pose le fruit a sa place finale avec
  `DropStart` (heure serveur), `DropHeight`, `DropTime` et `NewFruit`. Le client le remonte tout de
  suite dans le feuillage, fait tomber 3-5 feuilles voxel, puis la chute qui tourne et rebondit
  (courbe Bounce). Au 1er contact : cubes qui sautent (couleur du fruit + herbe), onde blanche,
  anneau de la couleur de la rarete (Uncommon+), colonne de lumiere (Rare+), gerbe d'etincelles et
  2e anneau (Legendary+), petit "pop" du fruit, son. Premier fruit d'une espece : etiquette
  **"NEW!"** qui monte + son. Rien au-dela de 150 studs de la camera.
- Le fruit n'est ramassable (prompt E) qu'apres `DropTime`.

## Arbre qui grandit (2026-11-19, refait le soir)

Une seule amelioration : **"Upgrade Tree"**, un pad vert devant la jardiniere (avant le 2026-11-19
soir : deux machines, Sprinkler = vitesse et Lucky Fertilizer = luck, "on comprend pas a quoi ca
sert"). **Chaque niveau = les fruits tombent nettement plus vite (effet principal, visible) + un peu
de Luck** (`Upgrades.TreeDropSeconds` : 2.5 s x 0.885 par niveau jusqu'au niveau 5, puis x0.8055,
min 0.5 s : ~0.52 s au niveau 10, soit ~x4.8 ; avant le 2026-11-23 : x0.885 partout, 0.83 s au niveau 10,
l'arbre limitait l'etage 10 ; Luck x1 -> x1.5). Decision du 2026-11-20 (nuit) : "la vitesse plutot que la chance", on
la voit tout de suite ; avant : x0.955 (1.65 s au niveau 10) et Luck x4. Plus de fruits = plus de
tirages : ~7.1 Rare+ / min au niveau 10 (avant ~8.2). Texte du pad : "Faster drops + luck". Depuis la tour d'etages
(2026-11-20) : l'arbre de l'etage n ne fait tomber que les 10 fruits de la rarete n
(`Fruits.OfRarity(n)`, **ancienne regle, a remplacer par la ligne n**, voir "Fonctionnement"), niveau 1 a 10 dans chaque etage (`Floors[n].Upgrades.Tree`). Sauvegarde : `Upgrades.Tree` (migration v3 : ancien niveau Luck, ou Speed s'il
etait plus haut).

**L'arbre change NETTEMENT a chaque niveau, et d'un etage a l'autre** (2026-11-20 soir, demande :
"un grand changement visuel sur chaque arbre de chaque niveau" et "chaque etage, l'arbre commence au
niveau max de l'etage precedent, et apres il s'ameliore"). Avant : 5 modeles (niveaux 1 / 3 / 7 / 12 /
18) agrandis, mais un etage ne va que jusqu'au niveau 10 : on ne voyait que 2-3 modeles.
- **Construit par code** (`Lib/TreeBuilder`, donnees `Config/Tree`), plus de modele dans
  ServerStorage. Meme etage + meme niveau = exactement le meme arbre (pas de hasard).
- **Palier = (etage - 1) x 9 + niveau** (1 a 91). L'etage n au niveau 1 a **exactement** l'arbre de
  l'etage n-1 au niveau 10 (verifie dans Studio pour les 9 passages), puis il continue.
- **Niveau affiche continu (2026-11-23)** : le panneau "Golden Tree Lv X" ne repart plus a 1 a chaque
  etage. `Tree.DisplayLevel` = (etage - 1) x 10 + niveau : etage 1 = Lv 1..10, etage 2 = Lv 11..20,
  etage 3 = Lv 21..30... Texte seul : la sauvegarde garde le niveau 1..10 de l'etage.
- **Etage 1 (Fruit Tree) : l'arbre pousse** (`Tree.Growth[1..10]`) : pousse avec tuteur (~8 de haut)
  -> jeune arbre (branches, racines) -> nichoir (niveau 5) -> anneaux d'ecorce (6) -> 3 etages de
  feuillage (6-7) -> ruche (8) -> balancoire (9) -> grand arbre (10, ~24 de haut).
- **Etages 2 a 10 : chaque niveau passe UNE partie de l'arbre au theme de l'etage** (`Tree.Slots`) :
  niveau 2 tronc (couleur, anneaux), 3 feuillage du bas, 4 feuillage du haut, 5 dessus des grappes a
  la couleur d'accent, 6 huit ornements dans le feuillage, 7 veines sur le tronc + anneau au pied,
  8 aura (etincelles + lumiere douce), 9 grand anneau autour du feuillage, 10 couronne au sommet (+
  etincelles). Avant son niveau, la partie garde le theme de l'etage d'en dessous. L'arbre grandit
  aussi un peu a chaque palier (`Tree.LateGrowth`, surtout en largeur).
- **Themes** (`Tree.Themes`, meme ordre que `Tree.Names`) : Lucky (vert emeraude, accent or, trefles
  dores, grand trefle), Golden (or, accent ambre, lingots, etoile), Crystal (glace bleue, pics de
  cristal, bouquet de cristaux), Magic (violet, accent cyan, runes, orbe), Royal (rouge, accent or,
  gemmes, couronne royale), Mystic (turquoise, accent violet, flammes, oeil), Cosmic (bleu nuit,
  accent jaune, etoiles, planete), Galaxy (rose / violet / bleu, accent cyan, anneaux, galaxie), Divine
  (blanc, accent or, petites ailes, aureole + grandes ailes dorees).
- **Pas de Neon** (utilisateur, 2026-11-20 : "pas de neon, c'est moche") : accents en plastique lisse
  un peu reflechissant (`SmoothPlastic`, Reflectance 0.25), cristaux et gemmes en verre ; l'eclat vient
  des effets (aura : ParticleEmitter + PointLight faible, etincelles de la couronne).
- **Pas de fruit de deco dans l'arbre** (2026-11-20, demande utilisateur : "on voudra les recuperer
  et on sait pas pourquoi on peut pas") : aucune piece en forme de fruit ; `TreeService.prepareBody`
  detruit par securite les pieces `Apple`, `GoldenApple`, `AppleStem`, `HangFruit`.
- **On traverse l'arbre** (2026-11-20) : toutes ses pieces `CanCollide / CanTouch / CanQuery = false` ;
  la camera passe au travers et l'arbre devient transparent quand il est entre la camera et le joueur
  (voir `camera.md`). L'arbre reste UN Model `Body` sous `Floor.Tree`.
- **Taille** : le plus haut (couronne comprise) reste sous `Tree.MaxHeight` (31.5 au-dessus de
  l'herbe, poutres du puits de lumiere a 34.6) : la couronne est reduite si besoin. Le plus large
  (ailes de l'etage 10) fait ~35 studs : reste dans la jardiniere (38 x 36).
- **Zone de chute** : rayon = rayon du feuillage + 2.6, entre 8 et 12.8 studs (`TreeBuilder.Measure`),
  `Tree.FruitArea` 26 x 26 limite a 13 studs ; pas de fruit pres du tronc (`trunkClear`) ; les fruits
  partent du bas du feuillage (`fallHeight`), la chute dure plus longtemps quand l'arbre est plus haut.
Apres un rebirth (niveau remis a 1), l'arbre de l'etage 1 redevient une pousse.

- `TreeService.setTreeModel` appelle `TreeBuilder.Build(etage, niveau)`, pose le modele `Body` sur
  `Tree.TreeRoot`, `prepareBody`, met les attributs `TreeStage` (= palier) et `TreeLevel` sur `Tree` et
  place le texte "Tree full!" / nom de l'arbre (`labelHeight`). Le modele n'est refait que si le niveau
  change (juste apres un achat sur le pad ; verifie a chaque chute : outils de test, rebirth).
- `TreeFxController` (client) anime la pousse quand `TreeLevel` monte ; `TreeStage` change a chaque
  niveau, donc toujours la grande pousse (35 % plus petit, puis pop et rebonds).
- Feuillage : attribut `Leaf = true` (animation), dessus des grappes plus clair ou couleur d'accent.
- ~10 pieces (pousse) a ~195 pieces (etage 10 niveau 10) par arbre, un arbre par etage ouvert.

## Remotes

- `IndexState` (serveur -> client) : `{ discovered = {ids}, claimed = {ids} }`, envoye au chargement,
  apres chaque decouverte (`TreeService.Discover`), chaque claim et `SetDiscovered` (outils de test).
- `IndexClaim` (client -> serveur) : id du fruit. `IndexService` verifie : chaine, fruit connu,
  sauvegarde chargee, fruit decouvert, pas deja pris, delai `GameConfig.IndexClaimCooldown`
  (0.15 s). Le montant est calcule par le serveur. Reponse : Feedback `"IndexClaim"` { fruit, amount }.

## Donnees sauvegardees

Niveau de l'arbre (`Upgrades.Tree`), liste des fruits decouverts (`DiscoveredFruits`), recompenses
de l'Index prises (`ClaimedFruits`, 2026-11-20 : ajoute par Reconcile, nettoye par `sanitize` :
seulement des fruits connus et decouverts), nombre de rebirths.

## Configuration

`src/shared/Config/Fruits.luau` : nom, rarete, valeur, couleur du jus, poids de tirage.
Les poids exacts s'equilibrent en test.

Valeurs validees le 2026-11-19 (argent entier, Apple = 5, environ +20 % par fruit, x25 par rarete,
arrondi a 3 chiffres) : Common 5, 6, 7, 9, 10, 12, 15, 18, 21, 26 ; Uncommon 125 -> 645 ;
Rare 3 120 -> 16 100 ; ... Infinity 19.1T -> 98.4T (liste complete dans le fichier).

Poids : `BaseWeight (1000) x 0.8^(position-1) x 0.1^(rarete-1)` (calcule au chargement ;
`weightOverride` possible par fruit). Ids sauvegardes : nom en PascalCase (`DragonFruit`,
`BuddhasHand`, `Fruit404`). `Fruits.OfRarity(r)` = les 10 fruits de la rarete r ; `Fruits.LocalIndex(fruit)` = sa place 1..10
(numero de sa caisse `Bin<n>` sur l'etage de sa rarete). `StartRarities` / `MaxLuck` supprimes
(2026-11-20 : ce sont les etages, plus les rebirths, qui ouvrent les raretes).

## Problemes connus / a faire

- Fruits voxel : si `ReplicatedStorage.FruitAssets` n'est pas dans la place (script pas lance ou
  place pas sauvegardee), on revoit les anciennes boules. Relancer le script apres tout changement
  de dessin.
- Effets de rarete : pas encore vus en vrai pour Epic+ (aucun profil n'a ces fruits) ; a regarder
  avec les outils de test.
- Arbre : vu seulement dans Studio (galerie des 100 arbres + jardiniere) et en playtest a l'etage 1
  (niveau 1 -> 7 -> 1 par les outils de test) ; etages 2+ pas encore vus en jeu, telephone pas teste.
  Couleurs, ornements et couronnes a valider par l'utilisateur.
- `ServerStorage.TreeStages` (5 anciens modeles, faits par 02b) ne sert plus : a retirer de 02b et
  de la place quand plus personne ne touche 02b.
- Le prix du pad "Upgrade Tree" est a equilibrer en jouant.
- Garantie : le compteur de chutes est en memoire (repart a 0 si le joueur revient).
- Equilibrer les poids pour que chaque nouveau fruit tombe assez vite pour etre decouvert.
