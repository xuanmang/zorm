//! Query - 查询构建器
//!
//! 提供类型安全的 SQL 查询构建器:
//! - SelectQuery - SELECT 查询
//! - InsertQuery - INSERT 查询
//! - UpdateQuery - UPDATE 查询
//! - DeleteQuery - DELETE 查询
//!
//! ## 设计原则
//! - 使用 comptime 泛型实现类型安全
//! - 链式 API 提供流畅的查询构建体验
//! - 方言感知,根据不同数据库生成正确的 SQL

const std = @import("std");
const Allocator = std.mem.Allocator;
const db_mod = @import("../core/db.zig");
const Dialect = @import("../dialect/dialect.zig").Dialect;
const types = @import("../types.zig");
const result_scanner = @import("../mapper/result_scanner.zig");

// 重导出类型定义
pub const WhereClause = types.WhereClause;
pub const WhereOperator = types.WhereOperator;
pub const JoinClause = types.JoinClause;
pub const JoinType = types.JoinType;
pub const OrderByClause = types.OrderByClause;
pub const OrderDirection = types.OrderDirection;
pub const HavingClause = types.HavingClause;
pub const QueryArg = types.QueryArg;
pub const InsertResult = types.InsertResult;
pub const UpdateResult = types.UpdateResult;
pub const ConflictAction = types.ConflictAction;
pub const OnConflictClause = types.OnConflictClause;
pub const OnDuplicateKeyUpdate = types.OnDuplicateKeyUpdate;

/// SELECT 查询构建器
///
/// ## 参数
/// - T: 模型类型
/// - dialect: 数据库方言 (编译时确定)
///
/// ## 示例
/// ```zig
/// const User = struct {
///     id: i64,
///     name: []const u8,
/// };
///
/// var query = try db.newSelect(User);
/// defer query.deinit();
///
/// try query.column("id").column("name")
///          .where("age > ?", .{18})
///          .orderBy("id DESC")
///          .limit(10);
///
/// const sql = try query.build();
/// ```
pub fn SelectQuery(comptime T: type, comptime dialect: Dialect) type {
    const DBType = db_mod.DB(dialect);

    return struct {
        const Self = @This();

        allocator: Allocator,
        db: *DBType,
        columns: std.ArrayList([]const u8),
        table_name: []const u8,
        where_clauses: std.ArrayList(WhereClause),
        join_clauses: std.ArrayList(JoinClause),
        order_by_clauses: std.ArrayList(OrderByClause),
        group_by_columns: std.ArrayList([]const u8),
        having_clauses: std.ArrayList(HavingClause),
        limit_value: ?usize,
        offset_value: ?usize,
        distinct_value: bool,

        /// 初始化查询构建器
        pub fn init(allocator: Allocator, db: *DBType, table_name: []const u8) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.* = .{
                .allocator = allocator,
                .db = db,
                .columns = .{},
                .table_name = table_name,
                .where_clauses = .{},
                .join_clauses = .{},
                .order_by_clauses = .{},
                .group_by_columns = .{},
                .having_clauses = .{},
                .limit_value = null,
                .offset_value = null,
                .distinct_value = false,
            };

            return self;
        }

        /// 释放资源
        pub fn deinit(self: *Self) void {
            self.columns.deinit(self.allocator);

            // 释放 WHERE 子句参数
            for (self.where_clauses.items) |clause| {
                self.allocator.free(clause.args);
            }
            self.where_clauses.deinit(self.allocator);

            self.join_clauses.deinit(self.allocator);
            self.order_by_clauses.deinit(self.allocator);
            self.group_by_columns.deinit(self.allocator);

            // 释放 HAVING 子句参数
            for (self.having_clauses.items) |clause| {
                self.allocator.free(clause.args);
            }
            self.having_clauses.deinit(self.allocator);

            self.allocator.destroy(self);
        }

        /// 选择列
        pub fn column(self: *Self, col: []const u8) !*Self {
            try self.columns.append(self.allocator, col);
            return self;
        }

        /// 选择所有列
        pub fn columnAll(self: *Self) !*Self {
            try self.columns.append(self.allocator, "*");
            return self;
        }

        /// 添加 WHERE 条件 (AND)
        pub fn where(self: *Self, condition: []const u8, args: anytype) !*Self {
            const args_slice = try allocArgs(self.allocator, args);
            const clause = WhereClause{
                .condition = condition,
                .args = args_slice,
                .operator = .and_op,
            };
            try self.where_clauses.append(self.allocator, clause);
            return self;
        }

        /// 添加 WHERE 条件 (OR)
        pub fn whereOr(self: *Self, condition: []const u8, args: anytype) !*Self {
            const args_slice = try allocArgs(self.allocator, args);
            const clause = WhereClause{
                .condition = condition,
                .args = args_slice,
                .operator = .or_op,
            };
            try self.where_clauses.append(self.allocator, clause);
            return self;
        }

        /// 添加 JOIN 子句
        pub fn join(self: *Self, join_type: JoinType, table: []const u8, condition: []const u8) !*Self {
            const clause = JoinClause{
                .join_type = join_type,
                .table = table,
                .condition = condition,
            };
            try self.join_clauses.append(self.allocator, clause);
            return self;
        }

        /// 添加 INNER JOIN
        pub fn innerJoin(self: *Self, table: []const u8, condition: []const u8) !*Self {
            return self.join(.inner, table, condition);
        }

        /// 添加 LEFT JOIN
        pub fn leftJoin(self: *Self, table: []const u8, condition: []const u8) !*Self {
            return self.join(.left, table, condition);
        }

        /// 添加 RIGHT JOIN
        pub fn rightJoin(self: *Self, table: []const u8, condition: []const u8) !*Self {
            return self.join(.right, table, condition);
        }

        /// 添加 FULL OUTER JOIN
        pub fn fullJoin(self: *Self, table: []const u8, condition: []const u8) !*Self {
            return self.join(.full, table, condition);
        }

        /// 添加 CROSS JOIN
        pub fn crossJoin(self: *Self, table: []const u8) !*Self {
            return self.join(.cross, table, "");
        }

        /// 添加 ORDER BY
        pub fn orderBy(self: *Self, col: []const u8, direction: OrderDirection) !*Self {
            const clause = OrderByClause{
                .column = col,
                .direction = direction,
            };
            try self.order_by_clauses.append(self.allocator, clause);
            return self;
        }

        /// 添加 GROUP BY
        pub fn groupBy(self: *Self, col: []const u8) !*Self {
            try self.group_by_columns.append(self.allocator, col);
            return self;
        }

        /// 添加 HAVING 子句
        pub fn having(self: *Self, condition: []const u8, args: anytype) !*Self {
            const args_slice = try allocArgs(self.allocator, args);
            const clause = HavingClause{
                .condition = condition,
                .args = args_slice,
            };
            try self.having_clauses.append(self.allocator, clause);
            return self;
        }

        /// 设置 LIMIT
        pub fn limit(self: *Self, value: usize) !*Self {
            self.limit_value = value;
            return self;
        }

        /// 设置 OFFSET
        pub fn offset(self: *Self, value: usize) !*Self {
            self.offset_value = value;
            return self;
        }

        /// 设置 DISTINCT
        pub fn distinct(self: *Self) !*Self {
            self.distinct_value = true;
            return self;
        }

        /// 构建 SQL 查询字符串
        pub fn build(self: *Self) ![]const u8 {
            var buf = std.ArrayList(u8){};
            errdefer buf.deinit(self.allocator);

            // SELECT [DISTINCT]
            try buf.appendSlice(self.allocator, "SELECT ");
            if (self.distinct_value) {
                try buf.appendSlice(self.allocator, "DISTINCT ");
            }

            // 列
            if (self.columns.items.len > 0) {
                for (self.columns.items, 0..) |col, i| {
                    if (i > 0) try buf.appendSlice(self.allocator, ", ");
                    try buf.appendSlice(self.allocator, col);
                }
            } else {
                try buf.appendSlice(self.allocator, "*");
            }

            // FROM
            try buf.appendSlice(self.allocator, " FROM ");
            try buf.appendSlice(self.allocator, self.table_name);

            // JOINs
            for (self.join_clauses.items) |join_clause| {
                try buf.appendSlice(self.allocator, " ");
                try buf.appendSlice(self.allocator, join_clause.join_type.toSQL());
                try buf.appendSlice(self.allocator, " ");
                try buf.appendSlice(self.allocator, join_clause.table);

                // CROSS JOIN 不需要 ON 条件
                if (join_clause.join_type != .cross) {
                    try buf.appendSlice(self.allocator, " ON ");
                    try buf.appendSlice(self.allocator, join_clause.condition);
                }
            }

            // WHERE
            if (self.where_clauses.items.len > 0) {
                try buf.appendSlice(self.allocator, " WHERE ");
                for (self.where_clauses.items, 0..) |clause, i| {
                    if (i > 0) {
                        try buf.appendSlice(self.allocator, " ");
                        try buf.appendSlice(self.allocator, clause.operator.toSQL());
                        try buf.appendSlice(self.allocator, " ");
                    }
                    try buf.appendSlice(self.allocator, clause.condition);
                }
            }

            // GROUP BY
            if (self.group_by_columns.items.len > 0) {
                try buf.appendSlice(self.allocator, " GROUP BY ");
                for (self.group_by_columns.items, 0..) |col, i| {
                    if (i > 0) try buf.appendSlice(self.allocator, ", ");
                    try buf.appendSlice(self.allocator, col);
                }
            }

            // HAVING
            if (self.having_clauses.items.len > 0) {
                try buf.appendSlice(self.allocator, " HAVING ");
                for (self.having_clauses.items, 0..) |clause, i| {
                    if (i > 0) try buf.appendSlice(self.allocator, " AND ");
                    try buf.appendSlice(self.allocator, clause.condition);
                }
            }

            // ORDER BY
            if (self.order_by_clauses.items.len > 0) {
                try buf.appendSlice(self.allocator, " ORDER BY ");
                for (self.order_by_clauses.items, 0..) |order_clause, i| {
                    if (i > 0) try buf.appendSlice(self.allocator, ", ");
                    try buf.appendSlice(self.allocator, order_clause.column);
                    try buf.appendSlice(self.allocator, " ");
                    try buf.appendSlice(self.allocator, order_clause.direction.toSQL());
                }
            }

            // LIMIT
            if (self.limit_value) |limit_val| {
                try std.fmt.format(buf.writer(self.allocator), " LIMIT {d}", .{limit_val});
            }

            // OFFSET
            if (self.offset_value) |offset_val| {
                try std.fmt.format(buf.writer(self.allocator), " OFFSET {d}", .{offset_val});
            }

            return buf.toOwnedSlice(self.allocator);
        }

        /// 执行查询并扫描一条记录
        ///
        /// 执行 SQL 查询,期望返回恰好一行结果。
        /// 使用 field_mapper 自动映射列到结构体字段。
        ///
        /// 返回:
        /// - T: 映射后的结构体实例
        ///
        /// 错误:
        /// - error.NoRows: 结果集为空
        /// - error.TooManyRows: 返回多于一行
        /// - error.QueryFailed: 查询执行失败
        /// - error.TypeMismatch: 类型不匹配
        ///
        /// 示例:
        /// ```zig
        /// const user = try query.where("id = $1", .{1}).scanOne();
        /// ```
        pub fn scanOne(self: *Self) !T {
            const query_str = try self.build();
            defer self.allocator.free(query_str);

            // 收集所有参数
            var all_args = std.ArrayList(QueryArg){};
            defer all_args.deinit(self.allocator);

            for (self.where_clauses.items) |clause| {
                try all_args.appendSlice(self.allocator, clause.args);
            }

            // 执行查询
            var result = try self.db.query(query_str, all_args.items);
            defer result.close();
            defer result.rows.deinit();

            // 使用 result_scanner 扫描单行
            return result_scanner.scanOne(T, &result.rows, self.allocator);
        }

        /// 返回查询结果的行数
        ///
        /// 执行 SELECT COUNT(*) 查询，返回符合条件的记录数量。
        /// 支持 DISTINCT 和列选择，例如:
        /// - COUNT(*): 所有行
        /// - COUNT(column): 指定列的非 NULL 行
        /// - COUNT(DISTINCT column): 去重后的行数
        ///
        /// 返回:
        /// - usize: 记录数量
        ///
        /// 错误:
        /// - error.QueryFailed: 查询执行失败
        /// - error.NoRows: 查询结果为空（不应该发生）
        ///
        /// 示例:
        /// ```zig
        /// const count = try query.where("age > $1", .{18}).count();
        /// ```
        pub fn count(self: *Self) !usize {
            var buf = std.ArrayList(u8){};
            errdefer buf.deinit(self.allocator);

            // SELECT COUNT(
            try buf.appendSlice(self.allocator, "SELECT COUNT(");

            // DISTINCT
            if (self.distinct_value) {
                try buf.appendSlice(self.allocator, "DISTINCT ");
            }

            // 列选择
            if (self.columns.items.len > 0) {
                // 对于 DISTINCT 多列，PostgreSQL 需要使用 (col1, col2) 语法
                if (self.distinct_value and self.columns.items.len > 1) {
                    try buf.appendSlice(self.allocator, "(");
                    for (self.columns.items, 0..) |col, i| {
                        if (i > 0) try buf.appendSlice(self.allocator, ", ");
                        try buf.appendSlice(self.allocator, col);
                    }
                    try buf.appendSlice(self.allocator, ")");
                } else {
                    // 单列或非 DISTINCT
                    try buf.appendSlice(self.allocator, self.columns.items[0]);
                }
            } else {
                try buf.appendSlice(self.allocator, "*");
            }

            try buf.appendSlice(self.allocator, ") FROM ");
            try buf.appendSlice(self.allocator, self.table_name);

            // WHERE 子句
            if (self.where_clauses.items.len > 0) {
                try buf.appendSlice(self.allocator, " WHERE ");
                for (self.where_clauses.items, 0..) |clause, i| {
                    if (i > 0) {
                        switch (clause.operator) {
                            .and_op => try buf.appendSlice(self.allocator, " AND "),
                            .or_op => try buf.appendSlice(self.allocator, " OR "),
                        }
                    }
                    try buf.appendSlice(self.allocator, clause.condition);
                }
            }

            const query_str = try buf.toOwnedSlice(self.allocator);
            defer self.allocator.free(query_str);

            // 收集所有参数
            var all_args = std.ArrayList(QueryArg){};
            defer all_args.deinit(self.allocator);

            for (self.where_clauses.items) |clause| {
                try all_args.appendSlice(self.allocator, clause.args);
            }

            // 执行查询
            var result = try self.db.query(query_str, all_args.items);
            defer result.close();
            defer result.rows.deinit();

            // 获取第一行
            const first_row = try result.rows.next();
            if (first_row == null) return error.NoRows;

            var row = first_row.?;

            // 提取 count 值（第一列）
            const count_value = row.get(i64, 0);
            return @intCast(count_value);
        }

        /// 执行查询并扫描多条记录
        ///
        /// 执行 SQL 查询,返回所有结果行映射到的结构体数组。
        /// 使用 field_mapper 自动映射列到结构体字段。
        ///
        /// 返回:
        /// - []T: 映射后的结构体切片 (调用者负责释放)
        ///
        /// 错误:
        /// - error.QueryFailed: 查询执行失败
        /// - error.TypeMismatch: 类型不匹配
        /// - error.OutOfMemory: 内存不足
        ///
        /// 示例:
        /// ```zig
        /// const users = try query.where("age > $1", .{18}).scan();
        /// defer self.allocator.free(users);
        /// ```
        pub fn scan(self: *Self) ![]T {
            const query_str = try self.build();
            defer self.allocator.free(query_str);

            // 收集所有参数
            var all_args = std.ArrayList(QueryArg){};
            defer all_args.deinit(self.allocator);

            for (self.where_clauses.items) |clause| {
                try all_args.appendSlice(self.allocator, clause.args);
            }

            // 执行查询
            var result = try self.db.query(query_str, all_args.items);
            defer result.close();
            defer result.rows.deinit();

            // 使用 ArrayList 收集结果
            var results = std.ArrayList(T){};
            errdefer results.deinit(self.allocator);

            // 使用 result_scanner 扫描所有行
            try result_scanner.scanAll(T, &result.rows, self.allocator, &results);

            return results.toOwnedSlice(self.allocator);
        }
    };
}

