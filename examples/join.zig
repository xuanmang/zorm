//! JOIN 查询示例
//!
//! 本示例演示 ZORM 的多表关联查询:
//! 1. INNER JOIN
//! 2. LEFT JOIN
//! 3. RIGHT JOIN
//! 4. 多表 JOIN
//! 5. JOIN 结果映射
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

// JOIN 结果结构体
const UserWithPosts = struct {
    user_id: i64,
    user_name: []const u8,
    user_email: []const u8,
    post_id: i64,
    post_title: []const u8,
    post_content: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("ZORM JOIN 查询示例\n", .{});
    std.debug.print("=" ** 60 ++ "\n\n", .{});

    try demonstrateJoins(allocator);

    std.debug.print("\n✅ 示例执行完成!\n", .{});
}

fn demonstrateJoins(allocator: std.mem.Allocator) !void {
    std.debug.print("📝 演示 JOIN 查询:\n\n", .{});

    // ========================================
    // 1. INNER JOIN
    // ========================================
    std.debug.print("1️⃣  INNER JOIN - 查询用户及其文章\n", .{});
    {
        var query = zorm.SelectQuery(User, .postgresql).init(allocator);
        defer query.deinit();

        // 选择字段
        try query.column("users.id");
        try query.column("users.name");
        try query.column("users.email");
        try query.column("posts.id");
        try query.column("posts.title");

        // INNER JOIN
        try query.join(.inner, "posts", "posts.user_id", .eq, "users.id");

        // WHERE 条件
        try query.where("posts.published", .eq, true);

        // 排序
        try query.orderBy("users.id", .asc);
        try query.orderBy("posts.id", .asc);

        const sql = try query.buildSQL();
        defer allocator.free(sql);

        std.debug.print("   SQL: {s}\n\n", .{sql});
    }

    // ========================================
    // 2. LEFT JOIN
    // ========================================
    std.debug.print("2️⃣  LEFT JOIN - 查询所有用户及其文章 (包括无文章的用户)\n", .{});
    {
        var query = zorm.SelectQuery(User, .postgresql).init(allocator);
        defer query.deinit();

        try query.column("users.id");
        try query.column("users.name");
        try query.column("posts.id");
        try query.column("posts.title");

        // LEFT JOIN - 保留所有用户,即使没有文章
        try query.join(.left, "posts", "posts.user_id", .eq, "users.id");

        try query.orderBy("users.id", .asc);

        const sql = try query.buildSQL();
        defer allocator.free(sql);

        std.debug.print("   SQL: {s}\n\n", .{sql});
    }

    // ========================================
    // 3. RIGHT JOIN
    // ========================================
    std.debug.print("3️⃣  RIGHT JOIN - 查询所有文章及其作者 (包括无作者的文章)\n", .{});
    {
        var query = zorm.SelectQuery(Post, .postgresql).init(allocator);
        defer query.deinit();

        try query.column("posts.id");
        try query.column("posts.title");
        try query.column("users.id");
        try query.column("users.name");

        // RIGHT JOIN - 保留所有文章
        try query.join(.right, "users", "posts.user_id", .eq, "users.id");

        const sql = try query.buildSQL();
        defer allocator.free(sql);

        std.debug.print("   SQL: {s}\n\n", .{sql});
    }

    // ========================================
    // 4. 多表 JOIN
    // ========================================
    std.debug.print("4️⃣  多表 JOIN - 查询用户、文章、评论\n", .{});
    {
        var query = zorm.SelectQuery(User, .postgresql).init(allocator);
        defer query.deinit();

        try query.column("users.name as author");
        try query.column("posts.title");
        try query.column("comments.content");

        // 第一个 JOIN: users -> posts
        try query.join(.inner, "posts", "posts.user_id", .eq, "users.id");

        // 第二个 JOIN: posts -> comments
        try query.join(.inner, "comments", "comments.post_id", .eq, "posts.id");

        try query.where("posts.published", .eq, true);
        try query.orderBy("posts.id", .asc);
        try query.orderBy("comments.id", .asc);

        const sql = try query.buildSQL();
        defer allocator.free(sql);

        std.debug.print("   SQL: {s}\n\n", .{sql});
    }

    // ========================================
    // 5. 使用子查询的 JOIN
    // ========================================
    std.debug.print("5️⃣  子查询 JOIN - 查询活跃用户 (发布过文章的用户)\n", .{});
    {
        var query = zorm.SelectQuery(User, .postgresql).init(allocator);
        defer query.deinit();

        try query.column("users.id");
        try query.column("users.name");
        try query.column("user_posts.post_count");

        // 使用派生表进行 JOIN
        const subquery =
            \\(SELECT user_id, COUNT(*) as post_count
            \\FROM posts
            \\WHERE published = true
            \\GROUP BY user_id) as user_posts
        ;

        try query.joinRaw(.inner, subquery, "user_posts.user_id", .eq, "users.id");

        try query.where("user_posts.post_count", .gte, 5);
        try query.orderBy("user_posts.post_count", .desc);

        const sql = try query.buildSQL();
        defer allocator.free(sql);

        std.debug.print("   SQL: {s}\n\n", .{sql});
    }

    // ========================================
    // 6. 聚合 JOIN
    // ========================================
    std.debug.print("6️⃣  聚合 JOIN - 统计每个用户的文章和评论数\n", .{});
    {
        var query = zorm.SelectQuery(User, .postgresql).init(allocator);
        defer query.deinit();

        try query.column("users.id");
        try query.column("users.name");
        try query.column("COUNT(DISTINCT posts.id) as post_count");
        try query.column("COUNT(DISTINCT comments.id) as comment_count");

        try query.join(.left, "posts", "posts.user_id", .eq, "users.id");
        try query.join(.left, "comments", "comments.user_id", .eq, "users.id");

        try query.groupBy("users.id");
        try query.groupBy("users.name");
        try query.orderBy("post_count", .desc);

        const sql = try query.buildSQL();
        defer allocator.free(sql);

        std.debug.print("   SQL: {s}\n\n", .{sql});
    }
}
