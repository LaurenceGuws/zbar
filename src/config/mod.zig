const std = @import("std");
pub const default_lua = @import("default_lua.zig");
pub const lua_config = @import("lua_config.zig");
pub const meta = @import("meta.zig");
pub const schema = @import("schema.zig");

pub const Setting = struct {
    key: []u8,
    value: []u8,

    pub fn deinit(self: Setting, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }
};

pub const ProviderConfig = struct {
    provider: []u8,
    name: ?[]u8 = null,
    format: ?[]u8 = null,
    interval_ms: u32 = 1000,
    max_width: u16 = 0,
    settings: []Setting = &.{},

    pub fn init(allocator: std.mem.Allocator, provider: []const u8) !ProviderConfig {
        return .{ .provider = try allocator.dupe(u8, provider) };
    }

    pub fn deinit(self: *ProviderConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.provider);
        if (self.name) |name| allocator.free(name);
        if (self.format) |format| allocator.free(format);
        for (self.settings) |setting| setting.deinit(allocator);
        if (self.settings.len > 0) allocator.free(self.settings);
    }
};

pub const ThemeConfig = struct {
    pub const Anchor = enum {
        top,
        top_left,
        top_right,
        bottom,
        bottom_left,
        bottom_right,

        pub fn parse(value: []const u8) ?Anchor {
            if (std.mem.eql(u8, value, "top")) return .top;
            if (std.mem.eql(u8, value, "top-left")) return .top_left;
            if (std.mem.eql(u8, value, "top-right")) return .top_right;
            if (std.mem.eql(u8, value, "bottom")) return .bottom;
            if (std.mem.eql(u8, value, "bottom-left")) return .bottom_left;
            if (std.mem.eql(u8, value, "bottom-right")) return .bottom_right;
            return null;
        }

        pub fn luaName(self: Anchor) []const u8 {
            return switch (self) {
                .top => "top",
                .top_left => "top-left",
                .top_right => "top-right",
                .bottom => "bottom",
                .bottom_left => "bottom-left",
                .bottom_right => "bottom-right",
            };
        }
    };

    segment_background: []u8,
    accent_background: []u8,
    subtle_background: []u8,
    warning_background: []u8,
    accent_foreground: []u8,
    font_path: []u8,
    font_fallback_path: []u8,
    font_fallback_path_2: []u8,
    preview_width_px: u16,
    anchor: Anchor,
    horizontal_padding_px: u16,
    segment_padding_x_px: u16,
    segment_padding_y_px: u16,
    font_points: u16,

    pub fn deinit(self: *ThemeConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.segment_background);
        allocator.free(self.accent_background);
        allocator.free(self.subtle_background);
        allocator.free(self.warning_background);
        allocator.free(self.accent_foreground);
        allocator.free(self.font_path);
        allocator.free(self.font_fallback_path);
        allocator.free(self.font_fallback_path_2);
    }
};

pub const BarConfig = struct {
    height_px: u16,
    section_gap_px: u16,
    background: []u8,
    foreground: []u8,
    theme: ThemeConfig,
    left: []ProviderConfig,
    center: []ProviderConfig,
    right: []ProviderConfig,

    pub fn deinit(self: *BarConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.background);
        allocator.free(self.foreground);
        self.theme.deinit(allocator);
        deinitProviders(allocator, self.left);
        deinitProviders(allocator, self.center);
        deinitProviders(allocator, self.right);
    }

    pub fn effectiveTickMs(self: BarConfig) u64 {
        var min_tick_ms: ?u64 = null;
        considerProviderIntervals(&min_tick_ms, self.left);
        considerProviderIntervals(&min_tick_ms, self.center);
        considerProviderIntervals(&min_tick_ms, self.right);
        return min_tick_ms orelse 1000;
    }
};

pub const IntegrationConfig = struct {
    zide_socket_name: []u8,
    wayspot_socket_name: []u8,

    pub fn deinit(self: *IntegrationConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.zide_socket_name);
        allocator.free(self.wayspot_socket_name);
    }
};

pub const ProviderDefault = struct {
    provider: []u8,
    settings: []Setting,

    pub fn deinit(self: *ProviderDefault, allocator: std.mem.Allocator) void {
        allocator.free(self.provider);
        for (self.settings) |setting| setting.deinit(allocator);
        allocator.free(self.settings);
    }
};

