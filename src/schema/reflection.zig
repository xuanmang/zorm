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

    // 使用 generateColumns 获取列定义（支持 schema 配置）
    const columns = try generateColumns(T, allocator);
    defer allocator.free(columns);

    // 检查是否有复合主键
    var pk_count: usize = 0;
    for (columns) |col| {
        if (col.primary_key) pk_count += 1;
    }
    const has_composite_pk = pk_count > 1;

    // 生成列定义
    for (columns, 0..) |*col, i| {
        if (i > 0) {
            try writer.writeAll(",\n");
        }
        try writer.writeAll("  ");

        // 使用 table_mod 中的 writeColumnDefinition 函数
        try table_mod.writeColumnDefinition(writer, col, dialect, has_composite_pk);
    }

    // 如果有复合主键，添加 PRIMARY KEY 约束
    if (has_composite_pk) {
        try writer.writeAll(",\n  PRIMARY KEY (");
        var first_pk = true;
        for (columns) |col| {
            if (col.primary_key) {
                if (!first_pk) try writer.writeAll(", ");
                try writer.writeAll(col.name);
                first_pk = false;
            }
        }
        try writer.writeAll(")");
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
            // 数组类型映射
            .smallint_array => .smallint_array,
            .integer_array => .int_array,
            .bigint_array => .bigint_array,
            .real_array => .float_array,
            .double_array => .double_array,
            .boolean_array => .boolean_array,
            .text_array => .text_array,
            .timestamp_array => .timestamp_array,
            .timestamptz_array => .timestamp_array,
            .uuid_array => .uuid_array,
            .jsonb_array => .jsonb_array,
        };

        // 使用自定义列名（如果配置了），否则使用字段名
        const col_name = if (schema_cfg.column_name) |custom_name|
            custom_name
        else
            field.name;

        columns[i] = .{
            .name = col_name,
            .column_type = col_type,
            .nullable = is_optional,
            .primary_key = is_primary,
            .auto_increment = is_auto_increment,
            .unique = schema_cfg.unique,
            .default_value = schema_cfg.default,
            .check_expr = schema_cfg.check,
            .custom_sql_type = schema_cfg.sql_type, // 设置自定义 SQL 类型
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
        age: u32, // 使用 u32 以映射到 INTEGER (符合 PRD AC3.1.3)
        is_active: bool,

        pub const table_name = "users";
    };

    const allocator = std.testing.allocator;
    const sql = try generateCreateTableSQL(User, .postgresql, allocator);
    defer allocator.free(sql);

    // 验证包含关键部分
    try std.testing.expect(std.mem.indexOf(u8, sql, "CREATE TABLE users") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "id BIGSERIAL PRIMARY KEY") != null);
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

test "generateColumns with custom column names" {
    const User = struct {
        id: i64,
        user_name: []const u8,
        user_email: []const u8,

        pub const schema = .{
            .user_name = .{ .column_name = "username" },
            .user_email = .{ .column_name = "email" },
        };
    };

    const allocator = std.testing.allocator;
    const columns = try generateColumns(User, allocator);
    defer allocator.free(columns);

    try std.testing.expectEqual(@as(usize, 3), columns.len);

    // id 列（无自定义列名）
    try std.testing.expectEqualStrings("id", columns[0].name);

    // user_name 列（自定义列名为 username）
    try std.testing.expectEqualStrings("username", columns[1].name);

    // user_email 列（自定义列名为 email）
    try std.testing.expectEqualStrings("email", columns[2].name);
}

test "generateColumns with custom SQL types" {
    const User = struct {
        id: i64,
        username: []const u8,
        price: f64,

        pub const schema = .{
            .username = .{ .sql_type = "VARCHAR(50)" },
            .price = .{ .sql_type = "DECIMAL(10,2)" },
        };
    };

    const allocator = std.testing.allocator;
    const columns = try generateColumns(User, allocator);
    defer allocator.free(columns);

    try std.testing.expectEqual(@as(usize, 3), columns.len);

    // id 列（无自定义类型）
    try std.testing.expect(columns[0].custom_sql_type == null);

    // username 列（自定义类型 VARCHAR(50)）
    try std.testing.expect(columns[1].custom_sql_type != null);
    try std.testing.expectEqualStrings("VARCHAR(50)", columns[1].custom_sql_type.?);

    // price 列（自定义类型 DECIMAL(10,2)）
    try std.testing.expect(columns[2].custom_sql_type != null);
    try std.testing.expectEqualStrings("DECIMAL(10,2)", columns[2].custom_sql_type.?);
}

