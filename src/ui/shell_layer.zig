const std = @import("std");
const bar = @import("../bar/mod.zig");
const config = @import("../config/mod.zig");
const modules = @import("../modules/mod.zig");
const render = @import("../render/mod.zig");
const ui_presenter = @import("presenter.zig");
const ui_paint = @import("paint.zig");
const ui_runtime = @import("runtime.zig");
const ui_style = @import("style.zig");
const ui_text = @import("text.zig");
const wm = @import("../wm/mod.zig");
const RunOptions = @import("../app/state.zig").RunOptions;
const c = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
    @cInclude("cairo/cairo.h");
    @cInclude("cairo/cairo-ft.h");
    @cInclude("sys/mman.h");
    @cInclude("wayland-client.h");
    @cInclude("wayland-client-protocol.h");
    @cInclude("xdg-shell-client-protocol.h");
    @cInclude("wlr-layer-shell-unstable-v1-client-protocol.h");
});

pub const CapabilityState = enum {
    ready,
    missing_wayland_display,
    missing_xdg_runtime_dir,
    wayland_connect_failed,
    missing_wl_compositor,
    missing_wl_shm,
    missing_layer_shell_protocol,
};

pub const CapabilityReport = struct {
    state: CapabilityState,
    wayland_display: ?[]const u8,
    xdg_runtime_dir: ?[]const u8,
    compositor_available: bool = false,
    shm_available: bool = false,
    layer_shell_available: bool = false,
    xdg_wm_base_available: bool = false,
    output_count: u32 = 0,

    pub fn ok(self: CapabilityReport) bool {
        return self.state == .ready;
    }
};

pub const Shell = struct {
    cfg: config.Config,
    runtime_bar: bar.Bar,
    backend: wm.Backend,
    registry: *modules.Registry,
    renderer: render.Renderer,
    options: RunOptions,

    pub fn init(
        cfg: config.Config,
        runtime_bar: bar.Bar,
        backend: wm.Backend,
        registry: *modules.Registry,
        renderer: render.Renderer,
        options: RunOptions,
    ) Shell {
        return .{
            .cfg = cfg,
            .runtime_bar = runtime_bar,
            .backend = backend,
            .registry = registry,
            .renderer = renderer,
            .options = options,
        };
    }

    pub fn run(self: *Shell) !void {
        const report = detectCapabilities();
        if (report.state != .ready) {
            return switch (report.state) {
                .ready => unreachable,
                .missing_wayland_display => error.MissingWaylandDisplay,
                .missing_xdg_runtime_dir => error.MissingXdgRuntimeDir,
                .wayland_connect_failed => error.WaylandConnectFailed,
                .missing_wl_compositor => error.MissingWlCompositor,
                .missing_wl_shm => error.MissingWlShm,
                .missing_layer_shell_protocol => error.MissingLayerShellProtocol,
            };
        }

        var layer_ui = try LayerUi.init(self.runtime_bar, self.backend);
        defer layer_ui.deinit();
        const state = self.runtimeState();
        try ui_runtime.runShell(&state, layer_ui.hooks());
    }

    fn runtimeState(self: *Shell) ui_runtime.ShellState {
        return .{
            .cfg = self.cfg,
            .runtime_bar = self.runtime_bar,
            .backend = self.backend,
            .registry = self.registry,
            .renderer = self.renderer,
            .options = self.options,
        };
    }
};

