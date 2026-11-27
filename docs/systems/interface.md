# Systeme : Interface (HUD et menus)

**Statut :** en cours
**Derniere mise a jour :** 2026-11-20 (infobulle au survol des fruits et jus)

## Role

Toute l'interface 2D du jeu : HUD (boutons Shop/Index, argent, offres a droite) et les menus
(fenetres Shop, Index, Rebirth, Settings...). Reprise du pack UI de l'utilisateur ("ultrauipack.rbxl").
Pour l'instant c'est **visuel seulement** : les menus s'ouvrent et se ferment, mais les contenus
sont encore ceux du pack (textes "[Name]", "Item Name", "$123,456,789"), pas branches au jeu.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/gui/HUD.rbxm` | client (StarterGui.HUD) | HUD : Canvas (Buttons, Money, TopButtons, ProgressBar), Gamepasses, Multipliers |
| `src/gui/ShopGUI.rbxm` | client (StarterGui.ShopGUI) | Tous les menus dans `MenuFrames` |
| `src/client/Controllers/MenuController.luau` | client | Ouvre/ferme les menus, animations, flou, sons, bouton Settings en haut |
| `src/client/Controllers/MusicController.luau` | client | Musique de fond : morceaux de `Config/Music` en alternance (1, 2, 1...), volume = curseur Music (pause a 0) ; ne demarre qu'apres la cinematique d'ouverture |
| `src/shared/Config/Music.luau` | partage | Liste des musiques (id, volume de base) : BGMusic, NYOBORA (2026-11-23) |
| `src/client/Controllers/SettingsController.luau` | client | Menu Settings : curseurs de volume Music et Sounds (0-100 %), interrupteur Low Quality, touches de deplacement (PC) |
| `src/client/Controllers/MovementKeysController.luau` | client | Applique les touches de deplacement choisies (PC) : remplace W A S D Espace seulement si une touche a change |
| `src/server/Services/SettingsService.luau` | serveur | Sauvegarde des reglages (`Data.Settings`), remote `SetSetting` |
| `src/client/Controllers/InventoryController.luau` | client | Effets de ramassage / depot ; cache la barre Roblox (l'inventaire = plateau sur la tete) |
| `src/client/Controllers/TrayController.luau` | client | Plateau sur la tete et fruits empiles, compteur "12/20" / "FULL!" (voir `chaine-production.md`) |
| `src/client/Controllers/ShopController.luau` | client | Construit le contenu du menu Shop |
| `src/client/Controllers/DealController.luau` | client | Fenetre "Deal" (copie de OfflineEarnings) : "Almost there!" (pack qui couvre l'etage) et fin de l'essai 3X CASH ; voir achats-robux.md |
| `src/client/Controllers/UpgradeMenuController.luau` | client | Bouton vert UPGRADE du HUD + menu Upgrade en Robux (voir `ameliorations-joueur.md`) |
| `src/client/Controllers/OffersController.luau` | client | Offre limitee a droite de l ecran (une a la fois, voir plus bas) |
| `src/client/Controllers/WelcomeBackController.luau` | client | Ecran "Welcome Back!" (gains hors ligne reels, calcules par le serveur : voir `gains-hors-ligne.md` ; plus de demo en Studio depuis le 2026-11-20) |
| `src/client/Controllers/NotifyController.luau` | client | Message court du serveur en haut au centre (remote `Notify`), 3.5 s puis fondu ; texte rouge pour les erreurs (`isError`) |
| `src/client/Controllers/BillboardStrokeController.luau` | client | Contours des panneaux 3D de la carte proportionnels au panneau (voir plus bas) |
| `src/client/Controllers/ScrollBarController.luau` | client | Barre de defilement a glisser a droite de chaque liste de ShopGUI (voir plus bas) |
| `src/client/Controllers/HoverInfoController.luau` | client | Infobulle au survol de la souris : fruit (nom, rarete), jus (nom, rarete, prix de vente) (voir plus bas) |
| `src/client/Fx/PurchaseFx.luau` | client | Contour arc-en-ciel + zoom camera pendant la fenetre d'achat Roblox (voir "Envie d'acheter") |
| `src/client/Controllers/PurchaseFxController.luau` | client | Lance `PurchaseFx` sur le Feedback serveur `PurchasePrompt` |
| `src/server/Lib/PurchasePrompt.luau` | serveur | Seul appel serveur a `Prompt...Purchase` ; previent le client (Feedback `PurchasePrompt`) |
| `src/client/UI/ButtonFx.luau` | client | Animation commune de tous les boutons (survol, appui, rebond, sons) |
| `src/client/Controllers/ButtonFxController.luau` | client | Branche ButtonFx sur tous les boutons de PlayerGui, meme crees plus tard |
| `src/client/UI/PackStyle.luau` | client | **Source unique du style** : police, couleurs des boutons et de l'en-tete, texte, boutons, Robux, prix |
| `src/shared/Config/Shop.luau` | partage | Boosts, passes, packs d'argent (prix, ids Roblox) |
| `src/shared/Config/Icons.luau` | partage | Ids des images de l'interface |
| `assets/icons/` | disque | Icones choisies dans ICONSPACK, a mettre en ligne |
| `src/shared/Assets/UISounds.rbxm` | partage | Sons : BGMusic, Click, Hover, MenuOpen, ShopOpen, CloseMenu |
| `src/shared/Vendor/TopbarPlus.rbxm` | partage | Librairie TopbarPlus (bouton Settings dans la barre Roblox du haut) |

Les `.rbxm` sont des fichiers binaires Roblox : on les modifie dans Studio puis on les reexporte
(voir "Modifier l'interface"). Ils ne contiennent **aucun script**.

## Fonctionnement

### Boutons des cotes (Shop/Index et offres)

- Offres a droite : largeur `PackStyle.SIDE_BUTTON_WIDTH` (0.075 de l'ecran, 0.085 sur petit ecran).
- Shop/Index a gauche : meme largeur x `PackStyle.LEFT_BUTTON_SCALE` (0.8, depuis le 2026-11-22) :
  leur icone remplit tout le bouton alors que celle des offres n'en prend que ~74 %, ils paraissaient
  plus gros. Meme marge au bord (`SIDE_MARGIN`). Calcul dans `MenuController` (`applyLayout`).

### Envie d'acheter (2026-11-20)

- **Pads Robux** : plus d'icone d'argent qui flotte et tourne au-dessus (retiree le 2026-11-21,
  demande du joueur ; `RobuxPadFxController` supprime).
- **Fenetre d'achat Roblox ouverte** : contour de l'ecran arc-en-ciel qui tourne et pulse (trait net
  + halo transparent vers l'interieur), etincelles blanches qui scintillent le long du bord, et la
  camera se rapproche du joueur (28 % de la distance, 9 studs max, petit rebond). Fin a la fermeture
  de la fenetre (`Prompt*PurchaseFinished` cote client) ou au bout de 60 s. Le zoom avance la camera
  apres le script de camera Roblox a chaque image (rien ne s'accumule, le FOV des menus n'est pas
  touche) ; aucun zoom si la camera est `Scriptable`.
- Declenchement : fenetres ouvertes par le serveur (pads Auto Collect / Auto Sell / Thief, Upgrade,
  Keep Cash, Lucky Cash) via `Lib/PurchasePrompt` -> Feedback `PurchasePrompt` ; fenetres ouvertes
  par le client (dons, offres) : `PurchaseFx.Show()` juste apres l'appel.
- Tant que les `passId` / `productId` sont a 0, aucune fenetre ne s'ouvre ("coming soon") : l'effet
  d'ecran ne se voit qu'avec de vrais produits (ou les dons s'ils ont leurs ids).

### Offre limitee a droite (2026-11-20, choix utilisateur)

- **Une seule offre a la fois.** Calendrier propre a chaque joueur, compte depuis son arrivee
  (`Config/Shop.LimitedOffers`), compte depuis la fin de l'ecran de chargement (attribut joueur
  `LoadingDone`, 30 s max d'attente) : `FirstDelaySeconds` = **15 s** (2026-11-21 ; avant : 0), le Starter Pack arrive 15 s apres l'arrivee.
  L'offre reste **3 min** (minuteur rouge), disparait, et **30 s** plus tard la suivante.
- **Entree d'une nouvelle offre** (2026-11-20) : elle "pop" en grand (x2.4) au milieu de l'ecran,
  reste **0.7 s** (2026-11-21 ; avant 1.8 s, trop long), puis file a sa place a droite (pop 0.25 s,
  trajet 0.35 s). Si un menu est ouvert a ce moment (ex. Welcome Back),
  l'animation attend sa fermeture.
- 1re offre = **Starter Pack** (19 R$, petit prix pour un premier achat facile), puis le `Pool`
  **melange a chaque session** (2026-11-21) : Money Rush, Lucky Hour, Customer Rush, Mega Cash,
  Triple Boost, Rare Rain. Toutes passent avant qu'une revienne, jamais deux fois la meme de suite.
  On saute une offre trop tot pour elle (`minCycle` : Mega Cash 99 R$ pas avant la 4e offre,
  ~10 min) ou inutile (tous ses boosts tournent deja avec un multiplicateur au moins aussi fort,
  attributs `Boost<Stat>`). (Auto Sell 30 min retire : "c'est nul".)
- **Offre achetee** (2026-11-21) : elle se retire tout de suite (attribut joueur `OfferBought` =
  `"<cle>#<n>"`, pose par `RobuxShopService` a la remise) au lieu de rester jusqu'a la fin du minuteur.
- **Starter Pack unique** (2026-11-21) : une fois achete (attribut `Bought_OfferStarter`, sauvegarde
  `BoughtOffers`), il n'est plus jamais propose ; la 1re offre de la session vient alors du Pool.
- **Pas d'etiquette de reduction ni de prix barre** : a droite seulement le nom, l'icone (+ gros
  "x2"/"x3" jaune si `badge` ; Mega Cash : le vrai montant "+$2.5K" en vert, mis a jour chaque
  seconde, jamais des "$$$") et le temps. Le prix est sur le bouton Buy de la fenetre.
- **Contenu en images, pas en phrases** (lisible par un enfant) : la fenetre montre une tuile par
  recompense (`rewards`) : icone (billets = argent, trefle = chance, chaussure = vitesse des
  clients) + "x2" jaune + "15 MIN" dessous. Un paquet d'argent montre le vrai montant en vert
  ("+$2.5K"), **adapte a l'etage du joueur** : minutes x gains theoriques (attribut joueur
  `IncomePerSecond` pose toutes les 10 s par `CustomerService`), **plafonne** a `floorShare` x prix
  de son prochain etage (`Floors.Prices` ; tour complete : dernier prix x5). Avant le 2026-11-20 :
  le plus grand des deux (Mega Cash ~$44K a l'etage 1). Mega Cash = 0.5 (au plus $750 a l'etage 1
  ... 5.5B a l'etage 10 ; courbe des etages du 2026-11-20), Starter Pack = 0.06 avec un minimum `minAmount` =
  **$1K** (au debut il montrait +$300, trop peu).
  **Jamais "+$0" ni une duree a la place du montant** (2026-11-22 : Mega Cash affichait "+$0" a
  droite et "+1 HOUR" dans la fenetre sans gains recents) : chaque recompense Cash DOIT avoir
  `minAmount` ou `minFloorShare` (RobuxShopService refuse de demarrer sinon ; Mega Cash : minimum
  0.25 x prochain etage, soit $375 a l'etage 1), le serveur ne renvoie jamais moins de $1, et le
  client laisse le texte vide tant que l'attribut `Cash_<cle>` n'est pas arrive.
- L'offre se cache quand un menu est ouvert (le temps continue de tourner). Fin de l'offre pendant
  que sa fenetre est ouverte : la fenetre se ferme.
- 2026-11-20 : remise de ce que donne chaque offre codee cote serveur (voir `achats-robux.md`) ;
  le bouton Buy passe par le remote `ShopBuy`, montants d'argent = attributs `Cash_<cle>` du serveur.
- **Pas encore fait** : produits Robux pas crees (`productId` = 0 : "coming soon").
- Menu Shop (2026-11-23) : plus de titre "POTIONS" (les potions sont tout en haut) ; cartes moins
  hautes et espaces reduits (`ShopController` : ecart entre lignes 8 px, titres 0.06 x largeur) pour
  voir plus de passes sans defiler.

### Retour des boutons (2026-11-20, retour de test : "des fois l'animation, des fois non")

- UNE animation pour TOUS les boutons 2D (`src/client/UI/ButtonFx.luau`) : survol = x1.10 (Back) +
  son Hover ; appui = x0.91 puis rebond + son Click. Ecran tactile sans souris : pas de survol.
- Branchement automatique : `ButtonFxController` branche chaque `GuiButton` de `PlayerGui` (tous
  les ScreenGui, meme crees plus tard) ; `MenuController` branche le HUD et les menus du ShopGUI en
  reprenant l'UIScale du pack. Un bouton n'est jamais branche deux fois.
- **Bouton X des menus** (2026-11-20, retour : "ca diminue sur un cote") : le X est range dans le
  `UIListLayout` de l'en-tete, qui recollait le bouton reduit en haut a gauche. `MenuController`
  (styleExitButton) pose l'attribut `FxTarget` = nom de la plaque rouge centree : `ButtonFx` fait
  grossir / retrecir cet enfant au lieu du bouton (`ButtonFx.Unbind` si le X etait deja branche).
  Le X du menu Rebirth est maintenant anime aussi. Fenetre des dons : X ancre au centre (0.5, 0.5).
- Exclus : attribut `NoButtonFx = true` (sur le bouton ou un parent), `Selectable = false` (fond qui
  ferme une fenetre, barres de defilement), bouton qui a deja un UIScale d'un autre effet (ex. CLAIM
  de l'Index et sa pulsation `PulseScale`), cases Now / After du menu Rebirth (texte + icone depuis
  le 2026-11-20, `RebirthController`, voir `rebirth.md` ; attribut `NoButtonFx`).
- Panneaux 3D (tuiles a cliquer des bases, panneau ELEVATOR compris) : `BoardFxController` (survol
  + appui + rebond du bouton dessine), inchange.

- Un panneau de `ShopGUI.MenuFrames` est un menu s'il a un enfant `Header`.
- Menus disponibles : Shop, Index, Rebirth, Upgrade, DailyRewards, Settings, StockShop,
  TradeRequest, SendTradeRequest, Trade, Teleport, OfflineEarnings, Codes, Playtime, SellItems.
- Un bouton du HUD dans `Canvas.Buttons` ouvre le menu qui porte son nom. Un bouton peut aussi
  avoir un attribut `MenuName` = nom du menu.
- `ExitButton` dans un menu le ferme. Manette : bouton B ferme.
- A l'ouverture : flou de fond, zoom camera, le HUD sort de l'ecran ; inverse a la fermeture.
- Depuis le code client : `MenuController.Open("OfflineEarnings")`, `MenuController.Close()`.
- HUD (2026-11-19) : Shop et Index l'un sous l'autre, icones seules + nom dessous ; argent en bas
  a gauche (+ jaune a gauche, montant vert) ; police ComicNeueAngular Bold, textes d'une seule couleur.
  Bouton vert UPGRADE (2026-11-20) : `UpgradeButton` du pack, rendu visible par
  `UpgradeMenuController` en bas au centre ; ouvre le menu Upgrade (`ameliorations-joueur.md`).
  Caches dans le fichier (pour plus tard) : TopButtons, ProgressBar, Rebirth,
  DailyRewards, Multipliers, Friend Boost.
- Bouton Settings en haut : engrenage officiel Roblox
  (`rbxasset://textures/ui/Settings/MenuBarIcons/GameSettingsTab.png`).

