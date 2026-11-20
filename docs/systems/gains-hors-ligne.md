# Systeme : Gains hors ligne (ecran "Welcome Back!")

**Statut :** en cours (fonctionne en playtest Studio PC le 2026-11-20 ; produit x2 pas cree, telephone pas teste)
**Derniere mise a jour :** 2026-11-20

## Role

Quand le joueur revient, il recoit l'argent que ses etages automatises ont gagne pendant son
absence, moins que s'il avait joue. L'ecran "Welcome Back!" montre la duree et le montant, avec
CLAIM et un bouton x2 en Robux. C'est la mesure de retour (J1 / J7) la plus rentable.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/OfflineService.luau` | serveur | Calcul, offre sauvegardee, CLAIM, x2 (recu), depart |
| `src/server/Services/DataService.luau` | serveur | `LastLogout` a chaque sauvegarde, `GetPreviousLogout`, champ `OfflineReward` |
| `src/server/Services/CustomerService.luau` | serveur | `GetIncomePerSecond` (production en nombres, `Lib/FloorIncome`) |
| `src/client/Controllers/WelcomeBackController.luau` | client | Ecran (menu `OfflineEarnings` du pack UI) |
| `src/shared/Config/Offline.luau` | partage | Reglages (part, plafond, minimums) |
| `src/shared/Config/Shop.luau` | partage | `Shop.OfflineDouble` (prix 9 R$, `productId`) |

## Fonctionnement

Joueur : il revient apres X heures -> une fois le chargement fini, l'ecran "Welcome Back!" s'ouvre :
"You were offline for 2h 0m and earned: $43.64K". CLAIM -> l'argent arrive (son + compteur du
HUD), l'ecran se ferme. x2 -> fenetre d'achat Robux (9 R$) -> le double arrive. Fermer l'ecran
(croix) = CLAIM. Absence courte ou etages pas automatises -> pas d'ecran.

Code :
1. `DataService` met `LastLogout = os.time()` a chaque sauvegarde (auto et derniere). Au chargement,
   la valeur d'avant est gardee (`GetPreviousLogout`). Serveur plante : l'absence part de la
   derniere sauvegarde (pas de la session d'avant).
2. `OfflineService` calcule l'offre UNE fois par session, quand le client dit "Ready" (apres
   `LoadingDone` : les attributs des passes Auto Sell / Billboard / Waiter Speed sont poses), ou au
   recu x2, ou au depart :
   `montant = floor(GetIncomePerSecond x min(absence, 8 h) x 0.5)`.
   - `GetIncomePerSecond` = somme des etages **automatises** (Fruit Picker + Waiter +
     Operator 1), x rebirth et Billboard. Un etage pas automatise ne rapporte rien (voulu).
   - Absence < 5 min ou montant < 10 $ : rien.
   - Offre d'avant pas reclamee (serveur coupe avant la sauvegarde de depart) : ajoutee a la nouvelle.
3. L'offre est sauvegardee (`Data.OfflineReward`) avec `Claimed` et `Doubled` :
   - CLAIM : `Claimed = true` puis `MoneyService.Add` (une seule fois ; 3 clics -> 1 seul ajout) ;
   - x2 (recu, `DataService.GrantPurchaseOnce`) : pas reclame -> 2 x montant ; deja reclame ->
     + montant (la moitie manquante) ; x2 deja donne (2e achat) -> le dernier montant, au moins
     10 min de gains actuels (`FallbackMinutes`) : jamais 0 contre des Robux ;
   - depart sans CLAIM : l'argent est donne avant la derniere sauvegarde (rien de perdu). Un recu
     x2 qui arrive plus tard donne encore la moitie manquante.
4. Le client n'envoie jamais de montant ; il recoit "Show" (secondes, montant) et "Claimed".

## Remotes

| Nom | Sens | Arguments | Verifications serveur |
|---|---|---|---|
| `OfflineEarnings` | client -> serveur | `"Ready"` \| `"Claim"` \| `"Double"` | chaine connue (le reste ignore), delai 0.5 s par action, sauvegarde chargee, offre pas deja prise ; `Double` : productId 0 -> "Robux purchases: coming soon!" |
| `OfflineEarnings` | serveur -> client | `"Show"`, secondes, montant \| `"Claimed"` | - |
| `Feedback` "Cash" | serveur -> client | `{ amount }` | effet d'argent du HUD apres CLAIM / x2 |

## Donnees sauvegardees

- `OfflineReward = { Amount, Seconds, Claimed, Doubled }`, defaut `{ 0, 0, true, true }` (rien a
  prendre). SchemaVersion 5 (2026-11-20), pose par Reconcile, corrige par `sanitize`.
- `LastLogout` (existait) : maintenant aussi mis a jour a chaque sauvegarde auto.
- Achats x2 : `PurchaseIds` (GrantPurchaseOnce). Voir `sauvegarde.md`.

## Configuration

`src/shared/Config/Offline.luau` (A VALIDER) : `Rate` 0.5, `MaxSeconds` 8 h, `MinAwaySeconds` 5 min,
`MinAmount` 10, `FallbackMinutes` 10, `ActionCooldownSeconds` 0.5, `ReceiptWaitSeconds` 15.
Produit x2 : `Shop.OfflineDouble` (`price` 9, `productId` 0 tant qu'il n'est pas cree ; le
handler de recu n'est enregistre que si `productId > 0`).

Tests Studio : `game.ServerStorage.Debug.Call:Invoke("Offline", "Get" | "Simulate" secondes | "Double", "<NomJoueur>")`.

## Problemes connus / a faire

- Produit Developer "x2 Offline Earnings" a creer sur Roblox, puis mettre son id dans `Shop.OfflineDouble`.
- Teste le 2026-11-20 (playtest Studio PC, 1 joueur, vrai DataStore) : 2 h / 3 h / 10 h (plafond 8 h)
  avec 12.12 $/s -> 43 649 / 65 473 / 174 596 (= formule) ; ecran affiche ("3h 0m", "$65.47K") ;
  3 clics sur CLAIM -> 1 seul ajout ; spam de remote et arguments faux ignores ; x2 a 0 -> "coming
  soon" ; x2 simule avant / apres CLAIM et 2e achat ; absence 2 min -> rien ; depart sans CLAIM ->
  argent donne et relu apres un vrai quitter / revenir ; retour 5 s apres -> pas d'ecran.
- Vu une fois, pas reproduit : au 1er essai, l'ecran s'est ferme tout seul en ~2 s (l'argent a ete
  donne par le "fermer = CLAIM"). A surveiller.
- Pas teste : vrai achat Robux, telephone, 2 serveurs, serveur qui plante.
- Le texte "You were offline for ..." contient des nombres : a mettre dans une table de traduction
  (docs/game-design.md, section Traduction).
