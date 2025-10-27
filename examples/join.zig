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

fn demonstrateJoinConcepts(db: *zorm.DB(.postgresql), allocator: std.mem.Allocator) !void {
    _ = allocator;

    // ========================================
    // 1. 准备：创建测试表和数据
    // ========================================
    std.debug.print("1️⃣  准备：创建测试表和数据\n", .{});
    {
        // 清理旧表
        db.exec("DROP TABLE IF EXISTS comments CASCADE", &[_]zorm.QueryArg{}) catch {};
        db.exec("DROP TABLE IF EXISTS posts CASCADE", &[_]zorm.QueryArg{}) catch {};
        db.exec("DROP TABLE IF EXISTS users CASCADE", &[_]zorm.QueryArg{}) catch {};

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
    // 2. INNER JOIN 示例
    // ========================================
    std.debug.print("2️⃣  INNER JOIN - 查询已发布文章及作者\n", .{});
    std.debug.print("\n   SQL 示例:\n", .{});
    std.debug.print("   SELECT users.name, posts.title\n", .{});
    std.debug.print("   FROM posts\n", .{});
    std.debug.print("   INNER JOIN users ON posts.user_id = users.id\n", .{});
    std.debug.print("   WHERE posts.published = true\n\n", .{});

    std.debug.print("   说明:\n", .{});
    std.debug.print("   • INNER JOIN 只返回两个表中都有匹配的行\n", .{});
    std.debug.print("   • 查询结果包含: 用户名, 文章标题\n", .{});
    std.debug.print("   • 只显示已发布的文章\n\n", .{});

    // ========================================
    // 3. LEFT JOIN 示例
    // ========================================
    std.debug.print("3️⃣  LEFT JOIN - 查询所有用户及其文章\n", .{});
    std.debug.print("\n   SQL 示例:\n", .{});
    std.debug.print("   SELECT users.name, posts.title\n", .{});
    std.debug.print("   FROM users\n", .{});
    std.debug.print("   LEFT JOIN posts ON posts.user_id = users.id\n\n", .{});

    std.debug.print("   说明:\n", .{});
    std.debug.print("   • LEFT JOIN 返回左表(users)的所有行\n", .{});
    std.debug.print("   • 如果右表没有匹配，则相应字段为 NULL\n", .{});
    std.debug.print("   • 结果包含所有用户，即使他们没有发表文章\n\n", .{});

    // ========================================
    // 4. 多表 JOIN 示例
    // ========================================
    std.debug.print("4️⃣  多表 JOIN - 查询文章、作者、评论\n", .{});
    std.debug.print("\n   SQL 示例:\n", .{});
    std.debug.print("   SELECT users.name, posts.title, comments.content\n", .{});
    std.debug.print("   FROM posts\n", .{});
    std.debug.print("   INNER JOIN users ON posts.user_id = users.id\n", .{});
    std.debug.print("   INNER JOIN comments ON comments.post_id = posts.id\n\n", .{});

    std.debug.print("   说明:\n", .{});
    std.debug.print("   • 可以连接多个表\n", .{});
    std.debug.print("   • 每个 JOIN 都需要指定连接条件\n", .{});
    std.debug.print("   • 查询结果: 用户名, 文章标题, 评论内容\n\n", .{});

    // ========================================
    // 5. 聚合 JOIN 示例
    // ========================================
    std.debug.print("5️⃣  聚合 JOIN - 统计每个用户的文章数\n", .{});
    std.debug.print("\n   SQL 示例:\n", .{});
    std.debug.print("   SELECT users.name, COUNT(posts.id) as post_count\n", .{});
    std.debug.print("   FROM users\n", .{});
    std.debug.print("   LEFT JOIN posts ON posts.user_id = users.id\n", .{});
    std.debug.print("   GROUP BY users.id, users.name\n", .{});
    std.debug.print("   ORDER BY post_count DESC\n\n", .{});

    std.debug.print("   说明:\n", .{});
    std.debug.print("   • 使用 COUNT() 聚合函数统计文章数\n", .{});
    std.debug.print("   • GROUP BY 对结果分组\n", .{});
    std.debug.print("   • ORDER BY 对结果排序\n\n", .{});

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
    std.debug.print("   • ✓ 使用原始 SQL 进行 JOIN 查询\n", .{});
    std.debug.print("   • ✓ db.exec() / db.query() 支持所有 SQL\n\n", .{});

    std.debug.print("   计划功能 (未来版本):\n", .{});
    std.debug.print("   • query.innerJoin(\"table\", \"condition\")\n", .{});
    std.debug.print("   • query.leftJoin(\"table\", \"condition\")\n", .{});
    std.debug.print("   • query.rightJoin(\"table\", \"condition\")\n", .{});
    std.debug.print("   • 类型安全的 JOIN 查询构建器\n", .{});
    std.debug.print("   • 自动类型推导和结果映射\n", .{});
}
