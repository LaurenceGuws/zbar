const std = @import("std");
const bar = @import("../bar/mod.zig");
const config = @import("../config/mod.zig");
const modules = @import("../modules/mod.zig");
const render = @import("../render/mod.zig");
const ui_runtime = @import("runtime.zig");
const wm = @import("../wm/mod.zig");
const RunOptions = @import("../app/state.zig").RunOptions;

pub const Shell = struct {
    cfg: config.Config,
    runtime_bar: bar.Bar,
    backend: wm.Backend,
    registry: *modules.Registry,
    renderer: render.Renderer,
    options: RunOptions,

    pub fn init(
        cfg: config.Config,
        runtime_bar: bar.Bar,
        backend: wm.Backend,
        registry: *modules.Registry,
        renderer: render.Renderer,
        options: RunOptions,
    ) Shell {
        return .{
            .cfg = cfg,
            .runtime_bar = runtime_bar,
            .backend = backend,
            .registry = registry,
            .renderer = renderer,
            .options = options,
        };
    }

    pub fn run(self: *Shell) !void {
        const state = self.runtimeState();
        try ui_runtime.runShell(&state, self.hooks());
    }

    fn renderFrameText(self: Shell, snapshot: wm.Snapshot, frame: modules.Frame) ![]u8 {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(std.heap.page_allocator);
        const writer = out.writer(std.heap.page_allocator);
        try self.renderer.render(writer.any(), self.runtime_bar, snapshot, frame);
        return out.toOwnedSlice(std.heap.page_allocator);
    }

    fn runtimeState(self: *Shell) ui_runtime.ShellState {
        return .{
            .cfg = self.cfg,
            .runtime_bar = self.runtime_bar,
            .backend = self.backend,
            .registry = self.registry,
            .renderer = self.renderer,
            .options = self.options,
        };
    }

    fn hooks(self: *Shell) ui_runtime.Hooks {
        return .{
            .context = @ptrCast(self),
            .vtable = &.{
                .isQuitRequested = isQuitRequested,
                .beforeFrame = beforeFrame,
                .drawFrame = drawFrame,
            },
        };
    }

    fn isQuitRequested(_: *anyopaque) bool {
        return false;
    }

    fn beforeFrame(_: *anyopaque) void {}

    fn drawFrame(context: *anyopaque, runtime_bar: bar.Bar, frame: modules.Frame) !void {
        const self: *Shell = @ptrCast(@alignCast(context));
        const snapshot = self.backend.snapshot();
        const output = try self.renderFrameText(snapshot, frame);
        defer std.heap.page_allocator.free(output);
        var buffer: [2048]u8 = undefined;
        var writer = std.fs.File.stdout().writer(&buffer);
        const out = &writer.interface;
        try out.print("\r\x1b[2K{s}", .{output});
        try out.flush();
        _ = runtime_bar;
    }
};
