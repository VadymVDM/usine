# Systeme : Carte, bases et attribution

**Statut :** fonctionne (playtest Studio a 1 joueur ; 2 joueurs et telephone a tester)
**Derniere mise a jour :** 2026-11-19

## Role

La carte (route, spawn, decor) et les 6 bases. Chaque joueur recoit une base libre a son arrivee
et apparait dedans ; elle est videe et liberee a son depart. Un 7e joueur recoit un message propre
et se promene ; il recoit la premiere base qui se libere.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `tools/build-map/01-ground-road.luau` | Studio (hors Rojo) | Herbe (3 x 3 dalles), route, trottoirs, lampadaires, place du spawn + fontaine, `Map.BaseSlots`, limites |
| `tools/build-map/02a..02f-*.luau` | Studio (hors Rojo) | `ServerStorage.BaseTemplate`, en 6 morceaux (voir plus bas) |
| `tools/build-map/03-decor.luau` | Studio (hors Rojo) | Foret, arbres ronds, sapins, buissons, fleurs, collines |
| `tools/build-map/04-lighting.luau` | Studio (hors Rojo) | Eclairage (soleil 14 h, contraste, brume) |
| `Workspace.Map` | Studio (.rbxl) | Resultat de 01 et 03 |
| `ServerStorage.BaseTemplate` | Studio (.rbxl) | Resultat de 02a..02f (~1100 objets) |
| `src/server/Services/BaseService.luau` | serveur | Clone le modele dans les 6 emplacements, attribution, apparition, nettoyage, clic sur zone fermee |
| `src/server/Services/NotifyService.luau` | serveur | Envoie un message court au joueur (remote `Notify`) |
| `src/client/Controllers/NotifyController.luau` | client | Affiche le message en haut de l'ecran (style PackStyle), 3.5 s |
| `src/shared/Network/Remotes.luau` | partage | Liste des remotes (voir `architecture.md`) |
| `src/shared/Config/Map.luau` | partage | Nombre de bases, textes (panneau, serveur plein, zones fermees), delai du clic |

## Reconstruire la carte

Studio en mode Edit, coller chaque script dans `execute_luau` (MCP) ou la barre de commande, dans
l'ordre : `01`, `02a`, `02b`, `02c`, `02d`, `02e`, `02f`, `03`, `04`. Chaque script est relancable
(il detruit et recree sa partie). Les scripts 02e/02f chargent une copie fraiche de la Config
(`execute_luau` garde les modules deja charges). Puis `save_place`.

## Fonctionnement

- Carte : zone jouable 680 x 460 (limites invisibles), herbe jusqu'a l'horizon. Route grise de
  500 x 24 le long de l'axe X, place du spawn a l'ouest (seule `SpawnLocation`, invisible).
  Bases espacees de 150, a 30 studs du centre de la route :

```
   [Base 1]      [Base 2]      [Base 3]        (nord, z +30 -> +110)
 SPAWN ======== ROUTE (clients) ==========
   [Base 4]      [Base 5]      [Base 6]        (sud, tournees de 180 degres)
```

- Une base, vue de dessus, route en bas (repere local : origine au bord avant, x 0 = limite
  zone 1 / zones 2-3, +Z vers le fond ; vu de la route, +X est a gauche).
  Zone 1 : x 0 -> 70, z 0 -> 80. Zones 2-3 : x -44 -> 0.

```
 z=80 +----------------------- haie ------------------------+-----------------+
      |      ARBRE (rond fleuri)      [Speed][Luck]   STAFF  | ZONE 2 (rouge)  |
      |                                        [3 pads staff]| "Cocktail Bar"  |
      |  ETAL A FRUITS (30 caisses)         [Juice Limit]    |                 |
      |  plancher = depot         PRESSE  palette de jus     |-----------------|
      |  ============== chemin en dalles ==================  | ZONE 3 (rouge)  |
      |  [Count][Speed][Counter]               |             | "Terrace"       |
      |  $ plateau   ETAL (comptoir + auvent)  |             |                 |
 z=0  +-- cloture --- clients ------------- ARCHE -- cloture -+-----------------+
     x=70                                                   x=0             x=-44
                                ROUTE (clients)
```

- Contenu du modele (noms utilises par le code des lots C a E) :