/// 辅助函数: 将 anytype 参数转换为 []const QueryArg
fn allocArgs(allocator: Allocator, args: anytype) ![]const QueryArg {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);

    if (args_type_info != .@"struct") {
        @compileError("args must be a tuple");
    }

    const fields = args_type_info.@"struct".fields;
    var result = try allocator.alloc(QueryArg, fields.len);
    errdefer allocator.free(result);

    inline for (fields, 0..) |field, i| {
        const value = @field(args, field.name);
        result[i] = QueryArg.fromValue(value);
    }

    return result;
}

/// 替换 SQL 字符串中的占位符 (? -> $N)
///
/// 将通用占位符 "?" 替换为 PostgreSQL 的位置参数格式 "$N"
///
/// ## 参数
/// - allocator: 内存分配器
/// - sql: 原始 SQL 字符串
/// - start_index: 起始参数索引（会被更新）
///
/// ## 返回
/// 替换后的 SQL 字符串，调用者负责释放内存
/// 替换 SQL 字符串中的占位符 (? -> $N)
///
/// 将通用占位符 "?" 替换为 PostgreSQL 的位置参数格式 "$N"
///
/// ## 参数
/// - allocator: 内存分配器
/// - sql: 原始 SQL 字符串
/// - start_index: 起始参数索引
///
/// ## 返回
/// 替换后的 SQL 字符串，调用者负责释放内存
fn replacePlaceholders(allocator: Allocator, sql: []const u8, start_index: usize) ![]const u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    var current_index = start_index;

    while (i < sql.len) : (i += 1) {
        if (sql[i] == '?') {
            // 替换 ? 为 $N
            const placeholder = try std.fmt.allocPrint(allocator, "${d}", .{current_index});
            defer allocator.free(placeholder);
            try result.appendSlice(allocator, placeholder);
            current_index += 1;
        } else {
            try result.append(allocator, sql[i]);
        }
    }

    return result.toOwnedSlice(allocator);
}

