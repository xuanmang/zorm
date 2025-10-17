//! Builder Base - 查询构建器共享基础功能
//!
//! 提供查询构建器之间的共享逻辑，减少代码重复:
//! - WHERE 子句构建
//! - 参数收集
//! - SQL 生成辅助函数
//!
//! ## 设计原则
//! - 使用工具函数提供可复用的逻辑
//! - 避免引入复杂的继承结构
//! - 保持类型安全和编译时优化

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../types.zig");

pub const WhereClause = types.WhereClause;
pub const WhereOperator = types.WhereOperator;
pub const QueryArg = types.QueryArg;

/// 将 anytype 参数转换为 []const QueryArg
///
/// ## 用途
/// 用于将用户传入的各种类型参数转换为统一的 QueryArg 数组
///
/// ## 示例
/// ```zig
/// const args = try allocArgs(allocator, .{1, "hello", true});
/// defer allocator.free(args);
/// ```
pub fn allocArgs(allocator: Allocator, args: anytype) ![]const QueryArg {
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

/// 添加 WHERE 条件（AND 运算符）
///
/// ## 参数
/// - allocator: 内存分配器
/// - where_clauses: WHERE 子句列表
/// - condition: SQL 条件字符串
/// - args: 参数元组
///
/// ## 示例
/// ```zig
/// try appendWhereAnd(allocator, &where_clauses, "age > $1", .{18});
/// ```
pub fn appendWhereAnd(
    allocator: Allocator,
    where_clauses: *std.ArrayList(WhereClause),
    condition: []const u8,
    args: anytype,
) !void {
    const args_slice = try allocArgs(allocator, args);
    const clause = WhereClause{
        .condition = condition,
        .args = args_slice,
        .operator = .and_op,
    };
    try where_clauses.append(allocator, clause);
}

/// 添加 WHERE 条件（OR 运算符）
///
/// ## 参数
/// - allocator: 内存分配器
/// - where_clauses: WHERE 子句列表
/// - condition: SQL 条件字符串
/// - args: 参数元组
///
/// ## 示例
/// ```zig
/// try appendWhereOr(allocator, &where_clauses, "role = $1", .{"admin"});
/// ```
pub fn appendWhereOr(
    allocator: Allocator,
    where_clauses: *std.ArrayList(WhereClause),
    condition: []const u8,
    args: anytype,
) !void {
    const args_slice = try allocArgs(allocator, args);
    const clause = WhereClause{
        .condition = condition,
        .args = args_slice,
        .operator = .or_op,
    };
    try where_clauses.append(allocator, clause);
}

/// 构建 WHERE 子句的 SQL 字符串
///
/// ## 参数
/// - allocator: 内存分配器
/// - buf: 字符串缓冲区
/// - where_clauses: WHERE 子句列表
///
/// ## 示例
/// ```zig
/// var buf = std.ArrayList(u8){};
/// try buildWhereClauses(allocator, &buf, where_clauses.items);
/// // buf 现在包含: " WHERE age > $1 AND status = $2 OR role = $3"
/// ```
pub fn buildWhereClauses(
    allocator: Allocator,
    buf: *std.ArrayList(u8),
    where_clauses: []const WhereClause,
) !void {
    if (where_clauses.len == 0) return;

    try buf.appendSlice(allocator, " WHERE ");
    for (where_clauses, 0..) |clause, i| {
        if (i > 0) {
            try buf.appendSlice(allocator, " ");
            try buf.appendSlice(allocator, clause.operator.toSQL());
            try buf.appendSlice(allocator, " ");
        }
        try buf.appendSlice(allocator, clause.condition);
    }
}

/// 收集 WHERE 子句的所有参数
///
/// ## 参数
/// - allocator: 内存分配器
/// - all_args: 目标参数列表
/// - where_clauses: WHERE 子句列表
///
/// ## 示例
/// ```zig
/// var all_args = std.ArrayList(QueryArg){};
/// defer all_args.deinit(allocator);
/// try collectWhereArgs(allocator, &all_args, where_clauses.items);
/// ```
pub fn collectWhereArgs(
    allocator: Allocator,
    all_args: *std.ArrayList(QueryArg),
    where_clauses: []const WhereClause,
) !void {
    for (where_clauses) |clause| {
        try all_args.appendSlice(allocator, clause.args);
    }
}

/// 释放 WHERE 子句的参数内存
///
/// ## 参数
/// - allocator: 内存分配器
/// - where_clauses: WHERE 子句列表
///
/// ## 示例
/// ```zig
/// freeWhereClauseArgs(allocator, where_clauses.items);
/// ```
pub fn freeWhereClauseArgs(
    allocator: Allocator,
    where_clauses: []const WhereClause,
) void {
    for (where_clauses) |clause| {
        allocator.free(clause.args);
    }
}

// ============================================
// 单元测试
// ============================================

test "allocArgs: 基本类型转换" {
    const args = try allocArgs(std.testing.allocator, .{ 1, "hello", true });
    defer std.testing.allocator.free(args);

    try std.testing.expectEqual(@as(usize, 3), args.len);
    try std.testing.expectEqual(QueryArg{ .int = 1 }, args[0]);
    try std.testing.expectEqualStrings("hello", args[1].string);
    try std.testing.expectEqual(QueryArg{ .bool = true }, args[2]);
}

test "allocArgs: 空参数" {
    const args = try allocArgs(std.testing.allocator, .{});
    defer std.testing.allocator.free(args);

    try std.testing.expectEqual(@as(usize, 0), args.len);
}

test "appendWhereAnd: 添加 AND 条件" {
    var where_clauses: std.ArrayList(WhereClause) = .{};
    defer {
        freeWhereClauseArgs(std.testing.allocator, where_clauses.items);
        where_clauses.deinit(std.testing.allocator);
    }

    try appendWhereAnd(std.testing.allocator, &where_clauses, "age > $1", .{18});
    try appendWhereAnd(std.testing.allocator, &where_clauses, "status = $2", .{"active"});

    try std.testing.expectEqual(@as(usize, 2), where_clauses.items.len);
    try std.testing.expectEqualStrings("age > $1", where_clauses.items[0].condition);
    try std.testing.expectEqual(WhereOperator.and_op, where_clauses.items[0].operator);
}

test "appendWhereOr: 添加 OR 条件" {
    var where_clauses: std.ArrayList(WhereClause) = .{};
    defer {
        freeWhereClauseArgs(std.testing.allocator, where_clauses.items);
        where_clauses.deinit(std.testing.allocator);
    }

    try appendWhereOr(std.testing.allocator, &where_clauses, "role = $1", .{"admin"});

    try std.testing.expectEqual(@as(usize, 1), where_clauses.items.len);
    try std.testing.expectEqualStrings("role = $1", where_clauses.items[0].condition);
    try std.testing.expectEqual(WhereOperator.or_op, where_clauses.items[0].operator);
}

test "buildWhereClauses: 构建 WHERE SQL" {
    var where_clauses: std.ArrayList(WhereClause) = .{};
    defer {
        freeWhereClauseArgs(std.testing.allocator, where_clauses.items);
        where_clauses.deinit(std.testing.allocator);
    }

    try appendWhereAnd(std.testing.allocator, &where_clauses, "age > $1", .{18});
    try appendWhereAnd(std.testing.allocator, &where_clauses, "status = $2", .{"active"});
    try appendWhereOr(std.testing.allocator, &where_clauses, "role = $3", .{"admin"});

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);

    try buildWhereClauses(std.testing.allocator, &buf, where_clauses.items);

    const expected = " WHERE age > $1 AND status = $2 OR role = $3";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "buildWhereClauses: 空 WHERE 列表" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);

    const empty_clauses: []const WhereClause = &.{};
    try buildWhereClauses(std.testing.allocator, &buf, empty_clauses);

    try std.testing.expectEqualStrings("", buf.items);
}

