# Performance mobile : mesures

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

### Piste n°1 (pas faite)

Cacher cote client les PNJ loin de la camera (comme les effets de rarete dans
`WorldDetailController`) : enleve ~440 000 triangles et ~200 appels de dessin par tour au max.
Piste n°2 : unions des etages (135 000 a 400 000 triangles par tour).

### Pas verifie

- FPS, chauffe et memoire sur un vrai telephone (Studio ne simule ni le processeur ni la memoire ;
  la memoire lue dans Studio melange edition, serveur et client).
- Pendant une partie des mesures, Studio etait en arriere-plan (15 images / s) : les compteurs de
  triangles et d'appels restent justes, aucun FPS de PC n'est donne ici.
- Vrai profil neuf (cinematique rejouee avec `IntroPending`), R6, 2 joueurs et plus.
- Tours au max passees par le vrai jeu (ombres par etage de `ShadowController`, PNJ qui bougent).