pub const ProviderDefaults = struct {
    entries: std.ArrayList(ProviderDefault) = .empty,

    pub fn deinit(self: *ProviderDefaults, allocator: std.mem.Allocator) void {
        for (self.entries.items) |*entry| entry.deinit(allocator);
        self.entries.deinit(allocator);
    }

    pub fn find(self: ProviderDefaults, provider: []const u8) ?[]const Setting {
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.provider, provider)) return entry.settings;
        }
        return null;
    }
};

pub const Config = struct {
    bar: BarConfig,
    integrations: IntegrationConfig,
    provider_defaults: ProviderDefaults,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        self.bar.deinit(allocator);
        self.integrations.deinit(allocator);
        self.provider_defaults.deinit(allocator);
    }
};

pub const Loader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Loader {
        return .{ .allocator = allocator };
    }

    pub fn load(self: Loader) !Config {
        return lua_config.load(self.allocator);
    }
};

pub fn defaultConfig() Config {
    const allocator = std.heap.page_allocator;
    return .{
        .bar = defaultBarConfigWithAllocator(allocator) catch unreachable,
        .integrations = .{
            .zide_socket_name = allocator.dupe(u8, "zide-ipc.sock") catch unreachable,
            .wayspot_socket_name = allocator.dupe(u8, "wayspot-ipc.sock") catch unreachable,
        },
        .provider_defaults = .{},
    };
}

pub fn defaultBarConfig() BarConfig {
    return defaultBarConfigWithAllocator(std.heap.page_allocator) catch unreachable;
}

fn defaultBarConfigWithAllocator(allocator: std.mem.Allocator) !BarConfig {
    return .{
        .height_px = 28,
        .section_gap_px = 12,
        .background = try allocator.dupe(u8, "#11161c"),
        .foreground = try allocator.dupe(u8, "#d7dee7"),
        .theme = .{
            .segment_background = try allocator.dupe(u8, "#2a3139"),
            .accent_background = try allocator.dupe(u8, "#275b7a"),
            .subtle_background = try allocator.dupe(u8, "#1c232a"),
            .warning_background = try allocator.dupe(u8, "#7a4627"),
            .accent_foreground = try allocator.dupe(u8, "#eff5fa"),
            .font_path = try allocator.dupe(u8, "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf"),
            .font_fallback_path = try allocator.dupe(u8, "/usr/share/fonts/TTF/IosevkaTermNerdFont-Regular.ttf"),
            .font_fallback_path_2 = try allocator.dupe(u8, "/usr/share/fonts/TTF/Hack-Regular.ttf"),
            .preview_width_px = 1280,
            .anchor = .top,
            .horizontal_padding_px = 18,
            .segment_padding_x_px = 10,
            .segment_padding_y_px = 6,
            .font_points = 15,
        },
        .left = try dupProviders(allocator, &.{
            .{ .provider = "workspaces", .name = "hypr", .format = "ws {focused}/{total}", .interval_ms = 0, .max_width = 0, .settings = &.{} },
            .{ .provider = "mode", .name = null, .format = "{compositor}", .interval_ms = 0, .max_width = 0, .settings = &.{} },
        }),
        .center = try dupProviders(allocator, &.{
            .{ .provider = "window", .name = "title", .format = null, .interval_ms = 0, .max_width = 96, .settings = &.{} },
        }),
        .right = try dupProviders(allocator, &.{
            .{ .provider = "cpu", .name = null, .format = "cpu {usage}%", .interval_ms = 1000, .max_width = 0, .settings = &.{} },
            .{ .provider = "memory", .name = null, .format = "mem {used_gib:.1}G", .interval_ms = 1000, .max_width = 0, .settings = &.{} },
            .{ .provider = "clock", .name = "local", .format = "%a %d %b %H:%M", .interval_ms = 1000, .max_width = 0, .settings = &.{} },
        }),
    };
}

