# Architecture

## Rojo

`default.project.json`, port 34850.

| Disque | Studio |
|---|---|
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared/` | `ReplicatedStorage.Shared` |
| `src/gui/` | `StarterGui` |
| `src/first/` | `ReplicatedFirst` (prechargement invisible, voir `systems/chargement.md`) |

Workspace et ServerStorage ne sont pas geres par Rojo (`$ignoreUnknownInstances`) : la carte et
les modeles restent dans le fichier .rbxl. Ils sont construits par les scripts de
`tools/build-map/` (hors Rojo, relances via MCP `execute_luau`) : voir `docs/systems/carte-bases.md`.
Au demarrage, `BaseService` clone `ServerStorage.BaseTemplate` dans `Workspace.Bases`.

## Demarrage

- `src/server/Main.server.luau` charge chaque ModuleScript de `src/server/Services/`.
- `src/client/Main.client.luau` charge chaque ModuleScript de `src/client/Controllers/`.
- Ordre : `Init()` de tous les modules, puis `Start()` de tous (chacun dans son propre thread).
  Une erreur dans un module est affichee dans la console sans bloquer les autres.
- Client seulement : apres son `Start()`, un controleur peut avoir `Prewarm()` (preparer en coulisse,
  pendant le prechargement, HUD encore cache). Quand tout est fait, `Main` pose l'attribut joueur `ClientReady`.

Modele de service :

```luau
--!strict
local MoneyService = {}

function MoneyService:Init()
	-- preparer : tables, remotes. Ne pas attendre ici.
end

function MoneyService:Start()
	-- lancer : connexions, boucles.
end

