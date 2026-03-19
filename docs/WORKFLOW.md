# Workflow

`docs/` is for developer/operator workflow, queues, research, and review.

## Meaning of the Main Trees

- `docs/todo/`: active queues and backlog
- `docs/research/`: comparative notes and evidence gathering
- `docs/review/`: audits, findings, and checkpoint reviews
- `app_architecture/`: design authority and subsystem intent

## Working Rule

If a document answers "what should this system be?" or "what architecture are we
committing to?", it belongs in `app_architecture/`.

If it answers "what did we learn?", "what is left?", or "what did we find in
review?", it belongs in `docs/`.

## Reference Rule

For difficult issues, especially around:

- Wayland / layer-shell behavior
- compositor lifecycle and IPC
- rendering, text, or buffer semantics
- scheduler and low-footprint runtime behavior
- provider or extension architecture

do not rely on memory alone.

Start from strong working reference implementations to bias design toward
proven shapes. Then inspect, compare, and adapt. Do not copy them blindly.

The goal is:

- seed bias from best-in-class working systems
- extract principles and constraints from them
- adapt those ideas to `zbar`'s architecture
- record what was learned and what was intentionally different

Check the local reference repos and record what was used. The outcome should
be captured in either:

- `docs/research/` for investigation notes
- `docs/review/` for findings against the current implementation

At minimum, cite:

- which reference repo(s) were inspected
- which file(s) or subsystem(s) were relevant
- what concrete behavior or design choice was learned from them
- what `zbar` chose to do with that evidence
