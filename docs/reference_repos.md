# Reference Repos

`zbar` keeps a small local set of reference repositories for architectural and
implementation comparison. This is not vendor code and it is intentionally not
tracked in git.

## Setup

```bash
./scripts/setup_reference_repos.sh
```

This populates:

- `reference_repos/bars`
- `reference_repos/backends`
- `reference_repos/wm`

## Current Seed Set

Bars:

- `waybar`
- `yambar`
- `ironbar`
- `eww`

Backends:

- `sdl`
- `wayland`
- `wayland_protocols`

Window managers / compositor references:

- `hyprland`
- `sway`

## Why These

- `waybar`: direct product reference
- `yambar`: low-footprint native bar reference
- `ironbar`: modern configurable bar reference
- `eww`: configuration and widget system reference
- `sdl`: preview backend reference
- `wayland` / `wayland_protocols`: real protocol and client semantics
- `hyprland` / `sway`: compositor and IPC reference points

## Current Policy

Keep the set small and purposeful. Add a repo only when it answers a concrete
question about:

- provider architecture
- layer-shell or Wayland client behavior
- compositor integration
- scheduling, rendering, or low-footprint bar design

## Citation Policy

For difficult issues, reference repos are not just for browsing. They should be
cited in `docs/research/` or `docs/review/`.

The intent is not blind copying. The intent is to bias `zbar` toward proven
solutions by studying strong existing implementations, then choosing what to
adopt, adapt, or reject.

Minimum citation shape:

- repo name
- relevant path(s)
- short note on what was learned
- short note on what `zbar` chose to do differently, if anything

Example:

```md
- `waybar`
  - `src/modules/*`
  - used to compare module lifecycle and output invalidation shape
```
