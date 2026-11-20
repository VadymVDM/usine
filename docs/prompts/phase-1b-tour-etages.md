# Mission : transformer l'usine en TOUR D'ETAGES (phase 1b), de A a Z

Projet Roblox dans `D:\Usine` (Windows). Rojo sur le port 34850. Roblox Studio est pilote via MCP
(place "usine", placeId 93027930223227). Tu ne connais pas le projet : **lis d'abord, code ensuite**.
Tout est deja decide (conception validee par l'utilisateur les 2026-11-19 et 2026-11-20) : ton
travail est de le construire proprement, par lots, avec des arrets pour que l'utilisateur valide.

L'utilisateur parle francais, decide vite, aime voir des **captures** et des **petits pas**. Le jeu
(tout ce que le joueur voit) est en **anglais**. Doc et commentaires en francais.

---

## 0. Regles de travail (obligatoires)

1. Lire `AGENTS.md` en entier et le suivre (skills `roblox-*`, doc par systeme, journal, Rojo).
   Charger `roblox-collaboration-mode` en premier, puis selon le lot : `roblox-building`
   (Studio, carte), `roblox-architecture`, `roblox-data` (sauvegarde), `roblox-networking` +
   `roblox-security` (remotes, achats), `roblox-gui` (panneau Floors), `roblox-performance`
   (60 etages par serveur), `roblox-studio-mcp` (playtests, captures), `roblox-npc-ai` (clients).
2. **Les fichiers sur disque font reference.** Workspace et ServerStorage ne sont pas dans Rojo :
   la carte et les modeles se construisent avec les scripts `tools/build-map/*.luau` (relancables).
   Toute construction faite dans Studio doit exister dans un script de `tools/build-map/`.
   Astuce deja utilisee : copier les scripts dans un dossier temporaire `src/shared/_BuildMap/`,
   Rojo les envoie comme ModuleScripts, les lancer par `require` d'un clone ; supprimer le dossier
   a la fin. Voir `docs/systems/carte-bases.md` > "Reconstruire la carte".
3. **D'autres sessions Claude travaillent souvent en parallele** sur ce projet. Avant de lancer
   ou arreter un playtest Studio, et avant de modifier un script de `tools/build-map/`, regarder
   `ListAgents` et prevenir les autres (`SendMessage`). Ne pas ecraser le travail d'un autre.
4. Si Studio ne recoit plus le code alors que Rojo dit "Connected" : le serveur Rojo a lache,
   le relancer (`start-rojo.bat` ou `rojo serve`) et faire reconnecter le plugin.
5. Sauvegarde de la place : demander a l'utilisateur avant `save_place`, sinon lui dire de faire
   Ctrl+S dans Studio. Ne **jamais** publier. Ne **pas commiter** sans demande.
6. Les 100 fruits voxel sont dans `ReplicatedStorage.FruitAssets` (hors Rojo) : ne pas y toucher.
7. Selene en fin de lot s'il est installe ; **pas de StyLua** (refuse par l'utilisateur).
8. A chaque lot : doc des systemes touches a jour + entree dans `docs/journal/AAAA-MM-JJ.md` +
   `rojo build default.project.json -o test-build.rbxl` (puis supprimer le fichier). Dire
   honnetement ce qui a ete vu dans Studio et ce qui ne l'a pas ete.
9. Regle du ressenti (`docs/game-design.md`) : simple, satisfaisant, geste clair ; une chose a
   acheter = la **vraie** chose teintee bleu clair avec un contour ; une zone fermee = **vitre rouge
   transparente** (cadenas, nom, prix, touche E) ; animations "gelee" (`src/client/Fx/Jelly.luau`).
10. Le serveur decide de tout (argent, prix, achats, etage du joueur). Chaque remote verifie type,
    valeurs, possession, delai. Prix et vitesses dans `src/shared/Config/`, jamais en dur.

## 1. A lire en premier, dans l'ordre

