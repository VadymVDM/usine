# Systeme : Sauvegarde des joueurs

**Statut :** fonctionne (quitter / revenir teste en Studio avec le vrai DataStore le 2026-11-19 ; 2 serveurs non testes)
**Derniere mise a jour :** 2026-11-22 (SchemaVersion 7 : `TutorialStep`, `FreeSpeedUsed`)

## Role

Charge la sauvegarde du joueur a son arrivee, la garde en memoire pendant la partie et l'ecrit
dans le DataStore (sauvegarde automatique, depart du joueur, fermeture du serveur). Un seul
serveur a la fois peut modifier la sauvegarde d'un joueur (verrou de session).

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/DataService.luau` | serveur | Chargement, verrou, migrations, depart, BindToClose |
| `src/server/Vendor/ProfileStore.luau` | serveur | Librairie ProfileStore (si validee) + `NOTICE.md` (source, version, licence) |
| `src/shared/Config/GameConfig.luau` | partage | `DataStoreName`, `SchemaVersion` |

## Fonctionnement

- Choix propose : **ProfileStore** (MadStudioRoblox). Raison : verrou de session, sauvegarde
  automatique, BindToClose et `UpdateAsync` deja faits et eprouves ; ecrire tout ca a la main est
  la premiere source de pertes de donnees. Sans accord : DataStore a la main (UpdateAsync,
  3 tentatives, verrou maison), plus long et plus risque.
- Arrivee : `StartSessionAsync("player_<UserId>")` avec delai maximum 60 s (`LoadTimeoutSeconds`).
  Ce delai doit depasser `SESSION_STEAL` de ProfileStore (40 s) : un verrou abandonne (serveur
  plante, playtest coupe) n'est repris qu'apres 40 s. Avec 30 s (avant le 2026-11-19 soir), le joueur
  etait renvoye ("Your data could not be loaded") a chaque essai.
  Echec ou erreur -> le joueur est renvoye avec un message propre ("Your data could not be loaded.
  Please rejoin."). Jamais de profil vide a la place d'un profil qui n'a pas pu etre lu.
- Sauvegarde illisible (champ du mauvais type qui fait planter la preparation) : la session est
  fermee sans jouer avec, le joueur est renvoye. Les valeurs simplement impossibles (argent
  negatif, niveau hors limites, table manquante) sont corrigees avec un avertissement.
- Session terminee ailleurs (fermeture du serveur, autre serveur) : les services sont prevenus
  (`OnPlayerRemoving`) et le joueur est renvoye ("Your data session ended."), sauf a la fermeture.
- Puis `Reconcile()` (ajoute les champs absents) et migration selon `SchemaVersion`.
- Premiere visite = profil neuf (premier chargement). Sert a poser 3 pommes au sol.
- Depart : `EndSession()`. Fermeture du serveur : ProfileStore termine les sessions ouvertes.
- DataStore indisponible (Studio sans "Enable Studio Access to API Services") : `DataService`
  teste lui-meme l'acces (ProfileStore ne reconnait pas l'erreur 502 "Studio access to APIs is not
  allowed") et utilise `ProfileStore.Mock` : avertissement `[DataService] DataStore indisponible...`
  dans la console, jeu jouable, rien n'est ecrit. Chaque session compte alors comme une premiere
  visite.
- Ordre de demarrage non garanti : les autres services s'abonnent avec
  `DataService.OnPlayerLoaded(fn)` (appele aussi pour les joueurs deja charges) et
  `DataService.OnPlayerRemoving(fn)` (avant la derniere sauvegarde).
- Une seule porte : les autres services lisent/modifient les donnees par `DataService`, et
  chaque champ a un seul proprietaire (Money -> MoneyService, Floors[n].Upgrades -> UpgradeService,
  DiscoveredFruits -> TreeService, ClaimedFruits -> IndexService, PlayerUpgrades -> PlayerUpgradeService, TowerUpgrades -> panneau Elevator (lot 5)).
- Lire les niveaux d'un etage : `DataService.FloorUpgrades(data, n)` (nil si l'etage n'est pas
  achete), nombre d'etages : `DataService.FloorsOwned(data)`. Seul FloorService allonge la liste
  `Floors` (achat d'un etage ; outils de test `SetFloorCount`). `GroundUpgrades` (transitoire) retire
  au lot 3 : chaque service lit l'etage de l'objet touche.

## Remotes

Aucun.

## Donnees sauvegardees (SchemaVersion 5, gains hors ligne, 2026-11-20)

| Champ | Type | Defaut | Proprietaire |
|---|---|---|---|
| `SchemaVersion` | number | 5 | DataService |
| `Money` | number (entier >= 0) | 0 (`GameConfig.StartingMoney`) | MoneyService |
| `Rebirths` | number | 0 | RebirthService (`systems/rebirth.md`) ; entier 0..`GameConfig.MaxRebirths` |
| `Floors` | liste { { Upgrades = { [UpgradeId]: niveau } } }, 1 a `Floors.MaxFloors` (10) cases, sans trou | `{ { Upgrades = defaut } }` : 1 etage. Defaut d'un etage = `Upgrades.DefaultLevels()` (Tree 1 (max 10 : les 10 fruits de la rarete de l'etage), ConveyorSpeed 1, JuiceLimit 1, CustomerSpeed 1, CustomerCount 1, Collector 0, Server 0, Blender1 = 1, Blender2..4 = 0, Operator1..4 = 0). Nombre d'etages achetes = `#Floors` (pas de champ FloorsOwned : une seule source). Un etage achete demarre avec ce defaut. | UpgradeService (niveaux), FloorService (ajout d'un etage, lot 4) |
| `TowerUpgrades` | { ElevatorSpeed, ElevatorCabin : entier 0..`Floors.TowerUpgradeMaxLevel` } | 0 et 0 (`Floors.TowerUpgradeDefaults`) | panneau Elevator (lot 5) ; remis a 0 au rebirth |
| `DiscoveredFruits` | { [FruitId]: true } | { Apple = true } | TreeService |
| `ClaimedFruits` | { [FruitId]: true } | {} | IndexService (recompenses CLAIM de l'Index prises ; seulement des fruits decouverts, 2026-11-20) |
| `PlayerUpgrades` | { WalkSpeed, FruitCarry, JuiceCarry: number } | tous a 1 | PlayerUpgradeService (menu Upgrade ; entiers 1..maxLevel, cles connues seulement ; ajoute le 2026-11-20 sans migration, pose par Reconcile ; garde au rebirth) |
| `LastLogout` | number (os.time, entier, jamais dans le futur) | 0 | DataService : mis a `os.time()` a CHAQUE sauvegarde (`OnSave`, depuis le 2026-11-20) et a la derniere ; la valeur lue au chargement est gardee (`DataService.GetPreviousLogout`) pour les gains hors ligne |
| `TutorialStep` | number | 0 | etape du tutoriel (TutorialService, SchemaVersion 7 ; anciens profils : 10 = fini ; voir `tutoriel.md`) |
| `FreeSpeedUsed` | boolean | false | 1re vitesse gratuite deja prise (PlayerUpgradeService, SchemaVersion 7 ; anciens profils : vrai) |
| `IntroSeen` | boolean | false | cinematique d'ouverture deja vue (IntroService, 2026-11-22 ; valeur abimee -> true ; voir `cinematique.md`) |
| `Settings` | { Music, Effects : number 0..1 ; LowQuality : boolean } | Music 1, Effects 1, LowQuality false (`GameConfig.DefaultSettings`) | SettingsService (ajoute le 2026-11-19 soir ; `Reconcile` l'ajoute aux anciens profils, `sanitize` ne garde que ces 3 cles, du type de la defaut). 2026-11-23 : Music / Effects deviennent des volumes ; ancien `true` -> 1, ancien `false` -> 0 |
| `JuicesSold` | number (entier >= 0) | 0 | LeaderboardService (jus vendus depuis toujours, ajoute le 2026-11-20, `classements.md`) |
| `TimePlayed` | number (secondes, entier >= 0 au chargement) | 0 | LeaderboardService (temps de jeu, ajoute le 2026-11-20) |
| `KeptTrees` | liste d'entiers (niveau Tree le plus haut de chaque etage avant un rebirth), sans trou, 0 a `MaxFloors` cases, bornes entre depart et max de l'arbre | `{}` | RebirthService (pass Rebirth Master ; ajoute le 2026-11-20 sans migration) |
| `OfflineReward` | { Amount (entier 0..MaxMoney), Seconds, Claimed, Doubled } | { 0, 0, true, true } (rien a prendre) | OfflineService (`systems/gains-hors-ligne.md`) ; ajoute le 2026-11-20 (SchemaVersion 5) |
| `PurchaseIds` | liste de chaines : les 50 derniers achats Robux appliques (le plus recent en premier) | `{}` | `DataService.GrantPurchaseOnce` (ajoute le 2026-11-20 sans migration ; premier utilisateur : "Rebirth & keep your cash") |
| `Boosts` | `{ [stat]: { ["x<mult>"]: secondes } }` : temps restant des boosts Robux (Money, Luck, Speed) | `{}` | `RobuxShopService` (ajoute le 2026-11-20 sans migration ; voir `achats-robux.md`) |
| `Setup` | entier 0..4 : pads FREE de l'etage 1 deja faits (usine a construire) ; abime -> 4 ; plus d'un etage ou rebirth -> 4 | 0 (profil neuf) ; migration 5 -> 6 : 4 pour les anciens profils | `SetupService` (`systems/usine-a-construire.md`, 2026-11-21) |
| `BoughtOffers` | `{ [cle d'offre]: true }` : offres uniques (`oneTime`) deja achetees, ex. `OfferStarter` ; sanitize ne garde que des cles d'offres connues | `{}` | `RobuxShopService` (ajoute le 2026-11-21 sans migration) |

Le niveau de l'arbre (`Tree`) est dans les `Upgrades` de chaque etage (meme mecanisme d'achat).
Rebirth (2026-11-20, `systems/rebirth.md`) : `Money` a 0 (sauf achat "keep cash"), `Rebirths` + 1,
`Floors = { { Upgrades = defaut } }` (`FloorService.ResetForRebirth`), `TowerUpgrades` a 0,
`KeptTrees` mis a jour. Gardes : Index, `PlayerUpgrades`, `Settings`, statistiques.

Achats Robux (Developer Products) : `DataService.GrantPurchaseOnce(player, purchaseId, apply)`
applique `apply(data)` une seule fois par PurchaseId (note dans `PurchaseIds`), force une
sauvegarde et attend qu'elle soit ecrite (`LastSavedData` contient le PurchaseId, via
`OnAfterSave`) avant de renvoyer true (methode de l'exemple ProfileStore). En Studio sans acces API
(Mock) : true tout de suite.

Verification au chargement (`sanitize`) : `Floors` qui n'est pas une table -> 1 etage par defaut ;
on lit les cases 1, 2, 3... et on s'arrete a la premiere qui n'est pas une table (pas d'etage apres
un trou) ou a `MaxFloors` ; chaque niveau inconnu / pas un nombre -> valeur de depart, borne entre
depart et maximum ; au moins l'etage 1. `TowerUpgrades` : seulement les cles connues, entiers
0..max. Le modele est copie en profondeur (`deepCopy`) a la remise a zero.

Migrations (`MIGRATIONS` de DataService) :
- 1 -> 2 (2026-11-19) : ancien employe `Presser` -> `Operator1`.
- 2 -> 3 (2026-11-19 soir, pad de l'arbre + mixeurs a 5 niveaux) : `Tree` = max(1, ancien `TreeLuck`,
  ancien `TreeSpeed`) (on garde les fruits deja possibles) ; `BowlSize` (1-4) -> niveau de chaque
  mixeur possede (1 / 2 / 3, et 4 -> 5 : meme taille de bol, 20) ; `TreeSpeed`, `TreeLuck` et
  `BowlSize` retires. Teste en Studio sur le profil de l'utilisateur (vieilles cles parties, niveaux
  corrects).
