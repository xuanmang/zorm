//! Schema - 数据库模式管理
//!
//! 提供:
//! - 表结构定义和反射
//! - 模式迁移
//! - 类型映射

const std = @import("std");
const dialect_module = @import("../dialect/dialect.zig");

/// 列类型
pub const ColumnType = enum {
    int,
    bigint,
    smallint,
    boolean,
    varchar,
    text,
    timestamp,
    date,
    time,
    decimal,
    float,
    double,
    json,
    jsonb,
    uuid,
    bytea,

    /// 获取 SQL 类型名称
    pub fn sqlType(self: ColumnType, comptime dialect: dialect_module.Dialect) []const u8 {
        return switch (dialect) {
            .postgresql => switch (self) {
                .int => "INTEGER",
                .bigint => "BIGINT",
                .smallint => "SMALLINT",
                .boolean => "BOOLEAN",
                .varchar => "VARCHAR",
                .text => "TEXT",
                .timestamp => "TIMESTAMP",
                .date => "DATE",
                .time => "TIME",
                .decimal => "DECIMAL",
                .float => "REAL",
                .double => "DOUBLE PRECISION",
                .json => "JSON",
                .jsonb => "JSONB",
                .uuid => "UUID",
                .bytea => "BYTEA",
            },
            .mysql => switch (self) {
                .int => "INT",
                .bigint => "BIGINT",
                .smallint => "SMALLINT",
                .boolean => "BOOLEAN",
                .varchar => "VARCHAR",
                .text => "TEXT",
                .timestamp => "TIMESTAMP",
                .date => "DATE",
                .time => "TIME",
                .decimal => "DECIMAL",
                .float => "FLOAT",
                .double => "DOUBLE",
                .json => "JSON",
                .jsonb => "JSON",
                .uuid => "CHAR(36)",
                .bytea => "BLOB",
            },
            .sqlite => switch (self) {
                .int, .bigint, .smallint => "INTEGER",
                .boolean => "INTEGER",
                .varchar, .text => "TEXT",
                .timestamp, .date, .time => "TEXT",
                .decimal, .float, .double => "REAL",
                .json, .jsonb => "TEXT",
                .uuid => "TEXT",
                .bytea => "BLOB",
            },
        };
    }
};

/// 表元数据
pub const TableMeta = struct {
    name: []const u8,
    columns: []const ColumnMeta,
};

/// 列元数据
pub const ColumnMeta = struct {
    name: []const u8,
    type: ColumnType,
    nullable: bool = true,
    primary_key: bool = false,
    auto_increment: bool = false,
    default_value: ?[]const u8 = null,
};

/// 从 Zig 类型获取表元数据 (编译时)
pub fn getTableMeta(comptime T: type) TableMeta {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("getTableMeta requires a struct type, got " ++ @typeName(T));
    }

    // 获取表名 (优先使用 table_name 常量)
    const table_name = if (@hasDecl(T, "table_name"))
        @field(T, "table_name")
    else
        @typeName(T);

    // 提取字段信息
    const fields = type_info.@"struct".fields;
    comptime var columns: [fields.len]ColumnMeta = undefined;

    inline for (fields, 0..) |field, i| {
        columns[i] = .{
            .name = field.name,
            .type = inferColumnType(field.type),
            .nullable = isNullable(field.type),
            .primary_key = isPrimaryKey(field.name),
            .auto_increment = isAutoIncrement(field.name, field.type),
            .default_value = null,
        };
    }

    const final_columns = columns;
    return .{
        .name = table_name,
        .columns = &final_columns,
    };
}