const LayerUi = struct {
    client: LayerClient,
    backend: wm.Backend,
    redraw_reason_buffer: [32]u8 = undefined,
    last_redraw_reason: ?[]const u8 = null,
    text_measurer: CairoTextMeasurer,

    fn init(runtime_bar: bar.Bar, backend: wm.Backend) !LayerUi {
        var client = try LayerClient.init(runtime_bar);
        errdefer client.deinit();
        try client.createSurface();
        var text_measurer = try CairoTextMeasurer.init(runtime_bar);
        errdefer text_measurer.deinit();
        return .{
            .client = client,
            .backend = backend,
            .text_measurer = text_measurer,
        };
    }

    fn deinit(self: *LayerUi) void {
        self.text_measurer.deinit();
        self.client.deinit();
    }

    fn hooks(self: *LayerUi) ui_runtime.Hooks {
        return .{
            .context = @ptrCast(self),
            .vtable = &.{
                .isQuitRequested = isQuitRequested,
                .beforeFrame = beforeFrame,
                .drawFrame = drawFrame,
                .forceRedraw = forceRedraw,
                .redrawReason = redrawReason,
                .wait = waitForNextEvent,
            },
        };
    }

    fn isQuitRequested(context: *anyopaque) bool {
        const self: *LayerUi = @ptrCast(@alignCast(context));
        return self.client.closed;
    }

    fn beforeFrame(context: *anyopaque) void {
        const self: *LayerUi = @ptrCast(@alignCast(context));
        _ = c.wl_display_dispatch_pending(self.client.display);
    }

    fn drawFrame(context: *anyopaque, runtime_bar: bar.Bar, frame: modules.Frame) !void {
        const self: *LayerUi = @ptrCast(@alignCast(context));
        try self.client.presentFrame(self.text_measurer.measurer(), frame, runtime_bar);
    }

    fn forceRedraw(context: *anyopaque) bool {
        const self: *LayerUi = @ptrCast(@alignCast(context));
        const dirty = self.client.takeDirty();
        self.last_redraw_reason = dirty.formatReason(&self.redraw_reason_buffer);
        return dirty.any();
    }

    fn redrawReason(context: *anyopaque) ?[]const u8 {
        const self: *LayerUi = @ptrCast(@alignCast(context));
        return self.last_redraw_reason;
    }

    fn waitForNextEvent(context: *anyopaque, timeout_ms: u64) void {
        const self: *LayerUi = @ptrCast(@alignCast(context));
        _ = c.wl_display_flush(self.client.display);
        var remaining_ms = timeout_ms;
        while (true) {
            if (drainWaylandEvents(self.client.display)) return;
            if (remaining_ms == 0) return;

            const slice_ms = @min(remaining_ms, 25);
            self.backend.waitForChange(slice_ms);
            remaining_ms -= slice_ms;
        }
    }
};

const CairoFont = struct {
    ft_library: c.FT_Library,
    ft_face: c.FT_Face,
    font_face: *c.cairo_font_face_t,

    fn init(runtime_bar: bar.Bar) ?CairoFont {
        var ft_library: c.FT_Library = null;
        if (c.FT_Init_FreeType(&ft_library) != 0 or ft_library == null) return null;
        errdefer _ = c.FT_Done_FreeType(ft_library);

        const path = selectFontPath(runtime_bar) orelse return null;
        const path_z = std.heap.page_allocator.dupeZ(u8, path) catch return null;
        defer std.heap.page_allocator.free(path_z);

        var ft_face: c.FT_Face = null;
        if (c.FT_New_Face(ft_library, path_z.ptr, 0, &ft_face) != 0 or ft_face == null) return null;
        errdefer _ = c.FT_Done_Face(ft_face);

        const font_face = c.cairo_ft_font_face_create_for_ft_face(ft_face, 0) orelse return null;
        if (c.cairo_font_face_status(font_face) != c.CAIRO_STATUS_SUCCESS) {
            c.cairo_font_face_destroy(font_face);
            return null;
        }

        return .{
            .ft_library = ft_library,
            .ft_face = ft_face,
            .font_face = font_face,
        };
    }

    fn deinit(self: *CairoFont) void {
        c.cairo_font_face_destroy(self.font_face);
        _ = c.FT_Done_Face(self.ft_face);
        _ = c.FT_Done_FreeType(self.ft_library);
    }
};

fn drainWaylandEvents(display: *c.wl_display) bool {
    const pending = c.wl_display_dispatch_pending(display);
    if (pending > 0) return true;

    const fd = c.wl_display_get_fd(display);
    if (fd < 0) return false;

    var poll_fds = [_]std.posix.pollfd{
        .{
            .fd = fd,
            .events = std.posix.POLL.IN,
            .revents = 0,
        },
    };

    const ready = std.posix.poll(&poll_fds, 0) catch return false;
    if (ready <= 0) return false;
    if ((poll_fds[0].revents & std.posix.POLL.IN) != 0) {
        _ = c.wl_display_dispatch(display);
        return true;
    }
    return false;
}

