const std = @import("std");
const bar = @import("../bar/mod.zig");
const config = @import("../config/mod.zig");
const modules = @import("../modules/mod.zig");
const render = @import("../render/mod.zig");
const ui_paint = @import("paint.zig");
const wm = @import("../wm/mod.zig");
const RunOptions = @import("../app/state.zig").RunOptions;

pub const ShellState = struct {
    cfg: config.Config,
    runtime_bar: bar.Bar,
    backend: wm.Backend,
    registry: *modules.Registry,
    renderer: render.Renderer,
    options: RunOptions,
};

pub const FrameContext = struct {
    index: u32,
    snapshot: wm.Snapshot,
    previous_snapshot: ?wm.Snapshot,
    snapshot_changed: bool,
    frame: modules.Frame,
    signature: render.Renderer.Signature,
    previous_signature: ?render.Renderer.Signature,
    signature_changed: bool,
    forced_redraw_reason: ?[]const u8 = null,
};

pub const LoopStats = struct {
    redraw_count: usize = 0,
    suppressed_count: usize = 0,
    previous_snapshot: ?wm.Snapshot = null,
    previous_signature: ?render.Renderer.Signature = null,
};

pub const Hooks = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        isQuitRequested: *const fn (context: *anyopaque) bool,
        beforeFrame: *const fn (context: *anyopaque) void,
        drawFrame: *const fn (context: *anyopaque, runtime_bar: bar.Bar, frame: modules.Frame) anyerror!void,
        forceRedraw: ?*const fn (context: *anyopaque) bool = null,
        redrawReason: ?*const fn (context: *anyopaque) ?[]const u8 = null,
        sceneStats: ?*const fn (context: *anyopaque) ?ui_paint.Stats = null,
        wait: ?*const fn (context: *anyopaque, timeout_ms: u64) void = null,
    };

    pub fn isQuitRequested(self: Hooks) bool {
        return self.vtable.isQuitRequested(self.context);
    }

    pub fn beforeFrame(self: Hooks) void {
        self.vtable.beforeFrame(self.context);
    }

    pub fn drawFrame(self: Hooks, runtime_bar: bar.Bar, frame: modules.Frame) !void {
        return self.vtable.drawFrame(self.context, runtime_bar, frame);
    }

    pub fn forceRedraw(self: Hooks) bool {
        if (self.vtable.forceRedraw) |force_redraw_fn| {
            return force_redraw_fn(self.context);
        }
        return false;
    }

    pub fn redrawReason(self: Hooks) ?[]const u8 {
        if (self.vtable.redrawReason) |reason_fn| {
            return reason_fn(self.context);
        }
        return null;
    }

    pub fn sceneStats(self: Hooks) ?ui_paint.Stats {
        if (self.vtable.sceneStats) |stats_fn| {
            return stats_fn(self.context);
        }
        return null;
    }

    pub fn wait(self: Hooks, timeout_ms: u64) bool {
        if (self.vtable.wait) |wait_fn| {
            wait_fn(self.context, timeout_ms);
            return true;
        }
        return false;
    }
};

pub fn runShell(state: *const ShellState, hooks: Hooks) !void {
    var stats = LoopStats{};
    var frame_index: u32 = 0;

    while (!hooks.isQuitRequested()) : (frame_index += 1) {
        hooks.beforeFrame();

        var frame_context = try collectFrame(state, frame_index, &stats);
        defer frame_context.frame.deinit(std.heap.page_allocator);

        const forced_redraw = hooks.forceRedraw();
        if (forced_redraw) {
            frame_context.forced_redraw_reason = hooks.redrawReason();
        }

        const should_redraw = frame_context.signature_changed or forced_redraw;
        if (should_redraw) {
            stats.redraw_count += 1;
            try hooks.drawFrame(state.runtime_bar, frame_context.frame);
        } else {
            stats.suppressed_count += 1;
        }

        if (state.options.debug_runtime) {
            try printRuntimeDebug(state, frame_context, stats, should_redraw, hooks.sceneStats());
        }

        if (state.options.once) break;
        if (state.options.max_frames) |limit| {
            if (frame_index + 1 >= limit) break;
        }

        const timeout_ms = sleepMs(state);
        if (!hooks.wait(timeout_ms)) {
            state.backend.waitForChange(timeout_ms);
        }
    }
}

pub fn collectFrame(state: *const ShellState, frame_index: u32, stats: *LoopStats) !FrameContext {
    const snapshot = state.backend.snapshot();
    const previous_snapshot = stats.previous_snapshot;
    const snapshot_changed = if (previous_snapshot) |prior| !wm.Snapshot.eql(prior, snapshot) else true;
    const frame = try state.registry.collect(std.heap.page_allocator, state.cfg.bar, .{
        .snapshot = snapshot,
        .snapshot_changed = snapshot_changed,
        .provider_defaults = state.cfg.provider_defaults,
    });
    errdefer frame.deinit(std.heap.page_allocator);
    stats.previous_snapshot = snapshot;

    const signature = state.renderer.signature(state.runtime_bar, snapshot, frame);
    const previous_signature = stats.previous_signature;
    const signature_changed = previous_signature == null or previous_signature.?.full() != signature.full();
    if (signature_changed) stats.previous_signature = signature;

    return .{
        .index = frame_index,
        .snapshot = snapshot,
        .previous_snapshot = previous_snapshot,
        .snapshot_changed = snapshot_changed,
        .frame = frame,
        .signature = signature,
        .previous_signature = previous_signature,
        .signature_changed = signature_changed,
    };
}