/// INSERT 查询构建器
///
/// ## 参数
/// - T: 模型类型
/// - dialect: 数据库方言 (编译时确定)
///
/// ## 示例
/// ```zig
/// var query = try db.newInsert(User);
/// defer query.deinit();
///
/// // 单行插入
/// try query.value(.{ .name = "Alice", .email = "alice@example.com" });
///
/// // PostgreSQL: 使用 RETURNING
/// try query.returning(&.{"id", "created_at"});
///
/// const sql = try query.build();
/// ```
pub fn InsertQuery(comptime T: type, comptime dialect: Dialect) type {
    const DBType = db_mod.DB(dialect);

    return struct {
        const Self = @This();

        allocator: Allocator,
        db: *DBType,
        table_name: []const u8,
        columns: std.ArrayList([]const u8),
        values_list: std.ArrayList([]const QueryArg),
        returning_columns: ?[]const []const u8,
        on_conflict: ?OnConflictClause,
        on_duplicate_key: ?OnDuplicateKeyUpdate,

        /// 初始化插入查询构建器
        pub fn init(allocator: Allocator, db: *DBType, table_name: []const u8) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.* = .{
                .allocator = allocator,
                .db = db,
                .table_name = table_name,
                .columns = .{},
                .values_list = .{},
                .returning_columns = null,
                .on_conflict = null,
                .on_duplicate_key = null,
            };

            return self;
        }

        /// 释放资源
        pub fn deinit(self: *Self) void {
            self.columns.deinit(self.allocator);

            // 释放所有 values 数组
            for (self.values_list.items) |row_values| {
                self.allocator.free(row_values);
            }
            self.values_list.deinit(self.allocator);

            self.allocator.destroy(self);
        }

        /// 插入单行数据
        ///
        /// ## 参数
        /// - row: 包含列名和值的结构体 (必须是匿名结构体)
        ///
        /// ## 示例
        /// ```zig
        /// try query.value(.{
        ///     .name = "Alice",
        ///     .email = "alice@example.com",
        ///     .age = 25,
        /// });
        /// ```
        pub fn value(self: *Self, row: anytype) !*Self {
            const RowType = @TypeOf(row);
            const row_type_info = @typeInfo(RowType);

            if (row_type_info != .@"struct") {
                @compileError("value() requires a struct");
            }

            const fields = row_type_info.@"struct".fields;

            // 第一次调用时，初始化列名
            if (self.columns.items.len == 0) {
                inline for (fields) |field| {
                    try self.columns.append(self.allocator, field.name);
                }
            }

            // 转换值为 QueryArg
            var row_values = try self.allocator.alloc(QueryArg, fields.len);
            errdefer self.allocator.free(row_values);

            inline for (fields, 0..) |field, i| {
                const field_value = @field(row, field.name);
                row_values[i] = QueryArg.fromValue(field_value);
            }

            try self.values_list.append(self.allocator, row_values);
            return self;
        }

        /// 批量插入多行数据
        ///
        /// ## 参数
        /// - rows: 结构体切片
        ///
        /// ## 示例
        /// ```zig
        /// const users = [_]User{
        ///     .{ .name = "Alice", .email = "alice@example.com" },
        ///     .{ .name = "Bob", .email = "bob@example.com" },
        /// };
        /// try query.values(&users);
        /// ```
        pub fn values(self: *Self, rows: anytype) !*Self {
            const RowsType = @TypeOf(rows);
            const rows_type_info = @typeInfo(RowsType);

            // 确保是切片或数组指针 - 使用编译时常量避免运行时评估
            const is_valid = comptime blk: {
                if (rows_type_info != .pointer) break :blk false;
                // 接受切片或数组指针
                if (rows_type_info.pointer.size == .slice) break :blk true;
                if (rows_type_info.pointer.size == .one) {
                    // 检查指向的是否是数组
                    const child_info = @typeInfo(rows_type_info.pointer.child);
                    break :blk child_info == .array;
                }
                break :blk false;
            };
            if (!is_valid) {
                @compileError("values() requires a slice or array pointer");
            }

            // AC1.5.1: 批量大小限制
            const MAX_BATCH_SIZE = 1000; // 保守值,适用于大多数场景
            if (rows.len > MAX_BATCH_SIZE) {
                return error.BatchSizeTooLarge;
            }

            // 计算总参数数量,检查 PostgreSQL 参数限制
            const first_row_type_info = @typeInfo(@TypeOf(rows[0]));
            const column_count = first_row_type_info.@"struct".fields.len;
            const total_params = rows.len * column_count;

            // PostgreSQL 最大参数限制: 65535
            if (total_params > 65535) {
                return error.ExceedsPostgreSQLParamLimit;
            }

            // AC1.5.1: 内存优化 - 预分配容量
            try self.values_list.ensureTotalCapacity(
                self.allocator,
                self.values_list.items.len + rows.len,
            );

            // 遍历每一行
            for (rows) |row| {
                _ = try self.value(row);
            }

            return self;
        }

        /// 添加 RETURNING 子句 (仅 PostgreSQL 和 SQLite 支持)
        ///
        /// ## 参数
        /// - cols: 要返回的列名数组
        ///
        /// ## 示例
        /// ```zig
        /// try query.returning(&.{"id", "created_at"});
        /// ```
        pub fn returning(self: *Self, cols: []const []const u8) !*Self {
            // 编译时检查方言是否支持 RETURNING
            if (comptime !dialect.supportsReturning()) {
                @compileError("RETURNING is not supported by " ++ @tagName(dialect));
            }

            self.returning_columns = cols;
            return self;
        }

        /// 添加 ON CONFLICT 子句 (仅 PostgreSQL 和 SQLite 支持)
        ///
        /// ## 参数
        /// - clause: ON CONFLICT 子句配置
        ///
        /// ## 示例
        /// ```zig
        /// try query.onConflict(.{
        ///     .columns = &.{"email"},
        ///     .action = .do_update,
        ///     .update_columns = &.{"name", "updated_at"},
        /// });
        /// ```
        pub fn onConflict(self: *Self, clause: OnConflictClause) !*Self {
            // 编译时检查方言是否支持 ON CONFLICT
            if (comptime !dialect.supportsOnConflict()) {
                @compileError("ON CONFLICT is not supported by " ++ @tagName(dialect));
            }

            self.on_conflict = clause;
            return self;
        }

        /// 添加 ON DUPLICATE KEY UPDATE 子句 (仅 MySQL 支持)
        ///
        /// ## 参数
        /// - update: ON DUPLICATE KEY UPDATE 配置
        ///
        /// ## 示例
        /// ```zig
        /// try query.onDuplicateKeyUpdate(.{
        ///     .columns = &.{"name", "email"},
        /// });
        /// ```
        pub fn onDuplicateKeyUpdate(self: *Self, update: OnDuplicateKeyUpdate) !*Self {
            // 编译时检查方言
            if (comptime dialect != .mysql) {
                @compileError("ON DUPLICATE KEY UPDATE is MySQL-specific");
            }

            self.on_duplicate_key = update;
            return self;
        }

        /// 构建 INSERT SQL 语句
        /// 估算 SQL 语句大小
        fn estimateSQLSize(self: *Self) usize {
            const base_size = 100; // INSERT INTO table_name ...
            const cols_size = self.columns.items.len * 20; // 列名平均长度
            const row_size = self.columns.items.len * 5; // 每个占位符 "$123, "
            const total_rows = self.values_list.items.len;
            return base_size + cols_size + (row_size * total_rows);
        }

        pub fn build(self: *Self) ![]const u8 {
            if (self.columns.items.len == 0 or self.values_list.items.len == 0) {
                return error.NoValuesToInsert;
            }

            // AC1.5.2: 内存优化 - 预估并预分配 SQL 缓冲区
            const estimated_size = self.estimateSQLSize();
            var buf = std.ArrayList(u8){};
            errdefer buf.deinit(self.allocator);
            try buf.ensureTotalCapacity(self.allocator, estimated_size);

            // INSERT INTO table (columns)
            try buf.appendSlice(self.allocator, "INSERT INTO ");
            try buf.appendSlice(self.allocator, self.table_name);
            try buf.appendSlice(self.allocator, " (");

            for (self.columns.items, 0..) |col, i| {
                if (i > 0) try buf.appendSlice(self.allocator, ", ");
                try buf.appendSlice(self.allocator, col);
            }

            try buf.appendSlice(self.allocator, ") VALUES ");

            // AC1.5.2: 多行 VALUES (...), (...), (...)
            var param_index: usize = 1;
            for (self.values_list.items, 0..) |_, row_idx| {
                if (row_idx > 0) try buf.appendSlice(self.allocator, ", ");
                try buf.appendSlice(self.allocator, "(");

                for (self.columns.items, 0..) |_, col_idx| {
                    if (col_idx > 0) try buf.appendSlice(self.allocator, ", ");

                    // 生成占位符 - 根据方言生成不同格式
                    switch (dialect) {
                        .postgresql => try std.fmt.format(buf.writer(self.allocator), "${d}", .{param_index}),
                        .mysql, .sqlite => try buf.appendSlice(self.allocator, "?"),
                    }
                    param_index += 1;
                }

                try buf.appendSlice(self.allocator, ")");
            }

            // ON CONFLICT (PostgreSQL/SQLite)
            if (self.on_conflict) |conflict| {
                try buf.appendSlice(self.allocator, " ON CONFLICT");

                if (conflict.columns) |cols| {
                    try buf.appendSlice(self.allocator, " (");
                    for (cols, 0..) |col, i| {
                        if (i > 0) try buf.appendSlice(self.allocator, ", ");
                        try buf.appendSlice(self.allocator, col);
                    }
                    try buf.appendSlice(self.allocator, ")");
                }

                try buf.appendSlice(self.allocator, " ");
                try buf.appendSlice(self.allocator, conflict.action.toSQL());

                if (conflict.action == .do_update) {
                    if (conflict.update_columns) |update_cols| {
                        try buf.appendSlice(self.allocator, " SET ");
                        for (update_cols, 0..) |col, i| {
                            if (i > 0) try buf.appendSlice(self.allocator, ", ");
                            try buf.appendSlice(self.allocator, col);
                            try buf.appendSlice(self.allocator, " = EXCLUDED.");
                            try buf.appendSlice(self.allocator, col);
                        }
                    }
                }
            }

            // ON DUPLICATE KEY UPDATE (MySQL)
            if (self.on_duplicate_key) |dup_key| {
                try buf.appendSlice(self.allocator, " ON DUPLICATE KEY UPDATE ");
                for (dup_key.columns, 0..) |col, i| {
                    if (i > 0) try buf.appendSlice(self.allocator, ", ");
                    try buf.appendSlice(self.allocator, col);
                    try buf.appendSlice(self.allocator, " = VALUES(");
                    try buf.appendSlice(self.allocator, col);
                    try buf.appendSlice(self.allocator, ")");
                }
            }

            // AC1.5.3: RETURNING 子句支持批量返回
            if (self.returning_columns) |ret_cols| {
                try buf.appendSlice(self.allocator, " RETURNING ");
                for (ret_cols, 0..) |col, i| {
                    if (i > 0) try buf.appendSlice(self.allocator, ", ");
                    try buf.appendSlice(self.allocator, col);
                }
            }

            return buf.toOwnedSlice(self.allocator);
        }

        /// 执行插入查询
        pub fn exec(self: *Self) !InsertResult {
            const query_str = try self.build();
            defer self.allocator.free(query_str);

            // 收集所有参数
            var all_args = std.ArrayList(QueryArg){};
            defer all_args.deinit(self.allocator);

            for (self.values_list.items) |row_values| {
                try all_args.appendSlice(self.allocator, row_values);
            }

            // 执行查询
            try self.db.exec(query_str, all_args.items);

            // 返回结果
            // 注意: PostgreSQL 的 last_insert_id 需要通过 RETURNING 获取
            return InsertResult{
                .rows_affected = self.values_list.items.len,
                .last_insert_id = null,
            };
        }

        /// 执行插入并返回插入的数据 (仅 PostgreSQL/SQLite 支持 RETURNING)
        ///
        /// ## 参数
        /// - dest: 目标 ArrayList,用于存储返回的数据
        ///
        /// ## 示例
        /// ```zig
        /// var inserted_users = std.ArrayList(User){};
        /// defer inserted_users.deinit(allocator);
        ///
        /// try query
        ///     .value(.{ .name = "Alice", .email = "alice@example.com" })
        ///     .returning(&.{"*"})
        ///     .execReturning(&inserted_users);
        ///
        /// std.debug.print("插入的用户 ID: {}\n", .{inserted_users.items[0].id});
        /// ```
        pub fn execReturning(self: *Self, dest: *std.ArrayList(T)) !void {
            // 编译时检查方言是否支持 RETURNING
            if (comptime !dialect.supportsReturning()) {
                @compileError("RETURNING is not supported by " ++ @tagName(dialect));
            }

            if (self.returning_columns == null) {
                return error.NoReturningColumns;
            }

            const query_str = try self.build();
            defer self.allocator.free(query_str);

            // 收集所有参数
            var all_args = std.ArrayList(QueryArg){};
            defer all_args.deinit(self.allocator);

            for (self.values_list.items) |row_values| {
                try all_args.appendSlice(self.allocator, row_values);
            }

            // 执行查询并获取结果
            const result = try self.db.query(query_str, all_args.items);
            defer result.close();

            // 扫描结果到目标 ArrayList
            try self.db.scanRows(T, &result.rows, dest);
        }
    };
}

