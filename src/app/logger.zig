const std = @import("std");

pub const Level = enum {
    debug,
    info,
    warn,
    err,
};

pub const Logger = struct {
    level: Level,

    pub fn init(level: Level) Logger {
        return .{ .level = level };
    }

    pub fn info(self: Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.info, fmt, args);
    }

    fn log(self: Logger, level: Level, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(level) < @intFromEnum(self.level)) return;
        std.log.info(fmt, args);
    }
};
