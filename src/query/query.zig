//! Query - 查询构建器
//!
//! 提供类型安全的 SQL 查询构建器:
//! - SelectQuery - SELECT 查询
//! - InsertQuery - INSERT 查询
//! - UpdateQuery - UPDATE 查询
//! - DeleteQuery - DELETE 查询

const std = @import("std");
const Allocator = std.mem.Allocator;
const DB = @import("../core/db.zig").DB;
const Dialect = @import("../dialect/dialect.zig").Dialect;

/// WHERE 子句操作符
pub const WhereOp = enum {
    and_op,
    or_op,
};

/// WHERE 子句
pub const WhereClause = struct {
    condition: []const u8,
    args: []const []const u8,
    operator: WhereOp,
};

/// SELECT 查询构建器
pub fn SelectQuery(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        db: *DB,
        columns: std.ArrayList([]const u8),
        table_name: []const u8,
        where_clauses: std.ArrayList(WhereClause),
        order_by: std.ArrayList([]const u8),
        limit_value: ?usize,
        offset_value: ?usize,
        distinct_value: bool,

        /// 初始化查询构建器
        pub fn init(allocator: Allocator, db: *DB, table_name: []const u8) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.* = .{
                .allocator = allocator,
                .db = db,
                .columns = std.ArrayList([]const u8).init(allocator),
                .table_name = table_name,
                .where_clauses = std.ArrayList(WhereClause).init(allocator),
                .order_by = std.ArrayList([]const u8).init(allocator),
                .limit_value = null,
                .offset_value = null,
                .distinct_value = false,
            };

            return self;
        }

        /// 释放资源
        pub fn deinit(self: *Self) void {
            self.columns.deinit();
            for (self.where_clauses.items) |clause| {
                self.allocator.free(clause.args);
            }
            self.where_clauses.deinit();
            self.order_by.deinit();
            self.allocator.destroy(self);
        }

        /// 选择列
        pub fn column(self: *Self, col: []const u8) !*Self {
            try self.columns.append(col);
            return self;
        }

        /// 选择所有列
        pub fn columnAll(self: *Self) !*Self {
            try self.columns.append("*");
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
            try self.where_clauses.append(clause);
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
            try self.where_clauses.append(clause);
            return self;
        }

        /// 添加 ORDER BY
        pub fn orderBy(self: *Self, order: []const u8) !*Self {
            try self.order_by.append(order);
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
            var buf = std.ArrayList(u8).init(self.allocator);
            errdefer buf.deinit();

            // SELECT
            try buf.appendSlice("SELECT ");

            if (self.distinct_value) {
                try buf.appendSlice("DISTINCT ");
            }

            // 列
            if (self.columns.items.len > 0) {
                for (self.columns.items, 0..) |col, i| {
                    if (i > 0) try buf.appendSlice(", ");
                    try buf.appendSlice(col);
                }
            } else {
                try buf.appendSlice("*");
            }

            // FROM
            try buf.appendSlice(" FROM ");
            try buf.appendSlice(self.table_name);

            // WHERE
            if (self.where_clauses.items.len > 0) {
                try buf.appendSlice(" WHERE ");
                for (self.where_clauses.items, 0..) |clause, i| {
                    if (i > 0) {
                        switch (clause.operator) {
                            .and_op => try buf.appendSlice(" AND "),
                            .or_op => try buf.appendSlice(" OR "),
                        }
                    }
                    try buf.appendSlice(clause.condition);
                }
            }

            // ORDER BY
            if (self.order_by.items.len > 0) {
                try buf.appendSlice(" ORDER BY ");
                for (self.order_by.items, 0..) |order, i| {
                    if (i > 0) try buf.appendSlice(", ");
                    try buf.appendSlice(order);
                }
            }

            // LIMIT/OFFSET
            const dialect_type = self.db.getDialect();
            const limit_clause = dialect_type.limitClause(self.limit_value, self.offset_value);
            if (limit_clause.len > 0) {
                try buf.appendSlice(limit_clause);
            }

            return buf.toOwnedSlice();
        }

        /// 执行查询并扫描一条记录
        pub fn scanOne(self: *Self) !T {
            const query_str = try self.build();
            defer self.allocator.free(query_str);

            // 收集所有参数
            var all_args = std.ArrayList([]const u8).init(self.allocator);
            defer all_args.deinit();

            for (self.where_clauses.items) |clause| {
                try all_args.appendSlice(clause.args);
            }

            const result = try self.db.query(query_str, all_args.items);
            defer result.close();

            if (!(try result.next())) {
                return error.NoRows;
            }

            // TODO: 实现完整的扫描逻辑
            return error.ScanError;
        }

        /// 执行查询并扫描多条记录
        pub fn scan(self: *Self) ![]T {
            _ = self;
            // TODO: 实现完整的扫描逻辑
            return error.ScanError;
        }
    };
}

