# Systeme : Argent, HUD et classement

**Statut :** en cours (code fait et teste en Studio sans sauvegarde reelle)
**Derniere mise a jour :** 2026-11-23 (prix affiches arrondis vers le haut)

## Role

`MoneyService` est le seul a modifier l'argent du joueur (ajouter, depenser). Le HUD affiche le
montant en bas a gauche et le classement du serveur (leaderstats) montre l'argent et les rebirths.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/MoneyService.luau` | serveur | `Add`, `TrySpend`, `Get` ; leaderstats |
| `src/client/Controllers/MoneyHudController.luau` | client | Affiche l'argent dans `HUD.Canvas.Money.Cash.Money` ; le montant **compte** au lieu de sauter (2026-11-19 soir) : pendant un encaissement, `CashController` retient le montant (`Hold`) puis le relache billet par billet (`Release`), les billets volent jusqu'au montant ; autre hausse = montee rapide ; baisse = immediate. Detail : `clients.md` |
| `src/shared/Util/NumberFormat.luau` | partage | Suffixes K/M/B/T... (affichage seulement). `Money` / `Abbreviate` : arrondi vers le bas (argent, gains). `Price` / `AbbreviateUp` : arrondi vers le haut (**tout prix a payer**) |
| `src/server/Services/DebugService.luau` | serveur | Studio seulement : `ServerStorage.Debug.Call` pour les tests |

## Fonctionnement

- Argent **toujours entier**, jamais negatif, plafonne a `GameConfig.MaxMoney` (1e15). `Add(player, montant, raison)` refuse les montants
  non entiers, negatifs, NaN ou infinis. `TrySpend(player, prix)` retire seulement si le joueur a
  assez et renvoie vrai/faux. Aucun remote ne modifie l'argent.
- Son de paiement : apres chaque `TrySpend` reussi (sauf raisons `Rebirth` et `debug`), le serveur
  envoie `Feedback` "Paid" { amount } au joueur ; `CashController` joue le son `Paid`
  (Config/Sounds). Couvre tous les achats en argent : pads de machines, tuiles des panneaux,
  etages, menu Upgrades.
- L'argent vit dans la sauvegarde (`Data.Money`) ; MoneyService met a jour aussi
  `leaderstats.Cash` (IntValue) et `leaderstats.Rebirths`.
- **Regle d'affichage des prix (2026-11-23)** : l'argent est arrondi vers le bas, les prix vers le
  haut (`NumberFormat.Price`). Ainsi "argent affiche >= prix affiche" veut toujours dire que l'achat
  passe. Avant, les deux etaient arrondis vers le bas : prix 1 525 et argent 1 520 affichaient tous
  les deux "$1.52K" et le clic donnait "Not enough money!" (vu sur le panneau Customers). Prix
  concernes : tuiles et pads (`UpgradeService`), etage a acheter et panneau Elevator
  (`FloorService`), pop-up de confirmation (`BuyController`), menu Upgrades
  (`UpgradeMenuController`), Rebirth, tutoriel ("{price}"), "Almost there!" (argent manquant).
  Tout nouveau prix affiche doit utiliser `NumberFormat.Price`.
- Le HUD lit `leaderstats.Cash` (replique par Roblox, pas de remote) et affiche "$1.25K" etc.
  Quand l'argent monte, le texte compte jusqu'a la nouvelle valeur (encaissement : au rythme des
  billets qui arrivent en bas a gauche).
- `leaderstats` (Cash, Rebirths) est cree des l'arrivee (valeurs 0), puis rempli quand la
  sauvegarde est chargee. Tant qu'elle n'est pas chargee, `Add`/`TrySpend` renvoient faux.
- Le "+" jaune (packs d'argent) reste non branche (phase 3).

## Tests

En playtest Studio (serveur) : `game.ServerStorage.Debug.Call:Invoke("Money", "Add", "<Nom>", 100)`
(aussi `TrySpend`, `Get`, et `"Data", "Get"`). Verifie le 2026-11-19 : +1250 accepte ; -5, 1.5,
NaN, inf refuses ; depense de 2000 refusee avec 1250 ; depense de 250 acceptee -> 1000 ;
leaderstats = 1000 ; HUD = "$1K".

Avant un test qui detruit la progression (rebirth) : `Invoke("Data", "Snapshot", "<Nom>")`, puis
`Invoke("Data", "Restore", "<Nom>")` (argent, rebirths, etages et leurs niveaux, ascenseur, arbres
gardes ; photo en memoire seulement, perdue a l'arret du playtest). Rebirth : `rebirth.md`.
Le multiplicateur du rebirth s'applique aux ventes (x2, x3...) : `rebirth.md`, `clients.md`.

Classement mondial de l'argent (panneau RICHEST au bout de la route) : `classements.md`.

## Remotes

Aucun qui modifie l'argent (le client lit `leaderstats`). Envoi seulement : `Feedback` "Paid" { amount } (son de paiement).

## Donnees sauvegardees

`Money` (voir `sauvegarde.md`).

## Configuration

`GameConfig.StartingMoney` (0), `GameConfig.MaxMoney` (1e15).

## Problemes connus / a faire

- Plafond 1e15 (= "$1Qa") : au-dela de 2^53 les entiers ne sont plus exacts. A revoir en phase 4
  (raretes tres hautes + multiplicateurs de rebirth : il faudra un autre format de nombre).
- `WelcomeBackController` a encore son propre `formatMoney` (pas de refactor de l'interface en
  phase 1) : a remplacer par `NumberFormat` plus tard.
