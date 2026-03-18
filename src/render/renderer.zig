const std = @import("std");
const bar = @import("../bar/mod.zig");
const modules = @import("../modules/mod.zig");
const wm = @import("../wm/mod.zig");

pub const Renderer = struct {
    pub const Signature = struct {
        layout: u64,
        display_content: u64,
        semantic_content: u64,

        pub fn full(self: Signature) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashInt(&hasher, self.layout);
            hashInt(&hasher, self.display_content);
            return hasher.final();
        }
    };

    pub fn init() Renderer {
        return .{};
    }

    pub fn render(
        self: Renderer,
        out: anytype,
        runtime_bar: bar.Bar,
        snapshot: wm.Snapshot,
        frame: modules.Frame,
    ) !void {
        _ = self;
        try out.print(
            "height={d} gap={d} bg={s} fg={s} compositor={s} outputs={d} left=[",
            .{ runtime_bar.height_px, runtime_bar.section_gap_px, runtime_bar.background, runtime_bar.foreground, snapshot.compositor, snapshot.outputs },
        );
        try printSection(out, frame.left);
        try out.print("] center=[", .{});
        try printSection(out, frame.center);
        try out.print("] right=[", .{});
        try printSection(out, frame.right);
        try out.print("]\n", .{});
    }

    pub fn signature(
        self: Renderer,
        runtime_bar: bar.Bar,
        snapshot: wm.Snapshot,
        frame: modules.Frame,
    ) Signature {
        _ = self;
        return .{
            .layout = layoutSignature(runtime_bar, snapshot, frame),
            .display_content = displayContentSignature(frame),
            .semantic_content = semanticContentSignature(frame),
        };
    }
};

fn printSection(out: anytype, segments: []const modules.Segment) !void {
    for (segments, 0..) |segment, i| {
        if (i != 0) try out.print(" | ", .{});
        try out.print("{s}", .{segment.text});
    }
}

fn hashSectionSemantic(hasher: *std.hash.Wyhash, segments: []const modules.Segment) void {
    for (segments) |segment| {
        hasher.update(segment.provider);
        if (segment.instance_name) |name| hasher.update(name);
        hashPayload(hasher, segment.payload);
        hashInt(hasher, segment.content_id);
        if (segment.content_id == 0 and segment.payload == .none) hasher.update(segment.text);
        hasher.update("|");
    }
}

fn hashSectionDisplay(hasher: *std.hash.Wyhash, segments: []const modules.Segment) void {
    for (segments) |segment| {
        hasher.update(segment.provider);
        if (segment.instance_name) |name| hasher.update(name);
        hasher.update(segment.text);
        hasher.update("|");
    }
}

fn hashSectionLayout(hasher: *std.hash.Wyhash, segments: []const modules.Segment) void {
    for (segments) |segment| {
        hasher.update(segment.provider);
        if (segment.instance_name) |name| hasher.update(name);
        hasher.update("|");
    }
}

fn hashInt(hasher: *std.hash.Wyhash, value: anytype) void {
    var buffer: [@sizeOf(@TypeOf(value))]u8 = undefined;
    std.mem.writeInt(@TypeOf(value), &buffer, value, .little);
    hasher.update(&buffer);
}

fn hashPayload(hasher: *std.hash.Wyhash, payload: modules.Payload) void {
    hasher.update(@tagName(payload));
    switch (payload) {
        .none => {},
        .text => |value| hasher.update(value),
        .state => |value| hasher.update(value),
        .integer => |value| hashInt(hasher, value),
        .number => |value| {
            const bits: u64 = @bitCast(value);
            hashInt(hasher, bits);
        },
    }
}

fn layoutSignature(runtime_bar: bar.Bar, snapshot: wm.Snapshot, frame: modules.Frame) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashInt(&hasher, runtime_bar.height_px);
    hashInt(&hasher, runtime_bar.section_gap_px);
    hasher.update(runtime_bar.background);
    hasher.update(runtime_bar.foreground);
    hasher.update(snapshot.compositor);
    hashInt(&hasher, snapshot.outputs);
    hashSectionLayout(&hasher, frame.left);
    hashSectionLayout(&hasher, frame.center);
    hashSectionLayout(&hasher, frame.right);
    return hasher.final();
}

fn displayContentSignature(frame: modules.Frame) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashSectionDisplay(&hasher, frame.left);
    hashSectionDisplay(&hasher, frame.center);
    hashSectionDisplay(&hasher, frame.right);
    return hasher.final();
}

fn semanticContentSignature(frame: modules.Frame) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashSectionSemantic(&hasher, frame.left);
    hashSectionSemantic(&hasher, frame.center);
    hashSectionSemantic(&hasher, frame.right);
    return hasher.final();
}

test "renderer prints composed frame" {
    const renderer = Renderer.init();
    var buffer: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const frame = modules.Frame{
        .left = &[_]modules.Segment{.{ .provider = "a", .text = "L" }},
        .center = &[_]modules.Segment{.{ .provider = "b", .text = "C" }},
        .right = &[_]modules.Segment{.{ .provider = "c", .text = "R" }},
    };

    const runtime_bar = bar.Bar{
        .height_px = 28,
        .section_gap_px = 12,
        .background = "#11161c",
        .foreground = "#d7dee7",
        .segment_background = "#2a3139",
        .accent_background = "#275b7a",
        .subtle_background = "#1c232a",
        .warning_background = "#7a4627",
        .accent_foreground = "#eff5fa",
        .horizontal_padding_px = 18,
        .segment_padding_x_px = 10,
        .segment_padding_y_px = 6,
        .font_points = 15,
    };

    try renderer.render(stream.writer().any(), runtime_bar, .{
        .outputs = 1,
        .workspaces = 3,
        .focused_workspace = 1,
        .focused_title = "T",
        .compositor = "stub",
    }, frame);

    try std.testing.expect(std.mem.indexOf(u8, stream.getWritten(), "left=[L]") != null);
}

