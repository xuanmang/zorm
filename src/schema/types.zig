//! SQL 类型系统
//!
//! 定义 SQL 数据类型和 Zig 类型到 SQL 类型的映射规则

const std = @import("std");
const Dialect = @import("../dialect/dialect.zig").Dialect;

/// SQL 数据类型
pub const SQLType = enum {
    // 整数类型
    smallint,      // 16-bit
    integer,       // 32-bit
    bigint,        // 64-bit

    // 浮点类型
    real,          // 32-bit float
    double,        // 64-bit float

    // 布尔类型
    boolean,

    // 字符串类型
    text,
    varchar,
    char,

    // 时间类型
    timestamp,
    timestamptz,   // timestamp with timezone
    date,
    time,

    // JSON 类型
    json,
    jsonb,         // PostgreSQL binary JSON

    // 二进制类型
    blob,
    bytea,         // PostgreSQL

    // UUID 类型
    uuid,

    // 自增类型
    serial,        // auto-increment integer
    bigserial,     // auto-increment bigint

    /// 转换为特定方言的 SQL 类型字符串
    pub fn toSQL(self: SQLType, comptime dialect: Dialect) []const u8 {
        return comptime switch (dialect) {
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
            .mssql => switch (self) {
                .smallint => "SMALLINT",
                .integer => "INT",
                .bigint => "BIGINT",
                .real => "REAL",
                .double => "FLOAT",
                .boolean => "BIT",
                .text => "NVARCHAR(MAX)",
                .varchar => "NVARCHAR(255)",
                .char => "NCHAR",
                .timestamp => "DATETIME2",
                .timestamptz => "DATETIMEOFFSET",
                .date => "DATE",
                .time => "TIME",
                .json => "NVARCHAR(MAX)",
                .jsonb => "NVARCHAR(MAX)",
                .blob => "VARBINARY(MAX)",
                .bytea => "VARBINARY(MAX)",
                .uuid => "UNIQUEIDENTIFIER",
                .serial => "INT IDENTITY",
                .bigserial => "BIGINT IDENTITY",
            },
            .oracle => switch (self) {
                .smallint => "NUMBER(5)",
                .integer => "NUMBER(10)",
                .bigint => "NUMBER(19)",
                .real => "BINARY_FLOAT",
                .double => "BINARY_DOUBLE",
                .boolean => "NUMBER(1)",
                .text => "CLOB",
                .varchar => "VARCHAR2(255)",
                .char => "CHAR",
                .timestamp => "TIMESTAMP",
                .timestamptz => "TIMESTAMP WITH TIME ZONE",
                .date => "DATE",
                .time => "TIMESTAMP",
                .json => "CLOB",
                .jsonb => "CLOB",
                .blob => "BLOB",
                .bytea => "BLOB",
                .uuid => "RAW(16)",
                .serial => "NUMBER GENERATED ALWAYS AS IDENTITY",
                .bigserial => "NUMBER GENERATED ALWAYS AS IDENTITY",
            },
        };
    }
};

/// Zig 类型到 SQL 类型的映射
pub fn zigToSQLType(comptime T: type) SQLType {
    const type_info = @typeInfo(T);

    return switch (type_info) {
        .Int => |int_info| {
            if (int_info.bits <= 16) return .smallint;
            if (int_info.bits <= 32) return .integer;
            return .bigint;
        },
        .Float => |float_info| {
            if (float_info.bits <= 32) return .real;
            return .double;
        },
        .Bool => .boolean,
        .Pointer => |ptr_info| {
            // []const u8 -> TEXT
            if (ptr_info.size == .Slice and ptr_info.child == u8) {
                return .text;
            }
            @compileError("Unsupported pointer type for SQL: " ++ @typeName(T));
        },
        .Optional => |opt_info| {
            return zigToSQLType(opt_info.child);
        },
        .Array => |arr_info| {
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
    return @typeInfo(T) == .Optional;
}

/// 获取可选类型的子类型
pub fn optionalChild(comptime T: type) type {
    const type_info = @typeInfo(T);
    if (type_info != .Optional) {
        @compileError("Type is not optional: " ++ @typeName(T));
    }
    return type_info.Optional.child;
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
