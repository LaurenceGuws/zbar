const std = @import("std");
const meta = @import("zbar").config.meta;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const output_path = if (args.len >= 2) args[1] else "lua/zbar-meta.lua";
    const snippets_path = if (args.len >= 3) args[2] else "snippets/lua.json";
    const rendered = try render(allocator);
    defer allocator.free(rendered);
    const snippets = try renderSnippets(allocator);
    defer allocator.free(snippets);

    if (std.fs.path.dirname(output_path)) |dir_path| {
        try std.fs.cwd().makePath(dir_path);
    }
    try std.fs.cwd().writeFile(.{ .sub_path = output_path, .data = rendered });
    if (std.fs.path.dirname(snippets_path)) |dir_path| {
        try std.fs.cwd().makePath(dir_path);
    }
    try std.fs.cwd().writeFile(.{ .sub_path = snippets_path, .data = snippets });
}

fn render(allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const w = out.writer(allocator);

    try w.writeAll(
        \\---@meta
        \\
        \\---@alias ZbarScalar string|number|boolean
        \\---@alias ZbarAnchor "top" | "top-left" | "top-right" | "bottom" | "bottom-left" | "bottom-right"
        \\
        \\---@class ZbarProviderConfig
        \\---@field provider? string Provider id registered in zbar.
        \\---@field name? string Optional instance name for distinguishing multiple instances.
        \\---@field format? string Optional output template for the provider instance.
        \\---@field interval_ms? integer Refresh interval in milliseconds.
        \\---@field max_width? integer Maximum rendered width before truncation.
        \\---@field settings? table<string, ZbarScalar> Provider-specific per-instance settings.
        \\
    );

    for (meta.providers) |provider| {
        try renderSettingsClass(w, provider);
        try w.writeAll("\n");
        try renderProviderClass(w, provider);
        try w.writeAll("\n");
    }

    try w.writeAll("---@class ZbarBarThemeConfig\n");
    for (meta.bar_theme_fields) |field| {
        try renderField(w, field, true);
    }
    try w.writeAll("\n---@class ZbarBarConfig\n");
    for (meta.bar_visual_fields) |field| {
        try renderField(w, field, true);
    }
    try w.writeAll(
        \\---@field theme? ZbarBarThemeConfig
        \\---@field left? ZbarProviderConfig[]
        \\---@field center? ZbarProviderConfig[]
        \\---@field right? ZbarProviderConfig[]
        \\
        \\---@class ZbarIntegrationsConfig
        \\---@field zide_socket_name? string
        \\---@field wayspot_socket_name? string
        \\
        \\---@class ZbarProviderDefaults
        \\
    );

    for (meta.providers) |provider| {
        try w.print("---@field {s}? {s}\n", .{ provider.id, provider.settings_class_name });
    }

    try w.writeAll(
        \\
        \\---@class ZbarConfig
        \\---@field bar? ZbarBarConfig
        \\---@field integrations? ZbarIntegrationsConfig
        \\---@field providers? ZbarProviderDefaults
        \\
        \\---@class ZbarProviderFactory
        \\
    );

    for (meta.providers) |provider| {
        try w.print("---@field {s} fun(opts?: {s}): {s}\n", .{ provider.id, provider.class_name, provider.class_name });
    }

    try w.writeAll(
        \\
        \\---@class ZbarModule
        \\---@field provider ZbarProviderFactory
        \\---@field config fun(opts: ZbarConfig): ZbarConfig
        \\
        \\---@type ZbarProviderFactory
        \\local provider_factory = {
        \\
    );

    for (meta.providers, 0..) |provider, i| {
        _ = i;
        try w.print(
            "  {s} = function(opts)\n    ---@type {s}\n    local value = opts or {{}}\n    value.provider = \"{s}\"\n    return value\n  end,\n",
            .{ provider.id, provider.class_name, provider.id },
        );
    }

    try w.writeAll(
        \\
        \\}
        \\
        \\---@type ZbarModule
        \\local zbar = {
        \\  provider = provider_factory,
        \\  config = function(opts)
        \\    return opts
        \\  end,
        \\}
        \\
        \\return zbar
        \\
    );

    return out.toOwnedSlice(allocator);
}

fn renderSettingsClass(writer: anytype, provider: meta.ProviderMeta) !void {
    try writer.print("---@class {s}\n", .{provider.settings_class_name});
    if (provider.settings.len == 0) {
        try writer.writeAll("--- No provider-specific settings.\n");
        return;
    }
    for (provider.settings) |field| {
        try renderField(writer, field, true);
    }
}

