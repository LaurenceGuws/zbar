const std = @import("std");
const config = @import("mod.zig");
const meta = @import("meta.zig");
const lua_reader = @import("../lua/reader.zig");

pub fn applyBarVisuals(reader: lua_reader.Reader, target: *config.BarConfig) !void {
    for (bar_visual_field_bindings) |binding| {
        try binding.apply(reader, target);
    }
    if (reader.child("theme")) |theme_reader| {
        defer theme_reader.finish();
        try applyBarTheme(theme_reader, &target.theme);
    }
}

const BarVisualFieldBinding = struct {
    name: []const u8,
    apply: *const fn (lua_reader.Reader, *config.BarConfig) anyerror!void,
};

const bar_visual_field_bindings = [_]BarVisualFieldBinding{
    bindBarVisualInt(.height_px, u16),
    bindBarVisualInt(.section_gap_px, u16),
    bindBarVisualString(.background),
    bindBarVisualString(.foreground),
};

fn bindBarVisualString(comptime field: std.meta.FieldEnum(config.BarConfig)) BarVisualFieldBinding {
    return .{
        .name = @tagName(field),
        .apply = struct {
            fn apply(reader: lua_reader.Reader, target: *config.BarConfig) !void {
                try reader.stringOwned(@tagName(field), &@field(target, @tagName(field)));
            }
        }.apply,
    };
}

fn bindBarVisualInt(comptime field: std.meta.FieldEnum(config.BarConfig), comptime T: type) BarVisualFieldBinding {
    return .{
        .name = @tagName(field),
        .apply = struct {
            fn apply(reader: lua_reader.Reader, target: *config.BarConfig) !void {
                reader.intInto(T, @tagName(field), &@field(target, @tagName(field)));
            }
        }.apply,
    };
}

pub fn validateBarTheme(
    allocator: std.mem.Allocator,
    issues: *std.ArrayList(ValidationIssue),
    theme: config.ThemeConfig,
) !void {
    try validateIntField(allocator, issues, "bar.theme.preview_width_px", meta.bar_theme_fields, "preview_width_px", theme.preview_width_px);
    try validateEnumField(allocator, issues, "bar.theme.anchor", meta.bar_theme_fields, "anchor", theme.anchor.luaName());
    try validateIntField(allocator, issues, "bar.theme.horizontal_padding_px", meta.bar_theme_fields, "horizontal_padding_px", theme.horizontal_padding_px);
    try validateIntField(allocator, issues, "bar.theme.segment_padding_x_px", meta.bar_theme_fields, "segment_padding_x_px", theme.segment_padding_x_px);
    try validateIntField(allocator, issues, "bar.theme.segment_padding_y_px", meta.bar_theme_fields, "segment_padding_y_px", theme.segment_padding_y_px);
    try validateIntField(allocator, issues, "bar.theme.font_points", meta.bar_theme_fields, "font_points", theme.font_points);
    try validateIntField(allocator, issues, "bar.theme.segment_radius_px", meta.bar_theme_fields, "segment_radius_px", theme.segment_radius_px);
    try validateIntField(allocator, issues, "bar.theme.edge_line_px", meta.bar_theme_fields, "edge_line_px", theme.edge_line_px);
    try validateIntField(allocator, issues, "bar.theme.edge_shadow_alpha", meta.bar_theme_fields, "edge_shadow_alpha", theme.edge_shadow_alpha);
    try validateIntField(allocator, issues, "bar.theme.segment_border_px", meta.bar_theme_fields, "segment_border_px", theme.segment_border_px);
    try validateIntField(allocator, issues, "bar.theme.segment_border_alpha", meta.bar_theme_fields, "segment_border_alpha", theme.segment_border_alpha);
}

