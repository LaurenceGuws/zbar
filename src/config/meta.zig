const std = @import("std");

pub const ScalarKind = enum {
    string,
    integer,
    number,
    boolean,
};

pub const FieldMeta = struct {
    name: []const u8,
    kind: ScalarKind,
    optional: bool = true,
    doc: []const u8 = "",
    min_int: ?i64 = null,
    max_int: ?i64 = null,
    min_number: ?f64 = null,
    max_number: ?f64 = null,
    enum_values: []const []const u8 = &.{},
    snippet_value: []const u8 = "",
};

pub const FieldOverride = struct {
    field_name: []const u8,
    doc: []const u8 = "",
    optional: ?bool = null,
    min_int: ?i64 = null,
    max_int: ?i64 = null,
    min_number: ?f64 = null,
    max_number: ?f64 = null,
    snippet_value: []const u8 = "",
};

pub const ProviderMeta = struct {
    id: []const u8,
    class_name: []const u8,
    settings_class_name: []const u8,
    doc: []const u8,
    settings: []const FieldMeta,
    output_fields: []const FieldMeta = &.{},
};

pub const PresentationStyle = enum {
    template,
    passthrough_text,
};

pub const PresentationMeta = struct {
    provider_id: []const u8,
    style: PresentationStyle,
    default_template: []const u8 = "",
    source_format: []const u8 = "",
    unit_field: ?[]const u8 = null,
    example_format: []const u8 = "",
    unit_template_gib: []const u8 = "",
    unit_template_mib: []const u8 = "",
    supports_truncation: bool = false,
    truncation_setting_key: ?[]const u8 = null,
};

pub const ProviderSpec = struct {
    provider: ProviderMeta,
    presentation: PresentationMeta,
};

const PresentationArgs = struct {
    style: PresentationStyle,
    default_template: []const u8 = "",
    source_format: []const u8 = "",
    unit_field: ?[]const u8 = null,
    example_format: []const u8 = "",
    unit_template_gib: []const u8 = "",
    unit_template_mib: []const u8 = "",
    supports_truncation: bool = false,
    truncation_setting_key: ?[]const u8 = null,
};

const MemoryUnit = enum {
    gib,
    mib,
};

const ClockTimezone = enum {
    local,
    utc,
};

pub const ThemeAnchor = enum {
    top,
    @"top-left",
    @"top-right",
    bottom,
    @"bottom-left",
    @"bottom-right",
};

const BarTheme = struct {
    segment_background: []const u8,
    accent_background: []const u8,
    subtle_background: []const u8,
    warning_background: []const u8,
    accent_foreground: []const u8,
    font_path: []const u8,
    font_fallback_path: []const u8,
    font_fallback_path_2: []const u8,
    preview_width_px: i64,
    anchor: ThemeAnchor,
    horizontal_padding_px: i64,
    segment_padding_x_px: i64,
    segment_padding_y_px: i64,
    font_points: i64,
    segment_radius_px: i64,
    edge_line_px: i64,
    edge_shadow_alpha: i64,
    segment_border_px: i64,
    segment_border_alpha: i64,
};

const BarVisuals = struct {
    height_px: i64,
    section_gap_px: i64,
    background: []const u8,
    foreground: []const u8,
};

const WorkspaceSettings = struct {
    show_empty: bool,
};

const WorkspaceOutput = struct {
    focused: i64,
    total: i64,
};

const ModeSettings = struct {};

const ModeOutput = struct {
    compositor: []const u8,
};

const WindowSettings = struct {
    truncate: bool,
};

const WindowOutput = struct {
    title: []const u8,
};

const CpuSettings = struct {
    usage: i64,
    sample_window: i64,
};

const CpuOutput = struct {
    usage: i64,
};

const MemorySettings = struct {
    unit: MemoryUnit,
    used_gib: f64,
    used_mib: i64,
};

