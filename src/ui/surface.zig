const std = @import("std");
const bar = @import("../bar/mod.zig");
const config = @import("../config/mod.zig");

pub const WidthPolicy = union(enum) {
    fixed: u16,
};

pub const HorizontalOrigin = enum {
    left,
    center,
    right,
};

pub const VerticalOrigin = enum {
    top,
    bottom,
};

pub const Placement = struct {
    horizontal: HorizontalOrigin,
    vertical: VerticalOrigin,
};

pub const SurfaceSpec = struct {
    title: []const u8,
    width: WidthPolicy,
    height_px: u16,
    anchor: config.ThemeConfig.Anchor,
    placement: Placement,
    always_on_top: bool,

    pub fn init(runtime_bar: bar.Bar) SurfaceSpec {
        return .{
            .title = "zbar preview",
            .width = .{ .fixed = @max(runtime_bar.preview_width_px, @as(u16, 320)) },
            .height_px = runtime_bar.height_px,
            .anchor = runtime_bar.anchor,
            .placement = placementForAnchor(runtime_bar.anchor),
            .always_on_top = anchoredAlwaysOnTop(runtime_bar.anchor),
        };
    }

    pub fn widthPx(self: SurfaceSpec) u16 {
        return switch (self.width) {
            .fixed => |value| value,
        };
    }
};

pub fn anchoredAlwaysOnTop(anchor: config.ThemeConfig.Anchor) bool {
    return switch (anchor) {
        .top, .top_left, .top_right => true,
        else => false,
    };
}

pub fn placementForAnchor(anchor: config.ThemeConfig.Anchor) Placement {
    return switch (anchor) {
        .top => .{ .horizontal = .center, .vertical = .top },
        .top_left => .{ .horizontal = .left, .vertical = .top },
        .top_right => .{ .horizontal = .right, .vertical = .top },
        .bottom => .{ .horizontal = .center, .vertical = .bottom },
        .bottom_left => .{ .horizontal = .left, .vertical = .bottom },
        .bottom_right => .{ .horizontal = .right, .vertical = .bottom },
    };
}

test "surface spec derives top preview policy from runtime bar" {
    const runtime_bar = bar.Bar{
        .height_px = 28,
        .section_gap_px = 12,
        .background = "",
        .foreground = "",
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
    };
    const spec = SurfaceSpec.init(runtime_bar);
    try std.testing.expectEqualStrings("zbar preview", spec.title);
    try std.testing.expectEqual(@as(u16, 1280), spec.widthPx());
    try std.testing.expectEqual(@as(u16, 28), spec.height_px);
    try std.testing.expectEqual(HorizontalOrigin.center, spec.placement.horizontal);
    try std.testing.expectEqual(VerticalOrigin.top, spec.placement.vertical);
    try std.testing.expect(spec.always_on_top);
}

test "surface spec clamps narrow preview widths" {
    const runtime_bar = bar.Bar{
        .height_px = 28,
        .section_gap_px = 12,
        .background = "",
        .foreground = "",
        .segment_background = "",
        .accent_background = "",
        .subtle_background = "",
        .warning_background = "",
        .accent_foreground = "",
        .font_path = "",
        .font_fallback_path = "",
        .font_fallback_path_2 = "",
        .preview_width_px = 100,
        .anchor = .bottom,
        .horizontal_padding_px = 18,
        .segment_padding_x_px = 10,
        .segment_padding_y_px = 6,
        .font_points = 15,
    };
    const spec = SurfaceSpec.init(runtime_bar);
    try std.testing.expectEqual(@as(u16, 320), spec.widthPx());
    try std.testing.expectEqual(HorizontalOrigin.center, spec.placement.horizontal);
    try std.testing.expectEqual(VerticalOrigin.bottom, spec.placement.vertical);
    try std.testing.expect(!spec.always_on_top);
}
