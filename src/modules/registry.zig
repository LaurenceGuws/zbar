const std = @import("std");
const builtins = @import("builtins.zig");
const config = @import("../config/mod.zig");
const types = @import("types.zig");
const wm = @import("../wm/mod.zig");

pub const ProviderStatus = struct {
    name: []const u8,
    health: types.ProviderHealth,
};

pub const ProviderRenderFailure = struct {
    provider_name: []const u8,
    err: anyerror,
};

pub const CollectReport = struct {
    had_runtime_failure: bool = false,
    runtime_failure_count: usize = 0,
    first_runtime_failure: ?ProviderRenderFailure = null,
};

pub const RuntimeStats = struct {
    cache_entries: usize = 0,
    cache_hits: usize = 0,
    cache_misses: usize = 0,
    timed_cache_hits: usize = 0,
    timed_cache_misses: usize = 0,
    snapshot_cache_hits: usize = 0,
    snapshot_cache_misses: usize = 0,
    timed_entries: usize = 0,
    snapshot_entries: usize = 0,
    next_wake_delay_ms: ?u64 = null,
};

pub const Registry = struct {
    providers: []const types.Provider,
    cache: std.ArrayList(CacheEntry) = .empty,
    cache_hits: usize = 0,
    cache_misses: usize = 0,
    timed_cache_hits: usize = 0,
    timed_cache_misses: usize = 0,
    snapshot_cache_hits: usize = 0,
    snapshot_cache_misses: usize = 0,

    pub fn default() Registry {
        return .{ .providers = builtins.builtinProviders() };
    }

    pub fn deinit(self: *Registry, allocator: std.mem.Allocator) void {
        for (self.cache.items) |*entry| entry.deinit(allocator);
        self.cache.deinit(allocator);
    }

    pub fn collect(self: *Registry, allocator: std.mem.Allocator, cfg: config.BarConfig, ctx: Context) !types.Frame {
        return self.renderFrame(allocator, cfg, ctx);
    }

    pub fn collectWithReport(self: *Registry, allocator: std.mem.Allocator, cfg: config.BarConfig, ctx: Context, out_frame: ?*types.Frame) !CollectReport {
        var report = CollectReport{};
        const now_ms = currentTimeMs();
        const left = try self.collectSection(allocator, .left, cfg.left, ctx, now_ms, &report);
        errdefer freeSegments(allocator, left);
        const center = try self.collectSection(allocator, .center, cfg.center, ctx, now_ms, &report);
        errdefer freeSegments(allocator, center);
        const right = try self.collectSection(allocator, .right, cfg.right, ctx, now_ms, &report);
        errdefer freeSegments(allocator, right);

        if (out_frame) |frame| {
            frame.* = .{ .left = left, .center = center, .right = right };
        } else {
            freeSegments(allocator, left);
            freeSegments(allocator, center);
            freeSegments(allocator, right);
        }
        return report;
    }

    pub fn renderFrame(self: *Registry, allocator: std.mem.Allocator, cfg: config.BarConfig, ctx: Context) !types.Frame {
        var frame: types.Frame = undefined;
        _ = try self.collectWithReport(allocator, cfg, ctx, &frame);
        return frame;
    }

    pub fn healthSnapshot(self: Registry, allocator: std.mem.Allocator) ![]ProviderStatus {
        var list = std.ArrayList(ProviderStatus).empty;
        defer list.deinit(allocator);
        for (self.providers) |provider| {
            try list.append(allocator, .{
                .name = provider.name,
                .health = provider.health(),
            });
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn renderHealthReport(self: Registry, allocator: std.mem.Allocator) ![]u8 {
        const statuses = try self.healthSnapshot(allocator);
        defer allocator.free(statuses);

        var out = std.ArrayList(u8).empty;
        defer out.deinit(allocator);
        const writer = out.writer(allocator);

        for (statuses) |status| {
            try writer.print("{s}: {s}\n", .{ status.name, healthLabel(status.health) });
        }

        return out.toOwnedSlice(allocator);
    }

    pub fn nextWakeDelayMs(self: Registry, fallback_ms: u64) u64 {
        const now_ms = currentTimeMs();
        var min_delay_ms: ?u64 = null;
        for (self.cache.items) |entry| {
            const refresh_at = entry.next_refresh_ms orelse continue;
            const delay_ms = if (refresh_at <= now_ms) 0 else refresh_at - now_ms;
            if (min_delay_ms == null or delay_ms < min_delay_ms.?) {
                min_delay_ms = delay_ms;
            }
        }
        return min_delay_ms orelse fallback_ms;
    }

    pub fn runtimeStats(self: Registry, fallback_ms: u64) RuntimeStats {
        var timed_entries: usize = 0;
        var snapshot_entries: usize = 0;
        for (self.cache.items) |entry| {
            if (entry.next_refresh_ms != null) timed_entries += 1;
            if (entry.snapshot_key != null) snapshot_entries += 1;
        }
        return .{
            .cache_entries = self.cache.items.len,
            .cache_hits = self.cache_hits,
            .cache_misses = self.cache_misses,
            .timed_cache_hits = self.timed_cache_hits,
            .timed_cache_misses = self.timed_cache_misses,
            .snapshot_cache_hits = self.snapshot_cache_hits,
            .snapshot_cache_misses = self.snapshot_cache_misses,
            .timed_entries = timed_entries,
            .snapshot_entries = snapshot_entries,
            .next_wake_delay_ms = self.nextWakeDelayMs(fallback_ms),
        };
    }

    fn collectSection(
        self: *Registry,
        allocator: std.mem.Allocator,
        section: Section,
        items: []const config.ProviderConfig,
        ctx: Context,
        now_ms: u64,
        report: *CollectReport,
    ) ![]types.Segment {
        var segments = std.ArrayList(types.Segment).empty;
        defer segments.deinit(allocator);

        for (items, 0..) |item, index| {
            const provider = self.find(item.provider) orelse {
                try segments.append(allocator, .{
                    .provider = item.provider,
                    .instance_name = item.name,
                    .text = try std.fmt.allocPrint(allocator, "{s} unavailable", .{item.provider}),
                    .content_id = std.hash.Wyhash.hash(0, item.provider),
                    .payload = .{ .state = "unavailable" },
                });
                continue;
            };

            const classification = cacheClass(item);
            if (classification != .none) {
                if (self.cachedSegment(allocator, section, index, item, ctx.snapshot, now_ms)) |segment| {
                    self.recordCacheHit(classification);
                    try segments.append(allocator, segment);
                    continue;
                }
                self.recordCacheMiss(missClass(classification, ctx.snapshot_changed));
            }

            const output = provider.render(.{
                .allocator = allocator,
                .snapshot = ctx.snapshot,
                .instance = item,
                .defaults = ctx.provider_defaults,
            }) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => {
                    report.had_runtime_failure = true;
                    report.runtime_failure_count += 1;
                    if (report.first_runtime_failure == null) {
                        report.first_runtime_failure = .{ .provider_name = provider.name, .err = err };
                    }
                    try segments.append(allocator, .{
                        .provider = item.provider,
                        .instance_name = item.name,
                        .text = try std.fmt.allocPrint(allocator, "{s} error", .{item.provider}),
                        .content_id = std.hash.Wyhash.hash(0, provider.name),
                        .payload = .{ .state = "error" },
                    });
                    continue;
                },
            };
            defer output.deinit(allocator);

            if (classification != .none) {
                try self.storeCachedOutput(
                    allocator,
                    section,
                    index,
                    item,
                    ctx.snapshot,
                    output.text,
                    output.content_id,
                    output.payload,
                    nextRefreshMs(section, index, item, now_ms),
                );
            }

            try segments.append(allocator, .{
                .provider = item.provider,
                .instance_name = item.name,
                .text = try allocator.dupe(u8, output.text),
                .content_id = output.content_id,
                .payload = output.payload,
            });
        }

        return segments.toOwnedSlice(allocator);
    }

    fn find(self: Registry, name: []const u8) ?types.Provider {
        for (self.providers) |provider| {
            if (std.mem.eql(u8, provider.name, name)) return provider;
        }
        return null;
    }

    fn cachedSegment(
        self: *Registry,
        allocator: std.mem.Allocator,
        section: Section,
        index: usize,
        item: config.ProviderConfig,
        snapshot: wm.Snapshot,
        now_ms: u64,
    ) ?types.Segment {
        const entry = self.findCacheEntry(section, index) orelse return null;
        if (!entry.matches(item)) return null;
        if (entry.next_refresh_ms != null and now_ms >= entry.next_refresh_ms.?) return null;
        if (entry.snapshot_key) |cached_key| {
            const current_key = self.snapshotCacheKey(item.provider, snapshot);
            if (current_key == null or cached_key != current_key.?) return null;
        }
        return .{
            .provider = item.provider,
            .instance_name = item.name,
            .text = allocator.dupe(u8, entry.text) catch return null,
            .content_id = entry.content_id,
            .payload = entry.payload,
        };
    }

    fn storeCachedOutput(
        self: *Registry,
        allocator: std.mem.Allocator,
        section: Section,
        index: usize,
        item: config.ProviderConfig,
        snapshot: wm.Snapshot,
        text: []const u8,
        content_id: u64,
        payload: types.Payload,
        next_refresh_ms: ?u64,
    ) !void {
        if (self.findCacheEntry(section, index)) |entry| {
            try entry.replace(allocator, item, snapshot, self.snapshotCacheKey(item.provider, snapshot), text, content_id, payload, next_refresh_ms);
            return;
        }
        try self.cache.append(allocator, try CacheEntry.init(allocator, section, index, item, snapshot, self.snapshotCacheKey(item.provider, snapshot), text, content_id, payload, next_refresh_ms));
    }

    fn findCacheEntry(self: *Registry, section: Section, index: usize) ?*CacheEntry {
        for (self.cache.items) |*entry| {
            if (entry.section == section and entry.index == index) return entry;
        }
        return null;
    }

    fn shouldUseCache(self: Registry, item: config.ProviderConfig) bool {
        _ = self;
        return item.interval_ms > 0 or isSnapshotDrivenProvider(item.provider);
    }

    fn recordCacheHit(self: *Registry, classification: CacheClass) void {
        self.cache_hits += 1;
        switch (classification) {
            .timed => self.timed_cache_hits += 1,
            .snapshot => self.snapshot_cache_hits += 1,
            .timed_and_snapshot => {
                self.timed_cache_hits += 1;
                self.snapshot_cache_hits += 1;
            },
            .none => {},
        }
    }

    fn recordCacheMiss(self: *Registry, classification: CacheClass) void {
        self.cache_misses += 1;
        switch (classification) {
            .timed => self.timed_cache_misses += 1,
            .snapshot => self.snapshot_cache_misses += 1,
            .timed_and_snapshot => {
                self.timed_cache_misses += 1;
                self.snapshot_cache_misses += 1;
            },
            .none => {},
        }
    }

    fn snapshotCacheKey(self: Registry, provider_name: []const u8, snapshot: wm.Snapshot) ?u64 {
        _ = self;
        if (std.mem.eql(u8, provider_name, "workspaces")) {
            return (@as(u64, snapshot.focused_workspace) << 32) | @as(u64, snapshot.workspaces);
        }
        if (std.mem.eql(u8, provider_name, "mode")) return std.hash.Wyhash.hash(0, snapshot.compositor);
        if (std.mem.eql(u8, provider_name, "window")) return std.hash.Wyhash.hash(0, snapshot.focused_title);
        return null;
    }
};

pub const Context = struct {
    snapshot: wm.Snapshot,
    snapshot_changed: bool = true,
    provider_defaults: config.ProviderDefaults,
};

const Section = enum {
    left,
    center,
    right,
};

const CacheClass = enum {
    none,
    timed,
    snapshot,
    timed_and_snapshot,
};

const CacheEntry = struct {
    section: Section,
    index: usize,
    provider: []u8,
    name: ?[]u8,
    snapshot_key: ?u64,
    last_snapshot: wm.Snapshot,
    text: []u8,
    content_id: u64,
    payload: types.Payload,
    next_refresh_ms: ?u64,

    fn init(
        allocator: std.mem.Allocator,
        section: Section,
        index: usize,
        item: config.ProviderConfig,
        snapshot: wm.Snapshot,
        snapshot_key: ?u64,
        text: []const u8,
        content_id: u64,
        payload: types.Payload,
        next_refresh_ms: ?u64,
    ) !CacheEntry {
        return .{
            .section = section,
            .index = index,
            .provider = try allocator.dupe(u8, item.provider),
            .name = if (item.name) |name| try allocator.dupe(u8, name) else null,
            .snapshot_key = snapshot_key,
            .last_snapshot = snapshot,
            .text = try allocator.dupe(u8, text),
            .content_id = content_id,
            .payload = payload,
            .next_refresh_ms = next_refresh_ms,
        };
    }

    fn deinit(self: *CacheEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.provider);
        if (self.name) |name| allocator.free(name);
        allocator.free(self.text);
    }

    fn replace(
        self: *CacheEntry,
        allocator: std.mem.Allocator,
        item: config.ProviderConfig,
        snapshot: wm.Snapshot,
        snapshot_key: ?u64,
        text: []const u8,
        content_id: u64,
        payload: types.Payload,
        next_refresh_ms: ?u64,
    ) !void {
        const provider = try allocator.dupe(u8, item.provider);
        errdefer allocator.free(provider);
        const name = if (item.name) |value| try allocator.dupe(u8, value) else null;
        errdefer if (name) |value| allocator.free(value);
        const cached_text = try allocator.dupe(u8, text);
        errdefer allocator.free(cached_text);

        allocator.free(self.provider);
        if (self.name) |value| allocator.free(value);
        allocator.free(self.text);

        self.provider = provider;
        self.name = name;
        self.snapshot_key = snapshot_key;
        self.last_snapshot = snapshot;
        self.text = cached_text;
        self.content_id = content_id;
        self.payload = payload;
        self.next_refresh_ms = next_refresh_ms;
    }

    fn matches(self: CacheEntry, item: config.ProviderConfig) bool {
        if (!std.mem.eql(u8, self.provider, item.provider)) return false;
        return nullableStringEql(self.name, item.name);
    }
};

