<h1><img src="assets/icon/zbar-icon.png" alt="Z" width="44" align="absmiddle" />bar</h1>

A native Zig status bar project aimed at replacing Waybar with a lower-footprint,
more explicit architecture: schema-driven Lua config, pluggable providers, and a
backend-neutral UI stack that can grow into a real Wayland layer-shell bar.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Shared Lua](https://img.shields.io/badge/shared--lua-zlua--portable-2f855a)](https://github.com/LaurenceGuws/zlua-portable)
[![Sibling App](https://img.shields.io/badge/sibling%20app-zide-1f6feb)](https://github.com/LaurenceGuws/Zide)
[![Zig](https://img.shields.io/badge/zig-0.15.2-f7a41d)](https://ziglang.org/download/)
[![Status](https://img.shields.io/badge/status-pre--alpha-b44cff)](#current-status)

## Links

- [Docs Index](docs/INDEX.md)
- [Roadmap](docs/todo/README.md)
- [Architecture Notes](app_architecture/README.md)

## Related Projects

- [zlua-portable](https://github.com/LaurenceGuws/zlua-portable) provides the
  shared low-level Lua state and reader helpers used by `zbar`.
- [Zide](https://github.com/LaurenceGuws/Zide) is the sibling Zig IDE/terminal
  project that shares the same `zlua-portable` package boundary.

## What zbar Is

`zbar` is being built as a serious bar/runtime rather than a theme pack around a
large pile of glue code. The current direction is:

- Zig-first implementation
- low-footprint runtime and explicit update scheduling
- schema-backed rich Lua config
- plug-and-play provider instances with per-instance customization
- backend-neutral UI layers that can later target real layer-shell surfaces

This project is intentionally still separate from `zide` and `wayspot`. The
integration seams exist, but the coupling remains loose for now.

## Current Status

`zbar` is in active pre-alpha. The current checkpoint is stronger
architecturally than visually.

Implemented today:

- Lua config loader with generated LuaLS metadata and snippets
- schema-backed config linting and strict lint mode
- provider registry with built-in `workspaces`, `mode`, `window`, `cpu`,
  `memory`, and `clock`
- real host sampling for CPU, memory, and clock
- Hyprland snapshot backend with fallback stub backend
- adaptive runtime scheduler with cache stats and debug output
- SDL preview window with shared surface, style, layout, presenter, and paint
  layers

Not implemented yet:

- real Wayland layer-shell surface
- external provider loading ABI/plugin system
- richer text/icon rendering
- live config reload and production packaging

## Quick Start

Prerequisites depend on your distro, but for the current Linux/SDL preview path
you need Zig plus SDL3/SDL3_ttf and Lua 5.4 development libraries available to
the build.

Common workflow:

```bash
zig build test
zig build meta
zig build run -- --lint-config --config config.lua
ZBAR_CONFIG_LUA=config.lua zig build run
```

`zbar` now consumes `zlua-portable` as a pinned Zig package dependency from the
`v0.1.0-beta.1` release line.

For local co-development only, you can temporarily replace that pinned package
with a sibling path dependency to a local `zlua-portable` checkout:

```zig
.zlua_portable = .{
    .path = "../zlua-portable",
},
```

Useful runtime variants:

```bash
ZBAR_CONFIG_LUA=config.lua zig build run -- --once
ZBAR_CONFIG_LUA=config.lua zig build run -- --frames 120 --debug-runtime
zig build run -- --print-provider-health
zig build run -- --print-runtime-stats
```

## Lua Authoring

The repo ships a completion-friendly local config and generated Lua metadata:

- [config.lua](config.lua)
- [lua/zbar-meta.lua](lua/zbar-meta.lua)
- [snippets/lua.json](snippets/lua.json)
- [.luarc.json](.luarc.json)

Current authoring workflow:

- edit `config.lua` in Neovim/LuaLS
- use the generated snippets and metadata for completion
- validate with `--lint-config`

## Repository Layout

- `src/config`: Lua loading, schema, metadata, defaults, linting
- `src/modules`: provider contracts, formatter, registry, built-ins
- `src/wm`: compositor backends and snapshot types
- `src/ui`: surface, style, text, layout, presenter, paint, shells
- `tools`: metadata generation tools
- `docs`: architecture notes, roadmap, and repository navigation

## Developer Notes

The current public contract to take seriously is the architecture split:

- config/schema is metadata-driven
- providers sample data and expose typed fields/payloads
- formatter owns display policy
- renderer tracks layout/display/semantic signatures
- UI preview consumes shared surface/layout/presentation layers

If you are changing one layer, keep the seam clean enough that the future
Wayland backend does not have to undo SDL-specific decisions.

## License

MIT
