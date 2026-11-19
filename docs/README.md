# Documentation : Mon usine de boissons

Lire `AGENTS.md` a la racine pour les regles de travail.

## Documents generaux

| Fichier | Contenu |
|---|---|
| [game-design.md](game-design.md) | Concept, boucle de jeu, progression, decisions |
| [style.md](style.md) | Direction artistique (blocky, couleurs, panneaux, regles de construction) |
| [first-session.md](first-session.md) | Cinematique d'ouverture + 30 premieres minutes (retention) |
| [roadmap.md](roadmap.md) | Ce qui est fait, ce qui reste, decisions ouvertes, dette technique |
| [references/](references/) | Captures de reference (style, boutique, ecran de retour) |
| [prompts/](prompts/) | Prompts de demarrage des nouveaux chats (ex. phase 1 en ultracode) |
| [architecture.md](architecture.md) | Organisation du code et de Rojo |
| [journal/](journal/) | Journal de bord, un fichier par jour |

## Systemes

Un fichier par systeme dans `systems/`, a partir de [systems/_TEMPLATE.md](systems/_TEMPLATE.md).

| Systeme | Doc | Statut |
|---|---|---|
| Fruits, raretes, arbre, index | [systems/fruits.md](systems/fruits.md) | en cours (Config faite, arbre au lot C) |
| Interface (HUD et menus) | [systems/interface.md](systems/interface.md) | en cours |
| Sauvegarde des joueurs | [systems/sauvegarde.md](systems/sauvegarde.md) | en cours (teste en mode Mock seulement) |
| Argent, HUD et classement | [systems/argent.md](systems/argent.md) | en cours (teste sans sauvegarde reelle) |
| Carte, bases et attribution | [systems/carte-bases.md](systems/carte-bases.md) | fonctionne (a tester a 2 joueurs) |
| Chaine de production (arbre, ramassage, bacs, presse, jus) | [systems/chaine-production.md](systems/chaine-production.md) | a concevoir |
| Comptoir, clients et tas d'argent | [systems/clients.md](systems/clients.md) | a concevoir |
| Pads d'ameliorations et employes | [systems/ameliorations-employes.md](systems/ameliorations-employes.md) | en cours (pads poses au lot B, achat au lot E) |

Statuts possibles : `a concevoir`, `en cours`, `fonctionne`, `a corriger`.