fn freeSegments(allocator: std.mem.Allocator, segments: []types.Segment) void {
    for (segments) |segment| allocator.free(segment.text);
    allocator.free(segments);
}

fn healthLabel(health: types.ProviderHealth) []const u8 {
    return switch (health) {
        .ready => "ready",
        .degraded => "degraded",
        .unavailable => "unavailable",
    };
}

fn currentTimeMs() u64 {
    return @intCast(std.time.milliTimestamp());
}

fn nullableStringEql(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return std.mem.eql(u8, a.?, b.?);
}

fn isSnapshotDrivenProvider(provider_name: []const u8) bool {
    return std.mem.eql(u8, provider_name, "workspaces") or
        std.mem.eql(u8, provider_name, "mode") or
        std.mem.eql(u8, provider_name, "window");
}

fn nextRefreshMs(section: Section, index: usize, item: config.ProviderConfig, now_ms: u64) ?u64 {
    if (item.interval_ms == 0) return null;
    const interval_ms: u64 = item.interval_ms;
    const phase_ms = refreshPhaseMs(section, index, item, interval_ms);
    const cycle_base = now_ms - (now_ms % interval_ms);
    var refresh_at = cycle_base + phase_ms;
    if (refresh_at <= now_ms) refresh_at += interval_ms;
    return refresh_at;
}