pub fn sleepMs(state: *const ShellState) u64 {
    if (state.options.tick_ms_override) |tick_ms| return tick_ms;
    return state.registry.nextWakeDelayMs(state.cfg.bar.effectiveTickMs());
}

pub fn printRuntimeDebug(
    state: *const ShellState,
    frame_context: FrameContext,
    stats: LoopStats,
    did_redraw: bool,
    scene_stats: ?ui_paint.Stats,
) !void {
    const runtime_stats = state.registry.runtimeStats(state.cfg.bar.effectiveTickMs());
    const sleep_ms = if (state.options.tick_ms_override) |tick_ms| tick_ms else runtime_stats.next_wake_delay_ms orelse state.cfg.bar.effectiveTickMs();
    const layout_changed = frame_context.previous_signature == null or frame_context.previous_signature.?.layout != frame_context.signature.layout;
    const display_changed = frame_context.previous_signature == null or frame_context.previous_signature.?.display_content != frame_context.signature.display_content;
    const semantic_changed = frame_context.previous_signature == null or frame_context.previous_signature.?.semantic_content != frame_context.signature.semantic_content;
    const snapshot_reason = snapshotReason(frame_context);

    var buffer: [256]u8 = undefined;
    var writer = std.fs.File.stderr().writer(&buffer);
    const err = &writer.interface;
    try err.print(
        "debug frame={d} redraw={s} redraw_reason={s} snapshot_changed={s} snapshot_reason={s} layout_changed={s} display_changed={s} semantic_changed={s} redraw_count={d} suppressed={d} cache={d} hits={d} misses={d} timed_hits={d} timed_misses={d} snapshot_hits={d} snapshot_misses={d} timed={d} snapshot={d} scene_cmds={d} fills={d} strokes={d} clips={d}/{d} text={d} sleep_ms={d}\n",
        .{
            frame_context.index + 1,
            if (did_redraw) "yes" else "no",
            frame_context.forced_redraw_reason orelse "-",
            if (frame_context.snapshot_changed) "yes" else "no",
            snapshot_reason,
            if (layout_changed) "yes" else "no",
            if (display_changed) "yes" else "no",
            if (semantic_changed) "yes" else "no",
            stats.redraw_count,
            stats.suppressed_count,
            runtime_stats.cache_entries,
            runtime_stats.cache_hits,
            runtime_stats.cache_misses,
            runtime_stats.timed_cache_hits,
            runtime_stats.timed_cache_misses,
            runtime_stats.snapshot_cache_hits,
            runtime_stats.snapshot_cache_misses,
            runtime_stats.timed_entries,
            runtime_stats.snapshot_entries,
            if (scene_stats) |s| s.total_commands else 0,
            if (scene_stats) |s| s.fill_rects else 0,
            if (scene_stats) |s| s.stroke_rects else 0,
            if (scene_stats) |s| s.push_clips else 0,
            if (scene_stats) |s| s.pop_clips else 0,
            if (scene_stats) |s| s.text_draws else 0,
            sleep_ms,
        },
    );
    try err.flush();
}

fn snapshotReason(frame_context: FrameContext) []const u8 {
    const previous = frame_context.previous_snapshot orelse return "initial";
    if (!frame_context.snapshot_changed) return "-";
    if (previous.outputs != frame_context.snapshot.outputs) return "outputs";
    if (previous.workspaces != frame_context.snapshot.workspaces) return "workspaces";
    if (previous.focused_workspace != frame_context.snapshot.focused_workspace) return "focused_workspace";
    if (!std.mem.eql(u8, previous.focused_title, frame_context.snapshot.focused_title)) return "focused_title";
    if (!std.mem.eql(u8, previous.compositor, frame_context.snapshot.compositor)) return "compositor";
    return "unknown";
}

test "sleepMs prefers explicit override" {
    var cfg = config.defaultConfig();
    defer cfg.deinit(std.heap.page_allocator);
    var registry = try modules.Registry.init(std.testing.allocator);
    defer registry.deinit(std.testing.allocator);
    const state = ShellState{
        .cfg = cfg,
        .runtime_bar = bar.Bar.init(cfg.bar),
        .backend = wm.stubBackend(),
        .registry = &registry,
        .renderer = render.Renderer.init(),
        .options = .{ .tick_ms_override = 25 },
    };
    try std.testing.expectEqual(@as(u64, 25), sleepMs(&state));
}
