# Documentation : Mon usine de boissons

Lire `AGENTS.md` a la racine pour les regles de travail.

## Documents generaux

| Fichier | Contenu |
|---|---|
| [game-design.md](game-design.md) | Concept, boucle de jeu, progression, decisions |
| [style.md](style.md) | Direction artistique (blocky, couleurs, panneaux, regles de construction) |
| [first-session.md](first-session.md) | Premiere minute (cinematique, usine a construire) + 30 premieres minutes (retention) |
| [roadmap.md](roadmap.md) | Ce qui est fait, ce qui reste, decisions ouvertes, dette technique |
| [references/](references/) | Captures de reference (style, boutique, ecran de retour) |
| [prompts/](prompts/) | Prompts de demarrage des nouveaux chats (ex. phase 1 en ultracode) |
| [architecture.md](architecture.md) | Organisation du code et de Rojo |
| [travailler-a-deux.md](travailler-a-deux.md) | Travail a deux : Git, une place Rojo par personne, place partagee Team Create |
| [journal/](journal/) | Journal de bord, un fichier par jour |

## Systemes

Un fichier par systeme dans `systems/`, a partir de [systems/_TEMPLATE.md](systems/_TEMPLATE.md).

| Systeme | Doc | Statut |
|---|---|---|
| Fruits, raretes, arbre, index | [systems/fruits.md](systems/fruits.md) | en cours (100 fruits voxel + effets ; arbre construit par code : grand changement a chaque niveau, un theme par etage, l'etage n repart du max de l'etage n-1 ; Index : grille des 100 fruits + CLAIM) |
| Chargement (prechargement invisible de l'interface, des fruits, PNJ, sons et avatars ; HUD montre des que l'interface est prete, le reste en arriere-plan) | [systems/chargement.md](systems/chargement.md) | fonctionne (Studio PC) |
| Interface (HUD et menus) | [systems/interface.md](systems/interface.md) | en cours |
| Sauvegarde des joueurs | [systems/sauvegarde.md](systems/sauvegarde.md) | fonctionne (quitter / revenir teste ; 2 serveurs a tester) |
| Argent, HUD et classement | [systems/argent.md](systems/argent.md) | en cours (teste sans sauvegarde reelle) |
| Tour d'etages et escalier (10 etages, 10 raretes par etage) | [systems/tour-etages.md](systems/tour-etages.md) | code (lots 0 a 6, 2026-11-20), en test chez l'utilisateur |
| Carte, bases et attribution (usine) | [systems/carte-bases.md](systems/carte-bases.md) | fonctionne (usine refaite le 2026-11-19 ; a tester a 2 joueurs) |
| Chaine de production (arbre, ramassage E, inventaire, etagere, mixeur, jus) | [systems/chaine-production.md](systems/chaine-production.md) | en cours (boucle complete en playtest le 2026-11-19) |
| Comptoir, clients R6 et tas d'argent | [systems/clients.md](systems/clients.md) | en cours (fonctionne en playtest a 1 joueur) |
| Machines, ameliorations et employes R6 | [systems/ameliorations-employes.md](systems/ameliorations-employes.md) | en cours (pad de l'arbre, panneaux Conveyor / Juice Table / Customers, mixeurs a 5 niveaux, decor par niveau ; 3 employes) |
| Ameliorations du joueur (bouton UPGRADE : vitesse, fruits et jus portes) | [systems/ameliorations-joueur.md](systems/ameliorations-joueur.md) | fonctionne (achats testes en playtest PC le 2026-11-20 ; telephone pas teste) |
| Dons (urne + tableau TOP DONORS, recus Robux) | [systems/dons.md](systems/dons.md) | en cours (coin + fenetre testes en Studio ; produits Robux a creer, vrai don pas teste) |
| Classements mondiaux (2 murs-ecrans aux bouts de la route : argent + jus vendus, temps de jeu + Robux) | [systems/classements.md](systems/classements.md) | en cours (murs construits, place v157, argent et temps remplis en playtest) |
| Panneau admin (cible au choix, ~40 boutons : argent, fruits, jus, ameliorations, etages, rebirth, passes, Index, teleport, Reset All) | [systems/admin.md](systems/admin.md) | en cours (teste en Studio a 1 joueur ; autre cible et Reset pas testes) |
| Vol de boissons (touche E "Steal" sur la table a jus ou le comptoir d'une autre base ; 1er vol gratuit par serveur, puis 19 R$ par vol ; pass Thief plus vendu, illimite pour ceux qui l'ont) | [systems/vol.md](systems/vol.md) | en cours (vol a l'unite code le 2026-11-27 ; pas teste en Play ; produit 19 R$ pas cree) |
| Camera (objets entre la camera et le joueur rendus transparents, la camera passe au travers ; murs et sols inchanges) | [systems/camera.md](systems/camera.md) | fonctionne (playtest PC le 2026-11-20 ; telephone pas teste) |
| Pads Robux Waiter Speed x10 (a cote de Take Juices) et Billboard (cour, 2X Sell Price) | [systems/pads-robux.md](systems/pads-robux.md) | en cours (teste en Studio le 2026-11-20 avec attributs ; passes pas crees) |
| Lucky Cash (tas d'argent qui brille a chaque etage : E ou marcher dessus -> gros montant adapte a l'etage contre des Robux) | [systems/lucky-cash.md](systems/lucky-cash.md) | en cours (teste en Studio le 2026-11-20 ; produit Robux pas cree) |
| Gains hors ligne (ecran Welcome Back : argent des etages automatises x temps absent, CLAIM, x2 Robux) | [systems/gains-hors-ligne.md](systems/gains-hors-ligne.md) | en cours (teste en Studio le 2026-11-20 ; produit x2 pas cree) |
| Cadeaux de passes (bouton rose de la boutique, boite aux lettres DataStore) | [systems/cadeaux.md](systems/cadeaux.md) | en cours (recus simules en Studio le 2026-11-23 ; 2 joueurs et vrai achat pas testes) |
| Achats Robux (boutique, offres limitees, boosts x2 sauvegardes, packs d'argent, passes 3X CASH / Drink Master / Greedy / Speed Master / VIP) | [systems/achats-robux.md](systems/achats-robux.md) | en cours (teste en Studio avec recus simules le 2026-11-20 ; produits pas crees) |
| Usine a construire (profil neuf : usine vide, 4 pads FREE Plant tree / Build shelf / Build blender / Open shop, tout le reste revele au bon moment avec un pop) | [systems/usine-a-construire.md](systems/usine-a-construire.md) | fonctionne (playtest Studio PC le 2026-11-21 ; telephone et 2 joueurs pas testes) |
| Cinematique d'ouverture (profil neuf : foret, arbre niveau 10, pelle, l'arbre niveau 1 dans les mains ; sans Skip) | [systems/cinematique.md](systems/cinematique.md) | fonctionne (playtest Studio PC le 2026-11-22 ; telephone et 2 joueurs pas testes) |
| Tutoriel etape par etape (usine, Fruit Picker, Index, tour complet, vitesse FREE, Operator, ameliorations au hasard ; objectif en haut, ligne + fleches, etape sauvegardee) | [systems/tutoriel.md](systems/tutoriel.md) | fonctionne (parcours complet en playtest Studio PC le 2026-11-22 ; telephone et 2 joueurs pas testes) |
| Rebirth (salle du Rebirth a l'etage 10, multiplicateur x2/x3..., keep cash en Robux, Rebirth Master) | [systems/rebirth.md](systems/rebirth.md) | en cours (code le 2026-11-20 ; produits Robux pas crees) |
| Apercu de l'usine en mode Edit (toute l'usine "tout achete" visible sans Play : 10 etages, arbres, fruits, PNJ ; jamais sauvegarde ni copie dans le Play) | [systems/apercu-edit.md](systems/apercu-edit.md) | en cours (echantillon par script le 2026-11-27 ; bouton Studio et retouches a faire) |

Statuts possibles : `a concevoir`, `en cours`, `fonctionne`, `a corriger`.
