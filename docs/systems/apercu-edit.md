# Systeme : Apercu de l'usine en mode Edit

**Statut :** en cours (bouton Studio "Factory Preview" en place ; retouches a reporter dans le moule)
**Derniere mise a jour :** 2026-11-27

## Role

Voir toute l'usine dans Studio **en mode Edit**, sans lancer de Play. Sans ca, on ne voit que la
carte : l'usine est un moule (`ServerStorage.BaseTemplate` + `FloorTemplate`) que le jeu assemble
seulement au Play (BaseService, FloorService, TreeService, WorkerService...).

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `tools/studio-plugin/` (`plugin.project.json`, `Main.server.luau`) | plugin Studio local | Bouton "Factory Preview" (onglet Plugins, barre "Usine") : construit / supprime l'apercu. Embarque `preview-factory.luau` |
| `tools/build-map/preview-factory.luau` | Studio (hors Rojo) | Construit `Workspace._Preview` : base + 10 etages "tout achete" + arbres + fruits + PNJ. `REMOVE = true` : supprime l'apercu |
| `src/server/Lib/FloorAssembly.luau` | serveur (reutilise) | Assemble chaque etage (variantes `Only<Tag>`), meme code que FloorService |
| `src/server/Lib/TreeBuilder.luau` | serveur (reutilise) | Arbre de chaque etage au niveau max |
| `src/shared/FruitModels.luau`, `Util/MachineModels.luau`, `Config/*` | partage (reutilise) | Fruits, gobelets, machines, niveaux max |
| `src/shared/Util/WorldLabel.luau`, `Util/NumberFormat.luau` | partage (reutilise) | Textes 3D ("Tree full!", "xN", "n/max", "$") |
| `src/server/Lib/OwnerBadge.luau` | serveur (reutilise) | Logo du proprietaire en haut de la tour |
| `src/client/UI/PackStyle.luau` | client (reutilise) | Style des textes de la liasse Lucky Cash |

## Fonctionnement

- **Le plus simple : le bouton.** Onglet Plugins > "Factory Preview" (mode Edit). 1er clic : construit
  l'apercu (environ 15 s). 2e clic : le supprime. Messages dans la fenetre Sortie (`[Factory Preview]`).
  - Installe / mis a jour par `start-rojo.bat` (`rojo build ... --plugin UsineTools.rbxm` dans le
    dossier Plugins local de Studio). Studio ne recharge pas un plugin deja charge : apres une mise a
    jour, **rouvrir la place** (ou lancer `start-rojo.bat` avant d'ouvrir Studio).
  - Si la place n'a pas ce qu'il faut (`ReplicatedStorage.Shared`, `ServerStorage.BaseTemplate`,
    `Workspace.Map.BaseSlots`...), le bouton ne fait rien et l'ecrit dans la Sortie (pas de blocage).
- Sinon : lancer `tools/build-map/preview-factory.luau` en mode Edit (MCP `execute_luau`, ou coller le
  fichier dans la barre de commande). Il remplace l'ancien apercu s'il existe. Environ 13 500 pieces.
- Ce qui est montre (etat "tout achete", comme un joueur au max) :
  - base posee sur `Map.BaseSlots.BaseSlot1`, salle du Rebirth ouverte (vitre `RebirthGate` retiree) ;
  - 10 etages ouverts assembles par `FloorAssembly.Build` (pas d'etage ferme) ;
  - machines construites ; silhouettes `GhostOnly` et pads verts retires (employes embauches) ;
  - decor du niveau max : regle de LevelLookController (`LookId`, `LookLevel`, `LookMaxLevel`) ;
  - tuiles des panneaux en "MAX" ; pads FREE de l'usine a construire (`Setup`) retires ;
  - arbre de chaque etage au niveau max (`Tree.LevelsPerFloor`) + `MaxGroundFruits` fruits au sol,
    "Tree full!" et "<Nom> Tree Lv N" au-dessus (comme TreeService) ;
  - interface du monde (`Dynamic.PreviewUi`) : fruit + "xN" sur chaque caisse, "n/max" des bols,
    gobelets + "n/max" + "$" de la table a jus, gobelets + "x8" du comptoir, tas de billets + "$" ;
    etage 1 seulement : fleche jaune du tutoriel + anneau + ligne de chevrons vers Collect Cash,
    liasse Lucky Cash ; logo du proprietaire (avatar du compte connecte a Studio) en haut de la tour ;
  - PNJ immobiles (`Dynamic.PreviewNpcs`) : Fruit Picker, Waiter, 4 Blender Operators, 5 clients au
    comptoir. Les pieds sont poses sur le sol (bas des jambes R6), pas via la boite englobante.
- **Sans risque pour le jeu** : `_Preview` a `Archivable = false`. Verifie le 2026-11-27 : il
  n'existe ni cote serveur ni cote client pendant un Play, et il est toujours la apres le Stop
  (`Clone()` renvoie nil). D'apres les regles de Roblox, il n'est pas non plus sauvegarde avec la
  place (pas teste en sauvegardant).
- Modifier l'apercu **ne change pas le jeu** (pas encore de report vers le moule).

## Remotes

Aucun (outil de Studio).

## Donnees sauvegardees

Aucune.

## Configuration

En tete du script : `FLOORS` (10), `SLOT` (1), `REMOVE`. Le reste vient de la Config du jeu.

## Problemes connus / a faire

- **Chaque dev construit son propre apercu** : `_Preview` n'est ni dans Git, ni sauvegarde, ni partage
  par Team Create (verifie le 2026-11-27 : construit dans une fenetre, absent dans une 2e fenetre de la
  meme place). D'ou le bouton.
- Le bouton ne s'allume pas visiblement quand l'apercu existe (`SetActive` peu visible) : a revoir si genant.
- Retouches a la main a reporter dans le moule (FloorTemplate / BaseTemplate) : pas fait. Attention :
  les scripts `tools/build-map/02*` recreent le moule et effaceraient ces retouches.
- Pas montres (passagers ou lies a un joueur) : bulles d'attente des clients, textes "+$" des ventes,
  fruits dans les bols, prompts E, nametags, fleches 2D du HUD.
- Cheveux / chapeaux des PNJ : en Edit, la soudure des accessoires n'est jamais calculee (seulement en
  Play). `snapAccessories` pose chaque poignee sur son point d'accroche du corps AVANT l'ancrage
  (corrige le 2026-11-27 : cheveux a ~30 studs de la tete, par terre). A garder si on touche `buildRig`.
- Copies a garder en phase avec le jeu (les builders sont locaux dans leur module) : PNJ
  (`Lib/NpcRig`), fleche / anneau / ligne (`TutorialController`), liasse (`LuckyCashController`),
  billets (`CustomerService.addBill`). Mieux plus tard : sortir ces builders dans des modules partages.
- Apres des captures MCP : remettre `workspace.CurrentCamera.CameraType = Fixed` (sinon la camera
  de Studio reste bloquee).
- Le Waiter se place sur son pad (comme WorkerService), au niveau du sol de l'etage.
- Remplace l'ancien `preview-tower.luau` pour regarder l'usine (preview-tower reste pour les
  verifications de z-fighting des etages fermes).
