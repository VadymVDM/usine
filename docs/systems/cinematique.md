# Systeme : Cinematique d'ouverture (profil neuf)

**Statut :** fonctionne (playtest Studio PC a 1 joueur le 2026-11-22, version ~20 s sans Skip ; version ralentie ~24 s pas encore rejouee ; telephone, manette et 2 joueurs pas testes)
**Derniere mise a jour :** 2026-11-22

## Role

Un profil NEUF (`IntroSeen == false` et `Setup == 0`) voit UNE fois une petite histoire de ~24 s :
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
| `tools/build-map/02m-intro-set.luau` | Studio | Construit `ReplicatedStorage.IntroSet` (dans le .rbxl, hors Rojo, place v236) |

## Fonctionnement

1. Serveur, au chargement de la sauvegarde : `IntroPending = not IntroSeen and Setup == 0`,
   `HoldingSapling = Setup == 0`. Sans sauvegarde chargee : pas d'attribut, pas d'intro.
2. Client (`IntroPending` vrai, personnage present, avatar charge ou 1.5 s max) :
   - ecran blanc tout de suite, HUD et ScreenGuis caches (ceux que le Preloader rallume pendant
     l'intro sont recaches puis rendus a la fin ; `TouchGui` jamais touche), touches E coupees
     (`ProximityPromptService.Enabled`), racine du vrai personnage ancree en local (il ne bouge pas) ;
   - decor `IntroSet` clone a `Intro.SetOrigin` (y = 1200, loin de la carte), chez ce joueur seulement ;
   - acteur = copie locale du personnage (`Archivable`), sans scripts, Animator, tags ni attributs,
     racine ancree. **Animations faites en code** : angles des articulations ecrits a chaque image
     (`Transform`), rotation donnee dans le repere du corps puis convertie par articulation ; marche
     en R6 et R15, Motor6D ou AnimationConstraint (teste en R15). Les bras peuvent **viser un point**
     (mains sur le manche de la pelle, bras en V, arbre brandi) : direction depuis l'epaule, position
     de repos des epaules calculee par la chaine des articulations, buste penche / tourne compris ;
     les poses de pelle sont corrigees pour la vraie hauteur du personnage (`gripDrop`) ;
   - camera `Scriptable` (plans `Intro.Shots`, glissement doux ou coupe), bandes noires.
3. Deroule (`Intro.Times`, secondes, refait le 2026-11-22 : "il le voit de loin et apres il court" ;
   ralenti le meme jour : "les changements de scene sont trop rapides" -> chaque plan de camera dure
   au moins ~1.2 s, avant certains duraient 0.3 s ou 0.6 s. Les temps de `Intro.Shots` sont ecrits avec
   `Intro.Times` : changer un temps deplace aussi la camera) :
   - 0-2.6 : marche tranquille sur le chemin (de cote), oiseaux ; il ralentit ;
   - 2.6 : il s'arrete net, gros plan de face, "!", leve la tete d'un coup (double prise), coup de
     zoom ; l'arbre commence a **scintiller** ;
   - 3.8-5.6 : derriere lui, **l'arbre au loin** au bout du chemin, zoom lent, son "chime" ;
   - 5.6 : gros plan de face, petite prise d'elan puis saut, **bras tendus en V au-dessus de la tete**,
     mains qui tremblent, "Wow!", etoiles, coup de zoom ;
   - 7.1-8.7 : **il court** (grands pas, buste en avant, bras qui pompent, poussiere a chaque pas),
     travelling de cote ; 8.7 : il freine (poussiere), contre-plongee derriere lui, il leve la tete ;
   - 10.1 : trois-quarts, main sous le menton, "?" ;
   - 11.4 : "!", la tete se tourne vers **la pelle plantee** a cote (elle scintille), il la montre ;
   - 12.6-14.2 : il va a la pelle, tend les mains, l'**arrache du sol** (terre, poussiere, secousse,
     "pop", etincelles), la prend en main ;
   - 14.2-18.4 : il va pres de l'arbre (hors des racines) ; 3 coups, mains sur le manche (droite en
     haut, gauche plus bas) : lever, enfoncer (le pied droit appuie sur la lame, terre + poussiere +
     secousse, le trou grandit), soulever une **motte de terre sur la lame**, buste tourne, la **jeter
     en arc sur le tas** (qui grandit a l'atterrissage) ;
   - 18.4 : il replante la pelle a sa gauche (elle reste dans le plan large) ;
   - 18.5-20.4 : l'arbre tombe (plan large), **grosse secousse**, poussiere, **les fruits sautent et
     roulent** ; il met les mains pres du visage (surpris) ; 20.4 : l'arbre disparait en poussiere ;
   - 20.4-21.1 : l'arbre niveau 1 tourne en flottant au-dessus du trou et **brille** (plan de face) ;
   - 21.1 : il saute en arc dans les mains, rebond "gelee" ; 21.4 : il le **brandit au-dessus de sa
     tete** (grosse gerbe d'etincelles, son "level up", petits sauts) ; 22.1 : il le redescend devant lui ;
   - 22.5-24.1 : fondu blanc plus long (1.2 s, puis blanc tenu un instant) ; puis l'usine (le blanc
     s'efface en 1 s), etincelles autour de l'arbre dans les mains.
   - Les angles des articulations sont lisses (`PoseSmoothing`, 0.07 s) : pas de saut entre deux
     poses ; presque pas de lissage quand les mains tiennent la pelle ou l'arbre (sinon elles
     quittent le manche). Epaules qui balancent un peu a la marche et a la course.
4. Fin : camera `Custom` posee DERRIERE le personnage, dans le sens ou il regarde
   (`ExitCameraDistance`, `ExitCameraHeight`) : avant, on rendait la vue d'avant l'intro, mais le
   serveur pose le personnage dans sa base apres le debut de l'intro (camera de cote contre un mur, vu
   par l'utilisateur le 2026-11-22). Le personnage est pose face a l'usine, bien droit depuis la
   porte (voir `carte-bases.md`, Apparition), donc la camera aussi. decor detruit, camera `Custom` remise a la meme place qu'avant l'intro (par rapport
   au personnage), HUD rendu, remote `IntroDone`. Le vrai personnage n'a jamais quitte la base.
5. Ensuite : musique de fond, tutoriel etape par etape (`tutoriel.md`) ; touche E au centre de la
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
`ShovelScale`, `StepsPerSecond`, `RunStepsPerSecond`, `NoticeSpot`, `ShovelSpot`, `ShovelReach`,
`ShovelDepth`, `ShovelRestSide`, `HoldOffset`, `HoldArmDegrees`, `Times`, `Digs`, `Shots`, fondus,
`AppearanceWaitSeconds`, `PoseSmoothing`, `ExitCameraDistance`, `ExitCameraHeight`, volumes
(`SoundVolume` 0.4 pour les bruitages, `BirdsVolume` 0.3 : plus doux que dans le jeu ; `StepVolume`,
`WhooshVolume`, `CrackVolume` multiplient `SoundVolume`), effets (`DigShake`, `PullShake`, `LandShake`, `NoticeFovKick`, `WowFovKick`),
textes (`NoticeText`, `WowText`, `ThinkText`, `IdeaText`), `BarHeight`. Poses de la pelle (CARRY,
RAISE, PLUNGE, PUSHED, PRY, THROW) en haut d'`IntroController`. Ligne et fleche du tutoriel : `Config/Tutorial.luau`.
Sons : `IntroBirds` (oiseaux en boucle), `IntroDig`, `IntroTreeFall` dans `Config/Sounds` (+ `NewFruit`,
`Notify`, `Pickup`, `TreeBoing`, `TreeChime`, `FruitLand` deja la).
Bruitages ajoutes le 2026-11-23 (`Config/Sounds`, evenements `at(...)` dans `IntroController`) :
- `IntroStepL` / `IntroStepR` : un pas dans l'herbe a chaque pas (marche du debut, vers la pelle, vers
  l'arbre), plus forts et plus aigus en courant ;
- `IntroJump` + `IntroWhoosh` au saut du "Wow!", `IntroLand` a l'atterrissage et aux 2 petits sauts de joie ;
- `IntroWhoosh` : depart de la course, pelle arrachee, chaque motte jetee, arbre niveau 1 qui vole dans les mains ;
- `IntroSkid` (feuillage) au freinage ; `IntroTreeCrack` juste avant la chute de l'arbre ;
  `IntroLeaves` a l'impact ; 5 `FruitLand` decales (fruits qui retombent) ;
- `IntroRise` (whoosh montant) pendant le fondu au blanc final.
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