fn refreshPhaseMs(section: Section, index: usize, item: config.ProviderConfig, interval_ms: u64) u64 {
    if (interval_ms <= 1) return 0;

    var hasher = std.hash.Wyhash.init(0);
    hasher.update(@tagName(section));
    hasher.update(item.provider);
    if (item.name) |name| hasher.update(name);

    var index_bytes: [@sizeOf(usize)]u8 = undefined;
    std.mem.writeInt(usize, &index_bytes, index, .little);
    hasher.update(&index_bytes);

    return hasher.final() % interval_ms;
}

fn cacheClass(item: config.ProviderConfig) CacheClass {
    const timed = item.interval_ms > 0;
    const snapshot = isSnapshotDrivenProvider(item.provider);
    if (timed and snapshot) return .timed_and_snapshot;
    if (timed) return .timed;
    if (snapshot) return .snapshot;
    return .none;
}

fn missClass(classification: CacheClass, snapshot_changed: bool) CacheClass {
    return switch (classification) {
        .snapshot => if (snapshot_changed) .snapshot else .none,
        .timed_and_snapshot => if (snapshot_changed) .timed_and_snapshot else .timed,
        else => classification,
    };
}

test "registry renders provider instances" {
    var cfg = config.defaultConfig();
    defer cfg.deinit(std.heap.page_allocator);
    var registry = Registry.default();
    defer registry.deinit(std.testing.allocator);
    const frame = try registry.renderFrame(std.testing.allocator, cfg.bar, .{
        .snapshot = .{
            .outputs = 1,
            .workspaces = 5,
            .focused_workspace = 2,
            .focused_title = "Terminal",
            .compositor = "stub",
        },
        .provider_defaults = cfg.provider_defaults,
    });
    defer frame.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("ws 2/5", frame.left[0].text);
}

