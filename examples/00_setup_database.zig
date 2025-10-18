//! 数据库初始化脚本
//!
//! 创建示例应用所需的 schema 和表。
//! 运行方式: zig build run-setup
//!
//! 本脚本展示 ZORM 高层级 DDL API 的最佳实践：
//! - 使用 db.newCreateTableEmpty() 构建类型安全的 DDL 查询
//! - 链式 API 简洁表达复杂表结构
//! - 统一的时间戳列定义减少重复代码
//! - db.newCreateIndex() 创建高性能索引

const std = @import("std");
const zorm = @import("zorm");
const db_config = @import("common/db_config.zig");

// ============================================
// 模型定义
// ============================================

const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    created_at: i64,
    updated_at: i64,

    pub const table_name = "users";
};

const Post = struct {
    id: i64,
    user_id: i64,
    title: []const u8,
    content: []const u8,
    status: []const u8,
    published_at: ?i64,
    created_at: i64,
    updated_at: i64,

    pub const table_name = "posts";
};

const Comment = struct {
    id: i64,
    post_id: i64,
    user_id: i64,
    content: []const u8,
    created_at: i64,

    pub const table_name = "comments";
};

const Tag = struct {
    id: i64,
    name: []const u8,

    pub const table_name = "tags";
};

const PostTag = struct {
    post_id: i64,
    tag_id: i64,

    pub const table_name = "post_tags";
};

// ============================================
// 公共列定义
// ============================================

/// 标准 ID 列（自增主键）
const ID_COLUMN = zorm.schema.Column{
    .name = "id",
    .column_type = .bigint,
    .primary_key = true,
    .auto_increment = true,
    .nullable = false,
};

/// 创建时间戳列
const CREATED_AT_COLUMN = zorm.schema.Column{
    .name = "created_at",
    .column_type = .bigint,
    .nullable = false,
    .default_value = "EXTRACT(EPOCH FROM NOW())::BIGINT",
};

/// 更新时间戳列
const UPDATED_AT_COLUMN = zorm.schema.Column{
    .name = "updated_at",
    .column_type = .bigint,
    .nullable = false,
    .default_value = "EXTRACT(EPOCH FROM NOW())::BIGINT",
};

/// 创建外键列定义
fn foreignKeyColumn(
    name: []const u8,
    ref_table: []const u8,
    ref_column: []const u8,
    on_delete: zorm.schema.Column.ForeignKeyRef.OnAction,
) zorm.schema.Column {
    return .{
        .name = name,
        .column_type = .bigint,
        .nullable = false,
        .foreign_key = .{
            .table = ref_table,
            .column = ref_column,
            .on_delete = on_delete,
        },
    };
}

// ============================================
// 主程序
// ============================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 数据库初始化 ===\n\n", .{});

    // 连接数据库
    std.debug.print("连接到 PostgreSQL...\n", .{});
    var db = try db_config.createDefaultDBInstance(allocator);
    defer db.deinit();
    std.debug.print("✓ 数据库连接成功\n\n", .{});

    // 创建 schema
    std.debug.print("创建 schema...\n", .{});
    try db.exec("CREATE SCHEMA IF NOT EXISTS zorm_examples", &.{});
    try db.exec("SET search_path TO zorm_examples", &.{});
    std.debug.print("✓ Schema 创建成功\n\n", .{});

    // 创建表
    std.debug.print("创建数据表...\n", .{});
    try createTables(db);
    std.debug.print("✓ 所有表创建成功\n\n", .{});

    // 创建索引
    std.debug.print("创建索引...\n", .{});
    try createIndexes(db);
    std.debug.print("✓ 所有索引创建成功\n\n", .{});

    std.debug.print("✅ 数据库初始化完成！\n", .{});
}

// ============================================
// 表创建函数
// ============================================

fn createTables(db: *zorm.DB(.postgresql)) !void {
    try createUsersTable(db);
    try createPostsTable(db);
    try createCommentsTable(db);
    try createTagsTable(db);
    try createPostTagsTable(db);
}

/// 创建用户表
fn createUsersTable(db: *zorm.DB(.postgresql)) !void {
    // var query = try db.newCreateTableEmpty(User);
    // defer query.deinit();

    // _ = query.ifNotExists();
    // _ = try query.column(ID_COLUMN);
    // _ = try query.column(.{
    //     .name = "name",
    //     .column_type = .text,
    //     .nullable = false,
    // });
    // _ = try query.column(.{
    //     .name = "email",
    //     .column_type = .text,
    //     .nullable = false,
    //     .unique = true,
    // });
    // _ = try query.column(CREATED_AT_COLUMN);
    // _ = try query.column(UPDATED_AT_COLUMN);

    // try query.exec();

    var query = try db.newCreateTable(User);

    defer query.deinit();

    try query.ifNotExists().exec();

    std.debug.print("  ✓ users\n", .{});
}