### Infobulle au survol (2026-11-20)

Demande : souris sur un fruit -> son nom et sa rarete ; souris sur une boisson -> son nom, sa rarete
et son prix.

- `HoverInfoController` (client seulement, aucun remote). Bulle sombre a cote de la souris :
  nom en blanc ("Golden Apple", ou "Dragon Fruit Juice" pour un gobelet), rarete dans sa couleur
  (`Fruits.Rarities`), et pour un jus "Sells for $15" en vert argent. Contour de la bulle = couleur
  de la rarete. Petit "pop" (0.8 -> 1) a chaque nouvel objet, et un contour lumineux (Highlight,
  une seule a la fois, rangee dans la ScreenGui `HoverInfo`) sur l'objet survole.
- Prix = celui du comptoir (`CustomerService.sellOne`) : `fruit.value` x multiplicateur du rebirth
  (`leaderstats.Rebirths` -> `Rebirth.Multiplier`). A changer ici aussi si la formule de vente change.
- Detection : les pieces des fruits et gobelets ont `CanQuery = false` (camera), un rayon de souris
  ne les touche pas. Le controleur suit tous les modeles avec l'attribut `FruitId` dans workspace
  (fruits et gobelets : au sol, plateau, caisses, tapis, table, comptoir, mains des clients), projette
  leur centre a l'ecran (30 fois / s) et prend le plus proche de la camera sous la souris (rayon de
  l'objet + 6 px), a 90 studs max, s'il n'est pas cache par une piece solide (rayon camera -> objet).
  Gobelet = modele qui a une piece `Cup`.
