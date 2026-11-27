# Systeme : Carte, bases et attribution

**Statut :** fonctionne (playtest Studio a 1 joueur ; 2 joueurs et telephone a tester)
**Derniere mise a jour :** 2026-11-27 (murs recules de 300 studs ; alentours et fond de carte poses sur tout le tour : foret, crete, montagnes, volcan de jus)

> **2026-11-20 : la base est maintenant une tour d'etages** (`tour-etages.md`). Les scripts
> construisent DEUX modeles : `BaseTemplate` (terrain, cour, annexe ouest, entree) et `FloorTemplate`
> (un etage : salle, escalier, verger, production, comptoir...). Les salles Cocktail Bar / Terrace
> et `ZoneLocks` n'existent plus : terrasse = hall de l'ascenseur (fermee jusqu'a l'etage 2), bar a
> cocktails = salle du Rebirth ("Reach Floor 10"). Zone SALES raccourcie a z 50, zone STAIRS
> x 60-108, z 50-84. Etagere : 10 caisses (`Bin1..10`). Le tableau ci-dessous donne les chemins
> DANS un etage ; en attendant FloorService, l'etage 1 est "deplie" dans la base (BaseService).

## Role

La carte (route, spawn, decor) et les 6 bases. Chaque base est une **usine de jus** (batiment
blocky, murs gris-bleu clair a studs, bas de mur en tole, sol ardoise, structure acier, neons, verger interieur). Chaque joueur recoit une base libre a son
arrivee et apparait dedans ; elle est videe et liberee a son depart. Un 7e joueur recoit un message
propre et se promene ; il recoit la premiere base qui se libere.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `tools/build-map/01-ground-road.luau` | Studio (hors Rojo) | Herbe, route (600 de long), trottoirs, lampadaires, place du spawn + fontaine, `Map.BaseSlots` (espacement 200), limites |
| `tools/build-map/02a-base-shell.luau` | Studio | `ServerStorage.BaseTemplate` : terrain, cour avant, sol, murs (portes, fenetres), poutres, puits de lumiere, lampes, **zones** (sol de couleur bordure + panneau suspendu : ORCHARD, FRUIT SHELF, JUICE BAR, SALES), panneau du proprietaire, enseigne |
| `tools/build-map/02b-base-tree.luau` | Studio | Verger : jardiniere 38 x 36, `FruitArea` (26 x 26 depuis le 2026-11-20, avant 22 x 22), `TreeRoot`, `TreeLabelAnchor`, les 5 stades d'arbre `ServerStorage.TreeStages.Stage1..5` (plus utilises depuis le 2026-11-20 soir : l'arbre est construit par `Lib/TreeBuilder`) et `Tree.Body` (pousse, remplace au demarrage). Voir `fruits.md` |
| `tools/build-map/02c-base-production.luau` | Studio | Etagere a fruits (30 caisses), plancher de depot, tapis roulant (montee + tapis qui longe la rangee), 4 mixeurs (`buildBlender`), table a jus |
| `tools/build-map/02d-base-counter.luau` | Studio | Comptoir dans la fenetre de la facade, auvent, tapis "SERVE", plateau a argent |
| `tools/build-map/02e-base-machines.luau` | Studio | Pads verts : "Upgrade Tree", Fruit Picker, Waiter + pad violet Auto Sell a la meme place (x 12, z 70, a cote de Take Juices) ; dossier `Looks` (panneau FRESH JUICE! de More Customers) |
| `tools/build-map/02f-base-annex-markers.luau` | Studio | Annexe (BaseTemplate.Annex) : terrasse fermee + portail + bas de la cage d'ascenseur, salle du Rebirth (vitre "Reach Floor 10", machine doree) ; marqueurs de l'etage |
| `tools/build-map/02l-floor-setup.luau` | Studio | `FloorTemplate.Setup` : les 4 pads FREE de l'usine a construire (positions dans `Config/Setup`), voir `usine-a-construire.md` (2026-11-21) |
| `tools/build-map/02k-floor-walkway.luau` | Studio | Allee gris-bleu en relief (plaque de 0.4, solide) dans les passages de l'etage : `FloorTemplate.Building.Walkway` (Entry, Corridor, ToBack, ToSales, SalesWalk) |
| `tools/build-map/02j-base-elevator.luau` | Studio | Annexe : panneau ELEVATOR colle sur la cage de l'ascenseur, face nord (2 tuiles `TowerUpgradeId`, a CLIQUER, dessin `Util/UpgradeTile`) + cabine `Annex.ElevatorBase.Cabin` |
| `tools/build-map/07-floor-studs.luau` | Studio | Dessus des sols (TopSurface Inlet) -> Studs comme la route ; FloorTemplate, BaseTemplate, Map. A lancer en dernier |
| `src/server/Lib/OwnerBadge.luau` | serveur | Logo du proprietaire au sommet de sa tour (photo ronde de l'avatar, nom, nombre de rebirths en jaune), appele par FloorService |
| `tools/build-map/02h-floor-stairs.luau` | Studio | Escalier (voies A/B), dalle des voies, trou + garde-corps (murs invisibles seulement sur l'etage a acheter), vitre d'achat, balcon, cage d'ascenseur (etages 2+) |
| `tools/build-map/preview-tower.luau` | Studio | Apercu temporaire de la tour (`Workspace._PreviewBase`, a retirer) |
| `tools/build-map/preview-factory.luau` | Studio | Apercu de toute l'usine "tout achete" en mode Edit (`Workspace._Preview`, non archivable : jamais sauvegarde ni copie dans le Play). Voir `apercu-edit.md` |
| `tools/build-map/02g-base-boards.luau` | Studio | Panneaux d'ameliorations (tuiles colorees) : Conveyor (mur du fond), Juice Table (mur de droite), Customers (facade), un panneau suspendu au-dessus de chaque mixeur |
| `tools/build-map/03-decor.luau` | Studio | `Map.Decor` : le coeur (arbres des couloirs, foret derriere les bases, spawn) + **les alentours** (2026-11-27 : foret, collines a grimper, rochers, mares dans la bande entre l'ancien coeur et les murs). `REBUILD_CORE` (faux par defaut : garde le coeur de la place), `SAMPLE_NORTH` : voir "Alentours et fond de carte" |
| `tools/build-map/09-mountains.luau` | Studio | **v3 (2026-11-27)** : `Map.Backdrop`, tout ce qui est derriere les murs : crete en gradins + grands arbres, rocher de la cascade, montagnes a facettes, volcan. Reglages `FRUITY_VOLCANO` (vrai), `FRUITY_REST` (faux), `SAMPLE_NORTH` : voir "Alentours et fond de carte" |
| `tools/build-map/04-lighting.luau` | Studio | Eclairage |
| `tools/build-map/05-shadows.luau` | Studio | Coupe les ombres inutiles (decor, petites pieces...), a lancer en dernier |
| `src/client/Controllers/ShadowController.luau` | client | Seul l'etage du joueur projette des ombres (evite les ombres des etages du dessus) |
| `tools/build-map/check-zfighting.luau` | Studio | Detecteur de z-fighting (lecture seule) : liste les faces visibles qui se superposent |
| `src/server/Services/BaseService.luau` | serveur | Clone le modele dans les 6 emplacements, attribution, apparition, nettoyage, prompt E des portes fermees |
| `src/server/Services/NotifyService.luau` | serveur | Message court au joueur (remote `Notify`) |
| `src/client/Controllers/NotifyController.luau` | client | Affiche le message en haut de l'ecran |
| `src/shared/Config/Map.luau` | partage | Nombre de bases, textes, noms et prix des salles fermees |

## Reconstruire la carte

Studio en mode Edit, lancer chaque script dans `execute_luau` (MCP) ou la barre de commande, dans
l'ordre : `01`, `02a` ... `02h`, `02i` (coin des dons, `docs/systems/dons.md`), `02j` (panneau ELEVATOR + cabine, `tour-etages.md`), `02k` (allee), `02l` (pads FREE, `usine-a-construire.md`), `03`, `04`, `05`, puis `06-no-touch` (CanTouch = false sur les modeles, a relancer apres tout 02*), puis `07-floor-studs` (sols en Studs, a relancer apres 01 et 02*), puis `08-leaderboards` (2 murs-ecrans des classements aux deux bouts de la route, `classements.md`), puis `09-mountains` (fond de carte derriere les murs, a relancer apres `01` ou `03` ; il n'a besoin ni de `05` ni de `06` : ses pieces sont deja sans ombre et sans CanTouch, comme celles de `03`). Chaque script est relancable (il detruit et recree sa
partie ; `02a` recree les deux modeles, donc relancer ensuite `02b` a `02j` puis `05`). Les scripts
02a, 02e, 02f, 02g et 02h chargent une copie fraiche de la Config. Verifier avec `preview-tower` +
`check-zfighting` (0 ligne), retirer l'apercu, puis `save_place`.
Astuce (2026-11-19) : copier les scripts dans un dossier temporaire `src/shared/_BuildMap/` ; Rojo
les envoie dans Studio comme ModuleScripts, qu'on lance avec un `require` d'une copie
(`m:Clone()`). Supprimer le dossier a la fin (il ne doit pas rester dans le jeu).

## Fonctionnement

- Carte : zone jouable **1380 x 1060** (limites invisibles `Map.Bounds` : North/South a z +-530,
  East/West a x +-690 ; 800 de haut depuis le sol). Le 2026-11-27 : hauteur 80 -> 800, puis murs
  recules de 300 studs de chaque cote (avant 780 x 460, colles derriere les usines ; constante
  `GROUND_SIZE` de `01-ground-road`). Route de 600 x 24 le long de l'axe X, place
  du spawn a l'ouest. Bases espacees de 200, a 30 studs du centre de la route (agrandi le
  2026-11-19 : "plus spacieux, zones delimitees, l'arbre trop colle aux autres trucs") :

```
   [Base 1]      [Base 2]      [Base 3]        (nord, z +30 -> +168)
 SPAWN ======== ROUTE (clients) ==========
   [Base 4]      [Base 5]      [Base 6]        (sud, tournees de 180 degres)
```

- Une base vue de dessus, route en bas. Repere local : origine au bord avant, +Z vers le fond ;
  **vu de la route, +X est a gauche**. Terrain : x -46 -> 110, z 0 -> 138. Salle principale
  x 1 -> 109, z 15 -> 135 (108 x 120). Murs de **36** de haut (doubles le 2026-11-19 : "plafond
  2 fois plus haut") : rangee du bas jusqu'a 18 (portes, fenetres), corniche menthe, rangee du
  haut avec hautes fenetres (y 22 -> 31) ; poutres et cadre du puits de lumiere a 34.6 -> 35.8 ;
  lampes et panneaux de zone a la meme hauteur qu'avant, sur de longs fils. Pas de toit (ciel ouvert).
- L'herbe du terrain (`Lot.Ground`, dessus a 0.3) est en **8 morceaux** qui entourent les sols du
  batiment (salle principale, seuil, bar a cocktails) : plus d'herbe cachee 0.2 sous le sol gris,
  qui clignotait vue de loin (z-fighting, corrige le 2026-11-19).
- Regle anti z-fighting : deux sols qui se chevauchent ont des dessus ecartes d'au moins 0.15.
  Sols de zone 0.5 -> 0.65 (a l'interieur de la bordure, sans la chevaucher), bordure 0.5 -> 0.75 ;
  cour : place et chemin a 0.45, dalles foncees a 0.6. Ne jamais laisser de copie de base
  (ex. `_PreviewBase`) dans le Workspace : mal placee, son sol tombe pile sur l'herbe de la map.

Plan en U refait le 2026-11-19 (soir), dans l'ordre de la chaine : verger -> etagere -> bar a jus
-> comptoir -> argent. Le bar a jus est passe a DROITE (vu de la route), dans l'espace vide : il ne
chevauche plus le verger (avant : deux sols de zone au meme niveau = z-fighting).

```
 z=135 +------------------------------- mur du fond ---------------------------+----------------+
       | VERGER (zone verte)            | ETAGERE A FRUITS (zone beige)       | BAR A COCKTAILS|
       | jardiniere 38 x 36, arbre au   |  etagere 30 caisses "x12" [boite][Conveyor] (ferme)  |
       | centre (x 87, z 116), puits de |  x 30-54                    tapis   |== porte E ===  |
       | lumiere                        |   ===== tapis le long de la rangee ===|                |
 z=92  | [pad Fruit Picker][pad Upgrade Tree] [MIX 4][MIX 3][MIX 2][MIX 1] (panneaux au-dessus) |
       |                                  [op]   [op]   [op]   [op] (allee)  | TERRASSE       |
       |  (allee)                         [ table a jus surelevee ] [Juice Table] (dehors,     |
 z=60  |                                                                     |  fermee)       |
       |   VENTE (zone bleue) :                  [pad Auto Sell]            |== porte E ===  |
       | [pad Robux] [table $] ==== COMPTOIR (MONEY / HOUR au-dessus) ==== [Customers]  |
 z=14  +---------------- facade "JUICE FACTORY" ---------------------+-- PORTE --+  (cloture)  |
       | [Billboard]            clients (dalles, 5 places)          haies         |             |
 z=0   x=110                                                                   x=0          x=-46
                                        ROUTE
```

- Couleurs (2026-11-19 soir, captures de reference de l'utilisateur) : palette en tete de `02a`.
  Murs (226, 232, 244) studs, bande basse en DiamondPlate, sol (104, 110, 128), cadres / piliers /
  poutres acier, bas des 4 piliers de la salle raye jaune / noir (`PillarHazard`), lampes = neons
  (`Housing` + `Tube`) sous les poutres, vitres cyan, cour et chemin orange, enseignes du
  proprietaire en bois orange. Herbe (01), arbres (03) vert vif ; eclairage (04) plus clair.
- Passe "moins flashy, plus pro" (2026-11-19, nuit) : eclairage (04) adouci (Brightness 3 -> 2.2,
  ambiances plus sombres, ombres plus douces, brume legere, bloom discret, saturation -0.08 et
  contraste +0.1). Herbe / terrain des bases (72, 170, 62), collines adoucies, route (70, 78, 96).
  Vitres bleu pale (176, 208, 228) a 0.6 de transparence. Zones moins saturees (verger 104,178,92 ;
  etagere 234,172,74 ; bar a jus 222,116,152 ; vente 84,148,222), sol de zone teinte a 22 %.
  Pads employes : dessus (100, 204, 78), neon (110, 236, 84). Applique aussi directement dans
  Studio (Lighting, Workspace, ServerStorage.BaseTemplate) : sauvegarder la place.
- **2026-11-20 : plus de sol de zone teinte ni de bordure de couleur** (demande : "tu retires les
  delimitations rose, vert, jaune, bleu") : les zones n'ont plus que leur panneau suspendu. Le
  joueur suit une **allee** (`02k`) : plaque gris-bleu (74, 85, 108) de 0.4 au-dessus du sol,
  solide, qui va de la porte (toute sa largeur, x 8-18, depuis le 2026-11-20 ; le tapis des dons
  finit a x 7.5) au couloir vente / bar a jus (x 8-60.5, z 52-62), monte entre le bar a jus et
  l'escalier jusqu'a l'etagere (x 53.5-60.5, z 107.5) et descend vers les pads du comptoir
  (x 49-55 puis z 27-33, x 49-82). Sol (74, 80, 93), murs (238, 242, 250) en **Inlet** (carres en creux, plus en Studs), bande basse
  (146, 156, 178) : un peu plus fonces (avant 104,110,128 / 226,232,244 / 162,172,192).
  Eclairage (04), cale en jeu sur les captures de reference : ciel Cartoon (cyan) supprime (ciel
  par defaut), EnvironmentDiffuseScale 0.6, Specular 1, Brightness 2.4, ambiances 110,110,114 /
  128,128,132, teinte 255,244,232, saturation 0.05 : perso et murs bien eclaires, sans cyan.
  Le texte ci-dessous sur les sols de zone est l'historique.
- Zones (jusqu'au 2026-11-20) : sol ardoise teinte (Inlet comme tous les sols) avec une large bordure de couleur vive + grand panneau suspendu aux
  poutres, lisible depuis l'entree. **Les sols de zone ne se chevauchent jamais**. Revues le
  2026-11-19 (demande : "fais bien rentrer tous les trucs dedans, de la place pour marcher") :
  chaque zone contient tout son poste (verifie par script : boites englobantes) :
  ORCHARD (x 62-108, z 84-134 : jardiniere, pad Upgrade Tree, pad Fruit Picker),
  FRUIT SHELF (x 14-60, z 108-134 : etagere, plancher, pad Drop Fruits ; le dos de l'etagere touche
  le mur, 0.4 apres la bordure), JUICE BAR (x 4-54, z 64-105 : 4 mixeurs, allee, table, pad
  Take Juices), SALES (x 36-108, z 15-54 : comptoir, pads Drop
  Juices / Collect Cash / Auto Collect, table a argent, pad Auto Sell). Allees libres :
  x 54-62 (bar a jus / verger) et z 54-64 (vente / bar a jus). Detecteur `check-zfighting.luau` :
  0 cas apres la relance (2026-11-19).
- **Pads d'action** (2026-11-19, on se tient dessus, pas de touche E) : meme forme que les pads
  d'employes (dalle + dessus a studs + neon), 7 x 7, titre au-dessus. `Production.FruitDropPad`
  (orange, x 38.5-45.5, z 118.5-125.5, sur le plancher), `Production.TakeJuicePad` (rose, x 18.5-25.5,
  z 66.5-73.5, devant la table a jus), `Counter.JuiceDropPad` (bleu, x 56.5-63.5,
  z 19.5-26.5, derriere le comptoir), `Counter.CashPad` (jaune, x 83.5-90.5, z 24.5-31.5, devant
  la table a argent). Chacun a une `PadZone` invisible testee par le serveur.
- Production (02c) : etagere, caisses, plancher ecrits puis **retournes en X** (`x' = 58 - x`) et
  decales de +20 en Z (fonction `place()`) : etagere x 30-54 (z 131-134.7, contre le mur du fond depuis le
  2026-11-20 soir, `SHELF_DZ`), plancher z 118-131.2. Bin10 (le plus rare) au bout cote tapis, Bin1 a l'autre bout.
  Depuis la refonte du mixeur (2026-11-19), tapis, mixeurs et table sont ecrits en **coordonnees
  finales** (`MIRROR = false`) : boite du tapis x 23.4-28.6 (z 127.5-133.5), montee x = 26
  (z 130 -> 101.5, y 4.8 -> 16.5), tapis de la rangee x 6.5-50 (z 101.5, y 16.5), **4 mixeurs**
  meubles 9 x 9 en x 8-17 / 18.5-27.5 / 29-38 / 39.5-48.5 (z 90-99, ecart 1.5), allee devant les
  panneaux z 83-90 (pads des operateurs 5 x 5), table a jus surelevee centree en x 22 (z 75-82,
  dessus a 3.4 ; 11 / 16 / 21 de long selon Juice Table). Depuis le 2026-11-19 soir, plus de Juice
  Cooler ni de panneau Juice : panneaux Conveyor (mur du fond, x 11.6-18.4), Juice Table (mur de
  droite, z 75-82), Customers (facade, x 33-46) et BlenderSign1..4 (suspendus au-dessus des mixeurs,
  y 15.3-21.8) ; "3/5" des bols remonte au-dessus (y 22.9). Le joueur contourne la rangee par l'est (x 48.5-64) ; la porte du bar a
  cocktails reste libre. Comptoir (02d) decale de (+16, 0, 0) : x 48-80.
- Decor retire le 2026-11-19 (soir) car inutile ou confondu avec de vrais fruits : fleurs autour
  de l'arbre, massifs de fleurs de la cour (remplaces par des haies vertes), petits fruits sur le
  comptoir, employes en blocs et chariots de fruits / gobelets des postes d'employes.

### Alentours et fond de carte (2026-11-27)

Demande : "recule les Bounds et ajoute des montagnes, volcan, arbres... dans le theme de Roblox et de
notre jeu". Choix de l'utilisateur : murs a +300 studs, montagnes et volcan en decor geant derriere
les murs (on ne grimpe pas dessus), et **deux versions de la carte : une fruitee, une sans**.

Du centre vers le fond :

| Plan | Ou | Quoi | Script |
|---|---|---|---|
| Alentours (on y marche) | entre l'ancien coeur (x +-384, z +-214) et les murs | Foret (un arbre possible par case de 30 studs, bosquets et clairieres par bruit, arbres plus gros et plus serres pres des murs), collines a grimper (gradins de 5 studs au plus), rochers, buissons, fleurs, 4 mares | `03-decor` |
| Crete | 0 a 190 studs derriere les murs | Talus en gradins a studs (10 a 55 de haut), falaises grises, grands arbres dessus et derriere. Montre la limite (on est dans une vallee) et cache l'horizon plat | `09-mountains` |
| Cascade | nord, x 100 | Rocher gris a chapeaux d'herbe (84 de haut), 2 chutes, bassin a cheval sur le mur (rive de sable solide, liquide sans collision), ecume | `09-mountains` |
| Montagnes | anneaux a 1500 et 2150 studs | Pics a facettes (4 CornerWedgeParts par pyramide), neige, pied vert, 480 a 1100 de haut | `09-mountains` |
| Volcan | nord-ouest (-900, 1700) | Tronc de pyramide, 660 de haut, coulees Neon sur la face cote carte, 1 emetteur de fumee | `09-mountains` |

**Choix final (2026-11-27, apres l'echantillon du cote nord montre en 2 versions) : "garde le volcan
fruits et pour le reste garde le naturel".** Deux reglages en tete de `09-mountains` ; tout ce qui en
depend est dans le modele `Backdrop.Details` :

| Reglage | Valeur dans la place | Vrai | Faux |
|---|---|---|---|
| `FRUITY_VOLCANO` | **vrai** | volcan de jus : 5 coulees (orange, fraise, raisin, citron vert, citron), brume orangee, 5 fruits geants craches en eventail au-dessus du cratere | lave orange, fumee grise |
| `FRUITY_REST` | **faux** | cascade de jus (Neon) + paille geante + glacons ; fruits geants : 11 sur la crete, 4 au pied des montagnes, 2 dans la foret (solides) | cascade d'eau bleue ; 2 tas de gros rochers comme reperes dans la foret (x -520, z 380 et x 520, z -380) |

- Fruit geant = le fruit voxel du jeu (`ReplicatedStorage.FruitAssets.<Id>`, une `UnionOperation`)
  clone et agrandi : **1 seule piece par fruit**. Si `FruitAssets` manque, le script le dit et saute.
- Orange en Neon : la couleur doit etre foncee (255, 116, 10), sinon elle vire au jaune.
- Poids : tout est ancre, sans ombre, sans CanTouch. Derriere les murs : aucune collision, modeles
  `Persistent` (StreamingEnabled, rayon 1024 : sinon le fond disparaitrait). Dans la zone : les arbres
  sont dans `Decor.Trees.Outskirts` (caches en Low Quality avec `Decor.Trees`, vus par CameraFade),
  collines / rochers / mares dans `Decor.Hills.Outskirts` (toujours visibles). Fumee et ecume sont
  des particules : Low Quality les eteint.
- L'ancien anneau de collines (z +-220, x +-396) est retire par `03-decor` : il aurait ferme l'acces
  a la nouvelle bande.
- `03-decor` garde le coeur deja dans la place (`REBUILD_CORE = false` : les retouches a la main
  dans le coeur ne sont pas perdues). `REBUILD_CORE = true` seulement pour une place neuve.
- `03-decor` reserve 3 places sans arbre pour ce que `09-mountains` pose dans la zone (bassin de la
  cascade, 2 reperes) : garder les deux listes d'accord (`blocked` / `LANDMARKS`, `CASCADE_X`).
- Aux 4 coins, deux blocs fixes bouchent la fente entre la crete est / ouest et la crete nord / sud.
- `SAMPLE_NORTH = true` (dans les deux scripts) ne pose que le cote nord, avec le meme tirage que
  la carte complete : a utiliser pour montrer un echantillon avant un gros changement.
- **Etat dans la place (2026-11-27) : tout le tour est pose.** Mesures : alentours 2 595 pieces
  (615 modeles d'arbres / buissons / fleurs, 74 collines / rochers / mares), fond 1 447 pieces en
  29 modeles (4 cretes, 23 montagnes, volcan, Details), carte entiere 5 103 pieces (avant : ~1 190).
  Captures : `docs/references/fond-de-carte/`.
- Pour changer un reglage : modifier la valeur en tete de `09-mountains`, relancer le script, puis
  `check-zfighting` (ligne `Map` a 0). Pour lancer un script de carte : voir "Reconstruire la carte".

### Z-fighting (check-zfighting)

Apres une reconstruction, lancer `tools/build-map/check-zfighting.luau` (lecture seule) : il liste
les faces de pieces bloc de `BaseTemplate`, `Map` et `TreeStages` qui sont dans le meme plan (ecart
< 0.05), se recouvrent, sont visibles et de couleur ou matiere differente. Objectif : 0 ligne.
Il ignore les faces vers le bas, les pieces de meme couleur et les MeshPart / Union (a l'oeil).
`03-decor` a une passe anti z-fighting a la fin (decor au hasard : un dessus de feuillage peut
tomber au niveau d'un dessus de colline ; on grandit l'une des deux pieces de 0.06 par le haut).

### Ombres (05-shadows)

`tools/build-map/05-shadows.luau`, a lancer **en dernier** (relancable). Depuis le 2026-11-20 c'est
une **liste blanche** : seules gardent leur ombre les pieces des dossiers `Tree` (arbre fruitier),
`Blenders` (mixeurs) et `Machines`, plus les modeles `ServerStorage.TreeStages`. Meme la, les petites
pieces (< 2.6 studs), les fines (< 0.35), les transparentes et les decoratives (sans collision ni
requete) restent sans ombre. Tout le reste est sans ombre : murs, balcons, terrasse, ascenseur,
escaliers, comptoir, convoyeur, palettes, panneaux, dons, lot, carte et decor. Le soleil est au
zenith (`04-lighting`), donc les ombres gardees tombent juste sous l'objet. Resultat le 2026-11-20 :
BaseTemplate 0 avec ombre / 337 ; FloorTemplate 90 / 1428 ; TreeStages 46 / 218 ; Map 0 / 1192.
Les objets crees en jeu (fruits, gobelets, billets, outils de fruits) coupent leur ombre dans le code.

**2026-11-27 (ombres "super legeres") :** `Counter` (comptoir) et `Production` (etagere, bar a jus,
convoyeur) rejoignent la liste blanche ; `ShadowSoftness` 0.35 -> 0.5 (`04-lighting`). Resultat :
FloorTemplate 143 avec ombre / 1435 (avant 90), BaseTemplate 0, TreeStages 46, Map 0.
**Ombres par etage (`src/client/Controllers/ShadowController.luau`) :** les sols ne projettent pas
d'ombre, donc un objet de l'etage N jetait son ombre dans l'etage N-1 (taches sur le haut des murs,
PNJ fantomes au sol). Le client ne garde que les ombres de l'etage ou se trouve le joueur (meme
hauteur dans chaque tour, `FloorWatch.FloorOfPosition`, teste toutes les 0.25 s) ; les autres etages
ont `CastShadow = false` en local et le retrouvent quand le joueur y arrive (sauf piece devenue
fantome, transparence >= 0.5). Pieces sans ombre au depart : jamais touchees. Bonus : moins de
pieces qui projettent une ombre en meme temps.
Soleil penche a 14 h depuis le 2026-11-27 (ombres "plus visibles", demande utilisateur ;
`04-lighting`). Sans ShadowController, un soleil penche faisait tomber les ombres des etages du
dessus en taches sur les murs ; avec lui, seul l'etage du joueur projette (verifie en Play : seul
l'etage 1 de chaque tour a des ombres, etages fermes et carte a 0).
**Attention :** le Studio du PC de Natixe n'affiche aucune ombre (meme un bloc de test), en Play
comme en Edit ; l'appli Roblox les affiche. Juger les ombres dans l'appli, pas dans Studio.

- Contenu du modele (noms utilises par le code) :

| Chemin dans la base | Role |
|---|---|
| `Origin` | PrimaryPart (pivot du modele) |
| `Tree.FruitArea` | Carre ou tombent les fruits (26 x 26 depuis le 2026-11-20, invisible), hors tronc |
| `Tree.TreeLabelAnchor` | Point du texte "Tree full!" |
| `Production.Bins.Bin1..30` | Fond des caisses. 1-10 Common, 11-20 Uncommon, 21-30 Rare |
| `Production.FruitDropPad` | Pad "Drop Fruits" sur le plancher de l'etagere (`PadTop` + `Tag`, `PadZone`) |
| `Production.ConveyorStart` / `ConveyorTurn` | Debut du tapis / haut de la montee, sur le tapis de la rangee (animation client) |
| `Production.Blenders.Blender1..4` | Les mixeurs (avant le 2026-11-19 : `Production.Press`). `Build` (pieces, `Cabinet`, `Panel` = prompt E "Blend", `ButtonGo`, `SpoutTip`, `Juice`, `Blade`, `BowlFloor`), `Chute` (goulotte), `FeedPoint`, `BowlLabelAnchor`, `BlenderNOperator` (place de l'operateur), `Operator` (pad, UpgradeId `OperatorN`). Mixeurs 2-4 : UpgradeId `BlenderN` |
| `Production.JuicePallet` / `JuicePile` / `JuiceLabelAnchor` | Table a jus / zone des gobelets / texte "n/max" |
| `Production.TakeJuicePad` | Pad "Take Juices" devant la table a jus (`PadZone`) |
| `Counter.JuiceDropPad` / `Counter.CashPad` | Pads "Drop Juices" (derriere le comptoir) et "Collect Cash" (devant la table a argent), `PadZone` |
| `Counter.CounterTopArea` / `CounterLabelAnchor` | Dessus du comptoir / texte "n/max" |
| `Counter.MoneyPile` / `MoneyLabelAnchor` | Dessus de la table a argent (billets, prompt E "Collect") / montant |
| `Counter.AutoCollectPad` | Pad violet Robux "Auto Collect" (`PadTop` + `Tag`, `PadZone`), chaque etage depuis le 2026-11-21 (avant : `OnlyGround`) |
| `Counter.InstantSellPad` | Pad violet Robux "Instant Sell" (2026-11-21), juste a droite de Drop Juices (x 64.5-70.5, z 20-26), chaque etage |
| `Machines.<UpgradeId>` | Pad a acheter : Tree ("Upgrade Tree"), Collector, Server (voir `ameliorations-employes.md`) |
| `Boards.<Board>.<UpgradeId>` | Tuile d'un panneau d'ameliorations (ConveyorBoard, JuiceTableBoard, SalesBoard, BlenderSign1..4) |
| `Looks` | Decor qui change avec les niveaux (panneau FRESH JUICE!) ; pieces `LookId` / `LookLevel` aussi dans Production (tapis, mixeurs, table) et Counter (`SpeedDecor`) |
| `Counter.IncomeSign` | Panneau "MONEY / HOUR" (texte `Board.Display.Value`, CustomerService) |
| `Markers.SpawnPoint` | Apparition du joueur (juste apres la porte) |
| `Markers.CustomerEntry`, `CustomerSpot1..5` | Arrivee des clients (trottoir) et places devant le comptoir (dehors) |
| `Markers.CollectorHome`, `ShelfDrop`, `ServerHome`, `ServerPallet`, `ServerCounter` | Postes et trajets des employes R15 (bas du marqueur = sol). Operateurs : dans chaque mixeur |
| `Entrance.OwnerSign` | Panneau du proprietaire (TextLabels `OwnerText`, dehors + dedans) |
| `OwnerBadge` | Cree en jeu (Lib/OwnerBadge, Model `Persistent`) : `Anchor.Badge` (BillboardGui 100 x 66 studs, ~ largeur de l'usine : `Ring.Avatar` = photo `rbxthumb://type=AvatarHeadShot`, `OwnerName`, `Rebirths` = "N Rebirths" en jaune plus petit, sans fond ni icone) pose 3 studs au-dessus de l'avant du toit de l'etage le plus haut (etage ferme compris), pas AlwaysOnTop (choix utilisateur), cache si la base est libre. Mis a jour par `FloorService.refreshAnnex` (achat d'etage, rebirth) |
| `Floors.FloorN` | Les etages (FloorService, voir `tour-etages.md`) : `Tree`, `Production`, `Counter`, `Markers`... sont DANS chaque etage |
| `Annex.Terrace` / `Annex.RebirthRoom` | Terrasse (ouverte a l'etage 2) et salle "???" (ouverte a l'etage 10) |
| `Setup.<id>.Pad` | Pads FREE de l'usine a construire (PlantTree, BuildShelf, BuildBlender, OpenShop) ; caches sauf celui de l'etape en cours (SetupService) |
| `Dynamic` | Tout ce qui est cree pendant le jeu : vide au depart du joueur |

- Attribution : premiere base libre (ordre 1 -> 6). Attribut `OwnerUserId` sur la base (0 = libre),
  attribut `BaseId` sur le joueur. Panneau `"<DisplayName>'s Juice Factory"` ("Free Factory" si libre).
- Apparition : a chaque `CharacterAdded`, le personnage est deplace sur le `Markers.SpawnPoint` de son
  etage le plus haut (point donne par FloorService, `BaseService.SetSpawnResolver` ; l'etage est
  d'abord charge chez le client avec `RequestStreamAroundAsync`).
  Le personnage regarde **bien droit vers l'interieur de l'usine** (axe +Z de l'etage, porte cote Z
  petit) : seule la position de `SpawnPoint` compte, pas sa rotation (piece tournee de 33 degres
  dans le .rbxl, ce qui donnait une vue de travers ; corrige le 2026-11-22 dans `FloorService.spawnCFrame`).
- Depart : `OnBaseReleased` (les services nettoient), `Dynamic` vide, panneau "Free Factory".
- 7e joueur : pas de base, message `ServerFullMessage`, il attend.
- Plus de salles a acheter (`ZoneLocks` / `Map.LockedZone*` supprimes le 2026-11-20) : la terrasse et
  la salle "???" s'ouvrent avec les etages (FloorService, `tour-etages.md`).
- API serveur : `BaseService.GetBase(player)`, `GetOwner(base)`, `GetBases()`,
  `OnBaseAssigned(cb(player, base))`, `OnBaseReleased(cb(player, base))`.

## Remotes

| Nom | Sens | Arguments | Verifications |
|---|---|---|---|
| `Notify` | serveur -> client | texte (anglais, depuis la Config) | client : type string, UTF-8 valide, longueur max `MaxNotifyLength` |

Teleport entre les etages : `FloorTeleport` (voir `tour-etages.md`).

## Donnees sauvegardees

Aucune (la base n'est pas sauvegardee ; les niveaux le sont, voir `sauvegarde.md`).

## Configuration

`Config/Map.luau` : `MaxBases`, `OwnerSignFormat`, `FreeSignText`, `ServerFullMessage`,
`StandAssignedMessage`, `MaxNotifyLength`.
Positions des machines, pads et panneaux : dans `02e` et `02g`.

## Tests (Studio)

`game.ServerStorage.Debug.Call:Invoke("Base", "SimulateFull", "<Nom>")` : serveur plein simule ;
`"EndSimulation"` : retour a la normale ; `"Get"` : nom de sa base.

## Problemes connus / a faire

- Le detecteur `check-zfighting` ne voit ni les montagnes (Wedge / CornerWedge) ni les fruits geants
  (Union) : regardes a l'oeil sur les captures seulement.
- Fond de carte pas vu sur telephone ni dans l'appli Roblox (brume, fumee du volcan, poids :
  1 447 pieces toujours chargees + ~2 600 dans la zone). Si un telephone rame : Low Quality cache deja
  les arbres ; sinon baisser la densite (`CELL` dans `03-decor`).
- `check-zfighting` du 2026-11-27 : `FloorTemplate` a 5 lignes (pas liees a la carte, pas regardees).
- Taille du serveur (6) : reglage de l'experience a faire par l'utilisateur.
- Non teste : 2 joueurs, telephone. Carte reconstruite le 2026-11-19 (version 52 de la place).
- Rojo etait connecte mais ne poussait plus les changements vers Studio le 2026-11-19 (apres
  14:30) : le code a ete reporte a la main dans Studio (sources identiques, longueurs verifiees).
  Reconnecter Rojo (Disconnect / Connect) avant la prochaine intervention.
- La camera peut passer derriere une poutre (poutres sans collision : elle ne saute pas).
