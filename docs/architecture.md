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
les modeles places a la main restent dans le fichier .rbxl.

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
- Les remotes seront regroupes dans un seul endroit (a decider au premier systeme qui en a besoin,
  puis documenter ici).
