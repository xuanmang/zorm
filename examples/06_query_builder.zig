//! 查询构建示例
//!
//! 学习目标:
//! - 构建复杂 SQL 查询
//! - JOIN 查询
//! - 子查询
//! - 查询优化技巧
//!
//! 注意: ZORM 查询构建器尚未实现，此示例展示 SQL 构建模式
//!
//! 对应功能需求: FR3
//! 难度: 中级

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 06: 查询构建 ===\n\n", .{});

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

    // 示例 1: 复杂 WHERE 条件
    try complexWhereQuery(&conn);

    // 示例 2: JOIN 查询
    try joinQuery(&conn);

    // 示例 3: 聚合和分组
    try aggregateQuery(&conn);

    // 示例 4: 子查询
    try subquery(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn complexWhereQuery(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 复杂 WHERE 条件\n", .{});

    // 多条件组合查询
    var result = try conn.query(
        \\SELECT id, name, email
        \\FROM zorm_examples.users
        \\WHERE (name LIKE $1 OR email LIKE $2)
        \\  AND created_at > $3
        \\ORDER BY created_at DESC
        \\LIMIT 10
    ,
        .{ "%Alice%", "%example.com%", 0 },
    );
    defer result.deinit();

    std.debug.print("  查询结果:\n", .{});
    var count: usize = 0;
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const name = row.get([]const u8, 1);
        const email = row.get([]const u8, 2);
        std.debug.print("    [{d}] {s} <{s}>\n", .{ id, name, email });
        count += 1;
    }
    std.debug.print("  总计: {d} 条\n\n", .{count});
}

fn joinQuery(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: JOIN 查询\n", .{});

    // INNER JOIN 查询用户和其文章
    var result = try conn.query(
        \\SELECT
        \\    u.id as user_id,
        \\    u.name as user_name,
        \\    p.id as post_id,
        \\    p.title as post_title,
        \\    p.status
        \\FROM zorm_examples.users u
        \\INNER JOIN zorm_examples.posts p ON u.id = p.user_id
        \\WHERE p.status = $1
        \\ORDER BY p.created_at DESC
        \\LIMIT 5
    ,
        .{"published"},
    );
    defer result.deinit();

    std.debug.print("  用户文章列表:\n", .{});
    while (try result.next()) |row| {
        const user_name = row.get([]const u8, 1);
        const post_id = row.get(i64, 2);
        const post_title = row.get([]const u8, 3);
        const status = row.get([]const u8, 4);

        std.debug.print("    [{d}] {s} by {s} ({s})\n", .{ post_id, post_title, user_name, status });
    }
    std.debug.print("\n", .{});
}

fn aggregateQuery(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: 聚合和分组\n", .{});

    // 统计每个用户的文章数
    var result = try conn.query(
        \\SELECT
        \\    u.id,
        \\    u.name,
        \\    COUNT(p.id) as post_count,
        \\    COUNT(CASE WHEN p.status = 'published' THEN 1 END) as published_count
        \\FROM zorm_examples.users u
        \\LEFT JOIN zorm_examples.posts p ON u.id = p.user_id
        \\GROUP BY u.id, u.name
        \\HAVING COUNT(p.id) > 0
        \\ORDER BY post_count DESC
    ,
        .{},
    );
    defer result.deinit();

    std.debug.print("  用户文章统计:\n", .{});
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const name = row.get([]const u8, 1);
        const post_count = row.get(i64, 2);
        const published_count = row.get(i64, 3);

        std.debug.print("    [{d}] {s}: {d} 篇文章 ({d} 已发布)\n", .{ id, name, post_count, published_count });
    }
    std.debug.print("\n", .{});
}

fn subquery(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 4: 子查询\n", .{});

    // 查询拥有最多文章的用户
    var result_opt = try conn.row(
        \\SELECT
        \\    u.id,
        \\    u.name,
        \\    u.email,
        \\    (SELECT COUNT(*) FROM zorm_examples.posts p WHERE p.user_id = u.id) as post_count
        \\FROM zorm_examples.users u
        \\WHERE u.id IN (
        \\    SELECT user_id
        \\    FROM zorm_examples.posts
        \\    GROUP BY user_id
        \\    ORDER BY COUNT(*) DESC
        \\    LIMIT 1
        \\)
    ,
        .{},
    );

    if (result_opt) |*result| {
        defer result.deinit() catch {};
        const id = result.get(i64, 0);
        const name = result.get([]const u8, 1);
        const email = result.get([]const u8, 2);
        const post_count = result.get(i64, 3);

        std.debug.print("  文章最多的用户:\n", .{});
        std.debug.print("    ID: {d}\n", .{id});
        std.debug.print("    姓名: {s}\n", .{name});
        std.debug.print("    邮箱: {s}\n", .{email});
        std.debug.print("    文章数: {d}\n", .{post_count});
    } else {
        std.debug.print("  没有找到用户\n", .{});
    }
}
