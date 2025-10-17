// src/types.zig
// ZORM 基础类型定义系统
// 提供查询参数、SQL 子句和列类型的统一类型系统

const std = @import("std");
const Error = @import("error.zig").Error;

// ========== 查询参数类型 ==========

/// 查询参数联合类型
///
/// 支持所有常见的 SQL 参数类型，包括：
/// - 整数 (i64, u64)
/// - 浮点数 (f64)
/// - 布尔值 (bool)
/// - 字符串 ([]const u8)
/// - 字节数组 ([]const u8)
/// - NULL 值
///
/// 使用示例:
/// ```zig
/// const arg1 = QueryArg.fromValue(42);        // int
/// const arg2 = QueryArg.fromValue(3.14);      // float
/// const arg3 = QueryArg.fromValue("hello");   // string
/// const arg4 = QueryArg.fromValue(true);      // bool
/// const arg5 = QueryArg.fromValue(null);      // null
/// const arg6 = QueryArg.fromValue(@as(?i32, null)); // optional
/// ```
pub const QueryArg = union(enum) {
    /// 有符号整数 (映射到 SQL BIGINT)
    int: i64,

    /// 无符号整数 (映射到 SQL BIGINT UNSIGNED)
    uint: u64,

    /// 浮点数 (映射到 SQL DOUBLE PRECISION)
    float: f64,

    /// 布尔值 (映射到 SQL BOOLEAN)
    bool: bool,

    /// 字符串 (映射到 SQL TEXT/VARCHAR)
    /// 注意: 不拥有内存，调用者负责生命周期管理
    string: []const u8,

    /// 字节数组 (映射到 SQL BYTEA)
    /// 注意: 不拥有内存，调用者负责生命周期管理
    bytes: []const u8,

    /// NULL 值 (映射到 SQL NULL)
    null_val: void,

    /// 从任意类型值创建 QueryArg (编译时类型检查)
    ///
    /// 该函数使用 Zig 的 comptime 特性在编译时进行类型检查和转换，
    /// 确保类型安全且零运行时开销。
    ///
    /// 支持的类型:
    /// - 整数类型 (i8, i16, i32, i64, u8, u16, u32, u64, usize, isize)
    /// - 浮点类型 (f16, f32, f64)
    /// - 布尔类型 (bool)
    /// - 字符串切片 ([]const u8)
    /// - Null 类型
    /// - 可选类型 (Optional)
    ///
    /// 不支持的类型会在编译时产生错误。
    pub fn fromValue(value: anytype) QueryArg {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        return switch (type_info) {
            .int => |int_info| {
                if (int_info.signedness == .signed) {
                    return .{ .int = @intCast(value) };
                } else {
                    return .{ .uint = @intCast(value) };
                }
            },
            .comptime_int => .{ .int = value },
            .float => .{ .float = @floatCast(value) },
            .comptime_float => .{ .float = value },
            .bool => .{ .bool = value },
            .pointer => |ptr_info| {
                // 字符串切片: []const u8
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    return .{ .string = value };
                }
                // 字符串字面量: *const [N:0]u8 (指向以 null 结尾的数组)
                if (ptr_info.size == .one) {
                    const child_type = @typeInfo(ptr_info.child);
                    if (child_type == .array) {
                        const arr_info = child_type.array;
                        if (arr_info.child == u8) {
                            // 将字符串字面量转换为切片
                            return .{ .string = value };
                        }
                    }
                }
                @compileError("Unsupported pointer type for QueryArg: " ++ @typeName(T));
            },
            .null => .{ .null_val = {} },
            .optional => {
                if (value) |v| {
                    return fromValue(v);
                } else {
                    return .{ .null_val = {} };
                }
            },
            else => @compileError("Unsupported type for QueryArg: " ++ @typeName(T)),
        };
    }
};

// ========== WHERE 子句相关类型 ==========

