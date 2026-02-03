const std = @import("std");
const Instant = std.time.Instant;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const wlr = wayland.client.zwlr;

const c = @import("cairo.zig").c;
const Cluster = @import("cluster.zig");
const Gauge = @import("gauge.zig");
const Window = @import("window.zig");
const Context = Window.Context;

pub fn main() !void {
    const alloc = std.heap.smp_allocator;
    var window = try Window.init(480, 480);
    defer window.deinit();

    const context = window.getContext();

    var cluster = try Cluster.init(alloc, context);
    defer cluster.deinit();

    var gauge = Gauge.create(context, 100, 100, 100);
    gauge.init();

    const thread = try std.Thread.spawn(.{ .allocator = alloc }, TEST_GAUGE_INDICATOR_ANIMATION, .{&gauge});
    thread.detach();

    try cluster.appendGauge(&gauge);

    window.cluster = cluster;

    try window.showAndRun();
}

fn TEST_GAUGE_INDICATOR_ANIMATION(gauge: *Gauge) !void {
    const rand = std.crypto.random;
    std.debug.print("Beginning test indicator animator loop\n", .{});
    while (true) {
        const new_rpm = rand.float(f64) * 8000.0;
        gauge.set_rpm(new_rpm);
        std.Thread.sleep(0.4e9);
    }
}
