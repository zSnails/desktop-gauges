const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const wlr = wayland.client.zwlr;

const c = @import("cairo.zig").c;

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
elapsed: f64 = undefined,
