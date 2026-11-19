# Mission : coder la PHASE 1 du tycoon de jus (zone 1), et rien d'autre

Projet Roblox dans `D:\Usine` (Windows). Rojo sur le port 34850. Roblox Studio est pilote via MCP.
Tu ne connais pas le projet : lis d'abord, code ensuite. Fais la phase 1 en entier, puis arrete-toi.
L'utilisateur teste dans Studio et valide avant la phase 2.

## 1. Contexte

- Tycoon Roblox, nom provisoire "Sell a Juice" ou "Make a Juice". 6 bases par serveur, 3 de chaque cote d'une route.
- Boucle de la zone 1 :
  1. Un arbre fait tomber des fruits au hasard. Le joueur les ramasse en marchant dessus.
  2. Il les depose dans les bacs. Le presse-fruits fait 1 jus par fruit.
  3. Le joueur pose les jus sur le comptoir. Des clients achetent et laissent l'argent.
  4. Il ramasse l'argent, puis achete des ameliorations et des employes qui automatisent.
- 100 fruits = 10 raretes x 10 fruits. Avec 0 rebirth, 3 raretes sont ouvertes : Common, Uncommon et Rare (30 fruits).
- **Deja fait (phase 0) :** le game design complet et toute l'interface 2D cote client (HUD, boutique, offres limitees, ecran Welcome Back). Elle est visuelle seulement, rien n'est branche.
- **N'existe pas :** tout le gameplay serveur. `src/server/Services/` est vide. Il n'y a ni sauvegarde, ni argent reel, ni carte (verifier le Workspace dans Studio).

### A lire en premier, dans l'ordre

