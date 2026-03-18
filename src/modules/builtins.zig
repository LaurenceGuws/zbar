const std = @import("std");
const config = @import("../config/mod.zig");
const formatter = @import("formatter.zig");
const types = @import("types.zig");
const c = @cImport({
    @cInclude("time.h");
});

pub fn builtinProviders() []const types.Provider {
    return &providers;
}

const providers = [_]types.Provider{
    .{ .name = "workspaces", .context = &workspace_provider, .vtable = &workspace_vtable },
    .{ .name = "mode", .context = &mode_provider, .vtable = &mode_vtable },
    .{ .name = "window", .context = &window_provider, .vtable = &window_vtable },
    .{ .name = "cpu", .context = &cpu_provider, .vtable = &cpu_vtable },
    .{ .name = "memory", .context = &memory_provider, .vtable = &memory_vtable },
    .{ .name = "clock", .context = &clock_provider, .vtable = &clock_vtable },
};

const WorkspaceProvider = struct {
    fn render(_: *const anyopaque, provider_ctx: types.ProviderContext) !types.ProviderOutput {
        const allocator = provider_ctx.allocator;
        const focused = try std.fmt.allocPrint(allocator, "{d}", .{provider_ctx.snapshot.focused_workspace});
        errdefer allocator.free(focused);
        const total = try std.fmt.allocPrint(allocator, "{d}", .{provider_ctx.snapshot.workspaces});
        errdefer allocator.free(total);
        const fields = try allocator.alloc(types.Field, 2);
        fields[0] = .{ .key = "focused", .value = focused, .scalar = .{ .integer = provider_ctx.snapshot.focused_workspace } };
        fields[1] = .{ .key = "total", .value = total, .scalar = .{ .integer = provider_ctx.snapshot.workspaces } };
        const text = try formatter.formatProviderOutput(allocator, "workspaces", provider_ctx.instance, null, fields);
        return .{
            .text = text,
            .content_id = hashFields(fields),
            .payload = .{ .integer = provider_ctx.snapshot.focused_workspace },
            .fields = fields,
        };
    }

    fn health(_: *const anyopaque) types.ProviderHealth {
        return .ready;
    }
};

const ModeProvider = struct {
    fn render(_: *const anyopaque, provider_ctx: types.ProviderContext) !types.ProviderOutput {
        const fields = try providerCtxFields(provider_ctx.allocator, &.{
            .{ .key = "compositor", .value = provider_ctx.snapshot.compositor, .scalar = .{ .string = provider_ctx.snapshot.compositor } },
        });
        const text = try formatter.formatProviderOutput(provider_ctx.allocator, "mode", provider_ctx.instance, null, fields);
        return .{
            .text = text,
            .content_id = hashFields(fields),
            .payload = .{ .state = provider_ctx.snapshot.compositor },
            .fields = fields,
        };
    }

    fn health(_: *const anyopaque) types.ProviderHealth {
        return .ready;
    }
};

const WindowProvider = struct {
    fn render(_: *const anyopaque, provider_ctx: types.ProviderContext) !types.ProviderOutput {
        const title = try formatter.presentWindowTitle(provider_ctx.allocator, provider_ctx.instance, provider_ctx.snapshot.focused_title);
        errdefer provider_ctx.allocator.free(title);
        const fields = try providerCtxFields(provider_ctx.allocator, &.{.{ .key = "title", .value = title, .scalar = .{ .string = title } }});
        const text = try formatter.formatProviderOutput(provider_ctx.allocator, "window", provider_ctx.instance, title, fields);
        return .{
            .text = text,
            .content_id = hashFields(fields),
            .payload = .{ .text = title },
            .fields = fields,
        };
    }

    fn health(_: *const anyopaque) types.ProviderHealth {
        return .ready;
    }
};

const CpuProvider = struct {
    fn render(_: *const anyopaque, provider_ctx: types.ProviderContext) !types.ProviderOutput {
        const usage_value = try cpuUsageString(provider_ctx);
        const fields = try providerCtxFields(provider_ctx.allocator, &.{
            .{ .key = "usage", .value = usage_value, .scalar = .{ .integer = std.fmt.parseInt(i64, usage_value, 10) catch 0 } },
        });
        const text = try formatter.formatProviderOutput(provider_ctx.allocator, "cpu", provider_ctx.instance, null, fields);
        return .{
            .text = text,
            .content_id = hashFields(fields),
            .payload = .{ .integer = std.fmt.parseInt(i64, usage_value, 10) catch 0 },
            .fields = fields,
        };
    }

    fn health(_: *const anyopaque) types.ProviderHealth {
        return if (readCpuUsagePercent() != null) .ready else .degraded;
    }
};

