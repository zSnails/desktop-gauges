const std = @import("std");

threadlocal var prev_total: i64 = 0;
threadlocal var prev_non_idle: i64 = 0;
threadlocal var prev_idle: i64 = 0;

/// TODO: I need to get individual cpu usage, basically this but for every cpu
/// in my pc, then I'll return some kind of array with every usage value
pub fn getCpuUsage() !f64 {
    const file = try std.fs.openFileAbsolute(
        "/proc/stat",
        .{ .mode = .read_only },
    );
    defer file.close();

    var buf: [1024]u8 = undefined;

    var reader = file.reader(&buf);
    if (try reader.interface.takeDelimiter('\n')) |line| {
        var dataIterator = std.mem.splitAny(u8, line, " ");
        // FIXME: this way of parsing is pretty stupid, I'm guessing there's
        // some kind of syscall that exists for this purpose
        _ = dataIterator.next().?; // this removes the initial "cpu" string
        _ = dataIterator.next().?; // this removes the initial " " string
        const pre_user = dataIterator.next().?;
        const user = try std.fmt.parseInt(i64, pre_user, 10);
        const nice = try std.fmt.parseInt(i64, dataIterator.next().?, 10);
        const system = try std.fmt.parseInt(i64, dataIterator.next().?, 10);
        const idle = try std.fmt.parseInt(i64, dataIterator.next().?, 10);
        const iowait = try std.fmt.parseInt(i64, dataIterator.next().?, 10);
        const irq = try std.fmt.parseInt(i64, dataIterator.next().?, 10);
        const softirq = try std.fmt.parseInt(i64, dataIterator.next().?, 10);
        const steal = try std.fmt.parseInt(i64, dataIterator.next().?, 10);

        const total_idle = idle + iowait;
        const non_idle = user + nice + system + irq + softirq + steal;
        const total = total_idle + non_idle;

        const totald = total - prev_total;
        const idled = total_idle - prev_idle;

        prev_non_idle = non_idle;
        prev_total = total;
        prev_idle = total_idle;
        if (totald == 0) return 0;
        return @as(f64, @floatFromInt(totald - idled)) / @as(f64, @floatFromInt(totald));
    }

    return 0;
}
