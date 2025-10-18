//! Comptime 反射工具
//!
//! 提供编译时反射功能，从 Zig struct 自动生成 SQL DDL

const std = @import("std");
const Allocator = std.mem.Allocator;
const Dialect = @import("../dialect/dialect.zig").Dialect;
const types = @import("types.zig");
const SQLType = types.SQLType;
const table_mod = @import("table.zig");
const Column = table_mod.Column;
const ColumnType = table_mod.ColumnType;

/// 从模型类型获取表名
///
/// 优先级：
/// 1. 检查 T.table_name 常量
/// 2. 使用类型名称（转小写）
pub fn getTableName(comptime T: type) []const u8 {
    // 检查是否有 table_name 常量
    if (@hasDecl(T, "table_name")) {
        return @field(T, "table_name");
    }

    // 使用类型名称（需要在运行时转小写）
    return @typeName(T);
}

/// 生成 CREATE TABLE SQL 语句
///
/// 从 struct 字段自动推断列定义：
/// - 字段名 -> 列名
/// - Zig 类型 -> SQL 类型
/// - ?T -> NULLABLE
/// - id 字段 -> PRIMARY KEY
pub fn generateCreateTableSQL(
    comptime T: type,
    comptime dialect: Dialect,
    allocator: Allocator,
) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    const writer = buf.writer();

    const table_name = getTableName(T);
    try writer.print("CREATE TABLE {s} (\n", .{table_name});

    const fields = @typeInfo(T).@"struct".fields;
    comptime var first = true;

    inline for (fields) |field| {
        if (!first) {
            try writer.writeAll(",\n");
        }
        first = false;

        // 获取 SQL 类型
        const sql_type = types.zigToSQLType(field.type);
        const is_optional = types.isOptional(field.type);

        // 列名和类型
        try writer.print("  {s} {s}", .{
            field.name,
            sql_type.toSQL(dialect),
        });

        // 主键检测（简单规则：名为 "id" 的字段）
        if (comptime std.mem.eql(u8, field.name, "id")) {
            try writer.writeAll(" PRIMARY KEY");
        }

        // NOT NULL 约束
        if (!is_optional) {
            try writer.writeAll(" NOT NULL");
        }
    }

    try writer.writeAll("\n)");
    return buf.toOwnedSlice();
}

/// 从 struct 字段生成 Column 列表
pub fn generateColumns(comptime T: type, allocator: Allocator) ![]Column {
    const fields = @typeInfo(T).@"struct".fields;
    var columns = try allocator.alloc(Column, fields.len);
    errdefer allocator.free(columns);

    inline for (fields, 0..) |field, i| {
        const sql_type = types.zigToSQLType(field.type);
        const is_optional = types.isOptional(field.type);
        const is_primary = comptime std.mem.eql(u8, field.name, "id");

        // 映射 SQLType 到 ColumnType
        const col_type: ColumnType = switch (sql_type) {
            .smallint => .smallint,
            .integer => .int,
            .bigint => .bigint,
            .real => .float,
            .double => .double,
            .boolean => .boolean,
            .text => .text,
            .varchar => .varchar,
            .char => .varchar, // char 映射到 varchar
            .timestamp => .timestamp,
            .timestamptz => .timestamp, // timestamptz 映射到 timestamp
            .date => .date,
            .time => .time,
            .json => .json,
            .jsonb => .jsonb,
            .blob => .bytea,
            .bytea => .bytea,
            .uuid => .uuid,
            .serial => .int, // serial 映射到 int (自增在其他地方处理)
            .bigserial => .bigint, // bigserial 映射到 bigint
        };

        columns[i] = .{
            .name = field.name,
            .column_type = col_type,
            .nullable = is_optional,
            .primary_key = is_primary,
            .unique = false,
            .default_value = null,
            .check_expr = null,
            .foreign_key = null,
        };
    }

    return columns;
}

/// 检测结构体是否有指定字段
pub fn hasField(comptime T: type, comptime field_name: []const u8) bool {
    const fields = @typeInfo(T).@"struct".fields;
    inline for (fields) |field| {
        if (comptime std.mem.eql(u8, field.name, field_name)) {
            return true;
        }
    }
    return false;
}

/// 获取字段类型
pub fn getFieldType(comptime T: type, comptime field_name: []const u8) type {
    const fields = @typeInfo(T).@"struct".fields;
    inline for (fields) |field| {
        if (comptime std.mem.eql(u8, field.name, field_name)) {
            return field.type;
        }
    }
    @compileError("Field '" ++ field_name ++ "' not found in type " ++ @typeName(T));
}

test "getTableName" {
    const User = struct {
        id: i64,
        name: []const u8,

        pub const table_name = "users";
    };

    const Post = struct {
        id: i64,
        title: []const u8,
    };

    try std.testing.expectEqualStrings("users", getTableName(User));
    // Post 没有 table_name，会使用类型名
    const post_table = getTableName(Post);
    try std.testing.expect(post_table.len > 0);
}

test "generateCreateTableSQL" {
    const User = struct {
        id: i64,
        name: []const u8,
        email: ?[]const u8,
        age: i32,
        is_active: bool,

        pub const table_name = "users";
    };

    const allocator = std.testing.allocator;
    const sql = try generateCreateTableSQL(User, .postgresql, allocator);
    defer allocator.free(sql);

    // 验证包含关键部分
    try std.testing.expect(std.mem.indexOf(u8, sql, "CREATE TABLE users") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "id BIGINT PRIMARY KEY NOT NULL") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "name TEXT NOT NULL") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "email TEXT") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "age INTEGER NOT NULL") != null);
}

test "generateColumns" {
    const User = struct {
        id: i64,
        name: []const u8,
        email: ?[]const u8,
    };

    const allocator = std.testing.allocator;
    const columns = try generateColumns(User, allocator);
    defer allocator.free(columns);

    try std.testing.expectEqual(@as(usize, 3), columns.len);

    // id 列
    try std.testing.expectEqualStrings("id", columns[0].name);
    try std.testing.expectEqual(ColumnType.bigserial, columns[0].column_type);
    try std.testing.expect(columns[0].primary_key);
    try std.testing.expect(!columns[0].nullable);

    // name 列
    try std.testing.expectEqualStrings("name", columns[1].name);
    try std.testing.expectEqual(ColumnType.text, columns[1].column_type);
    try std.testing.expect(!columns[1].nullable);

    // email 列（可选）
    try std.testing.expectEqualStrings("email", columns[2].name);
    try std.testing.expectEqual(ColumnType.text, columns[2].column_type);
    try std.testing.expect(columns[2].nullable);
}

test "hasField" {
    const User = struct {
        id: i64,
        name: []const u8,
    };

    try std.testing.expect(hasField(User, "id"));
    try std.testing.expect(hasField(User, "name"));
    try std.testing.expect(!hasField(User, "email"));
}
