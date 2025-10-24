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

    // 数组类型 (PostgreSQL specific)
    smallint_array, // SMALLINT[]
    integer_array, // INTEGER[]
    bigint_array, // BIGINT[]
    real_array, // REAL[]
    double_array, // DOUBLE PRECISION[]
    boolean_array, // BOOLEAN[]
    text_array, // TEXT[]
    timestamp_array, // TIMESTAMP[]
    timestamptz_array, // TIMESTAMPTZ[]
    uuid_array, // UUID[]
    jsonb_array, // JSONB[]

    /// 转换为 PostgreSQL SQL 类型字符串
    pub fn toSQL(self: SQLType, comptime dialect: Dialect) []const u8 {
        _ = dialect; // PostgreSQL 专用
        return switch (self) {
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
            // 数组类型
            .smallint_array => "SMALLINT[]",
            .integer_array => "INTEGER[]",
            .bigint_array => "BIGINT[]",
            .real_array => "REAL[]",
            .double_array => "DOUBLE PRECISION[]",
            .boolean_array => "BOOLEAN[]",
            .text_array => "TEXT[]",
            .timestamp_array => "TIMESTAMP[]",
            .timestamptz_array => "TIMESTAMPTZ[]",
            .uuid_array => "UUID[]",
            .jsonb_array => "JSONB[]",
        };
    }
};

/// Zig 类型到 SQL 类型的映射
pub fn zigToSQLType(comptime T: type) SQLType {
    const type_info = @typeInfo(T);

    return switch (type_info) {
        .int => |int_info| {
            // 按照 PRD AC3.1.3 的映射规则:
            // - i8, i16, i32 → SMALLINT
            // - i64 → BIGINT
            // - u8, u16, u32 → INTEGER
            // - u64 → BIGINT
            if (int_info.signedness == .signed) {
                // 有符号整数
                if (int_info.bits <= 32) return .smallint; // i8, i16, i32
                return .bigint; // i64
            } else {
                // 无符号整数
                if (int_info.bits <= 32) return .integer; // u8, u16, u32
                return .bigint; // u64
            }
        },
        .float => |float_info| {
            if (float_info.bits <= 32) return .real;
            return .double;
        },
        .bool => .boolean,
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice) {
                // []const u8 -> TEXT (字符串)
                if (ptr_info.child == u8) {
                    return .text;
                }
                // 其他 slice 类型 -> 数组类型
                // 例如: []i64 -> BIGINT[], [][]const u8 -> TEXT[]
                const elem_sql_type = zigToSQLType(ptr_info.child);
                return mapToArrayType(elem_sql_type);
            }
            @compileError("Unsupported pointer type for SQL: " ++ @typeName(T));
        },
        .optional => |opt_info| {
            return zigToSQLType(opt_info.child);
        },
        .array => |arr_info| {
            // [16]u8 -> UUID (特殊处理)
            if (arr_info.len == 16 and arr_info.child == u8) {
                return .uuid;
            }
            // [N]u8 -> TEXT (字符串)
            if (arr_info.child == u8) {
                return .text;
            }
            @compileError("Unsupported array type for SQL: " ++ @typeName(T));
        },
        else => @compileError("Unsupported type for SQL: " ++ @typeName(T)),
    };
}

/// 将基础 SQLType 映射到对应的数组类型
pub fn mapToArrayType(base_type: SQLType) SQLType {
    return switch (base_type) {
        .smallint => .smallint_array,
        .integer => .integer_array,
        .bigint => .bigint_array,
        .real => .real_array,
        .double => .double_array,
        .boolean => .boolean_array,
        .text => .text_array,
        .varchar => .text_array, // VARCHAR 数组映射为 TEXT[]
        .char => .text_array, // CHAR 数组映射为 TEXT[]
        .timestamp => .timestamp_array,
        .timestamptz => .timestamptz_array,
        .date => .timestamp_array, // DATE 数组映射为 TIMESTAMP[]
        .time => .timestamp_array, // TIME 数组映射为 TIMESTAMP[]
        .uuid => .uuid_array,
        .json => .jsonb_array, // JSON 数组映射为 JSONB[]
        .jsonb => .jsonb_array,
        .serial => .integer_array, // SERIAL 数组映射为 INTEGER[]
        .bigserial => .bigint_array, // BIGSERIAL 数组映射为 BIGINT[]
        .blob => .text_array, // BLOB 数组映射为 TEXT[] (不推荐)
        .bytea => .text_array, // BYTEA 数组映射为 TEXT[] (不推荐)
        // 数组类型自身不能再创建数组 (不支持多维数组)
        // 这些分支应该永远不会被执行,因为我们不支持多维数组
        .smallint_array,
        .integer_array,
        .bigint_array,
        .real_array,
        .double_array,
        .boolean_array,
        .text_array,
        .timestamp_array,
        .timestamptz_array,
        .uuid_array,
        .jsonb_array,
        => .text_array, // 返回 TEXT[] 作为默认值 (实际上不应该被调用)
    };
}

/// 检测 SQLType 是否为数组类型
pub fn isArrayType(sql_type: SQLType) bool {
    return switch (sql_type) {
        .smallint_array,
        .integer_array,
        .bigint_array,
        .real_array,
        .double_array,
        .boolean_array,
        .text_array,
        .timestamp_array,
        .timestamptz_array,
        .uuid_array,
        .jsonb_array,
        => true,
        else => false,
    };
}