pub fn validateBarVisuals(
    allocator: std.mem.Allocator,
    issues: *std.ArrayList(ValidationIssue),
    bar_cfg: config.BarConfig,
) !void {
    try validateIntField(allocator, issues, "bar.height_px", meta.bar_visual_fields, "height_px", bar_cfg.height_px);
    try validateIntField(allocator, issues, "bar.section_gap_px", meta.bar_visual_fields, "section_gap_px", bar_cfg.section_gap_px);
}

fn readAnchor(reader: lua_reader.Reader, target: *config.ThemeConfig.Anchor) !void {
    var raw: ?[]u8 = null;
    defer if (raw) |value| reader.allocator.free(value);
    try reader.optionalStringOwned("anchor", &raw);
    if (raw) |value| {
        if (config.ThemeConfig.Anchor.parse(value)) |anchor| {
            target.* = anchor;
        }
    }
}

fn applyBarTheme(reader: lua_reader.Reader, target: *config.ThemeConfig) !void {
    for (theme_field_bindings) |binding| {
        try binding.apply(reader, target);
    }
}

const ThemeFieldBinding = struct {
    name: []const u8,
    apply: *const fn (lua_reader.Reader, *config.ThemeConfig) anyerror!void,
};

const theme_field_bindings = [_]ThemeFieldBinding{
    bindThemeString(.segment_background),
    bindThemeString(.accent_background),
    bindThemeString(.subtle_background),
    bindThemeString(.warning_background),
    bindThemeString(.accent_foreground),
    bindThemeString(.font_path),
    bindThemeString(.font_fallback_path),
    bindThemeString(.font_fallback_path_2),
    bindThemeInt(.preview_width_px, u16),
    bindThemeAnchor(.anchor),
    bindThemeInt(.horizontal_padding_px, u16),
    bindThemeInt(.segment_padding_x_px, u16),
    bindThemeInt(.segment_padding_y_px, u16),
    bindThemeInt(.font_points, u16),
    bindThemeInt(.segment_radius_px, u16),
    bindThemeInt(.edge_line_px, u16),
    bindThemeInt(.edge_shadow_alpha, u8),
    bindThemeInt(.segment_border_px, u16),
    bindThemeInt(.segment_border_alpha, u8),
};

fn bindThemeString(comptime field: std.meta.FieldEnum(config.ThemeConfig)) ThemeFieldBinding {
    return .{
        .name = @tagName(field),
        .apply = struct {
            fn apply(reader: lua_reader.Reader, target: *config.ThemeConfig) !void {
                try reader.stringOwned(@tagName(field), &@field(target, @tagName(field)));
            }
        }.apply,
    };
}

fn bindThemeInt(comptime field: std.meta.FieldEnum(config.ThemeConfig), comptime T: type) ThemeFieldBinding {
    return .{
        .name = @tagName(field),
        .apply = struct {
            fn apply(reader: lua_reader.Reader, target: *config.ThemeConfig) !void {
                reader.intInto(T, @tagName(field), &@field(target, @tagName(field)));
            }
        }.apply,
    };
}

fn bindThemeAnchor(comptime field: std.meta.FieldEnum(config.ThemeConfig)) ThemeFieldBinding {
    return .{
        .name = @tagName(field),
        .apply = struct {
            fn apply(reader: lua_reader.Reader, target: *config.ThemeConfig) !void {
                try readAnchor(reader, &@field(target, @tagName(field)));
            }
        }.apply,
    };
}

pub fn readProviderSection(reader: lua_reader.Reader) ![]config.ProviderConfig {
    const allocator = reader.allocator;
    const len = reader.arrayLen();
    var items = try allocator.alloc(config.ProviderConfig, len);
    errdefer {
        for (items) |*item| item.deinit(allocator);
        allocator.free(items);
    }

    for (0..len) |i| {
        const item_reader = reader.arrayItem(i + 1) orelse return error.InvalidConfig;
        defer item_reader.finish();
        items[i] = try readProviderConfig(item_reader);
    }

    return items;
}