/// WHERE 子句
///
/// 表示 SQL WHERE 条件及其绑定参数。
/// 支持 AND/OR 运算符组合多个条件。
///
/// 使用示例:
/// ```zig
/// const where1 = WhereClause{
///     .condition = "age > $1",
///     .args = &[_]QueryArg{QueryArg.fromValue(18)},
///     .operator = .and_op,
/// };
/// ```
pub const WhereClause = struct {
    /// WHERE 条件字符串 (如 "age > $1 AND status = $2")
    condition: []const u8,

    /// 绑定参数数组
    args: []const QueryArg,

    /// 与前一个条件的运算符 (AND/OR)
    operator: WhereOperator,
};

/// WHERE 运算符
///
/// 用于组合多个 WHERE 条件的逻辑运算符。
pub const WhereOperator = enum {
    /// AND 运算符 (所有条件都必须满足)
    and_op,

    /// OR 运算符 (至少一个条件满足即可)
    or_op,

    /// 转换为 SQL 字符串
    pub fn toSQL(self: WhereOperator) []const u8 {
        return switch (self) {
            .and_op => "AND",
            .or_op => "OR",
        };
    }
};

// ========== JOIN 子句相关类型 ==========

/// JOIN 子句
///
/// 表示 SQL JOIN 操作及其连接条件。
///
/// 使用示例:
/// ```zig
/// const join = JoinClause{
///     .join_type = .inner,
///     .table = "orders",
///     .condition = "users.id = orders.user_id",
/// };
/// ```
pub const JoinClause = struct {
    /// JOIN 类型 (INNER/LEFT/RIGHT/FULL/CROSS)
    join_type: JoinType,

    /// 要连接的表名
    table: []const u8,

    /// 连接条件 (如 "users.id = orders.user_id")
    condition: []const u8,
};

/// JOIN 类型
///
/// SQL 支持的各种 JOIN 类型。
pub const JoinType = enum {
    /// INNER JOIN - 只返回两表匹配的行
    inner,

    /// LEFT JOIN - 返回左表所有行，右表无匹配则为 NULL
    left,

    /// RIGHT JOIN - 返回右表所有行，左表无匹配则为 NULL
    right,

    /// FULL JOIN - 返回两表所有行，无匹配则为 NULL
    full,

    /// CROSS JOIN - 返回笛卡尔积
    cross,

    /// 转换为 SQL 字符串
    pub fn toSQL(self: JoinType) []const u8 {
        return switch (self) {
            .inner => "INNER JOIN",
            .left => "LEFT JOIN",
            .right => "RIGHT JOIN",
            .full => "FULL OUTER JOIN",
            .cross => "CROSS JOIN",
        };
    }
};

// ========== ORDER BY 子句相关类型 ==========

/// ORDER BY 子句
///
/// 表示 SQL ORDER BY 排序规则。
///
/// 使用示例:
/// ```zig
/// const order = OrderByClause{
///     .column = "created_at",
///     .direction = .desc,
/// };
/// ```
pub const OrderByClause = struct {
    /// 排序列名
    column: []const u8,

    /// 排序方向 (ASC/DESC)
    direction: OrderDirection,
};

/// 排序方向
///
/// SQL ORDER BY 的排序方向。
pub const OrderDirection = enum {
    /// 升序排序 (1, 2, 3, ...)
    asc,

    /// 降序排序 (3, 2, 1, ...)
    desc,

    /// 转换为 SQL 字符串
    pub fn toSQL(self: OrderDirection) []const u8 {
        return switch (self) {
            .asc => "ASC",
            .desc => "DESC",
        };
    }
};

// ========== HAVING 子句相关类型 ==========

/// HAVING 子句
///
/// 表示 SQL HAVING 条件 (用于 GROUP BY 后的过滤)。
///
/// 使用示例:
/// ```zig
/// const having = HavingClause{
///     .condition = "COUNT(*) > $1",
///     .args = &[_]QueryArg{QueryArg.fromValue(10)},
/// };
/// ```
pub const HavingClause = struct {
    /// HAVING 条件字符串
    condition: []const u8,

    /// 绑定参数数组
    args: []const QueryArg,
};

