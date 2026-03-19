---@diagnostic disable: undefined-global
local mod
do
  local ok, loaded = pcall(require, "zbar-meta")
  if ok and type(loaded) == "table" then
    mod = loaded
  end
end
---@type ZbarModule
local zbar
if mod then
  zbar = mod
else
  ---@type ZbarProviderFactory
  local provider = {
    workspaces = function(opts) opts = opts or {}; opts.provider = "workspaces"; return opts end,
    mode = function(opts) opts = opts or {}; opts.provider = "mode"; return opts end,
    window = function(opts) opts = opts or {}; opts.provider = "window"; return opts end,
    cpu = function(opts) opts = opts or {}; opts.provider = "cpu"; return opts end,
    memory = function(opts) opts = opts or {}; opts.provider = "memory"; return opts end,
    clock = function(opts) opts = opts or {}; opts.provider = "clock"; return opts end,
  }
  zbar = {
    provider = provider,
    config = function(opts) return opts end,
  }
end

---@type ZbarConfig
return zbar.config({
  bar = {
    height_px = 34,
    section_gap_px = 18,
    background = "#0b1220",
    foreground = "#e6edf7",
    theme = {
      segment_background = "#172235",
      accent_background = "#0f6db2",
      subtle_background = "#10192a",
      warning_background = "#8d4b22",
      accent_foreground = "#f4faff",
      font_path = "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf",
      font_fallback_path = "/usr/share/fonts/TTF/IosevkaTermNerdFont-Regular.ttf",
      font_fallback_path_2 = "/usr/share/fonts/TTF/Hack-Regular.ttf",
      preview_width_px = 1440,
      anchor = "top",
      horizontal_padding_px = 26,
      segment_padding_x_px = 14,
      segment_padding_y_px = 8,
      font_points = 16,
      segment_radius_px = 10,
      edge_line_px = 2,
      edge_shadow_alpha = 220,
      segment_border_px = 1,
      segment_border_alpha = 190,
    },
    left = {
      zbar.provider.workspaces({
        name = "hypr",
        format = "ws {focused:.2}/{total:.2}",
        settings = {
          show_empty = false,
        },
      }),
      zbar.provider.mode({
        format = "{compositor|upper}",
      }),
    },
    center = {
      zbar.provider.window({
        name = "title",
        max_width = 72,
        settings = {
          truncate = true,
        },
      }),
    },
    right = {
      zbar.provider.cpu({
        interval_ms = 1000,
        format = "cpu {usage:.2}%",
        settings = {
          sample_window = 4,
        },
      }),
      zbar.provider.memory({
        interval_ms = 1000,
        format = "mem {used_gib:.1}G",
        settings = {
          unit = "gib",
        },
      }),
      zbar.provider.clock({
        name = "local",
        interval_ms = 1000,
        format = "{formatted}",
        settings = {
          timezone = "local",
        },
      }),
    },
  },
  integrations = {
    zide_socket_name = "zide-ipc.sock",
    wayspot_socket_name = "wayspot-ipc.sock",
  },
  providers = {
    cpu = {
      sample_window = 4,
    },
    memory = {
      unit = "gib",
    },
    clock = {
      timezone = "local",
    },
    workspaces = {
      show_empty = false,
    },
  },
})