/// 获取数组类型的元素 SQLType
pub fn arrayElementType(array_type: SQLType) ?SQLType {
    return switch (array_type) {
        .smallint_array => .smallint,
        .integer_array => .integer,
        .bigint_array => .bigint,
        .real_array => .real,
        .double_array => .double,
        .boolean_array => .boolean,
        .text_array => .text,
        .timestamp_array => .timestamp,
        .timestamptz_array => .timestamptz,
        .uuid_array => .uuid,
        .jsonb_array => .jsonb,
        else => null,
    };
}

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

    // 有符号整数 (AC3.1.3: i8, i16, i32 → SMALLINT; i64 → BIGINT)
    try testing.expectEqual(SQLType.smallint, zigToSQLType(i8));
    try testing.expectEqual(SQLType.smallint, zigToSQLType(i16));
    try testing.expectEqual(SQLType.smallint, zigToSQLType(i32));
    try testing.expectEqual(SQLType.bigint, zigToSQLType(i64));

    // 无符号整数 (AC3.1.3: u8, u16, u32 → INTEGER; u64 → BIGINT)
    try testing.expectEqual(SQLType.integer, zigToSQLType(u8));
    try testing.expectEqual(SQLType.integer, zigToSQLType(u16));
    try testing.expectEqual(SQLType.integer, zigToSQLType(u32));
    try testing.expectEqual(SQLType.bigint, zigToSQLType(u64));

    // 浮点数
    try testing.expectEqual(SQLType.real, zigToSQLType(f32));
    try testing.expectEqual(SQLType.double, zigToSQLType(f64));

    // 布尔和文本
    try testing.expectEqual(SQLType.boolean, zigToSQLType(bool));
    try testing.expectEqual(SQLType.text, zigToSQLType([]const u8));

    // 可选类型
    try testing.expectEqual(SQLType.bigint, zigToSQLType(?i64));
    try testing.expectEqual(SQLType.integer, zigToSQLType(?u32));
    try testing.expectEqual(SQLType.text, zigToSQLType(?[]const u8));
}

test "SQLType.toSQL" {
    const testing = std.testing;

    // PostgreSQL (ZORM 仅支持 PostgreSQL)
    try testing.expectEqualStrings("BIGINT", SQLType.bigint.toSQL(.postgresql));
    try testing.expectEqualStrings("TEXT", SQLType.text.toSQL(.postgresql));
    try testing.expectEqualStrings("JSONB", SQLType.jsonb.toSQL(.postgresql));
    try testing.expectEqualStrings("UUID", SQLType.uuid.toSQL(.postgresql));
    try testing.expectEqualStrings("SERIAL", SQLType.serial.toSQL(.postgresql));
    try testing.expectEqualStrings("BIGSERIAL", SQLType.bigserial.toSQL(.postgresql));
}

test "zigToSQLType array types" {
    const testing = std.testing;

    // 数组类型检测
    try testing.expectEqual(SQLType.bigint_array, zigToSQLType([]i64));
    try testing.expectEqual(SQLType.integer_array, zigToSQLType([]u32));
    try testing.expectEqual(SQLType.smallint_array, zigToSQLType([]i32));
    try testing.expectEqual(SQLType.real_array, zigToSQLType([]f32));
    try testing.expectEqual(SQLType.double_array, zigToSQLType([]f64));
    try testing.expectEqual(SQLType.boolean_array, zigToSQLType([]bool));
    try testing.expectEqual(SQLType.text_array, zigToSQLType([][]const u8));

    // 可选数组类型
    try testing.expectEqual(SQLType.bigint_array, zigToSQLType(?[]i64));
    try testing.expectEqual(SQLType.text_array, zigToSQLType(?[][]const u8));

    // UUID 特殊处理
    try testing.expectEqual(SQLType.uuid, zigToSQLType([16]u8));
}

test "array type helpers" {
    const testing = std.testing;

    // mapToArrayType
    try testing.expectEqual(SQLType.integer_array, mapToArrayType(.integer));
    try testing.expectEqual(SQLType.bigint_array, mapToArrayType(.bigint));
    try testing.expectEqual(SQLType.text_array, mapToArrayType(.text));
    try testing.expectEqual(SQLType.boolean_array, mapToArrayType(.boolean));

    // isArrayType
    try testing.expect(isArrayType(.integer_array));
    try testing.expect(isArrayType(.text_array));
    try testing.expect(!isArrayType(.integer));
    try testing.expect(!isArrayType(.text));

    // arrayElementType
    try testing.expectEqual(SQLType.integer, arrayElementType(.integer_array).?);
    try testing.expectEqual(SQLType.bigint, arrayElementType(.bigint_array).?);
    try testing.expectEqual(SQLType.text, arrayElementType(.text_array).?);
    try testing.expectEqual(@as(?SQLType, null), arrayElementType(.integer));
}

test "SQLType.toSQL array types" {
    const testing = std.testing;

    try testing.expectEqualStrings("INTEGER[]", SQLType.integer_array.toSQL(.postgresql));
    try testing.expectEqualStrings("BIGINT[]", SQLType.bigint_array.toSQL(.postgresql));
    try testing.expectEqualStrings("TEXT[]", SQLType.text_array.toSQL(.postgresql));
    try testing.expectEqualStrings("BOOLEAN[]", SQLType.boolean_array.toSQL(.postgresql));
    try testing.expectEqualStrings("DOUBLE PRECISION[]", SQLType.double_array.toSQL(.postgresql));
}