const MemoryProvider = struct {
    fn render(_: *const anyopaque, provider_ctx: types.ProviderContext) !types.ProviderOutput {
        const unit = setting(provider_ctx.instance, provider_ctx.defaults, "unit") orelse "gib";
        const used_gib = try memoryValueString(provider_ctx, .gib);
        const used_mib = try memoryValueString(provider_ctx, .mib);
        const fields = try providerCtxFields(provider_ctx.allocator, &.{
            .{ .key = "used_gib", .value = used_gib, .scalar = .{ .number = std.fmt.parseFloat(f64, used_gib) catch 0.0 } },
            .{ .key = "used_mib", .value = used_mib, .scalar = .{ .integer = std.fmt.parseInt(i64, used_mib, 10) catch 0 } },
            .{ .key = "unit", .value = try provider_ctx.allocator.dupe(u8, unit), .scalar = .{ .string = unit } },
        });
        const text = try formatter.formatProviderOutput(provider_ctx.allocator, "memory", provider_ctx.instance, null, fields);
        return .{
            .text = text,
            .content_id = hashFields(fields),
            .payload = .{ .number = std.fmt.parseFloat(f64, used_gib) catch 0.0 },
            .fields = fields,
        };
    }

    fn health(_: *const anyopaque) types.ProviderHealth {
        return if (readMemoryUsage() != null) .ready else .degraded;
    }
};

const ClockProvider = struct {
    fn render(_: *const anyopaque, provider_ctx: types.ProviderContext) !types.ProviderOutput {
        const format = formatter.defaultClockSourceFormat(provider_ctx.instance);
        const timezone = setting(provider_ctx.instance, provider_ctx.defaults, "timezone") orelse "local";
        const now = std.time.timestamp();
        const formatted = try formattedClock(provider_ctx.allocator, timezone, format);
        const timestamp = try std.fmt.allocPrint(provider_ctx.allocator, "{d}", .{now});
        const fields = try providerCtxFields(provider_ctx.allocator, &.{
            .{ .key = "timestamp", .value = timestamp, .scalar = .{ .integer = now } },
            .{ .key = "formatted", .value = try provider_ctx.allocator.dupe(u8, formatted), .scalar = .{ .string = formatted } },
            .{ .key = "timezone", .value = try provider_ctx.allocator.dupe(u8, timezone), .scalar = .{ .string = timezone } },
        });
        const text = try formatter.formatProviderOutput(provider_ctx.allocator, "clock", provider_ctx.instance, null, fields);
        return .{
            .text = text,
            .content_id = hashFields(fields),
            .payload = .{ .integer = now },
            .fields = fields,
        };
    }

    fn health(_: *const anyopaque) types.ProviderHealth {
        return .ready;
    }
};

var workspace_provider = WorkspaceProvider{};
var mode_provider = ModeProvider{};
var window_provider = WindowProvider{};
var cpu_provider = CpuProvider{};
var memory_provider = MemoryProvider{};
var clock_provider = ClockProvider{};

const workspace_vtable = types.Provider.VTable{ .render = WorkspaceProvider.render, .health = WorkspaceProvider.health };
const mode_vtable = types.Provider.VTable{ .render = ModeProvider.render, .health = ModeProvider.health };
const window_vtable = types.Provider.VTable{ .render = WindowProvider.render, .health = WindowProvider.health };
const cpu_vtable = types.Provider.VTable{ .render = CpuProvider.render, .health = CpuProvider.health };
const memory_vtable = types.Provider.VTable{ .render = MemoryProvider.render, .health = MemoryProvider.health };
const clock_vtable = types.Provider.VTable{ .render = ClockProvider.render, .health = ClockProvider.health };

fn providerCtxFields(
    allocator: std.mem.Allocator,
    source: []const struct { key: []const u8, value: []const u8, scalar: types.Scalar },
) ![]types.Field {
    const out = try allocator.alloc(types.Field, source.len);
    for (source, 0..) |field, i| {
        out[i] = .{
            .key = field.key,
            .value = try allocator.dupe(u8, field.value),
            .scalar = field.scalar,
        };
    }
    return out;
}

fn setting(instance: config.ProviderConfig, defaults: config.ProviderDefaults, key: []const u8) ?[]const u8 {
    for (instance.settings) |item| {
        if (std.mem.eql(u8, item.key, key)) return item.value;
    }
    if (defaults.find(instance.provider)) |items| {
        for (items) |item| {
            if (std.mem.eql(u8, item.key, key)) return item.value;
        }
    }
    return null;
}

fn numericSetting(provider_ctx: types.ProviderContext, key: []const u8, fallback: []const u8) ![]u8 {
    return provider_ctx.allocator.dupe(u8, setting(provider_ctx.instance, provider_ctx.defaults, key) orelse fallback);
}

fn cpuUsageString(provider_ctx: types.ProviderContext) ![]u8 {
    if (setting(provider_ctx.instance, provider_ctx.defaults, "usage")) |value| {
        return provider_ctx.allocator.dupe(u8, value);
    }
    const usage = readCpuUsagePercent() orelse return provider_ctx.allocator.dupe(u8, "0");
    return std.fmt.allocPrint(provider_ctx.allocator, "{d}", .{usage});
}

