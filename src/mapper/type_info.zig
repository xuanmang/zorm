//! 编译时类型反射工具
//!
//! 此模块提供零运行时开销的类型信息提取功能。
//! 所有函数都是 comptime 函数，结果在编译时计算。
//!
//! # 核心功能
//! - getTableName: 提取结构体对应的表名
//! - getFieldNames: 提取结构体所有字段名
//! - getFieldTypes: 提取结构体所有字段类型
//! - getFieldCount: 获取结构体字段数量
//!
//! # 设计原则
//! - 所有操作在编译时完成，零运行时开销
//! - 使用 @typeInfo 内省结构体元数据
//! - 支持自定义 table_name 声明
//! - 编译时错误检查，确保类型安全

const std = @import("std");

/// 编译时提取表名
///
/// 优先使用结构体的 `table_name` 常量声明。
/// 如果没有声明，则使用类型名称。
///
/// # 示例
/// ```zig
/// const User = struct {
///     id: i64,
///     name: []const u8,
///     pub const table_name = "users";
/// };
///
/// comptime {
///     const name = getTableName(User); // "users"
/// }
/// ```
pub fn getTableName(comptime T: type) []const u8 {
    // 检查是否为结构体类型
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("getTableName requires a struct type, got " ++ @typeName(T));
    }

    // 优先使用自定义 table_name
    if (@hasDecl(T, "table_name")) {
        return @field(T, "table_name");
    }

    // 否则使用类型名
    return @typeName(T);
}

/// 编译时提取字段名列表
///
/// 返回包含所有字段名的数组引用。
/// 数组在编译时分配，无运行时开销。
///
/// # 示例
/// ```zig
/// const User = struct {
///     id: i64,
///     name: []const u8,
///     email: ?[]const u8,
/// };
///
/// comptime {
///     const names = getFieldNames(User); // ["id", "name", "email"]
/// }
/// ```
pub fn getFieldNames(comptime T: type) []const []const u8 {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("getFieldNames requires a struct type, got " ++ @typeName(T));
    }

    const fields = type_info.@"struct".fields;
    comptime var names: [fields.len][]const u8 = undefined;

    inline for (fields, 0..) |field, i| {
        names[i] = field.name;
    }

    const final_names = names;
    return &final_names;
}

/// 编译时提取字段类型列表
///
/// 返回包含所有字段类型的数组引用。
/// 数组在编译时分配，无运行时开销。
///
/// # 示例
/// ```zig
/// const User = struct {
///     id: i64,
///     name: []const u8,
///     active: bool,
/// };
///
/// comptime {
///     const types = getFieldTypes(User); // [i64, []const u8, bool]
/// }
/// ```
pub fn getFieldTypes(comptime T: type) []const type {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("getFieldTypes requires a struct type, got " ++ @typeName(T));
    }

    const fields = type_info.@"struct".fields;
    comptime var types: [fields.len]type = undefined;

    inline for (fields, 0..) |field, i| {
        types[i] = field.type;
    }

    const final_types = types;
    return &final_types;
}

/// 编译时获取字段数量
///
/// 返回结构体字段的数量。
/// 完全在编译时计算，零运行时开销。
///
/// # 示例
/// ```zig
/// const User = struct {
///     id: i64,
///     name: []const u8,
///     email: ?[]const u8,
/// };
///
/// comptime {
///     const count = getFieldCount(User); // 3
/// }
/// ```
pub fn getFieldCount(comptime T: type) usize {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("getFieldCount requires a struct type, got " ++ @typeName(T));
    }

    return type_info.@"struct".fields.len;
}

// =============================================================================
// 单元测试
// =============================================================================

const testing = std.testing;

// 测试用的模型定义
const TestUser = struct {
    id: i64,
    name: []const u8,
    email: ?[]const u8,
    age: u32,
    active: bool,

    pub const table_name = "users";
};