const MemoryOutput = struct {
    used_gib: f64,
    used_mib: i64,
    unit: MemoryUnit,
};

const ClockSettings = struct {
    timezone: ClockTimezone,
};

const ClockOutput = struct {
    timestamp: i64,
    formatted: []const u8,
    timezone: ClockTimezone,
};

const workspace_settings = fieldsFromStruct(WorkspaceSettings, &.{
    fieldOverride(WorkspaceSettings, .show_empty, .{
        .doc = "Whether empty workspaces should be shown.",
        .snippet_value = "false",
    }),
});

const workspace_output_fields = fieldsFromStruct(WorkspaceOutput, &.{
    fieldOverride(WorkspaceOutput, .focused, .{ .doc = "Focused workspace id." }),
    fieldOverride(WorkspaceOutput, .total, .{ .doc = "Total visible workspace count." }),
});

const mode_settings = fieldsFromStruct(ModeSettings, &.{});

const mode_output_fields = fieldsFromStruct(ModeOutput, &.{
    fieldOverride(ModeOutput, .compositor, .{ .doc = "Current compositor label." }),
});

const window_settings = fieldsFromStruct(WindowSettings, &.{
    fieldOverride(WindowSettings, .truncate, .{
        .doc = "Whether long titles should be truncated.",
        .snippet_value = "true",
    }),
});

const window_output_fields = fieldsFromStruct(WindowOutput, &.{
    fieldOverride(WindowOutput, .title, .{ .doc = "Focused window title." }),
});

const cpu_settings = fieldsFromStruct(CpuSettings, &.{
    fieldOverride(CpuSettings, .usage, .{
        .doc = "Override usage value for testing or static configs.",
        .min_int = 0,
        .max_int = 100,
        .snippet_value = "0",
    }),
    fieldOverride(CpuSettings, .sample_window, .{
        .doc = "Number of samples to average.",
        .min_int = 1,
        .max_int = 120,
        .snippet_value = "4",
    }),
});

const cpu_output_fields = fieldsFromStruct(CpuOutput, &.{
    fieldOverride(CpuOutput, .usage, .{ .doc = "CPU usage percentage." }),
});

const memory_settings = fieldsFromStruct(MemorySettings, &.{
    fieldOverride(MemorySettings, .unit, .{
        .doc = "Display unit: gib or mib.",
        .snippet_value = "\"gib\"",
    }),
    fieldOverride(MemorySettings, .used_gib, .{
        .doc = "Override GiB value for testing or static configs.",
        .min_number = 0,
        .snippet_value = "0.0",
    }),
    fieldOverride(MemorySettings, .used_mib, .{
        .doc = "Override MiB value for testing or static configs.",
        .min_int = 0,
        .snippet_value = "0",
    }),
});

const memory_output_fields = fieldsFromStruct(MemoryOutput, &.{
    fieldOverride(MemoryOutput, .used_gib, .{ .doc = "Used memory in GiB." }),
    fieldOverride(MemoryOutput, .used_mib, .{ .doc = "Used memory in MiB." }),
    fieldOverride(MemoryOutput, .unit, .{ .doc = "Selected display unit." }),
});

const clock_settings = fieldsFromStruct(ClockSettings, &.{
    fieldOverride(ClockSettings, .timezone, .{
        .doc = "Requested clock timezone label.",
        .snippet_value = "\"local\"",
    }),
});

const clock_output_fields = fieldsFromStruct(ClockOutput, &.{
    fieldOverride(ClockOutput, .timestamp, .{ .doc = "Current unix timestamp." }),
    fieldOverride(ClockOutput, .formatted, .{ .doc = "Clock value formatted with the source time format." }),
    fieldOverride(ClockOutput, .timezone, .{ .doc = "Resolved timezone label." }),
});