pub fn detectCapabilities() CapabilityReport {
    const maybe_wayland_display = std.posix.getenv("WAYLAND_DISPLAY");
    const maybe_xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR");

    if (maybe_wayland_display == null or maybe_wayland_display.?.len == 0) {
        return .{
            .state = .missing_wayland_display,
            .wayland_display = maybe_wayland_display,
            .xdg_runtime_dir = maybe_xdg_runtime_dir,
        };
    }
    if (maybe_xdg_runtime_dir == null or maybe_xdg_runtime_dir.?.len == 0) {
        return .{
            .state = .missing_xdg_runtime_dir,
            .wayland_display = maybe_wayland_display,
            .xdg_runtime_dir = maybe_xdg_runtime_dir,
        };
    }
    return detectWaylandGlobals(maybe_wayland_display, maybe_xdg_runtime_dir);
}

fn detectWaylandGlobals(maybe_wayland_display: ?[]const u8, maybe_xdg_runtime_dir: ?[]const u8) CapabilityReport {
    const display = c.wl_display_connect(null);
    if (display == null) {
        return .{
            .state = .wayland_connect_failed,
            .wayland_display = maybe_wayland_display,
            .xdg_runtime_dir = maybe_xdg_runtime_dir,
        };
    }
    defer c.wl_display_disconnect(display);

    const registry = c.wl_display_get_registry(display);
    if (registry == null) {
        return .{
            .state = .wayland_connect_failed,
            .wayland_display = maybe_wayland_display,
            .xdg_runtime_dir = maybe_xdg_runtime_dir,
        };
    }
    defer c.wl_registry_destroy(registry);

    var scan = RegistryScan{};
    const listener = c.wl_registry_listener{
        .global = registryGlobal,
        .global_remove = registryGlobalRemove,
    };
    _ = c.wl_registry_add_listener(registry, &listener, &scan);
    _ = c.wl_display_roundtrip(display);

    var report = CapabilityReport{
        .state = .ready,
        .wayland_display = maybe_wayland_display,
        .xdg_runtime_dir = maybe_xdg_runtime_dir,
        .compositor_available = scan.compositor_available,
        .shm_available = scan.shm_available,
        .layer_shell_available = scan.layer_shell_available,
        .xdg_wm_base_available = scan.xdg_wm_base_available,
        .output_count = scan.output_count,
    };

    if (!scan.compositor_available) {
        report.state = .missing_wl_compositor;
    } else if (!scan.shm_available) {
        report.state = .missing_wl_shm;
    } else if (!scan.layer_shell_available) {
        report.state = .missing_layer_shell_protocol;
    }
    return .{
        .state = report.state,
        .wayland_display = report.wayland_display,
        .xdg_runtime_dir = report.xdg_runtime_dir,
        .compositor_available = report.compositor_available,
        .shm_available = report.shm_available,
        .layer_shell_available = report.layer_shell_available,
        .xdg_wm_base_available = report.xdg_wm_base_available,
        .output_count = report.output_count,
    };
}

pub fn printCapabilityReport() !void {
    const report = detectCapabilities();
    var buffer: [512]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buffer);
    const out = &writer.interface;
    try out.print("layer_shell_state={s}\n", .{@tagName(report.state)});
    try out.print("wayland_display={s}\n", .{report.wayland_display orelse ""});
    try out.print("xdg_runtime_dir={s}\n", .{report.xdg_runtime_dir orelse ""});
    try out.print("wl_compositor={s}\n", .{if (report.compositor_available) "yes" else "no"});
    try out.print("wl_shm={s}\n", .{if (report.shm_available) "yes" else "no"});
    try out.print("zwlr_layer_shell_v1={s}\n", .{if (report.layer_shell_available) "yes" else "no"});
    try out.print("xdg_wm_base={s}\n", .{if (report.xdg_wm_base_available) "yes" else "no"});
    try out.print("output_count={d}\n", .{report.output_count});
    try out.flush();
}

test "detectCapabilities reports a state" {
    const report = detectCapabilities();
    try std.testing.expect(@intFromEnum(report.state) <= @intFromEnum(CapabilityState.missing_layer_shell_protocol));
}

const RegistryScan = struct {
    compositor: ?*c.wl_compositor = null,
    shm: ?*c.wl_shm = null,
    layer_shell: ?*c.zwlr_layer_shell_v1 = null,
    first_output: ?*c.wl_output = null,
    compositor_available: bool = false,
    shm_available: bool = false,
    layer_shell_available: bool = false,
    xdg_wm_base_available: bool = false,
    output_count: u32 = 0,
};

