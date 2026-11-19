# Systeme : Pads d'ameliorations et employes

**Statut :** en cours (pads et cartes poses au lot B ; achat au lot E)
**Derniere mise a jour :** 2026-11-19

## Role

Les pads places dans la base permettent d'acheter les ameliorations et les employes avec
l'argent du jeu. Les employes automatisent la chaine.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/UpgradeService.luau` | serveur | Pads d'achat, verification, niveaux, cartes |
| `src/server/Services/EmployeeService.luau` | serveur | Ramasseur, Serveur (deplacements + travail) |
| `src/shared/Config/Upgrades.luau` | partage | Effets, prix argent, prix Robux (A VALIDER), niveaux max |

## Fonctionnement

- **Decision du 2026-11-19 (lot B, apres avis de l'utilisateur : "trop de boutons") :** plus de
  tableaux muraux ni de plaques Robux au sol. Chaque amelioration = **1 pad rond** au sol
  (`Base.Upgrades.Pad_<Id>`, attribut `UpgradeId`) avec son icone (champ `icon` de la Config) et
  une **carte flottante** au style de l'interface (`IconPlate.Card`, visible a moins de 32 studs) :
  titre, icone, "actuel -> suivant" (`Value`), bouton vert `Price`, bouton violet `Robux`
  (A VALIDER, branche en phase 3). Les cartes du modele montrent le niveau de depart : le lot E
  les met a jour pour le proprietaire.
- Emplacements : Tree Speed / Tree Luck pres de l'arbre, Juice Limit derriere la palette de jus,
  Counter Limit / Customer Speed / Customers derriere l'etal, les 3 employes devant la cabane STAFF.
- Achat : le serveur voit le joueur sur le pad (sa base seulement), verifie niveau max et
  argent (`MoneyService.TrySpend`), monte le niveau. Il faut quitter le pad pour racheter.
  Pas assez d'argent : la carte clignote en rouge.
- Ameliorations : TreeSpeed, TreeLuck, JuiceLimit, CounterLimit, CustomerSpeed, CustomerCount.
- Employes (1 niveau chacun en phase 1, PNJ blocky visibles) :
  - Ramasseur (Collector) : porte les fruits du sol vers les bacs.
  - Presseur (Presser) : la presse va 2 fois plus vite (elle est deja automatique).
  - Serveur (Server) : porte les jus de la pile vers le comptoir.

## Valeurs de depart proposees (a equilibrer en test)

| Id | Effet niv. 1 | Par niveau | Niv. max | Prix du niveau suivant |
|---|---|---|---|---|
| TreeSpeed | 1 fruit / 2.5 s | x0.92 | 15 (0.78 s) | 15 x 1.35^(niv-1) |
| TreeLuck | 1 fruit (Apple) | +1 fruit | 10 x (3 + Rebirths), max 100 | 25 x 1.3^(niv-1) |
| JuiceLimit | 10 jus | +5 | 9 (50) | 30 x 1.5^(niv-1) |
| CounterLimit | 6 jus | +3 | 9 (30) | 30 x 1.5^(niv-1) |
| CustomerSpeed | 1 vente / 2.5 s | x0.92 | 15 | 80 x 1.45^(niv-1) |
| CustomerCount | 1 client | +1 | 5 | 300 x 2.5^(niv-1) |
| Collector | - | - | 1 | 40 |
| Presser | presse 1.5 s -> 0.75 s | - | 1 | 150 |
| Server | - | - | 1 | 400 |

Prix Robux : 5 + 3 x (niv-1), **A VALIDER**, aucun produit cree.

Simulation simple (joueur qui achete toujours le moins cher, sans gains acceleres) :

| Cible (`first-session.md`) | Simulation | Ecart |
|---|---|---|
| Tree Speed 0:35 | 0:36 | ok (prix 15 = 3 pommes) |
| Orange (Luck 2) 1:00-1:30 | 1:13 | ok |
| Ramasseur 2:30 | 2:54 | +0:24 |
| Banane (Luck 3) 4:00 | 1:59 | en avance |
| Presseur 5:00 | 9:48 | +4:48 |
| Fraise (Luck 11) 7:00 | 16:20 | +9:20 |
| Serveur 9:00 | 19:34 | +10:34 |
| Clients 11:00 | 5:45 (vitesse) / 17:17 (nombre) | variable |
| Dragon Fruit (Luck 21) 20:00 | > 30:00 | gros ecart |

L'ecart apres 5 min est attendu : les gains acceleres du debut (phase 2) doivent le combler.
A reprendre en playtest.

## Remotes

Aucun : achat par pad au sol detecte par le serveur.

## Donnees sauvegardees

`Upgrades` : niveau de chaque id (employes : 0 ou 1).

## Configuration

`Config/Upgrades.luau`.

## Problemes connus / a faire

- Tester le pad au sol sur telephone.
- Positions des pads : en haut de `tools/build-map/02e-base-staff-pads.luau`.
