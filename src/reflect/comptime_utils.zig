//! Comptime 反射工具库
//!
//! 提供编译时类型反射和模型元数据推断功能。
//! 用于自动化 ORM 操作，减少样板代码。
//!
//! # 核心功能
//! - 表名推断 (getTableName)
//! - 类型映射 (inferSQLType)
//! - 字段特征检测 (isPrimaryKeyField, isTimestampField, etc.)
//! - 外键引用推断 (inferForeignKeyTable)
//!
//! # 设计原则
//! - 零运行时开销（纯 comptime 计算）
//! - 遵循约定优于配置 (Convention over Configuration)
//! - 支持自定义覆盖（通过类型声明）

const std = @import("std");
const ColumnType = @import("../schema/schema.zig").ColumnType;

/// 获取模型的表名
///
/// 优先级：
/// 1. 如果类型有 `table_name` 公共声明，使用该值
/// 2. 否则使用类型名称
///
/// 示例：
/// ```zig
/// const User = struct {
///     pub const table_name = "users";
///     id: i64,
///     name: []const u8,
/// };
///
/// comptime {
///     assert(std.mem.eql(u8, getTableName(User), "users"));
/// }
/// ```
pub fn getTableName(comptime T: type) []const u8 {
    if (@hasDecl(T, "table_name")) {
        return T.table_name;
    }
    return @typeName(T);
}

/// 从 Zig 类型推断 SQL 列类型
///
/// 映射规则：
/// - i8, i16 -> SMALLINT
/// - i32 -> INTEGER
/// - i64, isize -> BIGINT
/// - f32 -> REAL
/// - f64 -> DOUBLE PRECISION
/// - bool -> BOOLEAN
/// - []const u8, []u8 -> TEXT
/// - ?T -> 递归推断 T 的类型
///
/// 示例：
/// ```zig
/// comptime {
///     assert(inferSQLType(i64) == .bigint);
///     assert(inferSQLType(?[]const u8) == .text);
/// }
/// ```
pub fn inferSQLType(comptime T: type) ColumnType {
    return switch (@typeInfo(T)) {
        .int => |int_info| blk: {
            if (int_info.bits <= 16) break :blk .smallint;
            if (int_info.bits <= 32) break :blk .int;
            break :blk .bigint;
        },
        .float => |float_info| blk: {
            if (float_info.bits <= 32) break :blk .float;
            break :blk .double;
        },
        .bool => .boolean,
        .pointer => |ptr| blk: {
            // []const u8 或 []u8 -> TEXT
            if (ptr.size == .slice and ptr.child == u8) {
                break :blk .text;
            }
            break :blk .text;
        },
        .optional => |opt| inferSQLType(opt.child),
        else => .text,
    };
}

/// 检查类型是否为 Optional
///
/// 示例：
/// ```zig
/// comptime {
///     assert(isOptional(?i64) == true);
///     assert(isOptional(i64) == false);
/// }
/// ```
pub inline fn isOptional(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

/// 检查字段名是否为主键字段
///
/// 约定：字段名为 "id" 时视为主键
///
/// 示例：
/// ```zig
/// comptime {
///     assert(isPrimaryKeyField("id") == true);
///     assert(isPrimaryKeyField("user_id") == false);
/// }
/// ```
pub inline fn isPrimaryKeyField(field_name: []const u8) bool {
    return std.mem.eql(u8, field_name, "id");
}

/// 检查字段名是否为时间戳字段
///
/// 约定：以 "_at" 结尾的字段视为时间戳
///
/// 示例：
/// ```zig
/// comptime {
///     assert(isTimestampField("created_at") == true);
///     assert(isTimestampField("updated_at") == true);
///     assert(isTimestampField("name") == false);
/// }
/// ```
pub inline fn isTimestampField(field_name: []const u8) bool {
    return std.mem.endsWith(u8, field_name, "_at");
}

/// 检查字段名是否为外键字段
///
/// 约定：以 "_id" 结尾但不等于 "id" 的字段视为外键
///
/// 示例：
/// ```zig
/// comptime {
///     assert(isForeignKeyField("user_id") == true);
///     assert(isForeignKeyField("post_id") == true);
///     assert(isForeignKeyField("id") == false);
///     assert(isForeignKeyField("name") == false);
/// }
/// ```
pub inline fn isForeignKeyField(field_name: []const u8) bool {
    return std.mem.endsWith(u8, field_name, "_id") and
        !std.mem.eql(u8, field_name, "id");
}

/// 从外键字段名推断引用的表名
///
/// 约定：
/// - user_id -> users
/// - post_id -> posts
/// - tag_id -> tags
/// - category_id -> categories
/// - 未知模式返回空字符串
///
/// 算法：移除 "_id" 后缀，添加 "s" 复数后缀（简化规则）
///
/// 示例：
/// ```zig
/// comptime {
///     assert(std.mem.eql(u8, inferForeignKeyTable("user_id"), "users"));
///     assert(std.mem.eql(u8, inferForeignKeyTable("post_id"), "posts"));
/// }
/// ```
pub fn inferForeignKeyTable(field_name: []const u8) []const u8 {
    // 常见映射表（手动维护以支持特殊复数形式）
    const mappings = .{
        .{ "user_id", "users" },
        .{ "post_id", "posts" },
        .{ "tag_id", "tags" },
        .{ "comment_id", "comments" },
        .{ "category_id", "categories" },
    };

    // 检查预定义映射
    inline for (mappings) |mapping| {
        if (std.mem.eql(u8, field_name, mapping[0])) {
            return mapping[1];
        }
    }

    // 未找到映射，返回空字符串
    return "";
}

/// 获取字段的默认值表达式（SQL 字符串）
///
/// 约定：
/// - created_at/updated_at -> EXTRACT(EPOCH FROM NOW())::BIGINT
/// - status -> 'draft'
/// - 其他字段 -> null
///
/// 示例：
/// ```zig
/// comptime {
///     const default_val = getDefaultValue("created_at");
///     assert(default_val != null);
/// }
/// ```
pub fn getDefaultValue(field_name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, field_name, "created_at") or
        std.mem.eql(u8, field_name, "updated_at"))
    {
        return "EXTRACT(EPOCH FROM NOW())::BIGINT";
    }

    if (std.mem.eql(u8, field_name, "status")) {
        return "'draft'";
    }

    return null;
}