- Pas de bulle : souris sur un bouton / une liste / un panneau de menu, menu Roblox ouvert, ou
  appareil sans souris (telephone : rien, pas de survol).

### Charte de l'interface (2026-11-19, "tout doit etre coherent")

Regle : une seule apparence. Toute interface nouvelle prend police, couleurs et boutons dans
`UI/PackStyle.luau`, jamais des valeurs a elle.

- **Police** : ComicNeueAngular Bold partout (menus, HUD, "+$X", "+3 Apple", "NEW!", bulles des
  clients, panneaux 3D). Contour des textes : `PackStyle.TEXT_STROKE` (gris tres fonce), coins ronds.
  Seule exception : le "!" de la pastille rouge (`WorldLabel`, FredokaOne, plus epais = c'est une icone).
- **Boutons** : `PackStyle.button` = degrade bas -> haut + liseret blanc + contour fonce, bords carres.
  Couleurs : `GREEN` action / achat / ON, `RED` annuler / NO / OFF, `PURPLE` Robux en plus (x2),
  `PINK` cadeau. Argent : `MONEY_GREEN` (texte uni, sans degrade) + contour `MONEY_STROKE` (vert fonce, comme le montant du HUD).
- **En-tete des menus** : meme bandeau cyan pour tous (`PackStyle.HEADER`), icone + titre colles a
  gauche, meme hauteur de titre. Applique par `MenuController` (`styleHeader`) a chaque menu du pack
  et aux menus crees par code (`RegisterMenu`), donc par-dessus les couleurs du `.rbxm` (le pack avait
  Shop rose, Settings gris sans icone, Rebirth vert...). Settings recoit l'engrenage blanc ICONSPACK.
  La fleche verte/orange du pack (en-tete d'OfflineEarnings : Welcome Back, pop-ups "Confirm" et
  "Limited Offer!") est remplacee par le cadeau (`Icons.Gift`) dans `MenuController` (2026-11-20).
- **Interrupteurs Settings** : le bouton du pack (relief avec ombre, qui restait verte sous OFF et
  rouge sous ON) est cache ; a la place un `PackStyle.button` vert ON / rouge OFF, comme YES / NO.
  Depuis le 2026-11-23, seul Low Quality garde un interrupteur.
- **Low Quality** : coupe ombres, effets d'eclairage, brume, forets (`Map.Decor.Trees`) et eteint les
  effets (ParticleEmitter, Trail, Beam, Sparkles, Smoke, Fire) du workspace. Exception : un effet
  avec l'attribut `KeepInLowQuality = true` reste allume (2026-11-27 : ligne de chevrons du
  tutoriel `TutorialLine`, qui montre ou aller). Les collines `Map.Decor.Hills` restent visibles
  (2026-11-27 : avant, tout `Map.Decor` disparaissait et on croyait les Hills absentes en Play).
