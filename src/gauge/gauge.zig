pub const Digital = @import("./digital.zig");

pub const Self = @This();
pub const Provider = *const fn (gauge: *Self) void;

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    draw: *const fn (gauge: *anyopaque) void,
    update: *const fn (gauge: *anyopaque) void,
    setValue: *const fn (gauge: *anyopaque, new_value: f64) void,
    setMaxValue: *const fn (gauge: *anyopaque, new_max_value: f64) void,
    setMinValue: *const fn (gauge: *anyopaque, new_min_value: f64) void,
    setLabel: *const fn (gauge: *anyopaque, new_label: []const u8) void,
    setValueFmt: *const fn (gauge: *anyopaque, new_value_fmt: []const u8) void,
    join: *const fn (gauge: *anyopaque) void,
};

pub fn join(self: *Self) void {
    self.vtable.join(self.ptr);
}

pub fn draw(self: *Self) void {
    self.vtable.draw(self.ptr);
}

pub fn update(self: *Self) void {
    self.vtable.update(self.ptr);
}

pub fn setValue(self: *Self, new_value: f64) void {
    self.vtable.setValue(self.ptr, new_value);
}

pub fn setMaxValue(self: *Self, new_max_value: f64) void {
    self.vtable.setMaxValue(self.ptr, new_max_value);
}

pub fn setMinValue(self: *Self, new_min_value: f64) void {
    self.vtable.setMinValue(self.ptr, new_min_value);
}

pub fn setLabel(self: *Self, new_label: []const u8) void {
    self.vtable.setLabel(self.ptr, new_label);
}

pub fn setValueFmt(self: *Self, new_value_fmt: []const u8) void {
    self.vtable.setValueFmt(self.ptr, new_value_fmt);
}
