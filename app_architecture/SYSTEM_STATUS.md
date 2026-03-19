# System Status

Last updated: 2026-03-19

`zbar` is no longer just a bootstrap. The codebase is already a real bar
runtime with a meaningful architecture, but the project is still in the
"design hardening" phase rather than "stable daily driver" phase.

## Current Implemented State

- Config:
  - Lua config loading works
  - schema metadata drives linting, snippets, and LuaLS metadata
  - bar visuals and theme are on the same metadata-backed path as providers
- Providers:
  - built-in `workspaces`, `mode`, `window`, `cpu`, `memory`, `clock`
  - typed payloads and typed fields
  - scheduler and cache with timed and snapshot-driven invalidation
- WM:
  - stub backend
  - Hyprland snapshot backend
  - Hyprland event socket wake path
- UI:
  - shared `surface/style/text/layout/presenter/paint` stack
  - SDL preview backend
  - real Wayland `layer-shell` backend with shm + Cairo rendering
  - rounded outer bar scene and shared segment decoration
  - shared scene hit targets and first semantic action resolution

## Current Risks

- Input is not yet a first-class cross-backend subsystem
- layer-shell rendering works, but robustness and polish are still early
- action dispatch is only partially real; workspace activation exists, broader
  action execution does not
- text shaping and iconography are still simple
- docs were lagging the code until this checkpoint

## Current Design Position

- The shared UI stack is design authority
- shell backends should execute shared policy, not invent it
- config/spec should stay metadata-driven
- sibling integration with `zide` and `wayspot` stays loose until contracts are
  stable

## Definition Of "Good Next State"

The next meaningful checkpoint is:

- layer-shell backend remains the primary real backend
- pointer input lands on top of shared scene hit targets
- workspace/window/system actions route through explicit dispatch layers
- docs track architecture and work queues closely enough that code and intent do
  not drift apart again
