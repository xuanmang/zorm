//! 数据库初始化脚本
//!
//! 创建示例应用所需的 schema 和表。
//! 运行方式: zig build run-setup
//!
//! 创建的 schema: zorm_examples
//! 创建的表:
//! - users: 用户表
//! - posts: 文章表
//! - comments: 评论表
//! - tags: 标签表
//! - post_tags: 文章-标签关联表 (多对多)
//!
//! 本示例展示如何使用 ZORM 的 Table API 生成 CREATE TABLE SQL，
//! 而不是手写原始 SQL。这体现了 ORM 的核心优势：
//! - 声明式的表定义 (链式 API)
//! - 跨数据库方言的兼容性
//! - 类型安全的约束定义

const std = @import("std");
const zorm = @import("zorm");
const db_config = @import("common/db_config.zig");
const models = @import("common/models.zig");

pub fn main() !void {
    // 初始化内存分配器
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 数据库初始化 ===\n\n", .{});

    // 创建数据库驱动
    std.debug.print("连接到 PostgreSQL...\n", .{});
    var driver = try db_config.createDefaultDriver(allocator);
    defer driver.close() catch {};
    std.debug.print("✓ 数据库连接成功\n\n", .{});

    // 创建 schema
    std.debug.print("创建 schema: zorm_examples...\n", .{});
    try createSchema(&driver);
    std.debug.print("✓ Schema 创建成功\n\n", .{});

    // 创建表 (使用 ZORM Table API)
    std.debug.print("创建数据表...\n", .{});
    try createTables(&driver, allocator);
    std.debug.print("✓ 所有表创建成功\n\n", .{});

    std.debug.print("数据库初始化完成！\n", .{});
    std.debug.print("\n创建的表:\n", .{});
    std.debug.print("  - zorm_examples.users\n", .{});
    std.debug.print("  - zorm_examples.posts\n", .{});
    std.debug.print("  - zorm_examples.comments\n", .{});
    std.debug.print("  - zorm_examples.tags\n", .{});
    std.debug.print("  - zorm_examples.post_tags\n", .{});
}

/// 创建 zorm_examples schema
fn createSchema(driver: *zorm.PostgresDriver) !void {
    _ = try driver.exec("CREATE SCHEMA IF NOT EXISTS zorm_examples", &.{});
    _ = try driver.exec("SET search_path TO zorm_examples", &.{});
}

/// 辅助函数: 执行 CREATE TABLE IF NOT EXISTS
fn createTableIfNotExists(driver: *zorm.PostgresDriver, allocator: std.mem.Allocator, table: *const zorm.Table) !void {
    const create_sql = try table.toSQL(.postgresql);
    defer allocator.free(create_sql);

    // toSQL() 生成 "CREATE TABLE xxx (...)"，我们需要插入 "IF NOT EXISTS"
    const final_sql = try std.fmt.allocPrint(allocator, "CREATE TABLE IF NOT EXISTS {s}", .{create_sql[13..]});
    defer allocator.free(final_sql);

    _ = try driver.exec(final_sql, &.{});
}

/// 辅助函数: 创建带有默认时间戳的列
fn timestampCol(name: []const u8) zorm.Column {
    var col = zorm.Column.init(name, .bigint);
    _ = col.setNotNull().setDefault("EXTRACT(EPOCH FROM NOW())::BIGINT");
    return col;
}

