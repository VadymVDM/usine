# Systeme : Interface (HUD et menus)

**Statut :** en cours
**Derniere mise a jour :** 2026-11-19

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
| `src/client/Controllers/MusicController.luau` | client | Musique de fond |
| `src/client/Controllers/ShopController.luau` | client | Construit le contenu du menu Shop |
| `src/client/Controllers/OffersController.luau` | client | Offres animees a droite de l ecran |
| `src/client/Controllers/WelcomeBackController.luau` | client | Ecran "Welcome Back!" (gains hors ligne) |
| `src/client/Controllers/NotifyController.luau` | client | Message court du serveur en haut au centre (remote `Notify`), 3.5 s puis fondu |
| `src/client/UI/PackStyle.luau` | client | Briques de style communes (texte, boutons, Robux, prix) |
| `src/shared/Config/Shop.luau` | partage | Boosts, passes, packs d'argent (prix, ids Roblox) |
| `src/shared/Config/Icons.luau` | partage | Ids des images de l'interface |
| `assets/icons/` | disque | Icones choisies dans ICONSPACK, a mettre en ligne |
| `src/shared/Assets/UISounds.rbxm` | partage | Sons : BGMusic, Click, Hover, MenuOpen, ShopOpen, CloseMenu |
| `src/shared/Vendor/TopbarPlus.rbxm` | partage | Librairie TopbarPlus (bouton Settings dans la barre Roblox du haut) |

Les `.rbxm` sont des fichiers binaires Roblox : on les modifie dans Studio puis on les reexporte
(voir "Modifier l'interface"). Ils ne contiennent **aucun script**.

## Fonctionnement

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
  Caches dans le fichier (pour plus tard) : TopButtons, ProgressBar, UpgradeButton, Rebirth,
  DailyRewards, Multipliers, Friend Boost.
- Bouton Settings en haut : engrenage officiel Roblox
  (`rbxasset://textures/ui/Settings/MenuBarIcons/GameSettingsTab.png`).

## Remotes

Aucun pour l'instant.

## Donnees sauvegardees

Aucune.

## Configuration

`SETTINGS_ICON_IMAGE` en haut de `MenuController.luau`.

## Modifier l'interface (regle de synchro)

Les fichiers du disque font reference : toute modification d'interface doit finir sur le disque,
sinon Rojo l'ecrase.
- **A la main :** modifier dans Studio, puis clic droit sur le ScreenGui > Save to File > remplacer
  le fichier dans `src/gui/`.
- **Par l'agent (MCP) :** petit serveur local `127.0.0.1:34851` qui sert et recoit les `.rbxm`.
  Dans Studio : GET du fichier, `DeserializeInstancesAsync`, modification, `SerializeInstancesAsync`,
  POST. Rojo pousse ensuite le resultat dans le Studio "usine". Il faut `127.0.0.1:34851` dans la
  liste HTTP autorisee de l'Assistant du Studio utilise.
- **Attention :** ShopGUI (2 600 elements) traite en un seul appel a fait planter Studio le
  2026-11-19. Travailler un menu a la fois, avec `task.wait()` entre les morceaux.

## Problemes connus / a faire

- Sons du pack sans permission : remplaces (2026-11-19) par la serie officielle Roblox "RBLX UI" :
  Hover 10066931761, Click 10128760939, MenuOpen 10128766965, ShopOpen 10066968815,
  CloseMenu 10066914500, Purchase 10066947742 ; musique "Happy Daze (b)" (APM) 1839993539.
  Pas encore ecoutes en jeu.
- Icones : 19 icones de `D:\Downloads\ICONSPACK` copiees dans `assets/icons/`, **pas encore en ligne** :
  il faut autoriser le dossier `D:\Usine\assets\icons` (Assistant Settings > MCP Permissions > upload).
- Fait le 2026-11-19 : police ComicNeueAngular dans tous les menus, grille Index plus serree
  (cases "???"), textes Offline Earnings ("While you were away...", bouton x2 a 9).
- **Boutique** construite par `ShopController.luau` depuis `Config/Shop.luau` : Potions (3 boosts,
  15 min = 9, 30 min = 16), Passes (8, bouton cadeau 🎁 + prix), Cash Packs (4, "BEST VALUE").
  Achats **pas branches** : ids a 0, le clic affiche un avertissement dans la console.
  Les packs affichent "($0)" : a relier aux gains par minute du joueur.
- Style de la boutique (2026-11-19, demande utilisateur) : **comme le pack**, bords carres (aucun
  UICorner), fond a motif (89847456327542) + degrade 2 couleurs vives (`color`/`color2` dans
  Config/Shop), liseret blanc interieur, contour noir ; boutons verts en degrade (cadeau en rose).
- Boutique v3 (2026-11-19) : 3 potions sur une ligne ("2x SPEED / MONEY / LUCK"), gros boutons
  d'achat (prix + Robux dore centres, largeur selon le nombre de chiffres), logos plus petits,
  etiquettes BEST/OP au-dessus des cartes voisines, **tailles de texte egalisees par groupe**
  (titres, prix, lignes...) apres l'ouverture du menu et a chaque changement de taille d'ecran.
