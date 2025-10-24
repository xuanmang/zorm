const std = @import("std");
const Allocator = std.mem.Allocator;
const core_types = @import("../core/types.zig");

/// Row 接口 (由驱动实现,使用 VTable 实现多态)
///
/// 注意: VTable 中的函数返回固定类型 (i64, f64),
/// 实际类型转换在 getFieldValue 中完成
pub const Row = struct {
    driver_row: *anyopaque,
    vtable: *const RowVTable,

    pub const RowVTable = struct {
        isNull: *const fn (*anyopaque, usize) bool,
        getInt: *const fn (*anyopaque, usize) anyerror!i64,
        getFloat: *const fn (*anyopaque, usize) anyerror!f64,
        getBool: *const fn (*anyopaque, usize) anyerror!bool,
        getString: *const fn (*anyopaque, usize) anyerror![]const u8,
        getBytes: *const fn (*anyopaque, usize) anyerror![]const u8,
    };

    /// 检查字段是否为 NULL
    pub fn isNull(self: *Row, index: usize) bool {
        return self.vtable.isNull(self.driver_row, index);
    }

    /// 获取整数值 (返回 i64, 调用者负责类型转换)
    pub fn getInt(self: *Row, index: usize) !i64 {
        return self.vtable.getInt(self.driver_row, index);
    }

    /// 获取浮点数值 (返回 f64, 调用者负责类型转换)
    pub fn getFloat(self: *Row, index: usize) !f64 {
        return self.vtable.getFloat(self.driver_row, index);
    }

    /// 获取布尔值
    pub fn getBool(self: *Row, index: usize) !bool {
        return self.vtable.getBool(self.driver_row, index);
    }

    /// 获取字符串
    pub fn getString(self: *Row, index: usize) ![]const u8 {
        return self.vtable.getString(self.driver_row, index);
    }

    /// 获取字节数组
    pub fn getBytes(self: *Row, index: usize) ![]const u8 {
        return self.vtable.getBytes(self.driver_row, index);
    }
};

/// 将数据库行扫描到结构体 T (编译时生成映射逻辑)
///
/// 此函数在编译时为每个结构体类型 T 生成专用的映射代码,实现零运行时开销。
///
/// 参数:
/// - T: 目标结构体类型
/// - row: 数据库行对象
/// - allocator: 内存分配器(用于复制字符串等需要分配内存的字段)
///
/// 返回:
/// - T 类型的结构体实例
///
/// 错误:
/// - 如果字段类型不支持或值转换失败,返回相应错误
pub fn scanRow(comptime T: type, row: *Row, allocator: Allocator) !T {
    var result: T = undefined;

    const fields = @typeInfo(T).@"struct".fields;
    inline for (fields, 0..) |field, i| {
        const field_value = try getFieldValue(field.type, row, i, allocator);
        @field(result, field.name) = field_value;
    }

    return result;
}

/// 获取字段值 (根据类型)
///
/// 此函数根据字段类型从数据库行中提取值,支持:
/// - 整数类型 (i8, i16, i32, i64, u8, u16, u32, u64)
/// - 浮点类型 (f32, f64)
/// - 布尔类型
/// - 字符串 ([]const u8, []u8)
/// - 可选类型 (?T)
/// - 字节数组
///
/// 参数:
/// - FieldType: 字段的类型
/// - row: 数据库行对象
/// - index: 字段在行中的索引
/// - allocator: 内存分配器
///
/// 返回:
/// - FieldType 类型的值
///
/// 错误:
/// - UnsupportedType: 不支持的类型
/// - 数据库驱动返回的错误
fn getFieldValue(comptime FieldType: type, row: *Row, index: usize, allocator: Allocator) !FieldType {
    const type_info = @typeInfo(FieldType);

    // 处理可选类型
    if (type_info == .optional) {
        if (row.isNull(index)) {
            return null;
        }
        const child_type = type_info.optional.child;
        return try getFieldValue(child_type, row, index, allocator);
    }

    // 处理基础类型
    switch (type_info) {
        .int => |int_info| {
            const value = try row.getInt(index);
            if (int_info.signedness == .signed) {
                return @intCast(value);
            } else {
                // 将有符号值转换为无符号值
                return @intCast(@as(u64, @bitCast(value)));
            }
        },
        .float => {
            const value = try row.getFloat(index);
            return @floatCast(value);
        },
        .bool => {
            return try row.getBool(index);
        },
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                // []const u8 或 []u8 (字符串或字节数组)
                const str = try row.getString(index);
                if (ptr_info.is_const) {
                    return str; // 借用 row 的内存
                } else {
                    return try allocator.dupe(u8, str); // 复制字符串
                }
            }

            // 数组类型反序列化 (切片,非 []const u8)
            if (ptr_info.size == .slice and ptr_info.child != u8) {
                const pg_array_str = try row.getString(index);
                var result = try core_types.deserializeArray(ptr_info.child, pg_array_str, allocator);
                return result.toOwnedSlice(allocator);
            }

            return error.UnsupportedType;
        },
        .array => |arr_info| {
            // UUID 类型反序列化 ([16]u8)
            if (arr_info.len == 16 and arr_info.child == u8) {
                const uuid_str = try row.getString(index);
                return try core_types.stringToUuid(uuid_str);
            }
            return error.UnsupportedType;
        },
        else => return error.UnsupportedType,
    }
}

// ============================================================
// 测试
// ============================================================

