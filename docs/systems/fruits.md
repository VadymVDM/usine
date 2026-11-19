# Systeme : Fruits, raretes, arbre et index

**Statut :** en cours (Config faite au lot A ; arbre au lot C)
**Derniere mise a jour :** 2026-11-19

## Role

Definit les 100 fruits (10 raretes x 10 fruits), comment l'arbre les fait tomber, comment on les
decouvre (index) et comment le rebirth ouvre les raretes suivantes.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/shared/Config/Fruits.luau` | partage | 100 fruits : id, nom, rarete, valeur, couleur du jus, poids (fait le 2026-11-19) |
| `src/server/Services/TreeService.luau` | serveur | Tirage des fruits, niveaux de l'arbre (a creer) |
| `src/client/Controllers/IndexController.luau` | client | Ecran Index (a creer) |

## Fonctionnement

### Debut de partie

- Au tout debut, l'arbre ne fait tomber **que des pommes**.
- Tres vite (premieres minutes), l'amelioration **Luck** de l'arbre ajoute l'**Orange**, puis la **Banane**...
- Chaque niveau de Luck **ajoute le fruit suivant** dans ce que l'arbre peut faire tomber, avec une
  petite chance. Les nouveaux fruits sont toujours plus rares que les anciens.

### Decouverte et Index

- Un fruit ajoute a l'arbre n'est **pas encore connu** : dans l'Index il apparait en silhouette "???".
- La **premiere fois** qu'il tombe : annonce "NEW FRUIT!" + effet + son, il s'ajoute a l'Index.
- L'Index (bouton a gauche de l'ecran) montre les 100 fruits par rarete : decouverts (image, nom,
  valeur, chance actuelle) ou "???". Il montre aussi les raretes encore fermees ("Rebirth to unlock").
- L'Index ne donne pas de recompense en plus : c'est la vitrine de la progression.

### Limite de l'arbre et rebirth

- L'arbre a un **niveau maximum de Luck** : il ne peut pas depasser le dernier fruit des raretes ouvertes.
- Pour aller plus loin, il faut **renaitre** : chaque rebirth ouvre la rarete suivante.

| Rebirths | Raretes ouvertes | Fruits possibles |
|---|---|---|
| 0 | Common, Uncommon, Rare | 30 |
| 1 | + Epic | 40 |
| 2 | + Legendary | 50 |
| 3 | + Mythic | 60 |
| 4 | + Godly | 70 |
| 5 | + Celestial | 80 |
| 6 | + Glitched | 90 |
| 7 | + Infinity | 100 |

Apres le rebirth 7 : les rebirths continuent (multiplicateur d'argent), plus de nouvelle rarete
jusqu'a une mise a jour.

### Valeurs

- Chaque rarete vaut environ **x25** la precedente.
- Dans une rarete, les 10 fruits ont des valeurs proches mais differentes (environ +20 % par fruit) :
  le dernier fruit d'une rarete vaut moins que le premier de la suivante.

| Rarete | Valeur du 1er fruit (ex.) | Effet visuel |
|---|---|---|
| Common | 1 | aucun |
| Uncommon | 25 | leger contour vert |
| Rare | 600 | contour bleu |
| Epic | 15K | contour violet + petites etincelles |
| Legendary | 400K | dore + brillance |
| Mythic | 10M | rouge + particules de feu |
| Godly | 250M | blanc + aureole + rayons de lumiere |
| Celestial | 6B | etoiles qui tournent autour |
| Glitched | 150B | clignote, pixels, couleurs qui sautent |
| Infinity | 4T | arc-en-ciel anime + son special |

## Les 100 fruits

Noms en anglais (affiches en jeu). Ordre = ordre de deblocage.

| # | Common | Uncommon | Rare | Epic | Legendary |
|---|---|---|---|---|---|
| 1 | Apple | Strawberry | Dragon Fruit | Mangosteen | Golden Apple |
| 2 | Orange | Cherry | Star Fruit | Jabuticaba | Diamond Pear |
| 3 | Banana | Blueberry | Lychee | Cherimoya | Ruby Cherry |
| 4 | Pear | Raspberry | Passion Fruit | Snake Fruit | Emerald Kiwi |
| 5 | Lemon | Kiwi | Papaya | Horned Melon | Sapphire Berry |
| 6 | Lime | Pineapple | Pomegranate | Buddha's Hand | Crystal Grape |
| 7 | Grape | Mango | Guava | Miracle Berry | Pearl Coconut |
| 8 | Plum | Coconut | Fig | Cloudberry | Amber Peach |
| 9 | Peach | Melon | Rambutan | Finger Lime | Silver Plum |
| 10 | Apricot | Watermelon | Durian | Ackee | Platinum Banana |

| # | Mythic | Godly | Celestial | Glitched | Infinity |
|---|---|---|---|---|---|
| 1 | Fire Mango | Angel Apple | Moon Melon | Error Apple | Rainbow Apple |
| 2 | Ice Berry | Holy Grape | Sun Orange | Pixel Berry | Time Berry |
| 3 | Thunder Lemon | Phoenix Fruit | Star Berry | Lag Lemon | Void Fruit |
| 4 | Lava Melon | Dragon Heart | Comet Cherry | Bug Banana | Quantum Mango |
| 5 | Storm Grape | Unicorn Berry | Meteor Mango | 404 Fruit | Multiverse Melon |
| 6 | Shadow Plum | Kraken Melon | Nebula Grape | Corrupted Grape | Eternal Peach |
| 7 | Frost Peach | Titan Banana | Galaxy Plum | Null Melon | Big Bang Berry |
| 8 | Toxic Apple | Griffin Pear | Aurora Kiwi | Static Cherry | Omega Fruit |
| 9 | Magma Orange | Pegasus Peach | Saturn Peach | Binary Mango | Infinity Fruit |
| 10 | Volcano Pineapple | Hydra Cherry | Eclipse Apple | Glitch Kiwi | Juice God Fruit |

## Remotes

A definir au moment du code (ouvrir l'Index = lecture seule ; ameliorer l'arbre = verifie cote serveur).

## Donnees sauvegardees

Niveau Luck et niveau Speed de l'arbre, liste des fruits decouverts (index), nombre de rebirths.

## Configuration

`src/shared/Config/Fruits.luau` : nom, rarete, valeur, couleur du jus, poids de tirage.
Les poids exacts s'equilibrent en test.

Valeurs validees le 2026-11-19 (argent entier, Apple = 5, environ +20 % par fruit, x25 par rarete,
arrondi a 3 chiffres) : Common 5, 6, 7, 9, 10, 12, 15, 18, 21, 26 ; Uncommon 125 -> 645 ;
Rare 3 120 -> 16 100 ; ... Infinity 19.1T -> 98.4T (liste complete dans le fichier).

Poids : `BaseWeight (1000) x 0.8^(position-1) x 0.1^(rarete-1)` (calcule au chargement ;
`weightOverride` possible par fruit). Ids sauvegardes : nom en PascalCase (`DragonFruit`,
`BuddhasHand`, `Fruit404`). `Fruits.MaxLuck(rebirths)` = 10 x (3 + rebirths), max 100.

## Problemes connus / a faire

- 100 modeles 3D a faire (simples, style blocky) : commencer par les 30 premiers.
- Equilibrer les poids pour que chaque nouveau fruit tombe assez vite pour etre decouvert.
