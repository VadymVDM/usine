# Systeme : Lucky Cash (tas d'argent cache, a acheter en Robux)

**Statut :** en cours (teste en playtest Studio PC a 1 joueur le 2026-11-20 ; produit Robux pas cree)
**Derniere mise a jour :** 2026-11-21

## Role

De temps en temps, sur un etage ouvert de sa tour, le joueur voit une **liasse de billets 3D qui
tourne** ("LUCKY CASH!" + montant au-dessus). Marcher dessus ou E ouvre une fenetre "WOW! You found
a secret cash stash!" : un gros montant d'argent du jeu, adapte a sa progression, contre quelques
Robux. But : donner envie d'acheter avec une offre vraiment rentable (bien plus que la boutique).
Demande utilisateur du 2026-11-20.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/shared/Config/LuckyCash.luau` | partage | Prix, productId, formule du montant (`Amount`), place du tas, rayons, delais |
| `src/server/Services/LuckyCashService.luau` | serveur | Attribut `LuckyCashAmount`, remote `LuckyCashBuy`, recu Robux (ajout de l'argent une seule fois) |
| `src/client/Controllers/LuckyCashController.luau` | client | Liasse 3D locale qui tourne (une seule a la fois, etage tire au hasard), apparition rare, touche E, ouverture en marchant dessus, fenetre "Lucky Find!" |
| `src/server/Services/DebugService.luau` | serveur | `Debug.Call:Invoke("LuckyCash", "Get" / "Grant", nom)` (Studio) |

## Fonctionnement

Cote joueur :

1. Dans l'allee entre l'escalier et le verger, contre l'escalier (voie B) et pres du mur x 109
   (repere de l'etage x 96, z 80.5 ; avant x 78, z 81.3, deplace le 2026-11-21) : une liasse de
   5 billets verts avec une bande claire marquee "$", penchee, qui tourne (un tour en 4 s) et monte /
   descend un peu, a ~1.8 stud du sol. Plus de disque jaune au sol, de lumiere ni d'etincelles
   (2026-11-21 : "la lueur sur le sol, bizarre"). Pas de Neon.
   Etiquette : "LUCKY CASH!" (jaune) + "+$12.5K" (vert), qui flotte.
   **Apparition rare** : une seule liasse a la fois, sur un etage ouvert tire au hasard ; premiere
   apparition 2 min apres l'arrivee, reste 2 min, revient 6 a 10 min plus tard (au hasard).
2. Marcher dessus (moins de 4 studs) ouvre la fenetre, si aucun autre menu n'est ouvert, au plus
   une fois par minute, et seulement apres s'etre eloigne de 9 studs. E ("Lucky Cash / Open")
   l'ouvre toujours.
3. Fenetre "Lucky Find!" : "WOW! You found a secret cash stash!", billets qui tanguent devant des
   rayons qui tournent, "+$12.5K", "Hidden on Floor N", "= 45 MIN of profit!" (vrai calcul : montant
   / gains theoriques ; "SUPER DEAL!" si les gains sont 0), gros bouton vert [Robux] 29 qui pulse.
   Son "WelcomeBack" a l'ouverture.
4. Achat paye : gerbe de billets vers le HUD (CashController), la fenetre se ferme, la liasse
   disparait et reviendra au prochain tirage (6 a 10 min).

Cote code :

- Montant (serveur, `LuckyCash.Amount`) = 45 min des gains theoriques de toute la tour
  (`CustomerService.GetIncomePerSecond`), **plafonne** a 0.4 x prix du prochain etage du joueur
  (`Floors.Prices`), jamais sous $600 (`MinAmount` ; $1 500 avant les prix des etages / 2 du
  2026-11-20). `MinAmount` $600 depuis l'etage 2 a $1.5K ; etage 1 : $600 (0.4 x $1.5K). Arrondi a 3 chiffres (le "+$12.5K" affiche = le montant donne).
  Pose dans l'attribut joueur `LuckyCashAmount` toutes les `Gameplay.IncomeAttributeSeconds` (10 s).
- Bouton -> `LuckyCashBuy` -> le serveur recalcule le montant, le note (`pending`, garde 10 min)
  puis ouvre la fenetre d'achat Roblox (`PurchasePrompt.Product`). productId 0 : "Robux purchases:
  coming soon!".
- Recu (`ReceiptService`) : montant note (sinon recalcule), ajoute a `Data.Money` (plafond
  `GameConfig.MaxMoney`) via `DataService.GrantPurchaseOnce` (une seule fois par PurchaseId, attend
  la sauvegarde) ; puis Feedback "Cash" `{ amount, from, bills = 24, lucky = true }`.
- La rotation est faite a chaque image (Heartbeat) seulement quand la liasse est visible (connexion
  coupee a sa disparition).
- La liasse est locale (dossier `Workspace.LuckyCashPiles`, cree par le client) : pas de collision, pas
  de requete, aucun effet sur le jeu. Pas de remote "ouvrir" : tout ce qui compte est decide au
  clic d'achat et a la reception du paiement.

## Remotes

| Nom | Sens | Arguments | Verifications serveur |
|---|---|---|---|
| `LuckyCashBuy` | client -> serveur | aucun | delai 1 s, sauvegarde chargee ; montant calcule par le serveur ; produit choisi par le serveur |
| `Feedback` ("Cash", lucky = true) | serveur -> client | `{ amount, from, bills, lucky }` | (envoye seulement apres un recu accorde) |

## Donnees sauvegardees

Rien de nouveau : `Money` et `PurchaseIds` (deja existants).

## Configuration

`src/shared/Config/LuckyCash.luau` : `Price` (29, affiche), `ProductId` (0), `Minutes` (45),
`FloorShare` (0.4), `MinAmount` (600), `Spot`, `TouchRadius`, `RearmRadius`,
`AutoOpenCooldownSeconds` (60), `PromptDistance`, `FirstSpawnSeconds` (120), `VisibleSeconds` (120),
`SpawnMinSeconds` (360), `SpawnMaxSeconds` (600). Taille / vitesse de rotation : constantes en tete de
`LuckyCashController` (`PILE_SCALE` 2, `SPIN_SPEED`, `HOVER`, `BOB`). **Prix et montants A VALIDER.**
Comparaison : Mega Cash (99 R$) = 60 min ou 0.5 etage ; Lucky Cash (29 R$) = 45 min ou 0.4 etage
(~2.7x plus d'argent par Robux).

## Problemes connus / a faire

- **Creer le Developer Product** (29 R$) sur Roblox et mettre son id dans `ProductId` ; le prix
  affiche (`Price`) doit etre le meme que sur Roblox.
- Vrai achat Robux pas teste (seulement `Debug "LuckyCash" "Grant"` : +montant exact, tas caches).
- Le tas peut etre achete sans limite (developer product repetable) ; a surveiller pour l'economie.
- Pas teste : telephone (taille de la fenetre, bouton), 2 joueurs, etages 3+.
- Rythme d'apparition (2 / 6-10 min) a valider en jeu : trop rare = personne ne la voit.
- Le minuteur repart a chaque arrivee (cote client) : pas de memoire entre deux sessions.
