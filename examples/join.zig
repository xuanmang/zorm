//! JOIN 查询示例 - 演示版本
//!
//! 本示例演示 ZORM 的多表关联查询概念:
//! 1. INNER JOIN - 内连接
//! 2. LEFT JOIN - 左连接
//! 3. 多表 JOIN
//! 4. 聚合 JOIN
//!
//! 注意: 当前版本展示 JOIN 查询的 SQL 语法和使用场景
//!       未来版本将提供完整的 JOIN Query Builder API
//!
//! 运行方式:
//! ```sh
//! zig build run-example-join
//! ```

const std = @import("std");
const zorm = @import("zorm");

const User = struct {
    id: i64 = 0,
    name: []const u8,
    email: []const u8,
    pub const table_name = "users";
};

const Post = struct {
    id: i64 = 0,
    user_id: i64,
    title: []const u8,
    published: bool,
    pub const table_name = "posts";
};

const Comment = struct {
    id: i64 = 0,
    post_id: i64,
    content: []const u8,
    pub const table_name = "comments";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("ZORM JOIN 查询示例\n", .{});
    std.debug.print("=" ** 60 ++ "\n\n", .{});

    // 连接数据库
    std.debug.print("📦 连接数据库: pguser@127.0.0.1:5432/postgres\n\n", .{});
    const dsn = "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres";

    const db = try zorm.connect(allocator, dsn);
    defer db.deinit();

    std.debug.print("✓ 数据库连接成功\n\n", .{});

    // 执行 JOIN 示例
    try demonstrateJoinConcepts(db, allocator);

    std.debug.print("\n✅ 示例执行完成!\n", .{});
}

// JOIN 查询结果结构体
const UserPost = struct {
    user_name: []const u8,
    post_title: []const u8,
};

const UserPostComment = struct {
    user_name: []const u8,
    post_title: []const u8,
    comment_content: []const u8,
};

const UserPostCount = struct {
    user_name: []const u8,
    post_count: i64,
};

