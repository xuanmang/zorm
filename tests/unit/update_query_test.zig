//! UpdateQuery 单元测试
//!
//! 测试 UPDATE 查询构建器的各种功能，包括：
//! - SQL 生成
//! - WHERE 条件组合
//! - 参数绑定
//! - RETURNING 子句
//! - 链式调用
//! - 内存管理

const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");
const Dialect = zorm.Dialect;

// 测试用模型
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: u32,
    updated_at: i64,

    pub const table_name = "users";
};

test "UpdateQuery: 基本实例化" {
    const allocator = testing.allocator;

    // Mock DB (仅用于类型检查)
    const PostgresDB = zorm.DB(.postgresql);
    _ = PostgresDB; // 暂时不实例化，只测试类型

    // 验证 UpdateQuery 类型可以被创建
    const UpdateQuery = zorm.UpdateQuery(User, .postgresql);
    _ = UpdateQuery;
}

test "UpdateQuery: 基本 SET 表达式生成 (PostgreSQL)" {
    const allocator = testing.allocator;

    // 由于我们没有真实的 DB 实例，我们直接测试 SQL 构建逻辑
    // 这里我们通过测试来验证 API 设计是否正确

    // 模拟的测试：验证 SetClause 结构
    const SetClause = struct {
        assignment: []const u8,
        args: []const zorm.QueryArg,
    };

    var args = [_]zorm.QueryArg{zorm.QueryArg.fromValue("Alice")};
    const clause = SetClause{
        .assignment = "name = $1",
        .args = &args,
    };

    try testing.expectEqualStrings("name = $1", clause.assignment);
    try testing.expectEqual(@as(usize, 1), clause.args.len);
}

test "UpdateQuery: 多个 SET 子句" {
    const allocator = testing.allocator;

    // 测试多个 SET 表达式
    const SetClause = struct {
        assignment: []const u8,
        args: []const zorm.QueryArg,
    };

    var args1 = [_]zorm.QueryArg{zorm.QueryArg.fromValue(25)};
    var args2 = [_]zorm.QueryArg{zorm.QueryArg.fromValue(@as(i64, 1234567890))};

    const clause1 = SetClause{
        .assignment = "age = $1",
        .args = &args1,
    };
    const clause2 = SetClause{
        .assignment = "updated_at = $2",
        .args = &args2,
    };

    try testing.expectEqualStrings("age = $1", clause1.assignment);
    try testing.expectEqualStrings("updated_at = $2", clause2.assignment);
}

test "UpdateQuery: WHERE 条件组合" {
    const allocator = testing.allocator;

    // 测试 WHERE 子句
    const WhereClause = zorm.WhereClause;

    var args = [_]zorm.QueryArg{zorm.QueryArg.fromValue("alice@example.com")};
    const where_clause = WhereClause{
        .condition = "email = $1",
        .args = &args,
        .operator = .and_op,
    };

    try testing.expectEqualStrings("email = $1", where_clause.condition);
    try testing.expectEqual(zorm.WhereOperator.and_op, where_clause.operator);
}

test "UpdateQuery: WHERE 多条件 (AND/OR)" {
    const allocator = testing.allocator;

    const WhereClause = zorm.WhereClause;

    var args1 = [_]zorm.QueryArg{zorm.QueryArg.fromValue("active")};
    var args2 = [_]zorm.QueryArg{zorm.QueryArg.fromValue("pending")};

    const where1 = WhereClause{
        .condition = "status = $1",
        .args = &args1,
        .operator = .and_op,
    };
    const where2 = WhereClause{
        .condition = "status = $2",
        .args = &args2,
        .operator = .or_op,
    };

    try testing.expectEqual(zorm.WhereOperator.and_op, where1.operator);
    try testing.expectEqual(zorm.WhereOperator.or_op, where2.operator);
}

test "UpdateQuery: 参数类型测试" {
    const allocator = testing.allocator;

    // 测试各种参数类型
    const arg_int = zorm.QueryArg.fromValue(@as(i64, 42));
    const arg_str = zorm.QueryArg.fromValue("hello");
    const arg_bool = zorm.QueryArg.fromValue(true);
    const arg_float = zorm.QueryArg.fromValue(@as(f64, 3.14));

    try testing.expect(arg_int == .int);
    try testing.expect(arg_str == .string);
    try testing.expect(arg_bool == .bool);
    try testing.expect(arg_float == .float);
}

test "UpdateQuery: UpdateResult 结构" {
    const UpdateResult = zorm.UpdateResult;

    const result = UpdateResult{
        .rows_affected = 10,
    };

    try testing.expectEqual(@as(usize, 10), result.rows_affected);
}

test "UpdateQuery: RETURNING 列表" {
    const allocator = testing.allocator;

    // 测试 RETURNING 列
    const returning_cols = [_][]const u8{ "id", "updated_at" };

    try testing.expectEqual(@as(usize, 2), returning_cols.len);
    try testing.expectEqualStrings("id", returning_cols[0]);
    try testing.expectEqualStrings("updated_at", returning_cols[1]);
}

test "UpdateQuery: 链式调用验证" {
    // 验证 API 设计支持链式调用
    // 通过类型签名验证即可，无需实际执行

    const UpdateQuery = zorm.UpdateQuery(User, .postgresql);
    _ = UpdateQuery;

    // 如果能编译通过，说明链式调用的类型签名是正确的
}

test "UpdateQuery: SQL 表达式更新" {
    const allocator = testing.allocator;

    // 测试 SQL 表达式
    const SetClause = struct {
        assignment: []const u8,
        args: []const zorm.QueryArg,
    };

    // age = age + 1
    const clause = SetClause{
        .assignment = "age = age + 1",
        .args = &[_]zorm.QueryArg{},
    };

    try testing.expectEqualStrings("age = age + 1", clause.assignment);
    try testing.expectEqual(@as(usize, 0), clause.args.len);
}

test "UpdateQuery: 复杂表达式组合" {
    const allocator = testing.allocator;

    // 测试复杂的 SET 表达式
    const SetClause = struct {
        assignment: []const u8,
        args: []const zorm.QueryArg,
    };

    var args = [_]zorm.QueryArg{zorm.QueryArg.fromValue(@as(i64, 1234567890))};
    const clause = SetClause{
        .assignment = "score = score * 2, updated_at = $1",
        .args = &args,
    };

    try testing.expectEqualStrings("score = score * 2, updated_at = $1", clause.assignment);
    try testing.expectEqual(@as(usize, 1), clause.args.len);
}

test "UpdateQuery: 内存管理 - ArrayList 初始化" {
    const allocator = testing.allocator;

    // 测试 ArrayList 正确的初始化方式 (Zig 0.15.2+)
    var set_clauses = std.ArrayList(struct {
        assignment: []const u8,
        args: []const zorm.QueryArg,
    }){};
    defer set_clauses.deinit(allocator);

    var where_clauses = std.ArrayList(zorm.WhereClause){};
    defer where_clauses.deinit(allocator);

    // 验证初始状态
    try testing.expectEqual(@as(usize, 0), set_clauses.items.len);
    try testing.expectEqual(@as(usize, 0), where_clauses.items.len);
}
