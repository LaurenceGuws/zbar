const std = @import("std");
const bar = @import("../bar/mod.zig");
const config = @import("../config/mod.zig");
const modules = @import("../modules/mod.zig");
const render = @import("../render/mod.zig");
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
        var frame_index: u32 = 0;
        var previous_snapshot: ?wm.Snapshot = null;
        var previous_signature: ?render.Renderer.Signature = null;
        var redraw_count: usize = 0;
        var suppressed_count: usize = 0;
        while (true) : (frame_index += 1) {
            const snapshot = self.backend.snapshot();
            const snapshot_changed = if (previous_snapshot) |prior| !wm.Snapshot.eql(prior, snapshot) else true;
            const frame = self.registry.collect(std.heap.page_allocator, self.cfg.bar, .{
                .snapshot = snapshot,
                .snapshot_changed = snapshot_changed,
                .provider_defaults = self.cfg.provider_defaults,
            }) catch |err| {
                var buffer: [2048]u8 = undefined;
                var writer = std.fs.File.stdout().writer(&buffer);
                const out = &writer.interface;
                try out.print("zbar module collection failed err={s}\n", .{@errorName(err)});
                try out.flush();
                return err;
            };
            defer frame.deinit(std.heap.page_allocator);
            previous_snapshot = snapshot;

            const signature = self.renderer.signature(self.runtime_bar, snapshot, frame);
            const prior_signature = previous_signature;
            const changed = prior_signature == null or prior_signature.?.full() != signature.full();
            if (changed) {
                redraw_count += 1;
                const output = try self.renderFrameText(snapshot, frame);
                defer std.heap.page_allocator.free(output);
                var buffer: [2048]u8 = undefined;
                var writer = std.fs.File.stdout().writer(&buffer);
                const out = &writer.interface;
                if (frame_index != 0) try out.print("\r\x1b[2K", .{});
                try out.print("{s}", .{output});
                try out.flush();
                previous_signature = signature;
            } else {
                suppressed_count += 1;
            }

            if (self.options.debug_runtime) try self.printRuntimeDebug(frame_index, redraw_count, suppressed_count, changed, signature, prior_signature);

            if (self.options.once) break;
            if (self.options.max_frames) |limit| {
                if (frame_index + 1 >= limit) break;
            }
            self.backend.waitForChange(self.sleepMs());
        }
    }

    fn renderFrameText(self: Shell, snapshot: wm.Snapshot, frame: modules.Frame) ![]u8 {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(std.heap.page_allocator);
        const writer = out.writer(std.heap.page_allocator);
        try self.renderer.render(writer.any(), self.runtime_bar, snapshot, frame);
        return out.toOwnedSlice(std.heap.page_allocator);
    }

    fn sleepMs(self: Shell) u64 {
        if (self.options.tick_ms_override) |tick_ms| return tick_ms;
        return self.registry.nextWakeDelayMs(self.cfg.bar.effectiveTickMs());
    }

    fn printRuntimeDebug(
        self: Shell,
        frame_index: u32,
        redraw_count: usize,
        suppressed_count: usize,
        changed: bool,
        signature: render.Renderer.Signature,
        previous_signature: ?render.Renderer.Signature,
    ) !void {
        const stats = self.registry.runtimeStats(self.cfg.bar.effectiveTickMs());
        const sleep_ms = if (self.options.tick_ms_override) |tick_ms| tick_ms else stats.next_wake_delay_ms orelse self.cfg.bar.effectiveTickMs();
        const layout_changed = previous_signature == null or previous_signature.?.layout != signature.layout;
        const display_changed = previous_signature == null or previous_signature.?.display_content != signature.display_content;
        const semantic_changed = previous_signature == null or previous_signature.?.semantic_content != signature.semantic_content;

        var buffer: [256]u8 = undefined;
        var writer = std.fs.File.stderr().writer(&buffer);
        const err = &writer.interface;
        try err.print(
            "debug frame={d} redraw={s} layout_changed={s} display_changed={s} semantic_changed={s} redraw_count={d} suppressed={d} cache={d} hits={d} misses={d} timed_hits={d} timed_misses={d} snapshot_hits={d} snapshot_misses={d} timed={d} snapshot={d} sleep_ms={d}\n",
            .{
                frame_index + 1,
                if (changed) "yes" else "no",
                if (layout_changed) "yes" else "no",
                if (display_changed) "yes" else "no",
                if (semantic_changed) "yes" else "no",
                redraw_count,
                suppressed_count,
                stats.cache_entries,
                stats.cache_hits,
                stats.cache_misses,
                stats.timed_cache_hits,
                stats.timed_cache_misses,
                stats.snapshot_cache_hits,
                stats.snapshot_cache_misses,
                stats.timed_entries,
                stats.snapshot_entries,
                sleep_ms,
            },
        );
        try err.flush();
    }
};