- **Curseurs de volume Settings** (2026-11-23, Music et Sounds) : dans la case du bouton du pack
  (cache) : pourcentage, barre sombre, remplissage vert, bouton rond ; zone de prise large pour le
  doigt, la liste ne defile pas pendant le glissement. Le volume suit en direct (attribut
  `Setting<Cle>` change cote client) ; une demande `SetSetting` au plus toutes les 0.3 s, puis la
  valeur finale au relachement. Le son passe par des SoundGroup locaux (`SoundFx.Group("Effects")`
  / `SoundFx.Group("Music")`, dans SoundService) : tous les sons du jeu y sont ranges (SoundFx,
  MenuController, BlenderFx, MachineFx, oiseaux de l'intro), meme les boucles deja lancees suivent.
- **Touches de deplacement Settings** (2026-11-27, PC seulement) : 6 lignes apres Low Quality,
  copies de la ligne Effects du pack : Forward, Back, Left, Right, Jump (bouton violet = touche
  actuelle) et Reset Keys (bouton rouge RESET, "Back to Z S Q D Space" sur AZERTY). Clic sur une
  touche -> bouton vert "..." -> appui sur la nouvelle touche. Echap, un clic ailleurs ou la
  fermeture du menu annulent. Touche hors de `GameConfig.RebindableKeys` (E des prompts, I / O du
  zoom, Tab, chiffres...) -> "NO" rouge 0.8 s. Touche deja prise par une autre action -> echange.
  Lignes visibles seulement si `UserInputService.PreferredInput` = KeyboardAndMouse (cachees sur
  telephone et manette, mises a jour si le joueur change d'appareil).
  - Sauvegarde : reglages `KeyForward` / `KeyBack` / `KeyLeft` / `KeyRight` / `KeyJump` de
    `Data.Settings` (nom d'un `Enum.KeyCode`), meme remote `SetSetting` ; le serveur refuse tout nom
    hors de `RebindableKeys`.
  - KeyCode = position physique : la touche Z d'un AZERTY est `KeyCode.W`. Roblox gere donc deja
    Z Q S D sur AZERTY ; l'affichage passe par `GetStringForKeyCode` (le joueur voit Z, pas W).
  - En jeu (`MovementKeysController`) : touches par defaut -> rien n'est remplace. Sinon les 5 touches
    choisies + W A S D Espace sont prises par ContextActionService (priorite High, Sink) et, chaque
    image apres le module de controle Roblox, `LocalPlayer:Move(direction, true)` + `Humanoid.Jump`
    si une touche choisie est tenue. Fleches, manette et clic restent geres par Roblox.
- **Liste Settings** : hauteur du defilement calee a la main sur `UIListLayout.AbsoluteContentSize`
  + marges (2026-11-27). `AutomaticCanvasSize` comptait mal les lignes du pack (hauteur fixee par un
  `UIAspectRatioConstraint`) et coupait les 2 dernieres lignes des que la liste depasse la fenetre.
- **Index** (2026-11-20) : filtres de rarete du pack retires ; contenu refait par
  `IndexController` (grille des 100 fruits, bouton CLAIM). Voir `systems/fruits.md` (section Index).
- Icones ICONSPACK mises en ligne (17, type Image) : ids dans `Config/Icons.luau`. HUD : panier et
  livre ICONSPACK, icones plus coupees (ClipsDescendants retire, taille 100 %).
- ~~Index : renommer les raretes, construire les cases~~ fait le 2026-11-20 (`IndexController`).
- Bug corrige : le pack appelait `isSelected()` alors que c'est un champ dans TopbarPlus.
- Icone du bouton Shop du HUD : l'image d'origine (104216746370508) ne s'affichait pas, remplacee
  par le panier du menu Shop (97176673928357).
- Un id (203785492, "Pop Close Sound") n'est pas du bon type ("Asset type does not match") : introuvable
  dans la place et les scripts (verifie le 2026-11-23), vient probablement de TopbarPlus. Sans effet visible.
- 2026-11-23 : 3 images d'un autre createur ("hypnoticdeals", refusees hors de son compte) retirees des
  `.rbxm` : 104216746370508 (plaque des 15 croix ExitButton de ShopGUI : ImageTransparency 1, donc
  aucun changement visible), 103832952076051 (HUD ProgressBar Fill.Icon) et 94808176966042 (HUD
  Multipliers) : ces 2 cadres sont caches (Visible = false) et jamais montres. Fait sur disque par
  `tools/scripts/clear-asset-ids.py` (vide une propriete d'image d'un .rbxm binaire, sans Studio).
- Textes du pack a remplacer par les vrais (argent, Friend Boost, offres, contenus des menus).
- Argent reel branche le 2026-11-19 (`MoneyHudController`, voir `argent.md`). Reste : offres Robux,
  l'Index (fruits), Offline Earnings.
- Pas encore teste sur telephone (Device Simulator).
- 2026-11-19 (revue lot B) : Welcome Back utilise `NumberFormat.Money` (meme format que le HUD) et
  ne se referme plus si `Show` est appele menu ouvert ; flou des menus desactive a 0 ; pas d'effet
  de survol au toucher ; rotation des offres protegee par `pcall` ; texte "($0)" retire sous les
  packs d'argent (montant a calculer en phase 2-3). Restent : `WaitForChild` sans delai dans
  certains controleurs, attente de 1 s de MenuController dans OffersController, textes des offres
  petits sur telephone.
- **Panneaux 3D de la carte** (2026-11-19, demande utilisateur) : les `BillboardGui` (cartes des zones
  verrouillees, cartes des pads, compteurs "n/max", "Tree full!") avaient des contours en pixels fixes :
  de loin tout devenait noir, de pres le contour disparaissait. `BillboardStrokeController` (client)
  passe chaque contour d'un BillboardGui du Workspace en `StrokeSizingMode.ScaledSize`, avec
  l'epaisseur qu'il avait vu a la distance de reference (`PIXELS_PER_STUD` = 25, ~18 studs). Regler
  ce nombre pour epaissir (plus petit) ou affiner (plus grand) tous les contours d'un coup.
  `WorldLabel` cree directement ses contours en `ScaledSize` (0.06). Les menus 2D (shop, HUD) ne
  sont pas concernes : ceux du pack sont deja en `ScaledSize`.
  Teste dans Studio : carte "Terrace" a ~12 studs et a ~75 studs.

### Espacements et bouton X (2026-11-19 soir)

- `PackStyle.spaceList(liste, ratio)` : meme ecart entre les lignes et en haut / en bas d'une liste
  (part de sa hauteur visible, recalculee si elle change). Settings : 0.045 (l'Index a sa propre grille depuis le 2026-11-20).
- Bouton X des en-tetes (`MenuController.styleExitButton`) : le fond rouge fonce du pack, visible
  en bande sous l'image (effet "un truc derriere"), est retire ; une seule plaque en degrade
  `PackStyle.RED`, contour noir, croix en police du jeu.

## Touche E (prompts des bases)

- `Util/Prompt` cree tous les ProximityPrompt du jeu (E, X a la manette, appui sur mobile). Le serveur
  ne touche jamais `Enabled` : il pose l'attribut `Active` ; `PromptController` (client) decide.
- Regle : un prompt de base se montre seulement dans SA base et quand `Active ~= false`.
- Exception (2026-11-27) : attribut `ForOthers = true` (prompts "Steal" du pass Thief, `vol.md`) :
  montre seulement dans la base d'un AUTRE joueur (base avec proprietaire, pas la sienne).
