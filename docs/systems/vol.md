# Systeme : Vol de boissons (pass Thief)

**Statut :** en cours (seule la proposition d'achat est codee ; le vol lui-meme ne l'est pas)
**Derniere mise a jour :** 2026-11-20

## Role

Pass Robux "Thief" (149 R$, `Shop.Passes`, aussi dans la boutique). Quand un joueur marche sur les
boissons d'une autre base, la fenetre d'achat Roblox du pass s'ouvre directement (pas de menu du jeu).

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/ThiefService.luau` | serveur | Detecte le joueur sur un pad a jus d'une autre base, ouvre la fenetre d'achat, pose l'attribut `Thief` |
| `src/shared/Config/Shop.luau` | partage | Pass `Thief` : prix, `passId` (0 = pas cree sur Roblox) |
| `src/shared/Config/Gameplay.luau` | partage | `ThiefPromptCooldown`, message `ThiefOwned` |

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

## Remotes

Aucun : le serveur lit la position du personnage.

## Donnees sauvegardees

Aucune : Roblox garde le pass.

## Configuration

- `Gameplay.ThiefPromptCooldown` (8 s), `Gameplay.Messages.ThiefOwned`.
- `Shop.Passes` cle `Thief` : `passId` a remplir une fois le pass cree sur Roblox.

## Problemes connus / a faire

- `passId = 0` : la vraie fenetre Roblox n'apparaitra qu'une fois le pass cree et son id mis dans `Shop.luau`.
- Le vol lui-meme (prendre les jus d'un autre, garde-fous de `docs/game-design.md`) n'est pas code.
- Pas teste a 2 joueurs dans Studio.
