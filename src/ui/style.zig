const std = @import("std");
const bar = @import("../bar/mod.zig");
const modules = @import("../modules/mod.zig");

pub const AppearanceKind = enum {
    normal,
    accent,
    subtle,
    warning,
};

pub const Rgba = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

pub const Palette = struct {
    background: Rgba,
    foreground: Rgba,
    segment_background: Rgba,
    accent_background: Rgba,
    subtle_background: Rgba,
    warning_background: Rgba,
    accent_foreground: Rgba,
};

pub const Appearance = struct {
    kind: AppearanceKind = .normal,

    pub fn default() Appearance {
        return .{};
    }
};

pub const ResolvedAppearance = struct {
    kind: AppearanceKind,
    background: Rgba,
    foreground: Rgba,
    decoration: Decoration,
};

pub const Decoration = struct {
    corner_radius: f32,
    border_width: f32,
    border_color: Rgba,
};

pub fn styleForSegment(segment: modules.Segment) Appearance {
    if (std.mem.eql(u8, segment.provider, "workspaces")) return .{ .kind = .accent };
    if (std.mem.eql(u8, segment.provider, "window")) return .{ .kind = .subtle };
    if (std.mem.eql(u8, segment.provider, "cpu")) {
        return switch (segment.payload) {
            .integer => |value| if (value >= 80) .{ .kind = .warning } else .{},
            else => .{},
        };
    }
    if (std.mem.eql(u8, segment.provider, "memory")) {
        return switch (segment.payload) {
            .number => |value| if (value >= 12.0) .{ .kind = .warning } else .{},
            else => .{},
        };
    }
    return .{};
}

pub fn appearanceColors(appearance: Appearance, palette: Palette) struct { background: Rgba, foreground: Rgba } {
    return switch (appearance.kind) {
        .normal => .{ .background = palette.segment_background, .foreground = palette.foreground },
        .accent => .{ .background = palette.accent_background, .foreground = palette.accent_foreground },
        .subtle => .{ .background = palette.subtle_background, .foreground = palette.foreground },
        .warning => .{ .background = palette.warning_background, .foreground = palette.accent_foreground },
    };
}

pub fn resolveAppearance(appearance: Appearance, palette: Palette, runtime_bar: bar.Bar) ResolvedAppearance {
    const colors = appearanceColors(appearance, palette);
    return .{
        .kind = appearance.kind,
        .background = colors.background,
        .foreground = colors.foreground,
        .decoration = decorationForAppearance(appearance, colors.background, runtime_bar),
    };
}

pub fn decorationForAppearance(appearance: Appearance, background: Rgba, runtime_bar: bar.Bar) Decoration {
    const base_radius = @as(f32, @floatFromInt(runtime_bar.segment_radius_px));
    const base_border_width = @as(f32, @floatFromInt(runtime_bar.segment_border_px));
    const base_border_alpha = runtime_bar.segment_border_alpha;

    return switch (appearance.kind) {
        .normal => .{
            .corner_radius = base_radius,
            .border_width = base_border_width,
            .border_color = tintColor(background, 0.18, base_border_alpha),
        },
        .accent => .{
            .corner_radius = base_radius + 2,
            .border_width = base_border_width + (if (base_border_width > 0) @as(f32, 0.5) else @as(f32, 0.0)),
            .border_color = tintColor(background, 0.26, saturatingAdd(base_border_alpha, 32)),
        },
        .subtle => .{
            .corner_radius = @max(base_radius - 1, 0),
            .border_width = base_border_width,
            .border_color = tintColor(background, 0.12, scaleAlpha(base_border_alpha, 0.75)),
        },
        .warning => .{
            .corner_radius = base_radius + 1,
            .border_width = base_border_width + (if (base_border_width > 0) @as(f32, 0.5) else @as(f32, 0.0)),
            .border_color = tintColor(background, 0.30, saturatingAdd(base_border_alpha, 48)),
        },
    };
}

pub fn paletteFromBar(runtime_bar: bar.Bar) Palette {
    const bg = parseColor(runtime_bar.background) orelse Rgba{ .r = 17, .g = 22, .b = 28, .a = 255 };
    const fg = parseColor(runtime_bar.foreground) orelse Rgba{ .r = 215, .g = 222, .b = 231, .a = 255 };
    return .{
        .background = bg,
        .foreground = fg,
        .segment_background = parseColor(runtime_bar.segment_background) orelse mix(bg, fg, 0.12, 220),
        .accent_background = parseColor(runtime_bar.accent_background) orelse Rgba{ .r = 39, .g = 91, .b = 122, .a = 235 },
        .subtle_background = parseColor(runtime_bar.subtle_background) orelse mix(bg, fg, 0.06, 190),
        .warning_background = parseColor(runtime_bar.warning_background) orelse Rgba{ .r = 122, .g = 70, .b = 39, .a = 235 },
        .accent_foreground = parseColor(runtime_bar.accent_foreground) orelse Rgba{ .r = 239, .g = 245, .b = 250, .a = 255 },
    };
}

