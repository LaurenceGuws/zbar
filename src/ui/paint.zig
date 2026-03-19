const std = @import("std");
const layout = @import("layout.zig");
const style = @import("style.zig");

pub const FillRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    color: style.Rgba,
    corner_radius: f32,
    border_width: f32,
    border_color: style.Rgba,
};

pub const StrokeRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    corner_radius: f32,
    line_width: f32,
    color: style.Rgba,
};

pub const PushClipRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const DrawText = struct {
    pub const HorizontalAlign = enum {
        start,
        center,
        end,
    };

    pub const VerticalAlign = enum {
        top,
        middle,
        bottom,
    };

    pub const Overflow = enum {
        clip,
        allow,
    };

    text: []const u8,
    box_x: f32,
    box_y: f32,
    box_width: f32,
    box_height: f32,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    color: style.Rgba,
    horizontal_align: HorizontalAlign = .center,
    vertical_align: VerticalAlign = .middle,
    overflow: Overflow = .allow,
};

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const Command = union(enum) {
    fill_rect: FillRect,
    stroke_rect: StrokeRect,
    push_clip_rect: PushClipRect,
    pop_clip_rect: void,
    draw_text: DrawText,
};

pub const DrawList = struct {
    commands: []Command,

    pub fn deinit(self: DrawList, allocator: std.mem.Allocator) void {
        allocator.free(self.commands);
    }
};

pub fn effectiveRadius(width: f32, height: f32, radius: f32) f32 {
    return @min(radius, @min(width, height) * 0.5);
}

pub fn alignedTextX(text: DrawText, content_width: f32) f32 {
    return switch (text.horizontal_align) {
        .start => text.box_x,
        .center => text.box_x + @max((text.box_width - content_width) * 0.5, 0),
        .end => text.box_x + @max(text.box_width - content_width, 0),
    };
}

pub fn alignedTextY(text: DrawText, content_height: f32) f32 {
    return switch (text.vertical_align) {
        .top => text.box_y,
        .middle => text.box_y + @max((text.box_height - content_height) * 0.5, 0),
        .bottom => text.box_y + @max(text.box_height - content_height, 0),
    };
}

pub fn textContentRect(text: DrawText, content_width: f32, content_height: f32) Rect {
    return .{
        .x = alignedTextX(text, content_width),
        .y = alignedTextY(text, content_height),
        .width = content_width,
        .height = content_height,
    };
}

pub fn fromLayoutFrame(
    allocator: std.mem.Allocator,
    frame: layout.LayoutFrame,
    background: style.Rgba,
    window_width: f32,
    window_height: f32,
    edge_line_px: u16,
    edge_shadow_alpha: u8,
) !DrawList {
    const command_count = countCommands(frame, edge_line_px);
    const commands = try allocator.alloc(Command, command_count);
    var index: usize = 0;

    appendEdgeTreatments(commands, &index, background, window_width, window_height, edge_line_px, edge_shadow_alpha);
    appendBoxes(commands, &index, frame.left);
    appendBoxes(commands, &index, frame.center);
    appendBoxes(commands, &index, frame.right);

    std.debug.assert(index == commands.len);
    return .{ .commands = commands };
}

fn countCommands(frame: layout.LayoutFrame, edge_line_px: u16) usize {
    const box_count = frame.left.len + frame.center.len + frame.right.len;
    const edge_count: usize = if (edge_line_px == 0) 0 else 2;
    return edge_count + (box_count * 5);
}

fn appendEdgeTreatments(
    commands: []Command,
    index: *usize,
    background: style.Rgba,
    window_width: f32,
    window_height: f32,
    edge_line_px: u16,
    edge_shadow_alpha: u8,
) void {
    if (edge_line_px == 0) return;

    const line_height: f32 = @floatFromInt(edge_line_px);
    commands[index.*] = .{ .fill_rect = .{
        .x = 0,
        .y = 0,
        .width = window_width,
        .height = line_height,
        .color = style.tintColor(background, 0.16, 220),
        .corner_radius = 0,
        .border_width = 0,
        .border_color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    } };
    index.* += 1;

    commands[index.*] = .{ .fill_rect = .{
        .x = 0,
        .y = @max(window_height - line_height, 0),
        .width = window_width,
        .height = line_height,
        .color = style.tintColor(background, -0.18, edge_shadow_alpha),
        .corner_radius = 0,
        .border_width = 0,
        .border_color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    } };
    index.* += 1;
}

