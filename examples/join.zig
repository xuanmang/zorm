//! JOIN 查询示例
//!
//! 本示例演示 ZORM 的多表关联查询 API:
//! 1. INNER JOIN
//! 2. LEFT JOIN
//! 3. RIGHT JOIN
//! 4. 多表 JOIN
//! 5. 子查询 JOIN
//! 6. 聚合 JOIN
//!
//! 注意: 这是一个演示性示例，展示 JOIN API 的使用方式
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
    content: []const u8,
    published: bool,
    pub const table_name = "posts";
};

const Comment = struct {
    id: i64 = 0,
    post_id: i64,
    user_id: i64,
    content: []const u8,
    pub const table_name = "comments";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("ZORM JOIN 查询 API 演示\n", .{});
    std.debug.print("=" ** 60 ++ "\n\n", .{});

    try demonstrateJoins(allocator);

    std.debug.print("\n✅ 示例执行完成!\n", .{});
}

fn demonstrateJoins(allocator: std.mem.Allocator) !void {
    _ = allocator;

    std.debug.print("📝 演示 JOIN 查询 API:\n\n", .{});

    // ========================================
    // 1. INNER JOIN
    // ========================================
    std.debug.print("1️⃣  INNER JOIN - 查询用户及其已发布的文章\n", .{});
    std.debug.print("   var query = try db.newSelect(User);\n", .{});
    std.debug.print("   defer query.deinit();\n\n", .{});

    std.debug.print("   // 选择字段\n", .{});
    std.debug.print("   _ = try query.column(\"users.id\");\n", .{});
    std.debug.print("   _ = try query.column(\"users.name\");\n", .{});
    std.debug.print("   _ = try query.column(\"posts.title\");\n\n", .{});

    std.debug.print("   // INNER JOIN\n", .{});
    std.debug.print("   _ = try query.innerJoin(\"posts\", \"posts.user_id = users.id\");\n\n", .{});

    std.debug.print("   // WHERE 条件\n", .{});
    std.debug.print("   _ = try query.where(\"posts.published = $1\", .{{true}});\n\n", .{});

    std.debug.print("   // 生成 SQL:\n", .{});
    std.debug.print("   // SELECT users.id, users.name, posts.title\n", .{});
    std.debug.print("   // FROM users\n", .{});
    std.debug.print("   // INNER JOIN posts ON posts.user_id = users.id\n", .{});
    std.debug.print("   // WHERE posts.published = $1\n\n", .{});

    // ========================================
    // 2. LEFT JOIN
    // ========================================
    std.debug.print("2️⃣  LEFT JOIN - 查询所有用户及其文章 (包括无文章的用户)\n", .{});
    std.debug.print("   var query = try db.newSelect(User);\n", .{});
    std.debug.print("   _ = try query.column(\"users.*\");\n", .{});
    std.debug.print("   _ = try query.column(\"posts.title\");\n\n", .{});

    std.debug.print("   // LEFT JOIN - 保留所有用户\n", .{});
    std.debug.print("   _ = try query.leftJoin(\"posts\", \"posts.user_id = users.id\");\n\n", .{});

    std.debug.print("   // 生成 SQL:\n", .{});
    std.debug.print("   // SELECT users.*, posts.title\n", .{});
    std.debug.print("   // FROM users\n", .{});
    std.debug.print("   // LEFT JOIN posts ON posts.user_id = users.id\n\n", .{});

    // ========================================
    // 3. RIGHT JOIN
    // ========================================
    std.debug.print("3️⃣  RIGHT JOIN - 查询所有文章及其作者 (包括无作者的文章)\n", .{});
    std.debug.print("   var query = try db.newSelect(Post);\n", .{});
    std.debug.print("   _ = try query.column(\"posts.*\");\n", .{});
    std.debug.print("   _ = try query.column(\"users.name\");\n\n", .{});

    std.debug.print("   // RIGHT JOIN\n", .{});
    std.debug.print("   _ = try query.rightJoin(\"users\", \"posts.user_id = users.id\");\n\n", .{});

    std.debug.print("   // 生成 SQL:\n", .{});
    std.debug.print("   // SELECT posts.*, users.name\n", .{});
    std.debug.print("   // FROM posts\n", .{});
    std.debug.print("   // RIGHT JOIN users ON posts.user_id = users.id\n\n", .{});

    // ========================================
    // 4. 多表 JOIN
    // ========================================
    std.debug.print("4️⃣  多表 JOIN - 查询用户、文章、评论\n", .{});
    std.debug.print("   var query = try db.newSelect(User);\n", .{});
    std.debug.print("   _ = try query.column(\"users.name as author\");\n", .{});
    std.debug.print("   _ = try query.column(\"posts.title\");\n", .{});
    std.debug.print("   _ = try query.column(\"comments.content\");\n\n", .{});

    std.debug.print("   // 第一个 JOIN: users -> posts\n", .{});
    std.debug.print("   _ = try query.innerJoin(\"posts\", \"posts.user_id = users.id\");\n\n", .{});

    std.debug.print("   // 第二个 JOIN: posts -> comments\n", .{});
    std.debug.print("   _ = try query.innerJoin(\"comments\", \"comments.post_id = posts.id\");\n\n", .{});

    std.debug.print("   // 生成 SQL:\n", .{});
    std.debug.print("   // SELECT users.name as author, posts.title, comments.content\n", .{});
    std.debug.print("   // FROM users\n", .{});
    std.debug.print("   // INNER JOIN posts ON posts.user_id = users.id\n", .{});
    std.debug.print("   // INNER JOIN comments ON comments.post_id = posts.id\n\n", .{});

    // ========================================
    // 5. 子查询 JOIN
    // ========================================
    std.debug.print("5️⃣  子查询 JOIN - 查询活跃用户 (发布过多篇文章的用户)\n", .{});
    std.debug.print("   var query = try db.newSelect(User);\n", .{});
    std.debug.print("   _ = try query.column(\"users.id\");\n", .{});
    std.debug.print("   _ = try query.column(\"users.name\");\n", .{});
    std.debug.print("   _ = try query.column(\"user_posts.post_count\");\n\n", .{});

    std.debug.print("   // 使用派生表进行 JOIN\n", .{});
    std.debug.print("   const subquery =\n", .{});
    std.debug.print("       \\\\(SELECT user_id, COUNT(*) as post_count\n", .{});
    std.debug.print("       \\\\FROM posts\n", .{});
    std.debug.print("       \\\\WHERE published = true\n", .{});
    std.debug.print("       \\\\GROUP BY user_id) as user_posts\n", .{});
    std.debug.print("   ;\n\n", .{});

    std.debug.print("   _ = try query.join(.inner, subquery, \"user_posts.user_id = users.id\");\n", .{});
    std.debug.print("   _ = try query.where(\"user_posts.post_count >= $1\", .{{5}});\n", .{});
    std.debug.print("   _ = try query.orderBy(\"user_posts.post_count\", .desc);\n\n", .{});

    // ========================================
    // 6. 聚合 JOIN
    // ========================================
    std.debug.print("6️⃣  聚合 JOIN - 统计每个用户的文章和评论数\n", .{});
    std.debug.print("   var query = try db.newSelect(User);\n", .{});
    std.debug.print("   _ = try query.column(\"users.id\");\n", .{});
    std.debug.print("   _ = try query.column(\"users.name\");\n", .{});
    std.debug.print("   _ = try query.column(\"COUNT(DISTINCT posts.id) as post_count\");\n", .{});
    std.debug.print("   _ = try query.column(\"COUNT(DISTINCT comments.id) as comment_count\");\n\n", .{});

    std.debug.print("   _ = try query.leftJoin(\"posts\", \"posts.user_id = users.id\");\n", .{});
    std.debug.print("   _ = try query.leftJoin(\"comments\", \"comments.user_id = users.id\");\n\n", .{});

    std.debug.print("   _ = try query.groupBy(\"users.id\");\n", .{});
    std.debug.print("   _ = try query.groupBy(\"users.name\");\n", .{});
    std.debug.print("   _ = try query.orderBy(\"post_count\", .desc);\n\n", .{});

    std.debug.print("   // 生成 SQL:\n", .{});
    std.debug.print("   // SELECT users.id, users.name,\n", .{});
    std.debug.print("   //        COUNT(DISTINCT posts.id) as post_count,\n", .{});
    std.debug.print("   //        COUNT(DISTINCT comments.id) as comment_count\n", .{});
    std.debug.print("   // FROM users\n", .{});
    std.debug.print("   // LEFT JOIN posts ON posts.user_id = users.id\n", .{});
    std.debug.print("   // LEFT JOIN comments ON comments.user_id = users.id\n", .{});
    std.debug.print("   // GROUP BY users.id, users.name\n", .{});
    std.debug.print("   // ORDER BY post_count DESC\n", .{});
}
