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

// ========== INSERT 相关类型 ==========

/// INSERT 查询结果
///
/// 包含插入操作的结果信息。
///
/// 使用示例:
/// ```zig
/// const result = try query.exec();
/// std.debug.print("插入了 {} 行\n", .{result.rows_affected});
/// if (result.last_insert_id) |id| {
///     std.debug.print("最后插入的 ID: {}\n", .{id});
/// }
/// ```
pub const InsertResult = struct {
    /// 受影响的行数
    rows_affected: usize,

    /// 最后插入的 ID (对于支持的数据库)
    /// PostgreSQL 需要通过 RETURNING 获取
    /// MySQL 可以直接返回 LAST_INSERT_ID()
    last_insert_id: ?i64,
};

/// 冲突处理动作
///
/// 用于 PostgreSQL/SQLite 的 ON CONFLICT 子句。
pub const ConflictAction = enum {
    /// DO NOTHING - 忽略冲突的行
    do_nothing,

    /// DO UPDATE - 更新冲突的行
    do_update,

    /// 转换为 SQL 字符串
    pub fn toSQL(self: ConflictAction) []const u8 {
        return switch (self) {
            .do_nothing => "DO NOTHING",
            .do_update => "DO UPDATE",
        };
    }
};

/// ON CONFLICT 子句 (PostgreSQL/SQLite)
///
/// 用于处理插入冲突的情况，支持 UPSERT 操作。
///
/// 使用示例:
/// ```zig
/// const conflict = OnConflictClause{
///     .columns = &[_][]const u8{"email"},
///     .action = .do_update,
///     .update_columns = &[_][]const u8{"name", "updated_at"},
/// };
/// ```
pub const OnConflictClause = struct {
    /// 冲突检测的列 (用于 ON CONFLICT (columns))
    /// 如果为 null，则使用 ON CONFLICT 不指定列
    columns: ?[]const []const u8,

    /// 冲突处理动作
    action: ConflictAction,

    /// 要更新的列 (仅当 action = .do_update 时使用)
    update_columns: ?[]const []const u8,
};

/// ON DUPLICATE KEY UPDATE 子句 (MySQL)
///
/// MySQL 特定的 UPSERT 语法。
///
/// 使用示例:
/// ```zig
/// const updates = OnDuplicateKeyUpdate{
///     .columns = &[_][]const u8{"name", "updated_at"},
/// };
/// ```
pub const OnDuplicateKeyUpdate = struct {
    /// 要更新的列
    columns: []const []const u8,
};

test "ConflictAction.toSQL" {
    const testing = std.testing;

    try testing.expectEqualStrings("DO NOTHING", ConflictAction.do_nothing.toSQL());
    try testing.expectEqualStrings("DO UPDATE", ConflictAction.do_update.toSQL());
}

test "OnConflictClause creation" {
    const testing = std.testing;

    const columns = [_][]const u8{"email"};
    const update_columns = [_][]const u8{ "name", "updated_at" };

    const conflict = OnConflictClause{
        .columns = &columns,
        .action = .do_update,
        .update_columns = &update_columns,
    };

    try testing.expectEqual(@as(usize, 1), conflict.columns.?.len);
    try testing.expectEqual(ConflictAction.do_update, conflict.action);
    try testing.expectEqual(@as(usize, 2), conflict.update_columns.?.len);
}

test "OnDuplicateKeyUpdate creation" {
    const testing = std.testing;

    const columns = [_][]const u8{ "name", "email" };
    const update = OnDuplicateKeyUpdate{
        .columns = &columns,
    };

    try testing.expectEqual(@as(usize, 2), update.columns.len);
    try testing.expectEqualStrings("name", update.columns[0]);
    try testing.expectEqualStrings("email", update.columns[1]);
}

// ========== UPDATE 相关类型 ==========

/// UPDATE 查询结果
///
/// 包含更新操作的结果信息。
///
/// 使用示例:
/// ```zig
/// const result = try query.exec();
/// std.debug.print("更新了 {} 行\n", .{result.rows_affected});
/// ```
pub const UpdateResult = struct {
    /// 受影响的行数
    rows_affected: usize,
};

