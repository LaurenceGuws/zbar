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
    height_px = 28,
    section_gap_px = 12,
    background = "#11161c",
    foreground = "#d7dee7",
    theme = {
      segment_background = "#2a3139",
      accent_background = "#275b7a",
      subtle_background = "#1c232a",
      warning_background = "#7a4627",
      accent_foreground = "#eff5fa",
      font_path = "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf",
      font_fallback_path = "/usr/share/fonts/TTF/IosevkaTermNerdFont-Regular.ttf",
      font_fallback_path_2 = "/usr/share/fonts/TTF/Hack-Regular.ttf",
      preview_width_px = 1280,
      anchor = "top",
      horizontal_padding_px = 18,
      segment_padding_x_px = 10,
      segment_padding_y_px = 6,
      font_points = 15,
      segment_radius_px = 6,
      edge_line_px = 1,
      edge_shadow_alpha = 235,
      segment_border_px = 1,
      segment_border_alpha = 150,
    },
    left = {
      zbar.provider.workspaces({
        name = "hypr",
        format = "ws {focused}/{total}",
        settings = {
          show_empty = false,
        },
      }),
      zbar.provider.mode({
        format = "{compositor}",
      }),
    },
    center = {
      zbar.provider.window({
        name = "title",
        max_width = 96,
        settings = {
          truncate = true,
        },
      }),
    },
    right = {
      zbar.provider.cpu({
        interval_ms = 1000,
        format = "cpu {usage}%",
        settings = {
          usage = 12,
          sample_window = 4,
        },
      }),
      zbar.provider.memory({
        interval_ms = 1000,
        format = "mem {used_gib:.1}G",
        settings = {
          unit = "gib",
          used_gib = 3.5,
        },
      }),
      zbar.provider.clock({
        name = "unix",
        interval_ms = 1000,
        format = "{timestamp}",
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
      usage = 12,
      sample_window = 4,
    },
    memory = {
      unit = "gib",
      used_gib = 3.5,
    },
    clock = {
      timezone = "local",
    },
    workspaces = {
      show_empty = false,
    },
  },
})