1. `AGENTS.md`, `docs/README.md`, `docs/roadmap.md` (section "Phase 1b")
2. **`docs/systems/tour-etages.md`** : le plan technique complet. C'est la reference de cette
   mission. Si ce prompt et cette doc different, la doc gagne (elle peut avoir ete precisee depuis).
3. `docs/game-design.md` (sections "La tour d'etages", "Un etage", "L'arbre et les fruits",
   "Rebirth", tableau des decisions en bas)
4. `docs/systems/carte-bases.md` (repere local, coordonnees, contenu du modele, z-fighting, ombres)
5. `docs/systems/chaine-production.md`, `clients.md`, `ameliorations-employes.md`, `fruits.md`,
   `sauvegarde.md`, `argent.md`, `interface.md`, `admin.md`, `docs/architecture.md`, `docs/style.md`
6. Les deux derniers journaux (`docs/journal/`)
7. Le code : `src/server/Services/*.luau` (surtout `BaseService`, `TreeService`,
   `ProductionService`, `CustomerService`, `WorkerService`, `UpgradeService`, `DataService`),
   `src/shared/Config/*.luau` (`Map`, `Upgrades`, `Fruits`, `Tree`, `Gameplay`), les controleurs
   client qui lisent la base (`CustomerController`, `CashController`, `TreeFxController`,
   `FruitFxController`, `MachineFxController`, `PadController`, `BuyController`...)
8. Les scripts `tools/build-map/02a` a `02g`, `05-shadows`, `check-zfighting`

## 2. Ce qui est decide (resume ; detail dans `tour-etages.md`)

