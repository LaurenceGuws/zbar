const std = @import("std");

pub const Snapshot = struct {
    outputs: u8,
    workspaces: u8,
    focused_workspace: u8,
    focused_title: []const u8,
    compositor: []const u8,

    pub fn eql(a: Snapshot, b: Snapshot) bool {
        return a.outputs == b.outputs and
            a.workspaces == b.workspaces and
            a.focused_workspace == b.focused_workspace and
            std.mem.eql(u8, a.focused_title, b.focused_title) and
            std.mem.eql(u8, a.compositor, b.compositor);
    }
};

pub const Backend = struct {
    ptr: *const anyopaque,
    snapshotFn: *const fn (ptr: *const anyopaque) Snapshot,
    waitForChangeFn: *const fn (ptr: *const anyopaque, timeout_ms: u64) void,

    pub fn snapshot(self: Backend) Snapshot {
        return self.snapshotFn(self.ptr);
    }

    pub fn waitForChange(self: Backend, timeout_ms: u64) void {
        self.waitForChangeFn(self.ptr, timeout_ms);
    }
};
