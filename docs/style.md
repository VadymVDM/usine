# Direction artistique

> Analyse de captures d'un autre tycoon Roblox, fournies par l'utilisateur le 2026-11-19
> **comme reference de style uniquement**. On ne recopie ni sa carte, ni ses bases, ni ses panneaux.
> Notre jeu a son propre theme : un stand de jus en plein air avec un arbre, pas une usine en interieur.

## L'ambiance en 5 mots

Blocky, studs, couleurs vives, lisible, joyeux.

## Formes et matieres

- Style "brique Roblox" : grandes surfaces avec **texture de studs** (petits carres en relief),
  formes simples et carrees. Pas de details fins, pas de realisme.
- Arbres, buissons, montagnes en **gros blocs empiles** (low poly carre).
- Objets lisibles de loin : un objet = une forme simple + une couleur franche.

## Couleurs

| Element | Couleur |
|---|---|
| Ciel | Cyan clair, nuages blancs doux |
| Herbe | Vert vif sature |
| Route | Bleu fonce avec tirets jaunes ; trottoirs blanc-gris |
| Murs | Gris tres clair / bleute |
| Chemins vers une base | Orange |
| Boutons payants en Robux (au sol) | **Magenta neon** (toujours la meme couleur = on reconnait le payant) |
| Prix en argent du jeu | Texte vert |
| Zone fermee "a acheter" | Planches en croix + panneau rouge avec le prix |

Pour notre theme : ajouter les couleurs des fruits (rouge pomme, orange, jaune, violet raisin...)
partout sur le stand, les gobelets et les panneaux. Le jeu doit "sentir le fruit".

## Textes et panneaux

- Police ronde et grasse, style cartoon, texte blanc avec **contour noir epais**.
- Prix : gros, verts (argent) ; Robux : violet avec l'icone Robux.
- **Tableau d'ameliorations** pres de chaque machine : tuiles colorees (une couleur par type),
  "valeur actuelle -> suivante", prix en argent + prix en Robux.
- Au-dessus d'une pile (boissons, argent) : montant + "10/10", et un **!** rouge quand c'est plein.
- Panneau au-dessus de chaque base avec le nom du joueur ("<Name>'s Juice Stand").

## Interface (HUD)

- Grosses icones dessinees avec un label dessous (pas de boutons plats).
- Argent en bas a gauche, gros, vert avec contour, + un petit bouton "+" (packs d'argent).

## Regles de construction

- **Pas de z-fighting** : deux pieces ne doivent jamais avoir une face au meme endroit.
  Decaler d'au moins 0.05 stud ou ne pas chevaucher. Verifier en jeu avant de valider.
- Tout est ancre (Anchored) sauf ce qui doit bouger. Pieces decoratives : `CanCollide` coupe si inutile.
- Voir le skill `roblox-building` avant de construire la carte.
