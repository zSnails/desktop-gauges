const std = @import("std");
const Instant = std.time.Instant;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const wlr = wayland.client.zwlr;

const c = @import("cairo.zig").c;
const Cluster = @import("cluster.zig");
const Context = @import("context.zig");
const Gauge = @import("gauge.zig");

var total_elapsed_time: f64 = 0.0;

const t = @cImport({
    @cInclude("time.h");
    @cInclude("bits/time.h");
});

var cluster: Cluster = undefined;

pub fn main() !void {
    var context = Context{};
    const allocator = std.heap.smp_allocator;
    cluster = try Cluster.init(allocator, &context);
    defer cluster.deinit();

    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    registry.setListener(*Context, registryListener, &context);
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    _ = context.shared_memory orelse return error.NoWlShm;
    const compositor = context.compositor orelse return error.NoWlCompositor;
    const layer_shell_v1 = context.layer_shell orelse return error.NoLayerShellV1;

    const width = 480;
    const height = 480;
    context.surface = try compositor.createSurface();
    defer context.surface.destroy();

    const layer_surface_v1 = try wlr.LayerShellV1.getLayerSurface(
        layer_shell_v1,
        context.surface,
        null,
        wlr.LayerShellV1.Layer.bottom,
        "desktop-gauges",
    );

    layer_surface_v1.setListener(?*anyopaque, layerSurfaceListener, null);

    wlr.LayerSurfaceV1.setAnchor(
        layer_surface_v1,
        .{ .bottom = true, .left = true, .right = true, .top = true },
    );

    wlr.LayerSurfaceV1.setSize(
        layer_surface_v1,
        width,
        height,
    );
    wlr.LayerSurfaceV1.setExclusiveZone(
        layer_surface_v1,
        0,
    );

    try createBuffer(&context, width, height);

    context.surface.commit();
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    c.cairo_set_antialias(context.cairo_context, c.CAIRO_ANTIALIAS_BEST);

    var main_gauge = Gauge.create(&context, 100, 150, 150);
    main_gauge.init();
    var other_gauge = Gauge.create(&context, 150, 300, 200);
    other_gauge.init();

    try cluster.appendGauge(&main_gauge);
    try cluster.appendGauge(&other_gauge);

    std.debug.print("creating initial frame callback\n", .{});
    const callback = try context.surface.frame();
    callback.setListener(*Context, &mainDrawingFunction, &context);
    std.debug.print("created the initial frame callback\n", .{});

    c.cairo_select_font_face(
        context.cairo_context,
        "Rajdhani",
        c.CAIRO_FONT_SLANT_NORMAL,
        c.CAIRO_FONT_WEIGHT_NORMAL,
    );

    const thread = try std.Thread.spawn(.{ .allocator = allocator }, TEST_GAUGE_INDICATOR_ANIMATION, .{&cluster});
    thread.detach();

    // FIXME: I guess this is a bug, but I have to manually draw the first
    // frame before this POS begins drawing, I know this is because before
    // comitting the surface there won't be any previous frame so the client
    // does not begin drawing (see main_drawing_function)
    drawFrame(&context, 480, 480);

    context.surface.attach(context.buffer, 0, 0);
    context.surface.damage(0, 0, 480, 480);
    context.surface.commit();

    main_gauge.set_rpm(0.0);
    other_gauge.set_rpm(0.0);

    while (display.dispatchPending() == .SUCCESS) {
        if (display.dispatch() != .SUCCESS) return error.DispatchFailed;
    }
}

fn createBuffer(ctx: *Context, width: i32, height: i32) !void {
    const stride = width * 4;
    const size: usize = @intCast(height * stride);
    const fd = try std.posix.memfd_create(
        "desktop-gauges-shared-memory",
        0,
    );
    defer std.posix.close(fd);
    try std.posix.ftruncate(fd, @intCast(size));
    ctx.shared_memory_data = @ptrCast(try std.posix.mmap(
        null,
        size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        fd,
        0,
    ));
    const shm = ctx.shared_memory orelse return error.NoWlShm;
    const pool: *wl.ShmPool = try shm.createPool(fd, @intCast(size));
    defer pool.destroy();
    ctx.buffer = try pool.createBuffer(
        0,
        width,
        height,
        stride,
        wl.Shm.Format.argb8888,
    );

    ctx.cairo_surface = c.cairo_image_surface_create_for_data(
        @ptrCast(ctx.shared_memory_data),
        c.CAIRO_FORMAT_ARGB32,
        width,
        height,
        stride,
    );
    ctx.cairo_context = c.cairo_create(ctx.cairo_surface);
}

