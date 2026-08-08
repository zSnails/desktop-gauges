const std = @import("std");

const getMetricProvider = @import("metrics/providers.zig").getMetricProvider;
const zig_config = @import("zig-config");

const Cluster = @import("cluster.zig");
const Gauge = @import("gauge/gauge.zig");
const Window = @import("window.zig");
const app_config = @import("config.zig");

/// Computes and returns the viewport width and height based on the internal
/// gauge configs
pub fn getViewportSize(gauge_configs: []const app_config.GaugeConfig) struct { width: f64, height: f64 } {
    var max_x: f64 = 1;
    var max_y: f64 = 1;
    for (gauge_configs) |gauge_config| {
        max_x = @max(gauge_config.x + gauge_config.radius, max_x);
        max_y = @max(gauge_config.y + gauge_config.radius, max_y);
    }

    return .{ .width = max_x, .height = max_y };
}

test "get viewport dimensions" {
    const result = getViewportSize(&[_]app_config.GaugeConfig{.{ .x = 33, .y = 44, .radius = 200 }});
    try std.testing.expectEqual(244, result.height);
    try std.testing.expectEqual(233, result.width);
    const result2 = getViewportSize(&[_]app_config.GaugeConfig{
        .{ .x = 33, .y = 44, .radius = 200 },
        .{ .x = 22, .y = 0, .radius = 300 },
        .{ .x = 100, .y = 20, .radius = 300 },
    });
    try std.testing.expectEqual(320, result2.height);
    try std.testing.expectEqual(400, result2.width);

    const result3 = getViewportSize(&[_]app_config.GaugeConfig{
        .{ .x = 33, .y = 44, .radius = 200 },
        .{ .x = 22, .y = 0, .radius = 300 },
        .{ .x = 100, .y = 20, .radius = 300 },
        .{ .x = 100, .y = 20, .radius = 300 },
        .{ .x = 100, .y = 200, .radius = 300 },
        .{ .x = 100, .y = 20, .radius = 700 },
        .{ .x = 100, .y = 20, .radius = 300 },
    });
    try std.testing.expectEqual(720, result3.height);
    try std.testing.expectEqual(800, result3.width);
}

fn launchClusterWindow(
    io: std.Io,
    allocator: std.mem.Allocator,
    cluster_config: *const app_config.ClusterConfig,
) !void {
    const thread_id = std.Thread.getCurrentId();
    const dimensions = getViewportSize(cluster_config.gauges);
    var window = try Window.init(
        io,
        dimensions.width,
        dimensions.height,
        thread_id,
        cluster_config.viewport.anchor,
    );
    defer window.deinit();

    const context = window.getContext();

    var cluster = try Cluster.init(allocator, context);
    defer cluster.deinit();

    for (cluster_config.gauges) |gauge_config| {
        var gauge = try allocator.create(Gauge.Digital);
        std.log.debug("Creating {s} gauge", .{@tagName(gauge_config.provider)});
        gauge.* = Gauge.Digital.create(
            context,
            gauge_config.radius,
            gauge_config.x,
            gauge_config.y,
        );
        gauge.setProvider(getMetricProvider(gauge_config.provider));
        try gauge.init();

        const interface = gauge.getGauge();
        try cluster.addGauge(interface);
    }

    std.log.info(
        "[{d}] Using cluster with {} items",
        .{ thread_id, cluster.gauges.items.len },
    );
    window.cluster = cluster;

    try window.showAndRun();
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();

    var config = try zig_config.loadConfig(
        app_config.Config,
        alloc,
        .{ .name = "gauges", .env_prefix = "GAUGES" },
    );
    defer config.deinit(alloc);

    std.log.debug("Got the following config: {}", .{config});
    std.log.debug("Got the following config.value: {}", .{config.value});
    std.log.info("Loading config from {s}", .{@tagName(config.source)});
    std.log.info("Using the following configuration sources", .{});
    for (config.sources) |*source| {
        std.log.info("\t-\t{?s}\t({s})", .{ source.path, @tagName(source.source) });
    }

    var threads = try std.ArrayList(*std.Thread).initCapacity(alloc, 2);
    for (config.value.clusters) |cluster_config| {
        var thread = try std.Thread.spawn(.{ .allocator = alloc }, launchClusterWindow, .{ init.io, alloc, &cluster_config });
        try threads.append(alloc, &thread);
    }

    for (threads.items) |thread| {
        thread.join();
    }
    // TODO: create a window per cluster instead of drawing everything inside a huge window
    // TODO: make pre compute the cluster window dimensions

    // var temperature_gauge = Gauge.Digital.create(context, 100, 100, 100);
    // temperature_gauge.setProvider(gaugeTemperatureStatusThread);
    // try temperature_gauge.init();
    //
    // const interface = temperature_gauge.getGauge();
    //
    // try cluster.addGauge(interface);
    //
    // var ram_gauge = Gauge.Digital.create(context, 100, 300, 100);
    // ram_gauge.setProvider(gaugeMemoryUsageThread);
    // try ram_gauge.init();
    // const ram_gauge_interface = ram_gauge.getGauge();
    //
    // try cluster.addGauge(ram_gauge_interface);
    //
    // var cpu_gauge = Gauge.Digital.create(context, 100, 500, 100);
    // cpu_gauge.setProvider(gaugeCpuUsageThread);
    // try cpu_gauge.init();
    // const cpu_gauge_interface = cpu_gauge.getGauge();
    //
    // try cluster.addGauge(cpu_gauge_interface);

}

// TODO: find a way of abstracting away these pieces of shit