/// Raw SQL 查询结果
///
/// 用于 Raw SQL 执行的结果，包含受影响的行数。
/// 适用于 INSERT/UPDATE/DELETE/DDL 等不返回结果集的操作。
///
/// ## 使用场景
/// - 执行 Raw INSERT/UPDATE/DELETE 语句
/// - 执行 DDL 语句 (CREATE TABLE, DROP TABLE, etc.)
/// - 执行数据库管理命令
///
/// ## 示例
/// ```zig
/// const sql = "UPDATE users SET is_active = $1 WHERE created_at < $2";
/// var query = try db.newRaw(sql, .{ false, timestamp });
/// defer query.deinit();
///
/// const result = try query.exec();
/// std.debug.print("Updated {} rows\n", .{result.rows_affected});
/// ```
pub const RawResult = struct {
    /// 受影响的行数
    ///
    /// 对于 INSERT/UPDATE/DELETE 语句，表示被修改的行数。
    /// 对于 DDL 语句 (CREATE TABLE 等)，通常为 0。
    rows_affected: usize,
};

/// DELETE 查询执行结果
///
/// 包含删除操作影响的行数
///
/// ## 字段
/// - rows_affected: 被删除的行数
///
/// ## 示例
/// ```zig
/// const result = try query.exec();
/// std.debug.print("删除了 {d} 行\n", .{result.rows_affected});
/// ```
pub const DeleteResult = struct {
    /// 受影响的行数
    rows_affected: usize,
};

test "DeleteResult creation" {
    const testing = std.testing;

    const result = DeleteResult{
        .rows_affected = 3,
    };

    try testing.expectEqual(@as(usize, 3), result.rows_affected);
}

// ========== 子查询相关类型 ==========

/// 子查询类型
///
/// 定义不同类型的子查询操作
pub const SubqueryType = enum {
    /// WHERE column IN (SELECT ...)
    where_in,

    /// WHERE column NOT IN (SELECT ...)
    where_not_in,

    /// WHERE EXISTS (SELECT ...)
    exists,

    /// WHERE NOT EXISTS (SELECT ...)
    not_exists,
};

/// 子查询子句
///
/// 存储子查询的SQL、参数和类型信息。
/// 用于构建WHERE IN、EXISTS等子查询条件。
///
/// ## 使用场景
/// - WHERE IN 子查询:过滤在子查询结果中的记录
/// - WHERE NOT IN 子查询:过滤不在子查询结果中的记录
/// - WHERE EXISTS 子查询:过滤存在关联记录的记录
/// - WHERE NOT EXISTS 子查询:过滤不存在关联记录的记录
///
/// ## 示例
/// ```zig
/// const clause = SubqueryClause{
///     .type = .where_in,
///     .column = "id",
///     .sql = "SELECT user_id FROM posts WHERE published = $1",
///     .args = &[_]QueryArg{QueryArg.fromValue(true)},
/// };
/// ```
pub const SubqueryClause = struct {
    /// 子查询类型
    type: SubqueryType,

    /// 列名(仅用于 WHERE IN/NOT IN,可选)
    column: ?[]const u8,

    /// 子查询的完整SQL语句
    sql: []const u8,

    /// 子查询的绑定参数
    args: []const QueryArg,

    /// 将子查询子句转换为SQL字符串
    ///
    /// 根据子查询类型生成对应的SQL语法。
    ///
    /// 参数:
    /// - allocator: 用于分配SQL字符串的内存分配器
    ///
    /// 返回:
    /// - 生成的SQL字符串(调用者负责释放)
    ///
    /// 错误:
    /// - error.OutOfMemory: 内存分配失败
    ///
    /// 示例:
    /// ```zig
    /// const sql = try clause.toSQL(allocator);
    /// defer allocator.free(sql);
    /// // 对于WHERE IN: "id IN (SELECT ...)"
    /// // 对于EXISTS: "EXISTS (SELECT ...)"
    /// ```
    pub fn toSQL(self: SubqueryClause, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self.type) {
            .where_in => try std.fmt.allocPrint(
                allocator,
                "{s} IN ({s})",
                .{ self.column.?, self.sql },
            ),
            .where_not_in => try std.fmt.allocPrint(
                allocator,
                "{s} NOT IN ({s})",
                .{ self.column.?, self.sql },
            ),
            .exists => try std.fmt.allocPrint(
                allocator,
                "EXISTS ({s})",
                .{self.sql},
            ),
            .not_exists => try std.fmt.allocPrint(
                allocator,
                "NOT EXISTS ({s})",
                .{self.sql},
            ),
        };
    }
};

