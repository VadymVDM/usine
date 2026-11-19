# Systeme : Argent, HUD et classement

**Statut :** a concevoir
**Derniere mise a jour :** 2026-11-19

## Role

`MoneyService` est le seul a modifier l'argent du joueur (ajouter, depenser). Le HUD affiche le
montant en bas a gauche et le classement du serveur (leaderstats) montre l'argent et les rebirths.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/MoneyService.luau` | serveur | `Add`, `TrySpend`, `Get` ; leaderstats |
| `src/client/Controllers/MoneyHudController.luau` | client | Affiche l'argent dans `HUD.Canvas.Money.Cash.Money` |
| `src/shared/Util/NumberFormat.luau` | partage | Suffixes K/M/B/T (affichage seulement) |

## Fonctionnement

- Argent **toujours entier** et jamais negatif. `Add(player, montant, raison)` refuse les montants
  non entiers, negatifs, NaN ou infinis. `TrySpend(player, prix)` retire seulement si le joueur a
  assez et renvoie vrai/faux. Aucun remote ne modifie l'argent.
- L'argent vit dans la sauvegarde (`Data.Money`) ; MoneyService met a jour aussi
  `leaderstats.Cash` (IntValue) et `leaderstats.Rebirths`.
- Le HUD lit `leaderstats.Cash` (replique par Roblox, pas de remote) et affiche "$1.25K" etc.
- Le "+" jaune (packs d'argent) reste non branche (phase 3).

## Remotes

Aucun (le client lit `leaderstats`).

## Donnees sauvegardees

`Money` (voir `sauvegarde.md`).

## Configuration

`GameConfig.StartingMoney` (0).

## Problemes connus / a faire

- Au-dela de 2^53 (~9 quadrillions) les entiers ne sont plus exacts : a revoir en phase 4
  (raretes tres hautes + multiplicateurs de rebirth).