test "registry reuses cached timed provider output before expiry" {
    var registry = Registry{
        .providers = &.{.{
            .name = "counting",
            .context = &counting_provider_state,
            .vtable = &counting_provider_vtable,
        }},
    };
    defer registry.deinit(std.testing.allocator);

    var left = try std.testing.allocator.alloc(config.ProviderConfig, 1);
    left[0] = try config.ProviderConfig.init(std.testing.allocator, "counting");
    left[0].interval_ms = 60_000;

    const bar_cfg = config.BarConfig{
        .height_px = 28,
        .section_gap_px = 12,
        .background = try std.testing.allocator.dupe(u8, "#11161c"),
        .foreground = try std.testing.allocator.dupe(u8, "#d7dee7"),
        .theme = .{
            .segment_background = try std.testing.allocator.dupe(u8, "#2a3139"),
            .accent_background = try std.testing.allocator.dupe(u8, "#275b7a"),
            .subtle_background = try std.testing.allocator.dupe(u8, "#1c232a"),
            .warning_background = try std.testing.allocator.dupe(u8, "#7a4627"),
            .accent_foreground = try std.testing.allocator.dupe(u8, "#eff5fa"),
            .horizontal_padding_px = 18,
            .segment_padding_x_px = 10,
            .segment_padding_y_px = 6,
            .font_points = 15,
        },
        .left = left,
        .center = &.{},
        .right = &.{},
    };
    defer {
        var mutable_bar_cfg = bar_cfg;
        mutable_bar_cfg.deinit(std.testing.allocator);
    }

    counting_provider_state.render_count = 0;

    const frame_a = try registry.renderFrame(std.testing.allocator, bar_cfg, .{
        .snapshot = .{ .outputs = 1, .workspaces = 1, .focused_workspace = 1, .focused_title = "A", .compositor = "stub" },
        .provider_defaults = .{},
    });
    defer frame_a.deinit(std.testing.allocator);
    const frame_b = try registry.renderFrame(std.testing.allocator, bar_cfg, .{
        .snapshot = .{ .outputs = 1, .workspaces = 1, .focused_workspace = 1, .focused_title = "B", .compositor = "stub" },
        .provider_defaults = .{},
    });
    defer frame_b.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), counting_provider_state.render_count);
    try std.testing.expectEqualStrings(frame_a.left[0].text, frame_b.left[0].text);
}

