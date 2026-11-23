# Game design : Mon usine de boissons

> Version v8 (2026-11-19, tour d'etages). Historique dans `docs/journal/`.
> **[A VALIDER]** = proposition pas encore confirmee par l'utilisateur. Le reste est decide.
> Reference : skills `roblox-game-design`, `roblox-player-psychology`, `roblox-monetization`.
> Les chiffres sont des exemples : les vrais vont dans `src/shared/Config/` et s'equilibrent en test.

## Langue

**Tout le jeu est en anglais** (textes, boutons, noms). Traduction automatique de Roblox activee
(voir "Traduction"). La doc et les commentaires restent en francais.

## En une phrase

**Tu construis une tour a jus : chaque etage a son arbre d'une rarete, tu en fais des jus purs,
des clients les achetent, tu automatises l'etage et tu achetes l'etage du dessus, plus rare.**

Jamais de melange de fruits (pas de smoothie, pas de cocktail) : **1 fruit = 1 jus pur**. C'est ce
qui distingue le jeu des jeux de smoothies existants (decide le 2026-11-19).

Regle d'or : tout ce qu'on achete sert a gagner plus d'argent. Rien ne se revend, rien ne devient inutile.

## Regle d'or du ressenti (decide le 2026-11-19, a respecter partout)

- Le jeu est **simple, satisfaisant, addictif, sans trop reflechir**.
- **Privilegier les clics** : s'approcher, cliquer, ramener. Rien de complique, aucune regle a lire.
- **Gagner de l'argent doit etre satisfaisant** (pluie de billets, son, chiffres qui montent).
- **Fabriquer les jus doit etre satisfaisant et logique** : de vraies machines animees (le mixeur
  tremble quand il mixe, les fruits passent sur un tapis), pas des pads abstraits.
- **Acheter = construire** : une machine pas encore achetee est **la vraie machine teintee bleu
  clair avec un contour** a sa place (pas un fantome tres transparent) ; on s'approche, on appuie
  sur **E**, elle se construit piece par piece.
- Les prochaines salles sont des **zones fermees** (vitre rouge transparente, cadenas, nom, prix ;
  E pour ouvrir).

### Decisions du 2026-11-19 (soir, demande de l'utilisateur)

- **Touche E (ProximityPrompt de Roblox) pour tout** : ramasser un fruit ("Apple / Pick up"),
  deposer a l'etagere, prendre les jus, les poser au comptoir, encaisser, acheter une machine,
  ouvrir une salle. Les **pads** restent seulement pour embaucher les employes (vert) et le pad
  Robux "Auto Collect" (violet). **Change le 2026-11-19 (plus tard)** : ramasser = marcher sur
  les fruits (plateau sur la tete) ; deposer les fruits, prendre / poser les jus, encaisser = pads.
  La touche E reste pour mixer, acheter / ameliorer et ouvrir une salle.
- **Inventaire en bas de l'ecran** pour les fruits (case par fruit, "x5", 20 max) ; plus de pile
  au-dessus de la tete. Les **jus** se portent dans les mains (pile devant le personnage, bras
  tendus) jusqu'au comptoir.
- Etagere : E = deposer tous les fruits ; chaque caisse affiche "x12". **Pas de vente de fruits crus.**
- Comptoir : on peut poser beaucoup de jus (10 au depart, +5 par niveau) ; les ventes dependent de
  la vitesse et du nombre de clients.
- **Tous les personnages en R6** avec les animations de base de Roblox : employes (tenue Roblox +
  tablier / casquette de couleur) et clients (vetements gratuits du catalogue Roblox). On doit voir
  les employes travailler (marcher, prendre, porter, poser).
- **Argent physique** : liasses de billets sur la table, qui s'envolent vers le joueur avec un
  "pop" a l'encaissement. Pad Robux "Auto Collect" a cote (pass 149 R$ A VALIDER).
- **Usine plus spacieuse** avec des zones delimitees (sol de couleur + panneau) : verger, etagere,
  bar a jus, vente.


## Nom du jeu [A VALIDER]

Les jeux qui percent en ce moment ont un nom **"Verbe + a + Nom"** : Steal An Egg (n°1 en
novembre 2026), Steal a Brainrot, Grow a Garden, 99 Nights in the Forest.
- **Finalistes : "Sell a Juice" (prefere par l'utilisateur) ou "Make a Juice".** Choix final plus tard.
- Eviter "Steal a ..." : le vol est un pass payant, pas le coeur du jeu (nom trompeur).
- Verifier que le nom n'est pas deja pris sur Roblox avant de publier.

## La boucle

**Fruits -> jus -> argent -> ameliorer l'etage -> employes -> acheter l'etage du dessus -> ... -> etage 10 -> rebirth -> recommencer plus vite.**

## La tour d'etages (decide le 2026-11-19, remplace les zones 1, 2, 3)

- **10 etages au lancement, 1 etage = 1 rarete** (etage 1 = Common ... etage 10 = la rarete la plus
  haute). Les 100 fruits sont tous utilises : **10 fruits par etage**.
- **Chaque etage fonctionne tout seul** : son arbre, son etagere, son ou ses mixeurs, sa table a
  jus, son comptoir, son tas d'argent, ses clients, ses employes. Rien ne voyage entre les etages.
- Le joueur joue a la main sur son **dernier etage** ; il embauche des employes et les **etages du
  dessous tournent tout seuls** (argent qui tombe de partout).
- **Acheter l'etage suivant** : escalier ferme par une vitre rouge (cadenas, nom, prix), E pour
  ouvrir, comme les anciennes salles fermees. On ne voit que les etages achetes + le suivant ferme
  (pas de tour vide de 10 etages : moins de pieces).
- Le joueur monte par un **escalier** qui part du milieu de l'usine et monte vers le mur de droite
  (decide le 2026-11-19) ; il apparait sur son etage le plus haut et un panneau "Floors" sur chaque
  palier l'emmene a un etage achete. Les jus ne quittent jamais leur etage.
- **Plan technique complet** (dimensions, 2 voies d'escalier, etage ferme, lag, sauvegarde) :
  [systems/tour-etages.md](systems/tour-etages.md).
- Idee ecartee : un grand trou ou tous les jus tombent au rez-de-chaussee (melangerait les raretes,
  et le joueur ferait tout au meme endroit).
- Plus tard, une mise a jour = **un nouvel etage** (11, 12...) avec 10 nouveaux fruits.
- Hauteur d'un etage : 36 studs (le plafond haut est garde).
- Annexe (decide le 2026-11-20) : la **terrasse** devient le hall de l'ascenseur des clients ; elle
  s'ouvre toute seule avec l'etage 2 et porte un panneau **Elevator** (Speed, Bigger Cabin : plus de
  ventes pour tous les etages 2+ ; depuis le 2026-11-20 : +4 % d'argent par vente et par niveau). Le **bar a cocktails** devient la **salle du Rebirth**, vitre
  rouge "Reach Floor 10", visible des le debut.
- Decide le 2026-11-20 : **un seul tas d'argent au rez-de-chaussee** (les ventes de tous les
  etages s'y ajoutent, un seul pad Collect Cash) ; clients des etages du haut par un **ascenseur
  vitre exterieur** + balcon ; un etage coute **~10-15 min de gains** ; **rebirth a l'etage 10**.
  2026-11-20 (revue de l'economie) : prix des etages / 2 (etage 2 = 2.5K) : l'arbre plafonne un
  etage vers 7-9 min, il restait ~8.5 min sans achat utile ; un etage = ~9 min pour un joueur qui
  achete bien, plus pour un vrai joueur. Puis (meme jour) courbe **progressive** (1.5K, 11K, 62K ...
  2.2B) + ascenseur = achat toujours utile des l'etage 2 : etage 2 ~10 min, ensuite ~11-16 min par
  etage, rebirth ~1 h 55 (joueur qui achete bien).

## Un etage (ex-"Zone 1 : le stand", meme fonctionnement a chaque etage)

1. **L'arbre** fait tomber un fruit toutes les X secondes, tire au hasard selon son niveau.
2. **Ramasser** : le joueur **marche sur les fruits** (pas de touche). Ils s'empilent en
   vrac sur un **plateau au-dessus de sa tete**. Il se tient sur le **pad "Drop Fruits"** devant
   l'etagere : tout est depose et trie (2026-11-19). Poser les jus au comptoir et encaisser
   l'argent : pareil, en se tenant sur les pads "Drop Juices" et "Collect Cash".
3. **Mixer** : le tapis remplit le bol du mixeur (5 fruits ; chaque mixeur a 5 niveaux : 8 / 12 / 16 / 20) ; le
   joueur appuie sur **E** : 2.5 s de mixage, puis **tous les jus sortent d'un coup** (1 fruit =
   1 jus, **prix du jus = valeur du fruit**). Jusqu'a 4 mixeurs (achetes) ; un operateur par
   mixeur appuie a la place du joueur quand le bol est plein. Les jus s'empilent sur la table a
   jus (**limite** : X jus, ameliorable).
4. **Poser** : le joueur prend les jus et les pose sur le **comptoir** (sans limite depuis le 2026-11-19 : on ameliore la vitesse et le nombre de clients).
5. **Vendre** : un client prend un jus et **laisse l'argent sur le comptoir**.
6. **Encaisser** : le joueur marche sur le **tas d'argent** pour le ramasser (pluie de billets + son).
   Gratuit : toujours a la main. Payant : le **Collecteur automatique** (pose juste a cote du tas d'argent).
7. **Employes** (achetes avec l'argent du jeu) : ramasseur, operateurs des mixeurs, serveur (pose les jus).

Garde-fou : maximum ~30 fruits au sol. Au-dela : "Tree full!" (pas de lag, pousse a embaucher).

## L'arbre et les fruits

Detail complet (100 fruits, raretes, valeurs, index) : [systems/fruits.md](systems/fruits.md).

- **100 fruits = 10 etages x 10 raretes** (decide le 2026-11-20, remplace "1 etage = 1 rarete").
  **Chaque etage a les 10 raretes**, de Common a Infinity : un fruit qui tombe tout le temps, un un
  peu plus rare, ... et un fruit tres tres rare. Chaque etage a donc son "jackpot".
- On garde les 100 fruits tels quels (nom, rarete, modele, effets) : on lit le tableau **par ligne**.
  Etage n = le n-ieme fruit de chaque rarete. Etage 1 : Apple, Strawberry, Dragon Fruit, Mangosteen,
  Golden Apple, Fire Mango, Angel Apple, Moon Melon, Error Apple, Rainbow Apple.
- **Valeur = surtout l'etage, un peu la rarete** : monter rapporte plus ; un fruit rare vaut plus
  qu'un commun du meme etage, mais beaucoup moins que sa rarete (sinon un Infinity a l'etage 1
  casserait l'economie).
- Chaque arbre a 2 ameliorations : **Luck** (rend les fruits rares plus frequents) et **Speed**.
  Tableau d'ameliorations a cote de l'arbre. Les boosts de chance (Robux) suivent la meme logique.
- **Collection** : la premiere fois qu'on ramasse un fruit, grosse animation de decouverte (voir
  [systems/fruits.md](systems/fruits.md)) et il entre dans l'**Index** (10 pages, une par etage).
- Pour gagner plus, on **achete l'etage du dessus**. Ancienne regle "chaque rebirth ouvre une rarete"
  remplacee le 2026-11-19, puis "1 etage = 1 rarete" remplacee le 2026-11-20.
- Gros nombres affiches avec suffixes (K, M, B, T...).
- Robux : on vend de la **chance** (boosts, pass), pas des raretes entieres (sinon "pay to win").

## Zone 2 : le bar a cocktails (ABANDONNE le 2026-11-19 : melange de fruits, remplace par les etages)

- Machine a cocktails avec **3 cases cliquables** (un fruit par case, seulement fruits debloques).
- Prix du cocktail = somme des 3 fruits ; **x2 si les 3 fruits sont identiques** (decide).
- Les cases se servent en premier dans les bacs (fruit reserve, visible) ; le presse-fruits prend
  le reste. Une case qui attend affiche le fruit en transparence. Le serveur attribue chaque fruit une fois.
- On peut acheter plus de machines.

## Zone 3 : la terrasse (ABANDONNE le 2026-11-19, remplace par les etages)

- Tables : des clients achetent 2-3 boissons d'un coup.
- Tapis roulant de vente : les boissons partent le long de la route, les clients qui passent les achetent.
- L'arbre reste le vrai frein : on ne vend que ce qu'il produit.

## Les clients

- Chaque base a ses propres clients (personne ne vole les clients d'un autre), et **chaque etage
  a les siens**.
- Ameliorations : vitesse des clients, nombre de clients.
- Le serveur decide des ventes ; les clients visibles sont surtout de l'affichage.

## Rebirth

- Condition : avoir l'**etage 10** + un montant d'argent (decide le 2026-11-20 ; avant : les 3 zones).
- **On perd tout** : argent, etages, ameliorations, employes, niveau des arbres.
- **On garde** : multiplicateur d'argent permanent (x2, x3...), les **passes et boosts achetes en
  Robux**, l'**Index**. Signe visible (couleur de l'arbre, titre).
- Chaque rebirth coute plus cher.
- A cote du bouton Rebirth : **"Rebirth & keep your cash"** en Robux (produit) : on renait sans
  perdre son argent. Risque : garder tout l'argent + le multiplicateur accelere beaucoup ;
  prix a monter avec le niveau du rebirth.
- **Code le 2026-11-20** (detail : [systems/rebirth.md](systems/rebirth.md)) :
  - Rebirth dans la salle du Rebirth (E sur la machine doree -> menu du pack "Now / After").
  - Prix : 10B, puis 20B, 30B... ; multiplicateur des ventes x2, x3, x4... (1 + rebirths).
    **Valides par l'utilisateur le 2026-11-20.**
  - On garde aussi le **menu Upgrade** (vitesse, plateaux) ; l'argent du tas d'en bas est encaisse
    avant le rebirth.
  - "Keep cash" : rebirth tout de suite **sans payer le prix** et en gardant l'argent (sert aussi de
    "Skip Rebirth") : 49 / 99 / 199 / 299 R$ selon le nombre de rebirths.
  - Rebirth Master : chaque etage rachete reprend son meilleur niveau d'arbre.
  - Signe visible : nametag (pseudo + "Rebirth N" en or, vu seulement par les autres, remplace le
    nom de Roblox ; demande utilisateur) + colonne Rebirths du classement +
    message "<Nom> reached Rebirth N!" aux autres joueurs. Couleur de l'arbre : pas faite.

## Guider le joueur (choix utilisateur)

- **Pas de barre d'objectif en haut** (trop d'infos a l'ecran).
- **Fleches 3D animees** qui montrent ou aller, + un **chemin lumineux au sol** (du joueur a la cible).
- **Visuel retenu (captures utilisateur, 2026-11-19)** : une **file de chevrons** blancs/bleu clair
  lumineux (style ">>>", un peu transparents, avec halo) qui part du joueur, a hauteur de taille, et
  va en ligne droite jusqu'a la cible. Les chevrons sont serres (un tous les ~1 studs), toujours
  tournes vers la camera, et defilent vers la cible. Piste technique : un `Beam` entre une
  `Attachment` du personnage et une sur la cible, texture chevron, `FaceCamera`, `TextureMode`
  Static/Wrap + `TextureSpeed` pour le defilement, `LightEmission` pour la lueur. Client seulement.
- **Quand il faut cliquer** (bouton, machine, objet) : l'objet recoit un **contour lumineux**
  (`Highlight`, contour epais qui pulse) et/ou une **fleche qui rebondit** au-dessus. Lequel des deux
  (ou les deux) : a choisir en testant dans Studio [A DECIDER].
- Le bouton ou l'objet a utiliser **brille et pulse** (Highlight + petite fleche qui rebondit dessus).
- Le guidage accompagne tout le tutoriel, puis **revient a chaque nouveau deblocage** (nouvelle
  zone, nouvelle machine, rebirth), puis se retire pour laisser le joueur faire seul.

## Premiere session (cinematique + 30 premieres minutes)

Plan complet : [first-session.md](first-session.md) [A VALIDER] : cinematique de 8-10 s passable,
tutoriel par fleches (premier achat avant 35 s), puis une nouveaute toutes les 1 a 3 minutes
(nouveaux fruits, employes, etage 2 vers 16 min (a revoir pour la tour), premier fruit Rare vers 20 min).

## Carte

**A revoir pour la tour** : chaque base devient une tour (etage 1 au sol). Le plan ci-dessous est
celui d'avant les etages.

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
- A droite : **une offre limitee a la fois** (3 min visible, minuteur rouge, puis 30 s sans offre
  avant la suivante ; rien les 90 premieres secondes ; pas de reduction affichee) ; clic -> fenetre
  "Limited Offer!" -> confirmation de paiement Roblox.
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
| Drink Master | Chance x2 d'avoir des fruits rares (en vrai ~+15 % d'argent + l'Index plus vite) | 199 (2026-11-23, 249 avant) |
| Greedy Customers | Chaque client achete 2 boissons au lieu d'1 | 199 |
| Speed Master | Vitesse de marche x2 + clients x2 plus rapides | 99 |
| Auto Collect | L'argent du comptoir arrive tout seul (machine a cote du tas d'argent) | 149 |
| Auto Sell | Les jus de la table vont tout seuls au comptoir, vite (pad violet qui remplace le pad du Waiter une fois le Waiter embauche, 2026-11-20) | 199 |
| Thief | Voler des boissons pretes chez les autres (avec garde-fous) | 149 |
| Rebirth Master | Garde le niveau de l'arbre apres un rebirth : chaque etage rachete reprend son meilleur niveau d'arbre (code le 2026-11-20) (+ peut-etre rebirth 50 % moins cher [A VALIDER]) | 199 (2026-11-23, 299 avant) |

"Drink Master" fait la chance (pas l'argent) pour ne pas doubler "x3 Cash".

**Regles de prix (revue du 2026-11-23, "qu'ils achetent, que ce soit renta") :**
- Chaque achat doit etre une bonne affaire : mesure = minutes de gains par Robux. Reference : boost
  2x Money 15 min a 9 R$ = 1.67 min / R$.
- Packs d'argent : plus le pack est gros, plus il est rentable (0.79 / 1.22 / 1.86 / 2.41 min / R$).
- Une offre limitee (minuteur) vaut toujours MIEUX que la meme chose en boutique.
- Un produit plus cher donne toujours plus qu'un moins cher (Mega Cash 49 > Lucky Cash 19).
- Les montants d'argent ne comptent pas les boosts en cours (boost x3 + pack != pack x3).
- Un achat Robux ne donne jamais "rien" (amelioration deja au max : autre amelioration ou argent).

**Techniques en place (2026-11-23), toujours honnetes :**
- Offre au moment du besoin : etage trop cher -> "Almost there!" avec le pack qui couvre ce qui manque.
- Essai gratuit de 3X CASH (3 min par session) puis le VRAI surplus gagne + "Keep it forever?".
- Ultimate Bundle 799 R$ (4 passes, vraie reduction de 15 %) : ancre les prix, 3X CASH parait moins cher.
- Interdit : faux minuteurs, faux anciens prix, caisses payantes, fenetres qui bloquent le jeu, messages
  qui culpabilisent.

### Produits (a acheter plusieurs fois)

| Produit | Prix |
|---|---|
| Doubler les gains hors ligne (ecran de retour) | 9 |
| Boost x2 argent : 15 min / 30 min (meilleure valeur) | 9 / 16 |
| Boost x2 vitesse des clients : 15 min / 30 min | 9 / 16 |
| Boost x2 chance de l'arbre : 15 min / 30 min | 9 / 16 |
| Packs d'argent (15 min / 1 h / 4 h / 12 h, "Best Value" sur le 12 h, vraiment le meilleur rapport ; chaque pack plus rentable que le precedent) | 19 / 49 / 129 / 299 (2026-11-23) |
| Rebirth & keep your cash (a cote du bouton Rebirth) | 49 / 99 / 199 / 299 selon le nombre de rebirths (0 / 1-4 / 5-14 / 15+) (2026-11-23) |
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

Argent, **etages achetes**, et **par etage** : Luck et Speed de l'arbre, mixeurs, employes et
niveaux, limites ; fruits decouverts (Index), rebirths, limites (jus), boosts en cours (temps restant),
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
| 2026-11-19 | Fleches de guidage = file de chevrons lumineux du joueur a la cible (Beam) | Visuel montre par l'utilisateur |
| 2026-11-19 | Classement du serveur | Choix utilisateur |
| 2026-11-19 | Argent laisse sur le comptoir, ramasse a la main ; Auto Collect payant | Choix utilisateur |
| 2026-11-20 | Employe Waiter retire, remplace par le pass Auto Sell (199 R$, pad dans l'usine) | Choix utilisateur |
| 2026-11-20 | Waiter de retour en argent du jeu ($400, lent, 9 jus) ; son pad devient le pad violet Auto Sell des qu'il est embauche | Sinon un etage ne s'automatisait pas sans Robux ; choix utilisateur |
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
| 2026-11-19 | Usine en interieur agrandie, machines fantomes bleues a acheter (clic), salles fermees, mixeur anime | Choix utilisateur : simple, satisfaisant, addictif |
| 2026-11-19 | Mixeur au bouton (E) : bol qui se remplit, 2.5 s, tous les jus d'un coup ; 4 mixeurs ; Bigger Bowl 5/8/12/20 ; 1 operateur par mixeur (reagit en ~1 s) ; ancien Blender Operator -> operateur du mixeur 1 | Demande utilisateur : le joueur doit avoir un geste a faire |
| 2026-11-19 (soir) | **Une amelioration = un endroit qu'on comprend, et chaque niveau se voit** : pad "Upgrade Tree" (nouveau fruit + chute plus rapide, remplace Sprinkler et Lucky Fertilizer) ; l'arbre change a chaque niveau (5 modeles, il grossit, les fruits debloques pendent dedans) ; panneaux muraux avec une phrase explicative (Conveyor Speed, Juice Table, Faster / More Customers ; remplacent Juice Cooler, Fast Register, Billboard) ; chaque mixeur a 5 niveaux (panneau au-dessus) ; tapis, mixeurs, table a jus, comptoir et panneau FRESH JUICE! gagnent des pieces a chaque palier ; table a jus surelevee ; panneau MONEY / HOUR ; billets qui volent jusqu'a l'argent du HUD | Demande utilisateur : "on comprend pas a quoi ca sert", "on doit voir notre restaurant s'ameliorer" |
| 2026-11-19 | **Tour d'etages** : 10 etages, 1 etage = 1 rarete (10 fruits), chaque etage autonome ; plus de cocktails ni de terrasse ; jamais de melange (1 fruit = 1 jus pur) | Demande utilisateur : ne pas ressembler aux jeux de smoothies, progression visible |
| 2026-11-20 | Tour : un seul tas d'argent en bas ; clients en haut par ascenseur vitre exterieur ; etage = ~10-15 min de gains ; rebirth a l'etage 10 | Choix utilisateur |
| 2026-11-20 | Terrasse = hall de l'ascenseur (ouverte avec l'etage 2, panneau Elevator) ; bar a cocktails = salle du Rebirth "Reach Floor 10" | Choix utilisateur |
| 2026-11-20 | **Chaque etage a les 10 raretes** (Common a Infinity) au lieu de 1 etage = 1 rarete ; tableau des 100 fruits lu par ligne ; Luck = chance des rares ; grosse animation de decouverte (fruit au centre, nom, rarete, confettis, vole vers l'Index) | Demande utilisateur : un "jackpot" a chaque etage, cote collection |
| 2026-11-20 | Offres a droite : **une seule a la fois**, 3 min visible puis 30 s de pause, rien les 90 premieres s, 1re = Starter Pack, plus d'etiquette de reduction (juste le temps) ; nouvelles offres (Money Rush, Lucky Hour, Customer Rush, Mega Cash, Triple Boost, Rare Rain) ; contenu montre en icones (billets/trefle/chaussure + "x2" + duree, argent = vrai montant "+$3K"), pas en phrases | Choix utilisateur : comprehensible meme par les enfants |
| 2026-11-20 | Menu Upgrade (vitesse, plateaux) en **Robux** : 9 R$ le niveau, 5 achats max ; vitesse de base du joueur x1.15 puis x1.1 (20.24) ; 3 premiers achats en argent du jeu, 2 derniers en Robux | Demande utilisateur |
| 2026-11-20 | Rebirth code : prix 10B x (1 + rebirths), multiplicateur 1 + rebirths, menu Upgrade garde, keep cash = sans payer le prix (sert de Skip), Rebirth Master = arbres repris etage par etage | Propose par l'IA (demande "fait completement le Rebirth") ; prix et multiplicateur valides par l'utilisateur ("garde-les"), paliers Robux encore A VALIDER |
| 2026-11-20 | Nametag au-dessus de la tete : pseudo + "Rebirth N", on ne voit que celui des autres ; menu Rebirth : cases Now / After en texte + icone (plus des boutons) | Demande utilisateur |
| 2026-11-20 | Revue de l'economie : prix des etages / 2 ; clients 1.8 s au depart (au lieu de 2.5 s) et More Customers 150 $ ; fin des achats qui ne font pas monter l'argent (tapis, clients, mixeurs 2-4, operateurs 2-4) moins chere ; Lucky Cash min $750 | Analyse + simulation, validee par l'utilisateur ("let's go") |
| 2026-11-20 | Economie (suite, "fun du debut a la fin, progressif") : prix des etages en courbe progressive (1.5K / 11K / 62K / 350K / 2M / 11.5M / 66M / 380M / 2.2B) ; ascenseur = +4 % d'argent par vente aux etages 2+ par niveau, 400 / 600 x1.75 (achat toujours utile) | Analyse + simulation, demande utilisateur ("fais tout le necessaire") |
| 2026-11-21 | Profil neuf = usine vide : 4 pads verts FREE (Plant tree, Build shelf, Build blender, Open shop) construisent l'usine ; tout le reste apparait quand il devient utile (pop) ; pas de fantome bleu avant un pad FREE (on decouvre en marchant dessus), le bleu reste pour les machines a acheter (seule la prochaine) ; profils existants inchanges | Demande utilisateur (prompt 2b avant le tutoriel, puis "le transparent c'est que pour les prochaines machines") ; voir `systems/usine-a-construire.md` |
| 2026-11-22 | Cinematique d'ouverture (~14 s, une fois, Skip) : foret, arbre niveau 10 de l'etage 1, Wow / reflexion, pelle, l'arbre devient l'arbre niveau 1 dans les mains ; pad Plant tree a la touche E, 5 pommes ; ligne de chevrons lumineux + fleche vers le prochain pad FREE | Demande utilisateur (deroule valide, puis capture de reference pour la ligne) ; voir `systems/cinematique.md` |
| 2026-11-22 | Cinematique refaite (~20 s) et **Skip retire** : il voit l'arbre de loin puis court, arrache une pelle plantee, vrai creusage (pied sur la lame, terre jetee sur le tas), brandit l'arbre niveau 1 au-dessus de sa tete | Demande utilisateur ("retire la possibilite de skip", "il le voit de loin et apres il court") |
