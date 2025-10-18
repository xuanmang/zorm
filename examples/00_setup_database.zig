//! 数据库初始化脚本
//!
//! 创建示例应用所需的 schema 和表。
//! 运行方式: zig build run-setup
//!
//! 本脚本展示如何使用 ZORM 高层级 API 创建表结构：
//! - 使用 db.newCreateTable() 构建 DDL 查询
//! - 链式调用添加列定义
//! - 类型安全的列定义（编译时检查）

const std = @import("std");
const zorm = @import("zorm");
const db_config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 数据库初始化 ===\n\n", .{});

    // 连接数据库 - 使用 DB 实例而不是直接用 driver
    std.debug.print("连接到 PostgreSQL...\n", .{});
    var db = try db_config.createDefaultDBInstance(allocator);
    defer db.deinit();
    std.debug.print("✓ 数据库连接成功\n\n", .{});

    // 创建 schema (这里仍需要原始 SQL，因为 ZORM 暂无 CREATE SCHEMA API)
    std.debug.print("创建 schema...\n", .{});
    try db.exec("CREATE SCHEMA IF NOT EXISTS zorm_examples", &.{});
    try db.exec("SET search_path TO zorm_examples", &.{});
    std.debug.print("✓ Schema 创建成功\n\n", .{});

    // 使用 ZORM 高层级 API 创建表
    std.debug.print("创建数据表...\n", .{});
    try createUsersTable(db, allocator);
    try createPostsTable(db, allocator);
    try createCommentsTable(db, allocator);
    try createTagsTable(db, allocator);
    try createPostTagsTable(db, allocator);
    std.debug.print("✓ 所有表创建成功\n\n", .{});

    // 创建索引 (暂时使用原始 SQL，后续可扩展 ZORM Index API)
    std.debug.print("创建索引...\n", .{});
    try createIndexes(db);
    std.debug.print("✓ 所有索引创建成功\n\n", .{});

    std.debug.print("✅ 数据库初始化完成！\n", .{});
}

/// 创建用户表 - 展示 ZORM CreateTableQuery API
fn createUsersTable(db: *zorm.DB(.postgresql), allocator: std.mem.Allocator) !void {
    _ = allocator;
    var query = try db.newCreateTable("users");
    defer query.deinit();

    _ = try query
        .ifNotExists()
        .column(.{
        .name = "id",
        .column_type = .bigserial,
        .primary_key = true,
        .nullable = false,
    })
        .column(.{
        .name = "name",
        .column_type = .text,
        .nullable = false,
    })
        .column(.{
        .name = "email",
        .column_type = .text,
        .nullable = false,
        .unique = true,
    })
        .column(.{
        .name = "created_at",
        .column_type = .bigint,
        .nullable = false,
        .default_value = "EXTRACT(EPOCH FROM NOW())::BIGINT",
    })
        .column(.{
        .name = "updated_at",
        .column_type = .bigint,
        .nullable = false,
        .default_value = "EXTRACT(EPOCH FROM NOW())::BIGINT",
    });

    try query.exec();
    std.debug.print("  ✓ users\n", .{});
}

/// 创建文章表
fn createPostsTable(db: *zorm.DB(.postgresql), allocator: std.mem.Allocator) !void {
    _ = allocator;
    var query = try db.newCreateTable("posts");
    defer query.deinit();

    _ = try query
        .ifNotExists()
        .column(.{
        .name = "id",
        .column_type = .bigserial,
        .primary_key = true,
        .nullable = false,
    })
        .column(.{
        .name = "user_id",
        .column_type = .bigint,
        .nullable = false,
        .foreign_key = .{
            .table = "users",
            .column = "id",
            .on_delete = .cascade,
        },
    })
        .column(.{
        .name = "title",
        .column_type = .text,
        .nullable = false,
    })
        .column(.{
        .name = "content",
        .column_type = .text,
        .nullable = false,
    })
        .column(.{
        .name = "status",
        .column_type = .text,
        .nullable = false,
        .default_value = "'draft'",
        .check_expr = "status IN ('draft', 'published', 'archived')",
    })
        .column(.{
        .name = "published_at",
        .column_type = .bigint,
        .nullable = true,
    })
        .column(.{
        .name = "created_at",
        .column_type = .bigint,
        .nullable = false,
        .default_value = "EXTRACT(EPOCH FROM NOW())::BIGINT",
    })
        .column(.{
        .name = "updated_at",
        .column_type = .bigint,
        .nullable = false,
        .default_value = "EXTRACT(EPOCH FROM NOW())::BIGINT",
    });

    try query.exec();
    std.debug.print("  ✓ posts\n", .{});
}

