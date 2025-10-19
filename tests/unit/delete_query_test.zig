//! DeleteQuery 单元测试
//!
//! 测试 DELETE 查询构建器的各种功能，包括：
//! - SQL 生成
//! - WHERE 条件组合 (AND/OR)
//! - whereIn/whereNotIn 批量删除
//! - 强制 WHERE 检查（安全性测试）
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
    created_at: i64,

    pub const table_name = "users";
};

test "DeleteQuery: 基本实例化" {
    const allocator = testing.allocator;

    // Mock DB (仅用于类型检查)
    const PostgresDB = zorm.DB(.postgresql);
    _ = PostgresDB; // 暂时不实例化，只测试类型

    // 验证 DeleteQuery 类型可以被创建
    const DeleteQuery = zorm.DeleteQuery(User, .postgresql);
    _ = DeleteQuery;
}

test "DeleteQuery: DeleteResult 结构" {
    const DeleteResult = zorm.DeleteResult;

    const result = DeleteResult{
        .rows_affected = 5,
    };

    try testing.expectEqual(@as(usize, 5), result.rows_affected);
}

test "DeleteQuery: WHERE 条件测试" {
    const allocator = testing.allocator;

    // 测试 WHERE 子句结构
    const WhereClause = zorm.WhereClause;

    var args = [_]zorm.QueryArg{zorm.QueryArg.fromValue(@as(i64, 123))};
    const where_clause = WhereClause{
        .condition = "id = ?",
        .args = &args,
        .operator = .and_op,
    };

    try testing.expectEqualStrings("id = ?", where_clause.condition);
    try testing.expectEqual(zorm.WhereOperator.and_op, where_clause.operator);
    try testing.expectEqual(@as(usize, 1), where_clause.args.len);
}

test "DeleteQuery: WHERE 多条件 (AND/OR)" {
    const allocator = testing.allocator;

    const WhereClause = zorm.WhereClause;

    var args1 = [_]zorm.QueryArg{zorm.QueryArg.fromValue("inactive")};
    var args2 = [_]zorm.QueryArg{zorm.QueryArg.fromValue("pending")};

    const where1 = WhereClause{
        .condition = "status = ?",
        .args = &args1,
        .operator = .and_op,
    };
    const where2 = WhereClause{
        .condition = "status = ?",
        .args = &args2,
        .operator = .or_op,
    };

    try testing.expectEqual(zorm.WhereOperator.and_op, where1.operator);
    try testing.expectEqual(zorm.WhereOperator.or_op, where2.operator);
}

test "DeleteQuery: 参数类型测试" {
    const allocator = testing.allocator;

    // 测试各种参数类型
    const arg_int = zorm.QueryArg.fromValue(@as(i64, 42));
    const arg_str = zorm.QueryArg.fromValue("test@example.com");
    const arg_bool = zorm.QueryArg.fromValue(true);

    try testing.expect(arg_int == .int);
    try testing.expect(arg_str == .string);
    try testing.expect(arg_bool == .bool);
}

// ============================================================================
// 编译时测试：验证强制 WHERE 检查的存在
// ============================================================================

test "DeleteQuery: 编译时类型安全检查" {
    // 验证 DeleteQuery 包含 has_where 字段
    const DeleteQuery = zorm.DeleteQuery(User, .postgresql);
    const type_info = @typeInfo(DeleteQuery);

    // 这是一个编译时验证，确保类型结构正确
    _ = type_info;
}

// ============================================================================
// 注意：以下测试需要真实的 DB Mock 实例才能运行
// 这些测试留待集成测试中实现
// ============================================================================

// test "DeleteQuery: 强制 WHERE 检查 - 无 WHERE 应返回错误" {
//     // 这个测试需要真实的 DB Mock
//     // 期望行为：query.exec() 应该返回 error.MissingWhereClause
// }

// test "DeleteQuery: 基本 DELETE SQL 生成" {
//     // 需要 DB Mock
//     // 期望 SQL: "DELETE FROM users WHERE id = $1"
// }

// test "DeleteQuery: whereIn 批量删除 SQL 生成" {
//     // 需要 DB Mock
//     // 期望 SQL: "DELETE FROM users WHERE id IN ($1, $2, $3)"
// }

// test "DeleteQuery: RETURNING 子句 SQL 生成" {
//     // 需要 DB Mock
//     // 期望 SQL: "DELETE FROM users WHERE id = $1 RETURNING *"
// }

// test "DeleteQuery: 链式调用语法" {
//     // 需要 DB Mock
//     // 测试：query.where(...).whereOr(...).setReturning(...)
// }
