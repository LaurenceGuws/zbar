pub const Snapshot = @import("types.zig").Snapshot;
pub const Backend = @import("types.zig").Backend;
pub const HyprlandBackend = @import("hyprland.zig").HyprlandBackend;
pub const StubBackend = @import("stub.zig").StubBackend;

var hyprland_backend = HyprlandBackend.init();
var stub_backend = StubBackend.init();

pub fn defaultBackend() Backend {
    if (HyprlandBackend.detect()) {
        return hyprland_backend.backend();
    }
    return stub_backend.backend();
}