/// 获取字段的检查约束表达式（SQL 字符串）
///
/// 约定：
/// - status -> status IN ('draft', 'published', 'archived')
/// - 其他字段 -> null
///
/// 示例：
/// ```zig
/// comptime {
///     const check = getCheckConstraint("status");
///     assert(check != null);
/// }
/// ```
pub fn getCheckConstraint(field_name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, field_name, "status")) {
        return "status IN ('draft', 'published', 'archived')";
    }

    return null;
}

/// 检查字段是否应该是唯一的
///
/// 约定：
/// - email 字段 -> UNIQUE
/// - 其他字段 -> false
///
/// 示例：
/// ```zig
/// comptime {
///     assert(isUniqueField("email") == true);
///     assert(isUniqueField("name") == false);
/// }
/// ```
pub inline fn isUniqueField(field_name: []const u8) bool {
    return std.mem.eql(u8, field_name, "email");
}

/// 检查字段是否应该自动递增
///
/// 约定：只有主键字段（id）才自动递增
///
/// 示例：
/// ```zig
/// comptime {
///     assert(isAutoIncrementField("id") == true);
///     assert(isAutoIncrementField("count") == false);
/// }
/// ```
pub inline fn isAutoIncrementField(field_name: []const u8) bool {
    return isPrimaryKeyField(field_name);
}

// =============================================================================
// 单元测试
// =============================================================================

const testing = std.testing;

test "getTableName: 使用 table_name 声明" {
    const User = struct {
        pub const table_name = "users";
        id: i64,
        name: []const u8,
    };

    try testing.expectEqualStrings("users", getTableName(User));
}

test "getTableName: 默认使用类型名" {
    const MyModel = struct {
        id: i64,
    };

    const name = getTableName(MyModel);
    try testing.expect(std.mem.indexOf(u8, name, "MyModel") != null);
}

test "inferSQLType: 整数类型" {
    try testing.expectEqual(ColumnType.smallint, inferSQLType(i8));
    try testing.expectEqual(ColumnType.smallint, inferSQLType(i16));
    try testing.expectEqual(ColumnType.int, inferSQLType(i32));
    try testing.expectEqual(ColumnType.bigint, inferSQLType(i64));
}

test "inferSQLType: 浮点类型" {
    try testing.expectEqual(ColumnType.float, inferSQLType(f32));
    try testing.expectEqual(ColumnType.double, inferSQLType(f64));
}

test "inferSQLType: 布尔类型" {
    try testing.expectEqual(ColumnType.boolean, inferSQLType(bool));
}

test "inferSQLType: 字符串类型" {
    try testing.expectEqual(ColumnType.text, inferSQLType([]const u8));
    try testing.expectEqual(ColumnType.text, inferSQLType([]u8));
}

test "inferSQLType: Optional 类型" {
    try testing.expectEqual(ColumnType.bigint, inferSQLType(?i64));
    try testing.expectEqual(ColumnType.text, inferSQLType(?[]const u8));
}

test "isOptional: 检测 Optional 类型" {
    try testing.expect(isOptional(?i64));
    try testing.expect(isOptional(?[]const u8));
    try testing.expect(!isOptional(i64));
    try testing.expect(!isOptional([]const u8));
}

