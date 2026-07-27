const MetricProvider = @import("metrics/providers.zig").MetricProvider;

pub const Anchor = struct {
    left: bool = false,
    right: bool = false,
    top: bool = false,
    bottom: bool = false,
};

pub const GaugeConfig = struct {
    x: f64 = 0,
    y: f64 = 0,
    radius: f64 = 0,
    provider: MetricProvider,
};

pub const ViewportConfig = struct {
    anchor: Anchor,
};

pub const ClusterConfig = struct {
    gauges: []GaugeConfig,
    viewport: ViewportConfig,
};

pub const Config = struct {
    clusters: []ClusterConfig,
};