fn registryGlobal(
    data: ?*anyopaque,
    registry: ?*c.wl_registry,
    name_id: u32,
    interface: [*c]const u8,
    version: u32,
) callconv(.c) void {
    const scan: *RegistryScan = @ptrCast(@alignCast(data.?));
    const name = std.mem.span(interface);
    if (std.mem.eql(u8, name, "wl_compositor")) {
        scan.compositor_available = true;
        if (scan.compositor == null) {
            scan.compositor = @ptrCast(c.wl_registry_bind(registry, name_id, &c.wl_compositor_interface, @min(version, 4)));
        }
    } else if (std.mem.eql(u8, name, "wl_shm")) {
        scan.shm_available = true;
        if (scan.shm == null) {
            scan.shm = @ptrCast(c.wl_registry_bind(registry, name_id, &c.wl_shm_interface, @min(version, 1)));
        }
    } else if (std.mem.eql(u8, name, "zwlr_layer_shell_v1")) {
        scan.layer_shell_available = true;
        if (scan.layer_shell == null) {
            scan.layer_shell = @ptrCast(c.wl_registry_bind(registry, name_id, &c.zwlr_layer_shell_v1_interface, @min(version, 4)));
        }
    } else if (std.mem.eql(u8, name, "xdg_wm_base")) {
        scan.xdg_wm_base_available = true;
    } else if (std.mem.eql(u8, name, "wl_output")) {
        scan.output_count += 1;
        if (scan.first_output == null) {
            scan.first_output = @ptrCast(c.wl_registry_bind(registry, name_id, &c.wl_output_interface, @min(version, 3)));
        }
    }
}

fn registryGlobalRemove(
    _: ?*anyopaque,
    _: ?*c.wl_registry,
    _: u32,
) callconv(.c) void {}

