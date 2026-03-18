const std = @import("std");
const config = @import("../config/mod.zig");
const meta = @import("../config/meta.zig");
const types = @import("types.zig");

pub const Placeholder = struct {
    key: []const u8,
    format_spec: ?[]const u8 = null,
    transform: ?[]const u8 = null,
};

pub const TransformKind = enum {
    none,
    upper,
    lower,
    trim,
    default_value,
    yesno,
    onoff,
    unknown,
};

pub fn formatProviderOutput(
    allocator: std.mem.Allocator,
    provider_name: []const u8,
    instance: config.ProviderConfig,
    fallback_text: ?[]const u8,
    fields: []const types.Field,
) ![]u8 {
    if (instance.format) |format| return renderTemplate(allocator, format, fields);
    const presentation = meta.presentationMeta(provider_name);
    return switch (presentation.style) {
        .template => renderTemplate(allocator, defaultTemplate(presentation, fields), fields),
        .passthrough_text => allocator.dupe(u8, fallback_text orelse ""),
    };
}

pub fn defaultClockSourceFormat(instance: config.ProviderConfig) []const u8 {
    if (instance.format) |format| {
        if (std.mem.indexOfScalar(u8, format, '%') != null) return format;
    }
    return meta.presentationMeta("clock").source_format;
}

pub fn presentWindowTitle(
    allocator: std.mem.Allocator,
    instance: config.ProviderConfig,
    raw_title: []const u8,
) ![]u8 {
    const presentation = meta.presentationMeta(instance.provider);
    if (!shouldTruncate(presentation, instance) or instance.max_width == 0 or raw_title.len <= instance.max_width) {
        return allocator.dupe(u8, raw_title);
    }
    return truncateText(allocator, raw_title, instance.max_width);
}

fn renderTemplate(allocator: std.mem.Allocator, template: []const u8, fields: []const types.Field) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var i: usize = 0;
    while (i < template.len) {
        if (template[i] == '{') {
            if (std.mem.indexOfScalarPos(u8, template, i + 1, '}')) |end| {
                const raw_key = template[i + 1 .. end];
                const placeholder = parsePlaceholder(raw_key);
                if (findField(fields, placeholder.key)) |field| {
                    const value = try renderFieldValue(allocator, field, placeholder);
                    defer allocator.free(value);
                    try out.appendSlice(allocator, value);
                } else {
                    try out.appendSlice(allocator, template[i .. end + 1]);
                }
                i = end + 1;
                continue;
            }
        }
        try out.append(allocator, template[i]);
        i += 1;
    }
    return out.toOwnedSlice(allocator);
}

fn findField(fields: []const types.Field, key: []const u8) ?types.Field {
    for (fields) |field| {
        if (std.mem.eql(u8, field.key, key)) return field;
    }
    return null;
}