/// 辅助函数: 将 anytype 参数转换为 []const []const u8
fn allocArgs(allocator: Allocator, args: anytype) ![]const []const u8 {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);

    if (args_type_info != .@"struct") {
        @compileError("args must be a tuple");
    }

    const fields = args_type_info.@"struct".fields;
    var result = try allocator.alloc([]const u8, fields.len);
    errdefer allocator.free(result);

    inline for (fields, 0..) |field, i| {
        const value = @field(args, field.name);
        const ValueType = @TypeOf(value);

        // 转换为字符串
        const str = switch (@typeInfo(ValueType)) {
            .int => try std.fmt.allocPrint(allocator, "{d}", .{value}),
            .float => try std.fmt.allocPrint(allocator, "{d}", .{value}),
            .bool => try std.fmt.allocPrint(allocator, "{}", .{value}),
            .pointer => |ptr_info| blk: {
                if (ptr_info.child == u8) {
                    break :blk value;
                } else {
                    @compileError("Unsupported pointer type");
                }
            },
            else => @compileError("Unsupported type for query argument"),
        };

        result[i] = str;
    }

    return result;
}

/// INSERT 查询构建器 (骨架)
pub fn InsertQuery(comptime T: type) type {
    _ = T; // TODO: 使用类型参数进行反射
    return struct {
        const Self = @This();
        allocator: Allocator,
        db: *DB,
        table_name: []const u8,

        pub fn init(allocator: Allocator, db: *DB, table_name: []const u8) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .allocator = allocator,
                .db = db,
                .table_name = table_name,
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.destroy(self);
        }
    };
}

/// UPDATE 查询构建器 (骨架)
pub fn UpdateQuery(comptime T: type) type {
    _ = T; // TODO: 使用类型参数进行反射
    return struct {
        const Self = @This();
        allocator: Allocator,
        db: *DB,
        table_name: []const u8,

        pub fn init(allocator: Allocator, db: *DB, table_name: []const u8) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .allocator = allocator,
                .db = db,
                .table_name = table_name,
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.destroy(self);
        }
    };
}

/// DELETE 查询构建器 (骨架)
pub fn DeleteQuery(comptime T: type) type {
    _ = T; // TODO: 使用类型参数进行反射
    return struct {
        const Self = @This();
        allocator: Allocator,
        db: *DB,
        table_name: []const u8,

        pub fn init(allocator: Allocator, db: *DB, table_name: []const u8) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .allocator = allocator,
                .db = db,
                .table_name = table_name,
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.destroy(self);
        }
    };
}

test "select query builder" {
    // TODO: 实现完整的测试
    // const testing = std.testing;
    // const allocator = testing.allocator;

    // 模拟 DB (需要实现)
    // var db = try DB.init(...);
    // defer db.deinit();

    // const User = struct {
    //     id: i64,
    //     name: []const u8,
    // };

    // var query = try SelectQuery(User).init(allocator, db, "users");
    // defer query.deinit();

    // _ = try query.column("id").column("name");
    // _ = try query.where("id = ?", .{123});
    // _ = try query.orderBy("id DESC");
    // _ = try query.limit(10);

    // const sql = try query.build();
    // defer allocator.free(sql);

    // std.debug.print("SQL: {s}\n", .{sql});
}
