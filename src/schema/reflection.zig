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
const schema_lib = @import("schema.zig");
const getFieldSchema = schema_lib.getFieldSchema;

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
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

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
    return buf.toOwnedSlice(allocator);
}

/// 从 struct 字段生成 Column 列表
pub fn generateColumns(comptime T: type, allocator: Allocator) ![]Column {
    const fields = @typeInfo(T).@"struct".fields;
    var columns = try allocator.alloc(Column, fields.len);
    errdefer allocator.free(columns);

    inline for (fields, 0..) |field, i| {
        // 读取 schema 配置
        const schema_cfg = comptime getFieldSchema(T, field.name);

        const is_optional = types.isOptional(field.type);

        // 判断是否为主键（优先使用 schema 配置）
        const is_primary = schema_cfg.primary_key or comptime std.mem.eql(u8, field.name, "id");

        // 判断是否自增 (默认: 整数主键字段自动启用自增)
        const is_auto_increment = schema_cfg.auto_increment or
            (is_primary and !is_optional and types.isIntegerType(field.type));

        // 获取 SQL 类型（考虑 auto_increment）
        var sql_type: types.SQLType = undefined;
        if (is_auto_increment) {
            // 自增字段使用 SERIAL/BIGSERIAL
            const field_type_info = @typeInfo(field.type);
            const base_type = if (field_type_info == .optional)
                field_type_info.optional.child
            else
                field.type;
            const type_info = @typeInfo(base_type);
            if (type_info == .int) {
                sql_type = if (type_info.int.bits == 64) .bigserial else .serial;
            } else {
                sql_type = types.zigToSQLType(field.type);
            }
        } else {
            sql_type = types.zigToSQLType(field.type);
        }

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
            .char => .varchar,
            .timestamp => .timestamp,
            .timestamptz => .timestamp,
            .date => .date,
            .time => .time,
            .json => .json,
            .jsonb => .jsonb,
            .blob => .bytea,
            .bytea => .bytea,
            .uuid => .uuid,
            .serial => .int, // SERIAL 映射为 INT
            .bigserial => .bigint, // BIGSERIAL 映射为 BIGINT
        };

        columns[i] = .{
            .name = field.name,
            .column_type = col_type,
            .nullable = is_optional,
            .primary_key = is_primary,
            .auto_increment = is_auto_increment,
            .unique = schema_cfg.unique,
            .default_value = schema_cfg.default,
            .check_expr = schema_cfg.check,
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
    try std.testing.expectEqual(ColumnType.bigint, columns[0].column_type);
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
