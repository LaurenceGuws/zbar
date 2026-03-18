const std = @import("std");
const bar = @import("../bar/mod.zig");
const config = @import("../config/mod.zig");
const modules = @import("../modules/mod.zig");
const render = @import("../render/mod.zig");
const ui_layout = @import("layout.zig");
const ui_paint = @import("paint.zig");
const ui_presenter = @import("presenter.zig");
const ui_surface = @import("surface.zig");
const ui_style = @import("style.zig");
const ui_text = @import("text.zig");
const wm = @import("../wm/mod.zig");
const RunOptions = @import("../app/state.zig").RunOptions;
const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
});

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
        var ui = try PreviewUi.init(self.runtime_bar);
        defer ui.deinit();

        var frame_index: u32 = 0;
        var previous_snapshot: ?wm.Snapshot = null;
        var previous_signature: ?render.Renderer.Signature = null;
        var redraw_count: usize = 0;
        var suppressed_count: usize = 0;

        while (!ui.should_quit) : (frame_index += 1) {
            ui.pollEvents();

            const snapshot = self.backend.snapshot();
            const snapshot_changed = if (previous_snapshot) |prior| !wm.Snapshot.eql(prior, snapshot) else true;
            const frame = try self.registry.collect(std.heap.page_allocator, self.cfg.bar, .{
                .snapshot = snapshot,
                .snapshot_changed = snapshot_changed,
                .provider_defaults = self.cfg.provider_defaults,
            });
            defer frame.deinit(std.heap.page_allocator);
            previous_snapshot = snapshot;

            const signature = self.renderer.signature(self.runtime_bar, snapshot, frame);
            const prior_signature = previous_signature;
            const changed = prior_signature == null or prior_signature.?.full() != signature.full();
            if (changed) {
                redraw_count += 1;
                try ui.draw(self.runtime_bar, frame);
                previous_signature = signature;
            } else {
                suppressed_count += 1;
            }

            if (self.options.debug_runtime) {
                try printRuntimeDebug(
                    self.cfg.bar.effectiveTickMs(),
                    self.registry,
                    self.options,
                    frame_index,
                    redraw_count,
                    suppressed_count,
                    changed,
                    signature,
                    prior_signature,
                );
            }

            if (self.options.once) break;
            if (self.options.max_frames) |limit| {
                if (frame_index + 1 >= limit) break;
            }
            self.backend.waitForChange(sleepMs(self.options, self.registry, self.cfg.bar.effectiveTickMs()));
        }
    }
};

const PreviewUi = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    font: *c.TTF_Font,
    should_quit: bool = false,

    fn init(runtime_bar: bar.Bar) !PreviewUi {
        const surface = ui_surface.SurfaceSpec.init(runtime_bar);
        if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SdlInitFailed;
        errdefer c.SDL_Quit();
        if (!c.TTF_Init()) return error.TtfInitFailed;
        errdefer c.TTF_Quit();

        var window: ?*c.SDL_Window = null;
        var renderer: ?*c.SDL_Renderer = null;
        if (!c.SDL_CreateWindowAndRenderer(surface.title.ptr, @intCast(surface.widthPx()), surface.height_px, c.SDL_WINDOW_RESIZABLE, &window, &renderer)) {
            return error.SdlWindowCreateFailed;
        }
        errdefer {
            if (renderer) |value| c.SDL_DestroyRenderer(value);
            if (window) |value| c.SDL_DestroyWindow(value);
        }

        _ = c.SDL_SetWindowAlwaysOnTop(window.?, surface.always_on_top);
        applySurfacePlacement(window.?, surface);

        const font = try openFont(runtime_bar);
        errdefer c.TTF_CloseFont(font);

        return .{
            .window = window.?,
            .renderer = renderer.?,
            .font = font,
        };
    }

    fn deinit(self: *PreviewUi) void {
        c.TTF_CloseFont(self.font);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.TTF_Quit();
        c.SDL_Quit();
    }

    fn pollEvents(self: *PreviewUi) void {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => self.should_quit = true,
                c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => self.should_quit = true,
                else => {},
            }
        }
    }

    fn draw(self: *PreviewUi, runtime_bar: bar.Bar, frame: modules.Frame) !void {
        const size = self.windowSize();
        const scene = try ui_presenter.presentFrame(
            std.heap.page_allocator,
            runtime_bar,
            self.measurer(),
            size.width,
            size.height,
            frame,
        );
        defer scene.deinit(std.heap.page_allocator);

        const background = toColor(scene.clear_color);
        try sdlBool(c.SDL_SetRenderDrawColor(self.renderer, background.r, background.g, background.b, background.a));
        try sdlBool(c.SDL_RenderClear(self.renderer));

        try self.executeDrawList(scene.draw_list);

        try sdlBool(c.SDL_RenderPresent(self.renderer));
    }

    fn executeDrawList(self: *PreviewUi, draw_list: ui_paint.DrawList) !void {
        for (draw_list.commands) |command| switch (command) {
            .fill_rect => |rect| {
                const sdl_rect = c.SDL_FRect{ .x = rect.x, .y = rect.y, .w = rect.width, .h = rect.height };
                const color = toColor(rect.color);
                try sdlBool(c.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, color.a));
                try sdlBool(c.SDL_RenderFillRect(self.renderer, &sdl_rect));
            },
            .draw_text => |text| {
                const rendered = try self.renderText(text.text, toColor(text.color));
                defer rendered.deinit(self.renderer);
                const dst = c.SDL_FRect{ .x = text.x, .y = text.y, .w = text.width, .h = text.height };
                try sdlBool(c.SDL_RenderTexture(self.renderer, rendered.texture, null, &dst));
            },
        };
    }

    fn renderText(self: *PreviewUi, text: []const u8, color: Color) !RenderedText {
        const surface = c.TTF_RenderText_Blended(self.font, text.ptr, text.len, color.toSdl());
        if (surface == null) return error.TtfRenderFailed;
        defer c.SDL_DestroySurface(surface);

        const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface);
        if (texture == null) return error.SdlTextureCreateFailed;

        return .{
            .texture = texture,
            .width = @floatFromInt(surface.*.w),
            .height = @floatFromInt(surface.*.h),
        };
    }

    fn measurer(self: *PreviewUi) ui_text.Measurer {
        return .{
            .context = @ptrCast(self),
            .vtable = &.{
                .measure = measureText,
            },
        };
    }

    fn measureText(context: *anyopaque, text: []const u8) !ui_text.Size {
        const self: *PreviewUi = @ptrCast(@alignCast(context));
        var text_w: c_int = 0;
        var text_h: c_int = 0;
        if (!c.TTF_GetStringSize(self.font, text.ptr, text.len, &text_w, &text_h)) {
            return error.TtfMeasureFailed;
        }
        return .{
            .width = @floatFromInt(text_w),
            .height = @floatFromInt(text_h),
        };
    }

    fn windowSize(self: *PreviewUi) struct { width: f32, height: f32 } {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = c.SDL_GetWindowSize(self.window, &w, &h);
        return .{ .width = @floatFromInt(w), .height = @floatFromInt(h) };
    }
};

