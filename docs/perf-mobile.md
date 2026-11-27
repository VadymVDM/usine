# Performance mobile : mesures

**Pour refaire le test : aller a "Relancer le test" en bas de ce fichier** (scripts `tools/perf/`).

Mesures faites dans Studio sur PC (pas sur un vrai telephone). Elles disent **combien le jeu
demande** au telephone (triangles, appels de dessin, particules), pas les FPS reels d'un telephone.

Reperes Roblox (`SceneAnalysisService`) : vers **800 000 triangles et 600 appels de dessin**
(ombres non comptees), la plupart des appareils tiennent 60 FPS. Un telephone d'entree de gamme
tient moins. Un appel de dessin coute bien plus cher qu'un triangle sur telephone.

## Test du 2026-11-27 (Studio PC, 1 joueur)

Methode : Play Studio, `execute_luau` serveur + client, `SceneAnalysisService`. Pour voir une
base **au maximum** (10 etages, tout achete), l'apercu `tools/build-map/preview-factory.luau` a ete
construit sur le serveur pendant le Play (jeté au Stop).

### Serveur : OK

- Heartbeat stable a 60 / s (moyenne 16,7 ms, pire 19,4 ms sur 5 s), 1 joueur, base neuve.
- 0 erreur de script ; 1 avertissement : `rbxassetid://203785492` "Asset type does not match".

### Client, base neuve (debut de partie) : OK

| | Triangles | Appels de dessin |
|---|---|---|
| Opaque | 38 870 | 60 |
| Interface (ecrans + textes 3D) | 3 158 | **229** |
| Total sans ombres | ~42 500 | ~295 |

- 45 000 instances dans Workspace, 27 500 pieces, 103 particules (33 actives).
- Memoire des scripts (VM Luau) : 11,3 Mo. 149 instances hors arbre (peu).
- Deja la : l'interface 3D fait 3 appels de dessin sur 4.

### Client, une base au maximum : trop lourd pour un telephone

| Vue | Triangles sans ombres | Appels de dessin sans ombres | dont interface 3D |
|---|---|---|---|
| Exterieur, tour entiere | **1 175 000** | **2 144** | **1 324** |
| Hauteur du joueur, pres du rez-de-chaussee | 20 000 | **1 049** | **1 023** |
| Dans l'etage 1 | 47 700 | 446 | 402 |

Une base au max = 53 000 instances, 20 000 pieces, 786 emetteurs de particules actifs
(4 300 particules / s), 251 lumieres, 4 500 pieces qui font de l'ombre, 110 PNJ R15.
Avec 6 joueurs avances sur le serveur, il faut multiplier (le streaming a 1024 studs les charge
presque toutes).

### Causes trouvees

1. **334 ecrans `SurfaceGui` par base sans distance max** (`MaxDistance = 0` = visibles de
   partout) : tuiles d'amelioration `Display` (`src/shared/Util/UpgradeTile.luau`), `DisplayFront`,
   `DisplayBack`. Ce sont eux qui font 1 000 a 1 300 appels de dessin. Les `BillboardGui` ont,
   eux, une distance max (40 a 100 studs) : OK.
2. **Effets de rarete des fruits** (`addRarityFx`, `src/shared/FruitModels.luau`) : 320 `Glow` +
   320 `Sparkles` + 40 `Fire` par base au max, toujours actifs, meme loin.
3. **Ombres** : 4 500 pieces avec `CastShadow` par base (1,3 M triangles d'ombre vus de loin).
   Moins grave : le telephone coupe souvent les ombres en qualite basse.
4. **110 PNJ R15** par base au max (2 050 pieces de corps) : a surveiller cote client et serveur.

### Corrections faites (2026-11-27 soir)

`src/client/Controllers/WorldDetailController.luau` (client seulement), reglages dans
`src/shared/Config/Gameplay.luau` :

- **Ecrans 3D** : toute `SurfaceGui` du Workspace sans distance max en recoit une :
  plus grand cote du panneau x 10 studs, entre 80 et 300 (tuile de 7 studs : 80 ; enseigne
  de 32 studs : 300). Les murs des classements (deja a 300) ne bougent pas.
- **Effets de rarete des fruits** : l'Attachment `RarityFx` est tague (`FruitModels.RarityFxTag`).
  Particules et lumiere coupees au-dela de 60 studs de la camera, remises en dessous (marge de
  8 studs pour ne pas clignoter).
- Les ombres sont deja limitees a l'etage du joueur par `ShadowController` (l'apercu mesure ne
  passe pas par lui : les ombres mesurees ci-dessus sont plus fortes que dans le jeu).

