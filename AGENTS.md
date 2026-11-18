# Mon usine de boissons : regles pour les agents IA

Jeu Roblox de type tycoon : le joueur construit et agrandit une usine de boissons.
Ces regles s'appliquent a tout agent (Claude Code, Codex, Cursor...). Les suivre a chaque intervention.

## 1. Avant de commencer une tache

1. Lire ce fichier en entier.
2. Lire `docs/README.md` (index de la doc) et le dernier fichier de `docs/journal/`.
3. Lire la doc du ou des systemes touches dans `docs/systems/`.
4. **Revoir le skill.** Ouvrir `.claude/skills/roblox-dev/SKILL.md`, suivre sa table de routage
   et lire les fichiers du sujet (`quick.md`, puis `full.md` si besoin) AVANT d'ecrire du code.
   - Nouveau systeme de tycoon : `.claude/skills/roblox-dev/genres/genre-tycoon.md`.
   - Argent, achats, remotes : `brain/core/roblox-security` + `brain/core/roblox-networking`.
   - Sauvegardes : `brain/core/roblox-data`.
   - Avant de dire "fini" : `workflows/code-review.md`.
   - Respecter les regles de conflit du skill (ProfileStore, noms d'outils MCP actuels, `task.*`).

## 2. Documentation : un fichier .md par systeme (obligatoire)

- Chaque systeme du jeu a sa doc : `docs/systems/<nom-du-systeme>.md`, copiee depuis
  `docs/systems/_TEMPLATE.md`. Exemples : `argent.md`, `machines.md`, `chaine-production.md`,
  `sauvegarde.md`, `boutique.md`.
- Creer la doc **avant ou pendant** le code du systeme, jamais apres coup.
- A chaque modification d'un systeme : mettre a jour sa doc dans la meme intervention
  (fichiers, remotes, donnees sauvegardees, regles, problemes connus).
- Ajouter chaque nouvelle doc a l'index `docs/README.md`.
- Decisions de conception du jeu : `docs/game-design.md`. Organisation du code : `docs/architecture.md`.
- Ecrire la doc en francais, simple et courte. Une doc fausse est pire qu'une doc absente.

## 3. Journal : a la fin de CHAQUE intervention (obligatoire)

- Fichier du jour : `docs/journal/AAAA-MM-JJ.md` (le creer s'il n'existe pas, depuis `_TEMPLATE.md`).
- Ajouter une entree en bas du fichier avec : heure, demande, ce qui a ete fait, fichiers
  modifies, ce qui a ete verifie (et comment), ce qui reste a faire ou a verifier.
- Ne jamais reecrire les anciennes entrees : on ajoute seulement.
- Etre honnete : si rien n'a ete teste dans Studio, l'ecrire.

## 4. Rojo et Studio

- Projet : `default.project.json`, **port 34850**. Lancer : `start-rojo.bat`. Arreter : `stop-rojo.bat`.
- Dans Studio : plugin Rojo > Connect > `localhost:34850`.
- Les fichiers sur disque (`src/`) font reference. Modifier les fichiers d'abord ; ne jamais
  corriger un script uniquement dans Studio. Si une correction passe par MCP, reporter la meme
  source sur disque dans la meme intervention.
- Correspondance :
  - `src/server/`  -> `ServerScriptService.Server`  (`Services/` : un ModuleScript par systeme serveur)
  - `src/client/`  -> `StarterPlayerScripts.Client` (`Controllers/` : un ModuleScript par systeme client)
  - `src/shared/`  -> `ReplicatedStorage.Shared`    (config, types, utilitaires partages)
  - `src/gui/`     -> `StarterGui`
- Workspace (carte, machines placees a la main) et ServerStorage ne sont pas geres par Rojo :
  ils vivent dans le fichier .rbxl. Ne pas ajouter de mapping pour eux sans en discuter.
- Ne jamais activer Script Sync de Studio et Rojo sur les memes scripts.
- Ne jamais publier sur Roblox sans demande explicite.

## 5. Conventions de code

- Luau avec `--!strict` en tete de chaque fichier ; extension `.luau`.
- Service serveur / controleur client = ModuleScript qui retourne une table avec `Init()`
  (preparer, sans attendre) et `Start()` (lancer les boucles et connexions). `Main` les charge tout seul.
- **Le serveur decide de tout** : argent, prix, production, achats. Le client affiche et envoie
  des demandes ; chaque RemoteEvent est verifie cote serveur (type, valeurs, possession, delai).
- Prix, vitesses de production et recompenses dans `src/shared/Config/`, jamais en dur ailleurs.
- `task.wait` / `task.spawn` / `task.delay` uniquement. Deconnecter les connexions inutiles.
- Noms de code en anglais (`MoneyService`, `MachineController`), doc et commentaires en francais.
- Formatage : StyLua (`stylua.toml`). Analyse : Selene (`selene.toml`), si installes.

## 6. Fin d'intervention

1. Doc du systeme a jour. 2. Entree de journal ajoutee. 3. `rojo build default.project.json -o test-build.rbxl` passe (fichier ignore par git, a supprimer apres).
4. Dire a l'utilisateur ce qui est verifie dans Studio et ce qui ne l'est pas.
