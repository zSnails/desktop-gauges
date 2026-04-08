// MemTotal:       32788284 kB
// MemFree:        20955928 kB
// MemAvailable:   27918988 kB

const std = @import("std");
pub const RamUsage = struct {
    total: u64,
    available: u64,
};

threadlocal var buf: [1024]u8 = undefined;
pub fn getRamUsage(usage: *RamUsage) void {
    const meminfo = std.fs.openFileAbsolute(
        "/proc/meminfo",
        .{
            .mode = .read_only,
        },
    ) catch |err| {
        std.log.err("error reading meminfo: {}", .{err});
        std.process.exit(1);
    };
    defer meminfo.close();

    var reader = meminfo.reader(&buf);
    if (reader.interface.takeDelimiter(0xA) catch unreachable) |line| {
        std.log.debug("this is the line we got: {s}", .{line});
        var total_iterator = std.mem.tokenizeScalar(u8, line, ' ');
        std.log.debug("total_iterator = {}", .{total_iterator});
        _ = total_iterator.next(); // this pos skips the first fucker
        const total = total_iterator.next().?; // this fucker takes the pos
        usage.total = std.fmt.parseInt(u64, total, 10) catch |err| {
            std.log.err("error parsing total mem: {}", .{err});
            std.process.exit(1);
        };
    }
    _ = reader.interface.takeDelimiter(0xA) catch |err| {
        std.log.err("error skipping MemFree line: {}", .{err});
    }; // this pos skips the mem free line in favor of the mem available line
    if (reader.interface.takeDelimiter(0xA) catch unreachable) |line| {
        std.log.debug("this is the line we got: {s}", .{line});
        var free_iterator = std.mem.tokenizeScalar(u8, line, ' ');
        _ = free_iterator.next(); // again, this fucker skips the title pos
        const free = free_iterator.next().?; // this pos is the actual value
        usage.available = std.fmt.parseInt(u64, free, 10) catch |err| {
            std.log.err("error parsing free mem: {}", .{err});
            std.process.exit(1);
        };
    }
}
