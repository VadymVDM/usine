# Systeme : Tutoriel etape par etape (profil neuf)

**Statut :** fonctionne (parcours complet en playtest Studio PC le 2026-11-22, joueur deplace par script ; telephone et 2 joueurs pas testes)
**Derniere mise a jour :** 2026-11-23 (tuto fini a l'etage 2, puis un seul conseil : l'ascenseur)

## Role

Apres la cinematique (`cinematique.md`), le joueur fait UNE chose a la fois, dans l'ordre demande par
l'utilisateur, avec un texte court tout en haut de l'ecran (a la hauteur de la barre "< Floors >") et,
selon la cible, une ligne + fleche 3D dans le monde ou une fleche a l'ecran sur un bouton.
La ligne (Beam `TutorialLine`) porte l'attribut `KeepInLowQuality` : le mode Low Quality ne l'eteint
pas (2026-11-27).
Fleche 3D (`Util/TutorialArrow`, refaite le 2026-11-27, style simulateur Roblox) : une fleche plate
epaisse, contour noir, tranches orange, face jaune en biseau, bout du manche arrondi, reflet blanc.
Toujours face a la camera (a l'horizontale), penchee de 15 deg vers le ciel autour de la pointe
(sinon la face verticale reste a l'ombre sous le soleil de midi et le jaune vire au kaki), leger
balancement, rebond avec ecrasement a l'impact et etirement en vitesse.
Le bouton vise grossit et retrecit doucement en boucle (+8 %, `Tutorial.ButtonPulse` /
`ButtonPulseSpeed`, 2026-11-23). La pulsation multiplie l'UIScale du bouton par-dessus le survol
(UI/ButtonFx) et le rebond de l'Index (DiscoveryController) ; attribut `PulseFactor` sur l'UIScale
pour qu'eux lisent leur taille de repos sans la pulsation. Taille d'origine remise quand la cible change.

1. **Factory** : Plant the tree -> Pick up the fruits -> Build the shelf -> Drop the fruits -> Build
   the blender -> Blend the fruits (E sur le mixeur) -> Take the juices -> Open the shop -> Sell the
   juices -> Collect your cash (premier argent).
2. **Picker** : Hire the Fruit Picker (pad vert). S'il n'a pas le prix, il refait des jus avec une
   petite ligne jaune sous l'objectif "Fruit Picker: $20 / $25".
3. **OpenIndex** : fleche sur le bouton Index du HUD ("Open the Index").
4. **ClaimIndex** : fleche sur un bouton CLAIM de l'Index ("Claim a fruit reward") ; rien a prendre : on passe.
5. **Loop** : d'abord "Upgrade the tree" (pad Upgrade Tree, 15 $) si l'arbre est encore niveau 1 ;
   sans le prix, il refait des jus avec la petite ligne "Tree upgrade: $5 / $15". Puis un tour complet
   (fruits -> etagere -> mixeur -> jus -> comptoir -> argent encaisse). Pas d'etape sauvegardee en plus
   (fait = `Lv_Tree` > 1) : les numeros d'etape des profils ne bougent pas.
6. **Upgrade** : fleche sur UPGRADE ("Open Upgrades") puis sur la vitesse ("Upgrade your speed:
   FREE!") : le premier achat de vitesse est gratuit, une fois (serveur).
7. **Free** : 15 s de jeu libre, sans guidage.
8. **Operator** : quand il a l'argent de l'Operator du mixeur 1 : "Hire a Blender Operator" (pad) ;
   deja embauche : on passe.
9. **Suggest** (sans fin) : chaque minute, s'il peut payer une amelioration de panneau (Conveyor, Juice
   Table, Customers, Fruit Picker, mixeurs), une au hasard : "Upgrade <nom>" (ligne vers la tuile),
   jusqu'a l'achat ou 30 s. S'il n'a plus assez d'argent (autre chose achete entre-temps) : plus de
   ligne ni de fleche ; la meme proposition revient des qu'il peut la payer (30 s remises a plein).
   Picker et Operator : fleche sur le pad seulement quand le joueur a le prix.

**Etage 2 possede : fin du tutoriel (2026-11-23).** Des que la base possede l'etage
`Tutorial.StopAtFloor` (2), plus aucune etape (client) et le serveur met `TutorialStep` = Done
(`TutorialService.OnFloorsOwned`, appele par `FloorService.refreshAnnex`), meme si le joueur etait au
milieu du tuto. Reste fini apres un rebirth.

**Conseil unique : l'ascenseur.** `ElevatorHintDelaySeconds` (60 s) apres avoir vu l'etage 2 possede
(compte depuis l'arrivee en jeu pour une reconnexion), des qu'il a le prix d'Elevator Speed : ligne +
fleche sur sa tuile du panneau Elevator de la terrasse (`Annex.Terrace.ElevatorBoard`), texte
"Upgrade the Elevator". Fini des qu'une amelioration de l'ascenseur (Speed ou Cabin, attributs de base
`ElevatorSpeed` / `ElevatorCabin`) est > 0 : plus rien ensuite. Jamais apres un rebirth (attribut
joueur `Rebirths` > 0). Pas sauvegarde a part : l'achat lui-meme sert de "fait".

**Argent sur un tas (tuto fini ou pas, jusqu'a l'etage 2) :** des qu'un etage de SA base a de l'argent sur
son tas (attribut d'etage `PileCash`, CustomerService), ligne + fleche + anneau vers le pad Collect
Cash le plus proche, jusqu'a ce que tout soit encaisse. Passe avant les cibles du monde du tuto (pas
avant une fleche dans un menu). Texte "Collect your cash" en haut seulement pendant le tuto.
Plus montre du tout des que la base possede l'etage 2 (attribut de base `FloorsOwned` >=
`Tutorial.CashArrowUntilFloor`, FloorService) ; revient apres un rebirth (retour a 1 etage).

Un autre menu ouvert cache le bouton a viser (le HUD se cache menu ouvert) : fleche sur son X ("Close
this menu"). Cible dans le monde avec un menu ouvert : fleche aussi sur le X.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/client/Controllers/TutorialController.luau` | client | Calcule la cible 5 fois / s d'apres l'etape sauvegardee et l'etat du jeu, dessine ligne, fleche 3D, fleche a l'ecran, objectif (`TutorialGui`), demande l'etape suivante |
| `src/shared/Util/TutorialArrow.luau` | partage | Fleche 3D : `Build(size)` (contour sombre en pieces, corps orange, face jaune en biseau, bout arrondi, reflet, Highlight a travers les murs) et `Pose(model, cframe, scale)` (ecrasement / etirement depuis la pointe). Aussi utilisee par `tools/build-map/preview-factory.luau` |
| `src/server/Services/TutorialService.luau` | serveur | Seul a ecrire `Data.TutorialStep` ; attribut joueur `TutorialStep` ; remote `TutorialProgress` |
| `src/server/Services/PlayerUpgradeService.luau` | serveur | Vitesse gratuite une fois (`Data.FreeSpeedUsed`, attribut `FreeSpeed`) |
| `src/client/Controllers/UpgradeMenuController.luau` | client | "FREE" sur la ligne vitesse ; `GetBuyButton(id)` pour la fleche |
| `src/shared/Config/Tutorial.luau` | partage | Textes, `Phases`, `Done`, `FreePlaySeconds` (15), `SuggestEverySeconds` (60), `SuggestTimeoutSeconds` (30), `SuggestIds`, `PickFruits`, cibles, ligne, fleches, `BannerTop` |
| `src/server/Services/FloorService.luau` | serveur | Appelle `TutorialService.OnFloorsOwned` ; attributs de base `FloorsOwned`, `ElevatorSpeed`, `ElevatorCabin` |
| `src/server/Services/SetupService.luau` | serveur | Conditions d'apparition des pads FREE (`Config/Setup.PadGates`) |
| `src/shared/Config/Setup.luau` | partage | `PadGates` |
| `assets/textures/guide_triangle.png` | - | Texture de la ligne : triangle (fond rendu transparent), pointe vers le haut, 256 x 320 (`rbxassetid://77298151299812`). Source : `assets/icons/guide_triangle_source.webp`. Anciennes : `guide_skip.png`, `guide_chevron.png` |

## Fonctionnement

- Le client ne decide rien : il lit ce que le serveur publie deja : `Lv_Setup` (etage 1), `InvFruits`
  (format `Apple=5;Strawberry=1`), `InvMax`, `HandJuices`, `CounterJuices`, attributs du mixeur 1
  (`BowlCount`, `Blending`, `HeldJuices`), gobelets sur la table (`Dynamic.Production`), fruits au sol
  (`Dynamic.GroundFruits`), argent (`leaderstats.Cash`).
- Etape et cible :
  - etape 0 : touche E au centre de la pelouse (`Tree.TreeRoot`, pas de pad) ;
  - etape 1 : fruit au sol le plus proche tant qu'on en porte moins que `Tutorial.PickFruits` (5, ou
    le plateau plein), puis pad Build shelf ;
  - etape 2 : pad Drop Fruits si on porte des fruits, sinon pad Build blender ;
  - etape 3 : jus en main -> pad Open shop ; sinon etape "jus" ;
  - usine finie : jus en main -> pad Drop Juices ; jus deja poses -> pad Collect Cash ; sinon "jus" ;
    fini au premier argent encaisse (plus rien de la session) ;
  - etape "jus" : bol du mixeur 1 avec des fruits -> panneau du mixeur (E) ; mixage en cours ou jus
    sur la table -> pad Take Juices ; fruits portes -> pad Drop Fruits ; sinon fruits au sol.
- Actif seulement si l'etage 1 de SA base n'etait pas fini pendant cette session ; rien pour les
  profils existants. Cache pendant la cinematique (attribut local `IntroPlaying`).
- Pads FREE (serveur, `Setup.PadGates`, une fois apparu le pad reste) : Build shelf apres avoir
  ramasse 5 fruits (ou plateau plein) ; Build blender apres avoir pose les fruits ; Open shop avec
  des jus en main. Reverifie quand `InvFruits` / `HandJuices` changent.

## Remotes

| Nom | Sens | Arguments | Verifications serveur |
|---|---|---|---|
| `TutorialProgress` | client -> serveur | numero de l'etape suivante | entier, exactement l'etape actuelle + 1, <= Done, sauvegarde chargee, delai 0.3 s. Guidage seulement : aucun effet sur l'argent ni la partie |

`BuyPlayerUpgrade` (existant) : la vitesse gratuite est decidee par le serveur (`FreeSpeedUsed` faux), jamais par le client.

## Donnees sauvegardees

`TutorialStep` (entier, 0 = debut, `Tutorial.Done` = 10 = fini) et `FreeSpeedUsed` (booleen).
SchemaVersion 7 : migration 6 -> 7 = usine deja construite (`Setup` = 4) -> `TutorialStep` = Done et
`FreeSpeedUsed` = vrai (profils existants : rien ne change). Sanitize : etape abimee -> Done, booleen
abime -> vrai. Reprise apres deconnexion : a l'etape sauvegardee (ce qui a ete vu pendant l'etape,
ex. "jus deja poses", repart de zero).

## Configuration

`Config/Tutorial.luau` : `Steps` (textes anglais, 5 mots max), `StopAtFloor`, `ElevatorHintDelaySeconds`, `ElevatorHintId`, `PickFruits`, `TransitGraceSeconds`, `Targets`, `Guide*`,
`ArrowHeight*`, `ArrowBounce`, `ArrowBounceSpeed`, `ArrowSquash`, `ArrowStretch`, `ArrowTilt` (15 deg), `ArrowSway`,
`ArrowSwaySpeed`, `ArrowSize`, `RefreshSeconds`. `Config/Setup.luau` : `PadGates`.

## Problemes connus / a faire

- Corrige le 2026-11-23 : entre le depot des fruits et leur arrivee au bol (tapis), l'objectif passait
  ~1 s a "Pick up the fruits". Maintenant "Blend the fruits" reste affiche pendant
  `TransitGraceSeconds` apres le depot et apres chaque fruit envoye (attribut `Pulse` du mixeur 1,
  + `ConveyorTravel`).

- Parcours teste en deplacant le personnage par script (teleportation sur chaque cible, E du mixeur
  declenche par script, clics de souris envoyes sur les boutons) : a refaire a la main, sur telephone
  et a 2 joueurs.
- Conseil ascenseur sans limite de temps : reste tant qu'il n'achete pas (a revoir si ca gene).
- Etape Suggest sans fin (voulu : "toutes les minutes") ; a revoir si ca gene plus tard dans la partie.
- Tests Studio : `game.ServerStorage.Debug.Call:Invoke("Tutorial", "Get" | "Set", "<Nom>", n)`.
- L'objectif est un texte en haut de l'ecran (ScreenGui `TutorialGui`, zone sure) : verifier qu'il ne
  gene pas le HUD sur petit ecran.
- Depuis le 2026-11-27, un nouvel objectif tombe de 18 px a sa place en fondu (`UI/TextPop.In`) au
  lieu de grossir (UIScale 0.6 -> 1) : sur telephone, le texte qui grossit faisait clignoter ses
  lettres (voir `interface.md`, "Textes animes").
