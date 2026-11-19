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
- [ ] **Ramassage** (marcher dessus, pile au-dessus de la tete), **bacs**, **presse-fruits**, pile de jus
- [ ] **Comptoir**, **clients** (minuteur serveur + PNJ visuels), **tas d'argent** a ramasser
- [ ] **Pads d'amelioration** avec carte flottante (prix argent + prix Robux) et **employes**
      (ramasseur, presseur, serveur) - pads et cartes poses au lot B, achat au lot E
- [ ] Remotes verifies cote serveur (`roblox-security`, `roblox-networking`)

## Phase 2 : premiere session (A FAIRE)

- [ ] Cinematique d'ouverture (8-10 s, passable, une fois) - voir `first-session.md`
- [ ] Guidage : fleches 3D, chemin lumineux, objets qui brillent, etapes du tutoriel
- [ ] Annonces "NEW FRUIT!", Index branche sur les vrais fruits (10 raretes du jeu au lieu du pack)
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

## Phase 4 : zones 2 et 3, rebirth (A FAIRE)

- [ ] Zone 2 : bar a cocktails (3 cases, x2 si 3 identiques, reservation des fruits)
- [ ] Zone 3 : terrasse (tables, tapis roulant de vente)
- [ ] Rebirth (multiplicateur, rarete suivante, "Rebirth & keep your cash", Rebirth Master)
- [ ] 70 fruits restants (raretes ouvertes par les rebirths)

## Phase 5 : finition et lancement (A FAIRE)

- [ ] Sons de jeu (ramassage, presse, vente, jackpot), effets, musique
- [ ] Traduction auto (Creator Hub > Localization) + table pour les textes avec nombres
- [ ] Tests sur **vrai telephone**, tablette, manette
- [ ] Nom final, icone, miniatures (montrer exactement ce qu'on voit en jouant)
- [ ] Checklist de publication (`roblox-publish-checklist`), test avec de vrais joueurs
- [ ] Apres lancement : mises a jour regulieres (+10 a 20 fruits), evenements, offres limitees

## Decisions encore ouvertes (a trancher par l'utilisateur)

- Nom : **Sell a Juice** ou **Make a Juice**
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
