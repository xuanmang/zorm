//! 结果扫描器
//!
//! 提供流式处理查询结果集的高级接口。
//! 集成 field_mapper 实现自动类型映射,支持大结果集的内存高效处理。
//!
//! # 核心功能
//! - 流式迭代查询结果
//! - 自动类型映射 (通过 field_mapper.scanRow)
//! - 支持字符串复制选项
//! - 批量扫描和单行扫描
//!
//! # 设计原则
//! - 使用泛型实现编译时类型安全
//! - 零运行时反射开销
//! - 流式处理,内存占用可控
//! - 与 field_mapper 无缝集成

const std = @import("std");
const Allocator = std.mem.Allocator;
const field_mapper = @import("field_mapper.zig");
const Row = field_mapper.Row;

/// 扫描选项
///
/// 控制结果扫描行为的配置选项。
///
/// # 示例
/// ```zig
/// const options = ScanOptions{
///     .copy_strings = true, // 复制字符串,生命周期独立于 Row
/// };
/// ```
pub const ScanOptions = struct {
    /// 是否复制字符串
    ///
    /// - true: 复制所有字符串到 allocator (安全,但有内存开销)
    /// - false: 借用 Row 的内存 (高效,但生命周期受限)
    ///
    /// 注意:
    /// - 如果字符串需要在 Row 失效后继续使用,必须设置为 true
    /// - 对于大结果集,设置为 false 可以显著减少内存分配
    copy_strings: bool = false,
};

/// 扫描所有行到 ArrayList
///
/// 使用 field_mapper.scanRow 将行数据映射到结构体并添加到列表中。
///
/// 参数:
/// - T: 目标结构体类型
/// - rows: 实现 next() 方法的行迭代器
/// - allocator: 内存分配器
/// - dest: 目标 ArrayList
///
/// 错误:
/// - error.QueryFailed: 读取失败
/// - error.TypeMismatch: 类型不匹配
/// - error.OutOfMemory: 内存不足
///
/// 使用示例:
/// ```zig
/// var users = std.ArrayList(User){...};
/// defer users.deinit();
///
/// try scanAll(User, &rows, allocator, &users);
/// ```
pub fn scanAll(comptime T: type, rows: anytype, allocator: Allocator, dest: anytype) !void {
    while (try rows.next()) |row_const| {
        var row = row_const;
        const item = try field_mapper.scanRow(T, &row, allocator);
        try dest.append(allocator, item);
    }
}

/// 扫描单行
///
/// 读取迭代器中的第一行,确保只有一行,然后返回映射后的结构体。
///
/// 参数:
/// - T: 目标结构体类型
/// - rows: 实现 next() 方法的行迭代器
/// - allocator: 内存分配器
///
/// 返回:
/// - T: 映射后的结构体
///
/// 错误:
/// - error.NoRows: 结果集为空
/// - error.TooManyRows: 结果集有多于1行
/// - error.QueryFailed: 读取失败
/// - error.TypeMismatch: 类型不匹配
///
/// 使用示例:
/// ```zig
/// const user = try scanOne(User, &rows, allocator);
/// ```
pub fn scanOne(comptime T: type, rows: anytype, allocator: Allocator) !T {
    // 获取第一行
    const first_row = try rows.next();
    if (first_row == null) {
        return error.NoRows;
    }

    var first = first_row.?;
    const result = try field_mapper.scanRow(T, &first, allocator);

    // 检查是否还有更多行
    const second = try rows.next();
    if (second != null) {
        return error.TooManyRows;
    }

    return result;
}

// =============================================================================
// 单元测试
// =============================================================================

const testing = std.testing;

/// 测试用的模拟 Row 实现
const MockRow = struct {
    values: []const ?[]const u8,

    fn isNull(ptr: *anyopaque, index: usize) bool {
        const self: *const MockRow = @alignCast(@ptrCast(ptr));
        return self.values[index] == null;
    }

    fn getInt(ptr: *anyopaque, index: usize) !i64 {
        const self: *const MockRow = @alignCast(@ptrCast(ptr));
        const val_str = self.values[index] orelse return error.NullValue;
        return try std.fmt.parseInt(i64, val_str, 10);
    }

    fn getFloat(ptr: *anyopaque, index: usize) !f64 {
        const self: *const MockRow = @alignCast(@ptrCast(ptr));
        const val_str = self.values[index] orelse return error.NullValue;
        return try std.fmt.parseFloat(f64, val_str);
    }

    fn getBool(ptr: *anyopaque, index: usize) !bool {
        const self: *const MockRow = @alignCast(@ptrCast(ptr));
        const val_str = self.values[index] orelse return error.NullValue;
        return std.mem.eql(u8, val_str, "true") or std.mem.eql(u8, val_str, "1");
    }

    fn getString(ptr: *anyopaque, index: usize) ![]const u8 {
        const self: *const MockRow = @alignCast(@ptrCast(ptr));
        return self.values[index] orelse return error.NullValue;
    }

    fn getBytes(ptr: *anyopaque, index: usize) ![]const u8 {
        return getString(ptr, index);
    }

    const vtable_impl: Row.RowVTable = .{
        .isNull = isNull,
        .getInt = getInt,
        .getFloat = getFloat,
        .getBool = getBool,
        .getString = getString,
        .getBytes = getBytes,
    };
};

