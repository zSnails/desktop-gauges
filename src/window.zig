const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const wlr = wayland.client.zwlr;

const c = @import("cairo.zig").c;
const Cluster = @import("cluster.zig");

const Self = @This();

pub const Context = struct {
    const Self = @This();
    display: ?*wl.Display = null,
    width: f64 = 480.0,
    height: f64 = 480.0,
    compositor: ?*wl.Compositor = undefined,
    shared_memory: ?*wl.Shm = undefined,
    buffer: ?*wl.Buffer = undefined,
    layer_shell: ?*wlr.LayerShellV1 = undefined,
    surface: *wl.Surface = undefined,
    frame_callback: *wayland.client.wl.Callback = undefined,
    cairo_surface: ?*c.cairo_surface_t = null,
    cairo_context: ?*c.cairo_t = null,
    shared_memory_data: ?*anyopaque = null,
    delta: f64 = undefined,
    elapsed: f64 = 0.0,
};

context: Context = undefined,
cluster: ?Cluster = undefined,

pub fn init(width: f64, height: f64) !Self {
    var window = Self{
        .context = Context{
            .width = width,
            .height = height,
        },
    };
    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    window.context.display = display;

    registry.setListener(
        *Context,
        registryListener,
        &window.context,
    );
    if (display.roundtrip() != .SUCCESS) return error.RoundTripFailed;

    _ = window.context.shared_memory orelse return error.NoWaylandSharedMemory;
    const compositor = window.context.compositor orelse return error.NoWaylandCompositor;
    const layer_shell = window.context.layer_shell orelse return error.NoLayerShell;

    window.context.surface = try compositor.createSurface();

    const layer_surface = try wlr.LayerShellV1.getLayerSurface(
        layer_shell,
        window.context.surface,
        null,
        wlr.LayerShellV1.Layer.bottom,
        "desktop-gauges",
    );

    layer_surface.setListener(
        ?*anyopaque,
        layerSurfaceListener,
        null,
    );

    // TODO: I should get this from the configuration file instead of this hard
    // coded POS
    wlr.LayerSurfaceV1.setAnchor(layer_surface, .{
        .bottom = true,
        .left = true,
        .right = true,
        .top = true,
    });

    wlr.LayerSurfaceV1.setSize(
        layer_surface,
        @intFromFloat(window.context.width),
        @intFromFloat(window.context.height),
    );

    wlr.LayerSurfaceV1.setExclusiveZone(
        layer_surface,
        0,
    );

    try window.createBuffer();
    window.context.surface.commit();

    if (display.roundtrip() != .SUCCESS) return error.RoundTripFailed;

    c.cairo_set_antialias(window.context.cairo_context, c.CAIRO_ANTIALIAS_BEST);

    c.cairo_select_font_face(
        window.context.cairo_context,
        "IosevkaTerm Nerd Font Propo",
        c.CAIRO_FONT_SLANT_NORMAL,
        c.CAIRO_FONT_WEIGHT_NORMAL,
    );

    return window;
}

fn registerCallback(self: *Self) !void {
    std.debug.print("Registering initial frame callback\n", .{});
    const callback = try self.context.surface.frame();

    callback.setListener(
        *Self,
        mainDrawingFunction,
        self,
    );
    self.context.frame_callback = callback;
}

fn update(self: *Self) void {
    self.context.elapsed += self.context.delta;
    if (self.cluster) |*cluster| {
        cluster.update();
    }

    if (std.math.isNan(self.context.elapsed)) {
        std.debug.print("the elapsed time has become NaN\n", .{});
        std.process.exit(1);
    }
}

fn clearFrame(self: *Self) void {
    c.cairo_save(self.context.cairo_context);
    c.cairo_set_source_rgba(self.context.cairo_context, 0.0, 0.0, 0.0, 0.0);
    c.cairo_set_operator(self.context.cairo_context, c.CAIRO_OPERATOR_CLEAR);
    c.cairo_rectangle(self.context.cairo_context, 0, 0, self.context.width, self.context.height);
    c.cairo_paint_with_alpha(self.context.cairo_context, 1.0);
    c.cairo_set_operator(self.context.cairo_context, c.CAIRO_OPERATOR_OVER);
    c.cairo_new_path(self.context.cairo_context);
    c.cairo_restore(self.context.cairo_context);
}

fn mainDrawingFunction(cb: *wl.Callback, event: wl.Callback.Event, self: *Self) void {
    switch (event) {
        .done => |e| {
            cb.destroy();
            self.context.frame_callback = self.context.surface.frame() catch unreachable;
            self.context.frame_callback.setListener(
                *Self,
                mainDrawingFunction,
                self,
            );

            self.update();

            self.clearFrame();
            self.drawFrame();

            self.context.surface.attach(self.context.buffer, 0, 0);
            self.context.surface.damage(0, 0, @intFromFloat(self.context.width), @intFromFloat(self.context.height));
            self.context.surface.commit();
            const f: f64 = @floatFromInt(e.callback_data);
            self.context.delta = f / 1000000000.0;
        },
    }
}

pub fn showAndRun(self: *Self) !void {
    try registerCallback(self);
    self.drawFrame();

    self.context.surface.attach(self.context.buffer, 0, 0);
    self.context.surface.damage(
        0,
        0,
        @intFromFloat(self.context.width),
        @intFromFloat(self.context.height),
    );
    self.context.surface.commit();

    const display = self.context.display orelse return error.NoWaylandDisplay;

    while (display.dispatchPending() == .SUCCESS) {
        if (display.dispatch() != .SUCCESS) return error.DispatchFailed;
    }

    // TODO: here I will have to join the existing subprocesses (if any) and wait for them to die
}

pub fn getContext(self: *Self) *Context {
    return &self.context;
}

fn drawFrame(self: *Self) void {
    if (self.cluster) |*cluster| {
        cluster.draw();
    }
}

pub fn deinit(self: *Self) void {
    self.context.surface.destroy();
}

fn createBuffer(self: *Self) !void {
    const stride: i32 = @intFromFloat(self.context.width * 4);
    const size: usize = @intCast(@as(u64, @intFromFloat(self.context.height * @as(f64, @floatFromInt(stride)))));
    const fd = try std.posix.memfd_create(
        "desktop-gauges-shared-memory",
        0,
    );
    defer std.posix.close(fd);
    try std.posix.ftruncate(fd, @intCast(size));
    self.context.shared_memory_data = @ptrCast(try std.posix.mmap(
        null,
        size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        fd,
        0,
    ));
    const shm = self.context.shared_memory orelse return error.NoWlShm;
    const pool: *wl.ShmPool = try shm.createPool(fd, @intCast(size));
    defer pool.destroy();
    self.context.buffer = try pool.createBuffer(
        0,
        @intFromFloat(self.context.width),
        @intFromFloat(self.context.height),
        stride,
        wl.Shm.Format.argb8888,
    );

    self.context.cairo_surface = c.cairo_image_surface_create_for_data(
        @ptrCast(self.context.shared_memory_data),
        c.CAIRO_FORMAT_ARGB32,
        @intFromFloat(self.context.width),
        @intFromFloat(self.context.height),
        stride,
    );
    self.context.cairo_context = c.cairo_create(self.context.cairo_surface);
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
