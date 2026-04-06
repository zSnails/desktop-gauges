const std = @import("std");

const c = @import("../cairo.zig").c;
const color = @import("../color.zig");
const Window = @import("../window.zig");
const Context = Window.Context;
const Gauge = @import("./gauge.zig");

fn d2r(degrees: comptime_float) comptime_float {
    return degrees * (std.math.pi / 180.0);
}

const Self = @This();

ctx: *Context = undefined,

gauge_start: f64 = d2r(120.0),
gauge_end: f64 = d2r(344.0),

default_indicator_color: color.RGB = color.CYBER_YELLOW,
current_indicator_color: color.RGB = undefined,
underline_color: color.RGB = color.WHITE,
spoke_color: color.RGB = color.WHITE,
redline_color: color.RGB = color.CYBER_RED,

target_value: f64 = 0.0,
current_value: f64 = 0.0,
max_value: f64 = 8000.0,
min_value: f64 = 0.0,

gauge_indicator_level: f64 = 0.5,

radius: f64 = undefined,
center_x: f64 = undefined,
center_y: f64 = undefined,

indicator_radius: f64 = undefined,
indicator_width: f64 = undefined,
underline_radius: f64 = undefined,
spoke_radius: f64 = undefined,
spoke_width: f64 = undefined,
redline_radius: f64 = undefined,

// NOTE: I added the NUL byte just in case
value_fmt: []const u8 = "%03.0f%%\x00",
value_x: f64 = undefined,
value_y: f64 = undefined,
label_x: f64 = undefined,
label_y: f64 = undefined,
label: []const u8 = "rpm",
data_provider: ?Gauge.Provider = null,
provider_thread: std.Thread = undefined,
_gauge: ?Gauge = null,

pub fn join(gauge: *anyopaque) void {
    var self: *Self = @ptrCast(@alignCast(gauge));
    std.debug.print("joining thread\n", .{});
    self.provider_thread.join();
}

pub fn create(ctx: *Context, radius: f64, x: f64, y: f64) Self {
    return Self{
        .ctx = ctx,
        .center_y = y,
        .center_x = x,
        .radius = radius,
    };
}

pub fn init(self: *Self) !void {
    if (self.data_provider == null) {
        @panic("init called without a provider properly set, please set a provider using the setProvider function");
    }
    self.indicator_width = self.radius * 0.2;
    self.spoke_width = self.indicator_width + 5;
    self.redline_radius = self.radius;
    self.indicator_radius = self.radius - self.indicator_width / 2 - 2;
    self.underline_radius = (self.indicator_radius - self.indicator_width / 2) - 2;
    self.spoke_radius = self.indicator_radius;

    c.cairo_set_font_size(self.ctx.cairo_context, self.radius * 0.30);

    var extents: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(self.ctx.cairo_context, "0", &extents);

    self.value_x = self.center_x + self.radius * 0.4;
    self.value_y = self.center_y + self.radius * 0.4;

    self.label_x = self.value_x;
    self.label_y = self.value_y + extents.height;

    const self_interface = self.getGauge();
    const provider_thread = try std.Thread.spawn(
        .{ .allocator = std.heap.smp_allocator },
        threadMain,
        .{ self_interface, self.data_provider.? },
    );
    self.provider_thread = provider_thread;
}

fn threadMain(gauge: *Gauge, provider: Gauge.Provider) void {
    provider(gauge);
}

pub fn draw(gauge: *anyopaque) void {
    var self: *Self = @ptrCast(@alignCast(gauge));
    c.cairo_save(self.ctx.cairo_context);
    self.drawIndicator();
    self.drawIndicatorSpokes();
    self.drawIndicatorUnderline();
    self.drawIndicatorRedline();
    self.drawRpmLabel(self.label_x, self.label_y);
    self.drawRpmValue(self.value_x, self.value_y);
    c.cairo_restore(self.ctx.cairo_context);
}

pub fn setValue(gauge: *anyopaque, new_value: f64) void {
    var self: *Self = @ptrCast(@alignCast(gauge));
    const target = std.math.clamp(new_value, self.min_value, self.max_value);
    self.target_value = target;
}

pub fn update(gauge: *anyopaque) void {
    var self: *Self = @ptrCast(@alignCast(gauge));
    const smoothing: comptime_float = 1.0 / 30.0;

    self.current_value += (self.target_value - self.current_value) * smoothing;

    self.gauge_indicator_level = (self.current_value - self.min_value) / (self.max_value - self.min_value);

    self.current_indicator_color =
        if (self.current_value > self.max_value * 0.8)
            // TODO: add a redline indicator color property for this piece of
            // shit
            color.CYBER_RED
        else
            self.default_indicator_color;
}

fn drawIndicator(self: *Self) void {
    c.cairo_save(self.ctx.cairo_context);
    c.cairo_set_source_rgb(
        self.ctx.cairo_context,
        self.current_indicator_color.r,
        self.current_indicator_color.g,
        self.current_indicator_color.b,
    );
    c.cairo_set_line_width(self.ctx.cairo_context, self.indicator_width);
    c.cairo_arc(
        self.ctx.cairo_context,
        self.center_x,
        self.center_y,
        self.indicator_radius,
        self.gauge_start,
        self.gauge_start + (self.gauge_end - self.gauge_start) * self.gauge_indicator_level,
    );
    c.cairo_stroke(self.ctx.cairo_context);
    c.cairo_restore(self.ctx.cairo_context);
}