/// 测试用的模拟 Row 实现
const MockRow = struct {
    values: []const ?[]const u8,

    fn isNull(ptr: *anyopaque, index: usize) bool {
        const self: *const MockRow = @ptrCast(@alignCast(ptr));
        return self.values[index] == null;
    }

    fn getInt(ptr: *anyopaque, index: usize) !i64 {
        const self: *const MockRow = @ptrCast(@alignCast(ptr));
        const val_str = self.values[index] orelse return error.NullValue;
        return try std.fmt.parseInt(i64, val_str, 10);
    }

    fn getFloat(ptr: *anyopaque, index: usize) !f64 {
        const self: *const MockRow = @ptrCast(@alignCast(ptr));
        const val_str = self.values[index] orelse return error.NullValue;
        return try std.fmt.parseFloat(f64, val_str);
    }

    fn getBool(ptr: *anyopaque, index: usize) !bool {
        const self: *const MockRow = @ptrCast(@alignCast(ptr));
        const val_str = self.values[index] orelse return error.NullValue;
        return std.mem.eql(u8, val_str, "true") or std.mem.eql(u8, val_str, "1");
    }

    fn getString(ptr: *anyopaque, index: usize) ![]const u8 {
        const self: *const MockRow = @ptrCast(@alignCast(ptr));
        return self.values[index] orelse return error.NullValue;
    }

    fn getBytes(ptr: *anyopaque, index: usize) ![]const u8 {
        return getString(ptr, index);
    }

    const vtable: Row.RowVTable = .{
        .isNull = isNull,
        .getInt = getInt,
        .getFloat = getFloat,
        .getBool = getBool,
        .getString = getString,
        .getBytes = getBytes,
    };
};

test "scanRow - basic types" {
    const TestRow = struct {
        id: i64,
        name: []const u8,
        age: u32,
        active: bool,
    };

    const mock_values = [_]?[]const u8{ "123", "Alice", "25", "true" };
    var mock_row_instance = MockRow{ .values = &mock_values };

    var row = Row{
        .driver_row = @ptrCast(&mock_row_instance),
        .vtable = &MockRow.vtable,
    };

    const result = try scanRow(TestRow, &row, std.testing.allocator);

    try std.testing.expectEqual(@as(i64, 123), result.id);
    try std.testing.expectEqualStrings("Alice", result.name);
    try std.testing.expectEqual(@as(u32, 25), result.age);
    try std.testing.expect(result.active);
}

test "scanRow - optional types" {
    const TestRow = struct {
        id: i64,
        name: []const u8,
        email: ?[]const u8,
        age: ?u32,
    };

    const mock_values = [_]?[]const u8{ "456", "Bob", null, "30" };
    var mock_row_instance = MockRow{ .values = &mock_values };

    var row = Row{
        .driver_row = @ptrCast(&mock_row_instance),
        .vtable = &MockRow.vtable,
    };

    const result = try scanRow(TestRow, &row, std.testing.allocator);

    try std.testing.expectEqual(@as(i64, 456), result.id);
    try std.testing.expectEqualStrings("Bob", result.name);
    try std.testing.expectEqual(@as(?[]const u8, null), result.email);
    try std.testing.expectEqual(@as(?u32, 30), result.age);
}

test "scanRow - float types" {
    const TestRow = struct {
        id: i64,
        price: f64,
        discount: f32,
    };

    const mock_values = [_]?[]const u8{ "1", "99.99", "0.15" };
    var mock_row_instance = MockRow{ .values = &mock_values };

    var row = Row{
        .driver_row = @ptrCast(&mock_row_instance),
        .vtable = &MockRow.vtable,
    };

    const result = try scanRow(TestRow, &row, std.testing.allocator);

    try std.testing.expectEqual(@as(i64, 1), result.id);
    try std.testing.expectApproxEqAbs(@as(f64, 99.99), result.price, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.15), result.discount, 0.01);
}

test "getFieldValue - int types" {
    const mock_values = [_]?[]const u8{"42"};
    var mock_row_instance = MockRow{ .values = &mock_values };

    var row = Row{
        .driver_row = @ptrCast(&mock_row_instance),
        .vtable = &MockRow.vtable,
    };

    const i32_val = try getFieldValue(i32, &row, 0, std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 42), i32_val);

    const i64_val = try getFieldValue(i64, &row, 0, std.testing.allocator);
    try std.testing.expectEqual(@as(i64, 42), i64_val);

    const mock_values2 = [_]?[]const u8{"100"};
    var mock_row_instance2 = MockRow{ .values = &mock_values2 };
    var row2 = Row{
        .driver_row = @ptrCast(&mock_row_instance2),
        .vtable = &MockRow.vtable,
    };

    const u32_val = try getFieldValue(u32, &row2, 0, std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 100), u32_val);
}

test "getFieldValue - optional int returns null" {
    const mock_values = [_]?[]const u8{null};
    var mock_row_instance = MockRow{ .values = &mock_values };

    var row = Row{
        .driver_row = @ptrCast(&mock_row_instance),
        .vtable = &MockRow.vtable,
    };

    const optional_val = try getFieldValue(?i32, &row, 0, std.testing.allocator);
    try std.testing.expectEqual(@as(?i32, null), optional_val);
}

test "Row interface - all methods" {
    const mock_values = [_]?[]const u8{ "123", "45.67", "true", "test" };
    var mock_row_instance = MockRow{ .values = &mock_values };

    var row = Row{
        .driver_row = @ptrCast(&mock_row_instance),
        .vtable = &MockRow.vtable,
    };

    try std.testing.expectEqual(false, row.isNull(0));
    try std.testing.expectEqual(@as(i64, 123), try row.getInt(0));
    try std.testing.expectEqual(@as(f64, 45.67), try row.getFloat(1));
    try std.testing.expectEqual(true, try row.getBool(2));
    try std.testing.expectEqualStrings("test", try row.getString(3));
    try std.testing.expectEqualStrings("test", try row.getBytes(3));
}