fn appendBoxes(commands: []Command, index: *usize, boxes: []const layout.SegmentBox) void {
    for (boxes) |box| {
        commands[index.*] = .{ .fill_rect = .{
            .x = box.x,
            .y = box.y,
            .width = box.width,
            .height = box.height,
            .color = box.appearance.background,
            .corner_radius = box.appearance.decoration.corner_radius,
            .border_width = box.appearance.decoration.border_width,
            .border_color = box.appearance.decoration.border_color,
        } };
        index.* += 1;

        commands[index.*] = .{ .stroke_rect = .{
            .x = box.x,
            .y = box.y,
            .width = box.width,
            .height = box.height,
            .corner_radius = box.appearance.decoration.corner_radius,
            .line_width = box.appearance.decoration.border_width,
            .color = box.appearance.decoration.border_color,
        } };
        index.* += 1;

        commands[index.*] = .{ .push_clip_rect = .{
            .x = box.x,
            .y = box.y,
            .width = box.width,
            .height = box.height,
        } };
        index.* += 1;

        commands[index.*] = .{ .draw_text = .{
            .text = box.text,
            .box_x = box.x,
            .box_y = box.y,
            .box_width = box.width,
            .box_height = box.height,
            .x = box.text_x,
            .y = box.text_y,
            .width = box.text_width,
            .height = box.text_height,
            .color = box.appearance.foreground,
            .horizontal_align = .center,
            .vertical_align = .middle,
            .overflow = .allow,
        } };
        index.* += 1;

        commands[index.*] = .{ .pop_clip_rect = {} };
        index.* += 1;
    }
}

test "fromLayoutFrame emits rect and text commands per segment" {
    const allocator = std.testing.allocator;
    const frame = layout.LayoutFrame{
        .left = try allocator.dupe(layout.SegmentBox, &.{
            .{
                .provider = "cpu",
                .instance_name = null,
                .text = "cpu 5%",
                .appearance = .{
                    .kind = .warning,
                    .background = .{ .r = 11, .g = 12, .b = 13, .a = 255 },
                    .foreground = .{ .r = 211, .g = 212, .b = 213, .a = 255 },
                    .decoration = .{
                        .corner_radius = 8,
                        .border_width = 1.5,
                        .border_color = .{ .r = 44, .g = 45, .b = 46, .a = 200 },
                    },
                },
                .x = 10,
                .y = 5,
                .width = 80,
                .height = 24,
                .text_x = 18,
                .text_y = 9,
                .text_width = 64,
                .text_height = 12,
            },
        }),
        .center = try allocator.dupe(layout.SegmentBox, &.{}),
        .right = try allocator.dupe(layout.SegmentBox, &.{}),
    };
    defer frame.deinit(allocator);

    const draw_list = try fromLayoutFrame(
        allocator,
        frame,
        .{ .r = 16, .g = 17, .b = 18, .a = 255 },
        100,
        30,
        1,
        180,
    );
    defer draw_list.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 7), draw_list.commands.len);
    try std.testing.expectEqualDeep(Command{ .fill_rect = .{
        .x = 0,
        .y = 0,
        .width = 100,
        .height = 1,
        .color = style.tintColor(.{ .r = 16, .g = 17, .b = 18, .a = 255 }, 0.16, 220),
        .corner_radius = 0,
        .border_width = 0,
        .border_color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    } }, draw_list.commands[0]);
    try std.testing.expectEqualDeep(Command{ .fill_rect = .{
        .x = 0,
        .y = 29,
        .width = 100,
        .height = 1,
        .color = style.tintColor(.{ .r = 16, .g = 17, .b = 18, .a = 255 }, -0.18, 180),
        .corner_radius = 0,
        .border_width = 0,
        .border_color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    } }, draw_list.commands[1]);
    try std.testing.expectEqualDeep(Command{ .fill_rect = .{
        .x = 10,
        .y = 5,
        .width = 80,
        .height = 24,
        .color = .{ .r = 11, .g = 12, .b = 13, .a = 255 },
        .corner_radius = 8,
        .border_width = 1.5,
        .border_color = .{ .r = 44, .g = 45, .b = 46, .a = 200 },
    } }, draw_list.commands[2]);
    try std.testing.expectEqualDeep(Command{ .stroke_rect = .{
        .x = 10,
        .y = 5,
        .width = 80,
        .height = 24,
        .corner_radius = 8,
        .line_width = 1.5,
        .color = .{ .r = 44, .g = 45, .b = 46, .a = 200 },
    } }, draw_list.commands[3]);
    try std.testing.expectEqualDeep(Command{ .push_clip_rect = .{
        .x = 10,
        .y = 5,
        .width = 80,
        .height = 24,
    } }, draw_list.commands[4]);
    try std.testing.expectEqualDeep(Command{ .draw_text = .{
        .text = "cpu 5%",
        .box_x = 10,
        .box_y = 5,
        .box_width = 80,
        .box_height = 24,
        .x = 18,
        .y = 9,
        .width = 64,
        .height = 12,
        .color = .{ .r = 211, .g = 212, .b = 213, .a = 255 },
        .horizontal_align = .center,
        .vertical_align = .middle,
        .overflow = .allow,
    } }, draw_list.commands[5]);
    try std.testing.expectEqualDeep(Command{ .pop_clip_rect = {} }, draw_list.commands[6]);
}