fn dupProviders(allocator: std.mem.Allocator, source: []const struct {
    provider: []const u8,
    name: ?[]const u8,
    format: ?[]const u8,
    interval_ms: u32,
    max_width: u16,
    settings: []const Setting,
}) ![]ProviderConfig {
    var out = try allocator.alloc(ProviderConfig, source.len);
    errdefer allocator.free(out);
    for (source, 0..) |item, i| {
        out[i] = .{
            .provider = try allocator.dupe(u8, item.provider),
            .name = if (item.name) |name| try allocator.dupe(u8, name) else null,
            .format = if (item.format) |format| try allocator.dupe(u8, format) else null,
            .interval_ms = item.interval_ms,
            .max_width = item.max_width,
            .settings = &.{},
        };
    }
    return out;
}

fn deinitProviders(allocator: std.mem.Allocator, items: []ProviderConfig) void {
    for (items) |*item| item.deinit(allocator);
    allocator.free(items);
}

fn considerProviderIntervals(min_tick_ms: *?u64, items: []const ProviderConfig) void {
    for (items) |item| {
        if (item.interval_ms == 0) continue;
        const interval_ms: u64 = item.interval_ms;
        if (min_tick_ms.* == null or interval_ms < min_tick_ms.*.?) {
            min_tick_ms.* = interval_ms;
        }
    }
}

pub fn printDefault() !void {
    const allocator = std.heap.page_allocator;
    var cfg = try lua_config.load(allocator);
    defer cfg.deinit(allocator);
    var buffer: [2048]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buffer);
    const out = &writer.interface;
    try out.print("bar.height_px={d}\n", .{cfg.bar.height_px});
    try out.print("bar.background={s}\n", .{cfg.bar.background});
    try out.print("bar.left.providers={d}\n", .{cfg.bar.left.len});
    try out.print("integrations.zide_socket_name={s}\n", .{cfg.integrations.zide_socket_name});
    try out.print("integrations.wayspot_socket_name={s}\n", .{cfg.integrations.wayspot_socket_name});
    try out.flush();
}

pub fn lint(allocator: std.mem.Allocator) ![]u8 {
    const result = try lintDetailed(allocator);
    return result.output;
}

pub const LintResult = struct {
    ok: bool,
    issue_count: usize,
    output: []u8,
};

pub fn lintDetailed(allocator: std.mem.Allocator) !LintResult {
    const path = try default_lua.ensureDefaultConfig(allocator);
    defer allocator.free(path);
    return lintDetailedFromPath(allocator, path);
}

pub fn lintDetailedFromPath(allocator: std.mem.Allocator, path: []const u8) !LintResult {
    const source = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(source);
    var cfg = try lua_config.loadFromPath(allocator, path);
    defer cfg.deinit(allocator);
    const issues = try schema.validateConfig(allocator, cfg);
    defer {
        for (issues) |issue| issue.deinit(allocator);
        allocator.free(issues);
    }
    schema.attachLocations(source, issues);
    const rendered = try schema.renderIssues(allocator, issues);
    const summary = try std.fmt.allocPrint(
        allocator,
        "config={s} issues={d}\n{s}",
        .{ path, issues.len, rendered },
    );
    allocator.free(rendered);
    return .{
        .ok = issues.len == 0,
        .issue_count = issues.len,
        .output = summary,
    };
}

test "default config exposes provider sections" {
    var cfg = defaultConfig();
    defer cfg.deinit(std.heap.page_allocator);
    try std.testing.expect(cfg.bar.left.len > 0);
    try std.testing.expect(cfg.bar.right.len > 0);
}

test "effectiveTickMs uses smallest positive provider interval" {
    var cfg = defaultConfig();
    defer cfg.deinit(std.heap.page_allocator);
    cfg.bar.right[0].interval_ms = 1500;
    cfg.bar.right[1].interval_ms = 250;
    cfg.bar.right[2].interval_ms = 5000;
    try std.testing.expectEqual(@as(u64, 250), cfg.bar.effectiveTickMs());
}

test "effectiveTickMs falls back when all providers are event driven" {
    var cfg = defaultConfig();
    defer cfg.deinit(std.heap.page_allocator);
    for (cfg.bar.left) |*item| item.interval_ms = 0;
    for (cfg.bar.center) |*item| item.interval_ms = 0;
    for (cfg.bar.right) |*item| item.interval_ms = 0;
    try std.testing.expectEqual(@as(u64, 1000), cfg.bar.effectiveTickMs());
}
