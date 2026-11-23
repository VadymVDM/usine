# Systeme : Vol de boissons (pass Thief)

**Statut :** en cours (vol code le 2026-11-23 ; pas teste a 2 joueurs)
**Derniere mise a jour :** 2026-11-23

## Role

Pass Robux "Thief" (149 R$, `Shop.Passes`, aussi dans la boutique). Quand un joueur marche sur les
boissons d'une autre base, la fenetre d'achat Roblox du pass s'ouvre directement (pas de menu du jeu).

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/ThiefService.luau` | serveur | Detecte le joueur sur un pad a jus d'une autre base, ouvre la fenetre d'achat, pose l'attribut `Thief` |
| `src/shared/Config/Shop.luau` | partage | Pass `Thief` : prix, `passId` 2097082802 (cree sur Roblox) |
| `src/shared/Config/Gameplay.luau` | partage | `ThiefPromptCooldown`, `StealCooldown`, `StealHideSeconds`, messages `Steal*` |
| `src/server/Services/ProductionService.luau` | serveur | `PeekJuices` (gobelets du haut sans les retirer), `GetHandRoom`, `GiveJuices` |
| `src/client/Controllers/HandStackController.luau` | client | Cache chez le voleur les gobelets voles (Feedback `StolenCups`) |

## Fonctionnement

- Pads surveilles sur chaque etage qui tourne (proprietaire charge) ET vivant (son proprietaire y est) :
  `Production.TakeJuicePad` (table a jus) et `Counter.JuiceDropPad` (comptoir).
- Le serveur teste la position des personnages 10 fois / s (`PlayerCheck.IsOver`). Seulement a
  l'ARRIVEE sur un pad d'une autre base, et au plus une fois toutes les `ThiefPromptCooldown` s :
  - pas le pass et `passId > 0` : `MarketplaceService:PromptGamePassPurchase` (fenetre Roblox) ;
  - `passId = 0` : message "Robux purchases: coming soon!" (aucune fenetre possible) ;
  - deja le pass : message `ThiefOwned`.
- Achat fini (`PromptGamePassPurchaseFinished`) ou pass deja possede a l'arrivee
  (`UserOwnsGamePassAsync`) : attribut joueur `Thief = true` (pose par le serveur seulement).
- Ses propres pads ne declenchent rien.
- **Vol (2026-11-23, regles de l'utilisateur)**, avec le pass, sur la **table a jus** d'un autre :
  - le voleur prend **ses mains pleines** (place libre = `JuiceCarry` - jus deja portes), parmi les
    gobelets du haut de la table ; une fois par victime toutes les `StealCooldown` s (60 s) ;
  - **la victime ne perd rien** (son "assurance" rembourse) : sur le serveur, sa table ne change
    pas ; elle recoit le message `StealVictim` ("X stole N juices from you! Your insurance refunded
    everything.") ;
  - **seul le voleur** voit les gobelets disparaitre : Feedback `StolenCups` (modeles) ->
    `HandStackController` les rend transparents chez lui pendant `StealHideSeconds` (60 s) ; il voit
    aussi les gobelets sauter dans ses mains (Feedback `TakeJuice`) ;
  - il va les vendre a son propre comptoir (prix normal du jus = valeur du fruit).
  - Sur le comptoir d'un autre avec le pass : message `StealAtTable`. Mains pleines / table vide /
    trop tot : message rouge.
- Achat du pass : `GamePass.OnPurchased` (possession reverifiee aupres de Roblox, voir
  `achats-robux.md`).

## Remotes

Aucun : le serveur lit la position du personnage.

## Donnees sauvegardees

Aucune : Roblox garde le pass.

## Configuration

- `Gameplay.ThiefPromptCooldown` (8 s), `StealCooldown` (60 s), `StealHideSeconds` (60 s),
  messages `StealDone`, `StealVictim`, `StealWait`, `StealNothing`, `StealAtTable`.
- `Shop.Passes` cle `Thief` : `passId` 2097082802 (verifie le 2026-11-23 : "Thief", 149 R$, en vente).

## Problemes connus / a faire

- Le vol cree des jus (la victime ne perd rien) : argent en plus pour le voleur, limite par ses
  mains et 60 s par victime. A surveiller dans l'economie.
- Vol pas teste en jeu (code + build + Selene seulement). Le createur n'a jamais le pass : pour
  tester, activer le pass Thief dans le panneau admin, ou utiliser un autre compte.
- Pas teste a 2 joueurs dans Studio (seul cas qui ouvre la fenetre : il faut la base vivante d'un
  autre joueur ; test MCP a 1 joueur impossible). A faire : Test > Clients and Servers, 2 joueurs.
- Le createur n'a jamais le pass (Lib/GamePass) : il voit donc toujours la fenetre d'achat.
