//! Raw SQL Query Examples
//!
//! 演示如何使用 ZORM 的 Raw SQL 查询功能处理查询构建器无法覆盖的复杂场景。
//!
//! 本示例展示:
//! - 窗口函数查询 (Window Functions)
//! - CTE (Common Table Expressions)
//! - 复杂聚合查询
//! - Raw SQL 在事务中的使用
//!
//! ⚠️ 安全警告:
//! - 始终使用参数绑定 ($1, $2, ...)
//! - 永远不要拼接用户输入到 SQL 字符串

const std = @import("std");
const zorm = @import("zorm");

// 示例数据结构
const UserWithRank = struct {
    id: i64,
    name: []const u8,
    post_count: i64,
    rank: i64,
};

const UserStats = struct {
    name: []const u8,
    post_count: i64,
    avg_views: f64,
};

/// 窗口函数示例
///
/// 使用 RANK() 窗口函数按帖子数量排名用户
pub fn windowFunctionExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== 窗口函数示例 ===\n", .{});

    // 示例 SQL (实际使用时需要真实数据库连接)
    const sql =
        \\SELECT
        \\  u.id,
        \\  u.name,
        \\  COUNT(p.id) as post_count,
        \\  RANK() OVER (ORDER BY COUNT(p.id) DESC) as rank
        \\FROM users u
        \\LEFT JOIN posts p ON p.user_id = u.id
        \\GROUP BY u.id, u.name
        \\HAVING COUNT(p.id) > $1
        \\ORDER BY rank
        \\LIMIT $2
    ;

    std.debug.print("SQL:\n{s}\n", .{sql});
    std.debug.print("参数: min_posts=5, limit=10\n", .{});

    // 实际使用时:
    // var query = try db.newRaw(sql, .{ 5, 10 });
    // defer query.deinit();
    //
    // var results: std.ArrayList(UserWithRank) = .{};
    // defer results.deinit(allocator);
    //
    // try query.scan(UserWithRank, &results);
    //
    // for (results.items) |user| {
    //     std.debug.print("#{} - {} ({} posts)\n", .{
    //         user.rank, user.name, user.post_count
    //     });
    // }

    _ = allocator;
}

/// CTE (Common Table Expression) 示例
///
/// 使用 WITH 子句创建临时结果集
pub fn cteExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== CTE 示例 ===\n", .{});

    const sql =
        \\WITH active_users AS (
        \\  SELECT id, name FROM users WHERE is_active = $1
        \\),
        \\user_stats AS (
        \\  SELECT
        \\    au.id,
        \\    au.name,
        \\    COUNT(p.id) as post_count,
        \\    AVG(p.views) as avg_views
        \\  FROM active_users au
        \\  LEFT JOIN posts p ON p.user_id = au.id
        \\  GROUP BY au.id, au.name
        \\)
        \\SELECT name, post_count, avg_views
        \\FROM user_stats
        \\WHERE post_count > $2
        \\ORDER BY post_count DESC
    ;

    std.debug.print("SQL:\n{s}\n", .{sql});
    std.debug.print("参数: is_active=true, min_posts=10\n", .{});

    // 实际使用时:
    // var query = try db.newRaw(sql, .{ true, 10 });
    // defer query.deinit();
    //
    // var results: std.ArrayList(UserStats) = .{};
    // defer results.deinit(allocator);
    //
    // try query.scan(UserStats, &results);

    _ = allocator;
}

/// Raw SQL 执行 DML 示例
///
/// 执行 UPDATE/INSERT/DELETE 等不返回结果集的语句
pub fn dmlExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== DML 执行示例 ===\n", .{});

    const update_sql =
        \\UPDATE users
        \\SET last_login = CURRENT_TIMESTAMP,
        \\    login_count = login_count + 1
        \\WHERE id = $1
    ;

    std.debug.print("UPDATE SQL:\n{s}\n", .{update_sql});
    std.debug.print("参数: user_id=42\n", .{});

    // 实际使用时:
    // var query = try db.newRaw(update_sql, .{42});
    // defer query.deinit();
    //
    // const result = try query.exec();
    // std.debug.print("更新了 {} 行\n", .{result.rows_affected});

    _ = allocator;
}

/// 事务中的 Raw SQL 示例
///
/// 在事务上下文中执行复杂 SQL
pub fn transactionExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== 事务中的 Raw SQL 示例 ===\n", .{});

    const transfer_sql =
        \\UPDATE accounts
        \\SET balance = balance + $1
        \\WHERE user_id = $2
        \\RETURNING balance
    ;

    std.debug.print("转账 SQL:\n{s}\n", .{transfer_sql});

    // 实际使用时:
    // var tx = try db.beginTx(.{});
    // defer tx.deinit();
    // errdefer tx.rollback() catch {};
    //
    // // 从账户 A 扣款
    // var debit = try tx.newRaw(transfer_sql, .{ -100.0, user_a_id });
    // defer debit.deinit();
    // const debit_result = try debit.exec();
    //
    // // 向账户 B 存款
    // var credit = try tx.newRaw(transfer_sql, .{ 100.0, user_b_id });
    // defer credit.deinit();
    // const credit_result = try credit.exec();
    //
    // try tx.commit();

    _ = allocator;
}

/// 安全警告示例
///
/// 展示正确和错误的 SQL 使用方式
pub fn securityExample() void {
    std.debug.print("\n=== 安全警告示例 ===\n", .{});

    std.debug.print("❌ 错误 - SQL 注入风险:\n", .{});
    std.debug.print("  const user_input = \"'; DROP TABLE users; --\";\n", .{});
    std.debug.print("  const sql = try fmt.allocPrint(\n", .{});
    std.debug.print("    \"SELECT * FROM users WHERE name = '{{s}}'\",\n", .{});
    std.debug.print("    .{{user_input}}\n", .{});
    std.debug.print("  );\n\n", .{});

    std.debug.print("✅ 正确 - 使用参数绑定:\n", .{});
    std.debug.print("  const user_input = \"'; DROP TABLE users; --\";\n", .{});
    std.debug.print("  const sql = \"SELECT * FROM users WHERE name = $1\";\n", .{});
    std.debug.print("  var query = try db.newRaw(sql, .{{user_input}});\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("==============================================\n", .{});
    std.debug.print("ZORM Raw SQL Query Examples\n", .{});
    std.debug.print("==============================================\n", .{});

    try windowFunctionExample(allocator);
    try cteExample(allocator);
    try dmlExample(allocator);
    try transactionExample(allocator);
    securityExample();

    std.debug.print("\n==============================================\n", .{});
    std.debug.print("示例完成！\n", .{});
    std.debug.print("\n注意: 这些是示例代码，需要真实的数据库连接才能执行。\n", .{});
    std.debug.print("==============================================\n", .{});
}