/// UPDATE 查询构建器
///
/// ## 参数
/// - T: 模型类型
/// - dialect: 数据库方言 (编译时确定)
///
/// ## 示例
/// ```zig
/// var query = try db.newUpdate(User);
/// defer query.deinit();
///
/// try query.set("name", "new_name")
///          .set("email", "new_email@example.com")
///          .where("id = $1", .{1});
///
/// const sql = try query.build();
/// ```
pub fn UpdateQuery(comptime T: type, comptime dialect: Dialect) type {
    const DBType = db_mod.DB(dialect);

    return struct {
        const Self = @This();

        /// SET子句：包含表达式和参数
        const SetClause = struct {
            assignment: []const u8, // SQL 表达式，如 "age = age + 1" 或 "name = $1"
            args: []const QueryArg,
        };

        allocator: Allocator,
        db: *DBType,
        table_name: []const u8,
        set_clauses: std.ArrayList(SetClause),
        where_clauses: std.ArrayList(WhereClause),
        returning_columns: ?[]const []const u8,

        /// 初始化更新查询构建器
        pub fn init(allocator: Allocator, db: *DBType, table_name: []const u8) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.* = .{
                .allocator = allocator,
                .db = db,
                .table_name = table_name,
                .set_clauses = .{},
                .where_clauses = .{},
                .returning_columns = null,
            };

            return self;
        }

        /// 释放资源
        pub fn deinit(self: *Self) void {
            // 释放 SET 子句参数
            for (self.set_clauses.items) |clause| {
                self.allocator.free(clause.args);
            }
            self.set_clauses.deinit(self.allocator);

            // 释放 WHERE 子句参数
            for (self.where_clauses.items) |clause| {
                self.allocator.free(clause.args);
            }
            self.where_clauses.deinit(self.allocator);

            self.allocator.destroy(self);
        }

        /// 设置要更新的字段（支持字符串表达式）
        ///
        /// 支持 SQL 表达式，如算术运算、函数调用等
        ///
        /// ## 参数
        /// - assignments: SET 表达式字符串，如 "age = age + 1, updated_at = $1"
        /// - args: 绑定参数元组
        ///
        /// ## 示例
        /// ```zig
        /// // 简单赋值
        /// try query.set("name = $1", .{"Alice"});
        ///
        /// // 多列更新
        /// try query.set("age = age + 1, updated_at = $1", .{std.time.timestamp()});
        ///
        /// // 表达式更新
        /// try query.set("score = score * 2, level = $1", .{5});
        /// ```
        pub fn set(self: *Self, assignments: []const u8, args: anytype) !*Self {
            const args_slice = try allocArgs(self.allocator, args);
            const clause = SetClause{
                .assignment = assignments,
                .args = args_slice,
            };
            try self.set_clauses.append(self.allocator, clause);
            return self;
        }

        /// 添加 WHERE 条件 (AND)
        ///
        /// ## 参数
        /// - condition: WHERE 条件表达式
        /// - args: 绑定参数元组
        ///
        /// ## 示例
        /// ```zig
        /// try query.where("email = $1", .{"alice@example.com"});
        /// try query.where("age > $1", .{18});
        /// ```
        pub fn where(self: *Self, condition: []const u8, args: anytype) !*Self {
            const args_slice = try allocArgs(self.allocator, args);
            const clause = WhereClause{
                .condition = condition,
                .args = args_slice,
                .operator = .and_op,
            };
            try self.where_clauses.append(self.allocator, clause);
            return self;
        }

        /// 添加 WHERE 条件 (OR)
        ///
        /// ## 参数
        /// - condition: WHERE 条件表达式
        /// - args: 绑定参数元组
        ///
        /// ## 示例
        /// ```zig
        /// try query.whereOr("status = $1", .{"active"});
        /// ```
        pub fn whereOr(self: *Self, condition: []const u8, args: anytype) !*Self {
            const args_slice = try allocArgs(self.allocator, args);
            const clause = WhereClause{
                .condition = condition,
                .args = args_slice,
                .operator = .or_op,
            };
            try self.where_clauses.append(self.allocator, clause);
            return self;
        }

        /// 设置 RETURNING 子句 (仅 PostgreSQL 和 SQLite 支持)
        ///
        /// ## 参数
        /// - cols: 要返回的列名数组
        ///
        /// ## 示例
        /// ```zig
        /// try query.setReturning(&.{"id", "updated_at"});
        /// ```
        /// 添加 WHERE IN 条件 (批量匹配)
        ///
        /// 生成 WHERE column IN ($1, $2, $3, ...) 子句
        ///
        /// ## 参数
        /// - column: 列名
        /// - values: 值数组或切片
        ///
        /// ## 示例
        /// ```zig
        /// const user_ids = [_]i64{ 1, 2, 3, 5, 8 };
        /// try query.whereIn("id", &user_ids);
        /// // 生成: WHERE id IN ($1, $2, $3, $4, $5)
        /// ```
        pub fn whereIn(self: *Self, column: []const u8, values: anytype) !*Self {
            const ValuesType = @TypeOf(values);
            const type_info = @typeInfo(ValuesType);

            // 支持切片和数组
            const values_slice = switch (type_info) {
                .pointer => |ptr| if (ptr.size == .slice or ptr.size == .one) values else @compileError("whereIn requires a slice or array pointer"),
                else => @compileError("whereIn requires a slice or array"),
            };

            // 检查是否为空
            if (values_slice.len == 0) {
                return error.EmptyWhereIn;
            }

            // 构建 IN 子句: column IN ($1, $2, $3)
            var condition_buf = std.ArrayList(u8){};
            defer condition_buf.deinit(self.allocator);

            try condition_buf.appendSlice(self.allocator, column);
            try condition_buf.appendSlice(self.allocator, " IN (");

            // 生成占位符
            for (values_slice, 0..) |_, i| {
                if (i > 0) try condition_buf.appendSlice(self.allocator, ", ");
                try condition_buf.appendSlice(self.allocator, "?"); // 占位符将在 build() 时替换
            }
            try condition_buf.appendSlice(self.allocator, ")");

            // 分配参数数组
            const args_slice = try self.allocator.alloc(QueryArg, values_slice.len);
            errdefer self.allocator.free(args_slice);

            // 转换值为 QueryArg
            for (values_slice, 0..) |value, i| {
                args_slice[i] = QueryArg.fromValue(value);
            }

            const clause = WhereClause{
                .condition = try condition_buf.toOwnedSlice(self.allocator),
                .args = args_slice,
                .operator = .and_op,
            };
            try self.where_clauses.append(self.allocator, clause);

            return self;
        }

        /// 添加 WHERE NOT IN 条件 (批量排除)
        ///
        /// 生成 WHERE column NOT IN ($1, $2, $3, ...) 子句
        ///
        /// ## 参数
        /// - column: 列名
        /// - values: 值数组或切片
        ///
        /// ## 示例
        /// ```zig
        /// const banned_ids = [_]i64{ 99, 100 };
        /// try query.whereNotIn("id", &banned_ids);
        /// // 生成: WHERE id NOT IN ($1, $2)
        /// ```
        pub fn whereNotIn(self: *Self, column: []const u8, values: anytype) !*Self {
            const ValuesType = @TypeOf(values);
            const type_info = @typeInfo(ValuesType);

            // 支持切片和数组
            const values_slice = switch (type_info) {
                .pointer => |ptr| if (ptr.size == .slice or ptr.size == .one) values else @compileError("whereNotIn requires a slice or array pointer"),
                else => @compileError("whereNotIn requires a slice or array"),
            };

            // 检查是否为空
            if (values_slice.len == 0) {
                return error.EmptyWhereIn;
            }

            // 构建 NOT IN 子句: column NOT IN ($1, $2, $3)
            var condition_buf = std.ArrayList(u8){};
            defer condition_buf.deinit(self.allocator);

            try condition_buf.appendSlice(self.allocator, column);
            try condition_buf.appendSlice(self.allocator, " NOT IN (");

            // 生成占位符
            for (values_slice, 0..) |_, i| {
                if (i > 0) try condition_buf.appendSlice(self.allocator, ", ");
                try condition_buf.appendSlice(self.allocator, "?"); // 占位符将在 build() 时替换
            }
            try condition_buf.appendSlice(self.allocator, ")");

            // 分配参数数组
            const args_slice = try self.allocator.alloc(QueryArg, values_slice.len);
            errdefer self.allocator.free(args_slice);

            // 转换值为 QueryArg
            for (values_slice, 0..) |value, i| {
                args_slice[i] = QueryArg.fromValue(value);
            }

            const clause = WhereClause{
                .condition = try condition_buf.toOwnedSlice(self.allocator),
                .args = args_slice,
                .operator = .and_op,
            };
            try self.where_clauses.append(self.allocator, clause);

            return self;
        }

        /// 添加子查询作为 WHERE IN 条件
        ///
        /// 支持使用另一个 SELECT 查询作为 IN 子句的值源
        ///
        /// ## 参数
        /// - column: 列名
        /// - subquery: 子查询 (SelectQuery)
        ///
        /// ## 示例
        /// ```zig
        /// var subquery = try db.newSelect(Post);
        /// defer subquery.deinit();
        /// try subquery.column("DISTINCT user_id")
        ///     .where("published = ?", .{true});
        ///
        /// var update = try db.newUpdate(User);
        /// defer update.deinit();
        /// try update.set("verified = ?", .{true})
        ///     .whereInSubquery("id", subquery);
        /// // 生成: WHERE id IN (SELECT DISTINCT user_id FROM posts WHERE published = $1)
        /// ```
        pub fn whereInSubquery(self: *Self, column: []const u8, subquery: anytype) !*Self {
            // 构建子查询 SQL
            const subquery_sql = try subquery.build();
            defer self.allocator.free(subquery_sql);

            // 构建 IN 子句: column IN (subquery)
            var condition_buf = std.ArrayList(u8){};
            defer condition_buf.deinit(self.allocator);

            try condition_buf.appendSlice(self.allocator, column);
            try condition_buf.appendSlice(self.allocator, " IN (");
            try condition_buf.appendSlice(self.allocator, subquery_sql);
            try condition_buf.appendSlice(self.allocator, ")");

            // 收集子查询的参数
            var subquery_args = std.ArrayList(QueryArg){};
            defer subquery_args.deinit(self.allocator);

            // 从子查询的 where_clauses 中收集参数
            for (subquery.where_clauses.items) |clause| {
                try subquery_args.appendSlice(self.allocator, clause.args);
            }

            const clause = WhereClause{
                .condition = try condition_buf.toOwnedSlice(self.allocator),
                .args = try subquery_args.toOwnedSlice(self.allocator),
                .operator = .and_op,
            };
            try self.where_clauses.append(self.allocator, clause);

            return self;
        }

        pub fn setReturning(self: *Self, cols: []const []const u8) *Self {
            // 编译时检查方言是否支持 RETURNING
            if (comptime !dialect.supportsReturning()) {
                @compileError("RETURNING is not supported by " ++ @tagName(dialect));
            }

            self.returning_columns = cols;
            return self;
        }

        /// 构建 UPDATE SQL 语句
        ///
        /// 生成完整的 UPDATE SQL，包括占位符替换
        ///
        /// ## 返回
        /// 返回构建的 SQL 字符串，调用者负责释放内存
        ///
        /// ## 错误
        /// - NoColumnsToUpdate: 没有设置任何要更新的列
        /// 构建 UPDATE SQL 语句
        ///
        /// 生成完整的 UPDATE SQL，包括占位符替换
        ///
        /// ## 返回
        /// 返回构建的 SQL 字符串，调用者负责释放内存
        ///
        /// ## 错误
        /// - NoColumnsToUpdate: 没有设置任何要更新的列
        /// 构建 UPDATE SQL 语句
        ///
        /// 生成完整的 UPDATE SQL，包括占位符替换
        ///
        /// ## 返回
        /// 返回构建的 SQL 字符串，调用者负责释放内存
        ///
        /// ## 错误
        /// - NoColumnsToUpdate: 没有设置任何要更新的列
        pub fn build(self: *Self) ![]const u8 {
            if (self.set_clauses.items.len == 0) {
                return error.NoColumnsToUpdate;
            }

            var buf = std.ArrayList(u8){};
            errdefer buf.deinit(self.allocator);

            // UPDATE table
            try buf.appendSlice(self.allocator, "UPDATE ");
            try buf.appendSlice(self.allocator, self.table_name);

            // SET column = value
            try buf.appendSlice(self.allocator, " SET ");

            // 计算 SET 子句的参数数量（用于占位符编号）
            var param_index: usize = 1;

            for (self.set_clauses.items, 0..) |set_clause, i| {
                if (i > 0) try buf.appendSlice(self.allocator, ", ");

                // 替换 SET 子句中的占位符 (? -> $N)
                const replaced_assignment = try replacePlaceholders(
                    self.allocator,
                    set_clause.assignment,
                    param_index,
                );
                defer self.allocator.free(replaced_assignment);
                try buf.appendSlice(self.allocator, replaced_assignment);

                // 根据实际参数数量增加索引
                param_index += set_clause.args.len;
            }

            // WHERE
            if (self.where_clauses.items.len > 0) {
                try buf.appendSlice(self.allocator, " WHERE ");
                for (self.where_clauses.items, 0..) |clause, i| {
                    if (i > 0) {
                        try buf.appendSlice(self.allocator, " ");
                        try buf.appendSlice(self.allocator, clause.operator.toSQL());
                        try buf.appendSlice(self.allocator, " ");
                    }

                    // 替换 WHERE 子句中的占位符 (? -> $N)
                    const replaced_condition = try replacePlaceholders(
                        self.allocator,
                        clause.condition,
                        param_index,
                    );
                    defer self.allocator.free(replaced_condition);
                    try buf.appendSlice(self.allocator, replaced_condition);

                    // 根据实际参数数量增加索引
                    param_index += clause.args.len;
                }
            }

            // RETURNING (PostgreSQL/SQLite)
            if (self.returning_columns) |ret_cols| {
                try buf.appendSlice(self.allocator, " RETURNING ");
                for (ret_cols, 0..) |col, i| {
                    if (i > 0) try buf.appendSlice(self.allocator, ", ");
                    try buf.appendSlice(self.allocator, col);
                }
            }

            return buf.toOwnedSlice(self.allocator);
        }

        /// 执行更新查询，返回受影响的行数
        ///
        /// ## 返回
        /// 返回 UpdateResult，包含 rows_affected
        ///
        /// ## 错误
        /// - NoColumnsToUpdate: 没有设置任何要更新的列
        /// - 数据库执行错误
        ///
        /// ## 示例
        /// ```zig
        /// const result = try query.exec();
        /// std.debug.print("更新了 {} 行\n", .{result.rows_affected});
        /// ```
        pub fn exec(self: *Self) !UpdateResult {
            const query_str = try self.build();
            defer self.allocator.free(query_str);

            // 收集所有参数 (SET + WHERE)
            var all_args = std.ArrayList(QueryArg){};
            defer all_args.deinit(self.allocator);

            // 先添加 SET 参数
            for (self.set_clauses.items) |set_clause| {
                try all_args.appendSlice(self.allocator, set_clause.args);
            }

            // 再添加 WHERE 参数
            for (self.where_clauses.items) |clause| {
                try all_args.appendSlice(self.allocator, clause.args);
            }

            // 执行查询
            try self.db.exec(query_str, all_args.items);

            // TODO: 从数据库驱动获取实际的 rows_affected
            // 目前返回 0，待驱动实现后更新
            return UpdateResult{
                .rows_affected = 0,
            };
        }

        /// 执行更新查询并返回更新后的数据（需要 RETURNING 支持）
        ///
        /// ## 参数
        /// - dest: 目标 ArrayList，用于存储更新后的数据
        ///
        /// ## 错误
        /// - NoColumnsToUpdate: 没有设置任何要更新的列
        /// - 数据库执行错误
        ///
        /// ## 示例
        /// ```zig
        /// var updated_users = std.ArrayList(User){};
        /// defer updated_users.deinit(allocator);
        ///
        /// try query.setReturning(&.{"*"}).execReturning(&updated_users);
        /// for (updated_users.items) |user| {
        ///     std.debug.print("Updated: {s}\n", .{user.name});
        /// }
        /// ```
        pub fn execReturning(self: *Self, dest: *std.ArrayList(T)) !void {
            // 编译时检查方言是否支持 RETURNING
            if (comptime !dialect.supportsReturning()) {
                @compileError("RETURNING is not supported by " ++ @tagName(dialect));
            }

            const query_str = try self.build();
            defer self.allocator.free(query_str);

            // 收集所有参数 (SET + WHERE)
            var all_args = std.ArrayList(QueryArg){};
            defer all_args.deinit(self.allocator);

            // 先添加 SET 参数
            for (self.set_clauses.items) |set_clause| {
                try all_args.appendSlice(self.allocator, set_clause.args);
            }

            // 再添加 WHERE 参数
            for (self.where_clauses.items) |clause| {
                try all_args.appendSlice(self.allocator, clause.args);
            }

            // 执行查询并获取结果
            const result = try self.db.query(query_str, all_args.items);
            defer result.close();

            // 扫描结果到目标 ArrayList
            try self.db.scanRows(T, &result.rows, dest);
        }
    };
}

