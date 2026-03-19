const std = @import("std");
const bar = @import("../bar/mod.zig");
const config = @import("../config/mod.zig");
const modules = @import("../modules/mod.zig");
const render = @import("../render/mod.zig");
const ui_presenter = @import("presenter.zig");
const ui_runtime = @import("runtime.zig");
const ui_style = @import("style.zig");
const ui_text = @import("text.zig");
const wm = @import("../wm/mod.zig");
const RunOptions = @import("../app/state.zig").RunOptions;
const c = @cImport({
    @cInclude("cairo/cairo.h");
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
    last_redraw_reason: ?[]const u8 = null,

    fn init(runtime_bar: bar.Bar, backend: wm.Backend) !LayerUi {
        var client = try LayerClient.init(runtime_bar);
        errdefer client.deinit();
        try client.createSurface();
        return .{
            .client = client,
            .backend = backend,
        };
    }

    fn deinit(self: *LayerUi) void {
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
        _ = runtime_bar;
        try self.client.presentFrame(frame);
    }

    fn forceRedraw(context: *anyopaque) bool {
        const self: *LayerUi = @ptrCast(@alignCast(context));
        const dirty = self.client.takeDirty();
        self.last_redraw_reason = dirty.primaryReason();
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

    fn presentFrame(self: *LayerClient, frame: modules.Frame) !void {
        const width = self.surface_state.width(self.runtime_bar);
        const height = self.surface_state.height(self.runtime_bar);
        if (self.buffer) |*old_buffer| old_buffer.deinit();
        self.buffer = try Buffer.init(self.shm, width, height);
        errdefer if (self.buffer) |*buffer| buffer.deinit();

        const scene = try ui_presenter.presentFrame(
            std.heap.page_allocator,
            self.runtime_bar,
            approxMeasurer(),
            @floatFromInt(width),
            @floatFromInt(height),
            frame,
        );
        defer scene.deinit(std.heap.page_allocator);

        try self.buffer.?.paintScene(scene, self.runtime_bar);

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

    fn primaryReason(self: DirtyState) ?[]const u8 {
        if (self.initial) return "initial";
        if (self.configure) return "configure";
        if (self.output) return "output";
        return null;
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

    fn paintScene(self: *Buffer, scene: ui_presenter.Scene, runtime_bar: bar.Bar) !void {
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

        c.cairo_select_font_face(cr, "Sans", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
        c.cairo_set_font_size(cr, @floatFromInt(runtime_bar.font_points));

        for (scene.draw_list.commands) |command| switch (command) {
            .fill_rect => |rect| {
                paintColor(cr, rect.color);
                c.cairo_rectangle(cr, rect.x, rect.y, rect.width, rect.height);
                _ = c.cairo_fill(cr);
            },
            .draw_text => |text| {
                paintColor(cr, text.color);
                c.cairo_move_to(cr, text.x, text.y + text.height - 2);
                _ = c.cairo_show_text(cr, text.text.ptr);
            },
        };

        c.cairo_surface_flush(surface);
    }
};

fn approxMeasurer() ui_text.Measurer {
    return .{
        .context = undefined,
        .vtable = &.{
            .measure = measureApproxText,
        },
    };
}

fn measureApproxText(_: *anyopaque, text: []const u8) !ui_text.Size {
    const width = @as(f32, @floatFromInt(@max(text.len, 1) * 8));
    return .{ .width = width, .height = 16 };
}

fn paintColor(cr: *c.cairo_t, rgba: ui_style.Rgba) void {
    c.cairo_set_source_rgba(
        cr,
        @as(f64, @floatFromInt(rgba.r)) / 255.0,
        @as(f64, @floatFromInt(rgba.g)) / 255.0,
        @as(f64, @floatFromInt(rgba.b)) / 255.0,
        @as(f64, @floatFromInt(rgba.a)) / 255.0,
    );
}
