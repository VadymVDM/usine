# Direction artistique

> Analyse de captures d'un autre tycoon Roblox, fournies par l'utilisateur le 2026-11-19
> **comme reference de style uniquement**. On ne recopie ni sa carte, ni ses bases, ni ses panneaux.
> Notre jeu a son propre theme : depuis le 2026-11-19, une **usine de jus en interieur** (verger sous
> un puits de lumiere), toujours blocky / studs et fruitee. Couleurs refaites le 2026-11-19 (soir) sur
> de nouvelles captures : murs gris-bleu clair, sol ardoise, acier, neons, poteaux jaune / noir
> (palette en tete de `tools/build-map/02a-base-shell.luau`).
> Achat = machine fantome bleue transparente qui se construit ; employes : pad vert neon + nom et prix
> flottants ; ameliorations : panneaux en bois a tuiles colorees ; salles fermees : porte rouge
> transparente + planches en croix + cadenas + nom + prix.

## L'ambiance en 5 mots

Blocky, studs, couleurs vives, lisible, joyeux.

Mais pas "flashy" (2026-11-19, nuit, demande de l'utilisateur) : couleurs franches mais un peu
desaturees, eclairage doux (pas de surexposition), ombres visibles, neon reserve aux pads et aux
lampes. Eclairage dans `tools/build-map/04-lighting.luau`.

## Formes et matieres

- Style "brique Roblox" : grandes surfaces avec **texture de studs** (petits carres en relief),
  formes simples et carrees. Pas de details fins, pas de realisme.
- Arbres, buissons, collines en **gros blocs empiles** (low poly carre).
- Exception (2026-11-27) : le **fond de carte tres loin** (montagnes, volcan, a plus de 1000 studs)
  est en pics a facettes lisses (Wedge / CornerWedge), sans studs. Raison : les blocs empiles
  geants ont ete refuses ("moches"), et les studs font du moirage a cette distance. Tout ce qui
  est pres du joueur (foret, collines, crete derriere les murs, rocher de la cascade) reste en
  blocs a studs. Voir `systems/carte-bases.md`, section "Alentours et fond de carte".
- Touche "notre jeu" dans le decor : les fruits du jeu en geant (fruits voxel agrandis) et du
  jus a la place de la lave ou de l'eau (variante Fruity).
- Objets lisibles de loin : un objet = une forme simple + une couleur franche.

## Couleurs

| Element | Couleur |
|---|---|
| Ciel | Cyan clair, nuages blancs doux |
| Herbe | Vert vif sature |
| Route | Bleu fonce avec tirets jaunes ; trottoirs blanc-gris |
| Murs | Gris clair (238, 242, 250 depuis le 2026-11-20, cale en jeu avec l'eclairage de 04 ; avant 226, 232, 244), faces en Inlet (carres en creux) depuis le 2026-11-20 ; bas de mur en tole (DiamondPlate) gris |
| Sol de l'usine | Ardoise foncee (74, 80, 93 depuis le 2026-11-20 ; avant 104, 110, 128), Studs comme la route ; plus de sol de zone teinte : allee en relief gris-bleu (74, 85, 108), plaque de 0.4 (`02k`) |
| Structure (piliers, cadres, poutres) | Acier gris-bleu ; bas des piliers raye jaune / noir |
| Eclairage interieur | Neons blancs rectangulaires sous les poutres |
| Vitres | Cyan vif, transparentes |
| Chemins vers une base, cour | Orange (226, 134, 66) |
| Pads payants en Robux (au sol) | **Violet** a studs, bord dore, baguettes neon roses (toujours le meme look = on reconnait le payant) |
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
  Attention aussi aux faces de COTE : une bordure qui finit pile au bord d'un sol (meme x ou z)
  fait du z-fighting sur la tranche. Detecteur : `tools/build-map/check-zfighting.luau`.
- Tout est ancre (Anchored) sauf ce qui doit bouger. Pieces decoratives : `CanCollide` coupe si inutile.
- Voir le skill `roblox-building` avant de construire la carte.

## Captures "Ma ferme de poulet" (2026-11-19, apres-midi) : ce qu'on reprend

Reference de style seulement (on ne recopie ni les poulets, ni les oeufs, ni la carte). Ce qui
donne l'air "pro" a ce jeu, et ce qu'on en fait :

| Idee | Chez nous | Etat |
|---|---|---|
| Deux echelles : decor en grosses briques a studs, objets a collectionner en **voxel fin** (petits cubes, 3 tons, reflet blanc, etincelles pour les speciaux) | 100 fruits voxel + effets de rarete (`systems/fruits.md`) | fait |
| Pads = dalle epaisse a bord plus fonce + dessus clair a studs ; texte flottant (action blanche a contour noir, prix vert) ; pads payants d'une autre couleur ; zones de depot qui brillent | Pads employes verts + pad Robux violet/dore, baguettes neon | fait |
| Deux styles de studs (voir regle ci-dessous) | Studs / Inlet | fait (02a et 01 par la session "Couleurs de l'usine", 02b-02f) |
| Arbres en blocs empiles, dessus des grappes plus clairs, petits details (ruche...) | Arbre en 5 stades (nichoir, ruche, balancoire, pommes d'or) | fait |
| Etiquette nom + niveau au-dessus des objets ("Niveau 5") | "Lv 3" au-dessus des machines | idee |
| Beaucoup de petit decor (citrouilles, barrieres, rochers) pour remplir les vides | Caisses de fruits, tonneaux, plantes en pot dans l'usine | idee (pas de fleurs de couleur dans le verger : on les prend pour des fruits) |
| Gros panneau en bois avec un chiffre geant ("338 / 2 par seconde") | Panneau "Juice / s" pres du bar | idee |

### Regle des 2 studs

Roblox a plusieurs textures de surface ; on en garde **deux** :

- **Studs** (bosses) : objets, murs, machines, pads, herbe, feuillage, troncs.
- **Inlet** (creux) : ce sur quoi on marche et qui n'est pas de l'herbe (planchers, terrasse,
  chemins, dessus des bordures), et le dessous des pieces.

**Changement du 2026-11-20 (demande de l'utilisateur : "pour le sol utilise les autres studs, les
studs comme sur la route")** : le DESSUS des sols est maintenant en **Studs** (bosses), comme la
route. Les scripts 01-05 posent encore Inlet ; `tools/build-map/07-floor-studs.luau` (a lancer en
dernier) passe tout `TopSurface = Inlet` en Studs. Le dessous des pieces reste Inlet.

**Eclairage plus vif (2026-11-20)** : `04-lighting` : saturation +0.12 (avant -0.08), exposition 0
(avant -0.1), brume Haze 0.25 / Density 0.2 (avant 0.6 / 0.24), plus de teinte chaude. Raison : les
couleurs paraissaient ternes ("trop sombre, ca donne pas envie").
**Eclairage moins bleu (2026-11-20 soir)** : saturation 0.05, reflet du ciel coupe
(EnvironmentDiffuseScale 0.1, Specular 0.1), ambiances gris neutre. Raison : sans toit, le ciel
teintait murs et sol en cyan ; la reference a des murs gris et un sol ardoise. Puis (meme nuit) :
ciel Cartoon supprime et lumiere du ciel remise (0.6) pour que le perso soit eclaire comme sur la
reference ; voir `04-lighting`.

Pas de studs sur les petits objets lisses (fruits voxel, textes, neon). Exception (2026-11-19, demande
de l'utilisateur) : les **gobelets de jus** sont des briques a studs (1 stud par face, voir
`systems/chaine-production.md`).
Exception (2026-11-19, nuit, demande de l'utilisateur) : les **panneaux et supports de texte** (pancartes
des zones, enseignes, cadres des panneaux, etiquettes des machines, panneau des mixeurs) ont des studs,
y compris la face avec le texte (fond du texte transparent : les studs se voient derriere). Restent
lisses : la barriere transparente des zones verrouillees, le neon, les textes 3D flottants.

Deux surfaces en plus, demandees par l'utilisateur le 2026-11-19 (soir) :

- **Universal** (stud en creux avec une bosse dedans) : feuillage des arbres et buissons du decor
  (`03-decor`). A reutiliser quand un objet "nature" doit se distinguer des murs a studs.
- **Weld** (traits en X, comme une caisse en carton) : tuiles et boutons des panneaux
  d'ameliorations (`02g`, Tile / BuyButton / RobuxButton) ; le cadre en bois garde ses studs.
  (Glue donne exactement le meme dessin.)

**Soleil au zenith (2026-11-20)** : `04-lighting` : ClockTime 12 + GeographicLatitude 23.5 = soleil
juste au-dessus (direction (0, 1, 0)), les ombres tombent sous les objets. Avant : 14 h, ombres en biais.