test "renderer signature changes with frame text" {
    const renderer = Renderer.init();
    const runtime_bar = bar.Bar{
        .height_px = 28,
        .section_gap_px = 12,
        .background = "#11161c",
        .foreground = "#d7dee7",
        .segment_background = "#2a3139",
        .accent_background = "#275b7a",
        .subtle_background = "#1c232a",
        .warning_background = "#7a4627",
        .accent_foreground = "#eff5fa",
        .horizontal_padding_px = 18,
        .segment_padding_x_px = 10,
        .segment_padding_y_px = 6,
        .font_points = 15,
    };
    const snapshot = wm.Snapshot{
        .outputs = 1,
        .workspaces = 3,
        .focused_workspace = 1,
        .focused_title = "T",
        .compositor = "stub",
    };
    const frame_a = modules.Frame{
        .left = &[_]modules.Segment{.{ .provider = "a", .text = "L" }},
        .center = &[_]modules.Segment{.{ .provider = "b", .text = "C" }},
        .right = &[_]modules.Segment{.{ .provider = "c", .text = "R" }},
    };
    const frame_b = modules.Frame{
        .left = &[_]modules.Segment{.{ .provider = "a", .text = "LX" }},
        .center = &[_]modules.Segment{.{ .provider = "b", .text = "C" }},
        .right = &[_]modules.Segment{.{ .provider = "c", .text = "R" }},
    };

    const sig_a = renderer.signature(runtime_bar, snapshot, frame_a);
    const sig_b = renderer.signature(runtime_bar, snapshot, frame_b);
    try std.testing.expect(sig_a.display_content != sig_b.display_content);
    try std.testing.expect(sig_a.semantic_content != sig_b.semantic_content);
    try std.testing.expect(sig_a.full() != sig_b.full());
}

test "renderer layout signature ignores text-only changes" {
    const renderer = Renderer.init();
    const runtime_bar = bar.Bar{
        .height_px = 28,
        .section_gap_px = 12,
        .background = "#11161c",
        .foreground = "#d7dee7",
        .segment_background = "#2a3139",
        .accent_background = "#275b7a",
        .subtle_background = "#1c232a",
        .warning_background = "#7a4627",
        .accent_foreground = "#eff5fa",
        .horizontal_padding_px = 18,
        .segment_padding_x_px = 10,
        .segment_padding_y_px = 6,
        .font_points = 15,
    };
    const snapshot = wm.Snapshot{
        .outputs = 1,
        .workspaces = 3,
        .focused_workspace = 1,
        .focused_title = "T",
        .compositor = "stub",
    };
    const frame_a = modules.Frame{
        .left = &[_]modules.Segment{.{ .provider = "a", .instance_name = "x", .text = "L" }},
        .center = &[_]modules.Segment{.{ .provider = "b", .text = "C" }},
        .right = &[_]modules.Segment{.{ .provider = "c", .text = "R" }},
    };
    const frame_b = modules.Frame{
        .left = &[_]modules.Segment{.{ .provider = "a", .instance_name = "x", .text = "LL" }},
        .center = &[_]modules.Segment{.{ .provider = "b", .text = "CC" }},
        .right = &[_]modules.Segment{.{ .provider = "c", .text = "RR" }},
    };

    const sig_a = renderer.signature(runtime_bar, snapshot, frame_a);
    const sig_b = renderer.signature(runtime_bar, snapshot, frame_b);
    try std.testing.expectEqual(sig_a.layout, sig_b.layout);
    try std.testing.expect(sig_a.display_content != sig_b.display_content);
    try std.testing.expect(sig_a.semantic_content != sig_b.semantic_content);
}

test "renderer content signature uses payload semantics" {
    const renderer = Renderer.init();
    const runtime_bar = bar.Bar{
        .height_px = 28,
        .section_gap_px = 12,
        .background = "#11161c",
        .foreground = "#d7dee7",
        .segment_background = "#2a3139",
        .accent_background = "#275b7a",
        .subtle_background = "#1c232a",
        .warning_background = "#7a4627",
        .accent_foreground = "#eff5fa",
        .horizontal_padding_px = 18,
        .segment_padding_x_px = 10,
        .segment_padding_y_px = 6,
        .font_points = 15,
    };
    const snapshot = wm.Snapshot{
        .outputs = 1,
        .workspaces = 3,
        .focused_workspace = 1,
        .focused_title = "T",
        .compositor = "stub",
    };
    const frame_a = modules.Frame{
        .left = &[_]modules.Segment{.{ .provider = "cpu", .text = "cpu 12%", .payload = .{ .integer = 12 } }},
        .center = &.{},
        .right = &.{},
    };
    const frame_b = modules.Frame{
        .left = &[_]modules.Segment{.{ .provider = "cpu", .text = "cpu 15%", .payload = .{ .integer = 15 } }},
        .center = &.{},
        .right = &.{},
    };

    const sig_a = renderer.signature(runtime_bar, snapshot, frame_a);
    const sig_b = renderer.signature(runtime_bar, snapshot, frame_b);
    try std.testing.expectEqual(sig_a.display_content, sig_b.display_content);
    try std.testing.expect(sig_a.semantic_content != sig_b.semantic_content);
}
