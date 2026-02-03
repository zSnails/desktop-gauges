const std = @import("std");

const c = @import("cairo.zig").c;
const Context = @import("context.zig");
const color = @import("color.zig");

fn d2r(degrees: comptime_float) comptime_float {
    return degrees * (std.math.pi / 180.0);
}

const Self = @This();

ctx: *Context = undefined,

gauge_start: f64 = d2r(120.0),
gauge_end: f64 = d2r(344.0),

indicator_color: color.RGB = color.CYBER_YELLOW,
underline_color: color.RGB = color.WHITE,
spoke_color: color.RGB = color.WHITE,
redline_color: color.RGB = color.CYBER_RED,

target_value: f64 = 0.0,
current_value: f64 = 0.0,
max_value: f64 = 8000.0,

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

value_x: f64 = undefined,
value_y: f64 = undefined,
label_x: f64 = undefined,
label_y: f64 = undefined,

pub fn create(ctx: *Context, radius: f64, x: f64, y: f64) Self {
    return Self{
        .ctx = ctx,
        .center_y = y,
        .center_x = x,
        .radius = radius,
    };
}

pub fn init(self: *Self) void {
    self.indicator_width = self.radius * 0.2;
    self.spoke_width = self.indicator_width + 5;
    self.redline_radius = self.radius;
    self.indicator_radius = self.radius - self.indicator_width / 2 - 2;
    self.underline_radius = (self.indicator_radius - self.indicator_width / 2) - 2;
    self.spoke_radius = self.indicator_radius;

    c.cairo_set_font_size(self.ctx.cairo_context, self.radius * 0.30);

    var extents: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(self.ctx.cairo_context, "0", &extents);

    std.debug.print("got glyph height of = {}\n", .{extents.height});

    self.value_x = self.center_x + self.radius * 0.4;
    self.value_y = self.center_y + self.radius * 0.4;

    self.label_x = self.value_x;
    self.label_y = self.value_y + extents.height;
}

pub fn draw(self: *Self) void {
    c.cairo_save(self.ctx.cairo_context);
    self.drawIndicator();
    self.drawIndicatorSpokes();
    self.drawIndicatorUnderline();
    self.drawIndicatorRedline();
    self.drawRpmLabel(self.label_x, self.label_y);
    self.drawRpmValue(self.value_x, self.value_y);
    c.cairo_restore(self.ctx.cairo_context);
}

pub fn set_rpm(self: *Self, new_rpm: f64) void {
    self.target_value = new_rpm;
}

pub fn update(self: *Self) void {
    const smoothing = 0.09;

    self.current_value += (self.target_value - self.current_value) * smoothing;

    self.gauge_indicator_level = self.current_value / self.max_value;

    self.indicator_color =
        if (self.current_value > 6800)
            color.CYBER_RED
        else
            color.CYBER_YELLOW;
}

fn drawIndicator(self: *Self) void {
    c.cairo_save(self.ctx.cairo_context);
    // c.cairo_set_source_rgb(self.ctx.cairo_context, 1.0, 0.9294117647, 0.3058823529);
    c.cairo_set_source_rgb(
        self.ctx.cairo_context,
        self.indicator_color.r,
        self.indicator_color.g,
        self.indicator_color.b,
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
    // c.cairo_set_line_width(self.ctx.cairo_context, self.radius * 0.10);
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
            start + d2r(0.5),
        );
        c.cairo_stroke(self.ctx.cairo_context);
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
        // self.radius * 1.15,
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
        self.indicator_color.r,
        self.indicator_color.g,
        self.indicator_color.b,
    );
    c.cairo_move_to(self.ctx.cairo_context, x, y);
    // TODO: receive a label name for the gauge
    c.cairo_text_path(self.ctx.cairo_context, "rpm");
    c.cairo_fill(self.ctx.cairo_context);
    c.cairo_restore(self.ctx.cairo_context);
}

fn drawRpmValue(self: *Self, x: f64, y: f64) void {
    var rpmBuf: [6]u8 = undefined;
    c.cairo_save(self.ctx.cairo_context);
    c.cairo_set_source_rgb(self.ctx.cairo_context, 1, 1, 1);
    c.cairo_move_to(self.ctx.cairo_context, x, y);
    const rpm = std.fmt.bufPrintZ(&rpmBuf, "{: >4.0}", .{self.current_value}) catch unreachable;
    c.cairo_text_path(self.ctx.cairo_context, rpm);
    c.cairo_fill(self.ctx.cairo_context);
    c.cairo_restore(self.ctx.cairo_context);
}
