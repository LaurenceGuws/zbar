const std = @import("std");
const Backend = @import("types.zig").Backend;
const Snapshot = @import("types.zig").Snapshot;

pub const HyprlandBackend = struct {
    had_runtime_failure: bool = false,

    pub fn init() HyprlandBackend {
        return .{};
    }

    pub fn detect() bool {
        return std.posix.getenv("HYPRLAND_INSTANCE_SIGNATURE") != null and hasHyprctl();
    }

    pub fn backend(self: *HyprlandBackend) Backend {
        return .{
            .ptr = self,
            .snapshotFn = snapshotOpaque,
            .waitForChangeFn = waitForChangeOpaque,
        };
    }

    pub fn snapshot(self: *HyprlandBackend) Snapshot {
        const allocator = std.heap.page_allocator;

        const active_json = runHyprctlJson(allocator, "activewindow") catch {
            self.had_runtime_failure = true;
            return fallbackSnapshot();
        };
        defer allocator.free(active_json);

        const workspaces_json = runHyprctlJson(allocator, "workspaces") catch {
            self.had_runtime_failure = true;
            return fallbackSnapshot();
        };
        defer allocator.free(workspaces_json);

        const monitors_json = runHyprctlJson(allocator, "monitors") catch {
            self.had_runtime_failure = true;
            return fallbackSnapshot();
        };
        defer allocator.free(monitors_json);

        const active = parseActiveWindow(allocator, active_json) catch {
            self.had_runtime_failure = true;
            return fallbackSnapshot();
        };
        defer allocator.free(active.title);

        const workspace_info = parseWorkspaces(allocator, workspaces_json) catch {
            self.had_runtime_failure = true;
            return fallbackSnapshot();
        };

        const output_count = parseOutputs(allocator, monitors_json) catch {
            self.had_runtime_failure = true;
            return fallbackSnapshot();
        };

        self.had_runtime_failure = false;
        return .{
            .outputs = output_count,
            .workspaces = workspace_info.total,
            .focused_workspace = active.workspace_id,
            .focused_title = allocator.dupe(u8, active.title) catch "active window",
            .compositor = "hyprland",
        };
    }

    fn snapshotOpaque(ptr: *const anyopaque) Snapshot {
        const self: *const HyprlandBackend = @ptrCast(@alignCast(ptr));
        return @constCast(self).snapshot();
    }

    fn waitForChangeOpaque(_: *const anyopaque, timeout_ms: u64) void {
        waitForSocketEvent(timeout_ms);
    }
};

const ActiveWindow = struct {
    title: []u8,
    workspace_id: u8,
};

const WorkspaceInfo = struct {
    total: u8,
};

fn hasHyprctl() bool {
    var child = std.process.Child.init(&.{ "sh", "-lc", "command -v hyprctl >/dev/null 2>&1" }, std.heap.page_allocator);
    const term = child.spawnAndWait() catch return false;
    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn waitForSocketEvent(timeout_ms: u64) void {
    const socket_path = socket2Path() orelse {
        std.Thread.sleep(timeout_ms * std.time.ns_per_ms);
        return;
    };

    const fd = connectUnixSocket(socket_path) catch {
        std.Thread.sleep(timeout_ms * std.time.ns_per_ms);
        return;
    };
    defer std.posix.close(fd);

    var poll_fds = [_]std.posix.pollfd{.{
        .fd = fd,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    const poll_timeout: i32 = @intCast(@min(timeout_ms, @as(u64, std.math.maxInt(i32))));
    _ = std.posix.poll(&poll_fds, poll_timeout) catch {
        std.Thread.sleep(timeout_ms * std.time.ns_per_ms);
        return;
    };

    if ((poll_fds[0].revents & std.posix.POLL.IN) == 0) return;
    var buffer: [256]u8 = undefined;
    _ = std.posix.read(fd, &buffer) catch {};
}

fn runHyprctlJson(allocator: std.mem.Allocator, noun: []const u8) ![]u8 {
    var child = std.process.Child.init(&.{ "hyprctl", "-j", noun }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 512 * 1024);
    errdefer allocator.free(stdout);
    const stderr = try child.stderr.?.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(stderr);
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code == 0) return stdout,
        else => {},
    }
    allocator.free(stdout);
    return error.HyprctlFailed;
}

fn socket2Path() ?[:0]const u8 {
    const signature = std.posix.getenv("HYPRLAND_INSTANCE_SIGNATURE") orelse return null;
    return std.fmt.bufPrintZ(&socket_path_buffer, "/tmp/hypr/{s}/.socket2.sock", .{signature}) catch null;
}

var socket_path_buffer: [std.fs.max_path_bytes]u8 = undefined;

fn connectUnixSocket(path_z: [:0]const u8) !std.posix.socket_t {
    const fd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
    errdefer std.posix.close(fd);

    var addr = std.net.Address.initUnix(path_z) catch return error.BadPath;
    try std.posix.connect(fd, &addr.any, addr.getOsSockLen());
    return fd;
}

fn parseActiveWindow(allocator: std.mem.Allocator, json: []const u8) !ActiveWindow {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    const title = obj.get("title") orelse return error.InvalidJson;
    const workspace = obj.get("workspace") orelse return error.InvalidJson;
    const workspace_id_value = workspace.object.get("id") orelse return error.InvalidJson;

    return .{
        .title = try allocator.dupe(u8, title.string),
        .workspace_id = @intCast(@max(@as(i64, 0), workspace_id_value.integer)),
    };
}

fn parseWorkspaces(allocator: std.mem.Allocator, json: []const u8) !WorkspaceInfo {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    return .{
        .total = @intCast(@min(parsed.value.array.items.len, 255)),
    };
}

fn parseOutputs(allocator: std.mem.Allocator, json: []const u8) !u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    return @intCast(@min(parsed.value.array.items.len, 255));
}

fn fallbackSnapshot() Snapshot {
    return .{
        .outputs = 1,
        .workspaces = 1,
        .focused_workspace = 1,
        .focused_title = "hyprland unavailable",
        .compositor = "hyprland",
    };
}