- Ecrans : jeu en paysage uniquement (`StarterGui.ScreenOrientation = LandscapeSensor` dans
  `default.project.json`) ; menus x1.25 si l'ecran fait moins de 450 px de haut ; menus sous la
  barre Roblox (`CoreUISafeInsets`) ; sur ecran tactile l'argent est decale a droite du joystick.
  Teste sur Samsung Galaxy A06 (simulateur). Limite : le clic simule ne marche pas en mode tactile.
- Boutique v4 (2026-11-19) : couleurs des boutons de la v2, passes compacts (titre grand, grosse
  icone en partie derriere les 2 lignes), titres de passes plafonnes a la mediane (un titre long ne
  fait plus retrecir les autres), tailles de prix separees par section, contours de texte gris tres
  fonce + coins arrondis (les coins pointus faisaient des pics). Etiquettes = rubans rouges/violets
  ("BEST", "OP", "BEST VALUE"). Reductions : `oldPrice` dans Config/Shop -> prix barre sur le coin du
  bouton + ruban "-30%" calcule ; **seulement pour une vraie promo** (aucune en place).
- **Mise en page dans le code** (`HUD_LAYOUT`, `MENU_ASPECT`, `MENU_WIDTH` en haut de MenuController) :
  colonne Shop/Index collee a gauche, livre bleu, argent plus grand et plus haut, menus Shop (1.65) et
  Index (1.4) plus larges, en-tete qui remplit toute la largeur. Ces valeurs passent par-dessus les .rbxm.
- **Offres limitees a droite** (`OffersController.luau`, `Config/Shop.LimitedOffers`) : rotation
  commune a tous les joueurs (heure serveur) : **visibles 10 min, cachees 2 min**, puis 3 nouvelles
  offres prises a tour de role dans `Pool`. Chaque offre : nom, icone sur rayons qui tournent,
  **minuteur rouge** (pas de prix : il est dans la fenetre), petite etiquette "-X%" en haut a droite de l'icone, sous le nom seulement si `oldPrice` (reduction sur certaines offres, par
  rapport au vrai prix de la boutique). Clic -> fenetre **"Limited Offer!"** (copie du menu
  OfflineEarnings du pack via `MenuController.CloneMenuTemplate` + `RegisterMenu`) : grande icone,
  nom, details, ancien prix barre + "-X%", "Ends in mm:ss", gros bouton vert avec contour dore qui
  pulse. Le bouton ouvre la **confirmation de paiement Roblox** (`PromptProductPurchase`) quand
  `productId` est rempli ; le serveur devra donner l'article (ProcessReceipt, a faire).
- Engrenage Settings : ICONSPACK "Settings White" (105567916477578), echelle 0.62.
- **Ecran "Welcome Back!"** (`WelcomeBackController`, menu `OfflineEarnings` du pack rempli par code) :
  "You were offline for Xh Ym and earned:", encadre du montant (billets + montant vert), bouton CLAIM
  vert (ferme l'ecran) et bouton x2 violet avec le prix Robux dessous (`Shop.OfflineDouble`, 9 R$).
  API : `WelcomeBackController.Show(secondes, montant)`. Gains reels pas encore calcules (serveur a
  faire) : en Studio, un exemple s'affiche au lancement (`SHOW_DEMO_IN_STUDIO`).
- **Pastille de notification** (petit rond rouge, contour noir, sans texte, immobile) sur un bouton du HUD pour signaler une nouveaute :
  `MenuController.SetBadge("Shop", true)` ; elle disparait quand le joueur ouvre ce menu.
  A utiliser des qu'il y a du nouveau a voir (offre, fruit decouvert, recompense...). En Studio, la
  demo l'affiche sur Shop.
- Telephone (2026-11-19, ecran < 450 px de haut) : **memes proportions que sur PC** (demande
  utilisateur ; les reglages `PHONE_MENU_*` restent dans le code mais sont desactives) ; titres de
  section proportionnels a la largeur de la boutique ; 3 cartes par ligne ; contours proportionnels a
  l'ecran ; colonne Shop/Index au ras du bord ; offres a droite remontees (bouton de saut libre).
- Etiquettes (BEST, OP, BEST VALUE, -X%) : rectangle rouge incline, petit contour noir, texte
  blanc ; construite en code, pas d'image.
  Teste : Galaxy A06 (705x338), iPhone 16 (733x392), PC (1417x578).
- Robux : **Robux blanc** (choix utilisateur) avec un **contour fonce** comme le texte (8 copies
  foncees decalees de 1-1,5 px autour, puis le blanc par-dessus), dans la boutique et les offres.
- Argent sur ecran tactile : aligne sous le bouton Index (meme bord gauche), un peu plus bas
  (`MoneyTouchY` = 0.975). Il touche legerement le bord du joystick sur Galaxy A06.
- Icones ICONSPACK mises en ligne (17, type Image) : ids dans `Config/Icons.luau`. HUD : panier et
  livre ICONSPACK, icones plus coupees (ClipsDescendants retire, taille 100 %).
- Index : renommer les raretes (Common... Divine du pack) en nos 10 raretes, construire les cases
  depuis `systems/fruits.md`.
- Bug corrige : le pack appelait `isSelected()` alors que c'est un champ dans TopbarPlus.
- Icone du bouton Shop du HUD : l'image d'origine (104216746370508) ne s'affichait pas, remplacee
  par le panier du menu Shop (97176673928357).
- Un id d'image (203785492) n'est pas du bon type ("Asset type does not match").
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
