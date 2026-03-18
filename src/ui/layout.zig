const std = @import("std");
const bar = @import("../bar/mod.zig");
const modules = @import("../modules/mod.zig");
const style = @import("style.zig");

pub const Metrics = struct {
    horizontal_padding: f32,
    segment_gap: f32,
    segment_padding_x: f32,
    segment_padding_y: f32,
    text_height: f32,
};

pub const MeasuredSegment = struct {
    provider: []const u8,
    instance_name: ?[]const u8,
    text: []const u8,
    text_width: f32,
    text_height: f32,
    appearance: style.Appearance = style.Appearance.default(),
};

pub const SegmentBox = struct {
    provider: []const u8,
    instance_name: ?[]const u8,
    text: []const u8,
    appearance: style.ResolvedAppearance,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    text_x: f32,
    text_y: f32,
    text_width: f32,
    text_height: f32,
};

pub const LayoutFrame = struct {
    left: []SegmentBox,
    center: []SegmentBox,
    right: []SegmentBox,

    pub fn deinit(self: LayoutFrame, allocator: std.mem.Allocator) void {
        allocator.free(self.left);
        allocator.free(self.center);
        allocator.free(self.right);
    }
};

pub fn layoutFrame(
    allocator: std.mem.Allocator,
    runtime_bar: bar.Bar,
    palette: style.Palette,
    window_width: f32,
    window_height: f32,
    left: []const MeasuredSegment,
    center: []const MeasuredSegment,
    right: []const MeasuredSegment,
    metrics: Metrics,
) !LayoutFrame {
    const left_width = sectionWidth(left, metrics);
    const center_width = sectionWidth(center, metrics);
    const right_width = sectionWidth(right, metrics);
    const section_gap = @max(metrics.segment_gap, @as(f32, @floatFromInt(runtime_bar.section_gap_px)));

    const left_x = metrics.horizontal_padding;
    const right_x = @max(metrics.horizontal_padding, window_width - metrics.horizontal_padding - right_width);
    var center_x = @max(metrics.horizontal_padding, (window_width - center_width) / 2.0);
    const center_min = left_x + left_width + section_gap;
    const center_max = right_x - center_width - section_gap;
    if (center_min <= center_max) {
        center_x = std.math.clamp(center_x, center_min, center_max);
    } else {
        center_x = @max(metrics.horizontal_padding, (window_width - center_width) / 2.0);
    }

    return .{
        .left = try placeSection(allocator, palette, left, left_x, window_height, metrics),
        .center = try placeSection(allocator, palette, center, center_x, window_height, metrics),
        .right = try placeSection(allocator, palette, right, right_x, window_height, metrics),
    };
}

fn placeSection(
    allocator: std.mem.Allocator,
    palette: style.Palette,
    segments: []const MeasuredSegment,
    start_x: f32,
    window_height: f32,
    metrics: Metrics,
) ![]SegmentBox {
    const out = try allocator.alloc(SegmentBox, segments.len);
    var x = start_x;
    for (segments, 0..) |segment, i| {
        if (i != 0) x += metrics.segment_gap;
        const box_height = segment.text_height + (metrics.segment_padding_y * 2.0);
        const box_width = segment.text_width + (metrics.segment_padding_x * 2.0);
        const box_y = @max(0, (window_height - box_height) / 2.0);
        out[i] = .{
            .provider = segment.provider,
            .instance_name = segment.instance_name,
            .text = segment.text,
            .appearance = style.resolveAppearance(segment.appearance, palette),
            .x = x,
            .y = box_y,
            .width = box_width,
            .height = box_height,
            .text_x = x + metrics.segment_padding_x,
            .text_y = box_y + metrics.segment_padding_y,
            .text_width = segment.text_width,
            .text_height = segment.text_height,
        };
        x += box_width;
    }
    return out;
}

fn sectionWidth(segments: []const MeasuredSegment, metrics: Metrics) f32 {
    var width: f32 = 0;
    for (segments, 0..) |segment, i| {
        if (i != 0) width += metrics.segment_gap;
        width += segment.text_width + (metrics.segment_padding_x * 2.0);
    }
    return width;
}

test "layoutFrame keeps center section between left and right" {
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
        .horizontal_padding_px = 18,
        .segment_padding_x_px = 10,
        .segment_padding_y_px = 6,
        .font_points = 15,
    };
    const metrics = Metrics{
        .horizontal_padding = 18,
        .segment_gap = 8,
        .segment_padding_x = 10,
        .segment_padding_y = 6,
        .text_height = 16,
    };
    const left = [_]MeasuredSegment{.{ .provider = "a", .instance_name = null, .text = "left", .text_width = 120, .text_height = 16 }};
    const center = [_]MeasuredSegment{.{ .provider = "b", .instance_name = null, .text = "center", .text_width = 180, .text_height = 16 }};
    const right = [_]MeasuredSegment{.{ .provider = "c", .instance_name = null, .text = "right", .text_width = 160, .text_height = 16 }};

    const frame = try layoutFrame(std.testing.allocator, runtime_bar, testPalette(), 900, 40, &left, &center, &right, metrics);
    defer frame.deinit(std.testing.allocator);

    try std.testing.expect(frame.center[0].x >= frame.left[0].x + frame.left[0].width);
    try std.testing.expect(frame.center[0].x + frame.center[0].width <= frame.right[0].x);
}

test "layoutFrame preserves segment style" {
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
        .horizontal_padding_px = 18,
        .segment_padding_x_px = 10,
        .segment_padding_y_px = 6,
        .font_points = 15,
    };
    const metrics = Metrics{
        .horizontal_padding = 18,
        .segment_gap = 8,
        .segment_padding_x = 10,
        .segment_padding_y = 6,
        .text_height = 16,
    };
    const left = [_]MeasuredSegment{.{ .provider = "cpu", .instance_name = null, .text = "cpu", .text_width = 60, .text_height = 16, .appearance = style.Appearance{ .kind = .warning } }};
    const frame = try layoutFrame(std.testing.allocator, runtime_bar, testPalette(), 400, 40, &left, &.{}, &.{}, metrics);
    defer frame.deinit(std.testing.allocator);
    try std.testing.expectEqual(style.AppearanceKind.warning, frame.left[0].appearance.kind);
    try std.testing.expectEqual(@as(u8, 33), frame.left[0].appearance.background.r);
}

fn testPalette() style.Palette {
    return .{
        .background = .{ .r = 1, .g = 2, .b = 3 },
        .foreground = .{ .r = 210, .g = 211, .b = 212 },
        .segment_background = .{ .r = 10, .g = 11, .b = 12 },
        .accent_background = .{ .r = 20, .g = 21, .b = 22 },
        .subtle_background = .{ .r = 30, .g = 31, .b = 32 },
        .warning_background = .{ .r = 33, .g = 34, .b = 35 },
        .accent_foreground = .{ .r = 240, .g = 241, .b = 242 },
    };
}