fn drawIndicatorUnderline(self: *Self) void {
    c.cairo_save(self.ctx.cairo_context);
    c.cairo_set_source_rgb(
        self.ctx.cairo_context,
        self.underline_color.r,
        self.underline_color.g,
        self.underline_color.b,
    );
    c.cairo_set_line_width(self.ctx.cairo_context, 2);
    c.cairo_arc(
        self.ctx.cairo_context,
        self.center_x,
        self.center_y,
        self.underline_radius,
        self.gauge_start,
        self.gauge_end,
    );
    c.cairo_stroke(self.ctx.cairo_context);
    c.cairo_restore(self.ctx.cairo_context);
}

fn drawIndicatorSpokes(self: *Self) void {
    c.cairo_save(self.ctx.cairo_context);
    const spoke_count = 9;
    const stride = (self.gauge_end - self.gauge_start) / @as(f64, @floatFromInt(spoke_count - 1));
    c.cairo_set_source_rgb(
        self.ctx.cairo_context,
        self.spoke_color.r,
        self.spoke_color.g,
        self.spoke_color.b,
    );

    c.cairo_set_line_width(self.ctx.cairo_context, self.spoke_width);
    for (0..spoke_count) |idx| {
        const i: f64 = @floatFromInt(idx);
        const start = self.gauge_start + (i * stride);
        c.cairo_arc(
            self.ctx.cairo_context,
            self.center_x,
            self.center_y,
            // self.radius + 2,
            self.spoke_radius,
            start,
            start + d2r(1),
        );
        c.cairo_stroke(self.ctx.cairo_context);
        // c.cairo_fill(self.ctx.cairo_context);
    }
    c.cairo_restore(self.ctx.cairo_context);
}

fn drawIndicatorRedline(self: *Self) void {
    c.cairo_save(self.ctx.cairo_context);
    // NOTE: this is cyber-red
    c.cairo_set_source_rgb(
        self.ctx.cairo_context,
        self.redline_color.r,
        self.redline_color.g,
        self.redline_color.b,
    );
    c.cairo_set_line_width(self.ctx.cairo_context, 2);
    c.cairo_arc(
        self.ctx.cairo_context,
        self.center_x,
        self.center_y,
        self.redline_radius,
        self.gauge_end - d2r(30),
        self.gauge_end,
    );
    c.cairo_stroke(self.ctx.cairo_context);
    c.cairo_restore(self.ctx.cairo_context);
}

fn drawRpmLabel(self: *Self, x: f64, y: f64) void {
    c.cairo_save(self.ctx.cairo_context);

    c.cairo_set_source_rgb(
        self.ctx.cairo_context,
        self.current_indicator_color.r,
        self.current_indicator_color.g,
        self.current_indicator_color.b,
    );
    c.cairo_move_to(self.ctx.cairo_context, x, y);
    // TODO: receive a label name for the gauge
    const label: [*c]const u8 = @ptrCast(self.label);
    c.cairo_text_path(self.ctx.cairo_context, label);
    c.cairo_fill(self.ctx.cairo_context);
    c.cairo_restore(self.ctx.cairo_context);
}

// BUG: this POS will cause a bug somewhere
const stdio = @cImport({
    @cInclude("stdio.h");
});

fn drawRpmValue(self: *Self, x: f64, y: f64) void {
    var rpmBuf: [10]u8 = undefined;
    c.cairo_save(self.ctx.cairo_context);
    c.cairo_set_source_rgb(self.ctx.cairo_context, 1, 1, 1);
    c.cairo_move_to(self.ctx.cairo_context, x, y);

    // FIXME: find an actual library to replace the builtin fmt module and stop
    // using stdio for this

    const fmt: [*c]const u8 = @ptrCast(self.value_fmt);
    _ = stdio.snprintf(@as([*c]u8, @ptrCast(&rpmBuf)), 9, fmt, self.current_value);

    c.cairo_text_path(self.ctx.cairo_context, @as([*c]const u8, @ptrCast(&rpmBuf)));
    c.cairo_fill(self.ctx.cairo_context);
    c.cairo_restore(self.ctx.cairo_context);
}

pub fn setLabel(gauge: *anyopaque, new_label: []const u8) void {
    var self: *Self = @ptrCast(@alignCast(gauge));
    self.label = new_label;
}

pub fn setMaxValue(gauge: *anyopaque, new_max_value: f64) void {
    var self: *Self = @ptrCast(@alignCast(gauge));
    self.max_value = new_max_value;
}

pub fn setMinValue(gauge: *anyopaque, new_min_value: f64) void {
    var self: *Self = @ptrCast(@alignCast(gauge));
    self.min_value = new_min_value;
}

pub fn setValueFmt(gauge: *anyopaque, new_value_fmt: []const u8) void {
    var self: *Self = @ptrCast(@alignCast(gauge));
    self.value_fmt = new_value_fmt;
}

pub fn setProvider(self: *Self, provider: Gauge.Provider) void {
    self.data_provider = provider;
}

pub fn getGauge(self: *Self) *Gauge {
    if (self._gauge == null) {
        if (@intFromPtr(self) == 0x2) {
            @panic("WTF!");
        }
        self._gauge = .{
            .ptr = self,
            .vtable = &Gauge.VTable{
                .draw = draw,
                .update = update,
                .setValue = setValue,
                .setLabel = setLabel,
                .setMaxValue = setMaxValue,
                .setMinValue = setMinValue,
                .setValueFmt = setValueFmt,
                .join = join,
            },
        };
    }
    return &self._gauge.?;
}
