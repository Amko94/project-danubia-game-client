---
paths:
  - "modules/**"
  - "mods/**"
  - "layouts/**"
  - "data/**"
---

# Lua/content layer: modules, mods, layouts, data

Almost all user-facing behavior (windows, HUD, chat, inventory, minimap, hotkeys, market, etc.) is implemented here as Lua, not in `src/`. See `.claude/rules/cpp-engine.md` only if you actually need to touch the C++ framework or client engine itself.

## Modules (`modules/`)

Each module is its own directory containing:
- `<name>.otmod` — manifest (name, description, dependencies, `sandboxed`, which `.lua` scripts to load, and `@onLoad`/`@onUnload` hooks), in OTML format.
- one or more `.lua` files — logic.
- `.otui` files — declarative UI layout/style (OTUI format, similar to OTML), referencing styles from `data/styles/`.

Modules are namespaced by prefix and loaded in tiers by `init.lua`, controlled by numeric ranges configured per module:
- libraries: 0–99 (e.g. `corelib`)
- client-level modules: 100–499 (e.g. `client_*`)
- game modules: 500–999 (e.g. `game_*`)
- user mods: 1000–9999, in `mods/`

`mods/` is for local/server-specific customizations layered on top of the base `modules/`; `game-testModule` under `modules/` is a scratch/example module, not part of the load-order convention.

## Layouts (`layouts/`)

Full alternate UI skins (e.g. `retro`) with their own `images/`/`styles/`, selected via `DEFAULT_LAYOUT` in `init.lua` or the `layout` key in `config.otml`.

## Data files (`data/`)

Fonts (`.otfont`), cursors, shaders (GLSL `.frag`), sounds, locale strings (`data/locales/*.lua`), and shared `.otui` styles (`data/styles/`) consumed by modules. `things/` and `data/things` (gitignored) hold Tibia sprite/object data (`.dat`/`.spr`/`.otb`) — these are binary asset files, not source.