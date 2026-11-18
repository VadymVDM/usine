---
name: roblox-dev
description: >
  Roblox game development: Luau, Roblox Studio (MCP), architecture, networking, DataStores,
  security, performance, GUI, physics, NPCs, game design, monetization, publishing, and
  genre templates (simulator, tycoon, obby, RPG, horror, battle royale). Use for building,
  changing, fixing, debugging, reviewing or auditing any Roblox game or Luau code.
when_to_use: >
  Any Roblox or Luau task: new game, feature, bug ("data not saving", "lag", "UI overlaps on
  mobile", "exploit"), Studio playtest, code review, security or monetization audit, publishing.
---

# Roblox Dev (merged skill)

This skill merges two sources into one router. Load ONLY the files a task needs.

- `brain/` — **roblox-brain** (MIT, recent, source-checked). **Primary authority.**
- `genres/`, `workflows/`, `extra/` — **roblox-game-skill**: genre templates, step-by-step
  workflows, and topics brain does not cover (combat, inventory, sharp edges, testing).

Each brain topic has `quick.md` (short, read first) and `full.md` (read only when needed).

## Step 0 — always

1. Read `brain/core/roblox-collaboration-mode/quick.md` (how much to decide alone vs ask).
2. If Roblox Studio MCP tools are present (`list_roblox_studios`, `execute_luau`, …), read
   `brain/tools/roblox-studio-mcp/quick.md` before touching Studio. Otherwise work offline:
   give copy-paste Luau with where each script goes, and say what was not verified.

## Conflict rules (important)

`brain/` wins whenever it disagrees with `genres/`, `workflows/` or `extra/`, which are older:

| Older content says | Do instead |
|---|---|
| `ProfileService` | `ProfileStore` or the patterns in `brain/core/roblox-data` |
| `MCP_MODE` "full" / "standard" / "offline" | Official Roblox Studio MCP = full capability; no MCP = offline |
| `run_code` | `execute_luau` |
| `insert_model` | `insert_asset` (or `search_asset` first) |
| `get_file_tree`, `get_project_structure`, `search_objects` | `search_game_tree`, `inspect_instance` |
| `grep_scripts` / `get_script_source` | `script_grep` / `script_read` |
| `start_playtest` / `stop_playtest` | `start_stop_play` |
| `get_playtest_output` | `get_console_output` |
| `create_build` | `multi_edit`, `execute_luau`, `generate_*` tools |
| `BodyVelocity` / `BodyPosition` / `BodyGyro` | constraints: `LinearVelocity`, `AlignPosition`, `AlignOrientation` |
| `wait()`, `spawn()`, `delay()` | `task.wait`, `task.spawn`, `task.delay` |

Template code is illustrative: adapt it to the project and verify in Studio before calling it done.

## Routing table

| Intent | Load |
|---|---|
| **Build a new game** | `workflows/new-game.md` + `genres/game-scaffold.md` + `genres/genre-{simulator,tycoon,obby,rpg,horror,battle-royale}.md` + `brain/design/roblox-game-design` |
| Fix a bug / debug | `workflows/debug-loop.md` + the topic below + `extra/sharp-edges.md` |
| Code review | `workflows/code-review.md` + `brain/core/roblox-luau-patterns` |
| Security audit / exploits | `workflows/security-audit.md` + `brain/core/roblox-security` + `brain/core/roblox-networking` |
| Performance audit / lag / FPS | `workflows/performance-audit.md` + `brain/core/roblox-performance` |
| Monetization audit | `workflows/monetization-audit.md` + `brain/design/roblox-monetization` |
| Ready to publish | `brain/tools/roblox-publish-checklist` + `workflows/publish-checklist.md` |
| Luau syntax / basics | `brain/core/roblox-luau-core` |
| Modules, signals, cleanup, tasks | `brain/core/roblox-luau-patterns` |
| Type annotations / strict mode | `brain/core/roblox-luau-types` |
| Code layout, services, startup | `brain/core/roblox-architecture` |
| RemoteEvents / client-server | `brain/core/roblox-networking` |
| Player saves / DataStore | `brain/core/roblox-data` |
| Leaderboards, cross-server, MemoryStore | `brain/core/roblox-server-data` |
| Combat, hitboxes, weapons, damage | `extra/combat-systems.md` + `brain/core/roblox-security` |
| Inventory, items, equipment | `extra/inventory-systems.md` + `brain/core/roblox-data` |
| Tests | `extra/testing-patterns.md` + `brain/tools/roblox-tooling` |
| Common gotchas | `extra/sharp-edges.md` |
| UI / HUD / shops / mobile layout | `brain/gameplay/roblox-gui` |
| Input (touch, gamepad, keys) | `brain/gameplay/roblox-input` |
| Camera | `brain/gameplay/roblox-camera` |
| Physics, vehicles, projectiles | `brain/gameplay/roblox-physics` |
| NPCs, enemies, pathfinding | `brain/gameplay/roblox-npc-ai` |
| Building maps / generated assets | `brain/gameplay/roblox-building` |
| Animation / VFX / tweens | `brain/gameplay/roblox-animation-vfx` |
| Audio | `brain/gameplay/roblox-audio` |
| Lighting / atmosphere | `brain/gameplay/roblox-lighting` |
| Translation | `brain/gameplay/roblox-localization` |
| Game design, core loop, FTUE | `brain/design/roblox-game-design` |
| Retention, rewards, pricing psychology | `brain/design/roblox-player-psychology` |
| Growth, discovery, LiveOps | `brain/design/roblox-growth-design` |
| Analytics | `brain/design/roblox-analytics` |
| GamePasses, Dev Products | `brain/design/roblox-monetization` |
| Rojo, Wally, Selene, CI | `brain/tools/roblox-tooling` |
| Open Cloud, API keys, webhooks | `brain/tools/roblox-cloud` |
| Working in Studio via MCP | `brain/tools/roblox-studio-mcp` |

A `brain/...` entry means: read its `quick.md`, then its `full.md` only if needed.
When a brain file mentions another skill in backticks (`roblox-data`), it means the folder of
the same name under `brain/`. If the intent is unclear, ask one short question, then route.

## Golden rules

- **Never trust the client.** Validate type, range, ownership, state and cooldown on the server
  for every remote. Prices, damage and rewards come from server-side definitions.
- Currency math happens on the server only; the client only displays it.
- `ProcessReceipt`: grant first, then return `PurchaseGranted`; if granting fails, `NotProcessedYet`.
- Disconnect every connection you create (Trove/Maid or explicit cleanup).
- Wrap DataStore calls in `pcall`, use session locking, never raw `SetAsync` for player data.
- In Studio: read before writing, read back after writing, playtest to verify.