const LayerClient = struct {
    display: *c.wl_display,
    registry: *c.wl_registry,
    compositor: *c.wl_compositor,
    shm: *c.wl_shm,
    layer_shell: *c.zwlr_layer_shell_v1,
    output: ?*c.wl_output,
    runtime_bar: bar.Bar,
    surface: ?*c.wl_surface = null,
    layer_surface: ?*c.zwlr_layer_surface_v1 = null,
    buffer: ?Buffer = null,
    surface_state: SurfaceState = .{},
    dirty: DirtyState = .{ .initial = true },
    closed: bool = false,

    fn init(runtime_bar: bar.Bar) !LayerClient {
        const display = c.wl_display_connect(null) orelse return error.WaylandConnectFailed;
        errdefer c.wl_display_disconnect(display);

        const registry = c.wl_display_get_registry(display) orelse return error.WaylandConnectFailed;
        errdefer c.wl_registry_destroy(registry);

        var scan = RegistryScan{};
        const listener = c.wl_registry_listener{
            .global = registryGlobal,
            .global_remove = registryGlobalRemove,
        };
        _ = c.wl_registry_add_listener(registry, &listener, &scan);
        _ = c.wl_display_roundtrip(display);

        const compositor = scan.compositor orelse return error.MissingWlCompositor;
        const shm = scan.shm orelse return error.MissingWlShm;
        const layer_shell = scan.layer_shell orelse return error.MissingLayerShellProtocol;

        return .{
            .display = display,
            .registry = registry,
            .compositor = compositor,
            .shm = shm,
            .layer_shell = layer_shell,
            .output = scan.first_output,
            .runtime_bar = runtime_bar,
        };
    }

    fn deinit(self: *LayerClient) void {
        if (self.buffer) |*buffer| buffer.deinit();
        if (self.layer_surface) |layer_surface| c.zwlr_layer_surface_v1_destroy(layer_surface);
        if (self.surface) |surface| c.wl_surface_destroy(surface);
        if (self.output) |output| c.wl_output_destroy(output);
        c.zwlr_layer_shell_v1_destroy(self.layer_shell);
        c.wl_shm_destroy(self.shm);
        c.wl_compositor_destroy(self.compositor);
        c.wl_registry_destroy(self.registry);
        c.wl_display_disconnect(self.display);
    }

    fn createSurface(self: *LayerClient) !void {
        const surface = c.wl_compositor_create_surface(self.compositor) orelse return error.WaylandSurfaceCreateFailed;
        self.surface = surface;

        const surface_listener = c.wl_surface_listener{
            .enter = surfaceEnter,
            .leave = surfaceLeave,
            .preferred_buffer_scale = null,
            .preferred_buffer_transform = null,
        };
        _ = c.wl_surface_add_listener(surface, &surface_listener, self);

        const layer_surface = c.zwlr_layer_shell_v1_get_layer_surface(
            self.layer_shell,
            surface,
            self.output,
            c.ZWLR_LAYER_SHELL_V1_LAYER_TOP,
            "zbar",
        ) orelse return error.LayerShellSurfaceCreateFailed;
        self.layer_surface = layer_surface;

        const listener = c.zwlr_layer_surface_v1_listener{
            .configure = layerSurfaceConfigure,
            .closed = layerSurfaceClosed,
        };
        _ = c.zwlr_layer_surface_v1_add_listener(layer_surface, &listener, self);

        c.zwlr_layer_surface_v1_set_size(layer_surface, self.runtime_bar.preview_width_px, self.runtime_bar.height_px);
        c.zwlr_layer_surface_v1_set_anchor(layer_surface, anchorMask(self.runtime_bar.anchor));
        c.zwlr_layer_surface_v1_set_exclusive_zone(layer_surface, self.runtime_bar.height_px);
        c.zwlr_layer_surface_v1_set_keyboard_interactivity(layer_surface, c.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
        c.wl_surface_commit(surface);
        _ = c.wl_display_roundtrip(self.display);

        if (!self.surface_state.configured) return error.LayerShellConfigureTimeout;
        self.ackPendingConfigure();
        c.wl_surface_commit(surface);
        _ = c.wl_display_roundtrip(self.display);
    }

    fn presentFrame(self: *LayerClient, measurer: ui_text.Measurer, frame: modules.Frame, runtime_bar: bar.Bar) !void {
        const width = self.surface_state.width(self.runtime_bar);
        const height = self.surface_state.height(self.runtime_bar);
        if (self.buffer) |*old_buffer| old_buffer.deinit();
        self.buffer = try Buffer.init(self.shm, width, height);
        errdefer if (self.buffer) |*buffer| buffer.deinit();

        const scene = try ui_presenter.presentFrame(
            std.heap.page_allocator,
            runtime_bar,
            measurer,
            @floatFromInt(width),
            @floatFromInt(height),
            frame,
        );
        defer scene.deinit(std.heap.page_allocator);

        try self.buffer.?.paintScene(scene, runtime_bar, measurer);

        self.ackPendingConfigure();
        c.wl_surface_attach(self.surface, self.buffer.?.buffer, 0, 0);
        c.wl_surface_damage_buffer(self.surface, 0, 0, @intCast(width), @intCast(height));
        c.wl_surface_commit(self.surface);
        _ = c.wl_display_flush(self.display);
    }

    fn takeDirty(self: *LayerClient) DirtyState {
        return self.dirty.take();
    }

    fn ackPendingConfigure(self: *LayerClient) void {
        if (self.surface_state.pending_configure_serial) |serial| {
            c.zwlr_layer_surface_v1_ack_configure(self.layer_surface, serial);
            self.surface_state.pending_configure_serial = null;
        }
    }
};

const CairoTextMeasurer = struct {
    surface: *c.cairo_surface_t,
    cr: *c.cairo_t,
    font: ?CairoFont = null,

    fn init(runtime_bar: bar.Bar) !CairoTextMeasurer {
        const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, 1, 1) orelse return error.CairoSurfaceCreateFailed;
        if (c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) return error.CairoSurfaceCreateFailed;
        errdefer c.cairo_surface_destroy(surface);

        const cr = c.cairo_create(surface) orelse return error.CairoCreateFailed;
        if (c.cairo_status(cr) != c.CAIRO_STATUS_SUCCESS) return error.CairoCreateFailed;
        errdefer c.cairo_destroy(cr);

        var font = CairoFont.init(runtime_bar);
        errdefer if (font) |*value| value.deinit();

        configureCairoFont(cr, runtime_bar, if (font) |*value| value else null);

        return .{
            .surface = surface,
            .cr = cr,
            .font = font,
        };
    }

    fn deinit(self: *CairoTextMeasurer) void {
        if (self.font) |*font| font.deinit();
        c.cairo_destroy(self.cr);
        c.cairo_surface_destroy(self.surface);
    }

    fn measurer(self: *CairoTextMeasurer) ui_text.Measurer {
        return .{
            .context = @ptrCast(self),
            .vtable = &.{
                .measure = measureText,
            },
        };
    }

    fn measureText(context: *anyopaque, text: []const u8) !ui_text.Size {
        const self: *CairoTextMeasurer = @ptrCast(@alignCast(context));
        var extents: c.cairo_text_extents_t = undefined;
        _ = c.cairo_text_extents(self.cr, text.ptr, &extents);

        var font_extents: c.cairo_font_extents_t = undefined;
        _ = c.cairo_font_extents(self.cr, &font_extents);

        const width = @max(@as(f32, @floatCast(extents.x_advance)), @as(f32, @floatCast(extents.width)));
        const height = @max(@as(f32, @floatCast(font_extents.height)), @as(f32, @floatCast(extents.height)));
        return .{
            .width = @max(width, 1),
            .height = @max(height, 1),
        };
    }

    fn fontPtr(self: *CairoTextMeasurer) ?*CairoFont {
        return if (self.font) |*font| font else null;
    }
};