return MoneyService
```

## Partage

- `src/shared/Config/GameConfig.luau` : valeurs globales du jeu.
- `src/shared/Assets/` : objets Roblox en `.rbxm` (sons de l'interface...).
- `src/shared/Vendor/` : librairies externes en `.rbxm` (TopbarPlus, licence MIT).
- `src/gui/*.rbxm` : interfaces (ScreenGui) en binaire, sans script ; la logique est dans `src/client/Controllers/`.
- `src/client/Fx/` : modules d'effets cote client, pas charges par `Main` (requis par les
  controleurs) : `Jelly` = deformation "gelee" + ressorts (mixeur, arbre, machines).
- `src/server/Vendor/` : librairies serveur en source (ProfileStore, Apache 2.0, voir
  `NOTICE-ProfileStore.md`). Pas charge par `Main` (seuls les ModuleScripts de `Services/` le sont).
- `src/shared/Util/` : petites fonctions partagees (`NumberFormat`, `TextUtil`, `WorldLabel` = textes 3D "n/max",
  `Prompt` = prompts E, `SoundFx` = sons de jeu cote client, `MachineModels` = modeles achetables
  d'une base : `Machines.<id>` + mixeurs `Production.Blenders.BlenderN` et leurs operateurs). `TutorialArrow` = fleche 3D jaune
  du tutoriel (jeu + apercu Edit).
- `src/server/Lib/` : aides serveur pas chargees par `Main` : `PlayerCheck` (personnage vivant,
  distance, zone, delai), `NpcRig` (rigs R6 des employes et clients, marche avec PathfindingService,
  animations, objets portes).
- `src/shared/Config/Tree.luau` : les 5 stades de l'arbre (points, rayon et hauteur de chute).
- `src/shared/FruitModels.luau` : fruits = clones des fruits voxel `ReplicatedStorage.FruitAssets`
  (construits dans Studio par `tools/build-assets/fruits-voxel.luau`, hors Rojo) + effets de rarete ;
  gobelets generes depuis la Config
  (aucun modele de fruit dans le .rbxl).
- `src/shared/Network/Remotes.luau` : la liste des remotes (voir plus bas).

## Remotes (decide le 2026-11-19, phase 1)

- Le moins possible. **Deux remotes client -> serveur : `SetSetting`** (reglages du menu
  Settings, sans effet sur la partie, ajoute le 2026-11-19 soir) **et `BuyUpgrade`** (achat apres
  appui long ou pop-up de confirmation, ajoute le 2026-11-19 a 16:45). Les autres actions du joueur passent par des
  ProximityPrompt (touche E, `Triggered` cote serveur) et des contacts detectes par le serveur
  (pads, table a argent). Chaque action est reverifiee : proprietaire de la base, distance
  (`PlayerCheck.CanReach`), delai (`PlayerCheck.Cooldown`), etat (place libre, argent...).
- Un seul endroit : `src/shared/Network/Remotes.luau` liste les noms. Le serveur cree
  `ReplicatedStorage.Remotes` et les RemoteEvents (`Remotes.GetServerEvent`, appele dans
  `NotifyService:Init`), le client les attend avec un delai de 15 s (`Remotes.WaitClientEvent`).

| Remote | Sens | Envoye par | Contenu | Verifications |
|---|---|---|---|---|
| `Notify` | serveur -> client | `NotifyService.Notify(player, texte, isError?)` | texte anglais de la Config, coupe a `Map.MaxNotifyLength` ; `isError` (bool) = affiche en rouge | client : type string, UTF-8, longueur ; isError ~= true = blanc |
| `Feedback` | serveur -> un client | ProductionService, CustomerService | effet de SON action : (kind, payload) Pickup / Deposit / TakeJuice / PlaceJuice / Cash / AutoCash / PurchasePrompt (fenetre d'achat Robux ouverte, sans payload ; `Lib/PurchasePrompt`) | client : types, ids connus, nombres et Vector3 finis, tailles max |
| `WorldFx` | serveur -> tous | CustomerService, ProductionService | effet visible dans une base : (base, kind, payload) Sale / FruitsToBins | client : base dans `workspace.Bases`, types, ids connus |
| `BuyUpgrade` | client -> serveur | BuyController | (id) : amelioration / employe a acheter (1 niveau) | serveur (UpgradeService) : string <= 40, id connu, etage ou se trouve le joueur (hauteur du personnage, `FloorService.GetPlayerFloor`), proprietaire, joueur pres d'un point d'achat de cet id (prompt de la machine fantome, tuile verte, pad pas encore achete ou pad "Upgrade Tree" ; portee + `BuyClickExtraDistance`), delai `BuyCooldownSeconds`, niveau max, argent (`MoneyService.TrySpend`). Le client n'envoie jamais de prix |
| `PadEnter` | client -> serveur | PadController | (nom du pad) : le joueur vient de monter sur un pad d'action de sa base (reaction sans attendre la boucle des pads) | serveur (ProductionService : FruitDrop, TakeJuice ; CustomerService : JuiceDrop, Cash) : nom connu (les autres ignores), etage de SA tour ou il se trouve, personnage vivant, position dans la `PadZone` + `PadEnterMargin` studs, delai 0.15 s par pad + `PadActionSeconds` de l'action, etat (fruits, place, argent). Le client n'envoie aucune quantite |
| `SetSetting` | client -> serveur | SettingsController | (cle, booleen) : Music / Effects / LowQuality | serveur (SettingsService) : cle dans `GameConfig.DefaultSettings`, valeur booleenne, sauvegarde chargee ; demandes a moins de `SettingCooldownSeconds` (0.25 s) regroupees (la derniere valeur gagne, appliquee apres le delai) |
| `FloorTeleport` | client -> serveur | FloorController | (numero d'etage) : fleches du selecteur d'etage (haut de l'ecran) | serveur (FloorService) : nombre entier, 1..etages achetes de SA tour, delai `Floors.TeleportCooldown` (0.5 s) ; teleport sur `Markers.SpawnPoint` de l'etage apres `RequestStreamAroundAsync`. Voir `systems/tour-etages.md` |
| `IndexState` | serveur -> un client | IndexService | { discovered = {ids}, claimed = {ids} } : etat de l'Index (chargement, decouverte, claim) | client (IndexController) : tables, ids connus |
| `IndexClaim` | client -> serveur | IndexController | (id du fruit) : bouton CLAIM de l'Index | serveur (IndexService) : chaine, fruit connu, sauvegarde chargee, fruit decouvert, pas deja pris, delai `GameConfig.IndexClaimCooldown` (0.15 s) ; montant calcule par le serveur (`Fruits.ClaimReward`). Voir `systems/fruits.md` |
| `BuyPlayerUpgrade` | client -> serveur | UpgradeMenuController | (id) : bouton vert d'une ligne du menu Upgrade | serveur (PlayerUpgradeService) : chaine, id connu (`Config/PlayerUpgrades`), sauvegarde chargee, delai 0.25 s, niveau < max, argent (`MoneyService.TrySpend`, prix calcule par le serveur). Voir `systems/ameliorations-joueur.md` |
| `RebirthRequest` | client -> serveur | RebirthController | (action) "Rebirth" (payer et renaitre) / "KeepCash" (demander l'achat Robux "Rebirth & keep your cash") : boutons du menu Rebirth | serveur (RebirthService) : action connue, delai 1 s, sauvegarde chargee, 10 etages, joueur pres de la machine de SA salle du Rebirth, argent >= prix (calcule par le serveur) ; le produit Robux est choisi par le serveur. Voir `systems/rebirth.md` |
| `LuckyCashBuy` | client -> serveur | LuckyCashController | (rien) bouton Robux de la fenetre "Lucky Find!" | serveur (LuckyCashService) : delai 1 s, sauvegarde chargee ; montant calcule et note par le serveur, produit choisi par le serveur, argent donne seulement a la reception du recu. Voir `systems/lucky-cash.md` |
| `ShopBuy` | client -> serveur | ShopController, OffersController | (kind, key, isGift) : bouton d'achat de la boutique ou d'une offre limitee | serveur (RobuxShopService) : chaines courtes, cle connue du catalogue `Config/Shop`, delai 0.5 s ; montants d'argent calcules et notes par le serveur, produit choisi par le serveur, effet donne seulement a la reception du recu (une fois par PurchaseId). Voir `systems/achats-robux.md` |
| `TutorialProgress` | client -> serveur | TutorialController | (numero) : etape suivante du tutoriel | serveur (TutorialService) : entier, exactement +1, <= Done, sauvegarde chargee, delai 0.3 s ; guidage seulement. Voir `systems/tutoriel.md` |
| `IntroDone` | client -> serveur | IntroController | (rien) : cinematique d'ouverture finie ou passee | serveur (IntroService) : delai 2 s, sauvegarde chargee ; ecrit seulement `IntroSeen = true`. Voir `systems/cinematique.md` |
| `OfflineEarnings` | client <-> serveur | WelcomeBackController | client -> serveur : `"Ready"` (chargement fini), `"Claim"`, `"Double"` ; serveur -> client : `"Show"` (secondes, montant), `"Claimed"` | serveur (OfflineService) : action connue (le reste ignore), delai 0.5 s, sauvegarde chargee, offre pas deja prise (`Claimed` / `Doubled` sauvegardes) ; montant calcule par le serveur ; x2 donne seulement au recu. Voir `systems/gains-hors-ligne.md` |
| `AdminAction` | client -> serveur | AdminController | (action) "MaxMoney" / "AddFloor" / "AllFloors" / "ResetFloors" / "Rebirth" / "ResetAll" : boutons du panneau admin | serveur (AdminService) : joueur admin (createur, `AdminUserIds`, ou Studio), action connue, delai `AdminCooldownSeconds` (1 s) ; aucune valeur lue du client. Voir `systems/admin.md` |

- Prompts E : le serveur ne change jamais `Enabled` ; il pose l'attribut `Active`. Le client
  (`PromptController`) n'affiche que les prompts de SA base et actifs. `ClickDetector` : seulement les
  boutons des panneaux d'ameliorations et le dessus des pads (curseur main) ; l'achat ne se fait
  plus au clic mais a l'appui long (`BuyController` -> `BuyUpgrade`).
- Chaque remote client -> serveur futur est verifie cote serveur : type, id connu, possession de
  la base, distance, prix / niveau max, delai entre deux demandes. Le client n'envoie jamais de
  prix ni de montant.

## Achats Robux (Developer Products, 2026-11-20)

- `ReceiptService` est le **seul** a ecrire `MarketplaceService.ProcessReceipt`. Chaque service
  enregistre ses produits dans son `Init` : `ReceiptService.Register(productId, handler)` ; le
  handler renvoie `true` seulement quand l'achat est ecrit une seule fois de facon durable
  (PurchaseId deja vu = succes). Premier utilisateur : `DonationService` (`systems/dons.md`).
- Le client demande l'achat lui-meme (`PromptProductPurchase`) ; `PromptProductPurchaseFinished`
  sert seulement a fermer une fenetre, jamais a donner quelque chose.

## Donnees joueur

- `DataService` ouvre/ferme les sessions (ProfileStore). Chaque champ a un seul module qui le
  modifie (voir `docs/systems/sauvegarde.md`). Les autres modules s'abonnent avec
  `DataService.OnPlayerLoaded` / `OnPlayerRemoving` (l'ordre des `Start()` n'est pas garanti).

## Bases

- `BaseService` (seul a ecrire `OwnerUserId` sur les bases et `BaseId` sur les joueurs) :
  `GetBase(player)`, `GetOwner(base)`, `GetBases()`, `OnBaseAssigned(cb)`, `OnBaseReleased(cb)`.
  Les services des lots C a E rangent ce qu'ils creent dans `Base.Dynamic` (vide au depart) et
  arretent leurs boucles dans `OnBaseReleased`.
- **Tour d'etages (phase 1b, 2026-11-20)** : `FloorService` (depend de BaseService, DataService,
  MoneyService, NotifyService) construit les etages de chaque base (`base.Floors.FloorN`, modele
  `ServerStorage.FloorTemplate` via `Lib/FloorAssembly`) et previent les autres services :
  `OnFloorAdded` / `OnFloorStarted` / `OnFloorStopped` / `OnFloorRemoving` / `OnLiveFloorChanged`.
  Tree, Production, Customer, Worker et Upgrade travaillent PAR ETAGE (etat indexe par le Model de
  l'etage), plus par base. L'etage du joueur se deduit de la hauteur de son personnage
  (`FloorService.GetPlayerFloor`), jamais d'un numero envoye par le client (sauf `FloorTeleport`,
  verifie). Production en nombres : `Lib/FloorIncome`. Client : `Util/FloorWatch` suit les etages
  ouverts. Detail : `systems/tour-etages.md`.
- `UpgradeService` (seul a ecrire `Data.Floors[n].Upgrades`) : machines fantomes / construites, pads verts des
  employes, tuiles des panneaux, achats (prompt E des machines, pad des employes, boutons des
  panneaux ; verifies serveur). Le client
  `MachineFxController` lit seulement des attributs (Built, BuildStamp, Price, Bought, Denied, Pulse)
  pour animer. `UpgradeService.OnBought(cb)` previent apres chaque achat.
- `TreeService` (arbre, fruits au sol, prompt E de chaque fruit) et `ProductionService`
  (inventaire, mains, caisses, presse, table a jus, prompts de l'etagere et de la table) demarrent
  quand le joueur a sa base ET sa sauvegarde. TreeService reste le seul a creer / retirer les fruits
  au sol (`TakeAround`, `FindNearest`, `TakeFruit`). Chaque boucle protege son tour par `pcall`.
- `CustomerService` (comptoir, ventes, tas d'argent, pad Auto Collect) depend de ProductionService ;
  `WorkerService` (employes R6 serveur : Fruit Picker, Blender Operator) depend de
  TreeService, ProductionService et UpgradeService ; `AutoSellService` (pad Auto Sell : jus de la
  table -> comptoir, remplace le Waiter le 2026-11-20) depend de ProductionService, CustomerService,
  DataService et FloorService. Pas de dependance en cercle.
- Les clients (PNJ) sont dessines par chaque client (`CustomerController`) a partir des modeles R6
  faits par le serveur (`ReplicatedStorage.NpcTemplates`) ; les employes sont des Humanoid serveur
  (groupe de collision "Npc" : ils ne bloquent ni les joueurs ni entre eux).

## Tests en Studio

- `DebugService` (actif seulement dans Studio) : `ServerStorage.Debug.Call` (BindableFunction).
  Un `require` depuis la barre de commande ou MCP cree une copie separee des modules : passer par
  ce BindableFunction pour appeler les vrais services pendant un playtest.

## Outils de verification (decide le 2026-11-19)

- **Selene 0.32.0** (analyse) : installe dans `%LOCALAPPDATA%\LuauTools\selene.exe` (binaire officiel
  GitHub Kampfkarren/selene). A lancer a la fin de chaque lot :
  `& "$env:LOCALAPPDATA\LuauTools\selene.exe" --display-style quiet src`. `selene.toml` exclut
  `src/server/Vendor/` (ProfileStore). Etat au 2026-11-19 : 0 erreur, 8 avertissements connus dans
  l'interface (variables masquees, `UDim2.new` -> `fromScale`), laisses car on ne refactore pas l'UI.
- **StyLua : pas utilise.** Essaye le 2026-11-19 : il reecrivait 30 fichiers (+1775 lignes),
  surtout en eclatant les tables compactes (`Config/Fruits.luau`, scripts de `tools/build-map/`),
  ce qui rend la Config moins lisible sans rien corriger. `stylua.toml` reste pour plus tard.
