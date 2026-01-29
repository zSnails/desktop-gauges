const std = @import("std");
const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // const mod = b.addModule("desktop_gauges", .{
    //     .root_source_file = b.path("src/root.zig"),
    //     .target = target,
    // });

    const scanner = Scanner.create(b, .{});

    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    // const sdl3 = b.dependency("sdl3", .{ .target = target, .optimize = optimize, .c_sdl_preferred_linkage = .dynamic });
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addCustomProtocol(b.path("./wlr-layer-shell-unstable-v1.xml"));

    // scanner.generate("wl_surface", 4);
    scanner.generate("wl_output", 1);
    scanner.generate("wl_compositor", 1);
    scanner.generate("wl_shm", 1);
    scanner.generate("xdg_wm_base", 3);
    scanner.generate("zwlr_layer_shell_v1", 5);

    const exe = b.addExecutable(.{
        .name = "desktop_gauges",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            // .imports = &.{
            //     .{ .name = "desktop_gauges", .module = mod },
            // },
        }),
    });
    exe.root_module.addImport("wayland", wayland);
    exe.root_module.linkSystemLibrary("cairo", .{
        .needed = true,
        .preferred_link_mode = .static,
    });
    exe.linkLibC();
    exe.root_module.linkSystemLibrary("wayland-client", .{
        .needed = true,
        .preferred_link_mode = .static,
    });

    // exe.root_module.addImport("sdl3", sdl3.module("sdl3"));

    b.installArtifact(exe);
}