/// 从 Zig 类型推断列类型 (编译时)
fn inferColumnType(comptime ZigType: type) ColumnType {
    // 处理可选类型 (?T)
    const actual_type = if (@typeInfo(ZigType) == .optional)
        @typeInfo(ZigType).optional.child
    else
        ZigType;

    const type_info = @typeInfo(actual_type);

    return switch (type_info) {
        .int => |int_info| {
            return switch (int_info.bits) {
                1...16 => .smallint,
                17...32 => .int,
                else => .bigint,
            };
        },
        .bool => .boolean,
        .float => |float_info| {
            return if (float_info.bits <= 32) .float else .double;
        },
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                return .text; // []const u8 或 []u8 映射为 TEXT
            }
            @compileError("Unsupported pointer type: " ++ @typeName(actual_type));
        },
        else => @compileError("Unsupported type for database column: " ++ @typeName(actual_type)),
    };
}

/// 检查类型是否可空 (编译时)
fn isNullable(comptime ZigType: type) bool {
    return @typeInfo(ZigType) == .optional;
}

/// 检查字段是否为主键 (基于约定: 名为 "id" 的字段)
fn isPrimaryKey(comptime field_name: []const u8) bool {
    return std.mem.eql(u8, field_name, "id");
}

/// 检查字段是否自增 (主键且为整数类型)
fn isAutoIncrement(comptime field_name: []const u8, comptime ZigType: type) bool {
    if (!isPrimaryKey(field_name)) {
        return false;
    }

    const actual_type = if (@typeInfo(ZigType) == .optional)
        @typeInfo(ZigType).optional.child
    else
        ZigType;

    return @typeInfo(actual_type) == .int;
}

// =============================================================================
// 单元测试
// =============================================================================

const testing = std.testing;

// 测试用模型定义
const TestUser = struct {
    id: i64,
    name: []const u8,
    email: ?[]const u8,
    age: i32,
    active: bool,

    pub const table_name = "users";
};

const TestProduct = struct {
    id: i64,
    title: []const u8,
    price: f64,
    stock: i32,
    // 没有 table_name,使用类型名
};

const TestSimple = struct {
    id: i64,
    value: i32,

    pub const table_name = "simple_table";
};

test "getTableMeta: 基本功能" {
    const meta = comptime getTableMeta(TestUser);

    // 验证表名
    try testing.expectEqualStrings("users", meta.name);

    // 验证列数
    try testing.expectEqual(5, meta.columns.len);

    // 验证 id 列
    try testing.expectEqualStrings("id", meta.columns[0].name);
    try testing.expectEqual(ColumnType.bigint, meta.columns[0].type);
    try testing.expectEqual(false, meta.columns[0].nullable);
    try testing.expectEqual(true, meta.columns[0].primary_key);
    try testing.expectEqual(true, meta.columns[0].auto_increment);

    // 验证 name 列
    try testing.expectEqualStrings("name", meta.columns[1].name);
    try testing.expectEqual(ColumnType.text, meta.columns[1].type);
    try testing.expectEqual(false, meta.columns[1].nullable);
    try testing.expectEqual(false, meta.columns[1].primary_key);

    // 验证 email 列 (可空)
    try testing.expectEqualStrings("email", meta.columns[2].name);
    try testing.expectEqual(ColumnType.text, meta.columns[2].type);
    try testing.expectEqual(true, meta.columns[2].nullable);
    try testing.expectEqual(false, meta.columns[2].primary_key);

    // 验证 age 列
    try testing.expectEqualStrings("age", meta.columns[3].name);
    try testing.expectEqual(ColumnType.int, meta.columns[3].type);
    try testing.expectEqual(false, meta.columns[3].nullable);

    // 验证 active 列
    try testing.expectEqualStrings("active", meta.columns[4].name);
    try testing.expectEqual(ColumnType.boolean, meta.columns[4].type);
    try testing.expectEqual(false, meta.columns[4].nullable);
}

test "getTableMeta: 使用类型名作为表名" {
    const meta = comptime getTableMeta(TestProduct);

    // 类型名包含完整路径,只检查是否包含 "TestProduct"
    try testing.expect(std.mem.indexOf(u8, meta.name, "TestProduct") != null);

    // 验证列数
    try testing.expectEqual(4, meta.columns.len);
}