pub const bar_theme_fields = fieldsFromStruct(BarTheme, &.{
    fieldOverride(BarTheme, .segment_background, .{
        .doc = "Default segment background color.",
        .snippet_value = "\"#2a3139\"",
    }),
    fieldOverride(BarTheme, .accent_background, .{
        .doc = "Accent segment background color.",
        .snippet_value = "\"#275b7a\"",
    }),
    fieldOverride(BarTheme, .subtle_background, .{
        .doc = "Subtle segment background color.",
        .snippet_value = "\"#1c232a\"",
    }),
    fieldOverride(BarTheme, .warning_background, .{
        .doc = "Warning segment background color.",
        .snippet_value = "\"#7a4627\"",
    }),
    fieldOverride(BarTheme, .accent_foreground, .{
        .doc = "Foreground color used on accent and warning segments.",
        .snippet_value = "\"#eff5fa\"",
    }),
    fieldOverride(BarTheme, .font_path, .{
        .doc = "Primary TTF font path for GUI preview.",
        .snippet_value = "\"/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf\"",
    }),
    fieldOverride(BarTheme, .font_fallback_path, .{
        .doc = "First fallback TTF font path for GUI preview.",
        .snippet_value = "\"/usr/share/fonts/TTF/IosevkaTermNerdFont-Regular.ttf\"",
    }),
    fieldOverride(BarTheme, .font_fallback_path_2, .{
        .doc = "Second fallback TTF font path for GUI preview.",
        .snippet_value = "\"/usr/share/fonts/TTF/Hack-Regular.ttf\"",
    }),
    fieldOverride(BarTheme, .preview_width_px, .{
        .doc = "Preview window width in pixels.",
        .min_int = 320,
        .snippet_value = "1280",
    }),
    fieldOverride(BarTheme, .anchor, .{
        .doc = "Requested preview anchor.",
        .snippet_value = "\"top\"",
    }),
    fieldOverride(BarTheme, .horizontal_padding_px, .{
        .doc = "Horizontal inset applied to section layout.",
        .min_int = 0,
        .snippet_value = "18",
    }),
    fieldOverride(BarTheme, .segment_padding_x_px, .{
        .doc = "Horizontal padding inside each segment box.",
        .min_int = 0,
        .snippet_value = "10",
    }),
    fieldOverride(BarTheme, .segment_padding_y_px, .{
        .doc = "Vertical padding inside each segment box.",
        .min_int = 0,
        .snippet_value = "6",
    }),
    fieldOverride(BarTheme, .font_points, .{
        .doc = "Font point size for GUI preview.",
        .min_int = 8,
        .snippet_value = "15",
    }),
    fieldOverride(BarTheme, .segment_radius_px, .{
        .doc = "Corner radius for segment boxes in rendered backends.",
        .min_int = 0,
        .snippet_value = "6",
    }),
    fieldOverride(BarTheme, .edge_line_px, .{
        .doc = "Top and bottom edge line thickness for the bar surface.",
        .min_int = 0,
        .snippet_value = "1",
    }),
    fieldOverride(BarTheme, .edge_shadow_alpha, .{
        .doc = "Alpha applied to the lower edge treatment.",
        .min_int = 0,
        .max_int = 255,
        .snippet_value = "235",
    }),
    fieldOverride(BarTheme, .segment_border_px, .{
        .doc = "Border thickness for segment boxes.",
        .min_int = 0,
        .snippet_value = "1",
    }),
    fieldOverride(BarTheme, .segment_border_alpha, .{
        .doc = "Alpha applied to segment box borders.",
        .min_int = 0,
        .max_int = 255,
        .snippet_value = "150",
    }),
});

