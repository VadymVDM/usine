# Architecture

## Rojo

`default.project.json`, port 34850.

| Disque | Studio |
|---|---|
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared/` | `ReplicatedStorage.Shared` |
| `src/gui/` | `StarterGui` |

Workspace et ServerStorage ne sont pas geres par Rojo (`$ignoreUnknownInstances`) : la carte et
les modeles restent dans le fichier .rbxl. Ils sont construits par les scripts de
`tools/build-map/` (hors Rojo, relances via MCP `execute_luau`) : voir `docs/systems/carte-bases.md`.
Au demarrage, `BaseService` clone `ServerStorage.BaseTemplate` dans `Workspace.Bases`.

## Demarrage

- `src/server/Main.server.luau` charge chaque ModuleScript de `src/server/Services/`.
- `src/client/Main.client.luau` charge chaque ModuleScript de `src/client/Controllers/`.
- Ordre : `Init()` de tous les modules, puis `Start()` de tous (chacun dans son propre thread).
  Une erreur dans un module est affichee dans la console sans bloquer les autres.

Modele de service :

```luau
--!strict
local MoneyService = {}

function MoneyService:Init()
	-- preparer : tables, remotes. Ne pas attendre ici.
end

function MoneyService:Start()
	-- lancer : connexions, boucles.
end

return MoneyService
```

## Partage

- `src/shared/Config/GameConfig.luau` : valeurs globales du jeu.
- `src/shared/Assets/` : objets Roblox en `.rbxm` (sons de l'interface...).
- `src/shared/Vendor/` : librairies externes en `.rbxm` (TopbarPlus, licence MIT).
- `src/gui/*.rbxm` : interfaces (ScreenGui) en binaire, sans script ; la logique est dans `src/client/Controllers/`.
- `src/server/Vendor/` : librairies serveur en source (ProfileStore, Apache 2.0, voir
  `NOTICE-ProfileStore.md`). Pas charge par `Main` (seuls les ModuleScripts de `Services/` le sont).
- `src/shared/Util/` : petites fonctions pures partagees (`NumberFormat`, `TextUtil`).
- `src/shared/Network/Remotes.luau` : la liste des remotes (voir plus bas).

## Remotes (decide le 2026-11-19, phase 1)

- Le moins possible : le serveur detecte lui-meme les contacts (fruits, bacs, comptoir, tas
  d'argent, plaques d'achat). En phase 1 : **aucun remote client -> serveur**.
- Un seul endroit : `src/shared/Network/Remotes.luau` liste les noms. Le serveur cree
  `ReplicatedStorage.Remotes` et les RemoteEvents (`Remotes.GetServerEvent`, appele dans
  `NotifyService:Init`), le client les attend avec un delai de 15 s (`Remotes.WaitClientEvent`).

| Remote | Sens | Envoye par | Contenu | Verifications |
|---|---|---|---|---|
| `Notify` | serveur -> client | `NotifyService.Notify(player, texte)` | texte anglais de la Config, coupe a `Map.MaxNotifyLength` | client : type string, UTF-8, longueur |

- Interactions sans remote : contacts detectes par le serveur (positions), et `ClickDetector` des
  zones fermees (serveur : joueur valide + delai, texte de la Config).
- Chaque remote client -> serveur futur est verifie cote serveur : type, id connu, possession de
  la base, distance, prix / niveau max, delai entre deux demandes. Le client n'envoie jamais de
  prix ni de montant.

## Donnees joueur

- `DataService` ouvre/ferme les sessions (ProfileStore). Chaque champ a un seul module qui le
  modifie (voir `docs/systems/sauvegarde.md`). Les autres modules s'abonnent avec
  `DataService.OnPlayerLoaded` / `OnPlayerRemoving` (l'ordre des `Start()` n'est pas garanti).

## Bases

- `BaseService` (seul a ecrire `OwnerUserId` sur les bases et `BaseId` sur les joueurs) :
  `GetBase(player)`, `GetOwner(base)`, `GetBases()`, `OnBaseAssigned(cb)`, `OnBaseReleased(cb)`.
  Les services des lots C a E rangent ce qu'ils creent dans `Base.Dynamic` (vide au depart) et
  arretent leurs boucles dans `OnBaseReleased`.

## Tests en Studio

- `DebugService` (actif seulement dans Studio) : `ServerStorage.Debug.Call` (BindableFunction).
  Un `require` depuis la barre de commande ou MCP cree une copie separee des modules : passer par
  ce BindableFunction pour appeler les vrais services pendant un playtest.
