const std = @import("std");
const Instant = std.time.Instant;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const wlr = wayland.client.zwlr;

const c = @import("cairo.zig").c;
const Cluster = @import("cluster.zig");
const Gauge = @import("gauge/gauge.zig");
const cpu = @import("metrics/cpu_usage.zig");
const ram = @import("metrics/ram_usage.zig");
const Window = @import("window.zig");
const Context = Window.Context;

pub fn main() !void {
    const alloc = std.heap.smp_allocator;
    var window = try Window.init(1080, 400);
    defer window.deinit();

    const context = window.getContext();

    var cluster = try Cluster.init(alloc, context);
    defer cluster.deinit();

    var gauge = Gauge.Digital.create(context, 200, 200, 200);
    gauge.init();

    var interface = gauge.getGauge();
    const thread = try std.Thread.spawn(
        .{ .allocator = alloc },
        gaugeTemperatureStatusThread,
        .{&interface},
    );
    thread.detach();

    try cluster.addGauge(&interface);

    var ram_gauge = Gauge.Digital.create(context, 200, 700, 200);
    ram_gauge.init();
    var ram_gauge_interface = ram_gauge.getGauge();
    const ram_gauge_thread = try std.Thread.spawn(
        .{ .allocator = alloc },
        gaugeCpuUsageThread,
        .{&ram_gauge_interface},
    );
    ram_gauge_thread.detach();

    try cluster.addGauge(&ram_gauge_interface);

    std.debug.print("using cluster with {} items\n", .{cluster.gauges.items.len});
    window.cluster = cluster;

    try window.showAndRun();
}

// TODO: find a way of abstracting away these pieces of shit

fn gaugeCpuUsageThread(gauge: *Gauge) !void {
    std.debug.print("address = {}\n", .{@intFromPtr(gauge)});
    gauge.setMaxValue(100);
    gauge.setLabel("cpu");
    std.debug.print("Begin test indicator animator loop\n", .{});
    while (true) {
        const cpu_usage = try cpu.getCpuUsage();
        gauge.setValue(cpu_usage * 100);
        std.Thread.sleep(5e9);
    }
}

fn gaugeMemoryUsageThread(gauge: *Gauge) !void {
    std.debug.print("address = {}\n", .{@intFromPtr(gauge)});
    const ram_usage = ram.getRamUsage();
    // gauge.max_value = @floatFromInt(ram_usage.total / 1024 / 1024 / 1024);
    gauge.setMaxValue(@floatFromInt(ram_usage.total / 1024 / 1024 / 1024));
    gauge.setMinValue(0.0);
    gauge.setLabel("ram");
    gauge.setValueFmt("%.0fGiB\x00");
    std.debug.print("Begin ram test indicator animator loop\n", .{});
    while (true) {
        std.debug.print("total = {} free = {}\nused = {}", .{ ram_usage.total, ram_usage.free, ram_usage.total - ram_usage.free });
        const usage = ram.getRamUsage();
        const _u: f64 = @floatFromInt(usage.total - usage.free);
        gauge.setValue(_u / 1024 / 1024 / 1024);
        std.Thread.sleep(5e9);
    }
}

fn gaugeTemperatureStatusThread(gauge: *Gauge) !void {
    // /sys/class/hwmon/hwmon2/temp3_input

    gauge.setMaxValue(100.0);
    gauge.setMinValue(-100.0);
    gauge.setLabel("Temp");
    gauge.setValueFmt("%.2fC\x00");
    var buf: [1024]u8 = undefined;
    while (true) {
        const hwmon = try std.fs.openFileAbsolute("/sys/class/hwmon/hwmon2/temp3_input", .{ .mode = .read_only });
        defer hwmon.close();
        var reader = hwmon.reader(&buf);
        if (try reader.interface.takeDelimiter(0x0a)) |line| {
            const temp: f64 = @floatFromInt(try std.fmt.parseInt(i64, line, 10));
            const temp_c = temp / 1000;
            gauge.setValue(temp_c);
        } else {
            return error.CouldNotReadIdkTODO_Define_This_Error_Properly;
        }
        std.Thread.sleep(5e9);
    }
}