/// DELETE 查询构建器
///
/// ## 参数
/// - T: 模型类型
/// - dialect: 数据库方言 (编译时确定)
///
/// ## 示例
/// ```zig
/// var query = try db.newDelete(User);
/// defer query.deinit();
///
/// try query.where("age < $1", .{18})
///          .where("email IS NULL", .{});
///
/// const sql = try query.build();
/// ```
pub fn DeleteQuery(comptime T: type, comptime dialect: Dialect) type {
    _ = T; // TODO: 使用类型参数进行反射
    const DBType = db_mod.DB(dialect);

    return struct {
        const Self = @This();

        allocator: Allocator,
        db: *DBType,
        table_name: []const u8,
        where_clauses: std.ArrayList(WhereClause),
        returning_columns: ?[]const []const u8,

        /// 初始化删除查询构建器
        pub fn init(allocator: Allocator, db: *DBType, table_name: []const u8) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.* = .{
                .allocator = allocator,
                .db = db,
                .table_name = table_name,
                .where_clauses = .{},
                .returning_columns = null,
            };

            return self;
        }

        /// 释放资源
        pub fn deinit(self: *Self) void {
            // 释放 WHERE 子句参数
            for (self.where_clauses.items) |clause| {
                self.allocator.free(clause.args);
            }
            self.where_clauses.deinit(self.allocator);

            self.allocator.destroy(self);
        }

        /// 添加 WHERE 条件 (AND)
        pub fn where(self: *Self, condition: []const u8, args: anytype) !*Self {
            const args_slice = try allocArgs(self.allocator, args);
            const clause = WhereClause{
                .condition = condition,
                .args = args_slice,
                .operator = .and_op,
            };
            try self.where_clauses.append(self.allocator, clause);
            return self;
        }

        /// 添加 WHERE 条件 (OR)
        pub fn whereOr(self: *Self, condition: []const u8, args: anytype) !*Self {
            const args_slice = try allocArgs(self.allocator, args);
            const clause = WhereClause{
                .condition = condition,
                .args = args_slice,
                .operator = .or_op,
            };
            try self.where_clauses.append(self.allocator, clause);
            return self;
        }

        /// 添加 RETURNING 子句 (仅 PostgreSQL 和 SQLite 支持)
        ///
        /// ## 参数
        /// - cols: 要返回的列名数组
        ///
        /// ## 示例
        /// ```zig
        /// try query.returning(&.{"id", "name"});
        /// ```
        pub fn returning(self: *Self, cols: []const []const u8) !*Self {
            // 编译时检查方言是否支持 RETURNING
            if (comptime !dialect.supportsReturning()) {
                @compileError("RETURNING is not supported by " ++ @tagName(dialect));
            }

            self.returning_columns = cols;
            return self;
        }

        /// 构建 DELETE SQL 语句
        pub fn build(self: *Self) ![]const u8 {
            var buf = std.ArrayList(u8){};
            errdefer buf.deinit(self.allocator);

            // DELETE FROM table
            try buf.appendSlice(self.allocator, "DELETE FROM ");
            try buf.appendSlice(self.allocator, self.table_name);

            // WHERE
            if (self.where_clauses.items.len > 0) {
                try buf.appendSlice(self.allocator, " WHERE ");
                for (self.where_clauses.items, 0..) |clause, i| {
                    if (i > 0) {
                        try buf.appendSlice(self.allocator, " ");
                        try buf.appendSlice(self.allocator, clause.operator.toSQL());
                        try buf.appendSlice(self.allocator, " ");
                    }
                    try buf.appendSlice(self.allocator, clause.condition);
                }
            }

            // RETURNING (PostgreSQL/SQLite)
            if (self.returning_columns) |ret_cols| {
                try buf.appendSlice(self.allocator, " RETURNING ");
                for (ret_cols, 0..) |col, i| {
                    if (i > 0) try buf.appendSlice(self.allocator, ", ");
                    try buf.appendSlice(self.allocator, col);
                }
            }

            return buf.toOwnedSlice(self.allocator);
        }

        /// 执行删除查询
        pub fn exec(self: *Self) !void {
            const query_str = try self.build();
            defer self.allocator.free(query_str);

            // 收集所有参数
            var all_args = std.ArrayList(QueryArg){};
            defer all_args.deinit(self.allocator);

            for (self.where_clauses.items) |clause| {
                try all_args.appendSlice(self.allocator, clause.args);
            }

            // 执行查询
            const result = try self.db.exec(query_str, all_args.items);
            defer result.close();
        }
    };
}