test "isPrimaryKeyField: 检测主键字段" {
    try testing.expect(isPrimaryKeyField("id"));
    try testing.expect(!isPrimaryKeyField("user_id"));
    try testing.expect(!isPrimaryKeyField("name"));
}

test "isTimestampField: 检测时间戳字段" {
    try testing.expect(isTimestampField("created_at"));
    try testing.expect(isTimestampField("updated_at"));
    try testing.expect(isTimestampField("published_at"));
    try testing.expect(!isTimestampField("name"));
    try testing.expect(!isTimestampField("user_id"));
}

test "isForeignKeyField: 检测外键字段" {
    try testing.expect(isForeignKeyField("user_id"));
    try testing.expect(isForeignKeyField("post_id"));
    try testing.expect(isForeignKeyField("tag_id"));
    try testing.expect(!isForeignKeyField("id"));
    try testing.expect(!isForeignKeyField("name"));
}

test "inferForeignKeyTable: 推断引用表名" {
    try testing.expectEqualStrings("users", inferForeignKeyTable("user_id"));
    try testing.expectEqualStrings("posts", inferForeignKeyTable("post_id"));
    try testing.expectEqualStrings("tags", inferForeignKeyTable("tag_id"));
    try testing.expectEqualStrings("comments", inferForeignKeyTable("comment_id"));
    try testing.expectEqualStrings("categories", inferForeignKeyTable("category_id"));
    try testing.expectEqualStrings("", inferForeignKeyTable("unknown_id"));
}

test "getDefaultValue: 时间戳字段" {
    const created_default = getDefaultValue("created_at");
    try testing.expect(created_default != null);
    try testing.expect(std.mem.indexOf(u8, created_default.?, "NOW()") != null);

    const updated_default = getDefaultValue("updated_at");
    try testing.expect(updated_default != null);
}

test "getDefaultValue: 状态字段" {
    const status_default = getDefaultValue("status");
    try testing.expect(status_default != null);
    try testing.expectEqualStrings("'draft'", status_default.?);
}

test "getDefaultValue: 其他字段" {
    try testing.expect(getDefaultValue("name") == null);
    try testing.expect(getDefaultValue("email") == null);
}

test "getCheckConstraint: 状态字段" {
    const status_check = getCheckConstraint("status");
    try testing.expect(status_check != null);
    try testing.expect(std.mem.indexOf(u8, status_check.?, "IN") != null);
}

test "getCheckConstraint: 其他字段" {
    try testing.expect(getCheckConstraint("name") == null);
    try testing.expect(getCheckConstraint("email") == null);
}

test "isUniqueField: email 字段" {
    try testing.expect(isUniqueField("email"));
    try testing.expect(!isUniqueField("name"));
    try testing.expect(!isUniqueField("id"));
}

test "isAutoIncrementField: id 字段" {
    try testing.expect(isAutoIncrementField("id"));
    try testing.expect(!isAutoIncrementField("user_id"));
    try testing.expect(!isAutoIncrementField("count"));
}

test "完整模型推断测试" {
    const User = struct {
        pub const table_name = "users";
        id: i64,
        name: []const u8,
        email: []const u8,
        created_at: i64,
        updated_at: i64,
    };

    // 表名
    try testing.expectEqualStrings("users", getTableName(User));

    // 字段类型推断
    const fields = @typeInfo(User).@"struct".fields;
    inline for (fields) |field| {
        const sql_type = inferSQLType(field.type);
        if (std.mem.eql(u8, field.name, "id")) {
            try testing.expectEqual(ColumnType.bigint, sql_type);
            try testing.expect(isPrimaryKeyField(field.name));
            try testing.expect(isAutoIncrementField(field.name));
        } else if (std.mem.eql(u8, field.name, "name") or std.mem.eql(u8, field.name, "email")) {
            try testing.expectEqual(ColumnType.text, sql_type);
            if (std.mem.eql(u8, field.name, "email")) {
                try testing.expect(isUniqueField(field.name));
            }
        } else if (std.mem.endsWith(u8, field.name, "_at")) {
            try testing.expectEqual(ColumnType.bigint, sql_type);
            try testing.expect(isTimestampField(field.name));
            try testing.expect(getDefaultValue(field.name) != null);
        }
    }
}

test "外键关系推断测试" {
    const Post = struct {
        pub const table_name = "posts";
        id: i64,
        user_id: i64,
        title: []const u8,
        content: []const u8,
        created_at: i64,
    };

    const fields = @typeInfo(Post).@"struct".fields;
    inline for (fields) |field| {
        if (std.mem.eql(u8, field.name, "user_id")) {
            try testing.expect(isForeignKeyField(field.name));
            try testing.expectEqualStrings("users", inferForeignKeyTable(field.name));
        }
    }
}
