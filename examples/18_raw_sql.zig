//! 原始 SQL 示例
//!
//! 学习目标:
//! - 直接执行原始 SQL
//! - SQL 注入防护
//! - 复杂 SQL 语句
//! - 参数化查询
//!
//! 对应功能需求: FR10
//! 难度: 基础

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 18: 原始 SQL ===\n\n", .{});

    const db_config = config.Config.default();
    var pool = try pg.Pool.init(allocator, .{
        .size = 5,
        .connect = .{
            .host = db_config.host,
            .port = db_config.port,
        },
        .auth = .{
            .username = db_config.user,
            .password = db_config.password,
            .database = db_config.database,
        },
    });
    defer pool.deinit();

    var conn = try pool.acquire();
    defer conn.release();

    // 示例 1: 基础原始 SQL
    try basicRawSQL(&conn);

    // 示例 2: 参数化查询（防注入）
    try parameterizedQuery(&conn);

    // 示例 3: 复杂 SQL 语句
    try complexSQL(&conn);

    // 示例 4: SQL 注入演示（安全版）
    try sqlInjectionDemo(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn basicRawSQL(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 基础原始 SQL\n", .{});

    // why: 直接执行 SQL，完全控制查询逻辑
    var result = try conn.query(
        \\SELECT
        \\    u.id,
        \\    u.name,
        \\    u.email,
        \\    COUNT(p.id) as post_count
        \\FROM zorm_examples.users u
        \\LEFT JOIN zorm_examples.posts p ON u.id = p.user_id
        \\GROUP BY u.id, u.name, u.email
        \\ORDER BY post_count DESC
        \\LIMIT 3
    ,
        .{},
    );
    defer result.deinit();

    std.debug.print("  Top 3 活跃用户:\n", .{});
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const name = row.get([]const u8, 1);
        const email = row.get([]const u8, 2);
        const post_count = row.get(i64, 3);

        std.debug.print("    [{d}] {s} <{s}> - {d} 篇文章\n", .{ id, name, email, post_count });
    }
    std.debug.print("\n", .{});
}

fn parameterizedQuery(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: 参数化查询（防 SQL 注入）\n", .{});

    const user_input = "Alice"; // 模拟用户输入

    // why: 使用 $1, $2 占位符防止 SQL 注入
    var result = try conn.query(
        \\SELECT id, name, email
        \\FROM zorm_examples.users
        \\WHERE name LIKE $1
        \\ORDER BY id
    ,
        .{user_input},
    );
    defer result.deinit();

    std.debug.print("  搜索用户名包含 \"{s}\" 的用户:\n", .{user_input});
    var count: usize = 0;
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const name = row.get([]const u8, 1);
        const email = row.get([]const u8, 2);

        std.debug.print("    [{d}] {s} <{s}>\n", .{ id, name, email });
        count += 1;
    }

    if (count == 0) {
        std.debug.print("    未找到匹配的用户\n", .{});
    }

    std.debug.print("  ✓ 参数化查询安全执行\n\n", .{});
}

fn complexSQL(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: 复杂 SQL 语句\n", .{});

    // why: 使用原始 SQL 执行复杂分析查询
    var result_opt = try conn.row(
        \\WITH post_stats AS (
        \\    SELECT
        \\        user_id,
        \\        COUNT(*) as total_posts,
        \\        COUNT(CASE WHEN status = 'published' THEN 1 END) as published_posts,
        \\        AVG(CASE WHEN published_at IS NOT NULL
        \\            THEN EXTRACT(EPOCH FROM NOW()) - published_at
        \\            ELSE NULL END) / 86400.0 as avg_days_since_publish
        \\    FROM zorm_examples.posts
        \\    GROUP BY user_id
        \\)
        \\SELECT
        \\    u.id,
        \\    u.name,
        \\    COALESCE(ps.total_posts, 0) as total_posts,
        \\    COALESCE(ps.published_posts, 0) as published_posts,
        \\    COALESCE(ps.avg_days_since_publish, 0) as avg_days
        \\FROM zorm_examples.users u
        \\LEFT JOIN post_stats ps ON u.id = ps.user_id
        \\ORDER BY total_posts DESC
        \\LIMIT 1
    ,
        .{},
    );

    if (result_opt) |*result| {
        defer result.deinit() catch {};

        const id = result.get(i64, 0);
        const name = result.get([]const u8, 1);
        const total_posts = result.get(i64, 2);
        const published_posts = result.get(i64, 3);
        const avg_days = result.get(f64, 4);

        std.debug.print("  最活跃用户统计:\n", .{});
        std.debug.print("    ID: {d}\n", .{id});
        std.debug.print("    姓名: {s}\n", .{name});
        std.debug.print("    总文章数: {d}\n", .{total_posts});
        std.debug.print("    已发布: {d}\n", .{published_posts});
        std.debug.print("    平均发布天数: {d:.1}\n\n", .{avg_days});
    }
}

fn sqlInjectionDemo(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 4: SQL 注入防护演示\n", .{});

    // 危险的用户输入（包含 SQL 注入尝试）
    const malicious_input = "' OR '1'='1"; // 尝试注入

    std.debug.print("  恶意输入: {s}\n", .{malicious_input});

    // why: 使用参数化查询，恶意输入会被当作普通字符串
    var result = try conn.query(
        \\SELECT id, name, email
        \\FROM zorm_examples.users
        \\WHERE name = $1
    ,
        .{malicious_input},
    );
    defer result.deinit();

    var count: usize = 0;
    while (try result.next()) |_| {
        count += 1;
    }

    std.debug.print("  查询结果: {d} 条\n", .{count});
    std.debug.print("  ✓ SQL 注入被防护（恶意输入被当作普通字符串）\n", .{});

    std.debug.print("\n安全提示:\n", .{});
    std.debug.print("  ❌ 错误: SELECT * FROM users WHERE name = '{s}'\n", .{malicious_input});
    std.debug.print("  ✓ 正确: SELECT * FROM users WHERE name = $1\n", .{});
    std.debug.print("  始终使用参数化查询，永远不要拼接 SQL！\n", .{});
}
