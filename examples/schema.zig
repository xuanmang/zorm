//! 表结构管理示例 - 可运行版本
//!
//! 本示例演示使用 ZORM 高层级 API 进行表结构管理:
//! 1. 使用 newCreateTable() 创建表
//! 2. 使用 newDropTable() 删除表
//! 3. 展示多种数据类型的表定义
//! 4. 展示主键、可选字段、外键引用
//!
//! 运行方式:
//! ```sh
//! zig build run-example-schema
//! ```

const std = @import("std");
const zorm = @import("zorm");

// 定义 User 模型
const User = struct {
    id: i64 = 0, // PRIMARY KEY, BIGINT NOT NULL
    name: []const u8, // TEXT NOT NULL
    email: []const u8, // TEXT NOT NULL
    age: u32, // INTEGER NOT NULL
    is_active: bool = true, // BOOLEAN NOT NULL

    pub const table_name = "users";
};

// 定义 Post 模型
const Post = struct {
    id: i64 = 0, // PRIMARY KEY, BIGINT NOT NULL
    user_id: i64, // BIGINT NOT NULL (外键)
    title: []const u8, // TEXT NOT NULL
    published: bool = false, // BOOLEAN NOT NULL

    pub const table_name = "posts";
};

// 定义 Comment 模型
const Comment = struct {
    id: i64 = 0, // PRIMARY KEY
    post_id: i64, // BIGINT NOT NULL (外键)
    content: []const u8, // TEXT NOT NULL
    likes: i32 = 0, // INTEGER NOT NULL

    pub const table_name = "comments";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("ZORM 表结构管理示例\n", .{});
    std.debug.print("=" ** 60 ++ "\n\n", .{});

    // 连接数据库
    std.debug.print("📦 连接数据库: pguser@127.0.0.1:5432/postgres\n\n", .{});
    const dsn = "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres";

    const db = try zorm.connect(allocator, dsn, null);
    defer db.deinit();

    std.debug.print("✓ 数据库连接成功\n\n", .{});

    // 执行表结构管理操作
    try runSchemaOperations(db);

    std.debug.print("\n✅ 示例执行完成!\n", .{});
}

