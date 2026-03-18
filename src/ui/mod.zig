const build_options = @import("build_options");

pub const gui_enabled = build_options.enable_gui;
pub const layout = @import("layout.zig");
pub const paint = @import("paint.zig");
pub const presenter = @import("presenter.zig");
pub const surface = @import("surface.zig");
pub const style = @import("style.zig");
pub const text = @import("text.zig");
pub const Shell = if (build_options.enable_gui)
    @import("shell_gui.zig").Shell
else
    @import("shell_headless.zig").Shell;