pub fn readProviderConfig(reader: lua_reader.Reader) !config.ProviderConfig {
    const allocator = reader.allocator;
    var out = try config.ProviderConfig.init(allocator, "custom");
    errdefer out.deinit(allocator);

    try reader.stringOwned("provider", &out.provider);
    try reader.optionalStringOwned("name", &out.name);
    try reader.optionalStringOwned("format", &out.format);
    reader.intInto(u32, "interval_ms", &out.interval_ms);
    reader.intInto(u16, "max_width", &out.max_width);

    if (reader.child("settings")) |settings_reader| {
        defer settings_reader.finish();
        out.settings = try readSettingMap(settings_reader);
    }

    return out;
}

pub fn readSettingMap(reader: lua_reader.Reader) ![]config.Setting {
    const allocator = reader.allocator;
    var list = std.ArrayList(config.Setting).empty;
    defer list.deinit(allocator);

    var it = reader.iter();
    defer it.finish();
    while (it.next()) {
        if (it.keyString()) |key| {
            const value = try reader.scalarStringOwned(-1);
            errdefer allocator.free(value);
            try list.append(allocator, .{
                .key = try allocator.dupe(u8, key),
                .value = value,
            });
        }
    }

    return list.toOwnedSlice(allocator);
}

pub fn applyIntegrations(reader: lua_reader.Reader, target: *config.IntegrationConfig) !void {
    try reader.stringOwned("zide_socket_name", &target.zide_socket_name);
    try reader.stringOwned("wayspot_socket_name", &target.wayspot_socket_name);
}

pub fn applyProviderDefaults(reader: lua_reader.Reader, target: *config.ProviderDefaults) !void {
    const allocator = reader.allocator;
    target.deinit(allocator);
    target.* = .{};

    var it = reader.iter();
    defer it.finish();
    while (it.next()) {
        if (it.keyString()) |provider_name| {
            if (!reader.state.isTable(-1)) continue;
            const nested = lua_reader.Reader.init(reader.state, allocator, -1);
            try target.entries.append(allocator, .{
                .provider = try allocator.dupe(u8, provider_name),
                .settings = try readSettingMap(nested),
            });
        }
    }
}

pub fn replaceProviderSection(
    allocator: std.mem.Allocator,
    target: *[]config.ProviderConfig,
    section_reader: ?lua_reader.Reader,
) !void {
    const reader = section_reader orelse return;
    defer reader.finish();
    freeProviderSlice(allocator, target.*);
    target.* = try readProviderSection(reader);
}

pub fn freeProviderSlice(allocator: std.mem.Allocator, items: []config.ProviderConfig) void {
    for (items) |*item| item.deinit(allocator);
    allocator.free(items);
}

pub const ValidationIssue = struct {
    path: []u8,
    message: []u8,
    line: ?usize = null,

    pub fn deinit(self: ValidationIssue, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.message);
    }
};

pub fn validateConfig(allocator: std.mem.Allocator, cfg: config.Config) ![]ValidationIssue {
    var issues = std.ArrayList(ValidationIssue).empty;
    defer if (@TypeOf(issues) == std.ArrayList(ValidationIssue)) {} else {};
    errdefer {
        for (issues.items) |issue| issue.deinit(allocator);
        issues.deinit(allocator);
    }

    try validateProviderSection(allocator, &issues, "bar.left", cfg.bar.left);
    try validateProviderSection(allocator, &issues, "bar.center", cfg.bar.center);
    try validateProviderSection(allocator, &issues, "bar.right", cfg.bar.right);
    try validateBarVisuals(allocator, &issues, cfg.bar);
    try validateBarTheme(allocator, &issues, cfg.bar.theme);
    try validateProviderDefaults(allocator, &issues, cfg.provider_defaults);

    return issues.toOwnedSlice(allocator);
}

