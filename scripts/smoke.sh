#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

GOOD_CONFIG="$TMP_DIR/good.lua"
BAD_CONFIG="$TMP_DIR/bad.lua"

cat >"$GOOD_CONFIG" <<'EOF'
---@diagnostic disable: undefined-global
local ok, zbar = pcall(require, "zbar-meta")
if not ok then
  zbar = {
    provider = {
      workspaces = function(opts) opts = opts or {}; opts.provider = "workspaces"; return opts end,
      mode = function(opts) opts = opts or {}; opts.provider = "mode"; return opts end,
      window = function(opts) opts = opts or {}; opts.provider = "window"; return opts end,
      cpu = function(opts) opts = opts or {}; opts.provider = "cpu"; return opts end,
      memory = function(opts) opts = opts or {}; opts.provider = "memory"; return opts end,
      clock = function(opts) opts = opts or {}; opts.provider = "clock"; return opts end,
    },
    config = function(opts) return opts end,
  }
end

return zbar.config({
  bar = {
    height_px = 28,
    section_gap_px = 12,
    background = "#11161c",
    foreground = "#d7dee7",
    left = {
      zbar.provider.workspaces({ format = "ws {focused}/{total}" }),
      zbar.provider.mode({ format = "{compositor}" }),
    },
    center = {
      zbar.provider.window({ name = "title", max_width = 96 }),
    },
    right = {
      zbar.provider.cpu({ interval_ms = 1000, format = "cpu {usage}%" }),
      zbar.provider.memory({ interval_ms = 1000, format = "mem {used_gib:.1}G" }),
      zbar.provider.clock({ name = "unix", interval_ms = 1000, format = "{timestamp}" }),
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
EOF

cat >"$BAD_CONFIG" <<'EOF'
return {
  providers = {
    memory = {
      unit = "bytes",
      used_gib = -1,
    },
    bogus = {
      x = 1,
    },
  },
}
EOF

cd "$ROOT_DIR"

echo "[1/6] generate metadata"
zig build meta

echo "[2/6] run tests"
zig build test

echo "[3/6] lint good config"
zig build run -- --lint-config --config "$GOOD_CONFIG"

echo "[4/6] lint bad config"
if zig build run -- --lint-config-strict --config "$BAD_CONFIG"; then
  echo "expected bad config lint to fail" >&2
  exit 1
fi

echo "[5/6] print provider health"
zig build run -- --print-provider-health

echo "[6/6] run app with good config"
ZBAR_CONFIG_LUA="$GOOD_CONFIG" zig build run

echo "smoke ok"