test "getTableMeta: 简单结构" {
    const meta = comptime getTableMeta(TestSimple);

    try testing.expectEqualStrings("simple_table", meta.name);
    try testing.expectEqual(2, meta.columns.len);

    // id 应该是主键且自增
    try testing.expectEqual(true, meta.columns[0].primary_key);
    try testing.expectEqual(true, meta.columns[0].auto_increment);

    // value 不是主键
    try testing.expectEqual(false, meta.columns[1].primary_key);
    try testing.expectEqual(false, meta.columns[1].auto_increment);
}

test "inferColumnType: 整数类型" {
    try testing.expectEqual(ColumnType.smallint, comptime inferColumnType(i8));
    try testing.expectEqual(ColumnType.smallint, comptime inferColumnType(i16));
    try testing.expectEqual(ColumnType.int, comptime inferColumnType(i32));
    try testing.expectEqual(ColumnType.bigint, comptime inferColumnType(i64));

    try testing.expectEqual(ColumnType.smallint, comptime inferColumnType(u8));
    try testing.expectEqual(ColumnType.smallint, comptime inferColumnType(u16));
    try testing.expectEqual(ColumnType.int, comptime inferColumnType(u32));
    try testing.expectEqual(ColumnType.bigint, comptime inferColumnType(u64));
}

test "inferColumnType: 浮点类型" {
    try testing.expectEqual(ColumnType.float, comptime inferColumnType(f32));
    try testing.expectEqual(ColumnType.double, comptime inferColumnType(f64));
}

test "inferColumnType: 布尔类型" {
    try testing.expectEqual(ColumnType.boolean, comptime inferColumnType(bool));
}

test "inferColumnType: 字符串类型" {
    try testing.expectEqual(ColumnType.text, comptime inferColumnType([]const u8));
    try testing.expectEqual(ColumnType.text, comptime inferColumnType([]u8));
}

test "inferColumnType: 可选类型" {
    try testing.expectEqual(ColumnType.bigint, comptime inferColumnType(?i64));
    try testing.expectEqual(ColumnType.text, comptime inferColumnType(?[]const u8));
    try testing.expectEqual(ColumnType.boolean, comptime inferColumnType(?bool));
    try testing.expectEqual(ColumnType.float, comptime inferColumnType(?f32));
}

test "isNullable: 正确识别可选类型" {
    try testing.expectEqual(false, comptime isNullable(i64));
    try testing.expectEqual(true, comptime isNullable(?i64));
    try testing.expectEqual(false, comptime isNullable([]const u8));
    try testing.expectEqual(true, comptime isNullable(?[]const u8));
    try testing.expectEqual(false, comptime isNullable(bool));
    try testing.expectEqual(true, comptime isNullable(?bool));
}

test "isPrimaryKey: 基于字段名识别" {
    try testing.expectEqual(true, comptime isPrimaryKey("id"));
    try testing.expectEqual(false, comptime isPrimaryKey("user_id"));
    try testing.expectEqual(false, comptime isPrimaryKey("name"));
    try testing.expectEqual(false, comptime isPrimaryKey("ID")); // 大小写敏感
}

test "isAutoIncrement: 主键且为整数" {
    try testing.expectEqual(true, comptime isAutoIncrement("id", i64));
    try testing.expectEqual(true, comptime isAutoIncrement("id", i32));
    try testing.expectEqual(false, comptime isAutoIncrement("id", []const u8)); // 主键但非整数
    try testing.expectEqual(false, comptime isAutoIncrement("name", i64)); // 整数但非主键
    try testing.expectEqual(true, comptime isAutoIncrement("id", ?i64)); // 可选整数主键
}

