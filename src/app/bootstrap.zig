const App = @import("state.zig").App;
const Logger = @import("logger.zig").Logger;
const Mode = @import("state.zig").Mode;

pub fn bootstrap() App {
    return .{
        .mode = .bar,
        .logger = Logger.init(.info),
    };
}

test "bootstrap defaults to bar mode" {
    const app = bootstrap();
    try @import("std").testing.expect(app.mode == Mode.bar);
}