test "registry reuses snapshot-driven provider output until snapshot changes" {
    var registry = Registry.default();
    defer registry.deinit(std.testing.allocator);

    var cfg = config.defaultConfig();
    defer cfg.deinit(std.heap.page_allocator);

    cfg.bar.left[0].interval_ms = 0;

    const frame_a = try registry.renderFrame(std.testing.allocator, cfg.bar, .{
        .snapshot = .{ .outputs = 1, .workspaces = 5, .focused_workspace = 2, .focused_title = "One", .compositor = "hyprland" },
        .provider_defaults = cfg.provider_defaults,
    });
    defer frame_a.deinit(std.testing.allocator);

    const frame_b = try registry.renderFrame(std.testing.allocator, cfg.bar, .{
        .snapshot = .{ .outputs = 1, .workspaces = 5, .focused_workspace = 2, .focused_title = "Two", .compositor = "hyprland" },
        .provider_defaults = cfg.provider_defaults,
    });
    defer frame_b.deinit(std.testing.allocator);

    const frame_c = try registry.renderFrame(std.testing.allocator, cfg.bar, .{
        .snapshot = .{ .outputs = 1, .workspaces = 5, .focused_workspace = 3, .focused_title = "Three", .compositor = "hyprland" },
        .provider_defaults = cfg.provider_defaults,
    });
    defer frame_c.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("ws 2/5", frame_a.left[0].text);
    try std.testing.expectEqualStrings("ws 2/5", frame_b.left[0].text);
    try std.testing.expectEqualStrings("ws 3/5", frame_c.left[0].text);
}

