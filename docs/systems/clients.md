# Systeme : Comptoir, clients et tas d'argent

**Statut :** en cours (fonctionne en playtest Studio a 1 joueur le 2026-11-19 ; 2 joueurs, telephone
et vrai pass Robux non testes)
**Derniere mise a jour :** 2026-11-27 soir (vraies files d'attente, bulles emoji, arrivee et depart au loin)

> **Vraies files d'attente (2026-11-27 soir, demande : "vraies queues plus naturelles, emojis
> au-dessus de leurs tetes en boule, disparaitre et apparaitre plus loin")** - tout dans
> `CustomerController` (client seulement, le serveur n'a pas change) :
> - **Rez-de-chaussee** : une vraie file par place du comptoir (avant : 1 client au comptoir + 1
>   derriere). Longueur `Npcs.CustomerLineLength` selon le nombre de places (5, 4, 4, 3, 3), +-1 au
>   hasard, retiree toutes les 8 a 18 s. Ecart avec celui de devant au hasard (`CustomerLineGap`
>   2.8 a 3.5 studs), petit decalage de cote (`CustomerLineJitter`), regard pas tout a fait droit.
>   Files en **eventail** (6 degres de plus par file vers l'exterieur) : 5 files droites a 5 studs
>   faisaient une masse. Bout de file limite (reste a 4.5 studs de la voie des departs).
> - **Arrivee** : en fondu (`CustomerFadeInSeconds` 1 s), loin sur le trottoir cote route
>   (`CustomerSpawnFar` 70 studs avec peu de clients -> 30 avec beaucoup), marche jusqu'au bout de
>   SA file. Traversee du trottoir a 3.2 studs au moins d'un lampadaire. Jamais au-dela du bout de
>   la route (`Map.Road.Asphalt`). Une arrivee toutes les 0.3 a 0.9 s (`CustomerSpawnGap`), vers la
>   file la plus en retard.
> - **La file avance en accordeon** : chacun part 0.12 a 0.22 s apres celui de devant, en marchant
>   plus doucement (55 % de la vitesse). Ceux qui attendent regardent autour d'eux de temps en temps.
> - **Depart** : le client servi longe le comptoir (entre le comptoir et le premier rang) jusqu'au
>   bord des files, descend vers la rue en suivant l'eventail, part dans l'herbe entre le trottoir
>   et les bases (`CustomerLeaveFar` 55 -> 20 studs) et disparait en fondu sur les 10 derniers studs.
> - **Etages 2+** : la file de la terrasse est une vraie file (memes ecarts au hasard ; avant :
>   clients espaces pour remplir toute la terrasse). Arrivee de loin par le trottoir. Le premier
>   attend a 3.5 studs de la porte de l'ascenseur. Client servi : longe le comptoir vers
>   l'ascenseur, attend a cote de la porte (12 au plus, sinon fondu a la porte comme avant), monte
>   dans la cabine quand elle est en haut, redescend, sort cote terrasse, contourne la cage et part
>   dans la rue (fondu au loin). Personne a monter mais des clients attendent en haut : la cabine
>   monte a vide les chercher.
> - **Bulles emoji** (`Fx/EmojiBubble`) : boule blanche a contour fonce + 2 petites bulles de
>   pensee, apparait avec un rebond. Au comptoir, comptoir vide : 🥤 avec pastille rouge "?" (remplace
>   la bulle texte "Juice?"). Clients qui attendent : une bulle de temps en temps (`Waiting` :
>   🥤😋🤤🍹🧃🤔🎵👀... ; `Impatient` si comptoir vide ou plus de 25 s : ⏳😤😒🥱😴), 4 + 1 par place
>   au plus en meme temps. Client servi : bulle contente (😍😋🤩❤️👍✨😄) 1.8 s.
> - **Vente sans client pret au comptoir** : elle attend le prochain client qui arrive au comptoir
>   (2 par place au plus), sinon "+$" et son seuls. Plus de client pose d'un coup au comptoir
>   (avant, au rez-de-chaussee : apparition ou teleportation au comptoir).
> - **Sons contents** (2026-11-27 soir, demande : "effets sonores contents satisfaisants quand on
>   leur rapporte les jus" ; ecoutes et valides par Adam en Play : "le son est parfait") :
>   client servi = ka-ching (`Sale`) + ding scintillant `CustomerHappy` (la note monte de 5 % par
>   vente enchainee en moins de 1.5 s, 8 crans au plus ; 1 ding / 0.1 s par etage) + `CustomerSip`
>   ("slurp" cartoon 0.55 s apres, 1 / 0.3 s par etage, volume 0.9 : -10 % le 2026-11-27). Jus
>   poses sur le comptoir vide alors que des clients attendaient au comptoir depuis au moins 1 s :
>   ils passent a une bulle contente, sans son (~~`CustomersCheer`, "Yeah" d'enfants~~ retire le
>   2026-11-27 a la demande d'Adam). Ids et sources dans `Config/Sounds.luau` (ProSoundEffects).
> - Boucle sur `Heartbeat` (avant `RenderStepped`) : continue quand l'image n'est pas dessinee.
> - Au plus `CustomerMaxPerFloor` (48) clients dessines au rez-de-chaussee ; test a 6 ventes / s :
>   28 clients au plus.

> **Clients en R15 (2026-11-27, demande : "passer TOUS les PNJ en R15, comme les joueurs")** : les
> modeles `NpcTemplates.Customer1..8` sont des rigs R15 (`NpcRig.Prepare`). `CustomerController`
> joue les animations R15 des joueurs (`Npcs.AnimationsR15` : attente, marche, course) ; marche et
> course jouees ensemble et melangees selon la vitesse du client (`Npcs.CustomerWalkSpeed` 10 x 0.92
> a 1.08), meme formule que le script Animate et que les employes (`Util/R15Walk`). A 10 studs/s
> c'est l'animation de course qui domine (comme un joueur a cette vitesse). Gobelet tenu a deux mains
> (`CarryPose`, bras R15 vers l'avant, point de prise calcule depuis `UpperTorso`). Avant : rigs R6,
> `Npcs.Animations` (R6) + `Npcs.WalkAnimSpeed`, supprimes. Le prechargement (`Preloader`) charge
> les animations R15. Verifie en Play (etage 2) : marche, attente, prise du gobelet, depart,
> cheveux a leur place.

## Role

> **Un tas d'argent PAR ETAGE (2026-11-20 soir, demande de l'utilisateur)** : chaque etage a sa table
> a argent (`MoneyTray`, `MoneyPile`, `MoneyLabelAnchor`) et son pad `CashPad` ; les ventes d'un
> etage vont sur SON tas ; il faut aller sur l'etage pour encaisser. `AutoCollectPad` est aussi sur
> chaque etage depuis le 2026-11-21 (avant : etage 1 seulement, `Counter.OnlyGround`) ; le pass vaut
> pour toute la tour (a l'achat : tous les tas encaisses). `CollectPile(player)` encaisse les tas de tous les etages (rebirth). Prix de vente x2
> avec le pass Billboard (`sellMultiplier`, voir `pads-robux.md`).
>
> **Tour d'etages (2026-11-20, phase 1b lot 3)** : chaque etage a son comptoir et ses ventes
> (`CustomerSpeed` / `CustomerCount` de l'etage). ~~Un seul tas d'argent a l'etage 1~~ (remplace le
> soir meme, voir au-dessus). Attributs `CounterJuices`, `CustomerSlots`, `IncomePerHour`, `PileCash` (argent sur le tas, lu par le tuto) sur l'etage. Clients
> des etages 2+ : voir plus bas (lot 5).
>
> **Lot 5 (2026-11-20, pas encore teste en jeu)** :
> - **Etage dessine** : seulement l'etage `ActiveFloor` de la base (1 si absent) ; au changement,
>   fondu 0.25 s des clients de l'ancien etage. Le serveur n'envoie `Sale` que pour l'etage actif.
> - **Etages 2+** : file en SERPENTIN dans toute la longueur de la terrasse (2026-11-20, retour de
>   test : "la terrasse ne sert a rien") : 4 allees nord-sud entre des cordes rouges
>   (`Annex.Terrace.QueuePath.Point1..8`, le client lit Point1..N) -> `ElevatorEntry`. Taille de la
>   file = 10 + 6 x emplacements (max 40, `QUEUE_*` dans CustomerController) ; ~~ecart entre deux
>   clients = longueur du chemin / 40~~ (2026-11-27 soir : vraie file, ecarts 2.8 a 3.5 studs, voir en haut).
>   Jusqu'a 40 clients R15 dessines en plus : a surveiller sur telephone, cabine animee en local (`Annex.ElevatorBase.Cabin`, sinon cabine simple creee
>   par le client), sortie sur le balcon, place reservee a l'embarquement ; depart : retour a la
>   sortie de l'ascenseur et fondu.
> - Cabine : duree = (3 + 0.6 x (etage - 2)) / (1 + 0.04 x ElevatorSpeed), descente x0.6 ; capacite
>   = 2 + floor(ElevatorCabin / 5) (A VALIDER, constantes en haut de `CustomerController`).
> - Vente sur un etage 2+ sans client pret au comptoir : "+$" et son seuls (pas de teleportation).
> - Les etages ou le joueur n'est pas vendent "en nombres" (voir `tour-etages.md`).

Le joueur (ou le Waiter) pose les jus sur le comptoir ; des clients R15 viennent de la route, prennent
un jus et laissent son prix sur la table a argent ; le joueur encaisse en se tenant sur le pad
"Collect Cash".

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/CustomerService.luau` | serveur | Comptoir (prompt E), minuteur des ventes, tas de billets, encaissement, pad Robux Auto Collect. Seul a modifier le comptoir et le tas |
| `src/client/Controllers/CustomerController.luau` | client | Clients R15 dessines par chaque client (vraies files, arrivee / depart au loin, ascenseur, prise du gobelet, "+$", bulles emoji) |
| `src/client/Fx/EmojiBubble.luau` | client | Bulle ronde avec un emoji au-dessus d'un client (rebond a l'apparition, pastille "?") |
| `src/client/Controllers/CashController.luau` | client | Billets 2D qui volent un par un du tas jusqu'au montant d'argent du HUD (bas gauche) ; a chaque billet un pop plus aigu, le HUD compte et rebondit, "+$X" a droite du montant ; ding a la fin |
| `src/client/Controllers/MoneyHudController.luau` | client | Montant du HUD : compte en montant (Hold / Release pendant l'encaissement), rebond (Bump) ; voir `argent.md` |
| `src/server/Lib/NpcRig.luau` | serveur | Fabrique les modeles R15 des clients (`ReplicatedStorage.NpcTemplates.Customer1..8`) |
| `src/shared/Config/Npcs.luau` | partage | Tenues (vetements gratuits du catalogue Roblox), vitesse, file d'attente, distance d'affichage |
| `src/shared/Util/R15Walk.luau` | partage | Melange marche / course R15 selon la vitesse (meme formule que les employes) |
| `src/shared/Config/Upgrades.luau` | partage | CustomerSpeed, CustomerCount |
| `src/shared/Util/RobuxPad.luau` | partage | Style commun des pads Robux (Auto Collect, Instant Sell...) : forme des pads verts en violet ; `SetPrice` ("R$ 149" / "ACTIVE") |
| `tools/build-map/02d-base-counter.luau` | Studio | Comptoir, table a argent (velours rouge), pad Robux Auto Collect (forme des pads verts en violet : `Util/RobuxPad.Style`, depuis le 2026-11-20), panneau "MONEY / HOUR" (`Counter.IncomeSign`), decor du comptoir par niveau de Faster Customers (`Counter.SpeedDecor`) |
| `tools/build-map/02g-base-boards.luau` | Studio | Panneau **Customers** (Faster Customers + More Customers) sur la facade, a cote de la fenetre du comptoir |

## Fonctionnement

- **Prix d'un jus vendu** (2026-11-20) : valeur du fruit x multiplicateur du rebirth
  (`Rebirth.Multiplier(Data.Rebirths)` : x1, x2, x3...), arrondi a l'entier. Meme multiplicateur
  sur la production "en nombres" des etages ou le joueur n'est pas (`incomeOf`) et donc sur
  l'attribut `IncomePerSecond`. `CustomerService.CollectPile(player)` encaisse tout le tas d'un coup
  (utilise juste avant un rebirth). Voir `rebirth.md`.
- **Comptoir** : derriere le comptoir, **pad "Drop Juices"** (bleu, `Counter.JuiceDropPad`) : se
  tenir dessus = tous les jus des mains sont deposes ; chaque jus va sur le comptoir de l'etage
  de SON fruit (2026-11-20 soir : on peut deposer a n'importe quel comptoir, les gobelets volent
  jusqu'au bon ; comptoir pas charge -> il reste ici). **Pas de limite** (2026-11-19 :
  plus d'amelioration CounterLimit ni de vitrine ; on ameliore seulement la vitesse et le nombre
  de clients). Remote `PadEnter` a l'arrivee (client
  `PadController`, reaction immediate) puis test serveur 10 fois / s, proprietaire
  seulement, delai `PadActionSeconds`. Plus de prompt E (2026-11-19). Les jus quittent les mains et se rangent en grille sur
  `Counter.CounterTopArea` (couches). Au-dela de `CounterCupLayersMax` (3) couches, les gobelets
  ne sont plus dessines (le compteur continue). Au-dessus : "xN" (nombre de jus).
- **Ameliorations** (2026-11-19 soir : avant, "Fast Register" sur le comptoir et "Billboard" dans la
  cour, qu'on ne comprenait pas) : panneau **Customers** sur la facade, a cote de la fenetre du
  comptoir : "Faster Customers" (Time between customers, "1.8s > 1.7s") et "More Customers"
  (Customers buying at once, "1 > 2"). Ce qui se voit : sonnette, caisse, guirlande,
  bord dore sur le comptoir (Faster Customers) ; panneau FRESH JUICE! dans la cour qui apparait au
  niveau 2 puis grandit (More Customers). Voir `ameliorations-employes.md`.
- **Panneau "MONEY / HOUR"** (2026-11-19 soir) : au-dessus de la fenetre du comptoir, cote
  interieur (`Counter.IncomeSign`, texte `Board.Display.Value`). `CustomerService` garde les ventes
  des `IncomeWindowSeconds` (120 s) dernieres secondes (auto-collect compris) et affiche leur somme
  ramenee a une heure ("$12.5K") ; au debut il divise au moins par `IncomeMinSeconds` (30 s) pour
  ne pas afficher un chiffre enorme apres 2 ventes. Mis a jour a chaque tour de vente ; aussi
  l'attribut de base `IncomePerHour`. "$0" quand la base est libre.
- **Attribut joueur `IncomePerSecond`** (2026-11-20) : toutes les `Gameplay.IncomeAttributeSeconds`
  (10 s), `CustomerService` pose sur chaque joueur ses gains theoriques de toute la tour
  (`GetIncomePerSecond`). Sert aux offres d'argent ("+$3K", voir `interface.md`).
- **Ventes (serveur)** : toutes les `CustomerSpeed` secondes (1.8 s au niveau 1 depuis le 2026-11-20, avant 2.5 s), pour chaque place
  1..`CustomerCount`, s'il reste un jus : le dernier gobelet pose est vendu, son prix (valeur du
  fruit) va sur le tas d'argent. Le serveur envoie `WorldFx` "Sale" { spot, fruit, amount } a tous
  et pose sur la base `CustomerSlots` (places actives) et `CounterJuices` (jus au comptoir).
- **Clients (client seulement, aucune charge serveur)** : pour chaque base avec proprietaire a moins
  de `CustomerRenderDistance` (220) : au rez-de-chaussee, une vraie file par place active (voir le
  bloc "Vraies files d'attente" en haut) ; etages 2+ : file de la terrasse, puis au balcon un client
  "devant" chaque place et un "qui attend" derriere (`CustomerQueueGap`). Animations R15 des joueurs
  (marche + course melangees : `Util/R15Walk`). Bulle 🥤 + "?" si le comptoir est vide.
  Sur "Sale" : le gobelet vole dans ses mains (bras tendus, `CarryPose`), "+$5" monte au-dessus de
  lui avec une bulle contente, il repart et disparait au loin ; la file avance.
- **Tas d'argent** : de vraies liasses de billets (vert clair) et des pieces sur le tapis rouge de
  la table (`Counter.MoneyPile`) : 12 piles, +4 billets a chaque fois que le montant double, 60 max.
  Montant au-dessus ("$1.2K"). **Encaisser** : se tenir sur le **pad "Collect Cash"** (jaune,
  `Counter.CashPad`, devant la table ; plus de prompt E ni d'encaissement en s'approchant de la
  table, 2026-11-19). `MoneyService.Add`, puis `Feedback` "Cash" (client, `CashController`) :
  des billets 2D (rectangle vert arrondi, "$" au milieu, taille relative a la hauteur de l'ecran)
  sortent du tas (position 3D projetee a l'ecran), font un petit saut puis volent en courbe, un par
  un (0.045 s ; tous partis en 0.4 a 0.9 s), jusqu'au **montant d'argent du HUD en bas a gauche**.
  A chaque billet qui arrive : pop un peu plus aigu (gamme qui monte), le montant du HUD **monte en
  comptant** de la part de ce billet avec un petit rebond, et le "+$X" (vert, juste a droite du
  montant, il suit le texte qui s'allonge) grimpe. Dernier billet : ding + gros rebond du HUD et du
  "+$X", qui monte et s'efface 0.9 s plus tard. Le HUD compte ~0.7 a 1.2 s selon le nombre de
  billets. Deux encaissements rapproches s'additionnent dans le meme "+$X".
  Comment le HUD compte (`MoneyHudController`) : le serveur met `leaderstats.Cash` a jour tout de
  suite ; `CashController` retient le montant encaisse (`Hold`) puis le relache billet par billet
  (`Release`), et le texte rattrape la valeur (reelle - retenue) en comptant. Securite : tout ce
  qui est retenu est relache apres 4 s. Autres hausses (Auto Collect, admin, gains hors ligne) :
  petite montee rapide (~0.3 s) + rebond, apres 0.12 s d'attente ; baisse (achat) : immediate.
- **Pad Robux "Auto Collect"** (violet, a cote de la table) : marcher dessus = achat du pass
  `Shop.Passes` "AutoCollect" (`MarketplaceService:PromptGamePassPurchase`). `passId = 0` tant que le
  pass n'est pas cree : message "Robux purchases: coming soon!". Pass possede : l'argent de chaque
  vente va directement au joueur (`Feedback` "AutoCash" : petit "+$5" a droite du montant du HUD ; depuis le 2026-11-23 un
  seul texte a la fois, les montants rapproches s'y additionnent, "pop" au plus tous les 0.25 s :
  avant, chaque etage automatise affichait son propre texte au meme endroit et ils se superposaient),
  le pad affiche "ACTIVE". **Depuis le 2026-11-21** : possession = attribut joueur `AutoCollect`
  (pose par le serveur seulement, comme les autres passes). Avant, c'etait une table interne de
  CustomerService : la boutique ne la voyait pas, et le bouton admin ne marchait que si le joueur
  etait dans son usine (bug "l'auto collect ne marche pas"). Quand l'attribut passe a vrai, les tas
  de tous les etages sont encaisses tout de suite (billets qui volent pour l'etage ou est le joueur).
  **Depuis le 2026-11-21** : un pad par etage (meme place). Le drapeau "sur le pad" est rangé par
  etage (`state.onAutoPad`) pour que la fenetre d'achat ne s'ouvre qu'a l'arrivee ; l'etiquette
  "ACTIVE" / prix est remise a jour sur le pad de chaque etage du joueur.
- **Pass Robux "Instant Sell"** (2026-11-21, ancien "Auto Sell" ; pad violet a droite du pad Drop
  Juices, voir `pads-robux.md`) : avec l'attribut joueur `InstantSell`, les jus que le JOUEUR pose
  sur le comptoir sont vendus des que l'animation de depot est finie (`Gameplay.InstantSell*` :
  0.32 s + 0.06 s par gobelet, au plus 1.5 s, + 0.15 s), sans attendre les clients. Prix comme une
  vente normale (rebirth, Billboard, 3X CASH, ascenseur), argent sur le tas (ou direct avec Auto
  Collect), `Feedback` "InstantSell" (son). Les jus poses par le Waiter attendent les clients.
- Rien n'est sauvegarde : comptoir et tas repartent a zero (le tas est perdu si le joueur part).

## Remotes

| Nom | Sens | Contenu | Verifications (client) |
|---|---|---|---|
| `WorldFx` | serveur -> tous | (etage, "Sale", { spot, fruit, amount }) | etage (`Floors.FloorN`) d'une base de `workspace.Bases`, spot entier 1..5, fruit connu, montant fini >= 0 |
| `Feedback` | serveur -> le joueur | "PlaceJuice" { count }, "Cash" { amount, from, bills }, "AutoCash" { amount, from }, "InstantSell" { amount, count } | types, nombres finis, Vector3 finis |

Actions du joueur : pads (Drop Juices, Collect Cash, Auto Collect), verifies par le serveur :
proprietaire de la base, position du personnage dans `PadZone` (marge `PadEnterMargin` pour le
remote `PadEnter`), delai, etat (jus dans les mains, argent sur la table).

## Donnees sauvegardees

Aucune (niveaux `CustomerSpeed`, `CustomerCount` dans `Upgrades` ; un ancien `CounterLimit`
reste dans les vieilles sauvegardes, ignore). Le pass Auto
Collect est verifie a chaque arrivee (`UserOwnsGamePassAsync`).

## Configuration

`Config/Upgrades.luau` (CustomerSpeed, CustomerCount), `Config/Gameplay.luau`
(`CounterCupLayersMax`, `MoneyStacks`, `MoneyBillsMax`, `MoneyBillsPerDoubling`, `SaleMaxSpots`, `IncomeWindowSeconds`, `IncomeMinSeconds`, `PadTitles`, `PadActionSeconds`,
`PromptTexts`, `Messages`), `Config/Npcs.luau`, `Config/Shop.luau` (pass AutoCollect : prix 149 A
VALIDER, `passId` 0), `Config/Sounds.luau` (Sale, CashPop, CustomerHappy, CustomerSip ; CashBig
retire le 2026-11-20, CustomersCheer retire le 2026-11-27).

## Tests (Studio)

```
game.ServerStorage.Debug.Call:Invoke("Customer", "Get", "<Nom>")                   -- comptoir, tas, billets
game.ServerStorage.Debug.Call:Invoke("Customer", "Do", "<Nom>", "Place")           -- teleporte sur le pad Drop Juices
game.ServerStorage.Debug.Call:Invoke("Customer", "Do", "<Nom>", "CashPad")         -- teleporte sur le pad Collect Cash
game.ServerStorage.Debug.Call:Invoke("Customer", "Do", "<Nom>", "AddCash", 400)    -- remplir le tas
game.ServerStorage.Debug.Call:Invoke("Customer", "Do", "<Nom>", "Collect")         -- encaisser (sans pad)
game.ServerStorage.Debug.Call:Invoke("Customer", "Do", "<Nom>", "SetAutoCollect", true)
```

## Problemes connus / a faire

- Pass Auto Collect pas cree sur Roblox (prix a valider, phase 3).
- MONEY / HOUR : teste le 2026-11-19 soir (quelques pommes vendues -> "$1.5K") ; a regarder en
  jeu long (valeur stable ?). Le chiffre ne compte que les ventes, pas l'argent encaisse.
- Les clients sont dessines par chaque client : deux joueurs ne voient pas exactement le meme
  client au meme moment (la vente, elle, est la meme pour tous).
- Vraies files (2026-11-27 soir) : logique verifiee en Play (positions, ventes en attente, depart
  au loin, ascenseur aller-retour, charge) mais **pas vue en mouvement** : Studio etait reduit
  (aucune image dessinee). Bulles et eventail vus seulement sur un echantillon fixe en mode Edit.
  A regarder en jeu : naturel des files, lampadaires, telephone (jusqu'a ~30 clients R15 de plus).
- La police emoji se charge a la premiere bulle : la toute premiere peut etre vide un instant.
- Avec beaucoup de ventes (5 places, Faster Customers haut), les arrivees ne suivent pas :
  beaucoup de ventes en "+$" seul (voulu : pas de teleportation, nombre de clients limite).
- Equilibrage : avec 1 place, 1 vente / 1.8 s (2026-11-20 : 2.5 s = exactement l'arbre niveau 1, les
  premiers "Upgrade Tree" ne rapportaient rien) ; More Customers 150 $ ; a revoir en jeu reel.
- Non teste : 2 joueurs, telephone, achat reel du pass.
- Billets vers le HUD + HUD qui compte (2026-11-19) : **pas encore vus en jeu**. A verifier : les
  billets touchent bien le texte du montant (PC et telephone), le "+$X" ne chevauche rien, la
  montee du HUD suit les billets. Si un menu est ouvert pendant l'encaissement, le HUD est cache
  (glisse en bas) : les billets le suivent hors de l'ecran.