// =============================================================================
// CREATE TABLE Query
// =============================================================================

/// CREATE TABLE 查询构建器
///
/// 提供声明式 API 构建和执行 CREATE TABLE DDL 语句。
/// 封装 Table 结构，提供链式 API 和数据库方言支持。
///
/// ## 参数
/// - dialect: 数据库方言 (编译时确定)
///
/// ## 示例
/// ```zig
/// var query = try db.newCreateTable("users");
/// defer query.deinit();
///
/// try query.ifNotExists()
///     .column(Column.init("id", .bigint).setPrimaryKey().setAutoIncrement())
///     .column(Column.init("name", .varchar).setNotNull())
///     .column(Column.init("email", .varchar).setUnique())
///     .exec();
/// ```
pub fn CreateTableQuery(comptime T: type, comptime dialect: Dialect) type {
    const DBType = db_mod.DB(dialect);
    const schema_mod = @import("../schema/table.zig");
    const reflection = @import("../schema/reflection.zig");

    return struct {
        const Self = @This();

        allocator: Allocator,
        db: *DBType,
        table: schema_mod.Table,
        if_not_exists_flag: bool = false,

        /// 初始化 CREATE TABLE 查询构建器
        ///
        /// 自动从模型类型 T 生成表结构：
        /// - 从 T.table_name 或类型名推断表名
        /// - 从 struct 字段自动生成列定义
        /// - 支持后续手动添加额外列
        pub fn init(allocator: Allocator, db: *DBType) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            // 获取表名
            const table_name = comptime reflection.getTableName(T);

            // 创建表对象
            var table = try schema_mod.Table.init(allocator, table_name);
            errdefer table.deinit();

            // 从 T 自动生成列
            const columns = try reflection.generateColumns(T, allocator);
            defer allocator.free(columns);

            for (columns) |col| {
                _ = try table.addColumn(col);
            }

            self.* = .{
                .allocator = allocator,
                .db = db,
                .table = table,
                .if_not_exists_flag = false,
            };

            return self;
        }

        /// 初始化空的 CREATE TABLE 查询构建器（不自动生成列）
        ///
        /// 用于需要完全手动控制列定义的场景，例如添加复杂约束。
        ///
        /// ## 示例
        /// ```zig
        /// var query = try db.newCreateTableEmpty(User);
        /// defer query.deinit();
        ///
        /// _ = try query.column(.{
        ///     .name = "id",
        ///     .column_type = .bigserial,
        ///     .primary_key = true,
        /// });
        /// ```
        pub fn initEmpty(allocator: Allocator, db: *DBType) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            // 获取表名
            const table_name = comptime reflection.getTableName(T);

            // 创建空表对象（不生成列）
            const table = try schema_mod.Table.init(allocator, table_name);

            self.* = .{
                .allocator = allocator,
                .db = db,
                .table = table,
                .if_not_exists_flag = false,
            };

            return self;
        }

        /// 释放资源
        pub fn deinit(self: *Self) void {
            self.table.deinit();
            self.allocator.destroy(self);
        }

        /// 添加 IF NOT EXISTS 子句
        ///
        /// 如果表已存在，CREATE TABLE 不会失败。
        ///
        /// ## 示例
        /// ```zig
        /// try query.ifNotExists();
        /// ```
        pub fn ifNotExists(self: *Self) *Self {
            self.if_not_exists_flag = true;
            return self;
        }

        /// 添加列定义
        ///
        /// ## 参数
        /// - col: 列定义，使用 Column.init() 创建
        ///
        /// ## 示例
        /// ```zig
        /// var id_col = Column.init("id", .bigint);
        /// _ = id_col.setPrimaryKey().setAutoIncrement();
        /// try query.column(id_col);
        /// ```
        pub fn column(self: *Self, col: schema_mod.Column) !*Self {
            _ = try self.table.addColumn(col);
            return self;
        }

        /// 构建 CREATE TABLE SQL 语句
        pub fn build(self: *Self) ![]const u8 {
            const base_sql = try self.table.toSQL(dialect);
            defer self.allocator.free(base_sql);

            // 如果不需要 IF NOT EXISTS，直接返回
            if (!self.if_not_exists_flag) {
                return self.allocator.dupe(u8, base_sql);
            }

            // 插入 IF NOT EXISTS
            // "CREATE TABLE users (...)" -> "CREATE TABLE IF NOT EXISTS users (...)"
            var buf = std.ArrayList(u8){};
            errdefer buf.deinit(self.allocator);

            try buf.appendSlice(self.allocator, "CREATE TABLE IF NOT EXISTS ");
            // 跳过 "CREATE TABLE "
            try buf.appendSlice(self.allocator, base_sql[13..]);

            return buf.toOwnedSlice(self.allocator);
        }

        /// 执行 CREATE TABLE 语句
        ///
        /// ## 错误
        /// - error.QueryFailed: DDL 执行失败
        /// - error.TableAlreadyExists: 表已存在（未使用 IF NOT EXISTS 时）
        pub fn exec(self: *Self) !void {
            const query_str = try self.build();
            defer self.allocator.free(query_str);

            // 执行 DDL（无参数绑定）
            try self.db.exec(query_str, &.{});
        }
    };
}

/// DROP TABLE 查询构建器
///
/// ## 示例
/// ```zig
/// const User = struct {
///     id: i64,
///     pub const table_name = "users";
/// };
///
/// var query = try db.newDropTable(User);
/// defer query.deinit();
///
/// _ = query.ifExists();  // 添加 IF EXISTS 子句
/// try query.exec();
/// ```
pub fn DropTableQuery(comptime T: type, comptime dialect: Dialect) type {
    const DBType = db_mod.DB(dialect);
    const reflection = @import("../schema/reflection.zig");

    return struct {
        const Self = @This();

        allocator: Allocator,
        db: *DBType,
        table_name: []const u8,
        if_exists_flag: bool = false,
        cascade_flag: bool = false,

        /// 初始化 DROP TABLE 查询构建器
        ///
        /// 自动从模型类型 T 获取表名
        pub fn init(allocator: Allocator, db: *DBType) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            // 从 T 获取表名
            const table_name = comptime reflection.getTableName(T);

            self.* = .{
                .allocator = allocator,
                .db = db,
                .table_name = table_name,
                .if_exists_flag = false,
                .cascade_flag = false,
            };

            return self;
        }

        /// 释放资源
        pub fn deinit(self: *Self) void {
            self.allocator.destroy(self);
        }

        /// 添加 IF EXISTS 子句
        ///
        /// 如果表不存在,DROP TABLE 不会失败
        pub fn ifExists(self: *Self) *Self {
            self.if_exists_flag = true;
            return self;
        }

        /// 添加 CASCADE 子句
        ///
        /// 自动删除依赖此表的对象(例如外键约束)
        pub fn cascade(self: *Self) *Self {
            self.cascade_flag = true;
            return self;
        }

        /// 构建 DROP TABLE SQL 语句
        pub fn build(self: *Self) ![]const u8 {
            var buf = std.ArrayList(u8).init(self.allocator);
            errdefer buf.deinit();

            try buf.appendSlice("DROP TABLE ");

            if (self.if_exists_flag) {
                try buf.appendSlice("IF EXISTS ");
            }

            try buf.appendSlice(self.table_name);

            if (self.cascade_flag) {
                try buf.appendSlice(" CASCADE");
            }

            return buf.toOwnedSlice();
        }

        /// 执行 DROP TABLE 语句
        pub fn exec(self: *Self) !void {
            const query_str = try self.build();
            defer self.allocator.free(query_str);

            try self.db.exec(query_str, &.{});
        }
    };
}

/// CREATE INDEX 查询构建器
///
/// ## 示例
/// ```zig
/// const User = struct {
///     id: i64,
///     email: []const u8,
///     pub const table_name = "users";
/// };
///
/// var query = try db.newCreateIndex(User, "idx_email");
/// defer query.deinit();
///
/// _ = query.unique();  // 唯一索引
/// _ = try query.column("email");
/// try query.exec();
/// ```
pub fn CreateIndexQuery(comptime T: type, comptime dialect: Dialect) type {
    const DBType = db_mod.DB(dialect);
    const reflection = @import("../schema/reflection.zig");

    return struct {
        const Self = @This();

        allocator: Allocator,
        db: *DBType,
        table_name: []const u8,
        index_name: []const u8,
        columns: std.ArrayList([]const u8),
        unique_flag: bool = false,
        if_not_exists_flag: bool = false,

        /// 初始化 CREATE INDEX 查询构建器
        ///
        /// 自动从模型类型 T 获取表名
        pub fn init(allocator: Allocator, db: *DBType, index_name: []const u8) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            // 从 T 获取表名
            const table_name = comptime reflection.getTableName(T);

            self.* = .{
                .allocator = allocator,
                .db = db,
                .table_name = table_name,
                .index_name = index_name,
                .columns = .{},
                .unique_flag = false,
                .if_not_exists_flag = false,
            };

            return self;
        }

        /// 释放资源
        pub fn deinit(self: *Self) void {
            self.columns.deinit(self.allocator);
            self.allocator.destroy(self);
        }

        /// 创建唯一索引
        pub fn unique(self: *Self) *Self {
            self.unique_flag = true;
            return self;
        }

        /// 添加 IF NOT EXISTS 子句 (仅 PostgreSQL 和 SQLite 支持)
        pub fn ifNotExists(self: *Self) *Self {
            self.if_not_exists_flag = true;
            return self;
        }

        /// 添加索引列
        pub fn column(self: *Self, col_name: []const u8) !*Self {
            try self.columns.append(self.allocator, col_name);
            return self;
        }

        /// 构建 CREATE INDEX SQL 语句
        pub fn build(self: *Self) ![]const u8 {
            var buf: std.ArrayList(u8) = .{};
            errdefer buf.deinit(self.allocator);

            try buf.appendSlice(self.allocator, "CREATE ");

            if (self.unique_flag) {
                try buf.appendSlice(self.allocator, "UNIQUE ");
            }

            try buf.appendSlice(self.allocator, "INDEX ");

            // IF NOT EXISTS 支持 (PostgreSQL 和 SQLite)
            if (self.if_not_exists_flag and (dialect == .postgresql or dialect == .sqlite)) {
                try buf.appendSlice(self.allocator, "IF NOT EXISTS ");
            }

            try buf.appendSlice(self.allocator, self.index_name);
            try buf.appendSlice(self.allocator, " ON ");
            try buf.appendSlice(self.allocator, self.table_name);
            try buf.appendSlice(self.allocator, " (");

            // 添加列名
            for (self.columns.items, 0..) |col, i| {
                if (i > 0) try buf.appendSlice(self.allocator, ", ");
                try buf.appendSlice(self.allocator, col);
            }

            try buf.appendSlice(self.allocator, ")");

            return buf.toOwnedSlice(self.allocator);
        }

        /// 执行 CREATE INDEX 语句
        pub fn exec(self: *Self) !void {
            const query_str = try self.build();
            defer self.allocator.free(query_str);

            try self.db.exec(query_str, &.{});
        }
    };
}