const SurfaceState = struct {
    configured: bool = false,
    pending_configure_serial: ?u32 = null,
    configured_width: u32 = 0,
    configured_height: u32 = 0,

    fn width(self: SurfaceState, runtime_bar: bar.Bar) u32 {
        return if (self.configured_width != 0) self.configured_width else runtime_bar.preview_width_px;
    }

    fn height(self: SurfaceState, runtime_bar: bar.Bar) u32 {
        return if (self.configured_height != 0) self.configured_height else runtime_bar.height_px;
    }
};

const DirtyState = packed struct(u8) {
    initial: bool = false,
    configure: bool = false,
    output: bool = false,
    reserved: u5 = 0,

    fn any(self: DirtyState) bool {
        return self.initial or self.configure or self.output;
    }

    fn take(self: *DirtyState) DirtyState {
        const current = self.*;
        self.* = .{};
        return current;
    }

    fn formatReason(self: DirtyState, buffer: []u8) ?[]const u8 {
        if (!self.any()) return null;

        var stream = std.io.fixedBufferStream(buffer);
        const writer = stream.writer();
        var first = true;

        if (self.initial) {
            writer.writeAll("initial") catch return "initial";
            first = false;
        }
        if (self.configure) {
            if (!first) writer.writeAll("+") catch {};
            writer.writeAll("configure") catch return if (first) "configure" else stream.getWritten();
            first = false;
        }
        if (self.output) {
            if (!first) writer.writeAll("+") catch {};
            writer.writeAll("output") catch return if (first) "output" else stream.getWritten();
        }

        return stream.getWritten();
    }
};

fn surfaceEnter(
    data: ?*anyopaque,
    _: ?*c.wl_surface,
    _: ?*c.wl_output,
) callconv(.c) void {
    const client: *LayerClient = @ptrCast(@alignCast(data.?));
    client.dirty.output = true;
}

fn surfaceLeave(
    data: ?*anyopaque,
    _: ?*c.wl_surface,
    _: ?*c.wl_output,
) callconv(.c) void {
    const client: *LayerClient = @ptrCast(@alignCast(data.?));
    client.dirty.output = true;
}

fn layerSurfaceConfigure(
    data: ?*anyopaque,
    _: ?*c.zwlr_layer_surface_v1,
    serial: u32,
    width: u32,
    height: u32,
) callconv(.c) void {
    const client: *LayerClient = @ptrCast(@alignCast(data.?));
    client.surface_state.configured = true;
    client.surface_state.pending_configure_serial = serial;
    if (client.surface_state.configured_width != width or client.surface_state.configured_height != height) {
        client.dirty.configure = true;
    }
    client.surface_state.configured_width = width;
    client.surface_state.configured_height = height;
}

fn layerSurfaceClosed(
    data: ?*anyopaque,
    _: ?*c.zwlr_layer_surface_v1,
) callconv(.c) void {
    const client: *LayerClient = @ptrCast(@alignCast(data.?));
    client.closed = true;
}

fn anchorMask(anchor: config.ThemeConfig.Anchor) u32 {
    return switch (anchor) {
        .top => c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT,
        .top_left => c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT,
        .top_right => c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT,
        .bottom => c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT,
        .bottom_left => c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT,
        .bottom_right => c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT,
    };
}

