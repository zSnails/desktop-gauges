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
    gauge.setProvider(gaugeTemperatureStatusThread);
    try gauge.init();

    const interface = gauge.getGauge();

    try cluster.addGauge(interface);

    var ram_gauge = Gauge.Digital.create(context, 200, 700, 200);
    ram_gauge.setProvider(gaugeCpuUsageThread);
    try ram_gauge.init();
    const ram_gauge_interface = ram_gauge.getGauge();

    try cluster.addGauge(ram_gauge_interface);

    window.cluster = cluster;

    try window.showAndRun();
}

// TODO: find a way of abstracting away these pieces of shit

fn gaugeCpuUsageThread(gauge: *Gauge) void {
    gauge.setMaxValue(100);
    gauge.setLabel("cpu");
    std.log.info("CPU indicator loop running on cpu {}", .{std.Thread.getCurrentId()});
    while (true) {
        const cpu_usage = cpu.getCpuUsage() catch unreachable;
        gauge.setValue(cpu_usage * 100);
        std.Thread.sleep(5e9);
    }
}

fn gaugeMemoryUsageThread(gauge: *Gauge) !void {
    const ram_usage = ram.getRamUsage();
    gauge.setMaxValue(@floatFromInt(ram_usage.total / 1024 / 1024 / 1024));
    gauge.setMinValue(0.0);
    gauge.setLabel("ram");
    gauge.setValueFmt("%.0fGiB\x00");
    std.log.info("Ram indicator loop running on cpu {}", .{std.Thread.getCurrentId()});
    while (true) {
        const usage = ram.getRamUsage();
        const _u: f64 = @floatFromInt(usage.total - usage.free);
        gauge.setValue(_u / 1024 / 1024 / 1024);
        std.log.debug("usage = {}", .{ram_usage});
        std.log.debug("actual value we got: {}", .{converted});
        std.log.debug("after being processed: {}", .{processed});
        std.Thread.sleep(5e9);
    }
}

fn gaugeTemperatureStatusThread(gauge: *Gauge) void {
    // /sys/class/hwmon/hwmon2/temp3_input
    gauge.setMaxValue(100.0);
    gauge.setMinValue(-100.0);
    gauge.setLabel("Temp");
    gauge.setValueFmt("%.2fC\x00");
    var buf: [1024]u8 = undefined;
    std.log.info("Temperature indicator loop running on cpu {}", .{std.Thread.getCurrentId()});
    while (true) {
        const hwmon = std.fs.openFileAbsolute(
            "/sys/class/hwmon/hwmon2/temp3_input",
            .{ .mode = .read_only },
        ) catch unreachable;
        defer hwmon.close();
        var reader = hwmon.reader(&buf);
        if (reader.interface.takeDelimiter(0x0a) catch unreachable) |line| {
            const temp: f64 = @floatFromInt(std.fmt.parseInt(i64, line, 10) catch unreachable);
            const temp_c = temp / 1000;
            gauge.setValue(temp_c);
        } else {
            @panic("error.CouldNotReadIdkTODO_Define_This_Error_Properly");
            // return error.CouldNotReadIdkTODO_Define_This_Error_Properly;
        }
        std.Thread.sleep(5e9);
    }
}