pub const bar_visual_fields = fieldsFromStruct(BarVisuals, &.{
    fieldOverride(BarVisuals, .height_px, .{
        .doc = "Bar height in pixels.",
        .min_int = 16,
        .snippet_value = "28",
    }),
    fieldOverride(BarVisuals, .section_gap_px, .{
        .doc = "Gap between left, center, and right sections.",
        .min_int = 0,
        .snippet_value = "12",
    }),
    fieldOverride(BarVisuals, .background, .{
        .doc = "Bar background color.",
        .snippet_value = "\"#11161c\"",
    }),
    fieldOverride(BarVisuals, .foreground, .{
        .doc = "Default bar foreground color.",
        .snippet_value = "\"#d7dee7\"",
    }),
});

pub const specs = [_]ProviderSpec{
    providerSpec("workspaces", "Workspace status provider.", workspace_settings, workspace_output_fields, .{
        .style = .template,
        .default_template = "ws {focused}/{total}",
        .example_format = "ws {focused}/{total}",
    }),
    providerSpec("mode", "Compositor mode provider.", mode_settings, mode_output_fields, .{
        .style = .template,
        .default_template = "{compositor}",
        .example_format = "{compositor}",
    }),
    providerSpec("window", "Focused window title provider.", window_settings, window_output_fields, .{
        .style = .passthrough_text,
        .supports_truncation = true,
        .truncation_setting_key = settingField(WindowSettings, .truncate),
    }),
    providerSpec("cpu", "CPU usage provider.", cpu_settings, cpu_output_fields, .{
        .style = .template,
        .default_template = "cpu {usage}%",
        .example_format = "cpu {usage}%",
    }),
    providerSpec("memory", "Memory usage provider.", memory_settings, memory_output_fields, .{
        .style = .template,
        .default_template = "mem {used_gib}G",
        .example_format = "mem {used_gib:.1}G",
        .unit_field = outputField(MemoryOutput, .unit),
        .unit_template_gib = "mem {used_gib}G",
        .unit_template_mib = "mem {used_mib}M",
    }),
    providerSpec("clock", "Clock provider.", clock_settings, clock_output_fields, .{
        .style = .template,
        .default_template = "{formatted}",
        .example_format = "{timestamp}",
        .source_format = "%a %d %b %H:%M",
    }),
};

pub const providers = blk: {
    var items: [specs.len]ProviderMeta = undefined;
    for (specs, 0..) |spec, i| items[i] = spec.provider;
    break :blk items;
};

pub const presentation = blk: {
    var items: [specs.len]PresentationMeta = undefined;
    for (specs, 0..) |spec, i| items[i] = spec.presentation;
    break :blk items;
};

pub fn providerMeta(provider_id: []const u8) ?ProviderMeta {
    for (specs) |entry| {
        if (std.mem.eql(u8, entry.provider.id, provider_id)) return entry.provider;
    }
    return null;
}

pub fn presentationMeta(provider_id: []const u8) PresentationMeta {
    for (specs) |entry| {
        if (std.mem.eql(u8, entry.presentation.provider_id, provider_id)) return entry.presentation;
    }
    return .{
        .provider_id = provider_id,
        .style = .template,
        .default_template = "{value}",
    };
}

fn fieldsFromStruct(comptime T: type, comptime field_overrides: []const FieldOverride) []const FieldMeta {
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("fieldsFromStruct expects a struct type");
    const struct_fields = info.@"struct".fields;

    const Storage = struct {
        const value = blk: {
            var out: [struct_fields.len]FieldMeta = undefined;
            for (struct_fields, 0..) |field, i| {
                const field_override = findOverride(field.name, field_overrides);
                const unwrapped = unwrapOptional(field.type);
                out[i] = .{
                    .name = field.name,
                    .kind = scalarKind(unwrapped),
                    .optional = field_override.optional orelse isOptional(field.type),
                    .doc = field_override.doc,
                    .min_int = field_override.min_int,
                    .max_int = field_override.max_int,
                    .min_number = field_override.min_number,
                    .max_number = field_override.max_number,
                    .enum_values = enumValues(unwrapped),
                    .snippet_value = field_override.snippet_value,
                };
            }
            break :blk out;
        };
    };
    return &Storage.value;
}