**Le jeu.** Chaque base devient une tour de **10 etages**. **1 etage = 1 rarete = ses 10 fruits**
(etage 1 Common, etage 2 Uncommon, etage 3 Rare...). Jamais de melange : 1 fruit = 1 jus pur.
Chaque etage est **autonome** (arbre, etagere, tapis, mixeurs, table a jus, comptoir, employes,
panneaux d'ameliorations). Le joueur joue a la main sur son dernier etage ; les etages du dessous
tournent avec les employes. Il achete l'etage suivant pour avoir des fruits plus chers. Rebirth
uniquement quand l'etage 10 est achete (le rebirth lui-meme = phase 4, pas cette mission).

**Un seul modele d'etage.** `ServerStorage.FloorTemplate`, copie tous les **36 studs** (etage n :
sol a `y = 36 * (n - 1)` dans le repere de la base). Le code ne connait que "un etage" : il y
cherche toujours les memes noms (`Tree`, `Production`, `Counter`, `Machines`, `Boards`, `Markers`,
`Looks`, `Dynamic`). Les differences entre etages passent par des **dossiers de variantes** dans le
modele, retires au clonage : par exemple `OnlyGround` (porte d'entree, comptoir sur la rue),
`OnlyUpper` (balcon, porte vers le balcon), `LaneA` / `LaneB` (escalier et trou de dalle). Ajouter
un etage 11 plus tard = une ligne de Config, zero code.

**Repere** (comme `carte-bases.md`) : origine au bord avant de la base, +Z vers le fond, **vu de la
route +X est a gauche**. Salle : x 1 -> 109, z 15 -> 135, murs de 36 de haut.

**L'escalier** (idee de l'utilisateur : "commence au milieu, monte vers le mur") :
- Zone **STAIRS** sur chaque etage : x 60 -> 109, z 50 -> 86 (zone vide aujourd'hui, verifiee). La
  zone SALES est raccourcie de z 54 a z 50 (rien dedans au-dela de z 34). Sol de zone + panneau
  suspendu "STAIRS" comme les autres zones.
- 2 voies de 8 de large : **voie A z 57-65**, **voie B z 70-78** ; allee sud z 50-57, garde-corps
  entre les voies z 65-70, allee nord z 78-86.
- L'escalier de l'etage n vers n+1 est sur la **voie A si n est impair, B si n est pair**. Il part
  du milieu (x 64, sol de l'etage) et monte a 45 degres jusqu'a x 100 (+36), puis **palier** x 100
  -> 108 contre le mur de droite (le palier appartient a l'etage du dessus).
- 24 marches de 1.5 x 1.5, **visuelles et sans collision** ; la collision est une **rampe
  invisible** (WedgePart) sous chaque volee : le personnage monte sans buter.
- **Trou** dans la dalle de l'etage n+1 au-dessus de l'escalier : x 64 -> 100 sur sa voie (le
  palier reste plein). Garde-corps tout autour du trou et le long des voies : impossible de tomber.
- Retirer la fenetre du mur de droite en z 56-70 (cachee par le palier). Les panneaux suspendus
  SALES (z 50) et ORCHARD (z 86) restent hors des voies (verifier).
- L'arbre au stade 5 monte a ~34.3 : la dalle du dessus commence a 35. **Ne jamais depasser 34.5.**

**Etage suivant (ferme) et achat.**
- On ne construit que les **etages achetes + le suivant ferme**. Jamais une tour vide de 10.
- Etage ferme : vu de dehors, la **coque** de l'etage (murs, dalle) teintee bleu clair + contour
  (Highlight), sans l'interieur. En haut de l'escalier, sur le palier : **vitre rouge** transparente
  avec cadenas, "FLOOR 2 - UNCOMMON", prix. **E** (ProximityPrompt) pour acheter.
- Achat : le serveur verifie (proprietaire de la base, c'est bien l'etage suivant, argent, delai),
  depense via `MoneyService`, puis l'etage **se construit piece par piece** (reutiliser l'effet de
  construction des machines, `MachineFxController`), "NEW FLOOR!" + son, et le nouvel etage ferme
  apparait au-dessus.
- Prix : environ **10 a 15 minutes de gains** de la tour quand l'etage d'en dessous est bien
  ameliore. Un jus de l'etage n+1 vaut environ x5 celui de l'etage n (`Fruits.luau`). Proposer une
  table de prix dans `Config/Floors.luau`, marquee "A VALIDER" en commentaire.

**Argent : un seul tas, au rez-de-chaussee.**
- Les ventes de **tous** les etages s'ajoutent au tas de la table a argent de l'etage 1. Un seul pad
  **Collect Cash** (en bas) ramasse tout. Le pad Robux Auto Collect ramasse ce tas (rien a changer).
- Les etages 2+ n'ont **pas** de table a argent, de pad Collect Cash ni de pad Auto Collect (ils
  sont dans `OnlyGround`). Leur comptoir montre ce qu'il gagne ("+$120" qui s'envole, panneau
  MONEY / HOUR de l'etage).
- Pas de tube a billets dans cette mission (idee non decidee).

**Clients.**
- Etage 1 : comme aujourd'hui (la rue, le comptoir dans la fenetre de la facade).
- Etages 2+ : le comptoir est au meme endroit et donne sur un **balcon** (z 0 -> 14, au-dessus de la
  cour, garde-corps). Les clients y arrivent par un **ascenseur vitre exterieur** dans le coin
  avant-ouest de la tour (cote annexe, a placer pour qu'il touche la terrasse en bas et chaque
  balcon en haut ; proposer l'emplacement exact a l'arret du lot 1).
- Les clients restent **visuels** (le serveur decide des ventes avec son minuteur, comme
  aujourd'hui) et ne sont dessines que sur l'etage ou se trouve le proprietaire (plus la rue).

**Annexe ouest (x -46 -> 0, rez-de-chaussee seulement).**
- **Terrasse -> hall de l'ascenseur.** Pas d'achat a part : elle **s'ouvre toute seule a l'achat de
  l'etage 2**. Avant : barriere fermee + panneau "Opens with Floor 2", la cage vide de l'ascenseur
  est deja visible. A l'achat de l'etage 2, dans la meme animation : etage construit, ascenseur
  qui apparait, barriere qui s'ouvre. Ensuite, une partie des clients de la rue fait la queue sur la
  terrasse et monte dans la cabine.
- Panneau d'ameliorations **"Elevator"** sur la terrasse (tuiles comme les autres panneaux,
  argent du jeu) : **Elevator Speed** et **Bigger Cabin**. Effet serveur : bonus de vitesse de vente
  pour **tous les etages 2+**. Visuel : la cabine monte plus vite / transporte plus de clients.
  Niveaux **globaux** (pas par etage), remis a 0 au rebirth. Prix dans `Config/Upgrades.luau`.
- **Bar a cocktails -> salle du Rebirth.** Garde sa vitre rouge, texte **"Reach Floor 10"** ;
  dedans, une grande machine / statue doree qui brille, visible des la premiere minute. A l'etage
  10 achete, la vitre s'ouvre ; E sur la machine -> message "Rebirth: coming soon!" (le vrai
  rebirth est en phase 4). Supprimer le contenu "cocktail" de la salle.