/// 创建文章表
fn createPostsTable(db: *zorm.DB(.postgresql)) !void {
    var query = try db.newCreateTableEmpty(Post);
    defer query.deinit();

    _ = query.ifNotExists();
    _ = try query.column(ID_COLUMN);
    _ = try query.column(foreignKeyColumn("user_id", "users", "id", .cascade));
    _ = try query.column(.{
        .name = "title",
        .column_type = .text,
        .nullable = false,
    });
    _ = try query.column(.{
        .name = "content",
        .column_type = .text,
        .nullable = false,
    });
    _ = try query.column(.{
        .name = "status",
        .column_type = .text,
        .nullable = false,
        .default_value = "'draft'",
        .check_expr = "status IN ('draft', 'published', 'archived')",
    });
    _ = try query.column(.{
        .name = "published_at",
        .column_type = .bigint,
        .nullable = true,
    });
    _ = try query.column(CREATED_AT_COLUMN);
    _ = try query.column(UPDATED_AT_COLUMN);

    try query.exec();
    std.debug.print("  ✓ posts\n", .{});
}

/// 创建评论表
fn createCommentsTable(db: *zorm.DB(.postgresql)) !void {
    var query = try db.newCreateTableEmpty(Comment);
    defer query.deinit();

    _ = query.ifNotExists();
    _ = try query.column(ID_COLUMN);
    _ = try query.column(foreignKeyColumn("post_id", "posts", "id", .cascade));
    _ = try query.column(foreignKeyColumn("user_id", "users", "id", .cascade));
    _ = try query.column(.{
        .name = "content",
        .column_type = .text,
        .nullable = false,
    });
    _ = try query.column(CREATED_AT_COLUMN);

    try query.exec();
    std.debug.print("  ✓ comments\n", .{});
}

/// 创建标签表
fn createTagsTable(db: *zorm.DB(.postgresql)) !void {
    var query = try db.newCreateTableEmpty(Tag);
    defer query.deinit();

    _ = query.ifNotExists();
    _ = try query.column(ID_COLUMN);
    _ = try query.column(.{
        .name = "name",
        .column_type = .text,
        .nullable = false,
        .unique = true,
    });

    try query.exec();
    std.debug.print("  ✓ tags\n", .{});
}

/// 创建文章-标签关联表（多对多）
fn createPostTagsTable(db: *zorm.DB(.postgresql)) !void {
    var query = try db.newCreateTableEmpty(PostTag);
    defer query.deinit();

    _ = query.ifNotExists();
    _ = try query.column(.{
        .name = "post_id",
        .column_type = .bigint,
        .nullable = false,
        .primary_key = true, // 组合主键第一部分
        .foreign_key = .{
            .table = "posts",
            .column = "id",
            .on_delete = .cascade,
        },
    });
    _ = try query.column(.{
        .name = "tag_id",
        .column_type = .bigint,
        .nullable = false,
        .primary_key = true, // 组合主键第二部分
        .foreign_key = .{
            .table = "tags",
            .column = "id",
            .on_delete = .cascade,
        },
    });

    try query.exec();
    std.debug.print("  ✓ post_tags\n", .{});
}

// ============================================
// 索引创建函数
// ============================================

fn createIndexes(db: *zorm.DB(.postgresql)) !void {
    try createPostsIndexes(db);
    try createCommentsIndexes(db);
    try createPostTagsIndexes(db);
}

/// 创建 posts 表索引
fn createPostsIndexes(db: *zorm.DB(.postgresql)) !void {
    // user_id 索引 - 用于查询某个用户的所有文章
    {
        var query = try db.newCreateIndex(Post, "idx_posts_user_id");
        defer query.deinit();
        _ = query.ifNotExists();
        _ = try query.column("user_id");
        try query.exec();
    }

    // status 索引 - 用于按状态过滤文章
    {
        var query = try db.newCreateIndex(Post, "idx_posts_status");
        defer query.deinit();
        _ = query.ifNotExists();
        _ = try query.column("status");
        try query.exec();
    }

    std.debug.print("  ✓ posts 索引\n", .{});
}

/// 创建 comments 表索引
fn createCommentsIndexes(db: *zorm.DB(.postgresql)) !void {
    // post_id 索引 - 用于查询某篇文章的所有评论
    {
        var query = try db.newCreateIndex(Comment, "idx_comments_post_id");
        defer query.deinit();
        _ = query.ifNotExists();
        _ = try query.column("post_id");
        try query.exec();
    }

    // user_id 索引 - 用于查询某个用户的所有评论
    {
        var query = try db.newCreateIndex(Comment, "idx_comments_user_id");
        defer query.deinit();
        _ = query.ifNotExists();
        _ = try query.column("user_id");
        try query.exec();
    }

    std.debug.print("  ✓ comments 索引\n", .{});
}

/// 创建 post_tags 表索引
fn createPostTagsIndexes(db: *zorm.DB(.postgresql)) !void {
    // tag_id 索引 - 用于查询使用某个标签的所有文章
    var query = try db.newCreateIndex(PostTag, "idx_post_tags_tag_id");
    defer query.deinit();
    _ = query.ifNotExists();
    _ = try query.column("tag_id");
    try query.exec();

    std.debug.print("  ✓ post_tags 索引\n", .{});
}
