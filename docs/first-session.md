# Premiere session : cinematique + 30 premieres minutes

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

## La cinematique d'ouverture

L'utilisateur voulait ~15 s. **Recommandation : 8-10 s, une seule fois (premiere visite), passable
a tout moment** (bouton "Skip" + toucher l'ecran). Raison : les donnees des skills montrent que les
joueurs quittent si on leur prend le controle trop longtemps au debut. Si les stats montrent que
les joueurs regardent jusqu'au bout, on pourra l'allonger.

| Temps | Image | But |
|---|---|---|
| 0-2 s | Gros plan sur un arbre geant de vitrine (pas celui du joueur). Il tremble, un **fruit legendaire dore** tombe au ralenti, rayons de lumiere, "NEW FRUIT!" | Montrer le reve (le jackpot) tout de suite |
| 2-5 s | La camera survole la route et les 6 stands ; on voit des clients qui achetent, des billets qui volent | Montrer le jeu vivant et le but (stands qui gagnent de l'argent) |
| 5-8 s | La camera plonge vers la base du joueur ; le **logo du jeu** apparait avec un son ; le petit arbre du joueur fait tomber **3 pommes** qui rebondissent | "Ca, c'est a toi" |
| 8-9 s | La camera se place derriere le joueur, le controle revient | Le joueur agit tout de suite |
| 9 s+ | **Fleche 3D sur les pommes** + chemin lumineux au sol | Premiere action evidente, sans texte |

Technique : camera scriptee (`roblox-camera`), petite musique "jingle", rien du HUD pendant la
cinematique, drapeau `IntroSeen` dans la sauvegarde. Sans sauvegarde chargee, ne pas la rejouer en boucle.

## Les 30 premieres minutes (quelque chose de nouveau a chaque palier)

| Moment | Nouveaute | Comment on guide |
|---|---|---|
| 0:10 | Ramasser les 3 pommes (marcher dessus) | Fleche 3D + pommes qui brillent |
| 0:15 | Deposer dans les bacs, le presse-fruits fait 3 jus | Fleche vers les bacs, puis vers les jus |
| 0:25 | Poser les jus sur le comptoir, **premier client**, premier argent : pluie de billets + son | Fleche vers le comptoir, puis vers le tas d'argent |
| 0:35 | **Premier achat garanti** : "Tree Speed" (prix ajuste pour etre payable tout de suite) | Le bouton du mur brille + fleche |
| 1:00-1:30 | **Premier nouveau fruit : l'Orange** (Luck niv. 2), annonce "NEW FRUIT!", pastille sur Index | Pastille rouge sur Index |
| 2:30 | **Premier employe : le Ramasseur**, les fruits se ramassent tout seuls ("aha" de l'automatisation) | Bouton du mur qui brille |
| 3:00 | Fin du tutoriel guide. Les offres limitees a droite apparaissent | Plus de fleches, sauf nouveaux deblocages |
| 4:00 | Banane + amelioration "limite du comptoir" | - |
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

- Cinematique (camera + effets) avec "Skip", jouee une fois.
- Systeme de guidage : fleche 3D + chemin lumineux (Beam) + objet qui brille (Highlight),
  pilote par une liste d'etapes declenchees par l'etat du joueur.
- Tutoriel en etapes (machine a etats), qui reprend a la bonne etape apres une deconnexion.
- Gains acceleres pendant les premieres minutes (les joueurs ne le remarquent pas ensuite).
- Fruits garantis au debut : 3 pommes au depart, Orange garantie au Luck niv. 2.
- Annonces "NEW FRUIT!" et pastilles sur Index.
- Mesure (`roblox-analytics`) : un entonnoir par etape du tutoriel pour voir ou les joueurs partent.