pub fn parsePlaceholder(raw_key: []const u8) Placeholder {
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

pub fn classifyTransform(transform: ?[]const u8) TransformKind {
    const name = transform orelse return .none;
    if (std.mem.eql(u8, name, "upper")) return .upper;
    if (std.mem.eql(u8, name, "lower")) return .lower;
    if (std.mem.eql(u8, name, "trim")) return .trim;
    if (std.mem.eql(u8, name, "yesno")) return .yesno;
    if (std.mem.eql(u8, name, "onoff")) return .onoff;
    if (std.mem.startsWith(u8, name, "default(") and std.mem.endsWith(u8, name, ")")) return .default_value;
    return .unknown;
}

fn renderFieldValue(allocator: std.mem.Allocator, field: types.Field, placeholder: Placeholder) ![]u8 {
    const base_value = switch (field.scalar) {
        .none => allocator.dupe(u8, field.value),
        .string => allocator.dupe(u8, field.value),
        .boolean => |value| renderBoolean(allocator, value, field.value, placeholder.transform),
        .integer => |value| renderInteger(allocator, value, field.value, placeholder.format_spec),
        .number => |value| renderNumber(allocator, value, field.value, placeholder.format_spec),
    };
    const value = try base_value;
    errdefer allocator.free(value);
    return applyTransform(allocator, value, placeholder.transform);
}

fn renderInteger(allocator: std.mem.Allocator, value: i64, fallback: []const u8, format_spec: ?[]const u8) ![]u8 {
    if (parsePrecision(format_spec)) |precision| {
        if (precision == 0) return std.fmt.allocPrint(allocator, "{d}", .{value});
        return zeroPadInteger(allocator, value, precision);
    }
    _ = fallback;
    return std.fmt.allocPrint(allocator, "{d}", .{value});
}

fn renderNumber(allocator: std.mem.Allocator, value: f64, fallback: []const u8, format_spec: ?[]const u8) ![]u8 {
    const precision = parsePrecision(format_spec) orelse return allocator.dupe(u8, fallback);
    return renderNumberWithPrecision(allocator, value, precision);
}

fn parsePrecision(format_spec: ?[]const u8) ?usize {
    const spec = format_spec orelse return null;
    if (spec.len < 2 or spec[0] != '.') return null;
    return std.fmt.parseInt(usize, spec[1..], 10) catch null;
}

fn renderBoolean(
    allocator: std.mem.Allocator,
    value: bool,
    fallback: []const u8,
    transform: ?[]const u8,
) ![]u8 {
    const transform_name = transform orelse return allocator.dupe(u8, fallback);
    if (std.mem.eql(u8, transform_name, "yesno")) {
        return allocator.dupe(u8, if (value) "yes" else "no");
    }
    if (std.mem.eql(u8, transform_name, "onoff")) {
        return allocator.dupe(u8, if (value) "on" else "off");
    }
    return allocator.dupe(u8, fallback);
}

fn applyTransform(allocator: std.mem.Allocator, value: []const u8, transform: ?[]const u8) ![]u8 {
    const transform_name = transform orelse return allocator.dupe(u8, value);
    return switch (classifyTransform(transform_name)) {
        .none => allocator.dupe(u8, value),
        .upper => asciiCase(allocator, value, .upper),
        .lower => asciiCase(allocator, value, .lower),
        .trim => allocator.dupe(u8, std.mem.trim(u8, value, &std.ascii.whitespace)),
        .default_value => if (value.len == 0) allocator.dupe(u8, transform_name["default(".len .. transform_name.len - 1]) else allocator.dupe(u8, value),
        .yesno, .onoff, .unknown => allocator.dupe(u8, value),
    };
}

const AsciiCase = enum { upper, lower };

fn asciiCase(allocator: std.mem.Allocator, value: []const u8, mode: AsciiCase) ![]u8 {
    const out = try allocator.dupe(u8, value);
    for (out) |*char| {
        char.* = switch (mode) {
            .upper => std.ascii.toUpper(char.*),
            .lower => std.ascii.toLower(char.*),
        };
    }
    return out;
}

fn zeroPadInteger(allocator: std.mem.Allocator, value: i64, width: usize) ![]u8 {
    const negative = value < 0;
    const magnitude: u64 = @intCast(if (negative) -value else value);
    const digits = try std.fmt.allocPrint(allocator, "{d}", .{magnitude});
    defer allocator.free(digits);

    if (digits.len >= width) {
        if (!negative) return allocator.dupe(u8, digits);
        return std.fmt.allocPrint(allocator, "-{s}", .{digits});
    }

    const zeros = width - digits.len;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    if (negative) try out.append(allocator, '-');
    try out.appendNTimes(allocator, '0', zeros);
    try out.appendSlice(allocator, digits);
    return out.toOwnedSlice(allocator);
}

fn renderNumberWithPrecision(allocator: std.mem.Allocator, value: f64, precision: usize) ![]u8 {
    const negative = value < 0;
    const abs_value = @abs(value);

    var scale: u64 = 1;
    var i: usize = 0;
    while (i < precision) : (i += 1) scale *= 10;

    const scaled = @as(u64, @intFromFloat(@round(abs_value * @as(f64, @floatFromInt(scale)))));
    const int_part = if (scale == 0) scaled else scaled / scale;
    const frac_part = if (scale == 0) 0 else scaled % scale;

    if (precision == 0) {
        return std.fmt.allocPrint(allocator, "{s}{d}", .{ if (negative) "-" else "", int_part });
    }

    const frac_digits = try std.fmt.allocPrint(allocator, "{d}", .{frac_part});
    defer allocator.free(frac_digits);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    if (negative) try out.append(allocator, '-');
    try out.writer(allocator).print("{d}.", .{int_part});
    if (frac_digits.len < precision) {
        try out.appendNTimes(allocator, '0', precision - frac_digits.len);
    }
    try out.appendSlice(allocator, frac_digits);
    return out.toOwnedSlice(allocator);
}

fn nonEmpty(value: ?[]const u8) ?[]const u8 {
    const slice = value orelse return null;
    if (slice.len == 0) return null;
    return slice;
}

fn setting(items: []const config.Setting, key: []const u8) ?bool {
    for (items) |item| {
        if (!std.mem.eql(u8, item.key, key)) continue;
        if (std.mem.eql(u8, item.value, "true")) return true;
        if (std.mem.eql(u8, item.value, "false")) return false;
    }
    return null;
}

fn truncateText(allocator: std.mem.Allocator, text: []const u8, max_width: u16) ![]u8 {
    if (max_width == 0 or text.len <= max_width) return allocator.dupe(u8, text);
    if (max_width <= 1) return allocator.dupe(u8, text[0..1]);
    if (max_width <= 3) return allocator.dupe(u8, text[0..max_width]);
    return std.fmt.allocPrint(allocator, "{s}...", .{text[0 .. max_width - 3]});
}

pub fn defaultTemplate(presentation: meta.PresentationMeta, fields: []const types.Field) []const u8 {
    if (presentation.unit_field) |unit_field| {
        if (fieldValue(fields, unit_field)) |unit| {
            if (std.mem.eql(u8, unit, "mib") and presentation.unit_template_mib.len > 0) {
                return presentation.unit_template_mib;
            }
            if (std.mem.eql(u8, unit, "gib") and presentation.unit_template_gib.len > 0) {
                return presentation.unit_template_gib;
            }
        }
    }
    if (presentation.default_template.len > 0) return presentation.default_template;
    return "{value}";
}

fn fieldValue(fields: []const types.Field, key: []const u8) ?[]const u8 {
    for (fields) |field| {
        if (std.mem.eql(u8, field.key, key)) return field.value;
    }
    return null;
}

fn shouldTruncate(presentation: meta.PresentationMeta, instance: config.ProviderConfig) bool {
    if (!presentation.supports_truncation) return false;
    if (presentation.truncation_setting_key) |key| {
        return setting(instance.settings, key) orelse true;
    }
    return true;
}

test "formatter renders placeholders" {
    const fields = [_]types.Field{
        .{ .key = "usage", .value = "42", .scalar = .{ .integer = 42 } },
    };
    const instance = config.ProviderConfig{
        .provider = @constCast("cpu"),
        .format = @constCast("cpu {usage}%"),
    };
    const out = try formatProviderOutput(std.testing.allocator, "cpu", instance, null, &fields);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("cpu 42%", out);
}

test "formatter can passthrough raw text" {
    const fields = [_]types.Field{
        .{ .key = "title", .value = "Zide", .scalar = .{ .string = "Zide" } },
    };
    const instance = config.ProviderConfig{
        .provider = @constCast("window"),
    };
    const out = try formatProviderOutput(std.testing.allocator, "window", instance, "Zide", &fields);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("Zide", out);
}

test "formatter picks memory default by unit" {
    const fields = [_]types.Field{
        .{ .key = "used_gib", .value = "1.5", .scalar = .{ .number = 1.5 } },
        .{ .key = "used_mib", .value = "1536", .scalar = .{ .integer = 1536 } },
        .{ .key = "unit", .value = "mib", .scalar = .{ .string = "mib" } },
    };
    const instance = config.ProviderConfig{
        .provider = @constCast("memory"),
    };
    const out = try formatProviderOutput(std.testing.allocator, "memory", instance, null, &fields);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("mem 1536M", out);
}

test "formatter respects numeric precision placeholders from typed fields" {
    const fields = [_]types.Field{
        .{ .key = "used_gib", .value = "1.54", .scalar = .{ .number = 1.54 } },
    };
    const instance = config.ProviderConfig{
        .provider = @constCast("memory"),
        .format = @constCast("mem {used_gib:.1}G"),
    };
    const out = try formatProviderOutput(std.testing.allocator, "memory", instance, null, &fields);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("mem 1.5G", out);
}

test "formatter supports uppercase string transform" {
    const fields = [_]types.Field{
        .{ .key = "compositor", .value = "hyprland", .scalar = .{ .string = "hyprland" } },
    };
    const instance = config.ProviderConfig{
        .provider = @constCast("mode"),
        .format = @constCast("{compositor|upper}"),
    };
    const out = try formatProviderOutput(std.testing.allocator, "mode", instance, null, &fields);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("HYPRLAND", out);
}

test "formatter supports zero-padded integers" {
    const fields = [_]types.Field{
        .{ .key = "workspace", .value = "7", .scalar = .{ .integer = 7 } },
    };
    const instance = config.ProviderConfig{
        .provider = @constCast("workspaces"),
        .format = @constCast("ws {workspace:.2}"),
    };
    const out = try formatProviderOutput(std.testing.allocator, "workspaces", instance, null, &fields);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("ws 07", out);
}

test "formatter supports boolean transforms" {
    const fields = [_]types.Field{
        .{ .key = "visible", .value = "true", .scalar = .{ .boolean = true } },
    };
    const instance = config.ProviderConfig{
        .provider = @constCast("workspaces"),
        .format = @constCast("{visible|yesno}"),
    };
    const out = try formatProviderOutput(std.testing.allocator, "workspaces", instance, null, &fields);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("yes", out);
}

test "presentWindowTitle truncates by formatter policy" {
    const title = "A very long window title";
    const instance = config.ProviderConfig{
        .provider = @constCast("window"),
        .max_width = 8,
        .settings = &.{},
    };
    const out = try presentWindowTitle(std.testing.allocator, instance, title);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("A ver...", out);
}

test "presentWindowTitle respects metadata-backed truncate setting" {
    const title = "A very long window title";
    const instance = config.ProviderConfig{
        .provider = @constCast("window"),
        .max_width = 8,
        .settings = &.{
            .{ .key = @constCast("truncate"), .value = @constCast("false") },
        },
    };
    const out = try presentWindowTitle(std.testing.allocator, instance, title);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(title, out);
}
