//! Has-Many 关系示例（一对多）
//!
//! 学习目标:
//! - 理解一对多关系（User -> Posts）
//! - 查询用户及其所有文章
//! - 处理集合关系
//!
//! 对应功能需求: FR5
//! 难度: 中级

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 09: Has-Many 关系（一对多）===\n\n", .{});

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

    // 示例 1: 查询用户及其所有文章
    try queryUserWithPosts(&conn);

    // 示例 2: 统计用户的文章数量
    try countUserPosts(&conn);

    // 示例 3: 批量查询多个用户及其文章
    try queryUsersWithPostCounts(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn queryUserWithPosts(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 查询用户及其所有文章\n", .{});

    const user_id: i64 = 1;

    // 先查询用户信息
    var user_opt = try conn.row(
        "SELECT id, name, email FROM zorm_examples.users WHERE id = $1",
        .{user_id},
    );

    if (user_opt) |*user| {
        defer user.deinit() catch {};
        const id = user.get(i64, 0);
        const name = user.get([]const u8, 1);
        const email = user.get([]const u8, 2);

        std.debug.print("  用户信息:\n", .{});
        std.debug.print("    ID: {d}\n", .{id});
        std.debug.print("    姓名: {s}\n", .{name});
        std.debug.print("    邮箱: {s}\n", .{email});

        // why: 查询该用户的所有文章（一对多关系）
        var posts = try conn.query(
            \\SELECT id, title, status, created_at
            \\FROM zorm_examples.posts
            \\WHERE user_id = $1
            \\ORDER BY created_at DESC
        ,
            .{user_id},
        );
        defer posts.deinit();

        std.debug.print("  文章列表:\n", .{});
        var count: usize = 0;
        while (try posts.next()) |post| {
            const post_id = post.get(i64, 0);
            const title = post.get([]const u8, 1);
            const status = post.get([]const u8, 2);
            const created_at = post.get(f64, 3);

            std.debug.print("    [{d}] {s} ({s}) - created: {d}\n", .{ post_id, title, status, created_at });
            count += 1;
        }
        std.debug.print("  总计: {d} 篇文章\n\n", .{count});
    } else {
        std.debug.print("  未找到用户\n\n", .{});
    }
}

fn countUserPosts(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: 统计用户的文章数量\n", .{});

    // why: 使用 COUNT 聚合函数统计一对多关系中的记录数
    var result = try conn.query(
        \\SELECT
        \\    u.id,
        \\    u.name,
        \\    COUNT(p.id) as total_posts,
        \\    COUNT(CASE WHEN p.status = 'published' THEN 1 END) as published_posts,
        \\    COUNT(CASE WHEN p.status = 'draft' THEN 1 END) as draft_posts
        \\FROM zorm_examples.users u
        \\LEFT JOIN zorm_examples.posts p ON u.id = p.user_id
        \\GROUP BY u.id, u.name
        \\HAVING COUNT(p.id) > 0
        \\ORDER BY total_posts DESC
    ,
        .{},
    );
    defer result.deinit();

    std.debug.print("  用户文章统计:\n", .{});
    while (try result.next()) |row| {
        const user_id = row.get(i64, 0);
        const user_name = row.get([]const u8, 1);
        const total_posts = row.get(i64, 2);
        const published_posts = row.get(i64, 3);
        const draft_posts = row.get(i64, 4);

        std.debug.print("    [{d}] {s}:\n", .{ user_id, user_name });
        std.debug.print("         总文章数: {d}\n", .{total_posts});
        std.debug.print("         已发布: {d}\n", .{published_posts});
        std.debug.print("         草稿: {d}\n", .{draft_posts});
    }
    std.debug.print("\n", .{});
}

fn queryUsersWithPostCounts(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: 批量查询用户及文章统计\n", .{});

    // why: 使用子查询优化批量查询性能
    var result = try conn.query(
        \\SELECT
        \\    u.id,
        \\    u.name,
        \\    u.email,
        \\    (SELECT COUNT(*) FROM zorm_examples.posts p WHERE p.user_id = u.id) as post_count,
        \\    (SELECT COUNT(*) FROM zorm_examples.posts p WHERE p.user_id = u.id AND p.status = 'published') as published_count
        \\FROM zorm_examples.users u
        \\ORDER BY u.id
        \\LIMIT 10
    ,
        .{},
    );
    defer result.deinit();

    std.debug.print("  用户列表（含文章统计）:\n", .{});
    while (try result.next()) |row| {
        const user_id = row.get(i64, 0);
        const user_name = row.get([]const u8, 1);
        const user_email = row.get([]const u8, 2);
        const post_count = row.get(i64, 3);
        const published_count = row.get(i64, 4);

        std.debug.print("    [{d}] {s} <{s}>\n", .{ user_id, user_name, user_email });
        std.debug.print("         文章: {d} 篇 ({d} 已发布)\n", .{ post_count, published_count });
    }
}
