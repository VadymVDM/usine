# Systeme : Chaine de production (arbre, ramassage, bacs, presse, jus)

**Statut :** a concevoir
**Derniere mise a jour :** 2026-11-19

## Role

L'arbre fait tomber des fruits ; le joueur les ramasse en marchant dessus, les depose dans les
bacs ; le presse-fruits fait 1 jus par fruit ; le joueur porte les jus jusqu'au comptoir.
Tirage des fruits et Index : voir aussi `fruits.md`.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/TreeService.luau` | serveur | Chute, tirage selon Luck, garantie, "Tree full!", decouvertes |
| `src/server/Services/ProductionService.luau` | serveur | Contacts (fruits, bacs, pile de jus, comptoir), pile portee, presse |
| `src/shared/Config/Fruits.luau` | partage | 100 fruits |
| `src/shared/Config/Gameplay.luau` | partage | Plafonds, capacites, temps de presse |
| `src/shared/FruitModels.luau` | partage | Modele blocky d'un fruit genere depuis la Config |

## Fonctionnement

- Chute : 1 fruit toutes les `TreeSpeed` secondes, sur le sol autour de l'arbre. A 30 fruits au
  sol (`Gameplay.MaxGroundFruits`) l'arbre s'arrete et affiche "Tree full!".
- Tirage : fruits 1 a `TreeLuck`, chacun avec son poids (`Fruits.luau`). Luck max =
  10 x (`StartRarities` + Rebirths), plafonne a 100.
- Garantie : s'il existe un fruit pas encore decouvert parmi les fruits possibles, il tombe au
  plus tard a la `Gameplay.NewFruitGuaranteeDrops`-ieme chute (3). Regle sans etat a sauvegarder.
- Premiere visite : 3 pommes au sol des l'arrivee (`Gameplay.FirstVisitApples`).
- Ramassage : le serveur regarde regulierement (~10 fois/s) la position de chaque joueur dans sa
  base ; un fruit a moins de `PickupRadius` est ramasse. Pas de remote "j'ai ramasse".
  On ne ramasse que dans SA base.
- Pile au-dessus de la tete : fruits et jus, capacite fixe `Gameplay.CarryCapacity` (20,
  proposition : fixe en phase 1).
- Bacs : marcher dessus depose tous les fruits portes, tries par type (1 bac par fruit ouvert).
- Presse : **automatique des le debut**, prend un fruit dans les bacs (le moins cher d'abord) toutes
  les `Gameplay.PressSeconds` (1.5 s) et pose 1 jus sur la pile a cote. S'arrete si la pile de
  jus est pleine (`JuiceLimit`). Le Presseur divise ce temps par 2.
- Jus : prix = valeur du fruit. Gobelet de la couleur du jus. Au-dessus de la pile : "n/max",
  "!" rouge si pleine.
- Marcher sur la pile de jus : le joueur prend les jus (jusqu'a sa capacite). Marcher sur le
  comptoir : il les pose (jusqu'a `CounterLimit`).

## Remotes

Aucun : tous les contacts sont detectes par le serveur.

## Donnees sauvegardees

`DiscoveredFruits` (TreeService). Niveaux `TreeSpeed`/`TreeLuck` dans `Upgrades`.

## Configuration

`Config/Fruits.luau`, `Config/Gameplay.luau`, `Config/Upgrades.luau`.

## Problemes connus / a faire

-