Re-mesure, meme methode, base au max :

| Vue | Avant (tris / appels) | Apres (tris / appels) |
|---|---|---|
| Exterieur, tour entiere | 1 175 000 / 2 144 | 927 000 / **290** |
| Hauteur du joueur, pres du rez-de-chaussee | 20 000 / 1 049 | 9 000 / **242** |
| Dans l'etage 1 | 47 700 / 446 | 28 600 / **299** |

Effets de rarete actifs : 786 emetteurs avant, 0 vu de l'exterieur et 2 dans l'etage 1 apres.
Verifie en Play : un fruit rare a 200 studs a ses effets coupes (0/2), a 10 studs rallumes (2/2).
0 erreur de script.

### Pistes restantes

- Triangles vus de l'exterieur : encore ~930 000 pour une tour au max (geometrie : 110 PNJ R15,
  pieces des etages). A regarder si un vrai telephone rame en regardant la tour de loin.
- `CastShadow = false` sur les petites pieces (decor, fruits, caisses).
- Refaire la mesure apres chaque piste, puis tester sur un vrai telephone (console developpeur :
  taper `/console` dans le chat du jeu publie).

### Pas verifie

- FPS sur un vrai telephone (Studio sur PC ne simule pas le processeur ni la carte graphique
  d'un telephone).
- 6 bases avancees en meme temps, plusieurs joueurs.
- Mise en page de l'interface sur petit ecran (pas teste ici).
- A verifier dans Game Settings : `Players.MaxPlayers` vaut 60 dans la place alors que le jeu est
  prevu pour 6 joueurs (6 bases).

## Test du 2026-11-27 (21 h) : cinematique + jeu, qualite "telephone" simulee

Demande : "voir si ca tourne sur des telephones normaux a modestes". Toujours Studio PC, 1 joueur :
ce sont des **charges mesurees**, pas des FPS de telephone.

Methode (nouvelle) :
- Compteurs du moteur lus a chaque image cote client (`Stats.SceneTriangleCount`,
  `SceneDrawcallCount`, `Shadows*`, `RenderCPUFrameTime`) : moyenne et maximum par vue ou par phase.
- **Qualite telephone simulee** : `settings().Rendering.QualityLevel` regle pendant le Play sur
  21 (PC au max), 3 et 1 (niveaux bas, ceux d'un telephone modeste en reglage automatique), puis remis a 21.
- Cinematique rejouee en entier en temps reel (`IntroPending`), une fois en qualite 21, une fois en 3.
- Tour au maximum : `preview-factory` construit sur le serveur pendant le Play (emplacements 2, 3,
  5 et 6, jetes au Stop), en plus de la vraie base du profil de test (10 etages, peu de machines).
- Cout des scripts : MicroProfiler lu par `LibMP` (fil principal).

### Cinematique d'ouverture : OK, tres legere

28.1 s, 0 erreur de script. Decor : 2 650 pieces, 13 emetteurs de particules.

| Phase | Triangles (moy / max) | Appels de dessin (moy / max) |
|---|---|---|
| Ouverture (montagnes, volcan) | 69 000 / 91 000 | 38 / 102 |
| Marche, arbre au loin | 34 500 / 69 500 | 25 / 32 |
| Wow + course | 32 500 / 57 600 | 24 / 35 |
| Pelle | 14 500 / 55 600 | 19 / 28 |
| Creuse | 12 800 / 15 500 | 19 / 25 |
| Chute + arbre en main | 33 500 / 74 300 | 26 / 39 |
| Blanc + arrivee dans l'usine | 53 000 / 78 000 | 71 / 115 |

- Qualite 3 : memes triangles (les montagnes ne sont pas coupees), ombres a 0.
- Ombres en qualite 21 : 32 000 a 65 000 triangles (coupees sur telephone modeste).
- Rendu processeur sur ce PC : 4 a 6 ms par image, partout.
- A-coups : ~50 ms au debut (copie du decor) et ~80 ms a l'arrivee, tous deux sous le blanc.
- C'est 9 fois sous le repere Roblox (800 000 triangles, 600 appels).

### Jeu, debut de partie et carte : OK

Vraie base du profil de test + carte + nouveau fond (foret, crete, montagnes, volcan).

| Vue | Qualite 21 (tris / appels) | Qualite 3 (tris / appels) |
|---|---|---|
| Vue de jeu normale (dans sa base) | 76 000 / 102 | 15 000 / 134 |
| Route, vers la tour | 29 500 / 46 | 17 000 / 33 |
| Centre de la carte, vers la tour | 93 000 / 152 | 75 600 / 137 |
| Route, 4 directions (fond de carte) | 10 000 a 49 000 / 44 a 92 | 9 500 a 42 000 / 40 a 82 |
| Dans l'etage 1 | 15 000 / 211 | 14 000 / 204 |
| Vue aerienne de toute la carte | 301 000 / 208 | 139 000 / 90 |

Le fond de carte ajoute le 2026-11-27 ne pese presque rien. Serveur : 60 / s.
Scripts du jeu (serveur + client ensemble) : ~0.8 ms par image sur ce PC, meme avec une tour au max.

### Une tour au maximum : limite pour un telephone modeste

| Vue | Qualite 21 | Qualite 3 | Qualite 1 |
|---|---|---|---|
| Dehors, tour entiere | 1 150 000 / 439 | 746 000 / 353 | 631 000 / 306 |
| Hauteur du joueur, devant le rez-de-chaussee | 175 000 / 179 | 162 000 / 167 | 149 000 / 162 |
| Dans l'etage 1 | 323 000 / 343 | 320 000 / 337 | 320 000 / 334 |
| Dans un etage du milieu | 255 000 / 300 | 252 000 / 293 | 247 000 / 290 |

D'ou viennent les triangles (tour vue de dehors, en retirant un groupe a la fois) :

| Groupe | Qualite 21 | Qualite 3 |
|---|---|---|
| **110 PNJ R15** (2 050 pieces) | 440 000 tris, ~220 appels | **442 000 tris, ~190 appels** |
| 980 unions | 406 000 tris, 66 appels | 135 000 tris |
| 17 000 blocs | presque rien (ils cachent meme le reste) | presque rien |

Les PNJ pesent ~4 000 triangles chacun et ne s'allegent pas en basse qualite : sur telephone,
c'est 60 % des triangles et plus de la moitie des appels de dessin d'une tour au max.

### Serveur rempli de tours au maximum (4 tours au max + 1 vraie) : trop lourd

| Vue | Qualite 21 | Qualite 3 | Qualite 1 |
|---|---|---|---|
| Sur la route, regard le long de la route | 1 770 000 / 694 | 1 208 000 / 620 | 1 085 000 / 573 |
| Sur la route, vers une tour proche | 681 000 / 432 | 672 000 / 419 | 668 000 / 409 |
| Dans l'etage 1 d'une tour | 324 000 / 343 | 321 000 / 337 | 320 000 / 334 |

- Rendu processeur sur ce PC : 11 a 14 ms par image (4 a 6 ms en debut de partie), donc 2 a 3 fois
  plus de travail pour le telephone.
- Le client recoit 108 000 pieces et 328 000 instances (115 000 instances en debut de partie).
- Serveur : 59 / s (les tours du test sont des decors immobiles : la vraie charge du serveur avec
  6 joueurs avances n'est pas mesuree).

### Lecture pour un telephone (estimation, pas une mesure)

| Situation | Telephone normal | Telephone modeste |
|---|---|---|
| Cinematique | OK | OK |
| Debut de partie, base peu avancee, carte | OK | OK |
| Dans un etage d'une tour au max | OK | probablement OK, un peu juste |
| Une tour au max vue de dehors | OK | limite (au niveau du repere Roblox) |
| Route avec plusieurs tours au max | limite | rame |

### Piste n°1 : faite le soir meme (voir "Correction du 2026-11-27 (21 h 30)")

Cacher cote client les PNJ loin de la camera (comme les effets de rarete dans
`WorldDetailController`) : enleve ~440 000 triangles et ~200 appels de dessin par tour au max.
Piste n°2 (pas faite) : unions des etages (135 000 a 400 000 triangles par tour).

### Pas verifie

- FPS, chauffe et memoire sur un vrai telephone (Studio ne simule ni le processeur ni la memoire ;
  la memoire lue dans Studio melange edition, serveur et client).
- Pendant une partie des mesures, Studio etait en arriere-plan (15 images / s) : les compteurs de
  triangles et d'appels restent justes, aucun FPS de PC n'est donne ici.
- Vrai profil neuf (cinematique rejouee avec `IntroPending`), R6, 2 joueurs et plus.
- Tours au max passees par le vrai jeu (ombres par etage de `ShadowController`, PNJ qui bougent).

## Correction du 2026-11-27 (21 h 30) : PNJ invisibles loin de la camera

`src/client/Controllers/WorldDetailController.luau` (client seulement), reglages dans
`src/shared/Config/Gameplay.luau` :

- Chaque PNJ du monde porte le tag `Npcs.FarHideTag` ("FarHideNpc") : employes (`NpcRig.Spawn`,
  serveur), clients (`CustomerController`, client), PNJ de l'apercu (`preview-factory`).
- Toutes les 0.3 s, distance camera -> PNJ, la hauteur comptant 2.5 fois plus
  (`NpcVerticalWeight` : un PNJ 2 etages plus haut est derriere des plafonds). Au-dela de
  `NpcMaxDistance` (260 studs) le PNJ devient invisible ; `NpcMaxDistancePhone` (120) sur un
  appareil tactile sans clavier ou en Low Quality. Marge de 15 studs pour ne pas clignoter,
  40 PNJ caches au plus par passage.
- Moyen : `Transparency = 1` en local sur ses pieces et decalcomanies, valeur d'avant remise en
  s'approchant (seulement si personne d'autre n'y a touche). Pas `LocalTransparencyModifier` :
  les clients, la camera et les effets d'apparition l'animent deja.
- Un PNJ sorti par le streaming ou detruit est d'abord remis visible.

Avant / apres, meme script (`tools/perf`), 4 tours au maximum + la vraie base, triangles / appels
de dessin sans les ombres :

| Vue | Qualite 21 avant -> apres | Qualite 3 avant -> apres | Qualite 1 avant -> apres |
|---|---|---|---|
| Route, le long de la route | 2 349 000 / 762 -> 1 172 000 / 366 | **1 269 000 / 641 -> 334 000 / 209** | 1 138 000 / 564 -> 258 000 / 187 |
| Vue aerienne (pire cas) | 7 602 000 / 1 934 -> 5 861 000 / 774 | 2 495 000 / 1 290 -> 903 000 / 457 | 900 000 / 509 -> 377 000 / 207 |
| Tour, dehors, de derriere | 6 767 000 / 1 533 -> 4 666 000 / 472 | 3 566 000 / 1 237 -> 2 038 000 / 390 | 2 496 000 / 851 -> 1 662 000 / 278 |
| Tour, devant le rez-de-chaussee | 307 000 / 246 -> 224 000 / 195 | 278 000 / 229 -> 180 000 / 167 | 244 000 / 206 -> 166 000 / 161 |
| Tour, dans l'etage 1 | 364 000 / 405 -> 323 000 / 342 | 344 000 / 400 -> 321 000 / 338 | 334 000 / 395 -> 320 000 / 335 |
| Tour, dans un etage du milieu | 256 000 / 372 -> 255 000 / 298 | 239 000 / 367 -> 252 000 / 293 | 231 000 / 364 -> 247 000 / 289 |
| Route, fond de carte | 136 000 / 133 -> 113 000 / 115 | 125 000 / 123 -> 104 000 / 104 | 121 000 / 117 -> 100 000 / 102 |
| Vue de jeu normale | 59 000 / 112 -> 55 000 / 109 | 47 000 / 80 -> 42 000 / 78 | 60 000 / 76 -> 52 000 / 75 |

- Sur la route avec 4 tours au max, en qualite telephone : 4 fois moins de triangles, 3 fois moins
  d'appels de dessin. On repasse sous le repere Roblox (800 000 / 600).
- Verifie en Play : sur 458 PNJ, 28 proches intacts (0 piece restee invisible), 418 loin tous
  invisibles, 12 dans la marge. 0 erreur de script. Cinematique inchangee (28.3 s).
- **Ce qui reste lourd** : les 980 unions par tour. Tour vue de derriere apres correction : les PNJ
  font 0 triangle, les unions 770 000 (qualite 3) a 858 000 (qualite 21). C'est la piste suivante.
- **A savoir sur ces mesures** : la tour au maximum du test a 50 clients (5 par etage). Le vrai jeu
  n'en dessine pas autant : `CustomerController` ne montre que les clients de l'etage actif, a
  moins de 220 studs. Une vraie tour au max a ~60 employes + quelques clients : le poids "avant"
  des PNJ est un peu surestime, le gain reel aussi.
- Petit defaut accepte : un objet porte qui n'est pas dans le modele du PNJ (gobelet d'un client)
  reste visible quand le PNJ est cache. A plus de 120 studs, ca ne se voit presque pas.
- Pas verifie : vrai telephone ; employes du vrai jeu (le profil de test n'en a pas : verifie sur
  les PNJ de l'apercu, memes rigs, immobiles) ; 2 joueurs.

## Correction du 2026-11-27 (22 h) : mini fruits des gobelets invisibles loin de la camera

Les 980 unions d'une tour au maximum, regardees de pres (mode Edit, `TriangleCount`) :

- ~580 **mini fruits** (`MiniFruit`, `FruitModels.CreateCup`) : le fruit voxel entier reduit a
  0.3 stud et pose sur chaque gobelet. 3 300 a 4 500 triangles chacun.
- ~400 **fruits entiers** (`Body`) : fruits poses au sol (dossier `PreviewFruits` de l'apercu), memes maillages en grand.
- 2 300 000 triangles en tout par tour, en detail complet.

Fait : le mini fruit porte le tag `FruitModels.MiniFruitTag` ("FarHideMiniFruit") ;
`WorldDetailController` le rend invisible (`Transparency = 1` en local) au-dela de
`Gameplay.MiniFruitMaxDistance` (60 studs, marge de 8), et le remet en s'approchant. Pour tous les
appareils. Les gobelets des fenetres d'interface ne sont pas touches.

Mesure A/B dans le meme Play (4 tours au maximum, mini fruits montres puis caches, rien d'autre
ne change), triangles / appels de dessin :

| Vue | Qualite 21 : visibles -> caches | Qualite 3 : visibles -> caches |
|---|---|---|
| Vue aerienne | 5 889 000 / 773 -> 4 002 000 / 773 | 903 000 / 456 -> 903 000 / 459 |
| Tour, dehors, de derriere | 4 634 000 / 466 -> 3 342 000 / 466 | 2 036 000 / 393 -> 2 039 000 / 390 |
| Route, le long de la route | 1 094 000 / 357 -> 576 000 / 305 | 509 000 / 286 -> 499 000 / 287 |

- **Haute qualite (PC, bons telephones et tablettes) : 500 000 a 1 900 000 triangles en moins.**
- **Qualite telephone modeste : aucun gain.** En basse qualite, Roblox ne dessine deja plus ces
  tout petits objets de loin. Pour un telephone modeste, cette correction ne change rien.
- Verifie en Play : 2 320 mini fruits, tous caches loin (0 visible), 158 proches intacts (0 reste
  cache) quand la camera est a 20 studs d'un gobelet. 0 erreur de script.
- **Ce qui pese encore en qualite telephone** : les fruits entiers (`Body`). `Breakdown` en
  qualite 3 : les unions d'une tour vue de derriere font 770 000 triangles, et les mini fruits
  n'y comptent pour rien. Pistes : les cacher loin de la camera (ca se voit : les fruits au sol
  disparaissent de loin) ou refaire les maillages des fruits plus simples. Pas fait.
  **Decide par l'utilisateur le 2026-11-27 : les cacher, mais d'assez loin pour que personne ne
  les voie disparaitre.** Prompt pret pour un nouveau chat : `docs/prompts/perf-fruits-entiers.md`.
- Pas verifie : vrai telephone ; gobelets en mouvement dans le vrai jeu (verifie sur les gobelets
  immobiles de l'apercu).

## Relancer le test (scripts `tools/perf/`)

Deux scripts, synchronises par Rojo dans `ServerScriptService.DevTools.Perf`, jamais charges par
le jeu :

| Fichier | Cote | Role |
|---|---|---|
| `tools/perf/perf-server.luau` | serveur | Installe le module client, construit des tours au maximum, relance la cinematique, cadence du serveur, remise en etat de Studio |
| `tools/perf/perf-client.luau` | client | Mesures : vues de la carte et d'une tour par niveau de qualite, origine des triangles, cinematique par phase, cout des scripts |

Marche a suivre (MCP `execute_luau`, un appel par ligne ; Rojo connecte, Studio au premier plan
si possible) :

1. Lancer le Play.
2. Serveur : `return require(game.ServerScriptService.DevTools.Perf["perf-server"]).Setup({ 2, 3, 5, 6 })`
   (liste des emplacements ou poser une tour au maximum ; `{}` = aucune tour ; jamais l'emplacement
   de la base du joueur, attribut `BaseId`).
3. Client, attendre ~6 s puis : `return require(game.ReplicatedStorage:WaitForChild("PerfClient")).Game()`.
   Si la reponse est "EN COURS", rappeler `.Result()`. Une ligne par vue, une colonne par qualite :
   `triangles / appels de dessin, rendu processeur du PC, PNJ affiches`.
4. Client : `.Breakdown()` = d'ou viennent les triangles de la tour (PNJ, unions, blocs...).
5. Cinematique : client `.IntroArm(3)` (niveau de qualite), serveur `.ReplayIntro()`, client
   `.Result()` (deux fois si "EN COURS").
6. Cout des scripts, dans un Play SANS tour : client `.Scripts(require("@rbx/LibMP"))`.
7. Client `.Finish()`, Stop, puis en mode Edit :
   `return require(game.ServerScriptService.DevTools.Perf["perf-server"]:Clone()).EditCheck()`
   (qualite de Studio remise a 21, camera libre, aucun reste).

Comparer aux tableaux de ce fichier. Valeurs de reference apres la correction du 2026-11-27 :

- Avec 4 tours au maximum : colonne "apres" du tableau ci-dessus.
- Sans tour (`Setup({})`, profil de test avec sa vraie base de 10 etages), qualite 21 / qualite 3 :

| Vue | Qualite 21 | Qualite 3 |
|---|---|---|
| Vue de jeu normale | 49 000 / 104 | 36 000 / 76 |
| Route, le long de la route | 31 000 / 50 | 27 000 / 47 |
| Route, fond de carte | 49 000 / 62 | 42 000 / 54 |
| Vue aerienne (pire cas) | 269 000 / 209 | 139 000 / 90 |
| Tour, dehors, de derriere | 135 000 / 101 | 132 000 / 83 |
| Tour, devant le rez-de-chaussee | 31 000 / 90 | 19 000 / 79 |
| Tour, dans l'etage 1 | 18 000 / 212 | 17 000 / 207 |
| Tour, dans un etage du milieu | 14 000 / 140 | 14 000 / 134 |

  Scripts : 0.99 ms par image (serveur + client, PC). Serveur : 60 / s.
- Cinematique : tableau par phase du test de 21 h (12 000 a 91 000 triangles, 19 a 115 appels).

A savoir :

- Qualite 3 et 1 = telephone simule : niveau de qualite bas + attribut local `PerfAsPhone`, qui
  fait prendre au jeu ses distances "telephone" (Studio seulement).
- Ce sont des charges, pas des FPS. Le rendu processeur donne un ordre de grandeur relatif (a
  comparer d'un test a l'autre sur le meme PC), rien de plus.
- Les vues sont ecrites pour la carte actuelle (bases en x = -200, 0, 200 et z = +-90). Si la
  carte change : `MAP_VIEWS` et `towerViews` dans `perf-client.luau`. Si `Intro.Times` change :
  `INTRO_PHASES`.
- Un appel `execute_luau` qui se termine remet le type de camera du debut de l'appel : le script
  repose sa camera a chaque image et la rend 0.5 s apres le dernier appel.
- `Scripts` avec des tours au maximum ne marche pas (le MicroProfiler ne garde qu'une image).
- **Lancer `Game()` deux fois et garder la 2e mesure.** Vu le 2026-11-27 : la 1re mesure apres
  `Setup` peut differer de la suivante (vue aerienne en qualite 3 : 614 000 triangles puis
  901 000 ; dans un etage : 342 000 / 397 puis 321 000 / 334). Cause pas trouvee (les tours
  viennent d'arriver chez le client). La 2e mesure retombe sur les valeurs de reference.
- Pour juger UN changement, le mieux est une mesure A/B dans le meme Play (montrer / cacher le
  groupe, comme `Breakdown`), pas deux Play differents.
