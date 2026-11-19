# Systeme : Comptoir, clients et tas d'argent

**Statut :** a concevoir
**Derniere mise a jour :** 2026-11-19

## Role

Les clients de la base achetent les jus poses sur le comptoir et laissent l'argent sur un tas ;
le joueur marche sur le tas pour encaisser.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/CustomerService.luau` | serveur | Minuteur des ventes, tas d'argent, encaissement |
| `src/client/Controllers/CustomerController.luau` | client | PNJ blocky visuels qui viennent de la route, pluie de billets |
| `src/shared/Config/Upgrades.luau` | partage | Vitesse et nombre de clients |

## Fonctionnement

- Chaque base a son propre minuteur : toutes les `CustomerSpeed` secondes, jusqu'a
  `CustomerCount` clients prennent chacun 1 jus du comptoir et ajoutent son prix au tas d'argent.
- Le serveur decide seul des ventes. Les PNJ sont **dessines par le client** (aucune charge
  reseau) : a chaque vente, la base change un attribut (`SaleCount`) et le client fait venir un
  PNJ de la route, prendre un gobelet et repartir.
- Le tas d'argent affiche son montant ; le joueur proprietaire marche dessus -> `MoneyService.Add`
  + pluie de billets simple (client). Le tas n'est pas sauvegarde.

## Remotes

Aucun (attributs de la base).

## Donnees sauvegardees

Aucune (niveaux `CustomerSpeed`, `CustomerCount`, `CounterLimit` dans `Upgrades`).

## Configuration

`Config/Upgrades.luau` (CustomerSpeed, CustomerCount, CounterLimit).

## Problemes connus / a faire

-