test "nextWakeDelayMs uses earliest timed refresh" {
    var registry = Registry{
        .providers = &.{},
    };
    defer registry.deinit(std.testing.allocator);

    try registry.cache.append(std.testing.allocator, .{
        .section = .left,
        .index = 0,
        .provider = try std.testing.allocator.dupe(u8, "clock"),
        .name = null,
        .snapshot_key = null,
        .last_snapshot = .{ .outputs = 1, .workspaces = 1, .focused_workspace = 1, .focused_title = "", .compositor = "stub" },
        .text = try std.testing.allocator.dupe(u8, "clock"),
        .next_refresh_ms = currentTimeMs() + 250,
    });
    try registry.cache.append(std.testing.allocator, .{
        .section = .right,
        .index = 1,
        .provider = try std.testing.allocator.dupe(u8, "cpu"),
        .name = null,
        .snapshot_key = null,
        .last_snapshot = .{ .outputs = 1, .workspaces = 1, .focused_workspace = 1, .focused_title = "", .compositor = "stub" },
        .text = try std.testing.allocator.dupe(u8, "cpu"),
        .next_refresh_ms = currentTimeMs() + 50,
    });

    try std.testing.expect(registry.nextWakeDelayMs(1000) <= 50);
}

test "refresh phases differ across provider instances" {
    var cpu = try config.ProviderConfig.init(std.testing.allocator, "cpu");
    defer cpu.deinit(std.testing.allocator);
    cpu.interval_ms = 1000;

    var memory = try config.ProviderConfig.init(std.testing.allocator, "memory");
    defer memory.deinit(std.testing.allocator);
    memory.interval_ms = 1000;

    const cpu_phase = refreshPhaseMs(.right, 0, cpu, 1000);
    const memory_phase = refreshPhaseMs(.right, 1, memory, 1000);

    try std.testing.expect(cpu_phase < 1000);
    try std.testing.expect(memory_phase < 1000);
    try std.testing.expect(cpu_phase != memory_phase);
}

test "runtimeStats reports cache counters" {
    var registry = Registry{
        .providers = &.{},
        .cache_hits = 4,
        .cache_misses = 2,
        .timed_cache_hits = 3,
        .timed_cache_misses = 1,
        .snapshot_cache_hits = 1,
        .snapshot_cache_misses = 1,
    };
    defer registry.deinit(std.testing.allocator);

    try registry.cache.append(std.testing.allocator, .{
        .section = .left,
        .index = 0,
        .provider = try std.testing.allocator.dupe(u8, "clock"),
        .name = null,
        .snapshot_key = null,
        .last_snapshot = .{ .outputs = 1, .workspaces = 1, .focused_workspace = 1, .focused_title = "", .compositor = "stub" },
        .text = try std.testing.allocator.dupe(u8, "clock"),
        .next_refresh_ms = currentTimeMs() + 10,
    });
    try registry.cache.append(std.testing.allocator, .{
        .section = .center,
        .index = 0,
        .provider = try std.testing.allocator.dupe(u8, "window"),
        .name = null,
        .snapshot_key = 123,
        .last_snapshot = .{ .outputs = 1, .workspaces = 1, .focused_workspace = 1, .focused_title = "x", .compositor = "stub" },
        .text = try std.testing.allocator.dupe(u8, "window"),
        .next_refresh_ms = null,
    });

    const stats = registry.runtimeStats(1000);
    try std.testing.expectEqual(@as(usize, 2), stats.cache_entries);
    try std.testing.expectEqual(@as(usize, 4), stats.cache_hits);
    try std.testing.expectEqual(@as(usize, 2), stats.cache_misses);
    try std.testing.expectEqual(@as(usize, 3), stats.timed_cache_hits);
    try std.testing.expectEqual(@as(usize, 1), stats.timed_cache_misses);
    try std.testing.expectEqual(@as(usize, 1), stats.snapshot_cache_hits);
    try std.testing.expectEqual(@as(usize, 1), stats.snapshot_cache_misses);
    try std.testing.expectEqual(@as(usize, 1), stats.timed_entries);
    try std.testing.expectEqual(@as(usize, 1), stats.snapshot_entries);
    try std.testing.expect(stats.next_wake_delay_ms != null);
}

const CountingProviderState = struct {
    render_count: usize = 0,
};

var counting_provider_state = CountingProviderState{};

const counting_provider_vtable = types.Provider.VTable{
    .render = countingProviderRender,
    .health = countingProviderHealth,
};

fn countingProviderRender(ctx: *const anyopaque, provider_ctx: types.ProviderContext) !types.ProviderOutput {
    const state: *CountingProviderState = @ptrCast(@alignCast(@constCast(ctx)));
    state.render_count += 1;
    return .{
        .text = try std.fmt.allocPrint(provider_ctx.allocator, "count={d}", .{state.render_count}),
    };
}

fn countingProviderHealth(_: *const anyopaque) types.ProviderHealth {
    return .ready;
}