// ========== 列类型枚举 ==========

/// 列类型枚举
///
/// 表示 SQL 数据库的列类型，用于 Schema 定义和类型映射。
/// 涵盖 PostgreSQL/MySQL/SQLite/MSSQL/Oracle 的常见类型。
pub const ColumnType = enum {
    // ========== 整数类型 ==========

    /// SMALLINT - 小整数 (-32768 到 32767)
    smallint,

    /// INTEGER - 整数 (-2147483648 到 2147483647)
    integer,

    /// BIGINT - 大整数 (-9223372036854775808 到 9223372036854775807)
    bigint,

    // ========== 布尔类型 ==========

    /// BOOLEAN - 布尔值 (true/false)
    boolean,

    // ========== 文本类型 ==========

    /// CHAR(n) - 固定长度字符串
    char,

    /// VARCHAR(n) - 可变长度字符串
    varchar,

    /// TEXT - 无限制长度文本
    text,

    // ========== 浮点类型 ==========

    /// REAL - 单精度浮点数
    real,

    /// DOUBLE PRECISION - 双精度浮点数
    double_precision,

    /// NUMERIC/DECIMAL - 精确数值类型
    numeric,

    // ========== 日期时间类型 ==========

    /// DATE - 日期 (年-月-日)
    date,

    /// TIME - 时间 (时:分:秒)
    time,

    /// TIMESTAMP - 时间戳 (不带时区)
    timestamp,

    /// TIMESTAMPTZ - 时间戳 (带时区)
    timestamptz,

    // ========== JSON 类型 ==========

    /// JSON - JSON 文本格式
    json,

    /// JSONB - JSON 二进制格式 (PostgreSQL 特有)
    jsonb,

    // ========== 其他类型 ==========

    /// UUID - 通用唯一标识符
    uuid,

    /// BYTEA - 字节数组
    bytea,

    /// 转换为 SQL 类型名称
    pub fn toSQL(self: ColumnType) []const u8 {
        return switch (self) {
            .smallint => "SMALLINT",
            .integer => "INTEGER",
            .bigint => "BIGINT",
            .boolean => "BOOLEAN",
            .char => "CHAR",
            .varchar => "VARCHAR",
            .text => "TEXT",
            .real => "REAL",
            .double_precision => "DOUBLE PRECISION",
            .numeric => "NUMERIC",
            .date => "DATE",
            .time => "TIME",
            .timestamp => "TIMESTAMP",
            .timestamptz => "TIMESTAMPTZ",
            .json => "JSON",
            .jsonb => "JSONB",
            .uuid => "UUID",
            .bytea => "BYTEA",
        };
    }

    /// 从 Zig 类型推断列类型
    pub fn fromZigType(comptime T: type) ColumnType {
        const type_info = @typeInfo(T);
        return switch (type_info) {
            .int => |int_info| {
                if (int_info.signedness == .signed) {
                    if (int_info.bits <= 16) return .smallint;
                    if (int_info.bits <= 32) return .integer;
                    return .bigint;
                } else {
                    if (int_info.bits <= 16) return .smallint;
                    if (int_info.bits <= 32) return .integer;
                    return .bigint;
                }
            },
            .float => |float_info| {
                if (float_info.bits <= 32) return .real;
                return .double_precision;
            },
            .bool => .boolean,
            .pointer => |ptr_info| {
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    return .text;
                }
                @compileError("Unsupported pointer type for ColumnType: " ++ @typeName(T));
            },
            else => @compileError("Unsupported Zig type for ColumnType: " ++ @typeName(T)),
        };
    }
};

// ========== 测试 ==========

