# Systeme : Panneau admin (tests)

**Statut :** en cours (gros panneau teste en playtest Studio PC le 2026-11-20 a 1 joueur ; cible
"autre joueur", Reset All, Rebirth et telephone pas testes)
**Derniere mise a jour :** 2026-11-20 (refonte : cible, champ Value, ~40 boutons)

## Role

Outil de test pour le createur : un bouton "Admin" a droite de l'ecran ouvre un panneau "vite fait"
plein de boutons (argent, faire apparaitre fruits / jus / argent, ameliorations, etages, rebirth,
passes gratuits, Index, teleport, remise a zero). Les actions visent **la cible** choisie en haut
(soi-meme ou un autre joueur du serveur). Invisible pour les autres joueurs, et le serveur refuse
leurs demandes.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/AdminService.luau` | serveur | Qui est admin, attribut `IsAdmin`, table `ACTIONS` du remote `AdminAction` |
| `src/client/Controllers/AdminController.luau` | client | Bouton + panneau (cree en code), liste `SECTIONS` des boutons, seulement si `IsAdmin` |
| `src/server/Services/DataService.luau` | serveur | `ResetOnLeave(player)` : profil neuf ecrit au depart du joueur |
| `src/server/Services/PlayerUpgradeService.luau` | serveur | `AdminSetAll(player, toMax)` : ameliorations du joueur au max / niveau 1 |
| `src/shared/Config/GameConfig.luau` | partage | `AdminUserIds`, `AdminCooldownSeconds` (0.3 s) |

Fonctions de test reutilisees (aussi pour `DebugService` en Studio ; plus de verrou "Studio seulement",
les appelants verifient) : `TreeService.DebugDrop`, `CustomerService.DebugAction`,
`RebirthService.DebugSetMaster`, `ProductionService.DebugAction`, `FloorService.SetFloorCount` /
`DebugGoTo`, `LuckyCashService.DebugGrant`, `RebirthService.ForceRebirth` / `DebugSet`.

## Le panneau

- **Haut :** `<  Nom (you)  >` choisit la cible parmi les joueurs du serveur. **Value N** : nombre
  utilise par les boutons avec "N" (accepte `1000`, `1e6`, `1,000`).
- Boutons **rouges** = dangereux : 2e clic dans les 3 s pour confirmer ("Sure? Click again").
- Le serveur repond toujours par une notification : `Admin: ...`, `Admin (<cible>): ...`, ou en rouge
  `... did nothing` / `... failed`.

| Rubrique | Boutons (action envoyee) |
|---|---|
| Money | +$1K, +$1M, +$1B, +$N, Max Money, Money = 0 |
| Spawn (etage ou est la cible) | Drop 10 Fruits, Drop N Fruits (plafond de fruits au sol), Fill Bins (20 fruits dans les caisses), N Juices (max 50, poses sur le comptoir), Cash Pile +N, Collect Pile, Lucky Cash (comme un achat paye) |
| Upgrades | Max / Reset Floor Upg. (ameliorations de l'etage ou est la cible, puis tour reconstruite), Max / Reset Player Upg. (vitesse, fruits et jus portes), Max Elevator (TowerUpgrades) |
| Floors | +1, -1, 10 Floors, 1 Floor, Set N Floors, Go To Floor N |
| Rebirth | +1 Rebirth (vrai rebirth sans conditions), Rebirth Keep $, Set N Rebirths (la tour ne change pas) |
| Passes (bascule ON/OFF, sans achat) | Instant Sell, Waiter x10 (`SpeedBoost`), Billboard, Thief, Rebirth Master, Auto Collect, VIP, 3x Cash, Drink Master, Greedy, Speed Master (tous des attributs joueur ; boutique ajoutee le 2026-11-21). Le createur du jeu ne recoit plus aucun pass de Roblox (`Lib/GamePass`) : il les active ici |
| Index | Discover All (100 fruits), Reset Index (seul le 1er fruit reste, CLAIM oublies) |
| Player | TP To Target, Bring Target, Respawn, Replay Intro (rejoue la cinematique d'ouverture chez la cible : remet l'attribut `IntroPending` a vrai, IntroDone le remet a faux a la fin ; ne touche pas la sauvegarde), RESET ALL (kick) |

## Fonctionnement

- **Qui est admin :** en Studio tout le monde (tests) ; en jeu publie, le createur du jeu s'il
  appartient a un compte (`game.CreatorId`) et les UserId de `GameConfig.AdminUserIds` :
  PROVADNIKE_ROBLOX (3050299402, le createur, ajoute le 2026-11-23 car le jeu appartient
  maintenant au groupe 444006920 : la regle "createur" ne marche plus) et Himoxil (9061089590,
  ajoute le 2026-11-19). Le serveur pose `IsAdmin` ; l'attribut ne sert qu'a l'affichage.
- **Tout ce qui change etages, ameliorations, rebirths, Index ou argent ECRIT LA SAUVEGARDE** de la
  cible. Les passes bascules sont des attributs (perdus au depart, la vraie possession revient au
  prochain chargement).
- Changer des niveaux a la main reconstruit la tour (`SetFloorCount` au meme nombre) puis ramene la
  cible a son etage, pour que les machines suivent.
- **Reset All :** le serveur marque la cible (`DataService.ResetOnLeave`) puis la kick. Au depart, la
  sauvegarde est remplacee par le modele neuf (nouveau joueur). En Studio, le kick arrete le test.
- Chaque action est journalisee dans la sortie serveur : `[AdminService] admin -> cible : action (valeur)`.

## Remotes

| Nom | Sens | Arguments | Verifications serveur |
|---|---|---|---|
| `AdminAction` | client -> serveur | (action, userIdCible?, valeur?) | admin (recalcule cote serveur), action connue dans `ACTIONS`, delai `AdminCooldownSeconds` (0.3 s), cible = joueur present sur le serveur, valeur = nombre fini puis bornee par action. Action en `pcall` |

## Donnees sauvegardees

Aucun champ ajoute. Reset All remplace tout le profil par le modele (`TEMPLATE` de DataService).

## Problemes connus / a faire

- Pas teste : cible = un autre joueur (Local Server 2 joueurs), Reset All, +1 Rebirth depuis le
  panneau, telephone (panneau limite a 460 x 620 px, defile).
- "TP To Target" sur soi-meme ne fait rien (normal) : choisir un autre joueur.
- (Corrige le 2026-11-21 : Auto Collect est un attribut joueur, son bouton affiche ON / OFF.)
- En Studio, tout joueur est admin (Local Server a 2 joueurs compris) : voulu pour les tests.
- Premier essai du 2026-11-20 : une fois, argent a ~1e15 et 3 etages apres +1 Floor, sans action
  correspondante dans la sortie ; **pas reproduit** au 2e essai (1 -> 2 etages, argent normal).
  A surveiller.
