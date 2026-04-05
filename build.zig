const std = @import("std");
const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = Scanner.create(b, .{});

    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addCustomProtocol(b.path("./wlr-layer-shell-unstable-v1.xml"));

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

    b.installArtifact(exe);
}
