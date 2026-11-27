# Feuille de route : ce qui est fait, ce qui reste

> Etat au 2026-11-19. A mettre a jour a chaque etape terminee (cocher, dater).
> Ordre conseille : chaque phase s'appuie sur la precedente. Detail du jeu : `game-design.md`.

## Ou est l'information (tout le jeu est documente)

| Sujet | Fichier |
|---|---|
| Regles de travail des agents | `AGENTS.md` |
| Jeu complet : boucle, zones, fruits, rebirth, monetisation, decisions | `docs/game-design.md` |
| 100 fruits, 10 raretes, arbre, Index | `docs/systems/fruits.md` |
| Premiere session : cinematique + 30 premieres minutes | `docs/first-session.md` |
| Style visuel | `docs/style.md` |
| Interface (HUD, menus, boutique, offres, Welcome Back, pastille) | `docs/systems/interface.md` |
| Captures de reference | `docs/references/` |
| Organisation du code | `docs/architecture.md` |
| Historique detaille | `docs/journal/` |

## Phase 0 : conception et interface de base (FAIT)

- [x] Game design complet (v6) et decisions dans `game-design.md`
- [x] 100 fruits / 10 raretes nommes (`systems/fruits.md`)
- [x] Style visuel + captures de reference
- [x] Projet Rojo, chargeurs serveur/client, docs, journal
- [x] Interface : HUD (Shop, Index, argent, engrenage), boutique (potions, passes, packs, cadeaux,
      etiquettes, reductions), offres limitees a droite (rotation 10/2 min), fenetre d'offre,
      ecran Welcome Back, pastille de notification ; teste PC + telephone (simulateur)
- [x] 21 icones ICONSPACK mises en ligne, sons d'interface Roblox, musique

## Phase 1 : le coeur du jeu, zone 1 (A FAIRE, priorite)

Prompt pret pour un nouveau chat : [prompts/phase-1-ultracode.md](prompts/phase-1-ultracode.md).
Methode decidee : une phase a la fois, l'utilisateur teste dans Studio, puis phase suivante.


- [ ] **Sauvegarde** joueur (ProfileStore ou DataStore, `roblox-data`) : schema de `game-design.md` (Sauvegarde)
  - 2026-11-19 lot A : ProfileStore 1.0.3 + `DataService` (code, a valider par l'utilisateur ;
    non teste avec le vrai DataStore : acces API Studio desactive, teste en mode Mock)
  - Prealable : Game Settings > Security > **Enable Studio Access to API Services**
