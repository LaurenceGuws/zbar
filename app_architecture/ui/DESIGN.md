# UI Design

The current UI direction is not "build the final backend in SDL". The SDL path
is a preview executor while the real design authority lives in shared UI layers.

## Intended Stack

- `surface.zig`: backend-neutral surface policy
- `style.zig`: palette and appearance policy
- `text.zig`: text measurement contract
- `layout.zig`: retained geometry
- `presenter.zig`: frame-to-scene assembly
- `paint.zig`: backend-neutral draw commands
- backend shell: command execution and platform wiring

## Current State

- SDL preview consumes shared surface/style/layout/presenter/paint layers
- Wayland layer-shell backend also consumes the shared scene model
- redraw suppression and runtime signatures already exist
- theme values are config-driven
- scene hit targets and semantic action resolution now exist

## Next Step

Complete the interaction path on top of the shared scene model:

- backend pointer events
- shared hit testing
- semantic action dispatch
- backend-neutral execution routing
