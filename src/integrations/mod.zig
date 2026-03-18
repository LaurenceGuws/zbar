const std = @import("std");

pub const Endpoint = struct {
    name: []const u8,
    purpose: []const u8,
};

pub const zide = [_]Endpoint{
    .{ .name = "editor_focus", .purpose = "surface current project, branch, diagnostics, and task state" },
    .{ .name = "editor_commands", .purpose = "launch files, workspaces, and editor actions from the bar" },
};

pub const wayspot = [_]Endpoint{
    .{ .name = "launcher_state", .purpose = "share shell health, notifications, and search context" },
    .{ .name = "wm_snapshot", .purpose = "reuse compositor state and workspace/window events" },
};

pub fn printPlan() !void {
    var buffer: [2048]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buffer);
    const out = &writer.interface;

    try out.print("zide\n", .{});
    for (zide) |endpoint| {
        try out.print("  {s}: {s}\n", .{ endpoint.name, endpoint.purpose });
    }

    try out.print("wayspot\n", .{});
    for (wayspot) |endpoint| {
        try out.print("  {s}: {s}\n", .{ endpoint.name, endpoint.purpose });
    }

    try out.flush();
}

test "integration plan has sibling endpoints" {
    try std.testing.expect(zide.len > 0);
    try std.testing.expect(wayspot.len > 0);
}
