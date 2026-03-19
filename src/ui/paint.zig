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

pub const DrawText = struct {
    text: []const u8,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    color: style.Rgba,
};

pub const Command = union(enum) {
    fill_rect: FillRect,
    draw_text: DrawText,
};

pub const DrawList = struct {
    commands: []Command,

    pub fn deinit(self: DrawList, allocator: std.mem.Allocator) void {
        allocator.free(self.commands);
    }
};

pub fn fromLayoutFrame(allocator: std.mem.Allocator, frame: layout.LayoutFrame) !DrawList {
    const command_count = countCommands(frame);
    const commands = try allocator.alloc(Command, command_count);
    var index: usize = 0;

    appendBoxes(commands, &index, frame.left);
    appendBoxes(commands, &index, frame.center);
    appendBoxes(commands, &index, frame.right);

    std.debug.assert(index == commands.len);
    return .{ .commands = commands };
}

fn countCommands(frame: layout.LayoutFrame) usize {
    const box_count = frame.left.len + frame.center.len + frame.right.len;
    return box_count * 2;
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

        commands[index.*] = .{ .draw_text = .{
            .text = box.text,
            .x = box.text_x,
            .y = box.text_y,
            .width = box.text_width,
            .height = box.text_height,
            .color = box.appearance.foreground,
        } };
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

    const draw_list = try fromLayoutFrame(allocator, frame);
    defer draw_list.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), draw_list.commands.len);
    try std.testing.expectEqualDeep(Command{ .fill_rect = .{
        .x = 10,
        .y = 5,
        .width = 80,
        .height = 24,
        .color = .{ .r = 11, .g = 12, .b = 13, .a = 255 },
        .corner_radius = 8,
        .border_width = 1.5,
        .border_color = .{ .r = 44, .g = 45, .b = 46, .a = 200 },
    } }, draw_list.commands[0]);
    try std.testing.expectEqualDeep(Command{ .draw_text = .{
        .text = "cpu 5%",
        .x = 18,
        .y = 9,
        .width = 64,
        .height = 12,
        .color = .{ .r = 211, .g = 212, .b = 213, .a = 255 },
    } }, draw_list.commands[1]);
}
