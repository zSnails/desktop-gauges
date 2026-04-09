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

    var ram_gauge = Gauge.Digital.create(context, 100, 300, 100);
    ram_gauge.setProvider(gaugeMemoryUsageThread);
    try ram_gauge.init();
    const ram_gauge_interface = ram_gauge.getGauge();

    try cluster.addGauge(ram_gauge_interface);

    var cpu_gauge = Gauge.Digital.create(context, 100, 500, 100);
    cpu_gauge.setProvider(gaugeCpuUsageThread);
    try cpu_gauge.init();
    const cpu_gauge_interface = cpu_gauge.getGauge();

    try cluster.addGauge(cpu_gauge_interface);

    std.log.info("using cluster with {} items", .{cluster.gauges.items.len});
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

fn gaugeMemoryUsageThread(gauge: *Gauge) void {
    var ram_usage: ram.RamUsage = undefined;
    ram.getRamUsage(&ram_usage);
    gauge.setMaxValue(@as(f64, @floatFromInt(ram_usage.total)) / 1024 / 1024);
    gauge.setMinValue(0.0);
    gauge.setLabel("ram");
    gauge.setValueFmt("%.1fGiB\x00");
    std.log.info("Ram indicator loop running on cpu {}", .{std.Thread.getCurrentId()});
    while (true) {
        ram.getRamUsage(&ram_usage);
        const converted: f64 = @floatFromInt(ram_usage.total - ram_usage.available);
        const processed = converted / 1024 / 1024;
        gauge.setValue(processed);
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
