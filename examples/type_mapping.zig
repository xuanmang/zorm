//! ZORM Type Mapping Example
//!
//! 演示类型系统的核心功能:
//! - 编译时类型反射
//! - Zig 到 SQL 类型映射
//! - 自定义表名
//! - 可选类型处理

const std = @import("std");
const zorm = @import("zorm");

// 示例1: 基本类型映射
const User = struct {
    id: i64, // -> BIGINT
    username: []const u8, // -> TEXT
    email: []const u8, // -> TEXT
    age: u32, // -> INTEGER
    balance: f64, // -> DOUBLE PRECISION
    is_active: bool, // -> BOOLEAN

    pub const table_name = "users";
};

// 示例2: 带可选字段的类型
const UserProfile = struct {
    id: i64,
    user_id: i64,
    bio: ?[]const u8, // 可选字段,允许 NULL
    avatar_url: ?[]const u8,
    age: ?u32,
    last_login: ?i64,

    // 没有显式 table_name,将使用 "user_profile"
};

// 示例3: 不同数值类型
const Statistics = struct {
    id: i64,
    count: i32,
    total: u64,
    average: f32,
    percentage: f64,
    flags: u8,

    pub const table_name = "app_statistics";
};

pub fn main() !void {
    std.debug.print("=== ZORM Type Mapping Demo ===\n\n", .{});

    // 示例1: User 类型信息
    comptime {
        std.debug.print("--- User 类型 ---\n", .{});

        const table_name = zorm.types.getTableName(User);
        std.debug.print("表名: {s}\n", .{table_name});

        const fields = zorm.types.getFields(User);
        std.debug.print("字段数量: {d}\n", .{fields.len});

        std.debug.print("\n字段映射:\n", .{});
        inline for (fields) |field| {
            const sql_type = zorm.types.zigToSQLType(field.type);
            const is_optional = zorm.types.isOptional(field.type);
            const null_clause = if (is_optional) "" else " NOT NULL";

            std.debug.print("  {s}: {s}{s}\n", .{ field.name, sql_type, null_clause });
        }

        std.debug.print("\n", .{});
    }

    // 示例2: UserProfile 类型信息
    comptime {
        std.debug.print("--- UserProfile 类型 ---\n", .{});

        const table_name = zorm.types.getTableName(UserProfile);
        std.debug.print("表名: {s} (自动生成)\n", .{table_name});

        const fields = zorm.types.getFields(UserProfile);
        std.debug.print("字段数量: {d}\n", .{fields.len});

        std.debug.print("\n字段映射:\n", .{});
        inline for (fields) |field| {
            const sql_type = zorm.types.zigToSQLType(field.type);
            const is_optional = zorm.types.isOptional(field.type);
            const null_clause = if (is_optional) "" else " NOT NULL";

            std.debug.print("  {s}: {s}{s}\n", .{ field.name, sql_type, null_clause });
        }

        std.debug.print("\n", .{});
    }

    // 示例3: Statistics 类型信息
    comptime {
        std.debug.print("--- Statistics 类型 ---\n", .{});

        const table_name = zorm.types.getTableName(Statistics);
        std.debug.print("表名: {s}\n", .{table_name});

        const field_names = zorm.types.getFieldNames(Statistics);
        std.debug.print("字段列表: {s}\n", .{field_names});

        std.debug.print("\n类型映射详情:\n", .{});
        std.debug.print("  i64 -> {s}\n", .{zorm.types.zigToSQLType(i64)});
        std.debug.print("  i32 -> {s}\n", .{zorm.types.zigToSQLType(i32)});
        std.debug.print("  u64 -> {s}\n", .{zorm.types.zigToSQLType(u64)});
        std.debug.print("  f32 -> {s}\n", .{zorm.types.zigToSQLType(f32)});
        std.debug.print("  f64 -> {s}\n", .{zorm.types.zigToSQLType(f64)});
        std.debug.print("  u8  -> {s}\n", .{zorm.types.zigToSQLType(u8)});

        std.debug.print("\n", .{});
    }

    // 示例4: 可选类型处理
    comptime {
        std.debug.print("--- 可选类型处理 ---\n", .{});

        std.debug.print("i64 是可选类型? {}\n", .{zorm.types.isOptional(i64)});
        std.debug.print("?i64 是可选类型? {}\n", .{zorm.types.isOptional(?i64)});
        std.debug.print("[]const u8 是可选类型? {}\n", .{zorm.types.isOptional([]const u8)});
        std.debug.print("?[]const u8 是可选类型? {}\n", .{zorm.types.isOptional(?[]const u8)});

        std.debug.print("\n可选类型 SQL 映射:\n", .{});
        std.debug.print("  ?i64 -> {s}\n", .{zorm.types.zigToSQLType(?i64)});
        std.debug.print("  ?[]const u8 -> {s}\n", .{zorm.types.zigToSQLType(?[]const u8)});
        std.debug.print("  ?bool -> {s}\n", .{zorm.types.zigToSQLType(?bool)});

        std.debug.print("\n", .{});
    }

    // 示例5: 类型验证
    comptime {
        std.debug.print("--- 编译时类型验证 ---\n", .{});

        // 验证 User 类型有效
        zorm.types.validateType(User);
        std.debug.print("✅ User 类型验证通过\n", .{});

        // 验证 UserProfile 类型有效
        zorm.types.validateType(UserProfile);
        std.debug.print("✅ UserProfile 类型验证通过\n", .{});

        // 验证 Statistics 类型有效
        zorm.types.validateType(Statistics);
        std.debug.print("✅ Statistics 类型验证通过\n", .{});

        std.debug.print("\n", .{});
    }

    // 示例6: 生成 CREATE TABLE 语句示例
    comptime {
        std.debug.print("--- CREATE TABLE 语句示例 ---\n", .{});

        const table_name = zorm.types.getTableName(User);
        const fields = zorm.types.getFields(User);

        std.debug.print("CREATE TABLE {s} (\n", .{table_name});

        inline for (fields, 0..) |field, i| {
            const sql_type = zorm.types.zigToSQLType(field.type);
            const is_optional = zorm.types.isOptional(field.type);
            const null_clause = if (is_optional) "" else " NOT NULL";
            const comma = if (i < fields.len - 1) "," else "";

            std.debug.print("  {s} {s}{s}{s}\n", .{ field.name, sql_type, null_clause, comma });
        }

        std.debug.print(");\n\n", .{});
    }

    std.debug.print("✅ 所有类型映射操作在编译时完成,零运行时开销!\n", .{});
}
