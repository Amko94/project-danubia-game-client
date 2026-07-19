---
paths:
  - "src/**"
---

# C++ layer: framework vs. client (src/)

`src/framework/` and `src/client/` are the C++ layer. Nearly all game UI, screens, and feature logic instead lives as Lua **modules** under `modules/` — if a task is about UI, HUD, chat, inventory, minimap, hotkeys, or similar user-facing behavior, check `.claude/rules/content-system.md` instead; you're almost never meant to edit `src/` for that.

## framework vs. client

- `src/framework/` — engine-agnostic-to-Tibia framework: `core/` (application loop, event dispatcher, module manager, resource manager, config), `graphics/` (OpenGL painter, textures, framebuffers, shaders), `ui/` (widget tree, layouts, anchor system), `net/` (raw connection/protocol/message framing), `luaengine/` (Lua↔C++ binding layer — `luaobject`, `luainterface`, `luavaluecasts`), `otml/` (the custom YAML-like config format used for `.otml`/`.otmod` files), `platform/` (window creation per-OS, crash handler), `sound/`, `http/`.
- `src/client/` — Tibia-specific game logic on top of the framework: `game.cpp`/`game.h` (game state, actions), `map.cpp`/`mapview.cpp`/`tile.cpp` (world rendering), `creature.cpp`/`player.cpp`/`localplayer.cpp`, `item.cpp`/`itemtype.cpp`/`thing.cpp`/`thingtype.cpp` (the Tibia "thing" type system, sprites/appearances), `protocolgame.cpp` + `protocolgameparse.cpp` + `protocolgamesend.cpp` (the actual Tibia binary protocol — incoming packet parsing and outgoing packet building are split into separate files), `protocolcodes.h` (opcode tables), `uiitem.cpp`/`uicreature.cpp`/`uimap.cpp`/`uiminimap.cpp` (game-aware UI widget subclasses).
- Every new file added to either layer must be registered in the corresponding `CMakeLists.txt` (`src/framework/CMakeLists.txt` or `src/client/CMakeLists.txt`) — CMake here uses explicit file lists, not globs.
- C++ objects are exposed to Lua via `luafunctions.cpp`/`luafunctions_client.cpp` and the `luaengine/` binder; Lua-side value conversion for client types lives in `luavaluecasts_client.cpp`.

## Networking model

The client speaks the Tibia binary protocol over TCP (or an HTTP/WebSocket login handshake, see `src/framework/http/`). `protocolgame.cpp` owns the connection lifecycle; `protocolgameparse.cpp` decodes server→client messages by opcode into calls on `g_game`/`g_map`/etc.; `protocolgamesend.cpp` encodes client→server requests. There's also a packet recorder/player (`net/packet_recorder.*`, `net/packet_player.*`) for capturing and replaying network traffic, and an optional proxy client (`proxy/proxy_client.*`) for routing through OTCv8's proxy system.

## Build notes specific to src/

- `CMakeLists.txt` hardcodes dependency paths to `C:/vcpkg/installed/x64-windows/...` — if vcpkg is installed elsewhere, those paths in `src/framework/CMakeLists.txt` need updating before configuring.
- Key CMake options (in `CMakeLists.txt` / `src/framework/CMakeLists.txt`): `LUAJIT`, `CRASH_HANDLER`, `USE_STATIC_LIBS`, `USE_LTO`, `FRAMEWORK_SOUND` (off by default), `FRAMEWORK_GRAPHICS`, `FRAMEWORK_XML`, `FRAMEWORK_NET`.
- `WITH_ENCRYPTION` is always defined in the top-level `CMakeLists.txt` for this fork.
- Boost/OpenSSL/etc. versions in `src/framework/CMakeLists.txt` are pinned to specific vcpkg lib file names (e.g. `boost_system-vc143-mt-x64-1_88.lib`) — bumping vcpkg may require updating these paths.