const TestPost = struct {
    id: i64,
    title: []const u8,
    content: []const u8,
    published: bool,
    // 没有自定义 table_name
};

const TestSimple = struct {
    x: i32,
    y: i32,
};

test "getTableName: 使用自定义 table_name" {
    const name = comptime getTableName(TestUser);
    try testing.expectEqualStrings("users", name);
}

test "getTableName: 使用类型名" {
    const name = comptime getTableName(TestPost);
    // 类型名包含完整路径，只检查包含 "TestPost"
    try testing.expect(std.mem.indexOf(u8, name, "TestPost") != null);
}

test "getFieldNames: 提取所有字段名" {
    const names = comptime getFieldNames(TestUser);

    try testing.expectEqual(5, names.len);
    try testing.expectEqualStrings("id", names[0]);
    try testing.expectEqualStrings("name", names[1]);
    try testing.expectEqualStrings("email", names[2]);
    try testing.expectEqualStrings("age", names[3]);
    try testing.expectEqualStrings("active", names[4]);
}

test "getFieldNames: 简单结构体" {
    const names = comptime getFieldNames(TestSimple);

    try testing.expectEqual(2, names.len);
    try testing.expectEqualStrings("x", names[0]);
    try testing.expectEqualStrings("y", names[1]);
}

test "getFieldTypes: 提取所有字段类型" {
    const types = comptime getFieldTypes(TestUser);

    try testing.expectEqual(5, types.len);
    try testing.expectEqual(i64, types[0]);
    try testing.expectEqual([]const u8, types[1]);
    try testing.expectEqual(?[]const u8, types[2]);
    try testing.expectEqual(u32, types[3]);
    try testing.expectEqual(bool, types[4]);
}

test "getFieldTypes: 简单结构体" {
    const types = comptime getFieldTypes(TestSimple);

    try testing.expectEqual(2, types.len);
    try testing.expectEqual(i32, types[0]);
    try testing.expectEqual(i32, types[1]);
}

test "getFieldCount: 正确计数" {
    try testing.expectEqual(5, comptime getFieldCount(TestUser));
    try testing.expectEqual(4, comptime getFieldCount(TestPost));
    try testing.expectEqual(2, comptime getFieldCount(TestSimple));
}

test "getFieldCount: 空结构体" {
    const Empty = struct {};
    try testing.expectEqual(0, comptime getFieldCount(Empty));
}

test "编译时使用: 所有函数都是 comptime" {
    // 这个测试验证所有函数都可以在编译时调用
    comptime {
        const table_name = getTableName(TestUser);
        const field_names = getFieldNames(TestUser);
        const field_types = getFieldTypes(TestUser);
        const field_count = getFieldCount(TestUser);

        // 验证编译时计算的结果
        std.debug.assert(std.mem.eql(u8, table_name, "users"));
        std.debug.assert(field_names.len == 5);
        std.debug.assert(field_types.len == 5);
        std.debug.assert(field_count == 5);
    }
}

test "类型安全: inline for 与字段迭代" {
    // 验证可以在编译时迭代字段
    const field_names = comptime getFieldNames(TestUser);
    const field_types = comptime getFieldTypes(TestUser);

    var test_user: TestUser = undefined;

    // 使用 comptime 信息访问字段
    inline for (field_names, field_types, 0..) |name, field_type, i| {
        _ = i;
        _ = &test_user;

        // 验证类型匹配
        const actual_type = @TypeOf(@field(test_user, name));
        try testing.expectEqual(field_type, actual_type);
    }
}

test "性能: 零运行时开销验证" {
    // 编译时预计算
    const table_name = comptime getTableName(TestUser);
    const field_count = comptime getFieldCount(TestUser);

    // 这些都是编译时常量，不会有任何运行时查找
    try testing.expectEqualStrings("users", table_name);
    try testing.expectEqual(5, field_count);

    // 验证可以用于编译时数组大小
    const buffer: [field_count]u8 = undefined;
    try testing.expectEqual(5, buffer.len);
}