const MemoryUnit = enum {
    gib,
    mib,
};

fn memoryValueString(provider_ctx: types.ProviderContext, unit: MemoryUnit) ![]u8 {
    const override_key = switch (unit) {
        .gib => "used_gib",
        .mib => "used_mib",
    };
    if (setting(provider_ctx.instance, provider_ctx.defaults, override_key)) |value| {
        return provider_ctx.allocator.dupe(u8, value);
    }

    const memory = readMemoryUsage() orelse switch (unit) {
        .gib => return provider_ctx.allocator.dupe(u8, "0.0"),
        .mib => return provider_ctx.allocator.dupe(u8, "0"),
    };

    return switch (unit) {
        .gib => std.fmt.allocPrint(provider_ctx.allocator, "{d:.1}", .{memory.used_gib}),
        .mib => std.fmt.allocPrint(provider_ctx.allocator, "{d}", .{memory.used_mib}),
    };
}

fn readCpuUsagePercent() ?u8 {
    const data = readSmallFile("/proc/stat") orelse return null;
    defer std.heap.page_allocator.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    const first = lines.next() orelse return null;
    if (!std.mem.startsWith(u8, first, "cpu ")) return null;

    var it = std.mem.tokenizeScalar(u8, first[4..], ' ');
    var values: [8]u64 = [_]u64{0} ** 8;
    var i: usize = 0;
    while (it.next()) |token| {
        if (i >= values.len) break;
        values[i] = std.fmt.parseInt(u64, token, 10) catch return null;
        i += 1;
    }
    if (i < 4) return null;

    const idle = values[3] + (if (i > 4) values[4] else 0);
    var total: u64 = 0;
    for (values[0..i]) |value| total += value;
    if (total == 0 or idle > total) return null;
    const active = total - idle;
    return @intCast(@min(@as(u64, 100), (active * 100) / total));
}

const MemoryUsage = struct {
    used_mib: u64,
    used_gib: f64,
};

fn readMemoryUsage() ?MemoryUsage {
    const data = readSmallFile("/proc/meminfo") orelse return null;
    defer std.heap.page_allocator.free(data);

    var total_kib: ?u64 = null;
    var available_kib: ?u64 = null;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal:")) {
            total_kib = parseMeminfoValue(line);
        } else if (std.mem.startsWith(u8, line, "MemAvailable:")) {
            available_kib = parseMeminfoValue(line);
        }
    }

    const total = total_kib orelse return null;
    const available = available_kib orelse return null;
    if (available > total) return null;
    const used_kib = total - available;
    return .{
        .used_mib = used_kib / 1024,
        .used_gib = @as(f64, @floatFromInt(used_kib)) / (1024.0 * 1024.0),
    };
}

fn parseMeminfoValue(line: []const u8) ?u64 {
    var it = std.mem.tokenizeAny(u8, line, " \t:");
    _ = it.next();
    const value = it.next() orelse return null;
    return std.fmt.parseInt(u64, value, 10) catch null;
}

fn readSmallFile(path: []const u8) ?[]u8 {
    return std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 64 * 1024) catch null;
}

fn formattedClock(allocator: std.mem.Allocator, timezone: []const u8, format: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, format, '%') == null) {
        return allocator.dupe(u8, format);
    }

    const now: c.time_t = @intCast(std.time.timestamp());
    var tm_value: c.struct_tm = undefined;
    const tm_ptr = if (std.mem.eql(u8, timezone, "utc"))
        c.gmtime_r(&now, &tm_value)
    else
        c.localtime_r(&now, &tm_value);
    if (tm_ptr == null) return allocator.dupe(u8, format);

    const format_z = try allocator.dupeZ(u8, format);
    defer allocator.free(format_z);
    var buffer: [128]u8 = undefined;
    const written = c.strftime(&buffer, buffer.len, format_z.ptr, &tm_value);
    if (written == 0) return allocator.dupe(u8, format);
    return allocator.dupe(u8, buffer[0..written]);
}

fn hashFields(fields: []const types.Field) u64 {
    var hasher = std.hash.Wyhash.init(0);
    for (fields) |field| {
        hasher.update(field.key);
        hasher.update("=");
        hasher.update(field.value);
        hasher.update("|");
    }
    return hasher.final();
}

test "cpu provider reads proc stat or falls back cleanly" {
    _ = readCpuUsagePercent();
}

test "memory provider reads meminfo or falls back cleanly" {
    _ = readMemoryUsage();
}

test "clock formatting supports utc timestamp format strings" {
    const formatted = try formattedClock(std.testing.allocator, "utc", "%Y");
    defer std.testing.allocator.free(formatted);
    try std.testing.expect(formatted.len == 4);
}
