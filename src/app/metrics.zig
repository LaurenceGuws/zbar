const std = @import("std");

pub const Stopwatch = struct {
    started_ns: i128,

    pub fn start() Stopwatch {
        return .{ .started_ns = std.time.nanoTimestamp() };
    }

    pub fn elapsedNs(self: Stopwatch) i128 {
        return std.time.nanoTimestamp() - self.started_ns;
    }
};

test "stopwatch elapsed is monotonic enough for a single call" {
    const sw = Stopwatch.start();
    try @import("std").testing.expect(sw.elapsedNs() >= 0);
}