test "QueryArg.fromValue with int" {
    const testing = std.testing;

    const arg_i8 = QueryArg.fromValue(@as(i8, -10));
    try testing.expect(arg_i8 == .int);
    try testing.expectEqual(@as(i64, -10), arg_i8.int);

    const arg_i32 = QueryArg.fromValue(@as(i32, -42));
    try testing.expect(arg_i32 == .int);
    try testing.expectEqual(@as(i64, -42), arg_i32.int);

    const arg_i64 = QueryArg.fromValue(@as(i64, -9999));
    try testing.expect(arg_i64 == .int);
    try testing.expectEqual(@as(i64, -9999), arg_i64.int);
}

test "QueryArg.fromValue with uint" {
    const testing = std.testing;

    const arg_u8 = QueryArg.fromValue(@as(u8, 10));
    try testing.expect(arg_u8 == .uint);
    try testing.expectEqual(@as(u64, 10), arg_u8.uint);

    const arg_u32 = QueryArg.fromValue(@as(u32, 42));
    try testing.expect(arg_u32 == .uint);
    try testing.expectEqual(@as(u64, 42), arg_u32.uint);

    const arg_u64 = QueryArg.fromValue(@as(u64, 9999));
    try testing.expect(arg_u64 == .uint);
    try testing.expectEqual(@as(u64, 9999), arg_u64.uint);
}

test "QueryArg.fromValue with float" {
    const testing = std.testing;

    const arg_f32 = QueryArg.fromValue(@as(f32, 3.14));
    try testing.expect(arg_f32 == .float);
    try testing.expectApproxEqAbs(@as(f64, 3.14), arg_f32.float, 0.01);

    const arg_f64 = QueryArg.fromValue(@as(f64, 2.71828));
    try testing.expect(arg_f64 == .float);
    try testing.expectApproxEqAbs(@as(f64, 2.71828), arg_f64.float, 0.00001);
}

test "QueryArg.fromValue with bool" {
    const testing = std.testing;

    const arg_true = QueryArg.fromValue(true);
    try testing.expect(arg_true == .bool);
    try testing.expectEqual(true, arg_true.bool);

    const arg_false = QueryArg.fromValue(false);
    try testing.expect(arg_false == .bool);
    try testing.expectEqual(false, arg_false.bool);
}

test "QueryArg.fromValue with string" {
    const testing = std.testing;

    const arg_str = QueryArg.fromValue("hello");
    try testing.expect(arg_str == .string);
    try testing.expectEqualStrings("hello", arg_str.string);

    const empty_str = QueryArg.fromValue("");
    try testing.expect(empty_str == .string);
    try testing.expectEqualStrings("", empty_str.string);
}

test "QueryArg.fromValue with null" {
    const testing = std.testing;

    const arg_null = QueryArg.fromValue(null);
    try testing.expect(arg_null == .null_val);
}

test "QueryArg.fromValue with optional" {
    const testing = std.testing;

    // Optional with value
    const opt_value: ?i32 = 42;
    const arg_opt_value = QueryArg.fromValue(opt_value);
    try testing.expect(arg_opt_value == .int);
    try testing.expectEqual(@as(i64, 42), arg_opt_value.int);

    // Optional with null
    const opt_null: ?i32 = null;
    const arg_opt_null = QueryArg.fromValue(opt_null);
    try testing.expect(arg_opt_null == .null_val);

    // Optional string
    const opt_str: ?[]const u8 = "hello";
    const arg_opt_str = QueryArg.fromValue(opt_str);
    try testing.expect(arg_opt_str == .string);
    try testing.expectEqualStrings("hello", arg_opt_str.string);
}

test "WhereOperator.toSQL" {
    const testing = std.testing;

    try testing.expectEqualStrings("AND", WhereOperator.and_op.toSQL());
    try testing.expectEqualStrings("OR", WhereOperator.or_op.toSQL());
}

test "JoinType.toSQL" {
    const testing = std.testing;

    try testing.expectEqualStrings("INNER JOIN", JoinType.inner.toSQL());
    try testing.expectEqualStrings("LEFT JOIN", JoinType.left.toSQL());
    try testing.expectEqualStrings("RIGHT JOIN", JoinType.right.toSQL());
    try testing.expectEqualStrings("FULL OUTER JOIN", JoinType.full.toSQL());
    try testing.expectEqualStrings("CROSS JOIN", JoinType.cross.toSQL());
}

