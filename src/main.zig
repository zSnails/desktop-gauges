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
const temp = @import("metrics/temperature.zig");
const Window = @import("window.zig");
const Context = Window.Context;

pub fn main() !void {
    const alloc = std.heap.smp_allocator;
    var window = try Window.init(1080, 400);
    defer window.deinit();

    const context = window.getContext();

    var cluster = try Cluster.init(alloc, context);
    defer cluster.deinit();

    var temperature_gauge = Gauge.Digital.create(context, 100, 100, 100);
    temperature_gauge.setProvider(gaugeTemperatureStatusThread);
    try temperature_gauge.init();

    const interface = temperature_gauge.getGauge();

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
    gauge.setMaxValue(100.0);
    gauge.setMinValue(-100.0);
    gauge.setLabel("Temp");
    gauge.setValueFmt("%.2fC\x00");
    std.log.info("Temperature indicator loop running on cpu {}", .{std.Thread.getCurrentId()});
    while (true) {
        const temperature = temp.getTemperature();
        gauge.setValue(temperature);
        std.Thread.sleep(5e9);
    }
}