- Supprimer l'ancien systeme `ZoneLocks` Zone2/Zone3 et `Map.LockedZone*` (Cocktail Bar 5K,
  Terrace 50K), remplaces par ce qui precede.

**Deplacements du joueur.**
- Il apparait (connexion, mort) sur son **etage le plus haut** (`Markers.SpawnPoint` de l'etage).
- Sur chaque palier et a l'entree du rez-de-chaussee : un panneau **"Floors"** (E) qui ouvre une
  petite fenetre avec ses etages achetes ; clic = teleport (remote verifie). L'escalier sert la
  premiere fois et pour les petits trajets.

**Lumiere.** Chaque etage a un plafond (la dalle du dessus) : les lampes neon existantes eclairent.
Seul le dernier etage achete garde le ciel ouvert (et son puits de lumiere). Verifier que les
etages du bas ne sont pas trop sombres.

**Lag (tres important).** 6 joueurs x 10 etages = 60 etages par serveur.
- Le serveur calcule chaque etage **avec des nombres** (fruits/s, jus, ventes, argent) a partir de
  ses ameliorations et employes. La meme formule servira aux gains hors ligne (exposer une fonction
  du type `GetIncomePerSecond(player)`).
- Les choses visibles (fruits qui tombent, employes R6, clients, gobelets, billets) ne sont creees
  **que sur l'etage ou est le proprietaire**. Quand il change d'etage : on retire de l'ancien, on
  cree sur le nouveau, sans perte (les compteurs restent cote serveur).
- Un etage **sans employes** ne produit rien quand le joueur n'y est pas (pousse a embaucher).
  Definir clairement dans la doc ce qu'est un etage "automatise" et comment le debit est calcule
  (le plus lent de : arbre, mixeurs, clients).
- Pieces : la base actuelle fait **1469 pieces**. Viser **~800 par etage** (etagere a 10 caisses au
  lieu de 30, decor simplifie). StreamingEnabled est **actif** : cote client, ne jamais supposer
  qu'une piece d'un autre etage existe (WaitForChild avec delai, gerer l'absence).

**Sauvegarde (risque eleve, accord obligatoire avant de coder).** Proposition de depart :
```
FloorsOwned = 1
Floors = { [1] = { Upgrades = { Tree = 1, ... } }, [2] = { ... } }   -- par etage
TowerUpgrades = { ElevatorSpeed = 0, ElevatorCabin = 0 }               -- global
```
Restent globaux : Money, Rebirths, DiscoveredFruits (Index), passes / boosts, LastLogout...
Migration (nouvelle `SchemaVersion`, la boucle de `DataService` existe) : anciens `Upgrades` ->
`Floors[1].Upgrades`, niveau `Tree` borne a 10 (l'arbre d'un etage n'a que 10 fruits),
`FloorsOwned = 1`. Le jeu n'est pas lance : ce sont des donnees de test, mais la migration doit
quand meme etre propre (aucune erreur, valeurs par defaut pour tout champ absent).

**Arbre par etage.** L'arbre de l'etage n ne fait tomber que les 10 fruits de la rarete n. Niveau
`Tree` de 1 a 10 dans l'etage (1 = premier fruit de la rarete, chaque niveau ajoute le suivant).
L'ancienne regle "le rebirth ouvre une rarete" (`Fruits.StartRarities`, `Fruits.MaxLuck(rebirths)`)
est **remplacee** : ce sont les etages qui ouvrent les raretes. L'Index affiche "Floor N to unlock"
au lieu de "Rebirth to unlock".

**Admin / debug.** Ajouter au panneau admin (`admin.md`) et a `DebugService` : donner N etages,
aller a l'etage N, remettre la tour a 1 etage. Indispensable pour tester 10 etages.

## 3. Ordre de travail (un lot = un resultat verifiable)

### Lot 0 : lire et faire l'inventaire (pas de modification)
- Lire tout le point 1. Lister **tout le code qui suppose un seul etage par base** (recherche :
  `GetBase`, `base.Production`, `base.Counter`, `base.Tree`, `Markers`, `ZoneLocks`, `Rooms`,
  `LockedZone`, `StartRarities`, `MaxLuck`...), cote serveur et client.
- Ecrire le plan des fichiers a creer / modifier dans `tour-etages.md` (section Fichiers) si besoin.

### Lot 1 : le modele d'etage et l'escalier dans Studio (scripts `tools/build-map/`)
- Creer `ServerStorage.FloorTemplate` a partir de la base actuelle : la grande salle et tout son
  contenu par etage, zone STAIRS (voies A/B, rampes invisibles, marches, garde-corps, trous de
  dalle par variante, palier, vitre rouge d'achat, panneau Floors), zone SALES raccourcie, balcon
  (`OnlyUpper`), etagere a 10 caisses, dalle de plafond. Ce qui n'existe qu'en bas (cour, entree,
  annexe, table a argent, pads Collect Cash / Auto Collect) reste dans le modele de base.
- Annexe : terrasse fermee "Opens with Floor 2" + cage d'ascenseur vide ; salle du Rebirth (vitre
  rouge "Reach Floor 10", machine doree). Supprimer les salles Cocktail Bar / Terrace actuelles.
- Garder les noms d'objets que le code utilise (tableau de `carte-bases.md`), ou noter chaque
  renommage pour le lot 3.
- Pour tester : poser a la main dans le Workspace une base avec **2 etages** (copie temporaire,
  retiree a la fin, voir la regle `_PreviewBase` dans `carte-bases.md`).
- Verifier dans Studio : **check-zfighting = 0**, `05-shadows` relance, nombre de pieces par etage,
  et en playtest avec un personnage : monter l'escalier sans buter ni sauter, la tete ne touche
  pas la dalle, impossible de tomber dans le trou, camera correcte dans la cage d'escalier, arbre
  stade 5 sous le plafond, lumiere des etages du bas.
- **ARRET 1** : envoyer des captures (dehors : la tour a 2 etages + l'etage ferme bleu ; dedans :
  l'escalier vu du bas et du palier, la vitre rouge, la terrasse fermee, la salle du Rebirth,
  le balcon) et attendre la validation visuelle de l'utilisateur. Corriger selon ses retours.

### Lot 2 : la sauvegarde par etage (skill `roblox-data`)
- Presenter le schema exact, la migration et les valeurs par defaut a l'utilisateur.
- **ARRET 2** : attendre son accord explicite, puis coder (`DataService`, `GameConfig.SchemaVersion`,
  `sauvegarde.md`). Tester : profil neuf, ancien profil migre, sortie / retour (mode Mock si
  l'acces API de Studio est coupe ; le dire).

### Lot 3 : les services travaillent par etage
- `Config/Floors.luau` (hauteur 36, `MaxFloors = 10`, par etage : rarete, prix, couleur
  d'accent, titre affiche ; positions des voies).
- `TreeService`, `ProductionService`, `CustomerService`, `WorkerService`, `UpgradeService` et les
  controleurs client recoivent un **etage** au lieu d'une base. Le serveur retrouve l'etage d'un
  objet touche par son ancetre (attribut `FloorIndex` sur le modele d'etage, `OwnerUserId` sur la
  base) ; ne jamais croire un numero d'etage envoye par le client sauf pour le teleport (verifie).
- Ameliorations et employes **par etage** (`Floors[n].Upgrades`), memes identifiants qu'aujourd'hui.
- Arbre par etage (10 fruits de la rarete de l'etage), Index "Floor N to unlock".
- Ventes de tous les etages -> tas de l'etage 1.

### Lot 4 : `FloorService` (construction, achat, deplacements)
- Construire pour une base les etages achetes + le suivant ferme ; les retirer au depart du joueur.
- Achat par la vitre rouge (verifications serveur), animation de construction, "NEW FLOOR!",
  ouverture de la terrasse et apparition de l'ascenseur a l'etage 2, vitre "Reach Floor 10" qui
  s'ouvre a l'etage 10.
- Etage actif du joueur (ou il se trouve), apparition sur l'etage le plus haut, panneau Floors +
  remote `FloorTeleport` (entier, 1..FloorsOwned, proprietaire, delai), dans `Remotes.luau`.
- Commandes admin / debug du point 2.
- **ARRET 3** : l'utilisateur teste en jeu (acheter l'etage 2, monter, redescendre encaisser,
  teleport). Corriger selon ses retours.

### Lot 5 : production en nombres + clients des etages du haut + ascenseur
- Debit calcule des etages ou le joueur n'est pas (et formule exposee pour les gains hors ligne).
- Visuels seulement sur l'etage actif ; transition propre quand le joueur change d'etage.
- Clients des etages 2+ : queue sur la terrasse, cabine vitree qui monte, sortie sur le balcon,
  achat, retour. Repartition rue / terrasse. Panneau Elevator (Speed, Bigger Cabin) branche.

### Lot 6 : tests, performance, relecture
- Avec les commandes admin : 1 joueur a 10 etages, puis simuler 6 bases a 10 etages. Mesurer :
  pieces, memoire, battement serveur, FPS client (PC + simulateur telephone). Noter les chiffres.
- 2 joueurs (si possible dans Studio : Test > Clients and Servers), telephone (simulateur).
- Relecture `roblox-security` (achat d'etage, teleport, panneau Elevator, ventes) et
  `roblox-luau-patterns` (connexions deconnectees au changement d'etage et au depart du joueur).
- Mettre a jour toutes les docs touchees : `tour-etages.md` (statut, fichiers, ce qui est fait),
  `carte-bases.md`, `chaine-production.md`, `clients.md`, `ameliorations-employes.md`,
  `fruits.md`, `sauvegarde.md`, `interface.md`, `admin.md`, `architecture.md`, `README.md`,
  `roadmap.md` (cocher la phase 1b). `first-session.md` : signaler ce qui est a reecrire.

## 4. Fin de mission (ce que tu dois rendre)

- La tour fonctionne : etage 1 -> 10 achetables, escalier, terrasse + ascenseur, salle du Rebirth
  fermee, un seul tas d'argent en bas, panneau Floors, production des etages automatises.
- Scripts `tools/build-map/` a jour et relancables, aucun z-fighting, docs et journal a jour,
  `rojo build` OK.
- Un compte rendu court et honnete pour l'utilisateur : ce qui est vu et teste dans Studio (avec
  captures), ce qui ne l'est pas (vraie sauvegarde, vrai telephone, 6 vrais joueurs), les chiffres
  de performance, et les points "A VALIDER" restants (prix des etages, prix Elevator).
- Ne rien publier, ne rien commiter sans demande.
