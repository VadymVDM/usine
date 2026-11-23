# Premiere session : premiere minute + 30 premieres minutes


> **A reecrire (tour d'etages, 2026-11-20)** : ce deroule date d'avant la tour. Ce qui change : chaque
> etage a les 10 raretes (l'Uncommon tombe des le debut : "1 in 3"), la decouverte se fait au
> ramassage avec l'ecran "NEW FRUIT!", l'etage 2 coute 1.5K depuis le 2026-11-20 (ouvre la terrasse + l'ascenseur), les
> employes rendent un etage "automatise" (il produit quand on n'y est pas). Les minutes du tableau
> (premier Uncommon a 7:00, etc.) ne sont plus justes.
> Proposition (2026-11-19), **[A VALIDER]** par l'utilisateur. But : donner envie de jouer des les
> premieres secondes et avoir **quelque chose de nouveau toutes les 1 a 3 minutes** pendant 30 min,
> pour la retention (temps de jeu, D1) et le referencement Roblox.
> Sources : skills `roblox-game-design` (FTUE, onboarding) et `roblox-player-psychology` (premiere minute).
> Les durees sont des cibles : elles se reglent dans la Config et se verifient en test (et avec les stats).

## Regles tirees des skills (a respecter)

- Les 90 premieres secondes decident si le joueur reste. Le joueur doit **agir dans les 5 premieres
  secondes** : une intro longue et impossible a passer fait partir les joueurs.
- Tutoriel court (les jeux qui marchent : 15-20 s de guidage), **pas de texte** (5 mots max), des
  **fleches et des objets qui brillent**, une seule chose a faire a la fois.
- **Premier achat dans les 30 premieres secondes**, un succes a chaque etape, zero echec.
- Le jeu montre tout de suite ce que promet la miniature (un arbre, des fruits colores, des jus).
- Etapes declenchees par l'etat du joueur (argent atteint, objet ramasse), pas par un minuteur fixe.
- **Pas de popup d'achat pendant les 5 premieres minutes** (on donne d'abord, on vend apres).
- Garder les effets speciaux pour les grands moments (sinon plus rien n'impressionne).

## La premiere minute (validee et codee le 2026-11-22)

Remplace l'ancien plan (arbre de vitrine, survol des stands, logo), perime depuis l'usine a construire.
Detail : `systems/cinematique.md` et `systems/usine-a-construire.md`.

| Temps | Ce qui se passe |
|---|---|
| 0-2.6 s | Cinematique (une fois, profil neuf, **pas de Skip** depuis le 2026-11-22) : son personnage marche dans une foret calme, oiseaux |
| 2.6-7.4 s | Il s'arrete net : il voit DE LOIN l'arbre niveau 10 de l'etage 1 qui scintille, "Wow!" bras en l'air, il court jusqu'a lui |
| 7.4-11.4 s | Il leve la tete (arbre immense), reflechit ("?"), voit la pelle plantee ("!"), l'arrache du sol |
| 11.4-18.6 s | 3 coups de pelle (la terre va sur le tas), l'arbre tombe (fruits qui roulent), devient l'arbre niveau 1 qui vole dans ses mains ; il le brandit au-dessus de sa tete |
| 18.6-20 s | Fondu blanc : il est dans son usine vide, l'arbre en main, il a la main |
| 20 s+ | Tutoriel etape par etape (`systems/tutoriel.md`) : Plant the tree (marcher sur le pad) -> Pick up the fruits -> Build the shelf -> Drop the fruits -> Build the blender -> Blend the fruits -> Take the juices -> Open the shop -> Sell the juices -> Collect your cash |

Regles gardees : intro courte (~20 s, sans Skip : demande utilisateur du 2026-11-22), une seule chose a faire a la fois, pas de texte
(5 mots max), un succes a chaque etape. `IntroSeen` dans la sauvegarde ; sans sauvegarde chargee,
pas d'intro.

## Les 30 premieres minutes (quelque chose de nouveau a chaque palier)

| Moment | Nouveaute | Comment on guide |
|---|---|---|
| 0:10 | Ramasser les 3 pommes (marcher dessus) | Fleche 3D + pommes qui brillent |
| 0:15 | Deposer dans les bacs, le presse-fruits fait 3 jus | Fleche vers les bacs, puis vers les jus |
| 0:25 | Poser les jus sur le comptoir, **premier client**, premier argent : pluie de billets + son | Fleche vers le comptoir, puis vers le tas d'argent |
| 0:35 | **Premier achat garanti** : pad "Upgrade Tree" a 15 $ (2026-11-19 soir : un seul pad = nouveau fruit + chute plus rapide ; l'arbre change a chaque niveau) | Le pad brille + fleche |
| 1:00-1:30 | **Premier nouveau fruit : l'Orange** (arbre niv. 2, elle pend deja dans l'arbre), annonce "NEW FRUIT!", pastille sur Index | Pastille rouge sur Index |
| 2:30 | **Premier employe : le Ramasseur**, les fruits se ramassent tout seuls ("aha" de l'automatisation) | Bouton du mur qui brille |
| 3:00 | Fin du tutoriel guide. Les offres limitees a droite apparaissent | Plus de fleches, sauf nouveaux deblocages |
| 4:00 | Banane + amelioration "Faster Customers" (panneau Customers a cote du comptoir) | - |
| 5:00 | Presseur (2e employe). Les offres d'achat contextuelles peuvent commencer (max 1 / 5 min) | - |
| 7:00 | **Premier fruit Uncommon (Fraise)** : contour vert, jus colore | Annonce |
| 9:00 | Serveur (3e employe) : le stand tourne seul. Le joueur peut se concentrer sur les ameliorations | - |
| 11:00 | Ameliorations des clients (vitesse, nombre) | Bouton qui brille au comptoir |
| 13:00 | Le mur de la **zone 2** montre un prix presque atteignable (objectif visible) | Fleche vers le mur |
| 16:00 | **Zone 2 : bar a cocktails** debloque. Premier cocktail guide (3 pommes = x2) | Fleches sur les 3 cases |
| 20:00 | **Premier fruit Rare (Fruit du dragon)** : gros effet, annonce au serveur | Annonce |
| 24:00 | 2e machine a cocktails | - |
| 28:00 | Le mur de la **zone 3** (terrasse) est visible avec son prix : objectif suivant | Fleche vers le mur |
| 30:00+ | Zone 3 vers 35-45 min ; premier rebirth vers 1 h - 1 h 30 (a equilibrer) | Guidage au premier rebirth |

Pendant ces 30 minutes, ce qui garde le joueur : **un objectif toujours visible** (le prochain
bouton qui brille ou le prochain mur), **la surprise des fruits rares** (aleatoire gratuit),
**l'Index qui se remplit**, et l'automatisation qui libere le joueur pour viser plus haut.

## A coder pour cette premiere session

- ~~Cinematique avec "Skip", jouee une fois~~ : fait le 2026-11-22 (`systems/cinematique.md`).
- Systeme de guidage : file de chevrons lumineux du joueur a la cible (Beam, voir `game-design.md`)
  + fleche 3D + objet qui brille (Highlight),
  pilote par une liste d'etapes declenchees par l'etat du joueur.
- Tutoriel en etapes (machine a etats), qui reprend a la bonne etape apres une deconnexion.
- Gains acceleres pendant les premieres minutes (les joueurs ne le remarquent pas ensuite).
- Fruits garantis au debut : 5 pommes a l'arbre plante (`Setup.FirstApples`), Orange garantie au Luck niv. 2.
- Annonces "NEW FRUIT!" et pastilles sur Index.
- Mesure (`roblox-analytics`) : un entonnoir par etape du tutoriel pour voir ou les joueurs partent.