pub fn renderIssues(allocator: std.mem.Allocator, issues: []const ValidationIssue) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    if (issues.len == 0) {
        try writer.writeAll("ok\n");
        return out.toOwnedSlice(allocator);
    }

    for (issues) |issue| {
        if (issue.line) |line| {
            try writer.print("{s}:{d}: {s}\n", .{ issue.path, line, issue.message });
        } else {
            try writer.print("{s}: {s}\n", .{ issue.path, issue.message });
        }
    }
    return out.toOwnedSlice(allocator);
}

pub fn attachLocations(source: []const u8, issues: []ValidationIssue) void {
    for (issues) |*issue| {
        issue.line = locatePathLine(source, issue.path);
    }
}

fn validateProviderSection(
    allocator: std.mem.Allocator,
    issues: *std.ArrayList(ValidationIssue),
    prefix: []const u8,
    items: []const config.ProviderConfig,
) !void {
    for (items, 0..) |item, i| {
        const path = try std.fmt.allocPrint(allocator, "{s}[{d}]", .{ prefix, i });
        defer allocator.free(path);
        try validateProviderConfig(allocator, issues, path, item);
    }
}

fn validateProviderConfig(
    allocator: std.mem.Allocator,
    issues: *std.ArrayList(ValidationIssue),
    path: []const u8,
    item: config.ProviderConfig,
) !void {
    const provider_meta = findProviderMeta(item.provider);
    if (provider_meta == null) {
        try appendIssue(allocator, issues, path, "unknown provider");
        return;
    }

    for (item.settings) |setting| {
        const field_meta = findFieldMeta(provider_meta.?.settings, setting.key);
        if (field_meta == null) {
            const issue_path = try std.fmt.allocPrint(allocator, "{s}.settings.{s}", .{ path, setting.key });
            defer allocator.free(issue_path);
            try appendIssue(allocator, issues, issue_path, "unknown setting");
            continue;
        }
        const issue_path = try std.fmt.allocPrint(allocator, "{s}.settings.{s}", .{ path, setting.key });
        defer allocator.free(issue_path);
        try validateSettingValue(allocator, issues, issue_path, field_meta.?, setting.value);
    }

    if (item.format) |format| {
        const format_path = try std.fmt.allocPrint(allocator, "{s}.format", .{path});
        defer allocator.free(format_path);
        try validateProviderFormat(allocator, issues, format_path, provider_meta.?, format);
    }
}

fn validateProviderDefaults(
    allocator: std.mem.Allocator,
    issues: *std.ArrayList(ValidationIssue),
    defaults: config.ProviderDefaults,
) !void {
    for (defaults.entries.items) |entry| {
        const provider_meta = findProviderMeta(entry.provider);
        const provider_path = try std.fmt.allocPrint(allocator, "providers.{s}", .{entry.provider});
        defer allocator.free(provider_path);
        if (provider_meta == null) {
            try appendIssue(allocator, issues, provider_path, "unknown provider defaults block");
            continue;
        }
        for (entry.settings) |setting| {
            const field_meta = findFieldMeta(provider_meta.?.settings, setting.key);
            const issue_path = try std.fmt.allocPrint(allocator, "providers.{s}.{s}", .{ entry.provider, setting.key });
            defer allocator.free(issue_path);
            if (field_meta == null) {
                try appendIssue(allocator, issues, issue_path, "unknown setting");
                continue;
            }
            try validateSettingValue(allocator, issues, issue_path, field_meta.?, setting.value);
        }
    }
}

