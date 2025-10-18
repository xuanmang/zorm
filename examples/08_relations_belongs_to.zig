//! Belongs-To 关系示例（多对一）
//!
//! 学习目标:
//! - 理解多对一关系（Post -> User）
//! - 使用 JOIN 查询关联数据
//! - 处理外键关系
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

    std.debug.print("=== ZORM 示例 08: Belongs-To 关系（多对一）===\n\n", .{});

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

    // 示例 1: 查询文章及其作者
    try queryPostWithAuthor(&conn);

    // 示例 2: 查询多篇文章及其作者
    try queryPostsWithAuthors(&conn);

    // 示例 3: 创建文章时验证作者存在
    try createPostWithAuthorValidation(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn queryPostWithAuthor(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 查询单篇文章及其作者\n", .{});

    // why: INNER JOIN 确保只返回有作者的文章
    var result_opt = try conn.row(
        \\SELECT
        \\    p.id as post_id,
        \\    p.title,
        \\    p.content,
        \\    p.status,
        \\    u.id as author_id,
        \\    u.name as author_name,
        \\    u.email as author_email
        \\FROM zorm_examples.posts p
        \\INNER JOIN zorm_examples.users u ON p.user_id = u.id
        \\WHERE p.id = $1
    ,
        .{1},
    );

    if (result_opt) |*result| {
        defer result.deinit() catch {};

        const post_id = result.get(i64, 0);
        const title = result.get([]const u8, 1);
        const content = result.get([]const u8, 2);
        const status = result.get([]const u8, 3);
        const author_id = result.get(i64, 4);
        const author_name = result.get([]const u8, 5);
        const author_email = result.get([]const u8, 6);

        std.debug.print("  文章信息:\n", .{});
        std.debug.print("    ID: {d}\n", .{post_id});
        std.debug.print("    标题: {s}\n", .{title});
        std.debug.print("    内容: {s}\n", .{content});
        std.debug.print("    状态: {s}\n", .{status});
        std.debug.print("  作者信息:\n", .{});
        std.debug.print("    ID: {d}\n", .{author_id});
        std.debug.print("    姓名: {s}\n", .{author_name});
        std.debug.print("    邮箱: {s}\n", .{author_email});
    } else {
        std.debug.print("  未找到文章\n", .{});
    }
    std.debug.print("\n", .{});
}

fn queryPostsWithAuthors(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: 查询多篇文章及其作者\n", .{});

    var result = try conn.query(
        \\SELECT
        \\    p.id,
        \\    p.title,
        \\    p.status,
        \\    u.id as author_id,
        \\    u.name as author_name
        \\FROM zorm_examples.posts p
        \\INNER JOIN zorm_examples.users u ON p.user_id = u.id
        \\WHERE p.status = $1
        \\ORDER BY p.created_at DESC
        \\LIMIT 5
    ,
        .{"published"},
    );
    defer result.deinit();

    std.debug.print("  已发布文章列表:\n", .{});
    var count: usize = 0;
    while (try result.next()) |row| {
        const post_id = row.get(i64, 0);
        const title = row.get([]const u8, 1);
        const status = row.get([]const u8, 2);
        const author_id = row.get(i64, 3);
        const author_name = row.get([]const u8, 4);

        std.debug.print("    [{d}] {s} ({s})\n", .{ post_id, title, status });
        std.debug.print("         作者: [{d}] {s}\n", .{ author_id, author_name });
        count += 1;
    }
    std.debug.print("  总计: {d} 篇\n\n", .{count});
}

fn createPostWithAuthorValidation(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: 创建文章时验证作者存在\n", .{});

    const author_id: i64 = 1;

    // why: 先验证作者是否存在，避免外键约束错误
    var author_check_opt = try conn.row(
        "SELECT id, name FROM zorm_examples.users WHERE id = $1",
        .{author_id},
    );

    if (author_check_opt) |*author_check| {
        defer author_check.deinit() catch {};
        const author_name = author_check.get([]const u8, 1);
        std.debug.print("  ✓ 作者存在: [{d}] {s}\n", .{ author_id, author_name });

        // 创建文章
        var insert_result_opt = try conn.row(
            \\INSERT INTO zorm_examples.posts (user_id, title, content, status, created_at, updated_at)
            \\VALUES ($1, $2, $3, $4, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
            \\RETURNING id, title
        ,
            .{ author_id, "New Post with Validation", "Content here", "draft" },
        );

        if (insert_result_opt) |*insert_result| {
            defer insert_result.deinit() catch {};
            const post_id = insert_result.get(i64, 0);
            const title = insert_result.get([]const u8, 1);
            std.debug.print("  ✓ 文章创建成功: [{d}] {s}\n", .{ post_id, title });

            // 验证关系
            var verify_opt = try conn.row(
                \\SELECT p.title, u.name
                \\FROM zorm_examples.posts p
                \\INNER JOIN zorm_examples.users u ON p.user_id = u.id
                \\WHERE p.id = $1
            ,
                .{post_id},
            );

            if (verify_opt) |*verify| {
                defer verify.deinit() catch {};
                const post_title = verify.get([]const u8, 0);
                const author_name_verify = verify.get([]const u8, 1);
                std.debug.print("  ✓ 关系验证成功: \"{s}\" belongs to \"{s}\"\n", .{ post_title, author_name_verify });
            }
        }
    } else {
        std.debug.print("  ❌ 作者不存在，无法创建文章\n", .{});
    }
}