1. `AGENTS.md` (regles obligatoires)
2. `docs/README.md` (index), `docs/systems/_TEMPLATE.md` et `docs/journal/_TEMPLATE.md`
3. `docs/roadmap.md` (phases, decisions ouvertes, dette technique)
4. `docs/game-design.md` (zone 1, clients, carte, sauvegarde, tableau des decisions)
5. `docs/systems/fruits.md` (100 fruits, raretes, valeurs, Luck, plafond)
6. `docs/first-session.md` (rythme cible des 30 premieres minutes, pour l'equilibrage)
7. `docs/style.md`, puis `docs/architecture.md` et `docs/systems/interface.md`
8. Le dernier journal : `docs/journal/2026-11-19.md`
9. Le code : `src/server/Main.server.luau`, `src/client/Main.client.luau`, `src/shared/Config/*.luau`,
   `src/client/Controllers/MenuController.luau` (HUD, `Canvas.Money`, `SetBadge`) et `src/client/UI/PackStyle.luau`

## 2. Perimetre exact de la phase 1 (`docs/roadmap.md`)

### Sauvegarde (skill `roblox-data`)
- Choisir entre ProfileStore et DataStore (UpdateAsync, nouvelles tentatives, BindToClose, verrou de session). Proposer un choix et le justifier.
- Si ProfileStore est choisi : attendre l'accord de l'utilisateur (ARRET de l'etape Concevoir). Source : uniquement le depot officiel `MadStudioRoblox/ProfileStore`, avec la version et le commit notes. Ne rien executer d'autre du telechargement. Le placer cote serveur (ex. `src/server/Vendor/ProfileStore.luau`, pas dans `src/shared`), avec un fichier de licence et de source sur le modele de `.claude/skills/ROBLOX-BRAIN-NOTICE.md`. Wally n'est pas installe : ne pas l'installer sans accord.
- Champs de la phase 1 : `SchemaVersion`, `Money`, `Rebirths` (0), `TreeLuck`, `TreeSpeed`, `DiscoveredFruits`, les niveaux des ameliorations et des employes, `LastLogout`, `IntroSeen` (prevu pour la phase 2).
- Schema de reference : `game-design.md` > Sauvegarde. Les zones, les machines a cocktails et recettes et les boosts en cours (temps restant) arrivent en phases 3 et 4 : l'ecrire dans `sauvegarde.md`. Migration par `SchemaVersion` : une valeur par defaut pour chaque champ absent.
- Ne pas sauvegarder : les fruits au sol, les jus, l'argent pas encore ramasse.
- Nom du DataStore dans la Config (ex. `PlayerData_v1`) : les tests en Studio ecrivent dans le vrai DataStore de l'experience, et ce nom permet de repartir a zero avant le lancement.
- DataStores indisponibles (Studio sans acces API) : un avertissement clair, le jeu reste jouable, aucune sauvegarde n'est ecrasee.

### Argent, HUD et classement
- `MoneyService` est le seul a modifier l'argent (ajouter, depenser). L'argent n'est jamais negatif et le client ne le modifie jamais. Argent entier ou decimal : voir la section 7.
- HUD : afficher le vrai montant dans `HUD.Canvas.Money`, qui existe deja, avec les suffixes K/M/B/T. Le "+" jaune (packs d'argent) reste non branche.
- Classement (leaderstats) : argent et Rebirths, libelles en anglais.

### Carte et bases (dans Studio, PAS dans Rojo, skill `roblox-building`)
- Avant de construire : lire `docs/references/README.md` et regarder les captures `style-autre-jeu-*.webp`. Elles servent pour le style seulement : ne pas recopier la carte.
- La route, le spawn et 6 bases. Style blocky avec studs et couleurs vives (`docs/style.md`). Aucun z-fighting : decaler d'au moins 0.05 stud.
- Plan d'une base (schema dans `game-design.md`) : l'arbre, les bacs (1 par fruit), le presse-fruits et sa pile de jus, puis le comptoir et le tas d'argent cote route.
- Tableaux d'ameliorations places pres de ce qu'ils ameliorent :
  - Tree Speed et Tree Luck a cote de l'arbre ;
  - la limite de jus pres de la presse ;
  - la limite du comptoir et les clients au comptoir ;
  - les employes sur le mur du schema.

  Le schema ne montre qu'un seul mur : signaler cet ecart a l'etape Concevoir.
- Zones 2 et 3 : murs fermes (planches en croix et panneau rouge prevu pour le prix), non achetables en phase 1. Prix provisoire "A VALIDER" ou texte "Coming soon" : a demander a l'etape Concevoir.
- Une base est attribuee automatiquement a l'arrivee du joueur. Elle est liberee et nettoyee a son depart. Panneau "<Name>'s Juice Stand".
- Avec plus de 6 joueurs : pas d'erreur, un message propre.

### Arbre et fruits
- `src/shared/Config/Fruits.luau` : les 100 fruits (nom, rarete, valeur, couleur du jus, poids de tirage).
- Valeurs : les chiffres de `fruits.md` sont des exemples ("(ex.)"). Proposer la table dans la Config, puis la faire valider. Regles :
  - chaque rarete vaut environ x25 la precedente (table de `fruits.md`) ;
  - environ +20 % par fruit dans une rarete ;
  - le dernier fruit vaut moins que le premier de la rarete suivante ;
  - les 10 valeurs d'une rarete sont toutes differentes.

  Attention : avec Common = 1 et +20 %, les entiers se repetent (Apple 1, Orange 1,2 -> 1). Voir la section 7.
- `TreeService` fait tomber 1 fruit toutes les X secondes ; X depend du niveau Speed.
- Tirage selon le niveau Luck. Au niveau 1, seulement des pommes. Chaque niveau ajoute le fruit suivant avec une petite chance. Chaque nouveau fruit est plus rare que les precedents.
- Luck maximum = dernier fruit des raretes ouvertes = 10 x (raretes de depart (3, dans la Config) + Rebirths), plafonne a 100. Avec 0 rebirth : fruit 30 (Durian). Ne jamais ecrire 30 en dur.
- Un fruit ajoute par Luck et pas encore decouvert est garanti dans les N prochaines chutes (N dans la Config, ex. 3). L'Orange tombe donc vite au Luck 2 (`first-session.md` : "Orange garantie au Luck niv. 2").
- Plafond de 30 fruits au sol (dans la Config) : l'arbre s'arrete et affiche "Tree full!".
- Modeles blocky des 30 premiers fruits. Uncommon : contour vert. Rare : contour bleu. Proposer une forme commune avec des couleurs differentes pour commencer.
- "Premiere visite" = profil neuf (aucune donnee chargee) : 3 pommes sont deja au sol. Sans sauvegarde (Studio sans API), chaque session compte comme une premiere visite.
- La decouverte d'un fruit est enregistree (donnee seulement). L'annonce "NEW FRUIT!" et l'Index branche sont pour la phase 2.

### Ramassage, bacs, presse-fruits et jus
- Le serveur detecte le contact (position du personnage). Pas de remote "j'ai ramasse".
- Les fruits ramasses s'empilent au-dessus de la tete. La capacite est dans la Config.
- Marcher sur les bacs depose tous les fruits et les trie.
- Le presse-fruits se sert dans les bacs : 1 fruit = 1 jus (role du Presseur : section 7). **Prix du jus = valeur du fruit.**
- Les jus s'empilent a cote du presse-fruits, avec une limite ameliorable. Le joueur les prend et les pose sur le comptoir, dont la limite est aussi ameliorable.
- Au-dessus de la pile de jus et du comptoir : "n/max", et un "!" rouge quand c'est plein. Au-dessus du tas d'argent : le montant. Les gobelets prennent la couleur du jus du fruit (Config).

### Comptoir, clients et tas d'argent
- Chaque base a ses propres clients, jamais partages.
- Un minuteur serveur decide des ventes. Les PNJ blocky qui viennent de la route sont seulement visuels (legers, skill `roblox-npc-ai`).
- Un client prend 1 jus et laisse son prix sur le comptoir. Le tas d'argent affiche son montant.
- Le joueur marche sur le tas : l'argent est credite, avec une pluie de billets simple.
- Ameliorations : vitesse des clients et nombre de clients.

### Tableaux d'ameliorations et employes
- Chaque bouton est une tuile coloree (une couleur par type) et montre :
  - "valeur actuelle -> suivante" ;
  - le prix en argent (texte vert) ;
  - le prix en Robux (violet, avec l'icone Robux).

  La plaque Robux au sol est magenta neon.
- Achat en argent : verifie et applique par le serveur.
- Prix Robux : affiche depuis la Config, marque "A VALIDER". Aucun produit n'est cree et aucun achat Robux ne se fait en phase 1 (bouton inactif ou "Coming soon").
- Liste des ameliorations :
  - Tree Speed et Tree Luck ;
  - limite de jus et limite du comptoir ;
  - vitesse des clients et nombre de clients ;
  - employes : Ramasseur (fruits du sol vers les bacs), Presseur (section 7) et Serveur (jus vers le comptoir). Chaque employe est un PNJ visible et simple.
- Le premier Tree Speed doit etre payable avec l'argent des 3 premiers jus (achat vers 0:35).

### Remotes (skills `roblox-security` et `roblox-networking`)
- Le moins de remotes possible : le serveur detecte lui-meme les contacts.
- Un seul endroit pour les remotes : le decider et le documenter dans `docs/architecture.md`.
- Chaque remote est verifie cote serveur :
  - le type des arguments ;
  - l'id fait partie d'une liste connue ;
  - le joueur possede la base ;
  - la distance ;
  - le prix et le niveau maximum ;
  - le delai entre deux demandes.
- Le client n'envoie jamais de prix ni de montant.

### Hors perimetre (ne pas coder)
- Phase 2 : cinematique, fleches, guidage et tutoriel ; "NEW FRUIT!" et Index branche ; gains hors ligne et Welcome Back reel ; analytics ; gains acceleres du debut.
- Phase 3 : achats Robux (passes, produits, ProcessReceipt), boosts, cadeaux, offres, Auto Collect, Thief.
- Phase 4 : zones 2 et 3 (sauf les murs fermes), rebirth, les 70 autres fruits jouables.
- Phase 5 : sons de jeu, traduction, tests sur de vrais appareils, nom final, miniatures.
- Ne pas refactorer l'interface existante. Le doublon entre `ShopController` et `PackStyle` reste tel quel.

## 3. Regles du projet (resume de `AGENTS.md`, a lire en entier)

- **Une doc par systeme** dans `docs/systems/<nom>.md`, copiee depuis `_TEMPLATE.md`, creee avant ou pendant le code.
  - Decoupage propose : `sauvegarde.md`, `argent.md`, `carte-bases.md`, `chaine-production.md`, `clients.md`, `ameliorations-employes.md`.
  - Mettre a jour `fruits.md` et `interface.md`, et ajouter chaque nouvelle doc a `docs/README.md`.
- **Journal** dans `docs/journal/AAAA-MM-JJ.md` : on ajoute en bas, on ne reecrit jamais. Etre honnete sur ce qui n'a pas ete teste.
- **Le serveur decide de tout.** Toutes les valeurs (prix, vitesses, limites, recompenses) vont dans `src/shared/Config/`, jamais en dur ailleurs.
- Code :
  - service serveur ou controleur client = ModuleScript avec `Init()` (preparer, sans attendre) et `Start()` (boucles et connexions) ; `Main` les charge tout seul ;
  - `--!strict` et extension `.luau` ;
  - `task.*` uniquement ; deconnecter les connexions et tout nettoyer au depart du joueur ;
  - noms de code en anglais ; doc et commentaires en francais.
- **Tout ce que le joueur voit est en anglais.** Laisser `AutoLocalize` actif.
- Correspondance Rojo : `src/server` -> `ServerScriptService.Server`, `src/client` -> `StarterPlayerScripts.Client`, `src/shared` -> `ReplicatedStorage.Shared`, `src/gui` -> `StarterGui`. Workspace et ServerStorage ne sont pas geres par Rojo : ne pas ajouter de mapping sans en parler.
- Les fichiers sur disque font reference. Une correction faite via MCP est reportee sur disque dans la meme intervention. Ne jamais activer Script Sync en meme temps que Rojo.
- Skills : charger d'abord `roblox-collaboration-mode`, puis lire le `SKILL.md` du sujet (et `references/full.md` si besoin) :
  - conception : `roblox-game-design` et `roblox-architecture` ;
  - sauvegarde : `roblox-data` ;
  - remotes et argent : `roblox-security` et `roblox-networking` ;
  - carte : `roblox-building` ; PNJ : `roblox-npc-ai` ; HUD : `roblox-gui` ; Studio : `roblox-studio-mcp`.

  Avant de dire "fini" : relire le code avec `roblox-security` et `roblox-luau-patterns`.
- Icones : les prendre dans `D:\Downloads\ICONSPACK`, les copier dans `assets/icons/`, les mettre en ligne et noter leur id dans `Config/Icons.luau`.

## 4. Pieges connus

- **Rien n'est commite** depuis la creation du projet. Le git status contient aussi le remplacement de `.claude/skills/roblox-dev` par `.claude/skills/roblox-*`. Ne jamais commiter ni pousser sans accord (voir l'etape 1).
- **Studio :** la place "usine" (placeId 93027930223227) est deja liee a l'experience 10777527378. Plusieurs Studio peuvent etre ouverts : cibler "usine" avec `list_roblox_studios`.
- **DataStores en Studio :** l'utilisateur doit activer Game Settings > Security > "Enable Studio Access to API Services". Si l'acces est absent, le dire et marquer la sauvegarde "non testee".
- **`save_place`** cree une version dans le cloud (ce n'est pas une publication). Sauvegarder a chaque point d'arret et apres chaque base construite, pas apres chaque petite modification.
- **Ne jamais publier** sur Roblox. Ne creer aucun pass ni produit payant sans accord explicite : les prix ne sont pas valides.
- **Permissions.** Si un outil, un dossier, une URL HTTP ou un acces API est refuse : s'arreter et demander a l'utilisateur. Ne jamais modifier soi-meme :
  - les reglages de Studio (Game Settings, Security, liste HTTP, permissions MCP de l'Assistant) ;
  - `.claude/settings*.json` ;
  - `HttpEnabled` (force a false dans `default.project.json`).

  Ne jamais contourner un refus par un autre chemin (serveur local, script, autre outil MCP).
- **Assets.**
  - Construire avec des Parts, par script (style blocky).
  - Pas d'`insert_asset` de modeles gratuits du Creator Store : ils peuvent contenir des scripts caches.
  - Pas d'outils `generate_*` sans accord.
  - Mettre en ligne seulement les icones vraiment utilisees, jamais d'images d'essai. Lister chaque id mis en ligne dans le rapport et dans `Config/Icons.luau`.
- **Studio a plante deux fois** sur de gros traitements en un seul appel MCP. Travailler par petits morceaux (une base ou un modele a la fois), avec `task.wait()` entre les morceaux.
- **Si Studio plante ou ne repond plus :**
  - ne pas relancer le meme appel ;
  - ecrire l'etat dans le journal (lot, etape, ce qui est fait) ;
  - demander a l'utilisateur de rouvrir Studio et Rojo ;
  - reprendre en plus petit.

  Si la session devient tres longue : s'arreter proprement a la fin d'un lot, avec le journal et les docs a jour, pour qu'un nouveau chat puisse reprendre.
- **Les `.rbxm` de `src/gui` se modifient mal** : le HTTP `127.0.0.1:34851` est refuse dans "usine". Ne pas y toucher. Placer et brancher le HUD par code, comme le fait deja `MenuController`.
- **Tout ce qui est construit dans Studio** (carte, modele de base, fruits, PNJ) doit pouvoir etre reconstruit depuis le disque, car `*.rbxl` est ignore par git. Recommandation : les fruits et les PNJ sont generes par code depuis la Config (dans `src/`) ; la carte et les bases viennent d'un script de construction hors `src/` (ex. `tools/build-map/`), relance par morceaux via `execute_luau`.
- Rojo doit tourner (`start-rojo.bat`) et Studio doit etre connecte a `localhost:34850`. Sinon, demander a l'utilisateur.
- La taille de serveur de 6 est un reglage d'experience que l'utilisateur fera. Le code doit quand meme gerer un 7e joueur.
- Simulateur telephone : le clic simule ne marche pas en mode tactile. Remettre le simulateur par defaut apres les tests.
- StyLua et Selene ne sont pas installes : le formatage et l'analyse ne sont pas verifies, le dire.
- Garder les demos Studio telles quelles (`SHOW_DEMO_IN_STUDIO` : Welcome Back et pastille).

## 5. Comment travailler en ultracode

**Regles multi-agents :**
- maximum 3 agents en parallele, seulement pour LIRE (docs, code, skills) ou RELIRE (revue) ;
- un seul agent a la fois utilise les outils MCP de Studio (construction, `execute_luau`, playtest, captures), jamais deux appels Studio en meme temps ;
- chaque fichier n'a qu'un seul agent qui l'ecrit pendant un lot ;
- le journal, `docs/README.md` et `docs/roadmap.md` sont ecrits uniquement par l'orchestrateur.

Enchainer des workflows courts. Ne jamais lancer tous les systemes d'un coup sans verification.
A chaque ARRET et a la fin de chaque lot : ajouter une entree en bas de `docs/journal/<date du jour>.md` (creer le fichier depuis `_TEMPLATE.md` si la date a change), et mettre a jour la doc du systeme (statut : a concevoir -> en cours -> fonctionne).

1. **Comprendre.** Lire les docs et le code (agents en parallele). Verifier l'etat de Studio : carte presente ? Rojo connecte ? Acces API ?
   - Rendre un resume de 10 lignes.
   - Proposer le commit de l'etat actuel (liste des fichiers, message) sans attendre la reponse, puis continuer.
   - Ne modifier aucun fichier de `src/` avant l'ARRET.
2. **Concevoir.**
   - Liste des services et controleurs, schema de sauvegarde, liste des remotes et de leurs verifications.
   - Fichiers de Config avec des valeurs de depart, plan d'une base, ordre des lots.
   - Creer les docs `docs/systems/*.md` (statut "a concevoir").
   - Poser les questions de la section 7, avec une recommandation pour chacune.
   - **ARRET : l'utilisateur valide le commit et la conception ensemble.** Faire le commit (s'il est accepte) AVANT le lot A. Ne jamais pousser.
3. **Implementer par lots, dans l'ordre des dependances :**
   - A : Config, sauvegarde, argent, HUD et classement.
   - B : carte, 6 bases et attribution. **Point d'arret : montrer des captures du style de la carte avant de continuer.**
   - C : arbre, fruits, ramassage, bacs, presse-fruits et jus.
   - D : comptoir, clients et tas d'argent.
   - E : tableaux d'ameliorations et employes.

   Apres chaque lot : `rojo build`, un playtest court via MCP, la console, puis un point de 3-5 lignes a l'utilisateur. S'arreter seulement en cas de blocage ou de decision a prendre.
4. **Revue adversariale**, avec des agents separes qui n'ont pas ecrit le code :
   - securite : remotes, argent duplique, triche sur les distances ou le debit, base d'un autre joueur ;
   - Luau : strict, fuites de connexions, nettoyage au depart du joueur, boucles serveur couteuses ;
   - sauvegarde : perte, ecrasement, BindToClose, deux sessions en meme temps.

   Corriger, ou lister ce qui reste.
5. **Playtest Studio via MCP.**
   - Outils : `start_stop_play`, `character_navigation`, `get_console_output` et `screen_capture`.
   - Captures sur PC et sur le simulateur telephone en paysage (Galaxy A06).
   - Tester la boucle complete, puis quitter et relancer pour verifier la sauvegarde.
6. **Cloture.**
   - Docs a jour et entree de journal.
   - Dans `docs/roadmap.md` : cocher et dater seulement les points verifies en playtest. Marquer les autres "(code, a valider par l'utilisateur)" ou "(non teste : raison)". La phase 1 est cochee en entier seulement apres la validation de l'utilisateur.
   - `rojo build default.project.json -o test-build.rbxl` passe, puis supprimer le fichier.
   - Place sauvegardee. Rapport final.

## 6. Definition de "fini" pour la phase 1

- [ ] En playtest, un nouveau joueur :
  - recoit une base a son nom et voit des pommes tomber ;
  - ramasse, depose, obtient des jus, les pose sur le comptoir ;
  - voit un client acheter, ramasse l'argent, et le HUD et le classement se mettent a jour ;
  - achete Tree Speed, puis Tree Luck : l'Orange tombe ;
  - embauche les 3 employes, puis le stand tourne seul.
- [ ] "Tree full!" apparait a 30 fruits au sol. Les limites de jus et de comptoir sont respectees et ameliorables.
- [ ] L'argent et les niveaux sont sauvegardes et retrouves apres avoir quitte puis relance. Si ce n'est pas testable, l'ecrire clairement.
- [ ] Avec 2 joueurs (Test > Clients and Servers) : bases differentes, rien de melange. Si ce n'est pas faisable via MCP, le mettre dans "a tester".
- [ ] Console serveur et client : aucune erreur venant de nos scripts. Aucun avertissement, sauf ceux qui sont voulus et listes dans le rapport (ex. "DataStore indisponible, sauvegarde desactivee").
- [ ] Revue de securite et de Luau faite. Les problemes trouves sont corriges ou listes.
- [ ] Captures sur PC et sur le simulateur telephone : argent lisible ; tableaux d'ameliorations visibles, lisibles et de taille correcte ; aucun z-fighting visible. L'utilisation au toucher (vrai telephone) va dans "A tester toi-meme".
- [ ] Docs des systemes, `README.md`, `architecture.md`, `roadmap.md` (selon la regle de cloture) et journal a jour.
- [ ] `rojo build` passe et la place est sauvegardee.

**A rendre a l'utilisateur, puis S'ARRETER (ne pas commencer la phase 2) :**
1. **Verifie** : ce qui a ete teste et comment (playtest, captures, console).
2. **Pas verifie** : par exemple la sauvegarde sans acces API, le vrai telephone, plusieurs joueurs, StyLua et Selene.
3. **A tester toi-meme dans Studio** : 5 a 8 etapes concretes (jouer 5 minutes, quitter puis revenir, tester a 2 joueurs, telephone).
4. Les valeurs d'equilibrage proposees, en tableau, et ou les changer dans la Config.
5. Les questions encore ouvertes, les ids d'images mis en ligne et la proposition de commit.

## 7. Decisions ouvertes

**Elles touchent la phase 1. Les poser a l'etape "Concevoir", avec une recommandation pour chacune :**
- Le role exact du **Presseur**.
  - Recommandation : la presse est automatique des le debut et se sert dans les bacs. C'est le plan de `first-session.md` : a 0:15, on depose et la presse fait 3 jus ; le guidage va "vers les bacs, puis vers les jus", sans etape a la presse. Le Presseur la rend plus rapide, ou ajoute une 2e presse.
  - A eviter : obliger le joueur a se tenir sur une plaque pour presser. Cette etape est absente du plan de la premiere minute.
- La capacite de la pile au-dessus de la tete : fixe, ou ameliorable ?
- L'interaction avec les tableaux : plaque au sol a fouler, ou ProximityPrompt ? Elle doit marcher sur telephone. Recommandation : plaque au sol (`style.md` : boutons Robux "au sol", magenta neon), a verifier sur telephone.
- Autres choix :
  - ProfileStore ou DataStore ;
  - le modele de base : 1 modele dans ServerStorage clone 6 fois, ou 6 bases placees a la main ;
  - l'emplacement des remotes ;
  - prix provisoire ou "Coming soon" sur les murs des zones 2 et 3.
- **Argent entier ou decimal.** Recommandation : argent toujours entier. Arrondir les valeurs dans `Fruits.luau`, avec une echelle choisie pour que les 10 Common aient tous des valeurs differentes (ex. Apple = 5). Sinon, garder Common = 1 et accepter des doublons. Le premier Tree Speed reste payable avec 3 jus.
- **Equilibrage : ne pas trancher seul.** Proposer des valeurs de depart dans la Config, modifiables, et un tableau dans la doc.
  - Cibles de rythme (`first-session.md`) :
    - Tree Speed a 0:35 ;
    - Orange (Luck 2) vers 1:00-1:30 ;
    - Ramasseur vers 2:30 ;
    - Banane (Luck 3) et amelioration "limite du comptoir" vers 4:00 ;
    - Presseur vers 5:00 ;
    - Fraise (fruit 11, donc Luck 11) vers 7:00 ;
    - Serveur vers 9:00 ;
    - ameliorations des clients vers 11:00 ;
    - Dragon Fruit (fruit 21, Luck 21) vers 20:00, cible indicative car le plan met la zone 2 avant.
  - `first-session.md` prevoit des gains acceleres (phase 2). En phase 1, approcher ces cibles avec les seuls prix de la Config, et noter l'ecart dans le tableau d'equilibrage.
- Les prix Robux des tableaux : valeurs provisoires dans la Config, marquees "A VALIDER", sans produit cree.

**Elles ne bloquent PAS la phase 1 : ne pas les trancher, ne pas coder autour :**
- le nom final (ne pas changer `GameConfig.GameName`) ;
- les prix des passes et des packs ;
- Rebirth Master a -50 % ;
- la duree de la cinematique ;
- les recompenses quotidiennes ;
- les regles du pass Thief.