fn validateSettingValue(
    allocator: std.mem.Allocator,
    issues: *std.ArrayList(ValidationIssue),
    path: []const u8,
    field: meta.FieldMeta,
    value: []const u8,
) !void {
    if (field.enum_values.len > 0 and !matchesEnum(field.enum_values, value)) {
        try appendIssue(allocator, issues, path, "value not in allowed enum set");
        return;
    }

    switch (field.kind) {
        .boolean => {
            if (!std.mem.eql(u8, value, "true") and !std.mem.eql(u8, value, "false")) {
                try appendIssue(allocator, issues, path, "expected boolean");
            }
        },
        .integer => {
            const parsed = std.fmt.parseInt(i64, value, 10) catch {
                try appendIssue(allocator, issues, path, "expected integer");
                return;
            };
            if (field.min_int) |min| {
                if (parsed < min) try appendIssue(allocator, issues, path, "value below minimum");
            }
            if (field.max_int) |max| {
                if (parsed > max) try appendIssue(allocator, issues, path, "value above maximum");
            }
        },
        .number => {
            const parsed = std.fmt.parseFloat(f64, value) catch {
                try appendIssue(allocator, issues, path, "expected number");
                return;
            };
            if (field.min_number) |min| {
                if (parsed < min) try appendIssue(allocator, issues, path, "value below minimum");
            }
            if (field.max_number) |max| {
                if (parsed > max) try appendIssue(allocator, issues, path, "value above maximum");
            }
        },
        .string => {},
    }
}

fn validateIntField(
    allocator: std.mem.Allocator,
    issues: *std.ArrayList(ValidationIssue),
    path: []const u8,
    fields: []const meta.FieldMeta,
    field_name: []const u8,
    value: anytype,
) !void {
    const field = findFieldMeta(fields, field_name) orelse return;
    const raw = try std.fmt.allocPrint(allocator, "{d}", .{value});
    defer allocator.free(raw);
    try validateSettingValue(allocator, issues, path, field, raw);
}

fn validateEnumField(
    allocator: std.mem.Allocator,
    issues: *std.ArrayList(ValidationIssue),
    path: []const u8,
    fields: []const meta.FieldMeta,
    field_name: []const u8,
    value: []const u8,
) !void {
    const field = findFieldMeta(fields, field_name) orelse return;
    try validateSettingValue(allocator, issues, path, field, value);
}

fn validateProviderFormat(
    allocator: std.mem.Allocator,
    issues: *std.ArrayList(ValidationIssue),
    path: []const u8,
    provider: meta.ProviderMeta,
    format: []const u8,
) !void {
    var cursor: usize = 0;
    while (cursor < format.len) {
        const start = std.mem.indexOfScalarPos(u8, format, cursor, '{') orelse break;
        const end = std.mem.indexOfScalarPos(u8, format, start + 1, '}') orelse {
            try appendIssue(allocator, issues, path, "unterminated format placeholder");
            return;
        };
        const placeholder = parsePlaceholder(format[start + 1 .. end]);
        try validatePlaceholder(allocator, issues, path, provider, placeholder);
        cursor = end + 1;
    }
}

const Placeholder = struct {
    key: []const u8,
    format_spec: ?[]const u8 = null,
    transform: ?[]const u8 = null,
};

const TransformKind = enum {
    none,
    upper,
    lower,
    trim,
    default_value,
    yesno,
    onoff,
    unknown,
};

fn validatePlaceholder(
    allocator: std.mem.Allocator,
    issues: *std.ArrayList(ValidationIssue),
    path: []const u8,
    provider: meta.ProviderMeta,
    placeholder: Placeholder,
) !void {
    const field = findFieldMeta(provider.output_fields, placeholder.key) orelse {
        try appendIssue(allocator, issues, path, "format uses unknown provider field");
        return;
    };

    if (placeholder.format_spec) |format_spec| {
        if (!supportsFormatSpec(field.kind, format_spec)) {
            try appendIssue(allocator, issues, path, "format placeholder uses unsupported numeric format");
        }
    }

    switch (classifyTransform(placeholder.transform)) {
        .none => {},
        .upper, .lower, .trim, .default_value => {},
        .yesno, .onoff => {
            if (field.kind != .boolean) {
                try appendIssue(allocator, issues, path, "boolean transform used on non-boolean field");
            }
        },
        .unknown => try appendIssue(allocator, issues, path, "unknown format transform"),
    }
}