const Buffer = struct {
    fd: std.posix.fd_t,
    pool: *c.wl_shm_pool,
    buffer: *c.wl_buffer,
    data: []align(std.heap.page_size_min) u8,
    width: u32,
    height: u32,
    stride: u32,
    size: usize,

    fn init(shm: *c.wl_shm, width: u32, height: u32) !Buffer {
        const stride = width * 4;
        const size = stride * height;
        const fd = try std.posix.memfd_create("zbar-layer-buffer", 0x0001);
        errdefer std.posix.close(fd);

        try std.posix.ftruncate(fd, @intCast(size));
        const mapped = try std.posix.mmap(
            null,
            size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            fd,
            0,
        );
        errdefer std.posix.munmap(mapped);

        const pool = c.wl_shm_create_pool(shm, fd, @intCast(size)) orelse return error.WaylandShmPoolCreateFailed;
        errdefer c.wl_shm_pool_destroy(pool);

        const buffer = c.wl_shm_pool_create_buffer(
            pool,
            0,
            @intCast(width),
            @intCast(height),
            @intCast(stride),
            c.WL_SHM_FORMAT_ARGB8888,
        ) orelse return error.WaylandBufferCreateFailed;

        return .{
            .fd = fd,
            .pool = pool,
            .buffer = buffer,
            .data = mapped,
            .width = width,
            .height = height,
            .stride = stride,
            .size = size,
        };
    }

    fn deinit(self: *Buffer) void {
        c.wl_buffer_destroy(self.buffer);
        c.wl_shm_pool_destroy(self.pool);
        std.posix.munmap(self.data);
        std.posix.close(self.fd);
    }

    fn paintScene(self: *Buffer, scene: ui_presenter.Scene, runtime_bar: bar.Bar, measurer: ui_text.Measurer) !void {
        const surface = c.cairo_image_surface_create_for_data(
            self.data.ptr,
            c.CAIRO_FORMAT_ARGB32,
            @intCast(self.width),
            @intCast(self.height),
            @intCast(self.stride),
        );
        if (c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) return error.CairoSurfaceCreateFailed;
        defer c.cairo_surface_destroy(surface);

        const cr = c.cairo_create(surface) orelse return error.CairoCreateFailed;
        if (c.cairo_status(cr) != c.CAIRO_STATUS_SUCCESS) return error.CairoCreateFailed;
        defer c.cairo_destroy(cr);

        paintColor(cr, scene.clear_color);
        _ = c.cairo_paint(cr);

        configureCairoFont(cr, runtime_bar, fontFromMeasurer(measurer));
        configureCairoRenderQuality(cr);
        var font_extents: c.cairo_font_extents_t = undefined;
        _ = c.cairo_font_extents(cr, &font_extents);

        for (scene.draw_list.commands) |command| switch (command) {
            .fill_rect => |rect| {
                paintColor(cr, rect.color);
                roundedRectangle(
                    cr,
                    snapPixel(rect.x),
                    snapPixel(rect.y),
                    snapExtent(rect.width),
                    snapExtent(rect.height),
                    rect.corner_radius,
                );
                _ = c.cairo_fill(cr);
            },
            .stroke_rect => |rect| {
                drawStrokeRect(cr, rect);
            },
            .draw_text => |text| {
                paintColor(cr, text.color);
                const baseline_y = textBaselineY(text, font_extents);
                const x = ui_paint.alignedTextX(text, text.width);
                if (text.overflow == .clip) {
                    c.cairo_save(cr);
                    c.cairo_rectangle(
                        cr,
                        text.box_x,
                        text.box_y,
                        text.box_width,
                        text.box_height,
                    );
                    c.cairo_clip(cr);
                    defer c.cairo_restore(cr);
                }
                c.cairo_move_to(cr, snapPixel(x), snapBaseline(baseline_y));
                _ = c.cairo_show_text(cr, text.text.ptr);
            },
        };

        c.cairo_surface_flush(surface);
    }
};