fn defineProvider(comptime args: anytype) ProviderSpec {
    const pascal_id = pascalCase(args.id);
    return .{
        .provider = .{
            .id = args.id,
            .class_name = className(pascal_id, "ProviderConfig"),
            .settings_class_name = className(pascal_id, "Settings"),
            .doc = args.doc,
            .settings = args.settings,
            .output_fields = args.output_fields,
        },
        .presentation = .{
            .provider_id = args.id,
            .style = args.style,
            .default_template = if (@hasField(@TypeOf(args), "default_template")) args.default_template else "",
            .example_format = if (@hasField(@TypeOf(args), "example_format")) args.example_format else "",
            .source_format = if (@hasField(@TypeOf(args), "source_format")) args.source_format else "",
            .unit_field = if (@hasField(@TypeOf(args), "unit_field")) args.unit_field else null,
            .unit_template_gib = if (@hasField(@TypeOf(args), "unit_template_gib")) args.unit_template_gib else "",
            .unit_template_mib = if (@hasField(@TypeOf(args), "unit_template_mib")) args.unit_template_mib else "",
            .supports_truncation = if (@hasField(@TypeOf(args), "supports_truncation")) args.supports_truncation else false,
            .truncation_setting_key = if (@hasField(@TypeOf(args), "truncation_setting_key")) args.truncation_setting_key else null,
        },
    };
}

fn providerSpec(
    comptime id: []const u8,
    comptime doc: []const u8,
    comptime settings: []const FieldMeta,
    comptime output_fields: []const FieldMeta,
    comptime presentation_args: PresentationArgs,
) ProviderSpec {
    return defineProvider(.{
        .id = id,
        .doc = doc,
        .settings = settings,
        .output_fields = output_fields,
        .style = presentation_args.style,
        .default_template = presentation_args.default_template,
        .example_format = presentation_args.example_format,
        .source_format = presentation_args.source_format,
        .unit_field = presentation_args.unit_field,
        .unit_template_gib = presentation_args.unit_template_gib,
        .unit_template_mib = presentation_args.unit_template_mib,
        .supports_truncation = presentation_args.supports_truncation,
        .truncation_setting_key = presentation_args.truncation_setting_key,
    });
}

fn className(comptime stem: []const u8, comptime suffix: []const u8) []const u8 {
    return "Zbar" ++ stem ++ suffix;
}

fn pascalCase(comptime input: []const u8) []const u8 {
    var out: [input.len]u8 = undefined;
    var out_len: usize = 0;
    var upper_next = true;
    for (input) |char| {
        if (char == '_' or char == '-' or char == ' ') {
            upper_next = true;
            continue;
        }
        out[out_len] = if (upper_next) std.ascii.toUpper(char) else char;
        out_len += 1;
        upper_next = false;
    }
    return out[0..out_len];
}

fn findOverride(comptime name: []const u8, comptime field_overrides: []const FieldOverride) FieldOverride {
    inline for (field_overrides) |field_override| {
        if (std.mem.eql(u8, field_override.field_name, name)) return field_override;
    }
    return .{ .field_name = name };
}

fn fieldOverride(comptime T: type, comptime field: std.meta.FieldEnum(T), comptime data: anytype) FieldOverride {
    const field_name = @tagName(field);
    return .{
        .field_name = field_name,
        .doc = if (@hasField(@TypeOf(data), "doc")) data.doc else "",
        .optional = if (@hasField(@TypeOf(data), "optional")) data.optional else null,
        .min_int = if (@hasField(@TypeOf(data), "min_int")) data.min_int else null,
        .max_int = if (@hasField(@TypeOf(data), "max_int")) data.max_int else null,
        .min_number = if (@hasField(@TypeOf(data), "min_number")) data.min_number else null,
        .max_number = if (@hasField(@TypeOf(data), "max_number")) data.max_number else null,
        .snippet_value = if (@hasField(@TypeOf(data), "snippet_value")) data.snippet_value else "",
    };
}

