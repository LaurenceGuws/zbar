const Snapshot = @import("types.zig").Snapshot;
const Backend = @import("types.zig").Backend;

pub const StubBackend = struct {
    pub fn init() StubBackend {
        return .{};
    }

    pub fn backend(self: *const StubBackend) Backend {
        return .{
            .ptr = self,
            .snapshotFn = snapshotOpaque,
            .waitForChangeFn = waitForChangeOpaque,
        };
    }

    pub fn snapshot(_: StubBackend) Snapshot {
        return .{
            .outputs = 1,
            .workspaces = 5,
            .focused_workspace = 1,
            .focused_title = "zbar bootstrap",
            .compositor = "stub",
        };
    }

    fn snapshotOpaque(ptr: *const anyopaque) Snapshot {
        const self: *const StubBackend = @ptrCast(@alignCast(ptr));
        return self.snapshot();
    }

    fn waitForChangeOpaque(_: *const anyopaque, timeout_ms: u64) void {
        @import("std").Thread.sleep(timeout_ms * @import("std").time.ns_per_ms);
    }
};
