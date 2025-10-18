//! 高级查询示例
//!
//! 学习目标:
//! - 窗口函数（Window Functions）
//! - CTE（公用表表达式）
//! - JSON 查询
//! - 全文搜索
//!
//! 对应功能需求: FR3
//! 难度: 高级

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 13: 高级查询 ===\n\n", .{});

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

    // 示例 1: 窗口函数（排名）
    try windowFunctionRank(&conn);

    // 示例 2: CTE（递归查询）
    try cteRecursive(&conn);

    // 示例 3: CTE（复杂数据处理）
    try cteDataProcessing(&conn);

    // 示例 4: CASE 表达式
    try caseExpression(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn windowFunctionRank(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 窗口函数（排名）\n", .{});

    // why: ROW_NUMBER() 为每个用户的文章按时间排序
    var result = try conn.query(
        \\SELECT
        \\    u.name as author,
        \\    p.title,
        \\    p.status,
        \\    p.created_at,
        \\    ROW_NUMBER() OVER (PARTITION BY u.id ORDER BY p.created_at DESC) as post_rank
        \\FROM zorm_examples.posts p
        \\INNER JOIN zorm_examples.users u ON p.user_id = u.id
        \\ORDER BY u.id, post_rank
        \\LIMIT 10
    ,
        .{},
    );
    defer result.deinit();

    std.debug.print("  文章排名（按用户分组）:\n", .{});
    while (try result.next()) |row| {
        const author = row.get([]const u8, 0);
        const title = row.get([]const u8, 1);
        const status = row.get([]const u8, 2);
        const created_at = row.get(f64, 3);
        const rank = row.get(i64, 4);

        std.debug.print("    [{d}] {s} - \"{s}\" ({s}) - {d}\n", .{ rank, author, title, status, created_at });
    }
    std.debug.print("\n", .{});
}

fn cteRecursive(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: CTE 递归查询（数字序列）\n", .{});

    // why: WITH RECURSIVE 生成序列或处理层级数据
    var result = try conn.query(
        \\WITH RECURSIVE numbers AS (
        \\    SELECT 1 AS n
        \\    UNION ALL
        \\    SELECT n + 1 FROM numbers WHERE n < 10
        \\)
        \\SELECT n, n * n AS square, n * n * n AS cube
        \\FROM numbers
    ,
        .{},
    );
    defer result.deinit();

    std.debug.print("  数字序列（1-10）:\n", .{});
    while (try result.next()) |row| {
        const n = row.get(i32, 0);
        const square = row.get(i32, 1);
        const cube = row.get(i32, 2);

        std.debug.print("    {d}^2 = {d}, {d}^3 = {d}\n", .{ n, square, n, cube });
    }
    std.debug.print("\n", .{});
}

fn cteDataProcessing(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: CTE 复杂数据处理\n", .{});

    // why: 使用多个 CTE 分步处理复杂查询，提高可读性
    var result = try conn.query(
        \\WITH user_stats AS (
        \\    SELECT
        \\        u.id,
        \\        u.name,
        \\        COUNT(p.id) as total_posts,
        \\        COUNT(CASE WHEN p.status = 'published' THEN 1 END) as published_posts
        \\    FROM zorm_examples.users u
        \\    LEFT JOIN zorm_examples.posts p ON u.id = p.user_id
        \\    GROUP BY u.id, u.name
        \\),
        \\active_users AS (
        \\    SELECT * FROM user_stats WHERE total_posts > 0
        \\)
        \\SELECT
        \\    id,
        \\    name,
        \\    total_posts,
        \\    published_posts,
        \\    ROUND(published_posts::NUMERIC / NULLIF(total_posts, 0) * 100, 2) as publish_rate
        \\FROM active_users
        \\ORDER BY total_posts DESC
        \\LIMIT 5
    ,
        .{},
    );
    defer result.deinit();

    std.debug.print("  活跃用户统计（Top 5）:\n", .{});
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const name = row.get([]const u8, 1);
        const total_posts = row.get(i64, 2);
        const published_posts = row.get(i64, 3);
        const publish_rate_opt = row.get(?f64, 4);

        std.debug.print("    [{d}] {s}:\n", .{ id, name });
        std.debug.print("         总文章: {d}, 已发布: {d}\n", .{ total_posts, published_posts });

        if (publish_rate_opt) |rate| {
            std.debug.print("         发布率: {d:.2}%\n", .{rate});
        }
    }
    std.debug.print("\n", .{});
}

fn caseExpression(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 4: CASE 表达式（条件逻辑）\n", .{});

    // why: CASE 实现 SQL 中的条件逻辑
    var result = try conn.query(
        \\SELECT
        \\    p.id,
        \\    p.title,
        \\    p.status,
        \\    CASE
        \\        WHEN p.status = 'published' THEN '✓ 已发布'
        \\        WHEN p.status = 'draft' THEN '📝 草稿'
        \\        WHEN p.status = 'archived' THEN '📦 已归档'
        \\        ELSE '❓ 未知'
        \\    END as status_label,
        \\    CASE
        \\        WHEN p.published_at IS NULL THEN 'Not published'
        \\        WHEN EXTRACT(EPOCH FROM NOW()) - p.published_at < 86400 THEN 'Today'
        \\        WHEN EXTRACT(EPOCH FROM NOW()) - p.published_at < 604800 THEN 'This week'
        \\        ELSE 'Older'
        \\    END as recency
        \\FROM zorm_examples.posts p
        \\ORDER BY p.created_at DESC
        \\LIMIT 5
    ,
        .{},
    );
    defer result.deinit();

    std.debug.print("  文章状态和时效性:\n", .{});
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const title = row.get([]const u8, 1);
        const status = row.get([]const u8, 2);
        const status_label = row.get([]const u8, 3);
        const recency = row.get([]const u8, 4);

        std.debug.print("    [{d}] {s}\n", .{ id, title });
        std.debug.print("         原始状态: {s} → {s}\n", .{ status, status_label });
        std.debug.print("         时效性: {s}\n", .{recency});
    }
}