test "OrderDirection.toSQL" {
    const testing = std.testing;

    try testing.expectEqualStrings("ASC", OrderDirection.asc.toSQL());
    try testing.expectEqualStrings("DESC", OrderDirection.desc.toSQL());
}

test "ColumnType.toSQL" {
    const testing = std.testing;

    try testing.expectEqualStrings("INTEGER", ColumnType.integer.toSQL());
    try testing.expectEqualStrings("BIGINT", ColumnType.bigint.toSQL());
    try testing.expectEqualStrings("TEXT", ColumnType.text.toSQL());
    try testing.expectEqualStrings("BOOLEAN", ColumnType.boolean.toSQL());
    try testing.expectEqualStrings("TIMESTAMP", ColumnType.timestamp.toSQL());
    try testing.expectEqualStrings("JSONB", ColumnType.jsonb.toSQL());
}

test "ColumnType.fromZigType" {
    const testing = std.testing;

    // 整数类型
    try testing.expectEqual(ColumnType.smallint, ColumnType.fromZigType(i8));
    try testing.expectEqual(ColumnType.smallint, ColumnType.fromZigType(i16));
    try testing.expectEqual(ColumnType.integer, ColumnType.fromZigType(i32));
    try testing.expectEqual(ColumnType.bigint, ColumnType.fromZigType(i64));

    try testing.expectEqual(ColumnType.smallint, ColumnType.fromZigType(u8));
    try testing.expectEqual(ColumnType.smallint, ColumnType.fromZigType(u16));
    try testing.expectEqual(ColumnType.integer, ColumnType.fromZigType(u32));
    try testing.expectEqual(ColumnType.bigint, ColumnType.fromZigType(u64));

    // 浮点类型
    try testing.expectEqual(ColumnType.real, ColumnType.fromZigType(f32));
    try testing.expectEqual(ColumnType.double_precision, ColumnType.fromZigType(f64));

    // 布尔类型
    try testing.expectEqual(ColumnType.boolean, ColumnType.fromZigType(bool));

    // 字符串类型
    try testing.expectEqual(ColumnType.text, ColumnType.fromZigType([]const u8));
}

test "WhereClause creation" {
    const testing = std.testing;

    const args = [_]QueryArg{
        QueryArg.fromValue(18),
        QueryArg.fromValue("active"),
    };

    const where_clause = WhereClause{
        .condition = "age > $1 AND status = $2",
        .args = &args,
        .operator = .and_op,
    };

    try testing.expectEqualStrings("age > $1 AND status = $2", where_clause.condition);
    try testing.expectEqual(@as(usize, 2), where_clause.args.len);
    try testing.expectEqual(WhereOperator.and_op, where_clause.operator);
}

test "JoinClause creation" {
    const testing = std.testing;

    const join_clause = JoinClause{
        .join_type = .inner,
        .table = "orders",
        .condition = "users.id = orders.user_id",
    };

    try testing.expectEqual(JoinType.inner, join_clause.join_type);
    try testing.expectEqualStrings("orders", join_clause.table);
    try testing.expectEqualStrings("users.id = orders.user_id", join_clause.condition);
}

test "OrderByClause creation" {
    const testing = std.testing;

    const order_clause = OrderByClause{
        .column = "created_at",
        .direction = .desc,
    };

    try testing.expectEqualStrings("created_at", order_clause.column);
    try testing.expectEqual(OrderDirection.desc, order_clause.direction);
}

test "HavingClause creation" {
    const testing = std.testing;

    const args = [_]QueryArg{QueryArg.fromValue(10)};

    const having_clause = HavingClause{
        .condition = "COUNT(*) > $1",
        .args = &args,
    };

    try testing.expectEqualStrings("COUNT(*) > $1", having_clause.condition);
    try testing.expectEqual(@as(usize, 1), having_clause.args.len);
}