| Chemin dans la base | Role |
|---|---|
| `Origin` | PrimaryPart (pivot du modele) |
| `Tree.FruitArea` | Carre ou tombent les fruits (20 x 20, invisible), hors tronc (rayon ~3) |
| `Tree.TreeLabelAnchor` | Point du texte "Tree full!" |
| `Production.Bins.Bin1..30` | Fond des caisses (les fruits se posent dessus). 1-10 Common, 11-20 Uncommon, 21-30 Rare |
| `Production.BinsPad` | Zone (invisible) devant l'etal : marcher dessus = deposer les fruits |
| `Production.Press` | Presse (modele, PrimaryPart `Cabinet`) |
| `Production.JuicePile` / `JuiceLabelAnchor` | Zone de la palette de jus / point du texte "n/max" |
| `Counter.CounterPad` | Zone derriere le comptoir : marcher dessus = poser les jus |
| `Counter.CounterTopArea` / `CounterLabelAnchor` | Dessus du comptoir (gobelets) / point du texte "n/max" |
| `Counter.MoneyPile` / `MoneyLabelAnchor` | Plateau a argent / point du montant |
| `Upgrades.Pad_<Id>` | Pad d'amelioration (attribut `UpgradeId`), `Button`, `IconPlate.Card` (BillboardGui : `Title`, `Value`, `Price`, `Robux`) |
| `Markers.SpawnPoint` | Apparition du joueur (tourne vers l'interieur) |
| `Markers.CustomerEntry`, `CustomerSpot1..5` | Arrivee des clients (trottoir) et places devant le comptoir |
| `Entrance.Arch.SignBoard` | Panneau du proprietaire (TextLabels `OwnerText`, 2 faces) |
| `ZoneLocks.Zone2/Zone3` | Bloc rouge `Barrier` (ClickDetector), carte `ZoneName` + `Status` |
| `Dynamic` | Tout ce qui est cree pendant le jeu (fruits, jus, PNJ...) : vide au depart du joueur |

- Attribution : premiere base libre (ordre 1 -> 6). Attribut `OwnerUserId` sur la base (0 = libre),
  attribut `BaseId` sur le joueur (lisible par le client). Panneau `"<DisplayName>'s Juice Stand"`.
- Apparition : a chaque `CharacterAdded`, le personnage est deplace sur `Markers.SpawnPoint`
  (+3 studs) apres que le moteur l'a pose sur la place du spawn.
- Depart : `OnBaseReleased` (les services nettoient), `Dynamic` vide, panneau "Free Stand",
  attributs remis ; la base passe au premier joueur en attente (message "A stand is free...").
- 7e joueur : pas de base, message `ServerFullMessage` (remote `Notify`), il attend.
- Zones 2 et 3 : bloc rouge transparent avec aretes, carte cadenas + nom + "Coming soon",
  apercu du contenu (tables et parasols, bar). Clic -> message "<Zone>: coming soon!"
  (1 message par seconde maximum par joueur).
- API serveur : `BaseService.GetBase(player)`, `GetOwner(base)`, `GetBases()`,
  `OnBaseAssigned(cb(player, base))`, `OnBaseReleased(cb(player, base))`.

## Remotes

| Nom | Sens | Arguments | Verifications |
|---|---|---|---|
| `Notify` | serveur -> client | texte (anglais, depuis la Config) | client : type string, UTF-8 valide, longueur max `MaxNotifyLength` |

Le clic sur une zone fermee passe par un ClickDetector (pas de remote) : joueur verifie, delai
`LockedClickCooldown`, le texte vient de la Config.

## Donnees sauvegardees

Aucune (la base n'est pas sauvegardee ; les niveaux le sont, voir `sauvegarde.md`).

## Configuration

`Config/Map.luau` : `MaxBases`, `OwnerSignFormat`, `FreeSignText`, `ServerFullMessage`,
`StandAssignedMessage`, `LockedZoneText`, `LockedZoneNames`, `LockedZoneMessage`,
`LockedClickCooldown`, `MaxNotifyLength`. Positions des pads : en haut de `02e-base-staff-pads.luau`.
Icone de chaque pad : champ `icon` de `Config/Upgrades.luau`.

## Tests (Studio)

`game.ServerStorage.Debug.Call:Invoke("Base", "SimulateFull", "<Nom>")` : simule un serveur plein
pour ce joueur ; `"EndSimulation"` : revient a la normale ; `"Get"` : nom de sa base.

## Problemes connus / a faire

- Taille du serveur (6) : reglage de l'experience a faire par l'utilisateur.
- Non teste : 2 joueurs (Test > Clients and Servers), telephone, clic sur une zone fermee
  (pas de clic 3D possible via MCP).
- Pas de plaques Robux au sol (decision du 2026-11-19) : le prix Robux est sur la carte du pad ;
  le bouton sera branche en phase 3.
- Cartes des pads : valeurs de depart affichees ; le lot E les met a jour par joueur.
- Nouvelles icones : impossible de les mettre en ligne depuis ce poste (URL http exigee) ;
  les 19 icones deja en ligne sont reutilisees, cadenas dessine en UI.
