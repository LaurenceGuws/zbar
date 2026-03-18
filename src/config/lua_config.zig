const std = @import("std");
const config = @import("mod.zig");
const default_lua = @import("default_lua.zig");
const schema = @import("schema.zig");
const lua_api = @import("../lua/api.zig");
const lua_reader = @import("../lua/reader.zig");

pub fn load(allocator: std.mem.Allocator) !config.Config {
    const path = try default_lua.ensureDefaultConfig(allocator);
    defer allocator.free(path);
    return loadFromPath(allocator, path);
}

pub fn loadFromPath(allocator: std.mem.Allocator, path: []const u8) !config.Config {
    var lua = try lua_api.State.init();
    defer lua.deinit();
    try lua.loadFile(allocator, path);
    if (!lua.topIsTable()) return error.InvalidConfig;
    return parseConfig(lua, allocator, -1);
}

fn parseConfig(lua: lua_api.State, allocator: std.mem.Allocator, idx: c_int) !config.Config {
    var out = config.defaultConfig();
    errdefer out.deinit(allocator);
    const root = lua_reader.Reader.init(lua, allocator, idx);

    if (root.child("bar")) |bar_reader| {
        defer bar_reader.finish();
        out.bar = try parseBarConfig(bar_reader);
    }

    if (root.child("integrations")) |integrations_reader| {
        defer integrations_reader.finish();
        try parseIntegrations(integrations_reader, &out.integrations);
    }

    if (root.child("providers")) |providers_reader| {
        defer providers_reader.finish();
        try parseProviderDefaults(providers_reader, &out.provider_defaults);
    }

    return out;
}

fn parseBarConfig(reader: lua_reader.Reader) !config.BarConfig {
    const allocator = reader.allocator;
    var out = config.defaultBarConfig();
    errdefer out.deinit(allocator);

    try schema.applyBarVisuals(reader, &out);
    try schema.replaceProviderSection(allocator, &out.left, reader.child("left"));
    try schema.replaceProviderSection(allocator, &out.center, reader.child("center"));
    try schema.replaceProviderSection(allocator, &out.right, reader.child("right"));

    return out;
}

fn parseProviderSection(reader: lua_reader.Reader) ![]config.ProviderConfig {
    return schema.readProviderSection(reader);
}

fn parseProviderConfig(reader: lua_reader.Reader) !config.ProviderConfig {
    return schema.readProviderConfig(reader);
}

fn parseSettingMap(reader: lua_reader.Reader) ![]config.Setting {
    return schema.readSettingMap(reader);
}

fn parseProviderDefaults(reader: lua_reader.Reader, target: *config.ProviderDefaults) !void {
    try schema.applyProviderDefaults(reader, target);
}

fn parseIntegrations(reader: lua_reader.Reader, target: *config.IntegrationConfig) !void {
    try schema.applyIntegrations(reader, target);
}