const RenderedText = struct {
    texture: *c.SDL_Texture,
    width: f32,
    height: f32,

    fn deinit(self: RenderedText, renderer: *c.SDL_Renderer) void {
        _ = renderer;
        c.SDL_DestroyTexture(self.texture);
    }
};

const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    fn toSdl(self: Color) c.SDL_Color {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = self.a };
    }
};

fn openFont(runtime_bar: bar.Bar) !*c.TTF_Font {
    const candidates = [_][]const u8{
        runtime_bar.font_path,
        runtime_bar.font_fallback_path,
        runtime_bar.font_fallback_path_2,
    };
    for (candidates) |path| {
        if (path.len == 0) continue;
        const font = c.TTF_OpenFont(path.ptr, @floatFromInt(runtime_bar.font_points));
        if (font != null) return font.?;
    }
    return error.TtfOpenFontFailed;
}

fn toColor(rgba: ui_style.Rgba) Color {
    return .{ .r = rgba.r, .g = rgba.g, .b = rgba.b, .a = rgba.a };
}

fn sdlBool(ok: bool) !void {
    if (!ok) return error.SdlCallFailed;
}

fn sleepMs(options: RunOptions, registry: *modules.Registry, fallback_ms: u64) u64 {
    if (options.tick_ms_override) |tick_ms| return tick_ms;
    return registry.nextWakeDelayMs(fallback_ms);
}

fn applySurfacePlacement(window: *c.SDL_Window, surface: ui_surface.SurfaceSpec) void {
    const display_mode = c.SDL_GetDesktopDisplayMode(c.SDL_GetPrimaryDisplay());
    if (display_mode == null) return;

    const desktop_w = display_mode.*.w;
    const desktop_h = display_mode.*.h;
    const width = @as(c_int, @intCast(surface.widthPx()));
    const height = @as(c_int, @intCast(surface.height_px));

    const x: c_int = switch (surface.placement.horizontal) {
        .left => 0,
        .center => @max(0, @divTrunc(desktop_w - width, 2)),
        .right => @max(0, desktop_w - width),
    };
    const y: c_int = switch (surface.placement.vertical) {
        .top => 0,
        .bottom => @max(0, desktop_h - height),
    };

    _ = c.SDL_SetWindowPosition(window, x, y);
}

fn printRuntimeDebug(
    fallback_ms: u64,
    registry: *modules.Registry,
    options: RunOptions,
    frame_index: u32,
    redraw_count: usize,
    suppressed_count: usize,
    changed: bool,
    signature: render.Renderer.Signature,
    previous_signature: ?render.Renderer.Signature,
) !void {
    const stats = registry.runtimeStats(fallback_ms);
    const sleep_ms = if (options.tick_ms_override) |tick_ms| tick_ms else stats.next_wake_delay_ms orelse fallback_ms;
    const layout_changed = previous_signature == null or previous_signature.?.layout != signature.layout;
    const display_changed = previous_signature == null or previous_signature.?.display_content != signature.display_content;
    const semantic_changed = previous_signature == null or previous_signature.?.semantic_content != signature.semantic_content;

    var buffer: [256]u8 = undefined;
    var writer = std.fs.File.stderr().writer(&buffer);
    const err = &writer.interface;
    try err.print(
        "debug frame={d} redraw={s} layout_changed={s} display_changed={s} semantic_changed={s} redraw_count={d} suppressed={d} cache={d} hits={d} misses={d} timed_hits={d} timed_misses={d} snapshot_hits={d} snapshot_misses={d} timed={d} snapshot={d} sleep_ms={d}\n",
        .{
            frame_index + 1,
            if (changed) "yes" else "no",
            if (layout_changed) "yes" else "no",
            if (display_changed) "yes" else "no",
            if (semantic_changed) "yes" else "no",
            redraw_count,
            suppressed_count,
            stats.cache_entries,
            stats.cache_hits,
            stats.cache_misses,
            stats.timed_cache_hits,
            stats.timed_cache_misses,
            stats.snapshot_cache_hits,
            stats.snapshot_cache_misses,
            stats.timed_entries,
            stats.snapshot_entries,
            sleep_ms,
        },
    );
    try err.flush();
}
