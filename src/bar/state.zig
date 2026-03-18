const config = @import("../config/mod.zig");

pub const Bar = struct {
    height_px: u16,
    section_gap_px: u16,
    background: []u8,
    foreground: []u8,
    segment_background: []u8,
    accent_background: []u8,
    subtle_background: []u8,
    warning_background: []u8,
    accent_foreground: []u8,
    font_path: []u8,
    font_fallback_path: []u8,
    font_fallback_path_2: []u8,
    preview_width_px: u16,
    anchor: config.ThemeConfig.Anchor,
    horizontal_padding_px: u16,
    segment_padding_x_px: u16,
    segment_padding_y_px: u16,
    font_points: u16,

    pub fn init(cfg: config.BarConfig) Bar {
        return .{
            .height_px = cfg.height_px,
            .section_gap_px = cfg.section_gap_px,
            .background = cfg.background,
            .foreground = cfg.foreground,
            .segment_background = cfg.theme.segment_background,
            .accent_background = cfg.theme.accent_background,
            .subtle_background = cfg.theme.subtle_background,
            .warning_background = cfg.theme.warning_background,
            .accent_foreground = cfg.theme.accent_foreground,
            .font_path = cfg.theme.font_path,
            .font_fallback_path = cfg.theme.font_fallback_path,
            .font_fallback_path_2 = cfg.theme.font_fallback_path_2,
            .preview_width_px = cfg.theme.preview_width_px,
            .anchor = cfg.theme.anchor,
            .horizontal_padding_px = cfg.theme.horizontal_padding_px,
            .segment_padding_x_px = cfg.theme.segment_padding_x_px,
            .segment_padding_y_px = cfg.theme.segment_padding_y_px,
            .font_points = cfg.theme.font_points,
        };
    }
};

test "bar config preserves height" {
    var cfg = config.defaultConfig();
    defer cfg.deinit(@import("std").heap.page_allocator);
    const bar_cfg = cfg.bar;
    const runtime_bar = Bar.init(bar_cfg);
    try @import("std").testing.expectEqual(@as(u16, 28), runtime_bar.height_px);
}
