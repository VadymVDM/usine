# Systeme : Vol de boissons (pass Thief)

**Statut :** en cours (vol a l'unite code le 2026-11-27 : 1er gratuit puis 19 R$ ; produit cree ; PAS teste en Play)
**Derniere mise a jour :** 2026-11-27

## Role

Dans la base d'un autre joueur, en regardant les boissons de sa **table a jus** ou de son
**comptoir**, le joueur voit un prompt **E "Steal"**.

**Depuis le 2026-11-27 (demande utilisateur) : vol a l'unite.**
- **1er vol gratuit** pour tout le monde, **une fois par serveur** (compte par UserId en memoire :
  quitter / revenir sur le meme serveur ne le redonne pas ; un autre serveur = un nouveau vol gratuit).
- Ensuite **chaque vol = 19 R$** (Developer Product `Shop.Steal`) : fenetre d'achat Roblox, les
  boissons visees sont gardees de cote ("photo") pendant qu'il paie, et donnees au recu.
- Le pass "Thief" (149 R$) n'est **plus vendu en jeu** (`hidden = true` dans `Shop.Passes` : ni carte
  dans la boutique, ni cadeau). Ceux qui l'ont deja (achat ou cadeau) volent toujours **gratuitement
  et sans limite**. Le pass reste en vente sur la page Roblox du jeu (pas touche).

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/ThiefService.luau` | serveur | Cree les prompts Steal, verifie chaque appui sur E, photo + fenetre d'achat, vol, attribut `Thief` |
| `src/client/Controllers/PromptController.luau` | client | Montre les prompts `ForOthers` seulement dans les bases des AUTRES joueurs |
| `src/shared/Config/Shop.luau` | partage | Pass `Thief` (`hidden`), `passId` 2097082802 ; `Shop.Steal` : prix 19, `productId` du vol a l'unite |
| `src/server/Services/ReceiptService.luau` | serveur | Recoit le recu du produit Steal et appelle ThiefService |
| `src/client/Controllers/ShopController.luau` | client | Ne montre pas les passes `hidden` |
| `src/server/Services/DebugService.luau` | serveur (Studio) | `Thief GrantSteal` : simule l'achat paye d'un vol |
| `src/shared/Config/Gameplay.luau` | partage | Delais, portee, textes du prompt (`PromptTexts.Steal*`), messages `Steal*` |
| `src/server/Services/ProductionService.luau` | serveur | `PeekJuices` (gobelets du haut de la table, sans les retirer), `GetJuiceCount`, `GetHandRoom`, `GetHandCapacity`, `GiveJuices` |
| `src/server/Services/CustomerService.luau` | serveur | `PeekCounter` (gobelets du haut du comptoir, sans les retirer), `GetCounterCount` |
| `src/client/Controllers/HandStackController.luau` | client | Cache chez le voleur les gobelets voles (Feedback `StolenCups`) |

## Fonctionnement

- **Prompts** : sur chaque etage qui tourne, 2 prompts E "Steal" sur de petites pieces invisibles
  dans `Dynamic` de l'etage (`StealTableAnchor` au centre de `Production.JuicePile`,
  `StealCounterAnchor` au centre de `Counter.CounterTopArea`). Texte : "Adam's Juice Table" /
  "Adam's Counter". Portee `StealPromptDistance` (14 studs).
  - Attribut `ForOthers = true` : `PromptController` les montre seulement dans une base qui a un
    proprietaire et qui n'est PAS la sienne (les autres prompts restent visibles seulement chez soi).
  - Attribut `Active` (serveur, toutes les `StealRefreshSeconds` = 0.5 s) : vrai seulement si l'etage
    est vivant (son proprietaire y est) ET qu'il y a des jus sur cette table / ce comptoir.
  - Roblox montre le prompt le plus proche de la direction de la camera : on "regarde" la table ou
    le comptoir pour choisir.
- **Appui sur E** (`Triggered`, verifie par le serveur) : pas sa propre base, victime presente, etage
  vivant, joueur a portee (`PlayerCheck.CanReach`), 0.4 s minimum entre deux appuis.
  - **Avec le pass** : ses mains pleines (place libre = `JuiceCarry` - jus deja portes), parmi les
    gobelets du haut de la table ou du comptoir, **a chaque appui sur E, sans limite de temps**
    (pass "UNLIMITED"). Limites : mains pleines et 0.4 s entre deux appuis. Mains pleines / rien a
    voler : message rouge. (Jusqu'au 2026-11-27 : une fois par victime toutes les 60 s, ce qui
    bloquait E juste apres l'achat ; supprime a la demande de l'utilisateur.)
  - **Sans le pass, vol gratuit restant** (1er vol du serveur, ou vol paye garde en credit) : vol
    tout de suite comme avec le pass. Le vol gratuit n'est consomme que si au moins 1 jus est vole
    (mains pleines / rien a voler : pas consomme). Dernier vol gratuit utilise : message
    `StealFree` ("Free steal used! Next steals cost 19 Robux.").
  - **Sans le pass, plus de vol gratuit** (au plus une fenetre toutes les `ThiefPromptCooldown` = 2 s) :
    1. **photo** des jus vises A L'APPUI SUR E : les gobelets du haut, autant que le joueur peut en
       porter mains vides (`GetHandCapacity`) ; ids, positions et modeles gardes sur le serveur ;
    2. fenetre d'achat Roblox du produit `Shop.Steal` (19 R$, `Lib/PurchasePrompt.Product`) ;
    3. recu (`ReceiptService` -> `ThiefService`, PurchaseId note une seule fois avec
       `DataService.GrantPurchaseOnce`) : le voleur recoit **les jus de la photo** si elle a moins de
       `StealPendingSeconds` (180 s), meme si la table a ete videe ou vendue pendant qu'il payait
       (place libre des mains au moment du recu). Un nouvel appui sur E remplace la photo. Fenetre
       fermee sans acheter : la photo expire toute seule.
    4. recu sans photo valable, ou mains pleines au moment du recu : le vol paye devient un **credit**
       (prochain E = vol gratuit), message `StealCredit`.
  - `Shop.Steal.productId = 0` : message "Robux purchases: coming soon!" (aucune fenetre).
- **La victime ne perd rien** (son "assurance" rembourse) : sur le serveur, sa table et son comptoir
  ne changent pas ; elle recoit `StealVictim` ("X stole N juices from you! Your insurance refunded
  everything.") si elle est encore la.
- **Seul le voleur** voit les gobelets disparaitre : Feedback `StolenCups` (modeles) ->
  `HandStackController` les rend transparents chez lui pendant `StealHideSeconds` (60 s) ; il voit
  aussi les gobelets sauter dans ses mains (Feedback `TakeJuice`). Il va les vendre a son comptoir.
- Possession : attribut joueur `Thief = true`, pose par le serveur seulement (arrivee si deja achete,
  achat, cadeau `GamePass.OnGranted`, panneau admin). Si le serveur l'a rate alors que Roblox dit
  "deja possede", l'appui sur E rouvre la fenetre ; a sa fermeture (meme "Vous possedez deja cet
  objet"), `Lib/GamePass` revoit la possession et active le pass (corrige le 2026-11-27).
- Avant le 2026-11-27 : le vol / la fenetre se declenchaient en MARCHANT sur les pads a jus d'une
  autre base (table seulement). Remplace par la touche E.

## Remotes

Aucun remote a nous : `ProximityPrompt.Triggered` (verifie comme un remote).

## Donnees sauvegardees

Seulement le PurchaseId de chaque vol paye (`Data.PurchaseIds`, anti double recu). Roblox garde le
pass. Vol gratuit, credits, photo et delais : en memoire du serveur.

## Configuration

- `Gameplay.ThiefPromptCooldown` (2 s), `StealPromptDistance` (14), `StealPendingSeconds` (180),
  `StealRefreshSeconds` (0.5), `StealHideSeconds` (60 s). (`StealCooldown` supprime le 2026-11-27.)
- Textes : `PromptTexts.StealAction` ("Steal"), `StealTableObject`, `StealCounterObject` ;
  messages `StealDone`, `StealVictim`, `StealNothing` (`StealWait` supprime).
- `Shop.Passes` cle `Thief` : titre "THIEF (UNLIMITED)", `passId` 2097082802 (verifie le 2026-11-23 :
  "Thief", 149 R$, en vente). Le nom du pass SUR ROBLOX (fenetre d'achat) est toujours "Thief".

## Problemes connus / a faire

- Produit Steal cree le 2026-11-27 : id 3736758899, 19 R$, en vente, icone `thief.png` (verifie par `GetProductInfo`).
- **Pas teste en Play** (place partagee pas branchee sur Rojo). A tester avec Rojo : 1er E gratuit,
  2e E = fenetre 19 R$, `Debug.Call:Invoke("Thief", "GrantSteal", nom)` = credit puis E gratuit.
- Credit d'un vol paye (mains pleines au recu) garde en memoire du serveur seulement : perdu si le
  joueur change de serveur avant de l'utiliser (cas rare ; le PurchaseId, lui, est sauvegarde).
- Avocat du diable : 19 R$ par vol peut rapporter moins que l'ancien pass a 149 R$ (il faut 8 vols
  payes pour egaler 1 pass) ; a surveiller dans les ventes.

- **Pas teste a 2 joueurs** (Test > Clients and Servers, 2 joueurs) : appui sur E chez l'autre, vol
  avec le pass, fenetre d'achat + photo. Teste le 2026-11-27 a 1 joueur seulement : prompts crees,
  `Active` suit les jus du comptoir, prompt cache dans sa base et visible en simulant une autre base.
- Le createur n'a jamais le pass (Lib/GamePass) : il voit toujours la fenetre d'achat, et l'achat
  n'est jamais confirme pour lui (la photo n'est donc pas testable avec son compte). Pour tester le
  vol avec le pass : activer Thief dans le panneau admin, ou un autre compte.
- Le vol cree des jus (la victime ne perd rien) : argent en plus pour le voleur, limite seulement
  par ses mains (et le trajet jusqu'a son comptoir) depuis la fin du delai de 60 s. A surveiller
  dans l'economie : un voleur peut remplir ses mains a chaque aller-retour.
- Les gobelets caches chez le voleur sont les MODELES photographies : si la victime vend / bouge ses
  gobelets pendant les 60 s, d'autres gobelets peuvent rester visibles ou cachés (effet visuel seul).
