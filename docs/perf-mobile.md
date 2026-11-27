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