test "ColumnType.sqlType: PostgreSQL" {
    try testing.expectEqualStrings("INTEGER", ColumnType.int.sqlType(.postgresql));
    try testing.expectEqualStrings("BIGINT", ColumnType.bigint.sqlType(.postgresql));
    try testing.expectEqualStrings("BOOLEAN", ColumnType.boolean.sqlType(.postgresql));
    try testing.expectEqualStrings("TEXT", ColumnType.text.sqlType(.postgresql));
    try testing.expectEqualStrings("JSONB", ColumnType.jsonb.sqlType(.postgresql));
}

test "ColumnType.sqlType: MySQL" {
    try testing.expectEqualStrings("INT", ColumnType.int.sqlType(.mysql));
    try testing.expectEqualStrings("BIGINT", ColumnType.bigint.sqlType(.mysql));
    try testing.expectEqualStrings("BOOLEAN", ColumnType.boolean.sqlType(.mysql));
    try testing.expectEqualStrings("TEXT", ColumnType.text.sqlType(.mysql));
    try testing.expectEqualStrings("JSON", ColumnType.jsonb.sqlType(.mysql));
}

test "ColumnType.sqlType: SQLite" {
    try testing.expectEqualStrings("INTEGER", ColumnType.int.sqlType(.sqlite));
    try testing.expectEqualStrings("INTEGER", ColumnType.bigint.sqlType(.sqlite));
    try testing.expectEqualStrings("INTEGER", ColumnType.boolean.sqlType(.sqlite));
    try testing.expectEqualStrings("TEXT", ColumnType.text.sqlType(.sqlite));
    try testing.expectEqualStrings("TEXT", ColumnType.jsonb.sqlType(.sqlite));
}

test "完整流程: 从类型到 SQL DDL" {
    const meta = comptime getTableMeta(TestUser);

    // 验证可以使用元数据生成 SQL 类型
    try testing.expectEqualStrings("BIGINT", meta.columns[0].type.sqlType(.postgresql));
    try testing.expectEqualStrings("TEXT", meta.columns[1].type.sqlType(.postgresql));
    try testing.expectEqualStrings("BOOLEAN", meta.columns[4].type.sqlType(.postgresql));
}

test "编译时元数据: 零运行时开销" {
    // 验证所有操作都可以在编译时完成
    comptime {
        const meta = getTableMeta(TestUser);
        std.debug.assert(std.mem.eql(u8, meta.name, "users"));
        std.debug.assert(meta.columns.len == 5);
        std.debug.assert(meta.columns[0].primary_key);
        std.debug.assert(meta.columns[2].nullable);
    }
}

test "多种类型综合测试" {
    const ComplexModel = struct {
        id: i64,
        uuid: []const u8,
        count: i32,
        price: f64,
        discount: ?f32,
        active: bool,
        description: ?[]const u8,

        pub const table_name = "complex_models";
    };

    const meta = comptime getTableMeta(ComplexModel);

    try testing.expectEqualStrings("complex_models", meta.name);
    try testing.expectEqual(7, meta.columns.len);

    // id 列
    try testing.expectEqual(ColumnType.bigint, meta.columns[0].type);
    try testing.expectEqual(true, meta.columns[0].primary_key);
    try testing.expectEqual(true, meta.columns[0].auto_increment);

    // uuid 列
    try testing.expectEqual(ColumnType.text, meta.columns[1].type);
    try testing.expectEqual(false, meta.columns[1].nullable);

    // count 列
    try testing.expectEqual(ColumnType.int, meta.columns[2].type);

    // price 列
    try testing.expectEqual(ColumnType.double, meta.columns[3].type);

    // discount 列 (可空)
    try testing.expectEqual(ColumnType.float, meta.columns[4].type);
    try testing.expectEqual(true, meta.columns[4].nullable);

    // active 列
    try testing.expectEqual(ColumnType.boolean, meta.columns[5].type);

    // description 列 (可空)
    try testing.expectEqual(ColumnType.text, meta.columns[6].type);
    try testing.expectEqual(true, meta.columns[6].nullable);
}
