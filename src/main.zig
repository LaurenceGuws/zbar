const std = @import("std");
const zbar = @import("zbar");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (hasArg(args, "--help")) {
        try printUsage();
        return;
    }

    if (hasArg(args, "--print-config")) {
        try zbar.config.printDefault();
        return;
    }

    if (hasArg(args, "--print-integration-plan")) {
        try zbar.integrations.printPlan();
        return;
    }

    if (hasArg(args, "--print-provider-health")) {
        try printProviderHealth();
        return;
    }

    if (hasArg(args, "--print-runtime-stats")) {
        try printRuntimeStats(args);
        return;
    }

    if (hasArg(args, "--print-ui-capabilities")) {
        try zbar.ui.printLayerShellCapabilities();
        return;
    }

    if (hasArg(args, "--lint-config")) {
        try lintConfig(args, false);
        return;
    }

    if (hasArg(args, "--lint-config-strict")) {
        try lintConfig(args, true);
        return;
    }

    var app = zbar.app.bootstrap();
    defer app.deinit();

    try app.run(parseRunOptions(args));
}

fn hasArg(args: []const []const u8, flag: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, flag)) return true;
    }
    return false;
}

fn printUsage() !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buffer);
    const out = &writer.interface;
    try out.print("zbar\n", .{});
    try out.print("  --help                    Show usage\n", .{});
    try out.print("  --print-config            Print the built-in config\n", .{});
    try out.print("  --print-integration-plan  Print sibling integration targets\n", .{});
    try out.print("  --print-provider-health   Print provider health snapshot\n", .{});
    try out.print("  --print-runtime-stats    Print scheduler/cache runtime snapshot\n", .{});
    try out.print("  --print-ui-capabilities  Print layer-shell/ui environment readiness\n", .{});
    try out.print("  --lint-config            Validate config against schema\n", .{});
    try out.print("  --lint-config-strict     Validate config and exit non-zero on issues\n", .{});
    try out.print("  --config <path>          Use an explicit Lua config file\n", .{});
    try out.print("  --once                   Render one frame and exit\n", .{});
    try out.print("  --frames <n>             Render n frames and exit\n", .{});
    try out.print("  --tick-ms <n>            Override redraw interval in milliseconds\n", .{});
    try out.print("  --ui-backend <name>      Select ui backend: auto|sdl|layer-shell|headless\n", .{});
    try out.print("  --debug-runtime          Print per-frame scheduler stats to stderr\n", .{});
    try out.flush();
}

fn printProviderHealth() !void {
    const allocator = std.heap.page_allocator;
    const registry = zbar.modules.Registry.default();
    const report = try registry.renderHealthReport(allocator);
    defer allocator.free(report);

    var buffer: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buffer);
    const out = &writer.interface;
    try out.print("{s}", .{report});
    try out.flush();
}

fn printRuntimeStats(args: []const []const u8) !void {
    const allocator = std.heap.page_allocator;
    const loader = zbar.config.Loader.init(allocator);
    var cfg = if (argValueAfterFlag(args, "--config")) |path|
        try zbar.config.lua_config.loadFromPath(allocator, path)
    else
        try loader.load();
    defer cfg.deinit(allocator);

    var registry = zbar.modules.Registry.default();
    defer registry.deinit(allocator);
    const backend = zbar.wm.defaultBackend();
    const snapshot = backend.snapshot();
    const frame = try registry.renderFrame(allocator, cfg.bar, .{
        .snapshot = snapshot,
        .provider_defaults = cfg.provider_defaults,
    });
    defer frame.deinit(allocator);

    const stats = registry.runtimeStats(cfg.bar.effectiveTickMs());

    var buffer: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buffer);
    const out = &writer.interface;
    try out.print("cache_entries={d}\n", .{stats.cache_entries});
    try out.print("cache_hits={d}\n", .{stats.cache_hits});
    try out.print("cache_misses={d}\n", .{stats.cache_misses});
    try out.print("timed_cache_hits={d}\n", .{stats.timed_cache_hits});
    try out.print("timed_cache_misses={d}\n", .{stats.timed_cache_misses});
    try out.print("snapshot_cache_hits={d}\n", .{stats.snapshot_cache_hits});
    try out.print("snapshot_cache_misses={d}\n", .{stats.snapshot_cache_misses});
    try out.print("timed_entries={d}\n", .{stats.timed_entries});
    try out.print("snapshot_entries={d}\n", .{stats.snapshot_entries});
    try out.print("redraw_count=1\n", .{});
    try out.print("suppressed_redraws=0\n", .{});
    try out.print("next_wake_delay_ms={d}\n", .{stats.next_wake_delay_ms orelse 0});
    try out.flush();
}

fn lintConfig(args: []const []const u8, strict: bool) !void {
    const allocator = std.heap.page_allocator;
    const result = if (argValueAfterFlag(args, "--config")) |path|
        try zbar.config.lintDetailedFromPath(allocator, path)
    else
        try zbar.config.lintDetailed(allocator);
    defer allocator.free(result.output);

    var buffer: [2048]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buffer);
    const out = &writer.interface;
    try out.print("{s}", .{result.output});
    try out.flush();

    if (strict and !result.ok) std.process.exit(2);
}

fn argValueAfterFlag(args: []const []const u8, flag: []const u8) ?[]const u8 {
    for (args, 0..) |arg, i| {
        if (!std.mem.eql(u8, arg, flag)) continue;
        if (i + 1 >= args.len) return null;
        return args[i + 1];
    }
    return null;
}

fn parseRunOptions(args: []const []const u8) zbar.app.RunOptions {
    var options = zbar.app.RunOptions{};
    options.once = hasArg(args, "--once");
    if (argValueAfterFlag(args, "--frames")) |value| {
        options.max_frames = std.fmt.parseInt(u32, value, 10) catch null;
    }
    if (argValueAfterFlag(args, "--tick-ms")) |value| {
        options.tick_ms_override = std.fmt.parseInt(u64, value, 10) catch options.tick_ms_override;
    }
    if (argValueAfterFlag(args, "--ui-backend")) |value| {
        options.ui_backend = parseUiBackend(value) orelse options.ui_backend;
    }
    options.debug_runtime = hasArg(args, "--debug-runtime");
    if (options.once and options.max_frames == null) options.max_frames = 1;
    return options;
}

fn parseUiBackend(value: []const u8) ?zbar.app.RunOptions.UiBackend {
    if (std.mem.eql(u8, value, "auto")) return .auto;
    if (std.mem.eql(u8, value, "sdl")) return .sdl;
    if (std.mem.eql(u8, value, "layer-shell")) return .layer_shell;
    if (std.mem.eql(u8, value, "headless")) return .headless;
    return null;
}

test "hasArg detects present flag" {
    const args = [_][]const u8{ "zbar", "--help" };
    try std.testing.expect(hasArg(&args, "--help"));
}

test "argValueAfterFlag returns following argument" {
    const args = [_][]const u8{ "zbar", "--config", "config.lua" };
    try std.testing.expectEqualStrings("config.lua", argValueAfterFlag(&args, "--config").?);
}

test "parseRunOptions reads flags" {
    const args = [_][]const u8{ "zbar", "--frames", "3", "--tick-ms", "50", "--debug-runtime", "--ui-backend", "headless" };
    const options = parseRunOptions(&args);
    try std.testing.expectEqual(@as(?u32, 3), options.max_frames);
    try std.testing.expectEqual(@as(?u64, 50), options.tick_ms_override);
    try std.testing.expect(options.debug_runtime);
    try std.testing.expectEqual(zbar.app.RunOptions.UiBackend.headless, options.ui_backend);
}