fn paintColor(cr: *c.cairo_t, rgba: ui_style.Rgba) void {
    c.cairo_set_source_rgba(
        cr,
        @as(f64, @floatFromInt(rgba.r)) / 255.0,
        @as(f64, @floatFromInt(rgba.g)) / 255.0,
        @as(f64, @floatFromInt(rgba.b)) / 255.0,
        @as(f64, @floatFromInt(rgba.a)) / 255.0,
    );
}

fn configureCairoFont(cr: *c.cairo_t, runtime_bar: bar.Bar, font: ?*CairoFont) void {
    if (font) |loaded| {
        c.cairo_set_font_face(cr, loaded.font_face);
    } else {
        c.cairo_select_font_face(cr, "Sans", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
    }
    c.cairo_set_font_size(cr, @floatFromInt(runtime_bar.font_points));
}

fn configureCairoRenderQuality(cr: *c.cairo_t) void {
    c.cairo_set_antialias(cr, c.CAIRO_ANTIALIAS_BEST);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    const options = c.cairo_font_options_create() orelse return;
    defer c.cairo_font_options_destroy(options);

    c.cairo_font_options_set_antialias(options, c.CAIRO_ANTIALIAS_SUBPIXEL);
    c.cairo_font_options_set_subpixel_order(options, c.CAIRO_SUBPIXEL_ORDER_RGB);
    c.cairo_font_options_set_hint_style(options, c.CAIRO_HINT_STYLE_SLIGHT);
    c.cairo_font_options_set_hint_metrics(options, c.CAIRO_HINT_METRICS_ON);
    c.cairo_set_font_options(cr, options);
}

fn textBaselineY(text: @import("paint.zig").DrawText, font_extents: c.cairo_font_extents_t) f64 {
    const ascent = @as(f32, @floatCast(font_extents.ascent));
    const descent = @as(f32, @floatCast(font_extents.descent));
    const content_height = ascent + descent;
    const top = ui_paint.alignedTextY(text, content_height);
    return @as(f64, top + ascent);
}

fn roundedRectangle(cr: *c.cairo_t, x: f64, y: f64, width: f64, height: f64, radius: f64) void {
    const effective_radius = ui_paint.effectiveRadius(@floatCast(width), @floatCast(height), @floatCast(radius));
    const right = x + width;
    const bottom = y + height;

    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, right - effective_radius, y + effective_radius, effective_radius, -std.math.pi * 0.5, 0);
    c.cairo_arc(cr, right - effective_radius, bottom - effective_radius, effective_radius, 0, std.math.pi * 0.5);
    c.cairo_arc(cr, x + effective_radius, bottom - effective_radius, effective_radius, std.math.pi * 0.5, std.math.pi);
    c.cairo_arc(cr, x + effective_radius, y + effective_radius, effective_radius, std.math.pi, std.math.pi * 1.5);
    c.cairo_close_path(cr);
}

fn drawStrokeRect(cr: *c.cairo_t, rect: @import("paint.zig").StrokeRect) void {
    if (rect.line_width <= 0 or rect.color.a == 0) return;

    paintColor(cr, rect.color);
    c.cairo_set_line_width(cr, rect.line_width);
    roundedRectangle(
        cr,
        snapPixel(rect.x) + (rect.line_width * 0.5),
        snapPixel(rect.y) + (rect.line_width * 0.5),
        @max(snapExtent(rect.width) - rect.line_width, 1.0),
        @max(snapExtent(rect.height) - rect.line_width, 1.0),
        rect.corner_radius,
    );
    _ = c.cairo_stroke(cr);
}

fn snapPixel(value: f32) f64 {
    return @as(f64, @floatCast(@round(value))) + 0.5;
}

fn snapExtent(value: f32) f64 {
    return @max(@as(f64, @floatCast(@round(value))), 1.0);
}

fn snapBaseline(value: f64) f64 {
    return @round(value * 2.0) / 2.0;
}

fn fontFromMeasurer(measurer: ui_text.Measurer) ?*CairoFont {
    const context = measurer.context;
    const cairo_measurer: *CairoTextMeasurer = @ptrCast(@alignCast(context));
    return cairo_measurer.fontPtr();
}

fn selectFontPath(runtime_bar: bar.Bar) ?[]const u8 {
    const candidates = [_][]const u8{
        runtime_bar.font_path,
        runtime_bar.font_fallback_path,
        runtime_bar.font_fallback_path_2,
    };
    for (candidates) |path| {
        if (path.len == 0) continue;
        return path;
    }
    return null;
}