- 3 -> 4 (2026-11-20, tour d'etages) : `Upgrades` -> `Floors[1].Upgrades` (puis `sanitize` borne
  Tree a 10), champ `Upgrades` retire, `TowerUpgrades` a 0 (ajoute par Reconcile). Reconcile passe
  AVANT la migration : il a deja pose un `Floors` par defaut, que la migration remplace.
- 4 -> 5 (2026-11-20, gains hors ligne) : champ `OfflineReward` (pose par Reconcile : "rien a
  prendre"), rien a convertir. `LastLogout` existait deja. Teste en Studio (vrai DataStore) : offre
  pas reclamee au depart -> argent donne et relu au retour.

Pas sauvegardes : fruits au sol, fruits portes, jus, argent pas encore ramasse, contenu des bols
des mixeurs (et mixages en cours).

Plus tard (pas en phase 1) : zones achetees, machines a cocktails et recettes (phase 4), boosts en
cours avec le temps restant, passes recus en cadeau (phase 3).

Migration : chaque nouveau champ a une valeur par defaut dans le modele ; une fonction par
passage de version (`1 -> 2`...) si un champ change de forme (`MIGRATIONS` de DataService,
apres `Reconcile`, avant `sanitize`).

- **1 -> 2 (2026-11-19, refonte du mixeur)** : l'ancien employe `Presser` (Blender Operator qui
  portait les fruits au tapis, 150 $) devient `Operator1` (operateur du mixeur 1, meme prix) ; la
  cle `Presser` est retiree. Choix : convertir plutot que rembourser (rien n'est perdu, pas
  d'argent cree). Teste en Studio sur le profil de l'utilisateur (Presser 1 -> Operator1 1).

## Autres DataStores (hors profil du joueur)

- `DebugBackups` (Studio seulement, cle `player_<UserId>`) : copie JSON du profil faite par
  `Debug Data Backup` avant un test "profil neuf" ; remise au depart par `Data RestoreBackup`
  (`DataService.ReplaceOnLeave`).

- `Donations_v1` (cle `u<UserId>`) et l'OrderedDataStore `DonationRanking_v1` : dons en Robux,
  ecrits seulement par `DonationService` (UpdateAsync, voir `systems/dons.md`). Pas touches par le
  rebirth ni par "Reset All".

## Configuration

- `GameConfig.DataStoreName = "PlayerData_v1"` : les tests en Studio (avec l'acces API) ecrivent
  dans le vrai DataStore de l'experience. Changer le nom (ex. `PlayerData_v2`) avant le lancement
  pour repartir a zero.

## Problemes connus / a faire

- 2026-11-20 (SchemaVersion 4) : teste en Studio avec le vrai DataStore : profil de l'utilisateur
  migre (37 $, Tree 3, 3 fruits gardes ; lu brut apres la sortie : `SchemaVersion` 4, `Floors` en
  liste, plus de `Upgrades`), rechargement OK, ecriture d'un niveau (Collector 1 puis 0) OK.
  `migrate` + `sanitize` testes hors DataStore (code charge dans Studio) : profil neuf, v3 Tree 27
  (-> 10), v1 Presser/BowlSize, v4 abime, Floors pas une table, 12 etages (-> 10) : aucun plantage.

- 2026-11-19 (lot C) : acces API actif dans Studio "usine". Teste : stop puis play -> argent (123),
  `TreeLuck` 2 et Orange decouverte retrouves, `FirstVisit` faux (pas de pommes offertes).
  Le profil de test a ensuite ete remis a 0 $ et niveaux 1 (Orange reste decouverte).
- En mode Mock, ProfileStore ignore le delai `Cancel` (sans effet : le Mock ne fait pas attendre).
- Pas encore teste : deux serveurs en meme temps (verrou de session).
- Revue adversariale du lot A faite (2026-11-19) : erreurs de chargement protegees, nettoyage sur
  fin de session externe, plafond d'argent, `math.clamp` retire.
