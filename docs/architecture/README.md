# Architecture Overview

`zbar` is currently split into a few explicit runtime layers:

## Config

- `src/config/meta.zig`: source-of-truth schema metadata
- `src/config/schema.zig`: validation and parsing
- `src/config/lua_config.zig`: Lua-backed load path

The intended direction is that docs, snippets, Lua metadata, and linting all
derive from the same Zig-side schema tables.

## Providers

- `src/modules/types.zig`: provider payloads, fields, and segment types
- `src/modules/registry.zig`: scheduling, caching, runtime stats
- `src/modules/builtins.zig`: built-in providers
- `src/modules/formatter.zig`: display policy

Providers should sample data and expose structure. Formatting and rendering
policy belongs above them.

## WM

- `src/wm/hyprland.zig`: Hyprland snapshot/wait backend
- `src/wm/stub.zig`: fallback backend
- `src/wm/types.zig`: shared compositor snapshot contract

## UI

- `src/ui/surface.zig`: backend-neutral surface policy
- `src/ui/style.zig`: palette and appearance policy
- `src/ui/text.zig`: text measurement contract
- `src/ui/layout.zig`: retained layout
- `src/ui/presenter.zig`: frame-to-scene assembly
- `src/ui/paint.zig`: backend-neutral draw commands
- `src/ui/shell_gui.zig`: SDL preview backend

This is intentionally set up so SDL is a temporary executor, not the owner of
the UI architecture.