- [ ] **Argent** cote serveur (MoneyService) + affichage HUD + classement (leaderstats)
  - 2026-11-19 lot A : `MoneyService`, leaderstats Cash/Rebirths, HUD `$1K` (code, verifie en
    playtest Studio via `DebugService` ; a valider par l'utilisateur)
- [ ] **Carte** : route + 6 bases blocky (dans Studio, pas dans Rojo), attribution d'une base par joueur
  - 2026-11-19 lot B : carte + `BaseTemplate` reconstruits par `tools/build-map/` (style refait a la
    demande de l'utilisateur), `BaseService` (attribution, panneau, apparition, nettoyage, 7e joueur),
    remote `Notify` (verifie en playtest Studio a 1 joueur ; 2 joueurs et telephone non testes)
- [ ] **Arbre** : chute des fruits (tirage selon Luck), Speed, plafond 30 fruits au sol, modeles des
      30 premiers fruits (style blocky)
  - 2026-11-19 lot C : `TreeService` + `FruitModels` (verifie en playtest Studio a 1 joueur :
    chute, Luck 2 -> Orange, plafond 30 + "Tree full!", 3 pommes a la premiere visite, decouverte
    sauvegardee ; 2 joueurs et telephone non testes)
- [ ] **Ramassage** (marcher dessus, pile au-dessus de la tete), **bacs**, **presse-fruits**, pile de jus
  - 2026-11-19 lot C : `ProductionService` (verifie en playtest Studio : ramassage limite a 20, pile
    2 x 2, depot, presse 1 jus / 1.5 s, "n/max" + "!" a 10/10, pile gardee apres la mort). Prendre
    les jus et le comptoir : lot D
- [x] **Usine refaite** (2026-11-19, demande de l'utilisateur) : carte agrandie (bases 132 x 118,
      espacement 170), usine en interieur, verger, tapis roulant + mixeur anime, machines fantomes
      bleues qui se construisent, pads verts des employes, panneaux d'ameliorations a tuiles, salles
      fermees (portes rouges). `UpgradeService` (achats) + `MachineFxController` (effets) : l'achat du
      lot E est fait. Verifie en playtest (voir journal).
- [x] **Comptoir**, **clients R6 (R15 depuis le 2026-11-27)** (minuteur serveur + PNJ visuels), **tas de billets** a encaisser
      (E ou s'approcher), pad Robux "Auto Collect" (pass pas cree) — 2026-11-19, playtest 1 joueur
- [x] **Touche E partout** (fruits, etagere, table a jus, comptoir, argent, machines, portes),
      **barre d'inventaire** en bas, jus portes dans les mains, machines fantomes "vraie machine
      teintee bleu + contour", usine agrandie avec zones delimitees — 2026-11-19
- [x] **Employes R6 (R15 depuis le 2026-11-27)** visibles qui travaillent : Fruit Picker, Blender Operator (Waiter remplace par le pad Auto Sell le 2026-11-20) — 2026-11-19
- [x] **Plan de l'usine en U** (bar a jus a droite, plus de z-fighting), decor inutile retire,
      pieds des panneaux, fleche jaune retiree, marche des employes (pathfinding, animation seulement
      en marchant), inventaire = barre Roblox de base, HUD plus petit sur PC, "+" -> packs d'argent,
      menu Settings branche (Music, Sounds, Low Quality, sauvegardes), ombres inutiles coupees — 2026-11-19 soir
- [x] ~~Joueurs en R6~~ : abandonne le 2026-11-27, c'est l'inverse : tous les PNJ passent en R15
      comme les joueurs (employes, clients, apercu Edit)
- [x] Vrais modeles de fruits : 100 fruits voxel + effets de rarete + effets d'apparition, arbre
      en 5 stades qui grandit (2026-11-19, playtest PC 1 joueur)
- [ ] Meilleurs sons de jeu
- [ ] Remotes verifies cote serveur (`roblox-security`, `roblox-networking`) : relecture securite
      complete des nouveaux services (CustomerService, WorkerService) a faire
- [ ] Tests : 2 joueurs, telephone, manette

## Phase 1b : la tour d'etages (CODEE le 2026-11-20, en test chez l'utilisateur)

Nouveau gameplay : 10 etages de 10 fruits (depuis le 2026-11-20 : chaque etage a les 10 raretes,
de Common a Infinity), chaque etage autonome. Detail :
`game-design.md` (section "La tour d'etages"). Remplace les zones 2 et 3 (phase 4).

Plan technique complet : `systems/tour-etages.md`. Prompt pret pour un nouveau chat :
[prompts/phase-1b-tour-etages.md](prompts/phase-1b-tour-etages.md). Ordre prevu :

- [x] Plan : etage de 36, escalier du milieu vers le mur, 2 voies alternees, etage ferme, lag,
      sauvegarde (2026-11-19)
- [x] Tranche (2026-11-20) : un seul tas d'argent en bas, ascenseur vitre exterieur pour les
      clients, etage = ~10-15 min de gains, rebirth a l'etage 10
- [x] 1. (2026-11-20, valide par l'utilisateur) `FloorTemplate` dans Studio : la base actuelle sans facade/cour + zone STAIRS (rampes,
      garde-corps, trou, palier, vitre rouge) ; zone SALES raccourcie a z 50 ; retirer les salles
      Cocktail Bar / Terrace. Tester a 2 etages a la main (monter, camera, tete, chute)
- [x] 2. (2026-11-20, SchemaVersion 4) **Sauvegarde** par etage (`FloorsOwned`, `Floors[n].Upgrades`, migration) - a montrer
      avant de coder (`roblox-data`)
- [x] 3. (2026-11-20, en test chez l'utilisateur) Services par etage : recoivent un etage au lieu d'une base (Tree, Production, Customer,
      Worker, Upgrade) ; arbre = fruits de la rarete de l'etage
- [x] 4. (2026-11-20, en test chez l'utilisateur) `FloorService` : construire les etages achetes + le suivant ferme, achat (E), effet de
      construction, etage actif du joueur, apparition sur l'etage le plus haut, panneau Floors
- [x] 4b. (2026-11-20, verifie dans Studio) **Fruits par etage (regle du 2026-11-20)** : etage n = ligne n du tableau (une rarete de
      chaque), chances par rarete, Luck = chance des rares, valeur = etage x bonus de rarete, une caisse
      par rarete, decouverte au ramassage + animation (fruit au centre, confettis, vole vers l'Index).
      Detail : `systems/fruits.md` > "Fonctionnement"
- [x] 5. (2026-11-20, verifie dans Studio) Production en nombres sur les etages ou le joueur n'est pas
      (`Lib/FloorIncome`, formule prete pour les gains hors ligne), visuels seulement sur l'etage actif,
      panneau ELEVATOR, cabine et clients de la terrasse
- [x] 6. Clients des etages du haut (balcon + ascenseur vitre, lot 5) ; ventes de tous les etages vers le tas du bas (lot 3)
- [x] Lot 6 (2026-11-20) : mesures a 10 etages et 6 bases x 10 etages simulees, relecture securite /
      connexions (voir `systems/tour-etages.md` > "Performance")
- [ ] Tests restants : 2 vrais joueurs, vrai telephone, trajet des clients par l'ascenseur a l'oeil
- [ ] A decider : alleger un etage (~1 230 pieces, objectif ~800) et `StreamingTargetRadius` (1024 :
      tout est envoye sur PC)
- [ ] Premiere session (`first-session.md`) a reecrire avec les etages (voir la note en haut du fichier)

## Phase 2 : premiere session (A FAIRE)

- [ ] Cinematique d'ouverture (8-10 s, passable, une fois) - voir `first-session.md`
- [ ] Guidage : file de chevrons lumineux joueur -> cible (Beam), objets qui brillent, etapes du tutoriel
- [ ] Index branche sur les vrais fruits (10 pages, une par etage ; animation de decouverte : lot 4b)
- [ ] Gains hors ligne cote serveur + ecran Welcome Back branche (CLAIM credite l'argent)
- [ ] Entonnoir analytics du tutoriel (`roblox-analytics`)

## Phase 3 : monetisation (A FAIRE, apres accord sur les prix)

- [ ] **Valider les prix** (passes, packs, Rebirth Master) puis creer passes et produits sur Roblox
      (possible depuis ici avec les permissions ; sujet "argent" : toujours demander l'accord avant)
- [ ] Reception des achats cote serveur (ProcessReceipt / BindReceiptHandler, `roblox-monetization`)
- [ ] Effets des passes et boosts (x3 cash, chance, vitesse, auto collect, greedy customers...)
- [ ] Cadeaux (produits "Gift", choix du joueur, avantage enregistre chez le receveur)
- [ ] Produits des offres limitees (prix reduits) ; pass en promo = produit qui donne l'avantage
- [ ] Offres contextuelles (au bon moment, garde-fous : pas avant 5 min, max 1 / 5 min)
- [ ] Pass "Thief" : vol de boissons avec garde-fous (a cadrer)

## Phase 4 : rebirth (A FAIRE ; zones 2 et 3 abandonnees le 2026-11-19, remplacees par les etages)

- [x] Rebirth (multiplicateur, "Rebirth & keep your cash", Rebirth Master ; n'ouvre plus de rarete)
      — code le 2026-11-20 (`systems/rebirth.md`) ; prix (10B, 20B...) et multiplicateur (x2, x3...)
      valides ; paliers Robux a valider ; produits Robux et pass a creer
- [ ] Rebirth : a decider : bouton dans le HUD, badge "x2" pres de l'argent, couleur de l'arbre,
      Rebirth Master -50 %, guidage au premier rebirth

## Phase 5 : finition et lancement (A FAIRE)

- [ ] Sons de jeu (ramassage, presse, vente, jackpot), effets, musique
- [ ] Traduction auto (Creator Hub > Localization) + table pour les textes avec nombres
- [ ] Tests sur **vrai telephone**, tablette, manette
- [ ] Nom final, icone, miniatures (montrer exactement ce qu'on voit en jouant)
- [ ] Checklist de publication (`roblox-publish-checklist`), test avec de vrais joueurs
- [ ] Apres lancement : mises a jour regulieres (+10 a 20 fruits), evenements, offres limitees

## Decisions encore ouvertes (a trancher par l'utilisateur)

- Nom : **My Juice Factory** (decide le 2026-11-23)
- Prix des etages (remplacent les salles Cocktail Bar 5K / Terrace 50K)
- Prix des passes (VIP 149, 3x Cash 399, Drink Master 249, Greedy 199, Speed 99, Auto Collect 149,
  Thief 149, Rebirth Master 299) et des packs d'argent (25 / 79 / 199 / 499)
- Rebirth Master : ajouter "rebirth 50 % moins cher" ou non
- Cinematique : 8-10 s (recommande) ou 15 s
- Recompenses quotidiennes / serie de connexions : oui ou non (bon pour revenir le lendemain)
- Pass Thief : regles exactes

## Dette technique et points a surveiller

- Commit de la phase 0 fait le 2026-11-19 (9daae84). `api.txt` (cle API de l'utilisateur) est ignore
  par git : ne jamais le commiter.
- Studio "usine" : `127.0.0.1:34851` pas autorise en HTTP -> les `.rbxm` se modifient via le Studio du
  pack (ou a la main). Mise en page du HUD et taille des menus sont dans `MenuController` (code).
- `ShopController` a ses propres briques de style, en double avec `UI/PackStyle.luau` (a regrouper).
- StyLua et Selene pas installes (formatage / analyse non verifies).
- Demos visibles seulement dans Studio : ecran Welcome Back + pastille sur Shop (`SHOW_DEMO_IN_STUDIO`).
- Deux images d'essai en ligne non utilisees (106808625815623, 136027847911663).
- Studio a plante deux fois (gros traitement d'interface en un seul appel ; une fois sans cause connue).
