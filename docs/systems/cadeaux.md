# Systeme : Cadeaux de passes

**Statut :** en cours (teste en Studio le 2026-11-23 avec des recus simules, 1 joueur ; vrai achat et 2 joueurs pas testes)
**Derniere mise a jour :** 2026-11-23

## Role

Le bouton rose (cadeau) d'un pass dans la boutique permet d'offrir ce pass a un autre joueur du
serveur. Le joueur choisit qui, paie le meme prix que le pass, et le destinataire recoit le pass
pour toujours (meme effet qu'un achat), meme s'il a quitte le serveur entre-temps.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/GiftService.luau` | serveur | Remote `ShopGift`, recus des produits cadeaux, boite aux lettres DataStore, livraison, tests |
| `src/server/Lib/GamePass.luau` | serveur | `Owns` compte les passes offerts ; `OnGranted` / `FireGranted` pour activer l'effet |
| `src/server/Services/RobuxShopService.luau`, `CustomerService`, `PassPadService`, `RebirthService`, `ThiefService` | serveur | `GamePass.OnGranted` : meme effet qu'un achat de leur pass |
| `src/server/Services/DataService.luau` | serveur | Champ `GiftedPasses` (sauvegarde) |
| `src/client/Controllers/GiftController.luau` | client | Fenetre "Gift <pass> to:" : liste des autres joueurs (tete, pseudo, bouton GIFT) |
| `src/client/Controllers/ShopController.luau` | client | Bouton rose d'un pass -> `GiftController.Open(cle)` |
| `src/shared/Config/Shop.luau` | partage | `giftProductId` de chaque pass, `Shop.Gifts`, messages |

## Fonctionnement

1. Boutique > bouton rose d'un pass -> fenetre "Gift VIP to:" (copie du menu OfflineEarnings, comme
   la pop-up de confirmation). Liste triee des autres joueurs du serveur, mise a jour s'ils
   arrivent ou partent ; personne : "No other players here!".
2. GIFT -> remote `ShopGift(cle, userId)`. Le serveur verifie (voir Remotes), note le destinataire
   pour ce produit (10 min) et ouvre le Developer Product "Gift - <pass>".
3. Recu (`ReceiptService`) : le cadeau `{ id = PurchaseId, key, from, fromName }` est ajoute a la
   boite aux lettres du destinataire (DataStore `PassGifts_v1`, cle `u<UserId>`, `UpdateAsync`) s'il
   n'y est pas deja (dans `Pending` ou `Done`). Echec du DataStore apres 3 essais : recu laisse en
   attente, Roblox le redonne. Acheteur : "Gift sent to <nom>!".
4. Livraison (destinataire dans ce serveur tout de suite, sinon a sa prochaine arrivee) : chaque
   cadeau de `Pending` -> `DataService.GrantPurchaseOnce` (`GiftedPasses[cle] = true`, PurchaseId
   garde) -> `GamePass.FireGranted` (effet actif) -> message "<nom> gifted you <pass>!" -> l'id passe
   dans `Done` (un recu redonne n'offre jamais deux fois).
5. A chaque chargement de sauvegarde, `GamePass.FireGranted` pour chaque pass offert (les services
   ne regardent les passes qu'a l'arrivee, avant que la sauvegarde soit chargee).

Recu sans destinataire note (autre serveur, plus de 10 min) : le pass est offert a l'acheteur
lui-meme ("<pass> unlocked!"). Passes offerts comptent comme possedes partout, createur du jeu
compris (`Lib/GamePass`). La boutique refuse d'acheter un pass deja recu en cadeau ("You already own
this pass!").

## Remotes

| Nom | Sens | Arguments | Verifications serveur |
|---|---|---|---|
| `ShopGift` | client -> serveur | (cle du pass, UserId du destinataire) | chaine courte, entier ; cle connue avec un produit cadeau ; pas soi-meme ; destinataire dans le serveur ; pas deja possede (cadeau ou achat) ; delai `Shop.BuyCooldownSeconds` ; rien donne avant le recu |

## Donnees sauvegardees

- Profil : `GiftedPasses = { [cle de Shop.Passes]: true }`, defaut `{}`, sans migration (sanitize :
  seulement des cles connues, valeur true).
- DataStore `PassGifts_v1`, cle `u<UserId>` : `{ Pending = { cadeaux }, Done = { PurchaseId } }`
  (au plus 50 en attente, 100 ids livres gardes). Le UserId est dans la cle (effacement RTBF).

## Configuration

`Config/Shop` : `giftProductId` sur chaque pass (11 produits crees le 2026-11-23, voir
`achats-robux.md`), `Shop.Gifts` (StoreName, PendingSeconds, MaxMailbox, MaxDone, Retries),
messages `Gift*`.

Tests Studio :
```
game.ServerStorage.Debug.Call:Invoke("Gift", "Send", "<Nom>", "VIP", <UserId ou 0>, "id")
game.ServerStorage.Debug.Call:Invoke("Gift", "Get", "<Nom>")
game.ServerStorage.Debug.Call:Invoke("Gift", "Remove", "<Nom>", "VIP") -- ecrit la sauvegarde
```

## Problemes connus / a faire

- Pas teste : vraie fenetre d'achat, vrai achat, 2 joueurs (ligne d'un joueur dans la liste jamais
  vue a l'ecran), telephone.
- Le prix sur Roblox de chaque "Gift - <pass>" doit rester egal au prix du pass.
- Un destinataire qui achete le pass lui-meme entre le choix et le recu recoit quand meme le cadeau
  (perdu pour lui, avertissement dans la sortie).
- Les passes offerts restent apres un rebirth (comme les vrais passes).
- `Gift Remove` retire le pass de la sauvegarde, mais l'effet reste jusqu'a la prochaine arrivee.
