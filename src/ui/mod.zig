const build_options = @import("build_options");
const app = @import("../app/state.zig");
const bar = @import("../bar/mod.zig");
const config = @import("../config/mod.zig");
const modules = @import("../modules/mod.zig");
const render = @import("../render/mod.zig");
const wm = @import("../wm/mod.zig");

pub const gui_enabled = build_options.enable_gui;
pub const layout = @import("layout.zig");
pub const paint = @import("paint.zig");
pub const presenter = @import("presenter.zig");
pub const runtime = @import("runtime.zig");
const shell_gui = @import("shell_gui.zig");
const shell_headless = @import("shell_headless.zig");
const shell_layer = if (build_options.enable_gui) @import("shell_layer.zig") else void;
pub const surface = @import("surface.zig");
pub const style = @import("style.zig");
pub const text = @import("text.zig");

pub const Shell = union(enum) {
    gui: shell_gui.Shell,
    headless: shell_headless.Shell,
    layer_shell: if (build_options.enable_gui) shell_layer.Shell else void,

    pub fn init(
        cfg: config.Config,
        runtime_bar: bar.Bar,
        backend: wm.Backend,
        registry: *modules.Registry,
        renderer: render.Renderer,
        options: app.RunOptions,
    ) !Shell {
        return switch (resolveBackend(options.ui_backend)) {
            .sdl => .{ .gui = shell_gui.Shell.init(cfg, runtime_bar, backend, registry, renderer, options) },
            .headless => .{ .headless = shell_headless.Shell.init(cfg, runtime_bar, backend, registry, renderer, options) },
            .layer_shell => if (build_options.enable_gui)
                .{ .layer_shell = shell_layer.Shell.init(cfg, runtime_bar, backend, registry, renderer, options) }
            else
                error.GuiDisabled,
            .auto => unreachable,
        };
    }

    pub fn run(self: *Shell) !void {
        switch (self.*) {
            .gui => |*shell| try shell.run(),
            .headless => |*shell| try shell.run(),
            .layer_shell => |*shell| try shell.run(),
        }
    }
};

fn resolveBackend(requested: app.RunOptions.UiBackend) app.RunOptions.UiBackend {
    return switch (requested) {
        .auto => if (build_options.enable_gui) .sdl else .headless,
        else => requested,
    };
}

pub fn printLayerShellCapabilities() !void {
    if (!build_options.enable_gui) return error.GuiDisabled;
    try shell_layer.printCapabilityReport();
}
