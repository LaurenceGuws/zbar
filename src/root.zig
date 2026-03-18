pub const app = @import("app/mod.zig");
pub const bar = @import("bar/mod.zig");
pub const config = @import("config/mod.zig");
pub const integrations = @import("integrations/mod.zig");
pub const lua = @import("lua/mod.zig");
pub const modules = @import("modules/mod.zig");
pub const render = @import("render/mod.zig");
pub const ui = @import("ui/mod.zig");
pub const wm = @import("wm/mod.zig");

test "root exports bootstrap" {
    _ = app.bootstrap;
}
