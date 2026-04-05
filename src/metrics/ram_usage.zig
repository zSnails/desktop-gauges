// MemTotal:       32788284 kB
// MemFree:        20955928 kB
// MemAvailable:   27918988 kB

const std = @import("std");
const RamUsage = struct {
    total: u64,
    free: u64,
};
// TODO: I should be using that method that uses the /proc/meminfo file
/// The return type is the total memory and the available memory
/// the used memory can be calculated by subtracting used from total
pub fn getRamUsage() RamUsage {
    var info: std.os.linux.Sysinfo = undefined;
    _ = std.os.linux.sysinfo(&info);
    const total = info.totalram * info.mem_unit;
    const free = info.freeram * info.mem_unit;

    return RamUsage{
        .total = total,
        .free = free + info.bufferram + info.freeswap,
    };
}