fn renderProviderClass(writer: anytype, provider: meta.ProviderMeta) !void {
    try writer.print("---@class {s}: ZbarProviderConfig\n", .{provider.class_name});
    if (provider.output_fields.len > 0) {
        try writer.writeAll("--- Format fields: ");
        for (provider.output_fields, 0..) |field, i| {
            if (i != 0) try writer.writeAll(", ");
            try writer.print("{s}", .{field.name});
        }
        try writer.writeAll(".\n");
        try writer.writeAll("--- Supported transforms: upper, lower, trim, default(...). Boolean fields also support yesno and onoff.\n");
        try writer.writeAll("--- Supported numeric format spec: :.N for integer zero-padding or number precision.\n");
        if (showFormatLine(provider.id)) {
            try writer.print("--- Example format: \"{s}\"\n", .{exampleFormat(provider.id)});
        }
    }
    try writer.print("---@field provider? \"{s}\"\n", .{provider.id});
    try writer.print("---@field settings? {s}\n", .{provider.settings_class_name});
}

fn renderField(writer: anytype, field: meta.FieldMeta, force_optional: bool) !void {
    try writer.print(
        "---@field {s}{s} ",
        .{
            field.name,
            if (force_optional or field.optional) "?" else "",
        },
    );
    try writeFieldType(writer, field);
    if (field.doc.len > 0 or field.enum_values.len > 0 or field.min_int != null or field.max_int != null or field.min_number != null or field.max_number != null) {
        try writer.writeAll(" ");
        if (field.doc.len > 0) try writer.writeAll(field.doc);
        if (field.enum_values.len > 0) {
            if (field.doc.len > 0) try writer.writeAll(" ");
            try writer.writeAll("Allowed: ");
            try writeEnumLiterals(writer, field.enum_values);
            try writer.writeAll(".");
        }
        if (field.min_int != null or field.max_int != null or field.min_number != null or field.max_number != null) {
            if (field.doc.len > 0 or field.enum_values.len > 0) try writer.writeAll(" ");
            try writer.writeAll("Constraints: ");
            try writeConstraints(writer, field);
            try writer.writeAll(".");
        }
    }
    try writer.writeAll("\n");
}

fn writeFieldType(writer: anytype, field: meta.FieldMeta) !void {
    if (field.enum_values.len == 0) {
        try writer.writeAll(switch (field.kind) {
            .string => "string",
            .integer => "integer",
            .number => "number",
            .boolean => "boolean",
        });
        return;
    }

    try writeEnumLiterals(writer, field.enum_values);
}

fn writeEnumLiterals(writer: anytype, values: []const []const u8) !void {
    for (values, 0..) |value, i| {
        if (i != 0) try writer.writeAll(" | ");
        try writer.print("\"{s}\"", .{value});
    }
}

fn writeConstraints(writer: anytype, field: meta.FieldMeta) !void {
    var first = true;
    if (field.min_int) |v| {
        try writer.print("min={d}", .{v});
        first = false;
    }
    if (field.max_int) |v| {
        if (!first) try writer.writeAll(", ");
        try writer.print("max={d}", .{v});
        first = false;
    }
    if (field.min_number) |v| {
        if (!first) try writer.writeAll(", ");
        try writer.print("min={d}", .{v});
        first = false;
    }
    if (field.max_number) |v| {
        if (!first) try writer.writeAll(", ");
        try writer.print("max={d}", .{v});
    }
}

fn renderSnippets(allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const w = out.writer(allocator);

    try w.writeAll("{\n");
    try renderConfigSnippet(w);
    for (meta.providers) |provider| {
        try w.writeAll(",\n");
        try renderProviderSnippet(w, provider);
    }
    try w.writeAll("\n}\n");
    return out.toOwnedSlice(allocator);
}