fn TEST_GAUGE_INDICATOR_ANIMATION(global_cluster: *Cluster) !void {
    const rand = std.crypto.random;
    std.debug.print("Beginning test indicator animator loop\n", .{});
    while (true) {
        for (global_cluster.gauges.items) |gauge| {
            const new_rpm = rand.float(f64) * 8000.0;
            gauge.set_rpm(new_rpm);
        }
        std.Thread.sleep(0.4e9);
    }
}

fn mainDrawingFunction(cb: *wl.Callback, event: wl.Callback.Event, ctx: *Context) void {
    switch (event) {
        .done => |e| {
            cb.destroy();
            ctx.frame_callback = ctx.surface.frame() catch unreachable;
            ctx.frame_callback.setListener(
                *Context,
                mainDrawingFunction,
                ctx,
            );

            update(ctx, ctx.delta);

            // FIXME: propagate the actual width and height of this POS
            clearFrame(ctx, 480, 480);
            drawFrame(ctx, 480, 480);

            ctx.surface.attach(ctx.buffer, 0, 0);
            ctx.surface.damage(0, 0, 480, 480);
            ctx.surface.commit();
            const f: f64 = @floatFromInt(e.callback_data);
            ctx.delta = f / 1000000000.0;
        },
    }
}

fn update(ctx: *Context, dt: f64) void {
    ctx.elapsed += dt;

    cluster.update();
    // std.debug.print("running update loop, current elapsed time = {}\n", .{total_elapsed_time});
    if (std.math.isNan(total_elapsed_time)) {
        std.debug.print("total_elapsed_time has become NaN\n", .{});
        std.process.exit(1);
    }
}

fn clearFrame(ctx: *Context) void {
    c.cairo_save(ctx.cairo_context);
    c.cairo_set_source_rgba(ctx.cairo_context, 0.0, 0.0, 0.0, 0.0);
    c.cairo_set_operator(ctx.cairo_context, c.CAIRO_OPERATOR_CLEAR);
    c.cairo_rectangle(ctx.cairo_context, 0, 0, ctx.width, ctx.height);
    c.cairo_paint_with_alpha(ctx.cairo_context, 1.0);
    c.cairo_set_operator(ctx.cairo_context, c.CAIRO_OPERATOR_OVER);
    c.cairo_new_path(ctx.cairo_context);
    c.cairo_restore(ctx.cairo_context);
}

fn drawFrame(ctx: *Context) void {
    _ = ctx; // autofix
    cluster.draw();
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    switch (event) {
        .global => |global| {
            if (std.mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                context.compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                context.shared_memory = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, wlr.LayerShellV1.interface.name) == .eq) {
                context.layer_shell = registry.bind(global.name, wlr.LayerShellV1, 1) catch return;
            }
        },
        .global_remove => {},
    }
}

fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, surface: *wl.Surface) void {
    switch (event) {
        .configure => |configure| {
            xdg_surface.ackConfigure(configure.serial);
            surface.commit();
        },
    }
}
fn layerSurfaceListener(layer_surface: *wlr.LayerSurfaceV1, event: wlr.LayerSurfaceV1.Event, _: ?*anyopaque) void {
    switch (event) {
        .configure => |configure| {
            layer_surface.ackConfigure(configure.serial);
        },
        .closed => {
            std.debug.print("this piece of shit just closed\n", .{});
        },
    }
}

fn xdgToplevelListener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, running: *bool) void {
    switch (event) {
        .configure => {},
        .close => running.* = false,
    }
}