/// 测试用的模拟 Rows 迭代器
const MockRows = struct {
    rows_data: []const []const ?[]const u8,
    current_index: usize,

    fn init(data: []const []const ?[]const u8) MockRows {
        return .{
            .rows_data = data,
            .current_index = 0,
        };
    }

    fn next(self: *MockRows) !?Row {
        if (self.current_index >= self.rows_data.len) {
            return null;
        }

        const row_values = self.rows_data[self.current_index];
        self.current_index += 1;

        // 创建临时 MockRow (注意: 这里 Row 的生命周期仅在本次 next() 调用有效)
        var mock_row = MockRow{ .values = row_values };

        return Row{
            .driver_row = @ptrCast(&mock_row),
            .vtable = &MockRow.vtable_impl,
        };
    }
};

// 测试用的模型
const TestUser = struct {
    id: i64,
    name: []const u8,
    age: u32,
    active: bool,
};

test "scanAll: 批量扫描多行" {
    // 准备测试数据
    const row1 = [_]?[]const u8{ "1", "Alice", "25", "true" };
    const row2 = [_]?[]const u8{ "2", "Bob", "30", "false" };
    const row3 = [_]?[]const u8{ "3", "Charlie", "35", "true" };
    const rows_data = [_][]const ?[]const u8{ &row1, &row2, &row3 };

    // 创建 MockRows 迭代器
    var mock_rows = MockRows.init(&rows_data);

    // 批量扫描
    var users: std.ArrayList(TestUser) = .{};
    defer users.deinit(testing.allocator);

    try scanAll(TestUser, &mock_rows, testing.allocator, &users);

    // 验证结果
    try testing.expectEqual(@as(usize, 3), users.items.len);

    try testing.expectEqual(@as(i64, 1), users.items[0].id);
    try testing.expectEqualStrings("Alice", users.items[0].name);
    try testing.expectEqual(@as(u32, 25), users.items[0].age);
    try testing.expect(users.items[0].active);

    try testing.expectEqual(@as(i64, 2), users.items[1].id);
    try testing.expectEqualStrings("Bob", users.items[1].name);
    try testing.expectEqual(@as(u32, 30), users.items[1].age);
    try testing.expect(!users.items[1].active);

    try testing.expectEqual(@as(i64, 3), users.items[2].id);
    try testing.expectEqualStrings("Charlie", users.items[2].name);
    try testing.expectEqual(@as(u32, 35), users.items[2].age);
    try testing.expect(users.items[2].active);
}

test "scanOne: 单行扫描成功" {
    // 准备测试数据 (只有一行)
    const row1 = [_]?[]const u8{ "1", "Alice", "25", "true" };
    const rows_data = [_][]const ?[]const u8{&row1};

    var mock_rows = MockRows.init(&rows_data);

    // 扫描单行
    const user = try scanOne(TestUser, &mock_rows, testing.allocator);

    try testing.expectEqual(@as(i64, 1), user.id);
    try testing.expectEqualStrings("Alice", user.name);
    try testing.expectEqual(@as(u32, 25), user.age);
    try testing.expect(user.active);
}

test "scanOne: 无行错误" {
    // 准备测试数据 (空结果集)
    const rows_data = [_][]const ?[]const u8{};

    var mock_rows = MockRows.init(&rows_data);

    // 应该返回 NoRows 错误
    try testing.expectError(error.NoRows, scanOne(TestUser, &mock_rows, testing.allocator));
}

test "scanOne: 多行错误" {
    // 准备测试数据 (多于一行)
    const row1 = [_]?[]const u8{ "1", "Alice", "25", "true" };
    const row2 = [_]?[]const u8{ "2", "Bob", "30", "false" };
    const rows_data = [_][]const ?[]const u8{ &row1, &row2 };

    var mock_rows = MockRows.init(&rows_data);

    // 应该返回 TooManyRows 错误
    try testing.expectError(error.TooManyRows, scanOne(TestUser, &mock_rows, testing.allocator));
}

test "scanAll: 空结果集" {
    // 准备测试数据 (空结果集)
    const rows_data = [_][]const ?[]const u8{};

    var mock_rows = MockRows.init(&rows_data);

    var users: std.ArrayList(TestUser) = .{};
    defer users.deinit(testing.allocator);

    try scanAll(TestUser, &mock_rows, testing.allocator, &users);

    // 空结果集应该返回空列表
    try testing.expectEqual(@as(usize, 0), users.items.len);
}
