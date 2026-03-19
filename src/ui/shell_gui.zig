const std = @import("std");
const bar = @import("../bar/mod.zig");
const config = @import("../config/mod.zig");
const modules = @import("../modules/mod.zig");
const render = @import("../render/mod.zig");
const ui_layout = @import("layout.zig");
const ui_paint = @import("paint.zig");
const ui_presenter = @import("presenter.zig");
const ui_runtime = @import("runtime.zig");
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
        const state = self.runtimeState();
        try ui_runtime.runShell(&state, ui.hooks());
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

    fn hooks(self: *PreviewUi) ui_runtime.Hooks {
        return .{
            .context = @ptrCast(self),
            .vtable = &.{
                .isQuitRequested = isQuitRequested,
                .beforeFrame = beforeFrame,
                .drawFrame = drawFrame,
            },
        };
    }

    fn isQuitRequested(context: *anyopaque) bool {
        const self: *PreviewUi = @ptrCast(@alignCast(context));
        return self.should_quit;
    }

    fn beforeFrame(context: *anyopaque) void {
        const self: *PreviewUi = @ptrCast(@alignCast(context));
        self.pollEvents();
    }

    fn drawFrame(context: *anyopaque, runtime_bar: bar.Bar, frame: modules.Frame) !void {
        const self: *PreviewUi = @ptrCast(@alignCast(context));
        try self.draw(runtime_bar, frame);
    }

    fn executeDrawList(self: *PreviewUi, draw_list: ui_paint.DrawList) !void {
        for (draw_list.commands) |command| switch (command) {
            .fill_rect => |rect| {
                const color = toColor(rect.color);
                try sdlBool(c.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, color.a));
                if (rect.corner_radius > 0) {
                    try self.renderRoundedFill(rect);
                } else {
                    const sdl_rect = c.SDL_FRect{ .x = rect.x, .y = rect.y, .w = rect.width, .h = rect.height };
                    try sdlBool(c.SDL_RenderFillRect(self.renderer, &sdl_rect));
                }
            },
            .stroke_rect => |rect| {
                const color = toColor(rect.color);
                try sdlBool(c.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, color.a));
                if (rect.corner_radius > 0) {
                    try self.renderRoundedStroke(rect);
                } else {
                    const sdl_rect = c.SDL_FRect{ .x = rect.x, .y = rect.y, .w = rect.width, .h = rect.height };
                    try sdlBool(c.SDL_RenderRect(self.renderer, &sdl_rect));
                }
            },
            .draw_text => |text| {
                const rendered = try self.renderText(text.text, toColor(text.color));
                defer rendered.deinit(self.renderer);
                const dst = c.SDL_FRect{
                    .x = ui_paint.alignedTextX(text, rendered.width),
                    .y = ui_paint.alignedTextY(text, rendered.height),
                    .w = rendered.width,
                    .h = rendered.height,
                };
                if (text.overflow == .clip) {
                    const clip = c.SDL_Rect{
                        .x = @intFromFloat(@round(text.box_x)),
                        .y = @intFromFloat(@round(text.box_y)),
                        .w = @intFromFloat(@round(text.box_width)),
                        .h = @intFromFloat(@round(text.box_height)),
                    };
                    _ = c.SDL_SetRenderClipRect(self.renderer, &clip);
                    defer _ = c.SDL_SetRenderClipRect(self.renderer, null);
                }
                try sdlBool(c.SDL_RenderTexture(self.renderer, rendered.texture, null, &dst));
            },
        };
    }

    fn renderRoundedFill(self: *PreviewUi, rect: ui_paint.FillRect) !void {
        const radius = ui_paint.effectiveRadius(rect.width, rect.height, rect.corner_radius);
        const diameter = radius * 2.0;
        const center_w = @max(rect.width - diameter, 0);
        const center_h = @max(rect.height - diameter, 0);

        const center = c.SDL_FRect{ .x = rect.x + radius, .y = rect.y, .w = center_w, .h = rect.height };
        const left = c.SDL_FRect{ .x = rect.x, .y = rect.y + radius, .w = radius, .h = center_h };
        const right = c.SDL_FRect{ .x = rect.x + rect.width - radius, .y = rect.y + radius, .w = radius, .h = center_h };
        try sdlBool(c.SDL_RenderFillRect(self.renderer, &center));
        try sdlBool(c.SDL_RenderFillRect(self.renderer, &left));
        try sdlBool(c.SDL_RenderFillRect(self.renderer, &right));

        try self.renderQuarterCircles(rect.x + radius, rect.y + radius, radius, .fill);
        try self.renderQuarterCircles(rect.x + rect.width - radius, rect.y + radius, radius, .fill_top_right);
        try self.renderQuarterCircles(rect.x + radius, rect.y + rect.height - radius, radius, .fill_bottom_left);
        try self.renderQuarterCircles(rect.x + rect.width - radius, rect.y + rect.height - radius, radius, .fill_bottom_right);
    }

    fn renderRoundedStroke(self: *PreviewUi, rect: ui_paint.StrokeRect) !void {
        if (rect.line_width <= 0) return;
        const radius = ui_paint.effectiveRadius(rect.width, rect.height, rect.corner_radius);
        if (radius <= 0) {
            const sdl_rect = c.SDL_FRect{ .x = rect.x, .y = rect.y, .w = rect.width, .h = rect.height };
            try sdlBool(c.SDL_RenderRect(self.renderer, &sdl_rect));
            return;
        }

        const half_line = rect.line_width * 0.5;
        const top = c.SDL_FRect{ .x = rect.x + radius, .y = rect.y, .w = @max(rect.width - (radius * 2.0), 0), .h = rect.line_width };
        const bottom = c.SDL_FRect{ .x = rect.x + radius, .y = rect.y + rect.height - rect.line_width, .w = @max(rect.width - (radius * 2.0), 0), .h = rect.line_width };
        const left = c.SDL_FRect{ .x = rect.x, .y = rect.y + radius, .w = rect.line_width, .h = @max(rect.height - (radius * 2.0), 0) };
        const right = c.SDL_FRect{ .x = rect.x + rect.width - rect.line_width, .y = rect.y + radius, .w = rect.line_width, .h = @max(rect.height - (radius * 2.0), 0) };
        try sdlBool(c.SDL_RenderFillRect(self.renderer, &top));
        try sdlBool(c.SDL_RenderFillRect(self.renderer, &bottom));
        try sdlBool(c.SDL_RenderFillRect(self.renderer, &left));
        try sdlBool(c.SDL_RenderFillRect(self.renderer, &right));

        try self.renderArcOutline(rect.x + radius, rect.y + radius, @max(radius - half_line, 0.5), rect.line_width, .top_left);
        try self.renderArcOutline(rect.x + rect.width - radius, rect.y + radius, @max(radius - half_line, 0.5), rect.line_width, .top_right);
        try self.renderArcOutline(rect.x + radius, rect.y + rect.height - radius, @max(radius - half_line, 0.5), rect.line_width, .bottom_left);
        try self.renderArcOutline(rect.x + rect.width - radius, rect.y + rect.height - radius, @max(radius - half_line, 0.5), rect.line_width, .bottom_right);
    }

    const QuarterMode = enum {
        fill,
        fill_top_right,
        fill_bottom_left,
        fill_bottom_right,
    };

    const ArcQuadrant = enum {
        top_left,
        top_right,
        bottom_left,
        bottom_right,
    };

    fn renderQuarterCircles(self: *PreviewUi, center_x: f32, center_y: f32, radius: f32, mode: QuarterMode) !void {
        const radius_i = @as(i32, @intFromFloat(@round(radius)));
        var y: i32 = 0;
        while (y <= radius_i) : (y += 1) {
            const dy = @as(f32, @floatFromInt(y));
            const x_extent = @sqrt(@max((radius * radius) - (dy * dy), 0));
            const left_x = center_x - x_extent;
            const right_x = center_x + x_extent;

            switch (mode) {
                .fill => {
                    try self.drawHorizontalSpan(left_x, center_y - dy, center_x, center_y - dy);
                    try self.drawHorizontalSpan(left_x, center_y + dy, center_x, center_y + dy);
                },
                .fill_top_right => {
                    try self.drawHorizontalSpan(center_x, center_y - dy, right_x, center_y - dy);
                    try self.drawHorizontalSpan(center_x, center_y + dy, right_x, center_y + dy);
                },
                .fill_bottom_left => {
                    try self.drawHorizontalSpan(left_x, center_y - dy, center_x, center_y - dy);
                    try self.drawHorizontalSpan(left_x, center_y + dy, center_x, center_y + dy);
                },
                .fill_bottom_right => {
                    try self.drawHorizontalSpan(center_x, center_y - dy, right_x, center_y - dy);
                    try self.drawHorizontalSpan(center_x, center_y + dy, right_x, center_y + dy);
                },
            }
        }
    }

    fn renderArcOutline(self: *PreviewUi, center_x: f32, center_y: f32, radius: f32, line_width: f32, quadrant: ArcQuadrant) !void {
        const radius_i = @as(i32, @intFromFloat(@round(radius + (line_width * 0.5))));
        var y: i32 = 0;
        while (y <= radius_i) : (y += 1) {
            const dy = @as(f32, @floatFromInt(y));
            const x_extent = @sqrt(@max((radius * radius) - @min(dy * dy, radius * radius), 0));
            const thickness = @max(line_width, 1);
            switch (quadrant) {
                .top_left => try self.drawPointSquare(center_x - x_extent, center_y - dy, thickness),
                .top_right => try self.drawPointSquare(center_x + x_extent, center_y - dy, thickness),
                .bottom_left => try self.drawPointSquare(center_x - x_extent, center_y + dy, thickness),
                .bottom_right => try self.drawPointSquare(center_x + x_extent, center_y + dy, thickness),
            }
        }
    }

    fn drawHorizontalSpan(self: *PreviewUi, x0: f32, y0: f32, x1: f32, y1: f32) !void {
        try sdlBool(c.SDL_RenderLine(self.renderer, x0, y0, x1, y1));
    }

    fn drawPointSquare(self: *PreviewUi, x: f32, y: f32, size: f32) !void {
        const rect = c.SDL_FRect{
            .x = x - (size * 0.5),
            .y = y - (size * 0.5),
            .w = size,
            .h = size,
        };
        try sdlBool(c.SDL_RenderFillRect(self.renderer, &rect));
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
fn sdlBool(ok: bool) !void {
    if (!ok) return error.SdlCallFailed;
}
