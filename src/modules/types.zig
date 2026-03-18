const std = @import("std");
const config = @import("../config/mod.zig");
const wm = @import("../wm/mod.zig");

pub const ProviderHealth = enum {
    ready,
    degraded,
    unavailable,
};

pub const Field = struct {
    key: []const u8,
    value: []const u8,
    scalar: Scalar = .{ .none = {} },
};

pub const ScalarKind = enum {
    none,
    string,
    integer,
    number,
    boolean,
};

pub const Scalar = union(ScalarKind) {
    none: void,
    string: []const u8,
    integer: i64,
    number: f64,
    boolean: bool,
};

pub const PayloadKind = enum {
    none,
    text,
    integer,
    number,
    state,
};

pub const Payload = union(PayloadKind) {
    none: void,
    text: []const u8,
    integer: i64,
    number: f64,
    state: []const u8,
};

pub const Segment = struct {
    provider: []const u8,
    instance_name: ?[]const u8,
    text: []const u8,
    content_id: u64 = 0,
    payload: Payload = .{ .none = {} },
};

pub const Frame = struct {
    left: []Segment,
    center: []Segment,
    right: []Segment,

    pub fn deinit(self: Frame, allocator: std.mem.Allocator) void {
        freeSegments(allocator, self.left);
        freeSegments(allocator, self.center);
        freeSegments(allocator, self.right);
    }
};

pub const ProviderContext = struct {
    allocator: std.mem.Allocator,
    snapshot: wm.Snapshot,
    instance: config.ProviderConfig,
    defaults: config.ProviderDefaults,
};

pub const ProviderOutput = struct {
    text: []const u8,
    content_id: u64 = 0,
    payload: Payload = .{ .none = {} },
    fields: []Field = &.{},

    pub fn deinit(self: ProviderOutput, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        for (self.fields) |field| allocator.free(field.value);
        if (self.fields.len > 0) allocator.free(self.fields);
    }
};

pub const Provider = struct {
    name: []const u8,
    context: *const anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        render: *const fn (ctx: *const anyopaque, provider_ctx: ProviderContext) anyerror!ProviderOutput,
        health: *const fn (ctx: *const anyopaque) ProviderHealth,
    };

    pub fn render(self: Provider, provider_ctx: ProviderContext) !ProviderOutput {
        return self.vtable.render(self.context, provider_ctx);
    }

    pub fn health(self: Provider) ProviderHealth {
        return self.vtable.health(self.context);
    }
};

fn freeSegments(allocator: std.mem.Allocator, segments: []Segment) void {
    for (segments) |segment| allocator.free(segment.text);
    allocator.free(segments);
}
