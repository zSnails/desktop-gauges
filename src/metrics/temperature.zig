const std = @import("std");

threadlocal var buf: [1024]u8 = undefined;

pub fn getTemperature(io: std.Io) f64 {
    const hwmon = std.Io.Dir.openFileAbsolute(
        io,
        "/sys/class/hwmon/hwmon1/temp3_input",
        .{ .mode = .read_only },
    ) catch |err| {
        std.log.err("error reading temp3_input: {}", .{err});
        std.process.exit(1);
    };
    defer hwmon.close(io);
    var reader = hwmon.reader(io, &buf);
    if (reader.interface.takeDelimiter(0xA) catch unreachable) |line| {
        const temp: f64 = @floatFromInt(std.fmt.parseInt(i64, line, 10) catch unreachable);
        const temp_c = temp / 1000;
        return temp_c;
    } else {
        std.log.err("could not read temperature", .{});
        return 0;
    }
}