fn runSchemaOperations(db: *zorm.DB(.postgresql)) !void {
    // ========================================
    // 1. 清理旧表 (CASCADE 删除)
    // ========================================
    std.debug.print("1️⃣  清理旧表 (使用 newDropTable)\n", .{});
    {
        // 按依赖顺序删除 (先删除依赖表，再删除被依赖表)
        // 删除 Comment
        {
            var drop = try db.newDropTable(Comment);
            defer drop.deinit();
            _ = drop.ifExists().cascade();
            drop.exec() catch {};
        }
        // 删除 Post
        {
            var drop = try db.newDropTable(Post);
            defer drop.deinit();
            _ = drop.ifExists().cascade();
            drop.exec() catch {};
        }
        // 删除 User
        {
            var drop = try db.newDropTable(User);
            defer drop.deinit();
            _ = drop.ifExists().cascade();
            drop.exec() catch {};
        }
        std.debug.print("   ✓ 清理完成\n\n", .{});
    }

    // ========================================
    // 2. 创建 User 表 - 展示基础类型映射
    // ========================================
    std.debug.print("2️⃣  创建 User 表 (展示 Zig 类型映射)\n", .{});
    {
        var create = try db.newCreateTable(User);
        defer create.deinit();

        // 查看生成的 SQL
        const sql = try create.explain();
        defer create.allocator.free(sql);
        std.debug.print("   SQL: {s}\n", .{sql});

        try create.exec();
        std.debug.print("   ✓ User 表创建成功\n\n", .{});
    }

    // ========================================
    // 3. 创建 Post 表 - 展示外键引用
    // ========================================
    std.debug.print("3️⃣  创建 Post 表 (包含外键引用)\n", .{});
    {
        var create = try db.newCreateTable(Post);
        defer create.deinit();

        const sql = try create.explain();
        defer create.allocator.free(sql);
        std.debug.print("   SQL: {s}\n", .{sql});

        try create.exec();
        std.debug.print("   ✓ Post 表创建成功\n\n", .{});
    }

    // ========================================
    // 4. 创建 Comment 表 - 展示多外键
    // ========================================
    std.debug.print("4️⃣  创建 Comment 表 (多个外键引用)\n", .{});
    {
        var create = try db.newCreateTable(Comment);
        defer create.deinit();

        const sql = try create.explain();
        defer create.allocator.free(sql);
        std.debug.print("   SQL: {s}\n", .{sql});

        try create.exec();
        std.debug.print("   ✓ Comment 表创建成功\n\n", .{});
    }

    // ========================================
    // 5. 类型映射说明
    // ========================================
    std.debug.print("5️⃣  Zig 类型到 PostgreSQL 类型映射:\n", .{});
    std.debug.print("   i8, i16, i32    → SMALLINT\n", .{});
    std.debug.print("   i64             → BIGINT\n", .{});
    std.debug.print("   u8, u16, u32    → INTEGER\n", .{});
    std.debug.print("   u64             → BIGINT\n", .{});
    std.debug.print("   f32             → REAL\n", .{});
    std.debug.print("   f64             → DOUBLE PRECISION\n", .{});
    std.debug.print("   bool            → BOOLEAN\n", .{});
    std.debug.print("   []const u8      → TEXT\n", .{});
    std.debug.print("   ?T              → 对应类型 + 允许 NULL\n\n", .{});

    // ========================================
    // 6. 插入测试数据验证表结构
    // ========================================
    std.debug.print("6️⃣  插入测试数据验证表结构\n", .{});
    {
        // 插入用户
        var insert_user = try db.newInsert(User);
        defer insert_user.deinit();

        _ = try insert_user.value(.{
            .name = "张三",
            .email = "zhangsan@example.com",
            .age = 28,
            .is_active = true,
        });

        const user_result = try insert_user.exec();
        std.debug.print("   ✓ 插入用户: {} 行\n", .{user_result.rows_affected});

        // 插入文章
        var insert_post = try db.newInsert(Post);
        defer insert_post.deinit();

        _ = try insert_post.value(.{
            .user_id = 1,
            .title = "第一篇文章",
            .published = true,
        });

        const post_result = try insert_post.exec();
        std.debug.print("   ✓ 插入文章: {} 行\n", .{post_result.rows_affected});

        // 插入评论
        var insert_comment = try db.newInsert(Comment);
        defer insert_comment.deinit();

        _ = try insert_comment.value(.{
            .post_id = 1,
            .content = "很好的文章！",
            .likes = 10,
        });

        const comment_result = try insert_comment.exec();
        std.debug.print("   ✓ 插入评论: {} 行\n\n", .{comment_result.rows_affected});
    }

    // ========================================
    // 7. 验证数据插入成功
    // ========================================
    std.debug.print("7️⃣  验证数据插入成功\n", .{});
    {
        // 查询用户
        var query_user = try db.newSelect(User);
        defer query_user.deinit();

        const user = try query_user.scanOne();
        std.debug.print("   User: name={s}, email={s}, age={d}, active={}\n", .{
            user.name,
            user.email,
            user.age,
            user.is_active,
        });

        // 查询文章
        var query_post = try db.newSelect(Post);
        defer query_post.deinit();

        const post = try query_post.scanOne();
        std.debug.print("   Post: title={s}, published={}\n", .{
            post.title,
            post.published,
        });

        // 查询评论
        var query_comment = try db.newSelect(Comment);
        defer query_comment.deinit();

        const comment = try query_comment.scanOne();
        std.debug.print("   Comment: content={s}, likes={d}\n", .{
            comment.content,
            comment.likes,
        });
    }
}