/// 创建评论表
fn createCommentsTable(db: *zorm.DB(.postgresql), allocator: std.mem.Allocator) !void {
    _ = allocator;
    var query = try db.newCreateTable("comments");
    defer query.deinit();

    _ = try query
        .ifNotExists()
        .column(.{
        .name = "id",
        .column_type = .bigserial,
        .primary_key = true,
        .nullable = false,
    })
        .column(.{
        .name = "post_id",
        .column_type = .bigint,
        .nullable = false,
        .foreign_key = .{
            .table = "posts",
            .column = "id",
            .on_delete = .cascade,
        },
    })
        .column(.{
        .name = "user_id",
        .column_type = .bigint,
        .nullable = false,
        .foreign_key = .{
            .table = "users",
            .column = "id",
            .on_delete = .cascade,
        },
    })
        .column(.{
        .name = "content",
        .column_type = .text,
        .nullable = false,
    })
        .column(.{
        .name = "created_at",
        .column_type = .bigint,
        .nullable = false,
        .default_value = "EXTRACT(EPOCH FROM NOW())::BIGINT",
    });

    try query.exec();
    std.debug.print("  ✓ comments\n", .{});
}

/// 创建标签表
fn createTagsTable(db: *zorm.DB(.postgresql), allocator: std.mem.Allocator) !void {
    _ = allocator;
    var query = try db.newCreateTable("tags");
    defer query.deinit();

    _ = try query
        .ifNotExists()
        .column(.{
        .name = "id",
        .column_type = .bigserial,
        .primary_key = true,
        .nullable = false,
    })
        .column(.{
        .name = "name",
        .column_type = .text,
        .nullable = false,
        .unique = true,
    });

    try query.exec();
    std.debug.print("  ✓ tags\n", .{});
}

/// 创建文章-标签关联表
fn createPostTagsTable(db: *zorm.DB(.postgresql), allocator: std.mem.Allocator) !void {
    _ = allocator;
    var query = try db.newCreateTable("post_tags");
    defer query.deinit();

    _ = try query
        .ifNotExists()
        .column(.{
        .name = "post_id",
        .column_type = .bigint,
        .nullable = false,
        .primary_key = true, // 组合主键的第一部分
        .foreign_key = .{
            .table = "posts",
            .column = "id",
            .on_delete = .cascade,
        },
    })
        .column(.{
        .name = "tag_id",
        .column_type = .bigint,
        .nullable = false,
        .primary_key = true, // 组合主键的第二部分
        .foreign_key = .{
            .table = "tags",
            .column = "id",
            .on_delete = .cascade,
        },
    });

    try query.exec();
    std.debug.print("  ✓ post_tags\n", .{});
}

/// 创建索引 (暂时使用原始 SQL，后续可扩展为 CreateIndexQuery API)
fn createIndexes(db: *zorm.DB(.postgresql)) !void {
    // 文章相关索引
    try db.exec("CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id)", &.{});
    try db.exec("CREATE INDEX IF NOT EXISTS idx_posts_status ON posts(status)", &.{});
    std.debug.print("  ✓ posts 索引\n", .{});

    // 评论相关索引
    try db.exec("CREATE INDEX IF NOT EXISTS idx_comments_post_id ON comments(post_id)", &.{});
    try db.exec("CREATE INDEX IF NOT EXISTS idx_comments_user_id ON comments(user_id)", &.{});
    std.debug.print("  ✓ comments 索引\n", .{});

    // 标签关联索引
    try db.exec("CREATE INDEX IF NOT EXISTS idx_post_tags_tag_id ON post_tags(tag_id)", &.{});
    std.debug.print("  ✓ post_tags 索引\n", .{});
}