fn outputField(comptime T: type, comptime field: std.meta.FieldEnum(T)) []const u8 {
    return @tagName(field);
}

fn settingField(comptime T: type, comptime field: std.meta.FieldEnum(T)) []const u8 {
    return @tagName(field);
}

fn scalarKind(comptime T: type) ScalarKind {
    return switch (@typeInfo(T)) {
        .bool => .boolean,
        .int, .comptime_int => .integer,
        .float, .comptime_float => .number,
        .pointer => |ptr| if (ptr.size == .slice and ptr.child == u8) .string else @compileError("unsupported pointer field type"),
        .array => |array| if (array.child == u8) .string else @compileError("unsupported array field type"),
        .@"enum" => .string,
        else => @compileError("unsupported field type for config metadata"),
    };
}

fn enumValues(comptime T: type) []const []const u8 {
    return switch (@typeInfo(T)) {
        .@"enum" => |enum_info| blk: {
            const Storage = struct {
                const value = inner: {
                    var values: [enum_info.fields.len][]const u8 = undefined;
                    for (enum_info.fields, 0..) |field, i| {
                        values[i] = field.name;
                    }
                    break :inner values;
                };
            };
            break :blk &Storage.value;
        },
        else => &.{},
    };
}

fn isOptional(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

fn unwrapOptional(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .optional => |optional| optional.child,
        else => T,
    };
}

test "fieldsFromStruct derives enum and numeric metadata" {
    const derived = fieldsFromStruct(struct {
        unit: MemoryUnit,
        used_gib: f64,
        sample_window: i64,
    }, &.{
        fieldOverride(struct {
            unit: MemoryUnit,
            used_gib: f64,
            sample_window: i64,
        }, .used_gib, .{ .min_number = 0 }),
        fieldOverride(struct {
            unit: MemoryUnit,
            used_gib: f64,
            sample_window: i64,
        }, .sample_window, .{ .min_int = 1, .max_int = 120 }),
    });

    try std.testing.expectEqual(@as(usize, 3), derived.len);
    try std.testing.expectEqualStrings("gib", derived[0].enum_values[0]);
    try std.testing.expectEqual(ScalarKind.number, derived[1].kind);
    try std.testing.expectEqual(@as(?i64, 1), derived[2].min_int);
}

test "override uses compile-time checked field tags" {
    const item = fieldOverride(CpuSettings, .usage, .{ .doc = "usage", .min_int = 0 });
    try std.testing.expectEqualStrings("usage", item.field_name);
    try std.testing.expectEqual(@as(?i64, 0), item.min_int);
}

test "defineProvider builds provider and presentation spec together" {
    const spec = defineProvider(.{
        .id = "example",
        .doc = "Example provider.",
        .settings = &.{},
        .output_fields = &.{},
        .style = .template,
        .default_template = "{value}",
        .example_format = "{value}",
    });
    try std.testing.expectEqualStrings("example", spec.provider.id);
    try std.testing.expectEqualStrings("ZbarExampleProviderConfig", spec.provider.class_name);
    try std.testing.expectEqualStrings("ZbarExampleSettings", spec.provider.settings_class_name);
    try std.testing.expectEqualStrings("example", spec.presentation.provider_id);
    try std.testing.expectEqual(PresentationStyle.template, spec.presentation.style);
    try std.testing.expectEqualStrings("{value}", spec.presentation.example_format);
}

test "providerSpec creates compact provider declarations" {
    const spec = providerSpec("demo", "Demo provider.", &.{}, &.{}, .{
        .style = .template,
        .default_template = "{value}",
    });
    try std.testing.expectEqualStrings("demo", spec.provider.id);
    try std.testing.expectEqualStrings("Demo provider.", spec.provider.doc);
    try std.testing.expectEqualStrings("{value}", spec.presentation.default_template);
}
