const std = @import("std");
const bar = @import("../bar/mod.zig");
const modules = @import("../modules/mod.zig");
const layout = @import("layout.zig");
const paint = @import("paint.zig");
const style = @import("style.zig");
const text = @import("text.zig");

pub const Scene = struct {
    clear_color: style.Rgba,
    draw_list: paint.DrawList,
    stats: paint.Stats,

    pub fn deinit(self: Scene, allocator: std.mem.Allocator) void {
        self.draw_list.deinit(allocator);
    }
};

pub fn presentFrame(
    allocator: std.mem.Allocator,
    runtime_bar: bar.Bar,
    measurer: text.Measurer,
    window_width: f32,
    window_height: f32,
    frame: modules.Frame,
) !Scene {
    const palette = style.paletteFromBar(runtime_bar);
    const measured_left = try text.measureSegments(allocator, measurer, frame.left);
    defer allocator.free(measured_left);
    const measured_center = try text.measureSegments(allocator, measurer, frame.center);
    defer allocator.free(measured_center);
    const measured_right = try text.measureSegments(allocator, measurer, frame.right);
    defer allocator.free(measured_right);

    const layout_frame = try layout.layoutFrame(
        allocator,
        runtime_bar,
        palette,
        window_width,
        window_height,
        measured_left,
        measured_center,
        measured_right,
        metricsForBar(runtime_bar),
    );
    defer layout_frame.deinit(allocator);

    const draw_list = try paint.fromLayoutFrame(
        allocator,
        layout_frame,
        palette.background,
        window_width,
        window_height,
        runtime_bar.edge_line_px,
        runtime_bar.edge_shadow_alpha,
    );
    return .{
        .clear_color = palette.background,
        .stats = draw_list.stats(),
        .draw_list = draw_list,
    };
}

pub fn metricsForBar(runtime_bar: bar.Bar) layout.Metrics {
    return .{
        .horizontal_padding = @floatFromInt(runtime_bar.horizontal_padding_px),
        .segment_gap = @max(6, @as(f32, @floatFromInt(runtime_bar.section_gap_px)) * 0.5),
        .segment_padding_x = @floatFromInt(runtime_bar.segment_padding_x_px),
        .segment_padding_y = @floatFromInt(runtime_bar.segment_padding_y_px),
        .text_height = @floatFromInt(runtime_bar.font_points),
    };
}

test "presentFrame produces a paint scene" {
    const allocator = std.testing.allocator;
    const runtime_bar = bar.Bar{
        .height_px = 28,
        .section_gap_px = 12,
        .background = "#101112",
        .foreground = "#e0e1e2",
        .segment_background = "#1a1b1c",
        .accent_background = "#2a6b8f",
        .subtle_background = "#212223",
        .warning_background = "#8f4a2a",
        .accent_foreground = "#f8f9fa",
        .font_path = "",
        .font_fallback_path = "",
        .font_fallback_path_2 = "",
        .preview_width_px = 1200,
        .anchor = .top,
        .horizontal_padding_px = 18,
        .segment_padding_x_px = 10,
        .segment_padding_y_px = 6,
        .font_points = 15,
    };
    const measurer = text.Measurer{
        .context = undefined,
        .vtable = &.{
            .measure = struct {
                fn measure(_: *anyopaque, value: []const u8) !text.Size {
                    return .{ .width = @floatFromInt(value.len * 8), .height = 16 };
                }
            }.measure,
        },
    };
    var frame = modules.Frame{
        .left = try allocator.dupe(modules.Segment, &.{.{ .provider = "cpu", .text = "cpu 42%", .payload = .{ .integer = 42 } }}),
        .center = try allocator.dupe(modules.Segment, &.{}),
        .right = try allocator.dupe(modules.Segment, &.{}),
    };
    defer frame.deinit(allocator);

    const scene = try presentFrame(allocator, runtime_bar, measurer, 1000, 40, frame);
    defer scene.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 5), scene.draw_list.commands.len);
    try std.testing.expectEqual(@as(usize, 5), scene.stats.total_commands);
    try std.testing.expectEqual(@as(usize, 1), scene.stats.text_draws);
    try std.testing.expectEqual(@as(u8, 16), scene.clear_color.r);
}