/// 使用 ZORM Table API 创建所有表
/// 展示了 ORM 的优势：声明式定义、链式 API、跨方言兼容
fn createTables(driver: *zorm.PostgresDriver, allocator: std.mem.Allocator) !void {
    // 创建 users 表
    std.debug.print("  创建 users 表...\n", .{});
    {
        var table = try zorm.Table.init(allocator, "users");
        defer table.deinit();

        var id = zorm.Column.init("id", .bigint);
        var name = zorm.Column.init("name", .text);
        var email = zorm.Column.init("email", .text);

        _ = try table.addColumn(id.setPrimaryKey().setAutoIncrement().*);
        _ = try table.addColumn(name.setNotNull().*);
        _ = try table.addColumn(email.setNotNull().setUnique().*);
        _ = try table.addColumn(timestampCol("created_at"));
        _ = try table.addColumn(timestampCol("updated_at"));

        try createTableIfNotExists(driver, allocator, &table);
    }

    // 创建 posts 表
    std.debug.print("  创建 posts 表...\n", .{});
    {
        var table = try zorm.Table.init(allocator, "posts");
        defer table.deinit();

        var id = zorm.Column.init("id", .bigint);
        var user_id = zorm.Column.init("user_id", .bigint);
        var title = zorm.Column.init("title", .text);
        var content = zorm.Column.init("content", .text);
        var status = zorm.Column.init("status", .text);
        var published_at = zorm.Column.init("published_at", .bigint);

        _ = try table.addColumn(id.setPrimaryKey().setAutoIncrement().*);
        _ = try table.addColumn(user_id.setNotNull().setForeignKey("users", "id").*);
        _ = try table.addColumn(title.setNotNull().*);
        _ = try table.addColumn(content.setNotNull().*);
        _ = try table.addColumn(status.setNotNull().setDefault("'draft'").setCheck("status IN ('draft', 'published', 'archived')").*);
        _ = try table.addColumn(published_at);
        _ = try table.addColumn(timestampCol("created_at"));
        _ = try table.addColumn(timestampCol("updated_at"));

        try createTableIfNotExists(driver, allocator, &table);

        // 创建索引
        _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id)", &.{});
        _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_posts_status ON posts(status)", &.{});
    }

    // 创建 comments 表
    std.debug.print("  创建 comments 表...\n", .{});
    {
        var table = try zorm.Table.init(allocator, "comments");
        defer table.deinit();

        var id = zorm.Column.init("id", .bigint);
        var post_id = zorm.Column.init("post_id", .bigint);
        var user_id = zorm.Column.init("user_id", .bigint);
        var content = zorm.Column.init("content", .text);

        _ = try table.addColumn(id.setPrimaryKey().setAutoIncrement().*);
        _ = try table.addColumn(post_id.setNotNull().setForeignKey("posts", "id").*);
        _ = try table.addColumn(user_id.setNotNull().setForeignKey("users", "id").*);
        _ = try table.addColumn(content.setNotNull().*);
        _ = try table.addColumn(timestampCol("created_at"));

        try createTableIfNotExists(driver, allocator, &table);

        // 创建索引
        _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_comments_post_id ON comments(post_id)", &.{});
        _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_comments_user_id ON comments(user_id)", &.{});
    }

    // 创建 tags 表
    std.debug.print("  创建 tags 表...\n", .{});
    {
        var table = try zorm.Table.init(allocator, "tags");
        defer table.deinit();

        var id = zorm.Column.init("id", .bigint);
        var name = zorm.Column.init("name", .text);

        _ = try table.addColumn(id.setPrimaryKey().setAutoIncrement().*);
        _ = try table.addColumn(name.setNotNull().setUnique().*);

        try createTableIfNotExists(driver, allocator, &table);
    }

    // 创建 post_tags 表 (多对多关联)
    std.debug.print("  创建 post_tags 表...\n", .{});
    {
        var table = try zorm.Table.init(allocator, "post_tags");
        defer table.deinit();

        var post_id = zorm.Column.init("post_id", .bigint);
        var tag_id = zorm.Column.init("tag_id", .bigint);

        _ = try table.addColumn(post_id.setNotNull().setPrimaryKey().setForeignKey("posts", "id").*);
        _ = try table.addColumn(tag_id.setNotNull().setPrimaryKey().setForeignKey("tags", "id").*);

        try createTableIfNotExists(driver, allocator, &table);

        // 创建索引
        _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_post_tags_tag_id ON post_tags(tag_id)", &.{});
    }
}