/// DROP INDEX 查询构建器
///
/// ## 示例
/// ```zig
/// const User = struct {
///     id: i64,
///     pub const table_name = "users";
/// };
///
/// var query = try db.newDropIndex(User, "idx_email");
/// defer query.deinit();
///
/// _ = query.ifExists();
/// try query.exec();
/// ```
pub fn DropIndexQuery(comptime T: type, comptime dialect: Dialect) type {
    const DBType = db_mod.DB(dialect);
    const reflection = @import("../schema/reflection.zig");

    return struct {
        const Self = @This();

        allocator: Allocator,
        db: *DBType,
        table_name: []const u8,
        index_name: []const u8,
        if_exists_flag: bool = false,

        /// 初始化 DROP INDEX 查询构建器
        ///
        /// 自动从模型类型 T 获取表名
        pub fn init(allocator: Allocator, db: *DBType, index_name: []const u8) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            // 从 T 获取表名
            const table_name = comptime reflection.getTableName(T);

            self.* = .{
                .allocator = allocator,
                .db = db,
                .table_name = table_name,
                .index_name = index_name,
                .if_exists_flag = false,
            };

            return self;
        }

        /// 释放资源
        pub fn deinit(self: *Self) void {
            self.allocator.destroy(self);
        }

        /// 添加 IF EXISTS 子句
        pub fn ifExists(self: *Self) *Self {
            self.if_exists_flag = true;
            return self;
        }

        /// 构建 DROP INDEX SQL 语句
        pub fn build(self: *Self) ![]const u8 {
            var buf = std.ArrayList(u8).init(self.allocator);
            errdefer buf.deinit();

            try buf.appendSlice("DROP INDEX ");

            if (self.if_exists_flag) {
                try buf.appendSlice("IF EXISTS ");
            }

            // MySQL 语法: DROP INDEX index_name ON table_name
            // PostgreSQL/SQLite 语法: DROP INDEX index_name
            if (dialect == .mysql) {
                try buf.appendSlice(self.index_name);
                try buf.appendSlice(" ON ");
                try buf.appendSlice(self.table_name);
            } else {
                try buf.appendSlice(self.index_name);
            }

            return buf.toOwnedSlice();
        }

        /// 执行 DROP INDEX 语句
        pub fn exec(self: *Self) !void {
            const query_str = try self.build();
            defer self.allocator.free(query_str);

            try self.db.exec(query_str, &.{});
        }
    };
}

// ============================================
// 单元测试
// ============================================

// ============================================
// 测试辅助结构
// ============================================

const User = struct {
    id: i64,
    name: []const u8,
    email: ?[]const u8,
    age: u32,

    pub const table_name = "users";
};

// ============================================
// 单元测试
// ============================================

test "SelectQuery: 基本实例化" {
    // 验证查询构建器可以为不同方言实例化
    const PostgresSelectQuery = SelectQuery(User, .postgresql);
    const MySQLSelectQuery = SelectQuery(User, .mysql);
    const SQLiteSelectQuery = SelectQuery(User, .sqlite);

    // 验证它们是不同的类型
    try std.testing.expect(PostgresSelectQuery != MySQLSelectQuery);
    try std.testing.expect(PostgresSelectQuery != SQLiteSelectQuery);
    try std.testing.expect(MySQLSelectQuery != SQLiteSelectQuery);
}

test "SelectQuery: SELECT * FROM" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try SelectQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users", sql);
}

test "SelectQuery: SELECT specific columns" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try SelectQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.column("id");
    _ = try query.column("name");
    _ = try query.column("email");

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT id, name, email FROM users", sql);
}

test "SelectQuery: WHERE clause" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try SelectQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.where("age > $1", .{18});

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE age > $1", sql);
}

test "SelectQuery: Multiple WHERE clauses (AND/OR)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try SelectQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.where("age > $1", .{18});
    _ = try query.where("status = $2", .{"active"});
    _ = try query.whereOr("role = $3", .{"admin"});

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE age > $1 AND status = $2 OR role = $3", sql);
}

test "SelectQuery: INNER JOIN" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try SelectQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.innerJoin("orders", "users.id = orders.user_id");

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users INNER JOIN orders ON users.id = orders.user_id", sql);
}

test "SelectQuery: Multiple JOINs" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try SelectQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.leftJoin("orders", "users.id = orders.user_id");
    _ = try query.innerJoin("products", "orders.product_id = products.id");

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users LEFT JOIN orders ON users.id = orders.user_id INNER JOIN products ON orders.product_id = products.id", sql);
}

test "SelectQuery: ORDER BY" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try SelectQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.orderBy("created_at", .desc);
    _ = try query.orderBy("name", .asc);

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users ORDER BY created_at DESC, name ASC", sql);
}

test "SelectQuery: GROUP BY and HAVING" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try SelectQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.column("department");
    _ = try query.column("COUNT(*) as count");
    _ = try query.groupBy("department");
    _ = try query.having("COUNT(*) > $1", .{10});

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT department, COUNT(*) as count FROM users GROUP BY department HAVING COUNT(*) > $1", sql);
}

test "SelectQuery: LIMIT and OFFSET" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try SelectQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.limit(10);
    _ = try query.offset(20);

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users LIMIT 10 OFFSET 20", sql);
}

test "SelectQuery: DISTINCT" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try SelectQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.column("department");
    _ = try query.distinct();

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT DISTINCT department FROM users", sql);
}

test "SelectQuery: Complete complex query" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try SelectQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.column("u.id");
    _ = try query.column("u.name");
    _ = try query.column("COUNT(o.id) as order_count");
    _ = try query.innerJoin("orders o", "u.id = o.user_id");
    _ = try query.where("u.age > $1", .{18});
    _ = try query.where("u.status = $2", .{"active"});
    _ = try query.groupBy("u.id");
    _ = try query.groupBy("u.name");
    _ = try query.having("COUNT(o.id) > $3", .{5});
    _ = try query.orderBy("order_count", .desc);
    _ = try query.limit(10);

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    const expected = "SELECT u.id, u.name, COUNT(o.id) as order_count FROM users " ++
        "INNER JOIN orders o ON u.id = o.user_id " ++
        "WHERE u.age > $1 AND u.status = $2 " ++
        "GROUP BY u.id, u.name " ++
        "HAVING COUNT(o.id) > $3 " ++
        "ORDER BY order_count DESC " ++
        "LIMIT 10";

    try std.testing.expectEqualStrings(expected, sql);
}

// ============================================
// InsertQuery 测试
// ============================================

test "InsertQuery: 基本实例化" {
    const PostgresInsertQuery = InsertQuery(User, .postgresql);
    const MySQLInsertQuery = InsertQuery(User, .mysql);
    const SQLiteInsertQuery = InsertQuery(User, .sqlite);

    try std.testing.expect(PostgresInsertQuery != MySQLInsertQuery);
    try std.testing.expect(PostgresInsertQuery != SQLiteInsertQuery);
    try std.testing.expect(MySQLInsertQuery != SQLiteInsertQuery);
}

test "InsertQuery: 单行插入 (PostgreSQL)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try InsertQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.value(.{
        .name = "Alice",
        .email = "alice@example.com",
        .age = 25,
    });

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("INSERT INTO users (name, email, age) VALUES ($1, $2, $3)", sql);
}

test "InsertQuery: 单行插入 (MySQL)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try InsertQuery(User, .mysql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.value(.{
        .name = "Bob",
        .email = "bob@example.com",
        .age = 30,
    });

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("INSERT INTO users (name, email, age) VALUES (?, ?, ?)", sql);
}

test "InsertQuery: 批量插入" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try InsertQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    const users = [_]struct { name: []const u8, email: []const u8, age: u32 }{
        .{ .name = "Alice", .email = "alice@example.com", .age = 25 },
        .{ .name = "Bob", .email = "bob@example.com", .age = 30 },
        .{ .name = "Carol", .email = "carol@example.com", .age = 35 },
    };

    _ = try query.values(&users);

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    const expected = "INSERT INTO users (name, email, age) VALUES " ++
        "($1, $2, $3), ($4, $5, $6), ($7, $8, $9)";

    try std.testing.expectEqualStrings(expected, sql);
}

test "InsertQuery: RETURNING (PostgreSQL)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try InsertQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.value(.{
        .name = "Alice",
        .email = "alice@example.com",
        .age = 25,
    });

    _ = try query.returning(&.{ "id", "name" });

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("INSERT INTO users (name, email, age) VALUES ($1, $2, $3) RETURNING id, name", sql);
}

test "InsertQuery: ON CONFLICT DO NOTHING (PostgreSQL)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try InsertQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.value(.{
        .name = "Alice",
        .email = "alice@example.com",
        .age = 25,
    });

    const conflict_cols = [_][]const u8{"email"};
    _ = try query.onConflict(.{
        .columns = &conflict_cols,
        .action = .do_nothing,
        .update_columns = null,
    });

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("INSERT INTO users (name, email, age) VALUES ($1, $2, $3) ON CONFLICT (email) DO NOTHING", sql);
}

test "InsertQuery: ON CONFLICT DO UPDATE (PostgreSQL)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try InsertQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.value(.{
        .name = "Alice",
        .email = "alice@example.com",
        .age = 25,
    });

    const conflict_cols = [_][]const u8{"email"};
    const update_cols = [_][]const u8{ "name", "age" };
    _ = try query.onConflict(.{
        .columns = &conflict_cols,
        .action = .do_update,
        .update_columns = &update_cols,
    });

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    const expected = "INSERT INTO users (name, email, age) VALUES ($1, $2, $3) " ++
        "ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name, age = EXCLUDED.age";

    try std.testing.expectEqualStrings(expected, sql);
}

