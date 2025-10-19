//! SQL 类型系统
//!
//! 定义 SQL 数据类型和 Zig 类型到 SQL 类型的映射规则

const std = @import("std");
const Dialect = @import("../dialect/dialect.zig").Dialect;

/// SQL 数据类型
pub const SQLType = enum {
    // 整数类型
    smallint, // 16-bit
    integer, // 32-bit
    bigint, // 64-bit

    // 浮点类型
    real, // 32-bit float
    double, // 64-bit float

    // 布尔类型
    boolean,

    // 字符串类型
    text,
    varchar,
    char,

    // 时间类型
    timestamp,
    timestamptz, // timestamp with timezone
    date,
    time,

    // JSON 类型
    json,
    jsonb, // PostgreSQL binary JSON

    // 二进制类型
    blob,
    bytea, // PostgreSQL

    // UUID 类型
    uuid,

    // 自增类型
    serial, // auto-increment integer
    bigserial, // auto-increment bigint

    /// 转换为特定方言的 SQL 类型字符串
    pub fn toSQL(self: SQLType, comptime dialect: Dialect) []const u8 {
        return switch (dialect) {
            .postgresql => switch (self) {
                .smallint => "SMALLINT",
                .integer => "INTEGER",
                .bigint => "BIGINT",
                .real => "REAL",
                .double => "DOUBLE PRECISION",
                .boolean => "BOOLEAN",
                .text => "TEXT",
                .varchar => "VARCHAR",
                .char => "CHAR",
                .timestamp => "TIMESTAMP",
                .timestamptz => "TIMESTAMPTZ",
                .date => "DATE",
                .time => "TIME",
                .json => "JSON",
                .jsonb => "JSONB",
                .blob => "BYTEA",
                .bytea => "BYTEA",
                .uuid => "UUID",
                .serial => "SERIAL",
                .bigserial => "BIGSERIAL",
            },
            .mysql => switch (self) {
                .smallint => "SMALLINT",
                .integer => "INT",
                .bigint => "BIGINT",
                .real => "FLOAT",
                .double => "DOUBLE",
                .boolean => "BOOLEAN",
                .text => "TEXT",
                .varchar => "VARCHAR(255)",
                .char => "CHAR",
                .timestamp => "TIMESTAMP",
                .timestamptz => "TIMESTAMP",
                .date => "DATE",
                .time => "TIME",
                .json => "JSON",
                .jsonb => "JSON",
                .blob => "BLOB",
                .bytea => "BLOB",
                .uuid => "CHAR(36)",
                .serial => "INT AUTO_INCREMENT",
                .bigserial => "BIGINT AUTO_INCREMENT",
            },
            .sqlite => switch (self) {
                .smallint => "INTEGER",
                .integer => "INTEGER",
                .bigint => "INTEGER",
                .real => "REAL",
                .double => "REAL",
                .boolean => "INTEGER",
                .text => "TEXT",
                .varchar => "TEXT",
                .char => "TEXT",
                .timestamp => "INTEGER",
                .timestamptz => "INTEGER",
                .date => "TEXT",
                .time => "TEXT",
                .json => "TEXT",
                .jsonb => "TEXT",
                .blob => "BLOB",
                .bytea => "BLOB",
                .uuid => "TEXT",
                .serial => "INTEGER",
                .bigserial => "INTEGER",
            },
        };
    }
};

/// Zig 类型到 SQL 类型的映射
pub fn zigToSQLType(comptime T: type) SQLType {
    const type_info = @typeInfo(T);

    return switch (type_info) {
        .int => |int_info| {
            if (int_info.bits <= 16) return .smallint;
            if (int_info.bits <= 32) return .integer;
            return .bigint;
        },
        .float => |float_info| {
            if (float_info.bits <= 32) return .real;
            return .double;
        },
        .bool => .boolean,
        .pointer => |ptr_info| {
            // []const u8 -> TEXT
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                return .text;
            }
            @compileError("Unsupported pointer type for SQL: " ++ @typeName(T));
        },
        .optional => |opt_info| {
            return zigToSQLType(opt_info.child);
        },
        .array => |arr_info| {
            // [N]u8 -> TEXT
            if (arr_info.child == u8) {
                return .text;
            }
            @compileError("Unsupported array type for SQL: " ++ @typeName(T));
        },
        else => @compileError("Unsupported type for SQL: " ++ @typeName(T)),
    };
}

/// 检查类型是否是可选类型
pub fn isOptional(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

/// 检查类型是否为整数类型 (i8, i16, i32, i64, u8, u16, u32, u64 等)
///
/// 支持可选类型,会自动解包检查基础类型
pub fn isIntegerType(comptime T: type) bool {
    const base_type = if (@typeInfo(T) == .optional)
        @typeInfo(T).optional.child
    else
        T;

    return @typeInfo(base_type) == .int;
}

/// 获取可选类型的子类型
pub fn optionalChild(comptime T: type) type {
    const type_info = @typeInfo(T);
    if (type_info != .optional) {
        @compileError("Type is not optional: " ++ @typeName(T));
    }
    return type_info.optional.child;
}

test "zigToSQLType" {
    const testing = std.testing;

    try testing.expectEqual(SQLType.smallint, zigToSQLType(i16));
    try testing.expectEqual(SQLType.integer, zigToSQLType(i32));
    try testing.expectEqual(SQLType.bigint, zigToSQLType(i64));
    try testing.expectEqual(SQLType.real, zigToSQLType(f32));
    try testing.expectEqual(SQLType.double, zigToSQLType(f64));
    try testing.expectEqual(SQLType.boolean, zigToSQLType(bool));
    try testing.expectEqual(SQLType.text, zigToSQLType([]const u8));

    // Optional types
    try testing.expectEqual(SQLType.bigint, zigToSQLType(?i64));
    try testing.expectEqual(SQLType.text, zigToSQLType(?[]const u8));
}

test "SQLType.toSQL" {
    const testing = std.testing;

    // PostgreSQL
    try testing.expectEqualStrings("BIGINT", SQLType.bigint.toSQL(.postgresql));
    try testing.expectEqualStrings("TEXT", SQLType.text.toSQL(.postgresql));
    try testing.expectEqualStrings("JSONB", SQLType.jsonb.toSQL(.postgresql));

    // MySQL
    try testing.expectEqualStrings("BIGINT", SQLType.bigint.toSQL(.mysql));
    try testing.expectEqualStrings("TEXT", SQLType.text.toSQL(.mysql));
    try testing.expectEqualStrings("JSON", SQLType.jsonb.toSQL(.mysql));

    // SQLite
    try testing.expectEqualStrings("INTEGER", SQLType.bigint.toSQL(.sqlite));
    try testing.expectEqualStrings("TEXT", SQLType.text.toSQL(.sqlite));
}
