Contributions are welcome, but the current project priority is architecture
clarity over broad surface area.

If you send changes:

- keep config/schema/UI seams explicit
- avoid introducing tight coupling to sibling projects
- run `zig build test`
- regenerate Lua metadata with `zig build meta` if schema or docs change
