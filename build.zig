const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_headless = b.option(bool, "enable_headless", "Build without a GUI backend") orelse false;
    const app_version = b.option([]const u8, "app_version", "zbar version string") orelse "0.1.0-dev";

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_gui", !enable_headless);
    build_options.addOption([]const u8, "app_version", app_version);

    const mod = b.addModule("zbar", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "build_options", .module = build_options.createModule() },
        },
    });

    const meta_tool = b.addExecutable(.{
        .name = "generate_lua_meta",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/generate_lua_meta.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zbar", .module = mod },
            },
        }),
    });

    const meta_run = b.addRunArtifact(meta_tool);
    meta_run.addArg(b.path("lua/zbar-meta.lua").getPath(b));
    meta_run.addArg(b.path("snippets/lua.json").getPath(b));
    const meta_step = b.step("meta", "Generate Lua metadata");
    meta_step.dependOn(&meta_run.step);

    const wayland_protocols = b.addLibrary(.{
        .name = "zbar_wayland_protocols",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    wayland_protocols.linkLibC();
    wayland_protocols.addIncludePath(b.path("src/ui/wayland"));
    wayland_protocols.addCSourceFile(.{ .file = b.path("src/ui/wayland/wlr-layer-shell-unstable-v1-protocol.c") });
    wayland_protocols.addCSourceFile(.{ .file = b.path("src/ui/wayland/xdg-shell-protocol.c") });

    const exe = b.addExecutable(.{
        .name = "zbar",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zbar", .module = mod },
                .{ .name = "build_options", .module = build_options.createModule() },
            },
        }),
    });
    exe.linkLibC();
    exe.root_module.linkSystemLibrary("lua5.4", .{ .use_pkg_config = .force });
    if (!enable_headless) {
        exe.addIncludePath(b.path("src/ui/wayland"));
        exe.linkLibrary(wayland_protocols);
        exe.root_module.linkSystemLibrary("cairo", .{ .use_pkg_config = .force });
        exe.root_module.linkSystemLibrary("freetype2", .{ .use_pkg_config = .force });
        exe.root_module.linkSystemLibrary("sdl3", .{ .use_pkg_config = .force });
        exe.root_module.linkSystemLibrary("sdl3-ttf", .{ .use_pkg_config = .force });
        exe.root_module.linkSystemLibrary("wayland-client", .{ .use_pkg_config = .force });
    }

    b.installArtifact(exe);

    const run_step = b.step("run", "Run zbar");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    mod_tests.linkLibC();
    mod_tests.root_module.linkSystemLibrary("lua5.4", .{ .use_pkg_config = .force });
    if (!enable_headless) {
        mod_tests.addIncludePath(b.path("src/ui/wayland"));
        mod_tests.linkLibrary(wayland_protocols);
        mod_tests.root_module.linkSystemLibrary("cairo", .{ .use_pkg_config = .force });
        mod_tests.root_module.linkSystemLibrary("freetype2", .{ .use_pkg_config = .force });
        mod_tests.root_module.linkSystemLibrary("sdl3", .{ .use_pkg_config = .force });
        mod_tests.root_module.linkSystemLibrary("sdl3-ttf", .{ .use_pkg_config = .force });
        mod_tests.root_module.linkSystemLibrary("wayland-client", .{ .use_pkg_config = .force });
    }
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    exe_tests.linkLibC();
    exe_tests.root_module.linkSystemLibrary("lua5.4", .{ .use_pkg_config = .force });
    if (!enable_headless) {
        exe_tests.addIncludePath(b.path("src/ui/wayland"));
        exe_tests.linkLibrary(wayland_protocols);
        exe_tests.root_module.linkSystemLibrary("cairo", .{ .use_pkg_config = .force });
        exe_tests.root_module.linkSystemLibrary("freetype2", .{ .use_pkg_config = .force });
        exe_tests.root_module.linkSystemLibrary("wayland-client", .{ .use_pkg_config = .force });
    }
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&meta_run.step);
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
