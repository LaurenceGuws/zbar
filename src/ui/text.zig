const std = @import("std");
const modules = @import("../modules/mod.zig");
const layout = @import("layout.zig");
const style = @import("style.zig");

pub const Size = struct {
    width: f32,
    height: f32,
};

pub const Measurer = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        measure: *const fn (context: *anyopaque, text: []const u8) anyerror!Size,
    };

    pub fn measure(self: Measurer, text: []const u8) !Size {
        return self.vtable.measure(self.context, text);
    }
};

pub fn measureSegments(
    allocator: std.mem.Allocator,
    measurer: Measurer,
    segments: []const modules.Segment,
) ![]layout.MeasuredSegment {
    const measured = try allocator.alloc(layout.MeasuredSegment, segments.len);
    errdefer allocator.free(measured);

    for (segments, 0..) |segment, i| {
        const size = try measurer.measure(segment.text);
        measured[i] = .{
            .provider = segment.provider,
            .instance_name = segment.instance_name,
            .text = segment.text,
            .text_width = size.width,
            .text_height = size.height,
            .appearance = style.styleForSegment(segment),
        };
    }
    return measured;
}

test "measureSegments builds measured layout inputs" {
    const TestContext = struct {};
    const ctx = TestContext{};
    const measurer = Measurer{
        .context = @constCast(&ctx),
        .vtable = &.{
            .measure = struct {
                fn measure(_: *anyopaque, text: []const u8) !Size {
                    return .{ .width = @floatFromInt(text.len * 10), .height = 16 };
                }
            }.measure,
        },
    };
    const segments = [_]modules.Segment{
        .{ .provider = "workspaces", .text = "ws" },
        .{ .provider = "cpu", .text = "cpu 91%", .payload = .{ .integer = 91 } },
    };
    const measured = try measureSegments(std.testing.allocator, measurer, &segments);
    defer std.testing.allocator.free(measured);
    try std.testing.expectEqual(@as(f32, 20), measured[0].text_width);
    try std.testing.expectEqual(style.AppearanceKind.accent, measured[0].appearance.kind);
    try std.testing.expectEqual(style.AppearanceKind.warning, measured[1].appearance.kind);
}
