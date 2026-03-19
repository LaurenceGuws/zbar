# zbar Architecture

`app_architecture/` is design authority for `zbar`.

Use this tree for:

- design intent
- subsystem boundaries
- plans and checkpoints
- status communication
- release/design notes that describe what the code should become

Do not use this tree as a dumping ground for generic workflow notes or review
logs. Those belong under `docs/`.

## Current Core Layers

- config/schema: metadata-driven Lua config, linting, snippets, LuaLS metadata
- providers: typed payloads/fields, scheduler, cache, formatter boundary
- wm: snapshot and wake contracts, Hyprland backend, stub fallback
- ui: surface, style, text, layout, presenter, paint, shell backends

## Current Design Priorities

- keep the shared UI stack as design authority now that layer-shell exists
- make input and action dispatch as explicit as rendering and layout
- preserve the backend-neutral UI stack
- keep `zbar` loosely coupled to `zide` and `wayspot`
- harden provider extension seams before deep external integration

## Status Docs

- [System Status](SYSTEM_STATUS.md)
- [UI Pipeline](ui/PIPELINE.md)
