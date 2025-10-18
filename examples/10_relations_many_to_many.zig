//! Many-to-Many 关系示例（多对多）
//!
//! 学习目标:
//! - 理解多对多关系（Posts <-> Tags）
//! - 使用中间表（post_tags）管理关系
//! - 查询和操作多对多关系
//!
//! 对应功能需求: FR5
//! 难度: 高级

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 10: Many-to-Many 关系（多对多）===\n\n", .{});

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

    // 示例 1: 为文章添加标签
    try attachTagsToPost(&conn);

    // 示例 2: 查询文章的所有标签
    try queryPostWithTags(&conn);

    // 示例 3: 查询标签下的所有文章
    try queryTagWithPosts(&conn);

    // 示例 4: 移除文章的标签
    try detachTagsFromPost(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn attachTagsToPost(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 为文章添加标签\n", .{});

    const post_id: i64 = 1;

    // 先查询文章信息
    var post_opt = try conn.row(
        "SELECT id, title FROM zorm_examples.posts WHERE id = $1",
        .{post_id},
    );

    if (post_opt) |*post| {
        defer post.deinit() catch {};
        const title = post.get([]const u8, 1);
        std.debug.print("  文章: [{d}] {s}\n", .{ post_id, title });

        // why: 使用 ON CONFLICT DO NOTHING 避免重复添加标签
        _ = try conn.exec(
            \\INSERT INTO zorm_examples.post_tags (post_id, tag_id)
            \\SELECT $1, id FROM zorm_examples.tags
            \\WHERE name IN ('Zig', 'Database', 'Tutorial')
            \\ON CONFLICT (post_id, tag_id) DO NOTHING
        ,
            .{post_id},
        );

        std.debug.print("  ✓ 标签已添加\n\n", .{});
    }
}

fn queryPostWithTags(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: 查询文章的所有标签\n", .{});

    const post_id: i64 = 1;

    // 先查询文章信息
    var post_opt = try conn.row(
        "SELECT id, title, status FROM zorm_examples.posts WHERE id = $1",
        .{post_id},
    );

    if (post_opt) |*post| {
        defer post.deinit() catch {};
        const id = post.get(i64, 0);
        const title = post.get([]const u8, 1);
        const status = post.get([]const u8, 2);

        std.debug.print("  文章信息:\n", .{});
        std.debug.print("    ID: {d}\n", .{id});
        std.debug.print("    标题: {s}\n", .{title});
        std.debug.print("    状态: {s}\n", .{status});

        // why: 通过中间表 JOIN 查询多对多关系
        var tags = try conn.query(
            \\SELECT t.id, t.name
            \\FROM zorm_examples.tags t
            \\INNER JOIN zorm_examples.post_tags pt ON t.id = pt.tag_id
            \\WHERE pt.post_id = $1
            \\ORDER BY t.name
        ,
            .{post_id},
        );
        defer tags.deinit();

        std.debug.print("  标签列表:\n", .{});
        var count: usize = 0;
        while (try tags.next()) |tag| {
            const tag_id = tag.get(i64, 0);
            const tag_name = tag.get([]const u8, 1);
            std.debug.print("    [{d}] {s}\n", .{ tag_id, tag_name });
            count += 1;
        }
        std.debug.print("  总计: {d} 个标签\n\n", .{count});
    }
}

fn queryTagWithPosts(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: 查询标签下的所有文章\n", .{});

    const tag_name = "Zig";

    // 先查询标签信息
    var tag_opt = try conn.row(
        "SELECT id, name FROM zorm_examples.tags WHERE name = $1",
        .{tag_name},
    );

    if (tag_opt) |*tag| {
        defer tag.deinit() catch {};
        const tag_id = tag.get(i64, 0);
        const name = tag.get([]const u8, 1);

        std.debug.print("  标签: [{d}] {s}\n", .{ tag_id, name });

        // why: 反向查询多对多关系
        var posts = try conn.query(
            \\SELECT p.id, p.title, p.status, u.name as author
            \\FROM zorm_examples.posts p
            \\INNER JOIN zorm_examples.post_tags pt ON p.id = pt.post_id
            \\INNER JOIN zorm_examples.users u ON p.user_id = u.id
            \\WHERE pt.tag_id = $1
            \\ORDER BY p.created_at DESC
        ,
            .{tag_id},
        );
        defer posts.deinit();

        std.debug.print("  文章列表:\n", .{});
        var count: usize = 0;
        while (try posts.next()) |post| {
            const post_id = post.get(i64, 0);
            const title = post.get([]const u8, 1);
            const status = post.get([]const u8, 2);
            const author = post.get([]const u8, 3);

            std.debug.print("    [{d}] {s} ({s}) - by {s}\n", .{ post_id, title, status, author });
            count += 1;
        }
        std.debug.print("  总计: {d} 篇文章\n\n", .{count});
    } else {
        std.debug.print("  未找到标签\n\n", .{});
    }
}

fn detachTagsFromPost(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 4: 移除文章的标签\n", .{});

    const post_id: i64 = 1;

    // 先查询当前标签数量
    var count_before_opt = try conn.row(
        "SELECT COUNT(*) FROM zorm_examples.post_tags WHERE post_id = $1",
        .{post_id},
    );

    var count_before: i64 = 0;
    if (count_before_opt) |*result| {
        defer result.deinit() catch {};
        count_before = result.get(i64, 0);
        std.debug.print("  移除前标签数: {d}\n", .{count_before});
    }

    // why: 从中间表删除关系，不影响标签本身
    const affected = try conn.exec(
        \\DELETE FROM zorm_examples.post_tags
        \\WHERE post_id = $1
        \\  AND tag_id IN (
        \\      SELECT id FROM zorm_examples.tags WHERE name = 'Tutorial'
        \\  )
    ,
        .{post_id},
    );

    if (affected) |rows| {
        std.debug.print("  ✓ 移除了 {d} 个标签关联\n", .{rows});
    }

    // 验证结果
    var count_after_opt = try conn.row(
        "SELECT COUNT(*) FROM zorm_examples.post_tags WHERE post_id = $1",
        .{post_id},
    );

    if (count_after_opt) |*result| {
        defer result.deinit() catch {};
        const count_after = result.get(i64, 0);
        std.debug.print("  移除后标签数: {d}\n", .{count_after});
    }

    // 验证标签本身仍然存在
    var tag_exists_opt = try conn.row(
        "SELECT COUNT(*) FROM zorm_examples.tags WHERE name = 'Tutorial'",
        .{},
    );

    if (tag_exists_opt) |*result| {
        defer result.deinit() catch {};
        const tag_count = result.get(i64, 0);
        if (tag_count > 0) {
            std.debug.print("  ✓ 标签本身仍然存在（只删除了关联）\n", .{});
        }
    }
}
