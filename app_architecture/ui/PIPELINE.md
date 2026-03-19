# UI Pipeline

This file is the concrete pipeline view for the current UI architecture.

## Runtime Flow

```mermaid
flowchart LR
  A[Config + Theme] --> B[Runtime Bar]
  C[WM Snapshot] --> D[Registry Collect]
  E[Provider Defaults] --> D
  D --> F[Frame Segments]
  F --> G[Text Measure]
  B --> H[Style + Palette]
  G --> I[Layout Frame]
  H --> I
  I --> J[Presenter]
  J --> K[Paint Scene]
  K --> L[Hit Targets]
  K --> M[Draw Commands]
  M --> N[SDL Preview]
  M --> O[Wayland Layer Shell]
```

## Interaction Flow

```mermaid
flowchart LR
  A[Pointer Event] --> B[Backend Hit Test]
  B --> C[Hit Target]
  C --> D[UI Action Resolve]
  D --> E[App Action Dispatch]
  E --> F[WM / Integration Backend]
```

## Current Reality

- `surface.zig` resolves placement and surface intent
- `style.zig` resolves appearance and palette policy
- `text.zig` handles measurement inputs
- `layout.zig` owns retained geometry
- `presenter.zig` assembles scene state
- `paint.zig` owns backend-neutral draw commands and hit targets
- `shell_gui.zig` and `shell_layer.zig` execute the shared scene

## Current Gap

The interaction path is only partially complete:

- hit targets exist
- semantic action resolution exists
- workspace activation dispatch exists
- full pointer/input handling and broader action execution do not yet exist
