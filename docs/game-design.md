# Game design : Mon usine de boissons

> Version v7 (2026-11-19). Historique dans `docs/journal/`.
> **[A VALIDER]** = proposition pas encore confirmee par l'utilisateur. Le reste est decide.
> Reference : skills `roblox-game-design`, `roblox-player-psychology`, `roblox-monetization`.
> Les chiffres sont des exemples : les vrais vont dans `src/shared/Config/` et s'equilibrent en test.

## Langue

**Tout le jeu est en anglais** (textes, boutons, noms). Traduction automatique de Roblox activee
(voir "Traduction"). La doc et les commentaires restent en francais.

## En une phrase

**Ton arbre fait tomber des fruits au hasard, tu en fais des jus et des cocktails, des clients les
achetent, tu ameliores ton arbre pour avoir des fruits plus rares.**

Regle d'or : tout ce qu'on achete sert a gagner plus d'argent. Rien ne se revend, rien ne devient inutile.

## Nom du jeu [A VALIDER]

Les jeux qui percent en ce moment ont un nom **"Verbe + a + Nom"** : Steal An Egg (n°1 en
novembre 2026), Steal a Brainrot, Grow a Garden, 99 Nights in the Forest.
- **Finalistes : "Sell a Juice" (prefere par l'utilisateur) ou "Make a Juice".** Choix final plus tard.
- Eviter "Steal a ..." : le vol est un pass payant, pas le coeur du jeu (nom trompeur).
- Verifier que le nom n'est pas deja pris sur Roblox avant de publier.

## La boucle

**Fruits -> boissons -> argent -> ameliorer -> agrandir (zones 1, 2, 3) -> rebirth -> recommencer plus vite.**

| Zone | Le frein | Ce qui le fait sauter |
|---|---|---|
| 1. Le stand | Le joueur fait tout a la main | Employes |
| 2. Le bar a cocktails | Les jus valent peu | Cocktails (plus chers) |
| 3. La terrasse | Les clients sont lents | Tables + tapis roulant de vente |

## Zone 1 : le stand

1. **L'arbre** fait tomber un fruit toutes les X secondes, tire au hasard selon son niveau.
2. **Ramasser** : le joueur marche sur les fruits (pas d'outil, pas de clic). Ils s'empilent
   au-dessus de sa tete. Il marche sur les **bacs** : tout est depose et trie.
3. **Presser** : le presse-fruits prend 1 fruit = 1 jus. **Prix du jus = valeur du fruit.**
   Les jus s'empilent a cote du presse-fruits (**limite** : X jus, ameliorable).
4. **Poser** : le joueur prend les jus et les pose sur le **comptoir** (limite ameliorable).
5. **Vendre** : un client prend un jus et **laisse l'argent sur le comptoir**.
6. **Encaisser** : le joueur marche sur le **tas d'argent** pour le ramasser (pluie de billets + son).
   Gratuit : toujours a la main. Payant : le **Collecteur automatique** (pose juste a cote du tas d'argent).
7. **Employes** (achetes avec l'argent du jeu) : ramasseur, puis presseur, puis serveur (pose les jus).

Garde-fou : maximum ~30 fruits au sol. Au-dela : "Tree full!" (pas de lag, pousse a embaucher).

## L'arbre et les fruits

Detail complet (100 fruits, raretes, valeurs, index) : [systems/fruits.md](systems/fruits.md).

- **100 fruits = 10 raretes x 10 fruits** (decide). Au debut, seulement des pommes ; l'orange et la
  banane arrivent tres vite.
- Un seul arbre, 2 ameliorations : **Luck** (chaque niveau ajoute le fruit suivant, avec une petite
  chance) et **Speed**. Tableau d'ameliorations a cote de l'arbre.
- Un nouveau fruit tombe pour la premiere fois = "NEW FRUIT!" + il entre dans l'**Index**.
- **Limite de l'arbre** : le Luck s'arrete au dernier fruit des raretes ouvertes. Pour aller plus
  loin il faut **renaitre** : chaque rebirth ouvre la rarete suivante (0 rebirth = 3 raretes).
- Gros nombres affiches avec suffixes (K, M, B, T...).
- Robux : on vend de la **chance** (boosts, pass), pas des raretes entieres (sinon "pay to win").

## Zone 2 : le bar a cocktails

- Machine a cocktails avec **3 cases cliquables** (un fruit par case, seulement fruits debloques).
- Prix du cocktail = somme des 3 fruits ; **x2 si les 3 fruits sont identiques** (decide).
- Les cases se servent en premier dans les bacs (fruit reserve, visible) ; le presse-fruits prend
  le reste. Une case qui attend affiche le fruit en transparence. Le serveur attribue chaque fruit une fois.
- On peut acheter plus de machines.

## Zone 3 : la terrasse

- Tables : des clients achetent 2-3 boissons d'un coup.
- Tapis roulant de vente : les boissons partent le long de la route, les clients qui passent les achetent.
- L'arbre reste le vrai frein : on ne vend que ce qu'il produit.

## Les clients

- Chaque base a ses propres clients (personne ne vole les clients d'un autre).
- Ameliorations : vitesse des clients, nombre de clients.
- Le serveur decide des ventes ; les clients visibles sont surtout de l'affichage.

## Rebirth

- Condition : avoir les 3 zones + un montant d'argent.
- **On perd tout** : argent, zones, ameliorations, employes, niveau de l'arbre.
- **On garde** : multiplicateur d'argent permanent (x2, x3...), les **passes et boosts achetes en
  Robux**, l'**Index**, et on **debloque la rarete suivante**. Signe visible (couleur de l'arbre, titre).
- Chaque rebirth coute plus cher.
- A cote du bouton Rebirth : **"Rebirth & keep your cash"** en Robux (produit) : on renait sans
  perdre son argent. Risque : garder tout l'argent + le multiplicateur accelere beaucoup ;
  prix a monter avec le niveau du rebirth.

## Guider le joueur (choix utilisateur)

- **Pas de barre d'objectif en haut** (trop d'infos a l'ecran).
- **Fleches 3D animees** qui montrent ou aller, + un **chemin lumineux au sol** (du joueur a la cible).
- Le bouton ou l'objet a utiliser **brille et pulse** (Highlight + petite fleche qui rebondit dessus).
- Le guidage accompagne tout le tutoriel, puis **revient a chaque nouveau deblocage** (nouvelle
  zone, nouvelle machine, rebirth), puis se retire pour laisser le joueur faire seul.

## Premiere session (cinematique + 30 premieres minutes)

Plan complet : [first-session.md](first-session.md) [A VALIDER] : cinematique de 8-10 s passable,
tutoriel par fleches (premier achat avant 35 s), puis une nouveaute toutes les 1 a 3 minutes
(nouveaux fruits, employes, zone 2 vers 16 min, premier fruit Rare vers 20 min).

## Carte

6 bases par serveur, 3 de chaque cote d'une route. Serveur de 6 joueurs. Base attribuee automatiquement.

```
   [Base 1]      [Base 2]      [Base 3]
 ==SPAWN======== ROUTE (clients) ========
   [Base 4]      [Base 5]      [Base 6]
```

```
 +---------------------------------------------+
 |  ARBRE  -> fruits au sol                     |
 |  BACS (1 par fruit)    | ZONE 2 : COCKTAILS  |
 |  PRESSE-FRUITS + jus   | (mur ferme + prix)  |
 |  [boutons sur le mur]  |                     |
 +== COMPTOIR + ARGENT ===+== ZONE 3 TERRASSE ==+
                  ROUTE (clients)
```

## Interface

Detail et etat : [systems/interface.md](systems/interface.md).

- A gauche : **Shop** et **Index** (icones), argent en bas a gauche (+ jaune pour les packs).
- En haut : engrenage Settings (barre Roblox).
- A droite : **offres limitees** (10 min visibles / 2 min cachees, minuteur rouge, reduction sur
  certaines) ; clic -> fenetre "Limited Offer!" -> confirmation de paiement Roblox.
- A l'arrivee : ecran **"Welcome Back!"** (gains hors ligne, CLAIM / x2).
- **Pastille** (petit rond rouge, contour noir) sur un bouton quand il y a du nouveau.
- Ameliorations sur les murs de la base : **chaque bouton a 2 prix** (argent du jeu / Robux).
- Classement du serveur (leaderstats) : argent + rebirths.
- Style visuel : [style.md](style.md). Jeu en paysage uniquement.

## Monetisation

Regles : le jeu doit etre complet sans payer. Pas de caisse aleatoire payante. Le serveur
donne toujours l'avantage (jamais le client). Detail technique avec `roblox-monetization` au moment de coder.

### GamePasses (permanents) [prix A VALIDER]

| Pass | Effet | Prix propose |
|---|---|---|
| VIP | Name tag VIP + tag dans le chat | 149 |
| x3 Cash | Argent x3 pour toujours | 399 |
| Drink Master | Chance x2 d'avoir des fruits rares | 249 |
| Greedy Customers | Chaque client achete 2 boissons au lieu d'1 | 199 |
| Speed Master | Vitesse de marche x2 + clients x2 plus rapides | 99 |
| Auto Collect | L'argent du comptoir arrive tout seul (machine a cote du tas d'argent) | 149 |
| Thief | Voler des boissons pretes chez les autres (avec garde-fous) | 149 |
| Rebirth Master | Garde le niveau de l'arbre apres un rebirth (+ peut-etre rebirth 50 % moins cher [A VALIDER]) | 299 [A VALIDER] |

"Drink Master" fait la chance (pas l'argent) pour ne pas doubler "x3 Cash".

### Produits (a acheter plusieurs fois)

| Produit | Prix |
|---|---|
| Doubler les gains hors ligne (ecran de retour) | 9 |
| Boost x2 argent : 15 min / 30 min (meilleure valeur) | 9 / 16 |
| Boost x2 vitesse des clients : 15 min / 30 min | 9 / 16 |
| Boost x2 chance de l'arbre : 15 min / 30 min | 9 / 16 |
| Packs d'argent (4 tailles, "Best Value" sur le plus gros) | 25 / 79 / 199 / 499 [A VALIDER] |
| Rebirth & keep your cash (a cote du bouton Rebirth) | prix selon le niveau [A VALIDER] |
| Amelioration d'un niveau en Robux (a cote de chaque bouton du mur) | petit prix, monte avec le niveau |

- **Packs d'argent = X minutes de gains actuels du joueur**, pas un montant fixe (sinon un pack
  devient inutile apres 1 heure de jeu).
- Les boosts du meme type s'additionnent en temps (15 min + 15 min = 30 min).

### Offrir (cadeaux) (decide)

- **Tout ce qui s'achete en Robux peut etre offert** a un joueur du meme serveur.
- Un **bouton cadeau** juste a cote de chaque bouton d'achat : on choisit le joueur dans la liste
  du serveur, on paie, il recoit l'objet + un message "<Name> sent you a gift!" (effet + son).
- Technique : Roblox ne permet pas d'acheter un GamePass pour quelqu'un d'autre. Chaque cadeau est
  donc un **produit** ("Gift: x3 Cash") ; le serveur donne l'avantage au receveur et l'enregistre
  dans SA sauvegarde. Le jeu doit considerer "pass achete" OU "pass recu en cadeau".
- Si le receveur a deja le pass : cadeau refuse avant le paiement (bouton grise).
- Si le receveur quitte pendant l'achat : le cadeau est garde et donne a sa prochaine connexion.

### Proposer au bon moment (offres contextuelles)

| Moment | Offre |
|---|---|
| Retour dans le jeu | x2 gains hors ligne (9) |
| "Tree full!" ou fruits qui s'accumulent | Boost / employe en Robux |
| Il manque un peu d'argent pour un bouton | Le prix Robux est deja a cote du bouton + pack d'argent |
| Un fruit tres rare vient de tomber | Boost chance x2 15 min |
| Comptoir plein d'argent pas ramasse | Auto Collect |
| Rebirth presque atteint | Skip Rebirth |
| Clients en file d'attente | Boost vitesse clients |

Garde-fous : **jamais de popup pendant les 5 premieres minutes** (on donne d'abord, on vend apres) ;
**maximum 1 popup toutes les ~5 minutes** ; toujours un bouton "Non merci" bien visible.
Sinon les joueurs se sentent harceles et partent.

## Gains hors ligne

Oui (decide). Calcul simple : argent/minute moyen x temps absent, plafond ~8 h, moins que jouer.
Ecran au retour : "While you were away, you earned X" + bouton "x2 for 9 R$".

## Traduction

- Roblox traduit automatiquement les textes de l'interface (Automatic Text Capture + traduction
  automatique), a activer dans le Creator Hub > Localization. Langues : dont francais, allemand,
  portugais, japonais, coreen, chinois...
- Limites : seulement les textes d'interface (pas les panneaux 3D ni les messages) ; les textes avec
  des nombres qui changent ("You earned 1.2M") se traduisent mal -> utiliser une table de traduction
  avec des cles pour ceux-la. A traiter au moment de l'interface.

## Sauvegarde

Argent, niveau rarete et vitesse de l'arbre, fruits/raretes debloques, employes et niveaux, zones,
machines a cocktails et recettes, rebirths, limites (jus, comptoir), boosts en cours (temps restant),
heure de deconnexion. Pas les fruits au sol, ni les boissons, ni l'argent pas encore ramasse.

## A faire et questions ouvertes

Voir [roadmap.md](roadmap.md) (phases, decisions encore ouvertes, dette technique).

## Decisions

| Date | Decision | Pourquoi |
|---|---|---|
| 2026-11-18 | Pas de "boire les boissons" | Trop complique |
| 2026-11-18 | Pas de collection : debloquer = gagner plus | Une seule logique (2026-11-19 : un Index sert de vitrine des fruits decouverts, sans recompense a part) |
| 2026-11-18 | Un seul arbre qu'on ameliore (rarete) | Plus automatique, rien d'inutile |
| 2026-11-18 | Ramasser les fruits a la main, puis employe | Geste actif puis automatique |
| 2026-11-18 | Fruits en rarete (pas en kilos) | Plus clair |
| 2026-11-19 | Zone 1 = 1 fruit = 1 jus ; cocktails en zone 2 | Simple au debut |
| 2026-11-19 | Machine a cocktails a 3 cases cliquables | Garder "creer sa boisson" |
| 2026-11-19 | 3 zones puis rebirth (on perd tout sauf multiplicateur et achats Robux) | Choix utilisateur |
| 2026-11-19 | 6 bases autour d'une route | Choix utilisateur |
| 2026-11-19 | Interface : Shop + Index a gauche, offres a droite, argent en bas a gauche | Peu de boutons |
| 2026-11-19 | Tout le jeu en anglais + traduction auto Roblox | Toucher le plus de joueurs |
| 2026-11-19 | Gains hors ligne + bouton x2 a 9 R$ | Retour du joueur + premier achat |
| 2026-11-19 | Guidage par fleches 3D et objets qui brillent, pas de barre d'objectif | Moins d'infos a l'ecran |
| 2026-11-19 | Classement du serveur | Choix utilisateur |
| 2026-11-19 | Argent laisse sur le comptoir, ramasse a la main ; Auto Collect payant | Choix utilisateur |
| 2026-11-19 | Boosts x2 argent / vitesse clients : 9 R$ (15 min), 16 R$ (30 min) | Choix utilisateur |
| 2026-11-19 | 100 fruits = 10 raretes x 10 ; au debut seulement des pommes | Choix utilisateur |
| 2026-11-19 | Luck de l'arbre plafonne ; chaque rebirth ouvre une rarete | Donne une raison de renaitre |
| 2026-11-19 | Bouton Index (fruits decouverts) a gauche, a la place de Tree | Choix utilisateur |
| 2026-11-19 | Cocktail : x2 seulement si 3 fruits identiques | Choix utilisateur |
| 2026-11-19 | Rebirth Master garde le niveau de l'arbre ; "Rebirth & keep your cash" en Robux | Choix utilisateur |
| 2026-11-19 | Style blocky / studs, couleurs vives, pas de z-fighting (voir style.md) | Choix utilisateur |
| 2026-11-19 | Tout achat Robux peut etre offert a un joueur du serveur (bouton cadeau a cote) | Choix utilisateur |
| 2026-11-19 | Ecran "Welcome Back!" a l'arrivee (gains hors ligne, CLAIM / x2 en Robux) | Choix utilisateur |
| 2026-11-19 | Pastille de notification (petit rond rouge, contour noir) sur un bouton quand il y a du nouveau | Choix utilisateur |
| 2026-11-19 | Offres a droite = offres limitees : 10 min visibles / 2 min cachees, minuteur rouge, reduction sur certaines seulement, fenetre de confirmation | Choix utilisateur |
