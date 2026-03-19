---@meta

---@alias ZbarScalar string|number|boolean
---@alias ZbarAnchor "top" | "top-left" | "top-right" | "bottom" | "bottom-left" | "bottom-right"

---@class ZbarProviderConfig
---@field provider? string Provider id registered in zbar.
---@field name? string Optional instance name for distinguishing multiple instances.
---@field format? string Optional output template for the provider instance.
---@field interval_ms? integer Refresh interval in milliseconds.
---@field max_width? integer Maximum rendered width before truncation.
---@field settings? table<string, ZbarScalar> Provider-specific per-instance settings.
---@class ZbarWorkspacesSettings
---@field show_empty? boolean Whether empty workspaces should be shown.

---@class ZbarWorkspacesProviderConfig: ZbarProviderConfig
--- Format fields: focused, total.
--- Supported transforms: upper, lower, trim, default(...). Boolean fields also support yesno and onoff.
--- Supported numeric format spec: :.N for integer zero-padding or number precision.
--- Example format: "ws {focused}/{total}"
---@field provider? "workspaces"
---@field settings? ZbarWorkspacesSettings

---@class ZbarModeSettings
--- No provider-specific settings.

---@class ZbarModeProviderConfig: ZbarProviderConfig
--- Format fields: compositor.
--- Supported transforms: upper, lower, trim, default(...). Boolean fields also support yesno and onoff.
--- Supported numeric format spec: :.N for integer zero-padding or number precision.
--- Example format: "{compositor}"
---@field provider? "mode"
---@field settings? ZbarModeSettings

---@class ZbarWindowSettings
---@field truncate? boolean Whether long titles should be truncated.

---@class ZbarWindowProviderConfig: ZbarProviderConfig
--- Format fields: title.
--- Supported transforms: upper, lower, trim, default(...). Boolean fields also support yesno and onoff.
--- Supported numeric format spec: :.N for integer zero-padding or number precision.
---@field provider? "window"
---@field settings? ZbarWindowSettings

---@class ZbarCpuSettings
---@field usage? integer Override usage value for testing or static configs. Constraints: min=0, max=100.
---@field sample_window? integer Number of samples to average. Constraints: min=1, max=120.

---@class ZbarCpuProviderConfig: ZbarProviderConfig
--- Format fields: usage.
--- Supported transforms: upper, lower, trim, default(...). Boolean fields also support yesno and onoff.
--- Supported numeric format spec: :.N for integer zero-padding or number precision.
--- Example format: "cpu {usage}%"
---@field provider? "cpu"
---@field settings? ZbarCpuSettings

---@class ZbarMemorySettings
---@field unit? "gib" | "mib" Display unit: gib or mib. Allowed: "gib" | "mib".
---@field used_gib? number Override GiB value for testing or static configs. Constraints: min=0.
---@field used_mib? integer Override MiB value for testing or static configs. Constraints: min=0.

---@class ZbarMemoryProviderConfig: ZbarProviderConfig
--- Format fields: used_gib, used_mib, unit.
--- Supported transforms: upper, lower, trim, default(...). Boolean fields also support yesno and onoff.
--- Supported numeric format spec: :.N for integer zero-padding or number precision.
--- Example format: "mem {used_gib:.1}G"
---@field provider? "memory"
---@field settings? ZbarMemorySettings

---@class ZbarClockSettings
---@field timezone? "local" | "utc" Requested clock timezone label. Allowed: "local" | "utc".

---@class ZbarClockProviderConfig: ZbarProviderConfig
--- Format fields: timestamp, formatted, timezone.
--- Supported transforms: upper, lower, trim, default(...). Boolean fields also support yesno and onoff.
--- Supported numeric format spec: :.N for integer zero-padding or number precision.
--- Example format: "{timestamp}"
---@field provider? "clock"
---@field settings? ZbarClockSettings

