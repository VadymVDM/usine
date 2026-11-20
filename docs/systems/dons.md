# Systeme : Dons (urne + tableau TOP DONORS)

**Statut :** en cours (coin + fenetre testes en Studio le 2026-11-20 ; produits Robux pas crees, aucun vrai don teste)
**Derniere mise a jour :** 2026-11-20

## Role

Un coin "dons" au rez-de-chaussee de chaque base : une urne en verre pleine de billets sur une petite
table, et un grand panneau en bois "TOP DONORS" avec les 8 plus gros donateurs (tous serveurs, depuis
toujours). Les dons sont des pourboires en Robux, facultatifs, sans rien en echange.
Idee demandee par l'utilisateur le 2026-11-20 (captures d'un autre jeu, style seulement).

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/shared/Config/Donations.luau` | partage | Montants (Robux + `productId`), noms des DataStores, rafraichissement, textes, `Format` (14,355) |
| `src/server/Services/ReceiptService.luau` | serveur | **Seul** proprietaire de `MarketplaceService.ProcessReceipt` ; `Register(productId, handler)` |
| `src/server/Services/DonationService.luau` | serveur | Recus des dons, classement, tableau de chaque base, prompt de l'urne, attribut `DonatedRobux` |
| `src/client/Controllers/DonationController.luau` | client | Fenetre DONATIONS (8 boutons verts), demande d'achat a Roblox |
| `tools/build-map/02i-base-donations.luau` | Studio | Construit `ServerStorage.BaseTemplate.Donations` (Rug, Board, Table, Jar). Tapis x 1.1-7.5, z 42-63 (reduit le 2026-11-20 pour laisser toute la porte d'entree x 8-18 a l'allee) |

## Fonctionnement

Joueur : il voit l'urne "Donations!" a gauche en entrant (mur x 0 -> 1, entre la porte de la terrasse
et le bar a jus), appuie sur E ("Donations / Leave a tip"), choisit un montant, confirme dans la
fenetre de Roblox. Message "Thank you for your 100 R$ tip!" ; les autres joueurs du serveur voient
"<Nom> tipped 100 R$!". Le tableau se met a jour quelques secondes apres.

Code :

1. `DonationService:Start` pose le prompt `DonatePrompt` sur `Donations.Jar.PromptAnchor` de chaque
   base (le client ne le montre que dans SA base, comme tous les prompts).
2. Le client ouvre la fenetre et appelle `MarketplaceService:PromptProductPurchase`. Aucun remote :
   le client ne peut rien declarer, seul le recu de Roblox compte.
3. Recu : `ReceiptService` -> `DonationService` : `UpdateAsync` sur la cle `u<UserId>` du DataStore
   `Donations_v1` : `{ Total, Receipts }`. Si le `PurchaseId` est deja dans `Receipts`, rien n'est
   ajoute (jamais compte deux fois) et le recu est quand meme valide. Sinon Total += montant et le
   `PurchaseId` est garde (50 derniers). Erreur -> `NotProcessedYet` (Roblox redonnera le recu).
4. Ensuite seulement : classement (`OrderedDataStore` `DonationRanking_v1`, cle `<UserId>`, valeur
   jamais baissee), attribut `DonatedRobux` du joueur, messages. Si le classement echoue, il est
   reessaye au prochain rafraichissement (le don est deja sauvegarde).
5. Toutes les 60 s (3 s apres un don) : `GetSortedAsync` (8 premiers), noms
   (`GetNameFromUserIdAsync`, en cache), ecrits dans `Board.Panel.Display.Rows.RowN`
   (`Rank`, `Avatar` = tete `rbxthumb://`, `PlayerName`, `RobuxIcon`, `Amount`) de chaque base.

## Recus (ReceiptService)

- Un seul `ProcessReceipt` dans tout le jeu. Tout futur produit Robux (boosts, packs d'argent,
  offres) doit s'enregistrer avec `ReceiptService.Register(productId, handler)` dans son `Init`,
  jamais ecrire `ProcessReceipt` ailleurs.
- Le handler renvoie `true` seulement quand l'achat est ecrit de facon durable et une seule fois
  (PurchaseId deja vu = succes). Produit inconnu, erreur ou `false` -> `NotProcessedYet`.

- `ReceiptService.OnGranted(hook)` (2026-11-20) : appele apres chaque achat accorde ; utilise par
  `LeaderboardService` pour compter les Robux payes (`classements.md`). false -> `NotProcessedYet`.

## Remotes

Aucun. Prompt E `DonatePrompt` : cote client seulement (ouvre la fenetre).

## Donnees sauvegardees

Pas dans le profil du joueur (`DataService` pas touche, pas de changement de SchemaVersion) :

- DataStore `Donations_v1`, cle `u<UserId>` : `{ Total = number, Receipts = { string } }`.
- OrderedDataStore `DonationRanking_v1`, cle `<UserId>` : Total (entier).

Le rebirth et le "Reset All" admin n'effacent pas les dons (c'est de l'argent reel).

## Configuration

`src/shared/Config/Donations.luau` : `Amounts` (5, 10, 25, 50, 100, 500, 1000, 10000 R$),
`BoardRows` (8, doit egaler les lignes construites par 02i), `RefreshSeconds`, textes.

## Problemes connus / a faire

- **Produits pas crees** : les 8 `productId` sont a 0 -> boutons "Donations: coming soon!". A creer
  sur le Creator Dashboard (Monetization > Developer Products, un par montant), puis mettre les ids
  dans `Config/Donations.luau`.
- **Teste en Studio le 2026-11-20 (PC)** : 02i lance, place sauvegardee (version 122) ; tour en
  apercu (preview-tower) : 0 z-fighting et 0 piece qui chevauche le mur ou l'etage 1 ; capture du
  panneau rempli a la main (apercu) ; en jeu : prompt "Donations / Leave a tip" sur l'urne de SA
  base, fenetre DONATIONS ouverte (capture), tableau "Be the first!", classement lu sans erreur
  (vrai DataStore), console sans erreur.
- **Pas teste** : le bouton "coming soon" (clic), le telephone, et un vrai don (recu, merci, tableau
  mis a jour) : il faut un productId. Faire un achat test en Studio (gratuit, mais il ecrit dans le
  vrai DataStore : le don test apparaitra dans le classement, a effacer ensuite).
- Si `02a` est relance, relancer `02i` ensuite (sinon le coin disparait du modele).
- En Studio sans acces API : DataStore indisponible -> le recu reste en attente, tableau vide
  ("Be the first!").
- Le tableau est ecrit par le serveur dans le monde : avec StreamingEnabled il arrive avec la base.