test "collectWhereArgs: 收集所有参数" {
    var where_clauses: std.ArrayList(WhereClause) = .{};
    defer {
        freeWhereClauseArgs(std.testing.allocator, where_clauses.items);
        where_clauses.deinit(std.testing.allocator);
    }

    try appendWhereAnd(std.testing.allocator, &where_clauses, "age > $1", .{18});
    try appendWhereAnd(std.testing.allocator, &where_clauses, "status = $2", .{"active"});

    var all_args: std.ArrayList(QueryArg) = .{};
    defer all_args.deinit(std.testing.allocator);

    try collectWhereArgs(std.testing.allocator, &all_args, where_clauses.items);

    try std.testing.expectEqual(@as(usize, 2), all_args.items.len);
    try std.testing.expectEqual(QueryArg{ .int = 18 }, all_args.items[0]);
    try std.testing.expectEqualStrings("active", all_args.items[1].string);
}

test "freeWhereClauseArgs: 释放内存" {
    var where_clauses: std.ArrayList(WhereClause) = .{};
    defer where_clauses.deinit(std.testing.allocator);

    try appendWhereAnd(std.testing.allocator, &where_clauses, "age > $1", .{18});

    // 显式释放
    freeWhereClauseArgs(std.testing.allocator, where_clauses.items);

    // 验证没有泄漏 - 如果有泄漏，测试会失败
}