---@class ZbarBarThemeConfig
---@field segment_background? string Default segment background color.
---@field accent_background? string Accent segment background color.
---@field subtle_background? string Subtle segment background color.
---@field warning_background? string Warning segment background color.
---@field accent_foreground? string Foreground color used on accent and warning segments.
---@field font_path? string Primary TTF font path for GUI preview.
---@field font_fallback_path? string First fallback TTF font path for GUI preview.
---@field font_fallback_path_2? string Second fallback TTF font path for GUI preview.
---@field preview_width_px? integer Preview window width in pixels. Constraints: min=320.
---@field anchor? "top" | "top-left" | "top-right" | "bottom" | "bottom-left" | "bottom-right" Requested preview anchor. Allowed: "top" | "top-left" | "top-right" | "bottom" | "bottom-left" | "bottom-right".
---@field horizontal_padding_px? integer Horizontal inset applied to section layout. Constraints: min=0.
---@field segment_padding_x_px? integer Horizontal padding inside each segment box. Constraints: min=0.
---@field segment_padding_y_px? integer Vertical padding inside each segment box. Constraints: min=0.
---@field font_points? integer Font point size for GUI preview. Constraints: min=8.
---@field segment_radius_px? integer Corner radius for segment boxes in rendered backends. Constraints: min=0.
---@field edge_line_px? integer Top and bottom edge line thickness for the bar surface. Constraints: min=0.
---@field edge_shadow_alpha? integer Alpha applied to the lower edge treatment. Constraints: min=0, max=255.
---@field segment_border_px? integer Border thickness for segment boxes. Constraints: min=0.
---@field segment_border_alpha? integer Alpha applied to segment box borders. Constraints: min=0, max=255.

---@class ZbarBarConfig
---@field height_px? integer Bar height in pixels. Constraints: min=16.
---@field section_gap_px? integer Gap between left, center, and right sections. Constraints: min=0.
---@field background? string Bar background color.
---@field foreground? string Default bar foreground color.
---@field theme? ZbarBarThemeConfig
---@field left? ZbarProviderConfig[]
---@field center? ZbarProviderConfig[]
---@field right? ZbarProviderConfig[]

---@class ZbarIntegrationsConfig
---@field zide_socket_name? string
---@field wayspot_socket_name? string

---@class ZbarProviderDefaults
---@field workspaces? ZbarWorkspacesSettings
---@field mode? ZbarModeSettings
---@field window? ZbarWindowSettings
---@field cpu? ZbarCpuSettings
---@field memory? ZbarMemorySettings
---@field clock? ZbarClockSettings

---@class ZbarConfig
---@field bar? ZbarBarConfig
---@field integrations? ZbarIntegrationsConfig
---@field providers? ZbarProviderDefaults

---@class ZbarProviderFactory
---@field workspaces fun(opts?: ZbarWorkspacesProviderConfig): ZbarWorkspacesProviderConfig
---@field mode fun(opts?: ZbarModeProviderConfig): ZbarModeProviderConfig
---@field window fun(opts?: ZbarWindowProviderConfig): ZbarWindowProviderConfig
---@field cpu fun(opts?: ZbarCpuProviderConfig): ZbarCpuProviderConfig
---@field memory fun(opts?: ZbarMemoryProviderConfig): ZbarMemoryProviderConfig
---@field clock fun(opts?: ZbarClockProviderConfig): ZbarClockProviderConfig

---@class ZbarModule
---@field provider ZbarProviderFactory
---@field config fun(opts: ZbarConfig): ZbarConfig

---@type ZbarProviderFactory
local provider_factory = {
  workspaces = function(opts)
    ---@type ZbarWorkspacesProviderConfig
    local value = opts or {}
    value.provider = "workspaces"
    return value
  end,
  mode = function(opts)
    ---@type ZbarModeProviderConfig
    local value = opts or {}
    value.provider = "mode"
    return value
  end,
  window = function(opts)
    ---@type ZbarWindowProviderConfig
    local value = opts or {}
    value.provider = "window"
    return value
  end,
  cpu = function(opts)
    ---@type ZbarCpuProviderConfig
    local value = opts or {}
    value.provider = "cpu"
    return value
  end,
  memory = function(opts)
    ---@type ZbarMemoryProviderConfig
    local value = opts or {}
    value.provider = "memory"
    return value
  end,
  clock = function(opts)
    ---@type ZbarClockProviderConfig
    local value = opts or {}
    value.provider = "clock"
    return value
  end,

}

---@type ZbarModule
local zbar = {
  provider = provider_factory,
  config = function(opts)
    return opts
  end,
}

return zbar