test "InsertQuery: ON DUPLICATE KEY UPDATE (MySQL)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try InsertQuery(User, .mysql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.value(.{
        .name = "Alice",
        .email = "alice@example.com",
        .age = 25,
    });

    const update_cols = [_][]const u8{ "name", "age" };
    _ = try query.onDuplicateKeyUpdate(.{
        .columns = &update_cols,
    });

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    const expected = "INSERT INTO users (name, email, age) VALUES (?, ?, ?) " ++
        "ON DUPLICATE KEY UPDATE name = VALUES(name), age = VALUES(age)";

    try std.testing.expectEqualStrings(expected, sql);
}

test "InsertQuery: 完整复杂插入 (PostgreSQL)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try InsertQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    const users = [_]struct { name: []const u8, email: []const u8, age: u32 }{
        .{ .name = "Alice", .email = "alice@example.com", .age = 25 },
        .{ .name = "Bob", .email = "bob@example.com", .age = 30 },
    };

    _ = try query.values(&users);

    const conflict_cols = [_][]const u8{"email"};
    const update_cols = [_][]const u8{"name"};
    _ = try query.onConflict(.{
        .columns = &conflict_cols,
        .action = .do_update,
        .update_columns = &update_cols,
    });

    _ = try query.returning(&.{"id"});

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    const expected = "INSERT INTO users (name, email, age) VALUES ($1, $2, $3), ($4, $5, $6) " ++
        "ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name " ++
        "RETURNING id";

    try std.testing.expectEqualStrings(expected, sql);
}

// ============================================
// UpdateQuery 测试
// ============================================

test "UpdateQuery: 基本实例化" {
    const PostgresUpdateQuery = UpdateQuery(User, .postgresql);
    const MySQLUpdateQuery = UpdateQuery(User, .mysql);
    const SQLiteUpdateQuery = UpdateQuery(User, .sqlite);

    try std.testing.expect(PostgresUpdateQuery != MySQLUpdateQuery);
    try std.testing.expect(PostgresUpdateQuery != SQLiteUpdateQuery);
    try std.testing.expect(MySQLUpdateQuery != SQLiteUpdateQuery);
}

test "UpdateQuery: 基本UPDATE (PostgreSQL)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try UpdateQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.set("name = $1", .{"Alice"});

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("UPDATE users SET name = $1", sql);
}

test "UpdateQuery: 基本UPDATE (MySQL)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try UpdateQuery(User, .mysql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.set("name = ?", .{"Bob"});

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("UPDATE users SET name = ?", sql);
}

test "UpdateQuery: 多个SET子句" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try UpdateQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.set("name = $1", .{"Alice"});
    _ = try query.set("email = $2", .{"alice@example.com"});
    _ = try query.set("age = $3", .{25});

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("UPDATE users SET name = $1, email = $2, age = $3", sql);
}

test "UpdateQuery: UPDATE with WHERE" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try UpdateQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.set("name = $1", .{"Alice"});
    _ = try query.where("id = $2", .{1});

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("UPDATE users SET name = $1 WHERE id = $2", sql);
}

test "UpdateQuery: UPDATE with multiple WHERE (AND/OR)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try UpdateQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.set("name = $1", .{"Alice"});
    _ = try query.where("age > $2", .{18});
    _ = try query.where("status = $3", .{"active"});
    _ = try query.whereOr("role = $4", .{"admin"});

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    const expected = "UPDATE users SET name = $1 WHERE age > $2 AND status = $3 OR role = $4";
    try std.testing.expectEqualStrings(expected, sql);
}

test "UpdateQuery: UPDATE with RETURNING (PostgreSQL)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try UpdateQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.set("name = $1", .{"Alice"});
    _ = try query.where("id = $2", .{1});
    _ = query.setReturning(&.{ "id", "updated_at" });

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("UPDATE users SET name = $1 WHERE id = $2 RETURNING id, updated_at", sql);
}

test "UpdateQuery: 完整复杂UPDATE (PostgreSQL)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try UpdateQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.set("name = $1", .{"Alice"});
    _ = try query.set("email = $2", .{"alice@example.com"});
    _ = try query.set("age = $3", .{25});
    _ = try query.where("id = $4", .{1});
    _ = try query.where("status = $5", .{"active"});
    _ = query.setReturning(&.{"id"});

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    const expected = "UPDATE users SET name = $1, email = $2, age = $3 WHERE id = $4 AND status = $5 RETURNING id";
    try std.testing.expectEqualStrings(expected, sql);
}

// ============================================
// DeleteQuery 测试
// ============================================

test "DeleteQuery: 基本实例化" {
    const PostgresDeleteQuery = DeleteQuery(User, .postgresql);
    const MySQLDeleteQuery = DeleteQuery(User, .mysql);
    const SQLiteDeleteQuery = DeleteQuery(User, .sqlite);

    try std.testing.expect(PostgresDeleteQuery != MySQLDeleteQuery);
    try std.testing.expect(PostgresDeleteQuery != SQLiteDeleteQuery);
    try std.testing.expect(MySQLDeleteQuery != SQLiteDeleteQuery);
}

test "DeleteQuery: 简单DELETE (无WHERE)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try DeleteQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("DELETE FROM users", sql);
}

test "DeleteQuery: DELETE with WHERE (PostgreSQL)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try DeleteQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.where("id = $1", .{1});

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("DELETE FROM users WHERE id = $1", sql);
}

test "DeleteQuery: DELETE with WHERE (MySQL)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try DeleteQuery(User, .mysql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.where("age < ?", .{18});

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("DELETE FROM users WHERE age < ?", sql);
}

test "DeleteQuery: DELETE with multiple WHERE (AND/OR)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try DeleteQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.where("age < $1", .{18});
    _ = try query.where("status = $2", .{"inactive"});
    _ = try query.whereOr("role = $3", .{"guest"});

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    const expected = "DELETE FROM users WHERE age < $1 AND status = $2 OR role = $3";
    try std.testing.expectEqualStrings(expected, sql);
}

test "DeleteQuery: DELETE with RETURNING (PostgreSQL)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try DeleteQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.where("id = $1", .{1});
    _ = try query.returning(&.{ "id", "name" });

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings("DELETE FROM users WHERE id = $1 RETURNING id, name", sql);
}

test "DeleteQuery: 完整复杂DELETE (PostgreSQL)" {
    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try DeleteQuery(User, .postgresql).init(std.testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.where("age < $1", .{18});
    _ = try query.where("status = $2", .{"inactive"});
    _ = try query.whereOr("deleted_at IS NOT NULL", .{});
    _ = try query.returning(&.{ "id", "name", "deleted_at" });

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    const expected = "DELETE FROM users WHERE age < $1 AND status = $2 OR deleted_at IS NOT NULL RETURNING id, name, deleted_at";
    try std.testing.expectEqualStrings(expected, sql);
}

// =============================================================================
// CreateTableQuery 测试
// =============================================================================

test "CreateTableQuery: 基本 CREATE TABLE" {
    const Column = @import("../schema/table.zig").Column;

    const TestUser = struct {
        pub const table_name = "users";
    };

    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try CreateTableQuery(TestUser, .postgresql).init(std.testing.allocator, @ptrCast(&db));
    defer query.deinit();

    var id_col = Column.init("id", .bigint);
    _ = id_col.setPrimaryKey().setAutoIncrement();
    _ = try query.column(id_col);

    var name_col = Column.init("name", .varchar);
    _ = name_col.setNotNull();
    _ = try query.column(name_col);

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    // 验证 SQL 包含关键部分
    try std.testing.expect(std.mem.indexOf(u8, sql, "CREATE TABLE users") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "id BIGINT PRIMARY KEY") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "name VARCHAR NOT NULL") != null);
}

test "CreateTableQuery: IF NOT EXISTS" {
    const Column = @import("../schema/table.zig").Column;

    const TestUser = struct {
        pub const table_name = "users";
    };

    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try CreateTableQuery(TestUser, .postgresql).init(std.testing.allocator, @ptrCast(&db));
    defer query.deinit();

    _ = query.ifNotExists();

    var id_col = Column.init("id", .bigint);
    _ = id_col.setPrimaryKey();
    _ = try query.column(id_col);

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "CREATE TABLE IF NOT EXISTS users") != null);
}

test "CreateTableQuery: 外键约束" {
    const Column = @import("../schema/table.zig").Column;

    const TestPost = struct {
        pub const table_name = "posts";
    };

    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try CreateTableQuery(TestPost, .postgresql).init(std.testing.allocator, @ptrCast(&db));
    defer query.deinit();

    var id_col = Column.init("id", .bigint);
    _ = id_col.setPrimaryKey();
    _ = try query.column(id_col);

    var user_id_col = Column.init("user_id", .bigint);
    _ = user_id_col.setForeignKey("users", "id").setNotNull();
    _ = try query.column(user_id_col);

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "CREATE TABLE posts") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "user_id BIGINT NOT NULL REFERENCES users(id)") != null);
}

test "CreateTableQuery: MySQL 语法" {
    const Column = @import("../schema/table.zig").Column;

    const TestProduct = struct {
        pub const table_name = "products";
    };

    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try CreateTableQuery(TestProduct, .mysql).init(std.testing.allocator, @ptrCast(&db));
    defer query.deinit();

    var id_col = Column.init("id", .bigint);
    _ = id_col.setPrimaryKey().setAutoIncrement();
    _ = try query.column(id_col);

    var name_col = Column.init("name", .varchar);
    _ = name_col.setNotNull();
    _ = try query.column(name_col);

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    // MySQL 使用 AUTO_INCREMENT 而不是 GENERATED ALWAYS AS IDENTITY
    try std.testing.expect(std.mem.indexOf(u8, sql, "AUTO_INCREMENT") != null);
}

test "CreateTableQuery: 复合主键" {
    const Column = @import("../schema/table.zig").Column;

    const TestUserRole = struct {
        pub const table_name = "user_roles";
    };

    const MockDB = struct {
        allocator: Allocator,
    };

    var db = MockDB{ .allocator = std.testing.allocator };

    var query = try CreateTableQuery(TestUserRole, .postgresql).init(std.testing.allocator, @ptrCast(&db));
    defer query.deinit();

    var user_id_col = Column.init("user_id", .bigint);
    _ = user_id_col.setPrimaryKey();
    _ = try query.column(user_id_col);

    var role_id_col = Column.init("role_id", .bigint);
    _ = role_id_col.setPrimaryKey();
    _ = try query.column(role_id_col);

    const sql = try query.build();
    defer std.testing.allocator.free(sql);

    // 复合主键应该单独声明
    try std.testing.expect(std.mem.indexOf(u8, sql, "PRIMARY KEY (user_id, role_id)") != null);
}