fn demonstrateJoinConcepts(db: *zorm.DB(.postgresql), allocator: std.mem.Allocator) !void {
    // ========================================
    // 1. 准备：创建测试表和数据
    // ========================================
    std.debug.print("1️⃣  准备：创建测试表和数据\n", .{});
    {
        // 清理旧表 - 使用高级 API
        {
            var drop = try db.newDropTable(Comment);
            defer drop.deinit();
            _ = drop.ifExists().cascade();
            drop.exec() catch {};
        }
        {
            var drop = try db.newDropTable(Post);
            defer drop.deinit();
            _ = drop.ifExists().cascade();
            drop.exec() catch {};
        }
        {
            var drop = try db.newDropTable(User);
            defer drop.deinit();
            _ = drop.ifExists().cascade();
            drop.exec() catch {};
        }

        // 创建表
        var create_user = try db.newCreateTable(User);
        defer create_user.deinit();
        try create_user.exec();

        var create_post = try db.newCreateTable(Post);
        defer create_post.deinit();
        try create_post.exec();

        var create_comment = try db.newCreateTable(Comment);
        defer create_comment.deinit();
        try create_comment.exec();

        // 插入测试数据
        var insert_user1 = try db.newInsert(User);
        defer insert_user1.deinit();
        _ = try insert_user1.value(.{ .name = "张三", .email = "zhangsan@example.com" });
        _ = try insert_user1.exec();

        var insert_user2 = try db.newInsert(User);
        defer insert_user2.deinit();
        _ = try insert_user2.value(.{ .name = "李四", .email = "lisi@example.com" });
        _ = try insert_user2.exec();

        var insert_post1 = try db.newInsert(Post);
        defer insert_post1.deinit();
        _ = try insert_post1.value(.{ .user_id = 1, .title = "第一篇文章", .published = true });
        _ = try insert_post1.exec();

        var insert_post2 = try db.newInsert(Post);
        defer insert_post2.deinit();
        _ = try insert_post2.value(.{ .user_id = 1, .title = "草稿文章", .published = false });
        _ = try insert_post2.exec();

        var insert_comment = try db.newInsert(Comment);
        defer insert_comment.deinit();
        _ = try insert_comment.value(.{ .post_id = 1, .content = "很棒的文章！" });
        _ = try insert_comment.exec();

        std.debug.print("   ✓ 表和数据准备完成\n\n", .{});
    }

    // ========================================
    // 2. INNER JOIN 示例 - 使用 newRaw() 高级 API
    // ========================================
    std.debug.print("2️⃣  INNER JOIN - 查询已发布文章及作者 (使用 newRaw API)\n", .{});
    {
        const sql =
            \\SELECT users.name as user_name, posts.title as post_title
            \\FROM posts
            \\INNER JOIN users ON posts.user_id = users.id
            \\WHERE posts.published = $1
        ;

        std.debug.print("\n   SQL: {s}\n", .{sql});

        // 使用 newRaw() 高级 API 执行查询
        var query = try db.newRaw(sql, .{true});
        defer query.deinit();

        var results: std.ArrayList(UserPost) = .{};
        defer results.deinit(allocator);

        try query.scan(UserPost, &results);

        std.debug.print("   查询结果:\n", .{});
        for (results.items, 1..) |row, i| {
            std.debug.print("   [{d}] 用户: {s}, 文章: {s}\n", .{ i, row.user_name, row.post_title });
        }
        std.debug.print("   ✓ 共 {} 条记录\n\n", .{results.items.len});
    }

    // ========================================
    // 3. LEFT JOIN 示例 - 使用 newRaw() 高级 API
    // ========================================
    std.debug.print("3️⃣  LEFT JOIN - 查询所有用户及其文章 (使用 newRaw API)\n", .{});
    {
        const sql =
            \\SELECT users.name as user_name, COALESCE(posts.title, '(无文章)') as post_title
            \\FROM users
            \\LEFT JOIN posts ON posts.user_id = users.id
            \\ORDER BY users.id, posts.id
        ;

        std.debug.print("\n   SQL: {s}\n", .{sql});

        var query = try db.newRaw(sql, .{});
        defer query.deinit();

        var results: std.ArrayList(UserPost) = .{};
        defer results.deinit(allocator);

        try query.scan(UserPost, &results);

        std.debug.print("   查询结果:\n", .{});
        for (results.items, 1..) |row, i| {
            std.debug.print("   [{d}] 用户: {s}, 文章: {s}\n", .{ i, row.user_name, row.post_title });
        }
        std.debug.print("   ✓ 共 {} 条记录 (注意李四显示为无文章)\n\n", .{results.items.len});
    }

    // ========================================
    // 4. 多表 JOIN 示例 - 使用 newRaw() 高级 API
    // ========================================
    std.debug.print("4️⃣  多表 JOIN - 查询文章、作者、评论 (使用 newRaw API)\n", .{});
    {
        const sql =
            \\SELECT users.name as user_name, posts.title as post_title, comments.content as comment_content
            \\FROM posts
            \\INNER JOIN users ON posts.user_id = users.id
            \\INNER JOIN comments ON comments.post_id = posts.id
        ;

        std.debug.print("\n   SQL: {s}\n", .{sql});

        var query = try db.newRaw(sql, .{});
        defer query.deinit();

        var results: std.ArrayList(UserPostComment) = .{};
        defer results.deinit(allocator);

        try query.scan(UserPostComment, &results);

        std.debug.print("   查询结果:\n", .{});
        for (results.items, 1..) |row, i| {
            std.debug.print("   [{d}] 用户: {s}, 文章: {s}, 评论: {s}\n", .{
                i,
                row.user_name,
                row.post_title,
                row.comment_content,
            });
        }
        std.debug.print("   ✓ 共 {} 条记录\n\n", .{results.items.len});
    }

    // ========================================
    // 5. 聚合 JOIN 示例 - 使用 newRaw() 高级 API
    // ========================================
    std.debug.print("5️⃣  聚合 JOIN - 统计每个用户的文章数 (使用 newRaw API)\n", .{});
    {
        const sql =
            \\SELECT users.name as user_name, COUNT(posts.id) as post_count
            \\FROM users
            \\LEFT JOIN posts ON posts.user_id = users.id
            \\GROUP BY users.id, users.name
            \\ORDER BY post_count DESC
        ;

        std.debug.print("\n   SQL: {s}\n", .{sql});

        var query = try db.newRaw(sql, .{});
        defer query.deinit();

        var results: std.ArrayList(UserPostCount) = .{};
        defer results.deinit(allocator);

        try query.scan(UserPostCount, &results);

        std.debug.print("   查询结果:\n", .{});
        for (results.items, 1..) |row, i| {
            std.debug.print("   [{d}] 用户: {s}, 文章数: {d}\n", .{ i, row.user_name, row.post_count });
        }
        std.debug.print("   ✓ 共 {} 条记录\n\n", .{results.items.len});
    }

    // ========================================
    // 6. JOIN 类型对比
    // ========================================
    std.debug.print("6️⃣  JOIN 类型对比\n\n", .{});
    std.debug.print("   INNER JOIN (内连接):\n", .{});
    std.debug.print("   • 只返回两表都有匹配的行\n", .{});
    std.debug.print("   • 最常用的 JOIN 类型\n\n", .{});

    std.debug.print("   LEFT JOIN (左外连接):\n", .{});
    std.debug.print("   • 返回左表所有行 + 右表匹配的行\n", .{});
    std.debug.print("   • 右表无匹配时，相应字段为 NULL\n\n", .{});

    std.debug.print("   RIGHT JOIN (右外连接):\n", .{});
    std.debug.print("   • 返回右表所有行 + 左表匹配的行\n", .{});
    std.debug.print("   • 左表无匹配时，相应字段为 NULL\n\n", .{});

    std.debug.print("   FULL OUTER JOIN (全外连接):\n", .{});
    std.debug.print("   • 返回两表所有行\n", .{});
    std.debug.print("   • 无匹配时，相应字段为 NULL\n\n", .{});

    // ========================================
    // 7. ZORM JOIN API 路线图
    // ========================================
    std.debug.print("7️⃣  ZORM JOIN API 路线图\n\n", .{});
    std.debug.print("   当前版本:\n", .{});
    std.debug.print("   • ✓ 使用 newRaw() 高级 API 进行 JOIN 查询\n", .{});
    std.debug.print("   • ✓ 类型安全的结果映射\n", .{});
    std.debug.print("   • ✓ 支持所有 SQL JOIN 语法\n\n", .{});

    std.debug.print("   计划功能 (未来版本):\n", .{});
    std.debug.print("   • query.innerJoin(\"table\", \"condition\")\n", .{});
    std.debug.print("   • query.leftJoin(\"table\", \"condition\")\n", .{});
    std.debug.print("   • query.rightJoin(\"table\", \"condition\")\n", .{});
    std.debug.print("   • 类型安全的 JOIN 查询构建器\n", .{});
    std.debug.print("   • 自动类型推导和结果映射\n", .{});
}
