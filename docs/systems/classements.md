# Systeme : Classements mondiaux (murs-ecrans aux bouts de la route)

**Statut :** en cours (murs construits, place version 157 ; MONEY et TIME remplis en playtest le 2026-11-20)
**Derniere mise a jour :** 2026-11-20

## Role

2 grands murs-ecrans (cadre blanc a studs, ecran noir), un a chaque bout de la route, avec 2
classements cote a cote chacun : top 10 de tous les serveurs depuis toujours. Demande de
l'utilisateur (2026-11-20, avec 2 captures d'un autre jeu comme modele de style) : argent + boissons
vendues d'un cote, temps de jeu + Robux payes de l'autre.

```
 [WestWall : MONEY | JUICES SOLD]  SPAWN ======= ROUTE ======= [EastWall : TIME PLAYED | ROBUX SPENT]
   x -352, regarde l'est             (place)       x -300..300    x 304, regarde l'ouest
```

Mur : 66 de large (z -33 -> 33), 32 de haut, 3 d'epaisseur ; ecran 60 x 26 en retrait. Titre sans
fond, ecrit en couleur (vert, orange, bleu, violet ; fond retire le 2026-11-20 a la demande) ; lignes "#n, tete de l'avatar, nom, valeur" (valeur de
la couleur du titre). 1re version (4 panneaux sur une place au bout est) remplacee le jour meme.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/shared/Config/Leaderboards.luau` | partage | Les 4 classements (id, titre, couleur, mur, colonne, OrderedDataStore), lignes, delais, `FormatTime` |
| `src/server/Services/LeaderboardService.luau` | serveur | Compteurs `JuicesSold` / `TimePlayed`, Robux payes, ecriture et lecture des classements, texte des panneaux |
| `src/server/Services/ReceiptService.luau` | serveur | `OnGranted(hook)` : appele apres chaque achat Robux accorde |
| `src/server/Services/CustomerService.luau` | serveur | Appelle `LeaderboardService.AddJuicesSold` a chaque vente (et ventes "en nombres") |
| `tools/build-map/08-leaderboards.luau` | Studio | Construit `Workspace.Map.Leaderboards.WestWall / EastWall` (positions dans `WALLS`) |

## Fonctionnement

| Panneau | Valeur | Source |
|---|---|---|
| MONEY | argent actuel (`$1.26M`) | `Data.Money` (MoneyService reste le seul a le modifier) |
| JUICES SOLD | jus vendus depuis toujours | `Data.JuicesSold`, +1 par jus vendu au comptoir ; etages "en nombres" : `juicesPerSecond` |
| TIME PLAYED | temps de jeu (`3h 12m`, `2d 5h`) | `Data.TimePlayed` (secondes), ajoute depuis le chargement de la sauvegarde |
| ROBUX SPENT | Robux payes, tous achats (dons compris), affiche `R$4,483` | DataStore `RobuxSpent_v1`, cle `u<UserId>` : `{ Total, Receipts }` |

- Ecriture : chaque joueur toutes les `WriteSeconds` (120 s, joueurs etales) et a son depart :
  `SetAsync` dans un OrderedDataStore par panneau (`Board_<id>_v1`, cle `<UserId>`), seulement si la
  valeur a change et > 0. UserId <= 0 (joueurs de test "Local Server") ignores.
- Robux : `ReceiptService` appelle le hook apres le handler du produit. `UpdateAsync` avec la liste
  des 50 derniers `PurchaseId` (jamais compte deux fois), puis classement `UpdateAsync` qui ne
  baisse jamais. Si l'ecriture du total echoue : recu en `NotProcessedYet`, Roblox le redonne (le
  handler du produit doit donc reconnaitre un `PurchaseId` deja traite : regle de `dons.md`).
  `CurrencySpent` = 0 (achat test Studio) : rien compte.
- Lecture : toutes les `RefreshSeconds` (60 s), `GetSortedAsync` des 4 classements ; noms en cache ;
  le serveur ecrit `PlayerName`, `Value`, `Avatar` dans `Map.Leaderboards.<wall>.Screen.Display.<id>.Rows.RowN`.

## Remotes

Aucun.

## Donnees sauvegardees

Profil (`DataService`, sans changer `SchemaVersion` : `Reconcile` ajoute les champs, `sanitize` les
remet en entiers >= 0) : `JuicesSold` (0), `TimePlayed` (0, secondes).
Hors profil : `RobuxSpent_v1` (DataStore) et les 4 OrderedDataStores `Board_*_v1`.
"Reset All" admin remet `JuicesSold` / `TimePlayed` a 0 (le classement suit a la prochaine ecriture) ;
les Robux payes ne sont jamais effaces.

## Configuration

`src/shared/Config/Leaderboards.luau` : titres, couleurs, mur (`wall`), colonne (`column`), `Rows` (10,
doit egaler les lignes de 08), `RefreshSeconds`, `WriteSeconds`. Positions et tailles dans `08-leaderboards`
(`WALLS`, `W`, `H`).

## Problemes connus / a faire

- **Teste le 2026-11-20 (Studio PC, vrai DataStore, 1 joueur, 1re version des panneaux) :** argent
  "PROVADNIKE_ROBLOX / $999.99T" et temps "3m" lus depuis les OrderedDataStores et ecrits sur les
  panneaux ; console sans erreur. Murs actuels : captures en Edit avec des lignes d'apercu (texte,
  avatars, couleurs) ; 0 piece du decor qui chevauche les murs. Le service n'a PAS encore ete vu
  remplir les nouveaux murs en playtest : MONEY et TIME PLAYED remplis avec avatar (2026-11-20).
- **Pas teste :** jus vendus (compteur a 0 dans ce playtest, test `AddJuicesSold` coupe par la fin
  du playtest), Robux (aucun produit), 2 serveurs, telephone, avatars des lignes (pas vus en capture).
- Mur ouest : la fontaine du spawn cache un peu la colonne JUICES SOLD vue du centre de la place.
- Pas de "Scroll for more" (la capture de reference en a un) : seulement le top 10.

- "Max Money" du panneau admin met 1e15 $ : l'admin sera premier de RICHEST (vrai DataStore).
- Le classement RICHEST prend l'argent actuel : il baisse quand le joueur depense (ecrit tel quel).
- Robux payes : seuls les achats faits a partir du 2026-11-20 comptent (aucun produit n'existait).
- Les pass (GamePass) ne passent pas par `ProcessReceipt` : pas comptes dans TOP SUPPORTERS.
- Si `01-ground-road` ou `03-decor` change la route ou le spawn, verifier que les murs collent encore.
