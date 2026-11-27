# Systeme : Cinematique d'ouverture (profil neuf)

**Statut :** fonctionne (version ~27 s du 2026-11-27 : fond de carte, plan d'ouverture, lumiere du matin + fond flou, marche et course refaites ; rejouee en entier en Play Studio PC a 1 joueur, R15 ; telephone, manette, R6 et 2 joueurs pas testes)
**Derniere mise a jour :** 2026-11-27

## Role

Un profil NEUF (`IntroSeen == false` et `Setup == 0`) voit UNE fois une petite histoire de ~27 s :
la camera part du ciel (foret, montagnes, volcan de jus) et descend jusqu'a lui ;
son personnage marche dans une foret calme, voit DE LOIN l'arbre niveau 10 de l'etage 1 charge de
fruits, fait "Wow!" bras en l'air et court jusqu'a lui, reflechit ("?"), voit une pelle plantee ("!"),
l'arrache, creuse, l'arbre tombe et devient un petit objet qui vole dans ses mains (comme dans
Minecraft) : **l'arbre niveau 1**, qu'il brandit au-dessus de sa tete. Fondu au blanc : il est dans son usine vide,
l'arbre niveau 1 dans les mains, et le tutoriel commence (`tutoriel.md`) : on appuie sur E au
milieu de la pelouse, la ou poussera l'arbre (pas de pad, 2026-11-22).
**Musique de fond** : muette pendant toute la cinematique, elle demarre a la fin (MusicController
attend `IntroPending` du serveur, puis coupe tant que `IntroPending` ou `IntroPlaying` est vrai).
**Pas de Skip** (bouton, clic, toucher et manette retires le 2026-11-22 a la demande de l'utilisateur).

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/shared/Config/Intro.luau` | partage | Durees (`Times`), plans de camera (`Shots`), positions dans le decor (chemin, pelle plantee, creusage), textes, arbre tenu (`HoldOffset`, `HoldArmDegrees`), effets |
| `src/server/Services/IntroService.luau` | serveur | Seul a ecrire `Data.IntroSeen`. Attribut joueur `IntroPending` ; remote `IntroDone` |
| `src/server/Services/SetupService.luau` | serveur | Attribut joueur `HoldingSapling` (vrai tant que `Setup == 0`) |
| `src/client/Controllers/IntroController.luau` | client | Joue la cinematique (decor clone, acteur anime en code, camera, bulles) ; attribut local `IntroPlaying` pendant l'intro (lu par le tutoriel) |
| `src/client/Controllers/SaplingController.luau` | client | Arbre niveau 1 devant les joueurs qui ont `HoldingSapling` (chacun le voit chez soi, pour tous les joueurs) |
| `src/client/Controllers/CarryPoseController.luau` | client | Bras tendus devant (60 deg) pour `HoldingSapling` |
| `tools/build-map/02m-intro-set.luau` | Studio | Construit `ReplicatedStorage.IntroSet` (dans le .rbxl, hors Rojo). Depuis le 2026-11-27 : sol de 2040 studs, chemin jusqu'a la crete, `Props` (18 buissons, 44 fleurs, 14 cailloux), `Backdrop` = le fond de la carte en plus petit (voir "Decor") |
| `docs/references/cinematique/` | doc | Captures du Play (ouverture, marche, gros plan flou, chute de l'arbre) |

## Decor (2026-11-27 : "plus realiste, avec des montagnes en fond comme sur la map")

`IntroSet` = 2 621 pieces (avant 1 279), toutes ancrees, sans collision ni CanTouch. Repere : pied du
grand arbre = origine, la marche va vers +X, les cameras sont cote +Z.

| Partie | Quoi |
|---|---|
| `Ground`, `Path`, `Clearing` | Herbe a studs de 2040 de cote (elle va au pied des montagnes), chemin de terre de la crete a la clairiere |
| `Forest` | 228 arbres copies de la carte (meme tirage qu'avant). 36 projettent une ombre (ceux a moins de 46 studs du chemin et de la clairiere), les autres non |
| `Props` | Buissons et cailloux derriere le chemin (jamais entre la camera et lui), fleurs basses des deux cotes et autour de la clairiere. Places libres : cameras posees (`Intro.Shots` en repere "Set"), pelle, trou, zone de chute |
| `Backdrop` | Le fond de `09-mountains` a l'echelle 0.4 et plus pres (meme taille a l'ecran) : crete en gradins a 190 studs sur les 4 cotes, 180 grands arbres simples (3 pieces) entre la foret et la crete, 20 montagnes a facettes en 2 anneaux (600 et 880 studs ; base verte, roche grise, neige), volcan de jus a (536, -475) avec 5 coulees, fumee et 5 fruits geants |

- Le volcan est place pour etre vu dans le plan d'ouverture et derriere l'arbre qui tombe.
- Le 1er plan de `Intro.Shots` sert aussi au script : les arbres sur la route de la camera
  d'ouverture sont retires (2), sans toucher au tirage du reste.
- Trois tirages separes (foret + fruits, petits details, fond) : retoucher l'un ne deplace pas les autres.
- Apres un changement de `Config/Intro` qui touche le decor (`ActorStart`, 1er plan, `Times.open`) :
  relancer `require(game.ServerScriptService.DevTools.BuildMap["02m-intro-set"]:Clone())` en mode Edit.

## Fonctionnement

1. Serveur, au chargement de la sauvegarde : `IntroPending = not IntroSeen and Setup == 0`,
   `HoldingSapling = Setup == 0`. Sans sauvegarde chargee : pas d'attribut, pas d'intro.
2. Client (`IntroPending` vrai, personnage present, avatar charge ou 1.5 s max) :
   - ecran blanc tout de suite, HUD et ScreenGuis caches (ceux que le Preloader rallume pendant
     l'intro sont recaches puis rendus a la fin ; le ScreenGui `TouchGui` n'est jamais touche),
     touches E coupees (`ProximityPromptService.Enabled`), racine du vrai personnage ancree en local
     (il ne bouge pas) ;
   - **telephone : joystick et bouton de saut caches (2026-11-27)** par
     `GuiService.TouchControlsEnabled = false` (API officielle : Roblox desactive lui-meme `TouchGui`),
     recache si un autre script le rallume, valeur d'avant remise dans `unlockPlayer` (fin normale
     ET cinematique qui plante) ;
   - decor `IntroSet` clone a `Intro.SetOrigin` (y = 1200, loin de la carte), chez ce joueur seulement ;
   - acteur = copie locale du personnage (`Archivable`), sans scripts, Animator, tags ni attributs,
     racine ancree. **Animations faites en code** : angles des articulations ecrits a chaque image
     (`Transform`), rotation donnee dans le repere du corps puis convertie par articulation ; marche
     en R6 et R15, Motor6D ou AnimationConstraint (teste en R15). Les bras peuvent **viser un point**
     (mains sur le manche de la pelle, bras en V, arbre brandi) : direction depuis l'epaule, position
     de repos des epaules calculee par la chaine des articulations, buste penche / tourne compris ;
     les poses de pelle sont corrigees pour la vraie hauteur du personnage (`gripDrop`) ;
   - camera `Scriptable` (plans `Intro.Shots`, glissement doux ou coupe), bandes noires ;
   - **ecrans de l'intro (2026-11-27, "responsive sur tous les telephones")** : `IntroGui` (bandes
     noires + blanc) est en `ScreenInsets.None` : d'un bord a l'autre de l'ecran, encoche et coins
     arrondis compris. Avant, `IgnoreGuiInset = true` seul le mettait en `DeviceSafeInsets` : sur un
     telephone a encoche, les bandes s'arretaient avant les bords gauche et droit (iPhone 17 Pro
     simule : 750 px sur 874, le jeu visible des deux cotes). Les bulles ("!", "Wow!", "?") sont dans
     un 2e ecran, `IntroBubbles`, reste en `DeviceSafeInsets` : son coin est celui de
     `WorldToViewportPoint` (dans l'ecran None, une bulle tombait ~62 px a cote de la tete) ;
   - **lumiere de cinema** (`Intro.Mood`, 2026-11-27), posee sous le blanc du debut et remise sous
     le blanc de la fin : soleil du matin (`ClockTime` 9.2, latitude 50 : a ~40 degres, cote camera
     et devant lui, donc ombres longues et visages eclaires), `Brightness`, `ColorShift_Top` dore,
     couleur de la brume, rayons du soleil, un `ColorCorrectionEffect` "IntroGrade" (contraste,
     saturation, teinte chaude) et un `DepthOfFieldEffect` "IntroDof" : **fond flou sur les gros
     plans** (champ `blur` de chaque plan, la mise au point suit sa tete), net sur les plans larges.
     Chaque valeur changee est notee puis remise (aussi si la cinematique plante). En **Low
     Quality** (ombres coupees) : ni flou ni rayons. `Atmosphere.Density / Haze / Glare` ne sont
     jamais touches (Low Quality les sauvegarde et les remet lui-meme) ;
   - fumee du volcan : des bouffees "deja vieilles" sont posees le long du panache au debut, sinon
     il mettrait 10 s a se former (`ParticleEmitter:FastForward` est reserve a Roblox).
3. Deroule (`Intro.Times`, secondes, refait le 2026-11-22 : "il le voit de loin et apres il court" ;
   ralenti le meme jour : "les changements de scene sont trop rapides" -> chaque plan de camera dure
   au moins ~1.2 s. Le 2026-11-27 : plan d'ouverture de 3 s, tout le reste decale de 2.2 s. Les
   temps de `Intro.Shots` sont ecrits avec `Intro.Times` : changer un temps deplace aussi la camera) :
   - 0-3 : **ouverture**. Camera au-dessus de la foret : montagnes, volcan de jus qui fume et ses
     5 fruits, le grand arbre dans sa clairiere. Elle descend en douceur (`ease = "slow"`) jusqu'a
     cote de lui ; il marche deja sur le chemin et regarde la foret autour de lui ;
   - 3-4.8 : marche tranquille vue de cote, oiseaux ; il ralentit ;
   - 4.8 : il s'arrete net, gros plan de face, "!", leve la tete d'un coup (double prise), coup de
     zoom ; l'arbre commence a **scintiller** ;
   - 6.0-7.8 : derriere lui, **l'arbre au loin** au bout du chemin, zoom lent, son "chime" ;
   - 7.8 : gros plan de face, petite prise d'elan puis saut, **bras tendus en V au-dessus de la tete**,
     mains qui tremblent, "Wow!", etoiles, coup de zoom ;
   - 9.3-10.9 : **il court** (grandes foulees, buste en avant, bras qui pompent, poussiere a chaque
     pas), travelling de cote ; 10.9 : il freine (poussiere), contre-plongee derriere lui, il leve la tete ;
   - 12.3 : trois-quarts, main sous le menton, "?" ;
   - 13.6 : "!", la tete se tourne vers **la pelle plantee** a cote (elle scintille), il la montre ;
   - 14.8-16.4 : il va a la pelle, tend les mains, l'**arrache du sol** (terre, poussiere, secousse,
     "pop", etincelles), la prend en main ;
   - 16.4-20.6 : il va pres de l'arbre (hors des racines) ; 3 coups, mains sur le manche (droite en
     haut, gauche plus bas) : lever, enfoncer (le pied droit appuie sur la lame, terre + poussiere +
     secousse, le trou grandit), soulever une **motte de terre sur la lame**, buste tourne, la **jeter
     en arc sur le tas** (qui grandit a l'atterrissage) ;
   - 20.6 : il replante la pelle a sa gauche (elle reste dans le plan large) ;
   - 20.7-22.6 : l'arbre tombe (plan large, **le volcan apparait derriere**), **grosse secousse**,
     poussiere, **les fruits sautent et roulent** ; il met les mains pres du visage (surpris) ;
     22.6 : l'arbre disparait en poussiere ;
   - 22.6-23.3 : l'arbre niveau 1 tourne en flottant au-dessus du trou et **brille** (plan de face) ;
   - 23.3 : il saute en arc dans les mains, rebond "gelee" ; 23.6 : il le **brandit au-dessus de sa
     tete** (grosse gerbe d'etincelles, son "level up", petits sauts) ; 24.3 : il le redescend devant lui ;
   - 24.7-26.3 : fondu blanc plus long (1.2 s, puis blanc tenu un instant) ; puis l'usine (le blanc
     s'efface en 1 s), etincelles autour de l'arbre dans les mains.
   - **Marche et course (2026-11-27)** : l'animation suit la DISTANCE parcourue, plus le temps. On
     dit ou est chaque pied (devant la hanche, au-dessus du sol : `walkFoot`, `runFoot`) et un petit
     calcul donne la hanche, le genou et la cheville (`solveLeg`, `placeFeet`). Le pied pose recule
     exactement a la vitesse du corps : il ne glisse plus. Le corps descend quand les jambes sont
     ecartees ; talon qui se leve a la fin de l'appui ; en course, un temps en l'air entre deux
     pas. Un nombre entier de pas par trajet. Les bruits de pas (et la poussiere en courant) partent
     quand un pied se pose (`strikes`), plus sur l'horloge ; ils sont plus doux quand la camera est loin.
     Marche plus lente qu'avant (3.75 studs / s au lieu de 4.6) : les jambes d'un avatar Roblox sont
     courtes (1.6 stud de la hanche a la cheville), un pas de plus de ~1.7 stud ecrase le corps au sol.
   - **Pieds au sol (2026-11-27)** : les avatars R15 de 2026 ont des `AnimationConstraint` ; la
     copie gardait l'animation du vrai personnage sur l'articulation `Root` (bassin abaisse de 0.09
     a 0.17 stud) et les pieds s'enfoncaient dans le sol pendant toute la cinematique. `cleanActor`
     remet aussi les `AnimationConstraint` a zero, et la hauteur de la racine est mesuree sur la pose
     de repos (chaine des articulations), plus sur la boite englobante.
   - Les angles des articulations sont lisses (`PoseSmoothing`, 0.07 s) : pas de saut entre deux
     poses ; presque pas de lissage quand les mains tiennent la pelle ou l'arbre (sinon elles
     quittent le manche). Epaules qui balancent un peu a la marche et a la course.
4. **Arrivee sans a-coup (2026-11-27)** : sous le blanc de la fin, decor detruit, puis
   `warmArrival` : la camera fait un tour du personnage dans l'usine (`ArrivalSweepSteps` angles,
   1 image chacun : chaque cote de l'usine est dessine une fois, maillages, textures, ecrans 3D),
   puis le blanc reste tant que : streaming autour du personnage pas fini (`RequestStreamAroundAsync`),
   prechargement du Preloader pas fini (attribut local `PreloadDone`, voir `chargement.md`), ou
   moins de `ArrivalSmoothFrames` images fluides de suite. Au moins `ArrivalMinHold`, au plus
   `ArrivalMaxWait` (4 s). Avant, l'usine n'etait dessinee que 0.15 s sous le blanc : sa premiere
   image tombait pendant que le blanc s'effacait (a-coup a l'arrivee). Pendant les ~24 s de l'intro,
   la carte se charge deja en arriere-plan (streaming + Preloader etape 4).
5. Fin : camera `Custom` posee DERRIERE le personnage, dans le sens ou il regarde
   (`ExitCameraDistance`, `ExitCameraHeight`) : avant, on rendait la vue d'avant l'intro, mais le
   serveur pose le personnage dans sa base apres le debut de l'intro (camera de cote contre un mur, vu
   par l'utilisateur le 2026-11-22). Le personnage est pose face a l'usine, bien droit depuis la
   porte (voir `carte-bases.md`, Apparition), donc la camera aussi. decor detruit, camera `Custom` remise a la meme place qu'avant l'intro (par rapport
   au personnage), HUD rendu, remote `IntroDone`. Le vrai personnage n'a jamais quitte la base.
6. Ensuite : musique de fond, tutoriel etape par etape (`tutoriel.md`) ; touche E au centre de la
   pelouse ("Plant tree") -> l'arbre pousse
   (`Tree.PlantStamp`), 5 pommes tombent, `HoldingSapling = false` (l'arbre quitte les mains).

## Remotes

| Nom | Sens | Arguments | Verifications serveur |
|---|---|---|---|
| `IntroDone` | client -> serveur | aucun | delai 2 s, sauvegarde chargee ; ecrit `IntroSeen = true`, `IntroPending = false`. Aucun effet sur la partie |


## Donnees sauvegardees

`IntroSeen` (booleen, deja dans le TEMPLATE, false). Sanitize : autre chose qu'un booleen -> true
(jamais rejouee par erreur). Profils existants : `Setup = 4`, donc jamais d'intro (meme si `IntroSeen`
est faux chez eux : vrai pour le profil de test).

## Configuration

`src/shared/Config/Intro.luau` : `SetOrigin`, `ActorStart`, `ActorStop`, `DigSpot`, `HoleOffset`,
`PileOffset`, `TreeSpot`, `ItemSpot`, `TreeLevel`, `TreeFruits`, `SaplingLevel`, `SaplingScale`,
`ShovelScale`, `WalkStride`, `RunStride` (longueur d'un cycle de 2 pas, en studs ; remplacent
`StepsPerSecond` et `RunStepsPerSecond` le 2026-11-27), `NoticeSpot`, `ShovelSpot`, `ShovelReach`,
`ShovelDepth`, `ShovelRestSide`, `HoldOffset`, `HoldArmDegrees`, `Times`, `Digs`, `Shots` (champs
`ease = "slow"` : grand mouvement tres doux ; `blur` : flou du fond, 0 a 1), `Mood` (lumiere de
cinema : `ClockTime`, `GeographicLatitude`, `Brightness`, `ColorShiftTop`, `AtmosphereColor`,
`AtmosphereDecay`, `SunRaysIntensity`, `SunRaysSpread`, `Contrast`, `Saturation`, `Tint`,
`FocusRadius`), fondus,
`AppearanceWaitSeconds`, `PoseSmoothing`, `ExitCameraDistance`, `ExitCameraHeight`,
`ArrivalSweepSteps`, `ArrivalMinHold`, `ArrivalMaxWait`, `ArrivalSmoothFrames`, `ArrivalSmoothFrameSeconds`, volumes
(`SoundVolume` 0.4 pour les bruitages, `BirdsVolume` 0.3 : plus doux que dans le jeu ; `StepVolume`,
`WhooshVolume`, `CrackVolume` multiplient `SoundVolume`), effets (`DigShake`, `PullShake`, `LandShake`, `NoticeFovKick`, `WowFovKick`),
textes (`NoticeText`, `WowText`, `ThinkText`, `IdeaText`), `BarHeight`. Poses de la pelle (CARRY,
RAISE, PLUNGE, PUSHED, PRY, THROW) en haut d'`IntroController`. Ligne et fleche du tutoriel : `Config/Tutorial.luau`.
Sons : `IntroBirds` (oiseaux en boucle), `IntroDig`, `IntroTreeFall` dans `Config/Sounds` (+ `NewFruit`,
`Notify`, `Pickup`, `TreeBoing`, `TreeChime`, `FruitLand` deja la).
Bruitages ajoutes le 2026-11-23 (`Config/Sounds`, evenements `at(...)` dans `IntroController`) :
- `IntroGrass1..4` : un pas dans l'herbe a chaque pas (une des 4 variantes au hasard, jamais 2 fois
  de suite la meme ; pas "craquants" facon jeu de blocs, pas les vrais sons de Minecraft) (marche du debut, vers la pelle, vers
  l'arbre), plus forts et plus aigus en courant ;
- `IntroJump` + `IntroWhoosh` au saut du "Wow!", `IntroLand` a l'atterrissage et aux 2 petits sauts de joie ;
- `IntroWhoosh` : depart de la course, pelle arrachee, chaque motte jetee, arbre niveau 1 qui vole dans les mains ;
- `IntroSkid` (feuillage) au freinage ; `IntroTreeCrack` juste avant la chute de l'arbre ;
  `IntroLeaves` a l'impact ; 5 `FruitLand` decales (fruits qui retombent) ;
- `IntroRise` (whoosh montant) pendant le fondu au blanc final.
- 10 petits pas en plus (2026-11-23, liste dans `IntroController`) : il s'arrete net et se tourne,
  se tourne apres le freinage, recule en arrachant la pelle, recule quand l'arbre bascule, s'avance
  vers l'arbre niveau 1.
Reactions du personnage (voix, 2026-11-23, fonction `voice` dans `IntroController`, volume
`Intro.VoiceVolume`, efforts `Intro.GruntVolume`) :
- `IntroGasp` (il voit l'arbre), `IntroWowVoice` (Wow!), `IntroPant` (essouffle a l'arrivee),
  `IntroHmm` (il reflechit, coupe en douceur apres `Intro.HmmSeconds`), `IntroGrunt2` (pelle
  arrachee), `IntroGrunt1/3/2` (un effort par coup de pelle), `IntroWhoa` (l'arbre bascule),
  ("got it" et "woo hoo" de la fin retires le 2026-11-23 : trop de sons a la fin).
Marche refaite le 2026-11-23 : genoux et coudes (R15 seulement, champs `rk lk re le` de la pose),
la jambe qui avance plie le genou, bras legerement ecartes et coudes plies, petit rebond, tete stable ;
course genoux tres plies et bras a angle droit. Coudes remis droits quand les mains tiennent la pelle
ou l'arbre (le calcul des mains suppose un bras tendu).
Pelle arrachee : "pop" (`CashPop`, `Intro.ShovelPopVolume`) + la pelle grossit puis revient (`Intro.ShovelPop`).
Fin : pendant le fondu au blanc, la camera s'approche peu a peu de sa tete, un peu d'en haut pour
passer au-dessus du pot (`Intro.HeadZoom` : start, distance, fov, rise).
- Voix de createurs differents : pas la meme voix d'un son a l'autre. A ecouter ; changer un id
  dans `Config/Sounds` suffit.
Changer le decor (positions de l'arbre, du chemin, fruits) : modifier `Config/Intro`, relancer
`02m-intro-set.luau` dans Studio, sauvegarder la place. Pelle, trou, tas, depart de la marche et
points de l'histoire sont places par le client depuis la Config : pas besoin de reconstruire le decor.

## Tests (Studio)

Revoir la cinematique : panneau admin > Player > **Replay Intro** (ou, cote serveur,
`joueur:SetAttribute("IntroPending", true)`).

- Profil neuf : voir `usine-a-construire.md` (`Data Backup / ResetOnLeave / RestoreBackup`).
- Rejouer sans toucher a la sauvegarde (barre de commande serveur pendant un playtest) :
  `game.Players.<Nom>:SetAttribute("IntroPending", true)`.
- Figer la cinematique a une seconde (Studio seulement, pour des captures) : attribut joueur
  `IntroFreezeAt` = nombre (ex. 12.3). Avancer seulement : les evenements deja passes ne se rejouent
  pas (mettre 24 pour finir, puis rejouer avec `IntroPending`). Retirer l'attribut ensuite.
- **Version ~27 s (2026-11-27, Play Studio PC, 1 joueur, R15, Rojo synchronise)** :
  - rejouee en entier en temps reel : 28.2 s du declenchement a la fin (blanc d'arrivee compris),
    60 images / s, 0 image de plus de 50 ms pendant la cinematique (pire : 20 ms), copie du decor
    au debut : 87 ms sous le blanc ; aucune erreur de script dans la sortie ;
  - a la fin : `ClockTime` 12, latitude 23.5, `Brightness` 2.4, `ColorShift_Top` noir, couleurs
    de la brume et rayons du soleil revenus a leurs valeurs ; `IntroDof`, `IntroGrade`, `IntroSet`
    et `IntroGui` supprimes ; camera `Custom` sur le Humanoid ;
  - pieds (temps fige a `IntroFreezeAt`, mesure sur la cheville) : debout, semelles a 0.00 du sol
    (avant : -0.13 a -0.17) ; marche de 1.0 a 4.4 s, 42 mesures : le pied pose bouge de 0.002 stud
    en moyenne entre deux mesures (0.044 au pire), contre ~1 stud / s avant ; vitesse 3.9 studs / s ;
  - captures figees dans `docs/references/cinematique/` : ouverture (volcan, 5 fruits, fumee deja
    la), marche de cote, gros plan "Wow" avec le fond flou, chute de l'arbre avec le volcan derriere.
  - Pas mesure : la course (le pied touche le sol trop peu de temps pour la methode : 2 mesures).
  - Attention pendant un test MCP : un appel `execute_luau` qui dure pendant la fin de la
    cinematique remet le type de camera du debut de l'appel (`Scriptable`) : remettre `Custom` a la
    main. Ce n'est pas le jeu.
- **Bandes noires sur telephone (2026-11-27, 23 h, simulateur de Studio, Play, R15)** :
  - A/B en mode Edit, meme bande de 10 % : ancien reglage = 750 px sur 874 (iPhone 17 Pro) et 685
    sur 779 (Galaxy S25 Ultra), le jeu visible a gauche et a droite ; nouveau = toute la largeur.
    Capture : `docs/references/cinematique/2026-11-27-bandes-avant-apres.jpg` (rouge = ancien,
    vert = nouveau ; le point rouge, ecran DeviceSafeInsets, est pile sur la boule jaune, le vert
    a cote : d'ou l'ecran a part pour les bulles) ;
  - Play, iPhone 17 Pro, fige a 8 s : `IntroGui` et les 2 bandes de x = -62 a 812 (tout l'ecran),
    "Wow!" pile au-dessus de la tete. Capture : `2026-11-27-bandes-iphone-wow.jpg` ;
  - fin : `IntroGui`, `IntroBubbles`, `IntroSet` supprimes, camera `Custom`, 0 erreur de script.
  - Pas teste sur un vrai telephone (le simulateur ne fait pas la vraie encoche) ni en portrait.
  - Vu au passage : le joystick et le bouton de saut restaient affiches par-dessus la
    cinematique. Corrige le meme soir (voir "Joystick cache") ;
- **Joystick cache (2026-11-27, 23 h 15, simulateur iPhone 17 Pro, Play)** : avant l'intro
  `TouchControlsEnabled` vrai, `TouchGui` actif ; pendant (fige a 8 s) faux et `TouchGui` coupe,
  plus de joystick ni de saut a l'ecran (`2026-11-27-sans-joystick-pendant.jpg`) ; apres la fin,
  tout revenu (`JumpButton` visible, personnage libre, `2026-11-27-joystick-apres.jpg`) ; 0 erreur.
  Pas teste sur un vrai telephone ni avec une manette.
- **Charge pour un telephone (2026-11-27, 21 h, Play Studio PC, qualite 21 puis 3)** : rejouee en
  entier, 28.1 s, 0 erreur. 12 000 a 91 000 triangles et 19 a 115 appels de dessin selon la phase
  (repere Roblox : 800 000 / 600), memes chiffres en qualite 3 (montagnes toujours la, ombres a 0).
  A-coups de ~50 ms (copie du decor) et ~80 ms (arrivee), sous le blanc. Tableau par phase :
  `docs/perf-mobile.md`. Pas un test sur vrai telephone.
- Version ~20 s (2026-11-22, 2e refonte) : captures figees de chaque moment (marche, "!", arbre au
  loin, Wow bras en V, course, pelle arrachee, lame dans le trou, motte sur la lame, jet sur le tas,
  pelle replantee + chute, arbre brandi) ; passage complet en temps reel 19.9 s, camera `Custom` et
  HUD rendus, pas d'erreur de script. Profil existant (Setup 4) : `IntroDone` sans effet.
- Version ~18 s (2026-11-22, 21 h) : rejouee 3 fois en video MCP (PC), images verifiees : scintillement,
  etoiles du Wow, pose "?" visage visible, pelle visible de cote, chute + fruits + poussiere dans le plan
  large, ramassage avec etincelles ; pas d'erreur de script. Secousses et coup de zoom : effet en
  mouvement, pas juge sur image fixe.
- Verifie le 2026-11-22 (PC, 1 joueur, R15, avatar par defaut, version 14 s) : intro complete au premier lancement
  d'un profil neuf (version 14 s : 14.3 s), pas rejouee au retour, profil existant sans intro, Skip (bouton) ~3 s
  apres le debut, camera `Custom` a 13 studs ensuite, arbre en main, ligne + fleche, touche E ->
  `Setup = 1`, arbre plante, pommes, pad suivant ; pas d'erreur de script. Videos et captures MCP.

## Problemes connus / a faire

- **27 s sans Skip** pour un joueur qui vient d'arriver : c'est long (choix de l'utilisateur de ne
  pas avoir de Skip). A surveiller dans les stats de premiere session.
- Version du 2026-11-27 pas vue sur un vrai telephone (charge mesuree et legere, voir Tests) : le
  decor a double (2 621 pieces, copie de 87 ms sur PC, plus sur un telephone, sous le blanc) ; a faible qualite graphique Roblox coupe de lui-meme le
  flou, les ombres et ce qui est loin (les montagnes a 600-880 studs peuvent disparaitre).
- Marche et course en R6 : la jambe pointe vers le pied (pas de genou ni de cheville), pas teste.
  Avatars tres grands ou tres petits : reglages mis a l'echelle de la jambe, pas testes.
- Trajets courts (vers la pelle, vers l'arbre) : 2 pas chacun, juges seulement sur le calcul.
- `IntroSet` (2 621 pieces) reste dans `ReplicatedStorage` de tous les joueurs, meme ceux qui ne
  verront jamais la cinematique. Piste si la memoire compte sur telephone : le supprimer cote
  client quand `IntroPending` est faux.
- Arrivee (2026-11-27, Play Studio PC, intro rejouee) : blanc tenu 0.62 s, pire image pendant le
  blanc 76 ms (a-coup qui etait visible avant, maintenant cache). En Studio, rejouee = usine deja
  dessinee une fois : le vrai premier lancement (cache vide, telephone, connexion lente) n'est pas
  mesure. En Studio seulement, une ligne `[IntroController] arrivee : ...` donne le temps tenu.

- Fluidite mesuree le 2026-11-22 (Studio PC, profil neuf) : 18.5 s a ~236 images/s, 2 a-coups
  seulement au tout debut (50 et 97 ms : copie du decor et du personnage, caches par l'ecran blanc).
- Studio : apres beaucoup de captures video MCP, le rendu 3D de Studio est devenu noir (meme en
  edition) ; il a fallu fermer et rouvrir Studio. Ce n'est pas le jeu.

- Animations en code (pas d'assets d'animation, `generate_animation` du MCP pas utilise : il ne
  fait que du R15 et le jeu peut passer en R6). Rendu simple mais lisible.
- BillboardGui proches de la camera invisibles en playtest Studio (meme l'etiquette du nom) : les
  bulles sont dessinees dans le ScreenGui de l'intro. Cause pas trouvee.
- Roblox 2026 : `PlayerModule` est dans StarterPlayer ; le requerir depuis un controleur cree une
  2e camera bloquee en `Scriptable` (vu en test). Ne pas le requerir.
- Pas teste : telephone, manette, 2 joueurs (arbre en main vu par l'autre, ligne seulement chez
  soi), avatar avec vetements / R6 / tres grand ou petit (bras qui visent : calcul general, vu
  seulement en R15 par defaut).
- Plans cadres dans le viewport tres large de Studio (2.4:1) ; sur un ecran 16:9 on voit un peu
  plus en haut et en bas.
- Bras sans coude (blocs) : les mains "visent" le manche mais un bras trop court ou trop long ne
  touche pas exactement la poignee.
