const std = @import("std");

const Gauge = @import("../gauge/gauge.zig");
const cpu = @import("cpu_usage.zig");
const ram = @import("ram_usage.zig");
const temp = @import("temperature.zig");

// pub const MetricProvider = fn (io: std.Io, gauge: *Gauge) void;

pub fn gaugeCpuUsageThread(io: std.Io, gauge: *Gauge) void {
    gauge.setMaxValue(100);
    gauge.setLabel("cpu");
    std.log.info("CPU indicator loop running on cpu {}", .{std.Thread.getCurrentId()});
    while (true) {
        const cpu_usage = cpu.getCpuUsage(io) catch unreachable;
        gauge.setValue(cpu_usage * 100);
        io.sleep(std.Io.Duration.fromSeconds(5), std.Io.Clock.real) catch unreachable;
    }
}

pub fn gaugeMemoryUsageThread(io: std.Io, gauge: *Gauge) void {
    // safety: this will be set in the call to getRamUsage below
    var ram_usage: ram.RamUsage = undefined;
    ram.getRamUsage(io, &ram_usage);
    gauge.setMaxValue(@as(f64, @floatFromInt(ram_usage.total)) / 1024 / 1024);
    gauge.setMinValue(0.0);
    gauge.setLabel("ram");
    gauge.setValueFmt("%.1fGiB\x00");
    std.log.info("Ram indicator loop running on cpu {}", .{std.Thread.getCurrentId()});
    while (true) {
        ram.getRamUsage(io, &ram_usage);
        const converted: f64 = @floatFromInt(ram_usage.total - ram_usage.available);
        const processed = converted / 1024 / 1024;
        gauge.setValue(processed);
        io.sleep(std.Io.Duration.fromSeconds(5), std.Io.Clock.real) catch unreachable;
    }
}

pub fn gaugeTemperatureStatusThread(io: std.Io, gauge: *Gauge) void {
    gauge.setMaxValue(100.0);
    gauge.setMinValue(-100.0);
    gauge.setLabel("temp");
    gauge.setValueFmt("%.2fC\x00");
    std.log.info("Temperature indicator loop running on cpu {}", .{std.Thread.getCurrentId()});
    while (true) {
        const temperature = temp.getTemperature(io);
        gauge.setValue(temperature);
        io.sleep(std.Io.Duration.fromSeconds(5), std.Io.Clock.real) catch unreachable;
    }
}

pub const MetricProvider = enum(i8) {
    cpu = 0,
    memory = 1,
    temperature = 2,
};

pub fn getMetricProvider(provider: MetricProvider) Gauge.Provider {
    return switch (provider) {
        .cpu => &gaugeCpuUsageThread,
        .memory => &gaugeMemoryUsageThread,
        .temperature => &gaugeTemperatureStatusThread,
    };
}