pub fn parseColor(input: []const u8) ?Rgba {
    if (input.len != 7 or input[0] != '#') return null;
    const r = std.fmt.parseInt(u8, input[1..3], 16) catch return null;
    const g = std.fmt.parseInt(u8, input[3..5], 16) catch return null;
    const b = std.fmt.parseInt(u8, input[5..7], 16) catch return null;
    return .{ .r = r, .g = g, .b = b };
}

fn mix(base: Rgba, other: Rgba, factor: f32, alpha: u8) Rgba {
    const clamped = std.math.clamp(factor, 0, 1);
    return .{
        .r = mixChannel(base.r, other.r, clamped),
        .g = mixChannel(base.g, other.g, clamped),
        .b = mixChannel(base.b, other.b, clamped),
        .a = alpha,
    };
}

pub fn tintColor(color: Rgba, amount: f32, alpha: u8) Rgba {
    return .{
        .r = tintChannel(color.r, amount),
        .g = tintChannel(color.g, amount),
        .b = tintChannel(color.b, amount),
        .a = alpha,
    };
}

fn tintChannel(channel: u8, amount: f32) u8 {
    const base: f32 = @floatFromInt(channel);
    const delta = if (amount >= 0) (255.0 - base) * amount else base * amount;
    return @intFromFloat(std.math.clamp(base + delta, 0, 255));
}

fn scaleAlpha(alpha: u8, factor: f32) u8 {
    const scaled = @as(f32, @floatFromInt(alpha)) * factor;
    return @intFromFloat(std.math.clamp(scaled, 0, 255));
}

fn saturatingAdd(value: u8, amount: u8) u8 {
    return value +| amount;
}

fn mixChannel(a: u8, b: u8, factor: f32) u8 {
    const lhs: f32 = @floatFromInt(a);
    const rhs: f32 = @floatFromInt(b);
    return @intFromFloat(lhs + ((rhs - lhs) * factor));
}

test "styleForSegment marks workspaces as accent" {
    const segment = modules.Segment{ .provider = "workspaces", .text = "ws" };
    try std.testing.expectEqual(AppearanceKind.accent, styleForSegment(segment).kind);
}

test "styleForSegment marks hot cpu as warning" {
    const segment = modules.Segment{
        .provider = "cpu",
        .text = "cpu 91%",
        .payload = .{ .integer = 91 },
    };
    try std.testing.expectEqual(AppearanceKind.warning, styleForSegment(segment).kind);
}

test "paletteFromBar applies configured accent and derived segment colors" {
    const runtime_bar = bar.Bar{
        .height_px = 28,
        .section_gap_px = 12,
        .background = "#11161c",
        .foreground = "#d7dee7",
        .segment_background = "",
        .accent_background = "#275b7a",
        .subtle_background = "",
        .warning_background = "",
        .accent_foreground = "#eff5fa",
        .font_path = "",
        .font_fallback_path = "",
        .font_fallback_path_2 = "",
        .preview_width_px = 1280,
        .anchor = .top,
        .horizontal_padding_px = 18,
        .segment_padding_x_px = 10,
        .segment_padding_y_px = 6,
        .font_points = 15,
        .segment_radius_px = 6,
        .edge_line_px = 1,
        .edge_shadow_alpha = 235,
        .segment_border_px = 1,
        .segment_border_alpha = 150,
    };
    const palette = paletteFromBar(runtime_bar);
    try std.testing.expectEqual(@as(u8, 39), palette.accent_background.r);
    try std.testing.expectEqual(@as(u8, 42), palette.segment_background.r);
}

test "resolveAppearance derives stronger accent decoration" {
    const runtime_bar = bar.Bar{
        .height_px = 28,
        .section_gap_px = 12,
        .background = "#11161c",
        .foreground = "#d7dee7",
        .segment_background = "",
        .accent_background = "",
        .subtle_background = "",
        .warning_background = "",
        .accent_foreground = "",
        .font_path = "",
        .font_fallback_path = "",
        .font_fallback_path_2 = "",
        .preview_width_px = 1280,
        .anchor = .top,
        .horizontal_padding_px = 18,
        .segment_padding_x_px = 10,
        .segment_padding_y_px = 6,
        .font_points = 15,
        .segment_radius_px = 6,
        .edge_line_px = 1,
        .edge_shadow_alpha = 235,
        .segment_border_px = 1,
        .segment_border_alpha = 150,
    };
    const palette = paletteFromBar(runtime_bar);
    const accent = resolveAppearance(.{ .kind = .accent }, palette, runtime_bar);
    const subtle = resolveAppearance(.{ .kind = .subtle }, palette, runtime_bar);
    try std.testing.expect(accent.decoration.corner_radius > subtle.decoration.corner_radius);
    try std.testing.expect(accent.decoration.border_color.a > subtle.decoration.border_color.a);
}
