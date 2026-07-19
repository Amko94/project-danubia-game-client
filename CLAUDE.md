# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

This is **OTClientV8** (a fork/dev-edition of OTClient), a C++17 game client for Open Tibia servers. It's a hybrid
C++/Lua application: a C++ "framework + client" engine provides low-level systems (rendering, networking, Lua
bindings, windowing), while nearly all game UI, screens, and feature logic are implemented as Lua **modules** loaded
at runtime. This particular checkout ("project-danubia") is a custom server client build (custom outfits, custom
minimap, etc.), not vanilla OTClientV8.

- `src/framework/` and `src/client/` — the C++ engine. See `.claude/rules/cpp-engine.md` for architecture and the networking model.
- `modules/`, `mods/`, `layouts/`, `data/` — the Lua/UI content layer. See `.claude/rules/content-system.md` for structure.

When a task is about UI, HUD, chat, inventory, minimap, hotkeys, or similar user-facing behavior, you almost always
want to edit `modules/` (or `mods/`), not `src/`.

## Build

Windows is the primary target here (vcpkg + MSVC). `CMakeLists.txt` hardcodes dependency paths to
`C:/vcpkg/installed/x64-windows/...` — if vcpkg is installed elsewhere, those paths in
`src/framework/CMakeLists.txt` need updating before configuring.

```
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build .
```

Required vcpkg packages (x64-windows): boost-iostreams, boost-asio, boost-beast, boost-system, boost-variant,
boost-lockfree, boost-process, boost-program-options, luajit, glew, boost-filesystem, boost-uuid, physfs,
openal-soft, libogg, libvorbis, zlib, libzip, openssl.

There's also a Visual Studio solution at `vc16/otclient.sln` and a CLion CMake profile setup (Debug/Release) in
`.idea/` — both drive the same top-level `CMakeLists.txt`.

Linux: vcpkg + boost >=1.67, libzip-dev, physfs >= 3, gcc >= 9, then `mkdir build && cd build && cmake .. && make -j8`.

## Running

The built executable (`otclient.exe` at the repo root) reads `init.lua` at startup, which loads `data/`,
`modules/`, and `mods/` from the working directory — always run it from the repo root.

- `otclient.exe --test` — enables testing mode (also runs `test.lua` after `init.lua`); Lua test scripts live in
  `tests/*.lua`.
- `otclient.exe --mobile` — forces the mobile UI layout instead of the `DEFAULT_LAYOUT` set in `init.lua`.
- `otclient.exe --encrypt [path]` — encrypts data files (build tooling, not normal runtime use).

Runtime config lives in `init.lua` at the repo root: `APP_NAME`/`APP_VERSION` (client version reported to
login/updater), `DEFAULT_LAYOUT`, and `Servers`/`Services` tables (login endpoints, updater/crash/feedback URLs).
User-specific overrides go in `config.otml` (gitignored).

## Notes specific to this fork

- Encryption/build tooling and vcpkg paths assume Windows + MSVC (vc16) as the primary dev environment.
- This checkout ("project-danubia") is a custom server client build (custom outfits, custom minimap, etc.), not
  vanilla OTClientV8 — don't assume upstream OTClientV8 behavior without checking.