/// FROM派生表子句
///
/// 存储派生表的SQL、别名和参数信息。
/// 用于FROM子句中的子查询。
///
/// ## 使用场景
/// - 在FROM子句中使用子查询作为派生表
/// - 对子查询结果进行进一步过滤或聚合
///
/// ## 示例
/// ```zig
/// const derived = DerivedTable{
///     .sql = "SELECT id, COUNT(*) as post_count FROM users LEFT JOIN posts ON posts.user_id = users.id GROUP BY id",
///     .alias = "user_stats",
///     .args = &[_]QueryArg{},
/// };
/// ```
pub const DerivedTable = struct {
    /// 派生表子查询的SQL
    sql: []const u8,

    /// 派生表别名(必须)
    alias: []const u8,

    /// 派生表查询的参数
    args: []const QueryArg,
};

test "SubqueryType enum" {
    const testing = std.testing;

    // 验证枚举值存在
    const where_in_type: SubqueryType = .where_in;
    const where_not_in_type: SubqueryType = .where_not_in;
    const exists_type: SubqueryType = .exists;
    const not_exists_type: SubqueryType = .not_exists;

    try testing.expect(where_in_type == .where_in);
    try testing.expect(where_not_in_type == .where_not_in);
    try testing.expect(exists_type == .exists);
    try testing.expect(not_exists_type == .not_exists);
}

test "SubqueryClause.toSQL - WHERE IN" {
    const testing = std.testing;

    const args = [_]QueryArg{QueryArg.fromValue(true)};
    const clause = SubqueryClause{
        .type = .where_in,
        .column = "id",
        .sql = "SELECT user_id FROM posts WHERE published = $1",
        .args = &args,
    };

    const sql = try clause.toSQL(std.testing.allocator);
    defer std.testing.allocator.free(sql);

    try testing.expectEqualStrings(
        "id IN (SELECT user_id FROM posts WHERE published = $1)",
        sql,
    );
}

test "SubqueryClause.toSQL - WHERE NOT IN" {
    const testing = std.testing;

    const args = [_]QueryArg{QueryArg.fromValue(false)};
    const clause = SubqueryClause{
        .type = .where_not_in,
        .column = "user_id",
        .sql = "SELECT id FROM users WHERE active = $1",
        .args = &args,
    };

    const sql = try clause.toSQL(std.testing.allocator);
    defer std.testing.allocator.free(sql);

    try testing.expectEqualStrings(
        "user_id NOT IN (SELECT id FROM users WHERE active = $1)",
        sql,
    );
}

test "SubqueryClause.toSQL - EXISTS" {
    const testing = std.testing;

    const args = [_]QueryArg{QueryArg.fromValue(100)};
    const clause = SubqueryClause{
        .type = .exists,
        .column = null,
        .sql = "SELECT 1 FROM orders WHERE user_id = users.id AND total > $1",
        .args = &args,
    };

    const sql = try clause.toSQL(std.testing.allocator);
    defer std.testing.allocator.free(sql);

    try testing.expectEqualStrings(
        "EXISTS (SELECT 1 FROM orders WHERE user_id = users.id AND total > $1)",
        sql,
    );
}

test "SubqueryClause.toSQL - NOT EXISTS" {
    const testing = std.testing;

    const clause = SubqueryClause{
        .type = .not_exists,
        .column = null,
        .sql = "SELECT 1 FROM posts WHERE user_id = users.id",
        .args = &[_]QueryArg{},
    };

    const sql = try clause.toSQL(std.testing.allocator);
    defer std.testing.allocator.free(sql);

    try testing.expectEqualStrings(
        "NOT EXISTS (SELECT 1 FROM posts WHERE user_id = users.id)",
        sql,
    );
}

test "DerivedTable creation" {
    const testing = std.testing;

    const args = [_]QueryArg{QueryArg.fromValue(5)};
    const derived = DerivedTable{
        .sql = "SELECT id, COUNT(*) as post_count FROM users GROUP BY id HAVING COUNT(*) > $1",
        .alias = "user_stats",
        .args = &args,
    };

    try testing.expectEqualStrings(
        "SELECT id, COUNT(*) as post_count FROM users GROUP BY id HAVING COUNT(*) > $1",
        derived.sql,
    );
    try testing.expectEqualStrings("user_stats", derived.alias);
    try testing.expectEqual(@as(usize, 1), derived.args.len);
}

test "UpdateResult creation" {
    const testing = std.testing;

    const result = UpdateResult{
        .rows_affected = 5,
    };

    try testing.expectEqual(@as(usize, 5), result.rows_affected);
}
