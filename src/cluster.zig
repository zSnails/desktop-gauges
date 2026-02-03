const std = @import("std");
const Gauge = @import("gauge.zig");
const c = @import("cairo.zig").c;

const Self = @This();
const Window = @import("window.zig");
const Context = Window.Context;

allocator: std.mem.Allocator = undefined,
gauges: std.ArrayList(*Gauge) = undefined,
context: *Context = undefined,

pub fn init(allocator: std.mem.Allocator, context: *Context) !Self {
    const result = Self{
        .allocator = allocator,
        .gauges = try std.ArrayList(*Gauge).initCapacity(allocator, 3),
        .context = context,
    };

    return result;
}

pub fn deinit(self: *Self) void {
    self.gauges.deinit(self.allocator);
}

pub fn draw(self: *Self) void {
    c.cairo_save(self.context.cairo_context);
    for (self.gauges.items) |gauge| {
        gauge.draw();
    }
    c.cairo_restore(self.context.cairo_context);
}

pub fn update(self: *Self) void {
    for (self.gauges.items) |gauge| {
        gauge.update();
    }
}

pub fn appendGauge(self: *Self, gauge: *Gauge) !void {
    try self.gauges.append(self.allocator, gauge);
}