fn parsePlaceholder(raw_key: []const u8) Placeholder {
    var key_end = raw_key.len;
    var format_spec: ?[]const u8 = null;
    var transform: ?[]const u8 = null;

    if (std.mem.indexOfScalar(u8, raw_key, ':')) |idx| {
        key_end = @min(key_end, idx);
        const rest = raw_key[idx + 1 ..];
        if (std.mem.indexOfScalar(u8, rest, '|')) |pipe_idx| {
            format_spec = rest[0..pipe_idx];
            transform = rest[pipe_idx + 1 ..];
        } else {
            format_spec = rest;
        }
    }

    if (std.mem.indexOfScalar(u8, raw_key, '|')) |idx| {
        key_end = @min(key_end, idx);
        if (format_spec == null) transform = raw_key[idx + 1 ..];
    }

    return .{
        .key = raw_key[0..key_end],
        .format_spec = nonEmpty(format_spec),
        .transform = nonEmpty(transform),
    };
}

fn classifyTransform(transform: ?[]const u8) TransformKind {
    const name = transform orelse return .none;
    if (std.mem.eql(u8, name, "upper")) return .upper;
    if (std.mem.eql(u8, name, "lower")) return .lower;
    if (std.mem.eql(u8, name, "trim")) return .trim;
    if (std.mem.eql(u8, name, "yesno")) return .yesno;
    if (std.mem.eql(u8, name, "onoff")) return .onoff;
    if (std.mem.startsWith(u8, name, "default(") and std.mem.endsWith(u8, name, ")")) return .default_value;
    return .unknown;
}

fn nonEmpty(value: ?[]const u8) ?[]const u8 {
    const slice = value orelse return null;
    if (slice.len == 0) return null;
    return slice;
}

fn supportsFormatSpec(kind: meta.ScalarKind, format_spec: []const u8) bool {
    if (kind != .integer and kind != .number) return false;
    if (format_spec.len < 2 or format_spec[0] != '.') return false;
    _ = std.fmt.parseInt(usize, format_spec[1..], 10) catch return false;
    return true;
}

fn appendIssue(
    allocator: std.mem.Allocator,
    issues: *std.ArrayList(ValidationIssue),
    path: []const u8,
    message: []const u8,
) !void {
    try issues.append(allocator, .{
        .path = try allocator.dupe(u8, path),
        .message = try allocator.dupe(u8, message),
    });
}

fn findProviderMeta(id: []const u8) ?meta.ProviderMeta {
    for (meta.providers) |provider| {
        if (std.mem.eql(u8, provider.id, id)) return provider;
    }
    return null;
}

fn findFieldMeta(fields: []const meta.FieldMeta, name: []const u8) ?meta.FieldMeta {
    for (fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return field;
    }
    return null;
}

fn matchesEnum(values: []const []const u8, value: []const u8) bool {
    for (values) |allowed| {
        if (std.mem.eql(u8, allowed, value)) return true;
    }
    return false;
}

fn locatePathLine(source: []const u8, path: []const u8) ?usize {
    if (std.mem.startsWith(u8, path, "providers.")) {
        return locateProvidersPath(source, path["providers.".len..]);
    }
    if (std.mem.startsWith(u8, path, "bar.")) {
        return locateBarPath(source, path["bar.".len..]);
    }
    return null;
}

fn locateProvidersPath(source: []const u8, suffix: []const u8) ?usize {
    var parts = std.mem.splitScalar(u8, suffix, '.');
    const provider = parts.next() orelse return null;
    const setting = parts.next();

    const provider_line = findLineContaining(source, provider) orelse return null;
    if (setting) |field| {
        return findLineContainingAfter(source, provider_line, field) orelse provider_line;
    }
    return provider_line;
}

