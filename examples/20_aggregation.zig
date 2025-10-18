//! 聚合查询示例
//!
//! 学习目标:
//! - COUNT, SUM, AVG, MIN, MAX
//! - GROUP BY 分组聚合
//! - HAVING 过滤聚合结果
//! - 多维度聚合分析
//!
//! 对应功能需求: FR12
//! 难度: 中级

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 20: 聚合查询 ===\n\n", .{});

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

    // 示例 1: 基础聚合函数
    try basicAggregation(&conn);

    // 示例 2: GROUP BY 分组聚合
    try groupByAggregation(&conn);

    // 示例 3: HAVING 过滤
    try havingClause(&conn);

    // 示例 4: 多维度聚合分析
    try multidimensionalAggregation(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
    std.debug.print("\n🎉 恭喜！您已完成所有 20 个 ZORM 示例！\n", .{});
}

fn basicAggregation(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 基础聚合函数\n", .{});

    // why: COUNT, SUM, AVG, MIN, MAX 是最常用的聚合函数
    var result_opt = try conn.row(
        \\SELECT
        \\    COUNT(*) as total_users,
        \\    COUNT(DISTINCT email) as unique_emails,
        \\    MIN(created_at) as first_user_created,
        \\    MAX(created_at) as last_user_created
        \\FROM zorm_examples.users
    ,
        .{},
    );

    if (result_opt) |*result| {
        defer result.deinit() catch {};

        const total_users = result.get(i64, 0);
        const unique_emails = result.get(i64, 1);
        const first_created = result.get(f64, 2);
        const last_created = result.get(f64, 3);

        std.debug.print("  用户统计:\n", .{});
        std.debug.print("    总用户数: {d}\n", .{total_users});
        std.debug.print("    唯一邮箱: {d}\n", .{unique_emails});
        std.debug.print("    最早创建: {d}\n", .{first_created});
        std.debug.print("    最晚创建: {d}\n\n", .{last_created});
    }
}

fn groupByAggregation(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: GROUP BY 分组聚合\n", .{});

    // why: GROUP BY 按字段分组，对每组进行聚合计算
    var result = try conn.query(
        \\SELECT
        \\    p.status,
        \\    COUNT(*) as count,
        \\    COUNT(p.published_at) as published_count,
        \\    ROUND(AVG(CASE
        \\        WHEN p.published_at IS NOT NULL
        \\        THEN EXTRACT(EPOCH FROM NOW()) - p.published_at
        \\        ELSE NULL
        \\    END) / 86400.0, 1) as avg_days_since_publish
        \\FROM zorm_examples.posts p
        \\GROUP BY p.status
        \\ORDER BY count DESC
    ,
        .{},
    );
    defer result.deinit();

    std.debug.print("  按状态分组统计:\n", .{});
    while (try result.next()) |row| {
        const status = row.get([]const u8, 0);
        const count = row.get(i64, 1);
        const published_count = row.get(i64, 2);
        const avg_days_opt = row.get(?f64, 3);

        std.debug.print("    {s}:\n", .{status});
        std.debug.print("      总数: {d}\n", .{count});
        std.debug.print("      已发布: {d}\n", .{published_count});

        if (avg_days_opt) |avg_days| {
            std.debug.print("      平均发布天数: {d:.1}\n", .{avg_days});
        } else {
            std.debug.print("      平均发布天数: N/A\n", .{});
        }
    }
    std.debug.print("\n", .{});
}

fn havingClause(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: HAVING 过滤聚合结果\n", .{});

    // why: HAVING 在聚合后过滤，WHERE 在聚合前过滤
    var result = try conn.query(
        \\SELECT
        \\    u.id,
        \\    u.name,
        \\    COUNT(p.id) as post_count,
        \\    COUNT(CASE WHEN p.status = 'published' THEN 1 END) as published_count
        \\FROM zorm_examples.users u
        \\LEFT JOIN zorm_examples.posts p ON u.id = p.user_id
        \\GROUP BY u.id, u.name
        \\HAVING COUNT(p.id) >= 2
        \\ORDER BY post_count DESC
    ,
        .{},
    );
    defer result.deinit();

    std.debug.print("  至少有 2 篇文章的用户:\n", .{});
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const name = row.get([]const u8, 1);
        const post_count = row.get(i64, 2);
        const published_count = row.get(i64, 3);

        std.debug.print("    [{d}] {s}: {d} 篇 ({d} 已发布)\n", .{ id, name, post_count, published_count });
    }
    std.debug.print("\n", .{});
}

fn multidimensionalAggregation(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 4: 多维度聚合分析\n", .{});

    // why: 使用多个维度进行复杂分析
    var result = try conn.query(
        \\SELECT
        \\    u.id as user_id,
        \\    u.name as user_name,
        \\    p.status,
        \\    COUNT(*) as count,
        \\    MIN(p.created_at) as first_post,
        \\    MAX(p.created_at) as last_post
        \\FROM zorm_examples.users u
        \\INNER JOIN zorm_examples.posts p ON u.id = p.user_id
        \\GROUP BY u.id, u.name, p.status
        \\ORDER BY u.id, p.status
    ,
        .{},
    );
    defer result.deinit();

    std.debug.print("  用户 × 状态 多维度聚合:\n", .{});
    var current_user_id: ?i64 = null;

    while (try result.next()) |row| {
        const user_id = row.get(i64, 0);
        const user_name = row.get([]const u8, 1);
        const status = row.get([]const u8, 2);
        const count = row.get(i64, 3);
        const first_post = row.get(f64, 4);
        const last_post = row.get(f64, 5);

        // why: 检测用户切换，打印用户名
        if (current_user_id == null or current_user_id.? != user_id) {
            if (current_user_id != null) {
                std.debug.print("\n", .{});
            }
            std.debug.print("  [{d}] {s}:\n", .{ user_id, user_name });
            current_user_id = user_id;
        }

        std.debug.print("    {s}: {d} 篇 (first: {d:.0}, last: {d:.0})\n", .{ status, count, first_post, last_post });
    }

    std.debug.print("\n说明:\n", .{});
    std.debug.print("  - GROUP BY 可以包含多个字段\n", .{});
    std.debug.print("  - 每个分组维度组合都会生成一行结果\n", .{});
    std.debug.print("  - 适用于多维度数据分析和报表\n", .{});
}
