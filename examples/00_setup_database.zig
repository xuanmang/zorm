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
//! - 声明式的表定义
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
    try createTablesWithTableAPI(&driver, allocator);
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
    const create_schema_sql = "CREATE SCHEMA IF NOT EXISTS zorm_examples";
    _ = try driver.exec(create_schema_sql, &.{});

    // 设置搜索路径
    _ = try driver.exec("SET search_path TO zorm_examples", &.{});
}

/// 使用 ZORM Table API 创建表
/// 这展示了 ORM 的优势：声明式定义、跨方言兼容、类型安全
fn createTablesWithTableAPI(driver: *zorm.PostgresDriver, allocator: std.mem.Allocator) !void {
    // 创建 users 表
    std.debug.print("  创建 users 表...\n", .{});
    {
        var users_table = try zorm.Table.init(allocator, "users");
        defer users_table.deinit();

        // 使用声明式 API 定义列
        var id_col = zorm.Column.init("id", .bigint);
        _ = id_col.setPrimaryKey().setAutoIncrement();
        _ = try users_table.addColumn(id_col);

        var name_col = zorm.Column.init("name", .text);
        _ = name_col.setNotNull();
        _ = try users_table.addColumn(name_col);

        var email_col = zorm.Column.init("email", .text);
        _ = email_col.setNotNull().setUnique();
        _ = try users_table.addColumn(email_col);

        var created_at_col = zorm.Column.init("created_at", .bigint);
        _ = created_at_col.setNotNull().setDefault("EXTRACT(EPOCH FROM NOW())::BIGINT");
        _ = try users_table.addColumn(created_at_col);

        var updated_at_col = zorm.Column.init("updated_at", .bigint);
        _ = updated_at_col.setNotNull().setDefault("EXTRACT(EPOCH FROM NOW())::BIGINT");
        _ = try users_table.addColumn(updated_at_col);

        // 生成并执行 SQL
        const create_sql = try users_table.toSQL(.postgresql);
        defer allocator.free(create_sql);

        const final_sql = try std.fmt.allocPrint(allocator, "CREATE TABLE IF NOT EXISTS {s}", .{create_sql[13..]});
        defer allocator.free(final_sql);

        _ = try driver.exec(final_sql, &.{});
    }

    // 创建 posts 表
    std.debug.print("  创建 posts 表...\n", .{});
    {
        var posts_table = try zorm.Table.init(allocator, "posts");
        defer posts_table.deinit();

        var id_col = zorm.Column.init("id", .bigint);
        _ = id_col.setPrimaryKey().setAutoIncrement();
        _ = try posts_table.addColumn(id_col);

        var user_id_col = zorm.Column.init("user_id", .bigint);
        _ = user_id_col.setNotNull().setForeignKey("users", "id");
        _ = try posts_table.addColumn(user_id_col);

        var title_col = zorm.Column.init("title", .text);
        _ = title_col.setNotNull();
        _ = try posts_table.addColumn(title_col);

        var content_col = zorm.Column.init("content", .text);
        _ = content_col.setNotNull();
        _ = try posts_table.addColumn(content_col);

        var status_col = zorm.Column.init("status", .text);
        _ = status_col.setNotNull().setDefault("'draft'").setCheck("status IN ('draft', 'published', 'archived')");
        _ = try posts_table.addColumn(status_col);

        var published_at_col = zorm.Column.init("published_at", .bigint);
        _ = try posts_table.addColumn(published_at_col);

        var created_at_col = zorm.Column.init("created_at", .bigint);
        _ = created_at_col.setNotNull().setDefault("EXTRACT(EPOCH FROM NOW())::BIGINT");
        _ = try posts_table.addColumn(created_at_col);

        var updated_at_col = zorm.Column.init("updated_at", .bigint);
        _ = updated_at_col.setNotNull().setDefault("EXTRACT(EPOCH FROM NOW())::BIGINT");
        _ = try posts_table.addColumn(updated_at_col);

        const create_sql = try posts_table.toSQL(.postgresql);
        defer allocator.free(create_sql);

        const final_sql = try std.fmt.allocPrint(allocator, "CREATE TABLE IF NOT EXISTS {s}", .{create_sql[13..]});
        defer allocator.free(final_sql);

        _ = try driver.exec(final_sql, &.{});

        // 创建索引
        _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id)", &.{});
        _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_posts_status ON posts(status)", &.{});
    }

    // 创建 comments 表
    std.debug.print("  创建 comments 表...\n", .{});
    {
        var comments_table = try zorm.Table.init(allocator, "comments");
        defer comments_table.deinit();

        var id_col = zorm.Column.init("id", .bigint);
        _ = id_col.setPrimaryKey().setAutoIncrement();
        _ = try comments_table.addColumn(id_col);

        var post_id_col = zorm.Column.init("post_id", .bigint);
        _ = post_id_col.setNotNull().setForeignKey("posts", "id");
        _ = try comments_table.addColumn(post_id_col);

        var user_id_col = zorm.Column.init("user_id", .bigint);
        _ = user_id_col.setNotNull().setForeignKey("users", "id");
        _ = try comments_table.addColumn(user_id_col);

        var content_col = zorm.Column.init("content", .text);
        _ = content_col.setNotNull();
        _ = try comments_table.addColumn(content_col);

        var created_at_col = zorm.Column.init("created_at", .bigint);
        _ = created_at_col.setNotNull().setDefault("EXTRACT(EPOCH FROM NOW())::BIGINT");
        _ = try comments_table.addColumn(created_at_col);

        const create_sql = try comments_table.toSQL(.postgresql);
        defer allocator.free(create_sql);

        const final_sql = try std.fmt.allocPrint(allocator, "CREATE TABLE IF NOT EXISTS {s}", .{create_sql[13..]});
        defer allocator.free(final_sql);

        _ = try driver.exec(final_sql, &.{});

        // 创建索引
        _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_comments_post_id ON comments(post_id)", &.{});
        _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_comments_user_id ON comments(user_id)", &.{});
    }

    // 创建 tags 表
    std.debug.print("  创建 tags 表...\n", .{});
    {
        var tags_table = try zorm.Table.init(allocator, "tags");
        defer tags_table.deinit();

        var id_col = zorm.Column.init("id", .bigint);
        _ = id_col.setPrimaryKey().setAutoIncrement();
        _ = try tags_table.addColumn(id_col);

        var name_col = zorm.Column.init("name", .text);
        _ = name_col.setNotNull().setUnique();
        _ = try tags_table.addColumn(name_col);

        const create_sql = try tags_table.toSQL(.postgresql);
        defer allocator.free(create_sql);

        const final_sql = try std.fmt.allocPrint(allocator, "CREATE TABLE IF NOT EXISTS {s}", .{create_sql[13..]});
        defer allocator.free(final_sql);

        _ = try driver.exec(final_sql, &.{});
    }

    // 创建 post_tags 表 (多对多关联)
    std.debug.print("  创建 post_tags 表...\n", .{});
    {
        var post_tags_table = try zorm.Table.init(allocator, "post_tags");
        defer post_tags_table.deinit();

        var post_id_col = zorm.Column.init("post_id", .bigint);
        _ = post_id_col.setNotNull().setPrimaryKey().setForeignKey("posts", "id");
        _ = try post_tags_table.addColumn(post_id_col);

        var tag_id_col = zorm.Column.init("tag_id", .bigint);
        _ = tag_id_col.setNotNull().setPrimaryKey().setForeignKey("tags", "id");
        _ = try post_tags_table.addColumn(tag_id_col);

        const create_sql = try post_tags_table.toSQL(.postgresql);
        defer allocator.free(create_sql);

        const final_sql = try std.fmt.allocPrint(allocator, "CREATE TABLE IF NOT EXISTS {s}", .{create_sql[13..]});
        defer allocator.free(final_sql);

        _ = try driver.exec(final_sql, &.{});

        // 创建索引
        _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_post_tags_tag_id ON post_tags(tag_id)", &.{});
    }
}
