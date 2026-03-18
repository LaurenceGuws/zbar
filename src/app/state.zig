const std = @import("std");
const bar = @import("../bar/mod.zig");
const config = @import("../config/mod.zig");
const modules = @import("../modules/mod.zig");
const render = @import("../render/mod.zig");
const ui = @import("../ui/mod.zig");
const wm = @import("../wm/mod.zig");
const Logger = @import("logger.zig").Logger;

pub const Mode = enum {
    bar,
    daemon,
};

pub const RunOptions = struct {
    once: bool = false,
    max_frames: ?u32 = null,
    tick_ms_override: ?u64 = null,
    debug_runtime: bool = false,

    pub fn tickMs(self: RunOptions) u64 {
        return self.tick_ms_override orelse 1000;
    }
};

pub const App = struct {
    mode: Mode,
    logger: Logger,

    pub fn deinit(_: *App) void {}

    pub fn run(self: *App, options: RunOptions) !void {
        self.logger.info("zbar starting mode={s}", .{@tagName(self.mode)});

        const loader = config.Loader.init(std.heap.page_allocator);
        var runtime_cfg = try loader.load();
        defer runtime_cfg.deinit(std.heap.page_allocator);
        const runtime_bar = bar.Bar.init(runtime_cfg.bar);
        const backend = wm.defaultBackend();
        var registry = modules.Registry.default();
        defer registry.deinit(std.heap.page_allocator);
        const renderer = render.Renderer.init();
        var shell = ui.Shell.init(runtime_cfg, runtime_bar, backend, &registry, renderer, options);

        try shell.run();
    }
};