test "generateColumns with custom column name and SQL type combined" {
    const User = struct {
        id: i64,
        user_name: []const u8,

        pub const schema = .{
            .user_name = .{
                .column_name = "username",
                .sql_type = "VARCHAR(100)",
                .unique = true,
            },
        };
    };

    const allocator = std.testing.allocator;
    const columns = try generateColumns(User, allocator);
    defer allocator.free(columns);

    try std.testing.expectEqual(@as(usize, 2), columns.len);

    // user_name 列（同时有自定义列名和 SQL 类型）
    try std.testing.expectEqualStrings("username", columns[1].name);
    try std.testing.expectEqualStrings("VARCHAR(100)", columns[1].custom_sql_type.?);
    try std.testing.expect(columns[1].unique);
}

test "generateCreateTableSQL with field customization - constraint combinations" {
    const User = struct {
        id: i64,
        user_name: []const u8,
        email: []const u8,
        age: i32,
        status: []const u8,

        pub const table_name = "users";

        pub const schema = .{
            .user_name = .{
                .column_name = "username",
                .sql_type = "VARCHAR(50)",
                .unique = true,
            },
            .email = .{
                .unique = true,
            },
            .age = .{
                .check = "age >= 0 AND age <= 150",
            },
            .status = .{
                .default = "'active'",
            },
        };
    };

    const allocator = std.testing.allocator;
    const sql = try generateCreateTableSQL(User, .postgresql, allocator);
    defer allocator.free(sql);

    // 验证自定义列名和 SQL 类型
    try std.testing.expect(std.mem.indexOf(u8, sql, "username VARCHAR(50)") != null);
    // 验证 UNIQUE 约束
    try std.testing.expect(std.mem.indexOf(u8, sql, "username VARCHAR(50) NOT NULL UNIQUE") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "email TEXT NOT NULL UNIQUE") != null);
    // 验证 CHECK 约束
    try std.testing.expect(std.mem.indexOf(u8, sql, "age >= 0 AND age <= 150") != null);
    // 验证 DEFAULT 值
    try std.testing.expect(std.mem.indexOf(u8, sql, "DEFAULT 'active'") != null);
}

test "PRD AC3.2.8 Example" {
    // PRD Story 3.2 AC3.2.8 示例代码验证
    const User = struct {
        id: i64,
        username: []const u8,
        email: []const u8,
        age: u32,
        status: []const u8,
        created_at: i64,

        pub const table_name = "users";

        // Schema 配置（comptime）
        pub const schema = .{
            .id = .{ .primary_key = true, .auto_increment = true },
            .username = .{ .unique = true, .sql_type = "VARCHAR(50)" },
            .email = .{ .unique = true },
            .age = .{ .check = "age >= 0 AND age <= 150" },
            .status = .{ .default = "'active'" },
            .created_at = .{ .default = "CURRENT_TIMESTAMP" },
        };
    };

    const allocator = std.testing.allocator;
    const sql = try generateCreateTableSQL(User, .postgresql, allocator);
    defer allocator.free(sql);

    // 验证生成的 SQL 符合 PRD 期望
    try std.testing.expect(std.mem.indexOf(u8, sql, "CREATE TABLE users") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "id BIGSERIAL PRIMARY KEY") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "username VARCHAR(50)") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "username VARCHAR(50) NOT NULL UNIQUE") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "email TEXT NOT NULL UNIQUE") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "age INTEGER NOT NULL CHECK (age >= 0 AND age <= 150)") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "status TEXT NOT NULL DEFAULT 'active'") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "created_at BIGINT NOT NULL DEFAULT CURRENT_TIMESTAMP") != null);
}