fn locateBarPath(source: []const u8, suffix: []const u8) ?usize {
    var parts = std.mem.splitScalar(u8, suffix, '.');
    const section_and_index = parts.next() orelse return null;
    const section_name = trimIndex(section_and_index);
    const setting = parts.next();
    const maybe_field = parts.next();

    const section_line = findLineContaining(source, sectionNameToLuaKey(section_name)) orelse return null;
    if (setting) |name| {
        return findLineContainingAfter(source, section_line, name) orelse
            if (maybe_field) |field|
                findLineContainingAfter(source, section_line, field)
            else
                section_line;
    }
    return section_line;
}

test "theme parser bindings stay aligned with theme metadata" {
    try std.testing.expectEqual(meta.bar_theme_fields.len, theme_field_bindings.len);
    inline for (meta.bar_theme_fields, 0..) |field, i| {
        try std.testing.expectEqualStrings(field.name, theme_field_bindings[i].name);
    }
}

test "bar visual parser bindings stay aligned with visual metadata" {
    try std.testing.expectEqual(meta.bar_visual_fields.len, bar_visual_field_bindings.len);
    inline for (meta.bar_visual_fields, 0..) |field, i| {
        try std.testing.expectEqualStrings(field.name, bar_visual_field_bindings[i].name);
    }
}

fn sectionNameToLuaKey(name: []const u8) []const u8 {
    return if (std.mem.eql(u8, name, "left")) "left" else if (std.mem.eql(u8, name, "center")) "center" else if (std.mem.eql(u8, name, "right")) "right" else name;
}

fn trimIndex(section_and_index: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, section_and_index, '[')) |idx| return section_and_index[0..idx];
    return section_and_index;
}

fn findLineContaining(source: []const u8, needle: []const u8) ?usize {
    return findLineContainingAfter(source, 1, needle);
}

fn findLineContainingAfter(source: []const u8, line_start: usize, needle: []const u8) ?usize {
    var line_no: usize = 1;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| : (line_no += 1) {
        if (line_no < line_start) continue;
        if (std.mem.indexOf(u8, line, needle) != null) return line_no;
    }
    return null;
}

test "validator catches enum and range errors" {
    var cfg = config.defaultConfig();
    defer cfg.deinit(std.heap.page_allocator);

    cfg.provider_defaults.deinit(std.heap.page_allocator);
    cfg.provider_defaults = .{};
    try cfg.provider_defaults.entries.append(std.heap.page_allocator, .{
        .provider = try std.heap.page_allocator.dupe(u8, "memory"),
        .settings = try std.heap.page_allocator.dupe(config.Setting, &.{
            .{
                .key = try std.heap.page_allocator.dupe(u8, "unit"),
                .value = try std.heap.page_allocator.dupe(u8, "bytes"),
            },
            .{
                .key = try std.heap.page_allocator.dupe(u8, "used_gib"),
                .value = try std.heap.page_allocator.dupe(u8, "-1"),
            },
        }),
    });

    const issues = try validateConfig(std.testing.allocator, cfg);
    defer {
        for (issues) |issue| issue.deinit(std.testing.allocator);
        std.testing.allocator.free(issues);
    }
    try std.testing.expect(issues.len >= 2);
}

test "validator catches bad provider format placeholders" {
    var cfg = config.defaultConfig();
    defer cfg.deinit(std.heap.page_allocator);

    if (cfg.bar.right.len > 1) {
        if (cfg.bar.right[1].format) |old| std.heap.page_allocator.free(old);
        cfg.bar.right[1].format = try std.heap.page_allocator.dupe(u8, "mem {bogus} {used_gib|wat} {used_gib:x}");
    }

    const issues = try validateConfig(std.testing.allocator, cfg);
    defer {
        for (issues) |issue| issue.deinit(std.testing.allocator);
        std.testing.allocator.free(issues);
    }
    try std.testing.expect(issues.len >= 3);
}