fn renderConfigSnippet(writer: anytype) !void {
    try writer.writeAll(
        \\  "zbar config": {
        \\    "prefix": "zbar-config",
        \\    "body": [
        \\      "---@type ZbarConfig",
        \\      "return {",
        \\      "  bar = {",
        \\      "    height_px = ${1:28},",
        \\      "    section_gap_px = ${2:12},",
        \\      "    background = \"${3:#11161c}\",",
        \\      "    foreground = \"${4:#d7dee7}\",",
        \\      "    theme = {",
    );
    var tabstop: usize = 5;
    for (meta.bar_theme_fields) |field| {
        try writer.print("\n      \"      ${{{d}:{s} = ", .{ tabstop, field.name });
        try writeJsonSnippetValue(writer, field);
        try writer.writeAll("},\",\n");
        tabstop += 1;
    }
    try writer.writeAll(
        \\      "    },",
        \\      "    left = {",
    );
    try writer.print("\n      \"      ${{{d}:zbar.provider.workspaces({{ format = \\\"{s}\\\" }})}},\",\n", .{ tabstop, exampleFormat("workspaces") });
    tabstop += 1;
    try writer.print("      \"      ${{{d}:zbar.provider.mode({{ format = \\\"{s}\\\" }})}},\",\n", .{ tabstop, exampleFormat("mode") });
    tabstop += 1;
    try writer.writeAll(
        \\      "    },",
        \\      "    center = {",
    );
    try writer.print("\n      \"      ${{{d}:zbar.provider.window({{ name = \\\"title\\\", max_width = 96 }})}},\",\n", .{tabstop});
    tabstop += 1;
    try writer.writeAll(
        \\      "    },",
        \\      "    right = {",
    );
    try writer.print("\n      \"      ${{{d}:zbar.provider.cpu({{ interval_ms = 1000, format = \\\"{s}\\\" }})}},\",\n", .{ tabstop, exampleFormat("cpu") });
    tabstop += 1;
    try writer.print("      \"      ${{{d}:zbar.provider.memory({{ interval_ms = 1000, format = \\\"{s}\\\" }})}},\",\n", .{ tabstop, exampleFormat("memory") });
    tabstop += 1;
    try writer.print("      \"      ${{{d}:zbar.provider.clock({{ name = \\\"unix\\\", interval_ms = 1000, format = \\\"{s}\\\" }})}},\",\n", .{ tabstop, exampleFormat("clock") });
    tabstop += 1;
    try writer.writeAll(
        \\      "    },",
        \\      "  },",
        \\      "  integrations = {",
    );
    try writer.print("\n      \"    zide_socket_name = \\\"${{{d}:zide-ipc.sock}}\\\",\",\n", .{tabstop});
    tabstop += 1;
    try writer.print("      \"    wayspot_socket_name = \\\"${{{d}:wayspot-ipc.sock}}\\\",\",\n", .{tabstop});
    tabstop += 1;
    try writer.writeAll(
        \\      "  },",
        \\      "  providers = {",
    );
    for (meta.providers) |provider| {
        if (provider.settings.len == 0) continue;
        try writer.print("\n      \"    {s} = {{\",\n", .{provider.id});
        for (provider.settings) |field| {
            try writer.print("      \"      ${{{d}:{s} = ", .{ tabstop, field.name });
            try writeJsonSnippetValue(writer, field);
            try writer.writeAll("},\",\n");
            tabstop += 1;
        }
        try writer.writeAll("      \"    },\",\n");
    }
    try writer.writeAll(
        \\      "  },",
        \\      "}",
        \\      ""
        \\    ],
        \\    "description": "Full zbar Lua config scaffold"
        \\  }
    );
}

fn renderProviderSnippet(writer: anytype, provider: meta.ProviderMeta) !void {
    try writer.print(
        "  \"zbar {s} provider\": {{\n    \"prefix\": \"zbar-{s}\",\n    \"body\": [\n",
        .{ provider.id, provider.id },
    );
    try writer.print("      \"zbar.provider.{s}({{\",\n", .{provider.id});
    if (showFormatLine(provider.id)) {
        try writer.print("      \"  format = \\\"{s}\\\",\",\n", .{exampleFormat(provider.id)});
    }
    try writer.writeAll("      \"  settings = {\",\n");
    for (provider.settings, 0..) |field, i| {
        const tabstop: usize = i + 1 + @as(usize, if (showFormatLine(provider.id)) 1 else 0);
        try writer.print("      \"    ${{{d}:{s} = ", .{ tabstop, field.name });
        try writeJsonSnippetValue(writer, field);
        try writer.writeAll("},\",\n");
    }
    try writer.writeAll(
        \\      "  },",
        \\      "})"
        \\    ],
        \\
    );
    try writer.print("    \"description\": \"{s}\"\n  }}", .{provider.doc});
}

fn defaultSnippetValue(kind: meta.ScalarKind) []const u8 {
    return switch (kind) {
        .string => "\"value\"",
        .integer => "0",
        .number => "0.0",
        .boolean => "false",
    };
}

fn snippetValue(field: meta.FieldMeta) []const u8 {
    if (field.snippet_value.len > 0) return field.snippet_value;
    return defaultSnippetValue(field.kind);
}

fn writeJsonSnippetValue(writer: anytype, field: meta.FieldMeta) !void {
    const raw = snippetValue(field);
    for (raw) |char| {
        switch (char) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            else => try writer.writeByte(char),
        }
    }
}

fn exampleFormat(provider_id: []const u8) []const u8 {
    const presentation = meta.presentationMeta(provider_id);
    if (presentation.example_format.len > 0) return presentation.example_format;
    if (presentation.style == .passthrough_text) return "";
    if (presentation.default_template.len > 0) return presentation.default_template;
    return "{value}";
}

fn showFormatLine(provider_id: []const u8) bool {
    return exampleFormat(provider_id).len > 0;
}
