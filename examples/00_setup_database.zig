//! 数据库初始化脚本
//!
//! 学习目标:
//! - 了解如何使用 pg.zig 执行 DDL 语句
//! - 理解 PostgreSQL Schema 的作用
//! - 掌握表创建和约束定义
//!
//! 难度: 基础

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 连接数据库
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

    std.debug.print("🔌 连接到数据库...\n", .{});

    var conn = try pool.acquire();
    defer conn.release();

    // 创建 schema
    std.debug.print("📦 创建 schema '{s}'...\n", .{config.EXAMPLES_SCHEMA});
    _ = conn.exec(
        "CREATE SCHEMA IF NOT EXISTS " ++ config.EXAMPLES_SCHEMA,
        .{},
    ) catch |err| {
        std.debug.print("❌ 创建 schema 失败: {}\n", .{err});
        if (conn.err) |pg_err| {
            std.debug.print("  PostgreSQL 错误: {s}\n", .{pg_err.message});
        }
        return err;
    };

    // 创建 users 表
    std.debug.print("📝 创建 users 表...\n", .{});
    _ = try conn.exec(
        \\CREATE TABLE IF NOT EXISTS zorm_examples.users (
        \\    id BIGSERIAL PRIMARY KEY,
        \\    name VARCHAR(100) NOT NULL,
        \\    email VARCHAR(255) UNIQUE NOT NULL,
        \\    created_at BIGINT NOT NULL,
        \\    updated_at BIGINT NOT NULL
        \\)
    ,
        .{},
    );

    // 创建 posts 表
    std.debug.print("📝 创建 posts 表...\n", .{});
    _ = try conn.exec(
        \\CREATE TABLE IF NOT EXISTS zorm_examples.posts (
        \\    id BIGSERIAL PRIMARY KEY,
        \\    user_id BIGINT NOT NULL REFERENCES zorm_examples.users(id) ON DELETE CASCADE,
        \\    title VARCHAR(255) NOT NULL,
        \\    content TEXT,
        \\    status VARCHAR(20) DEFAULT 'draft',
        \\    published_at BIGINT,
        \\    created_at BIGINT NOT NULL,
        \\    updated_at BIGINT NOT NULL,
        \\    CONSTRAINT valid_status CHECK (status IN ('draft', 'published', 'archived'))
        \\)
    ,
        .{},
    );

    // 创建 comments 表
    std.debug.print("📝 创建 comments 表...\n", .{});
    _ = try conn.exec(
        \\CREATE TABLE IF NOT EXISTS zorm_examples.comments (
        \\    id BIGSERIAL PRIMARY KEY,
        \\    post_id BIGINT NOT NULL REFERENCES zorm_examples.posts(id) ON DELETE CASCADE,
        \\    user_id BIGINT NOT NULL REFERENCES zorm_examples.users(id) ON DELETE CASCADE,
        \\    content TEXT NOT NULL,
        \\    created_at BIGINT NOT NULL
        \\)
    ,
        .{},
    );

    // 创建 tags 表
    std.debug.print("📝 创建 tags 表...\n", .{});
    _ = try conn.exec(
        \\CREATE TABLE IF NOT EXISTS zorm_examples.tags (
        \\    id BIGSERIAL PRIMARY KEY,
        \\    name VARCHAR(50) UNIQUE NOT NULL
        \\)
    ,
        .{},
    );

    // 创建 post_tags 关联表
    std.debug.print("📝 创建 post_tags 表...\n", .{});
    _ = try conn.exec(
        \\CREATE TABLE IF NOT EXISTS zorm_examples.post_tags (
        \\    post_id BIGINT NOT NULL REFERENCES zorm_examples.posts(id) ON DELETE CASCADE,
        \\    tag_id BIGINT NOT NULL REFERENCES zorm_examples.tags(id) ON DELETE CASCADE,
        \\    PRIMARY KEY (post_id, tag_id)
        \\)
    ,
        .{},
    );

    // 创建索引
    std.debug.print("🔍 创建索引...\n", .{});
    _ = try conn.exec(
        "CREATE INDEX IF NOT EXISTS idx_posts_user_id ON zorm_examples.posts(user_id)",
        .{},
    );
    _ = try conn.exec(
        "CREATE INDEX IF NOT EXISTS idx_posts_status ON zorm_examples.posts(status)",
        .{},
    );
    _ = try conn.exec(
        "CREATE INDEX IF NOT EXISTS idx_comments_post_id ON zorm_examples.comments(post_id)",
        .{},
    );

    // 插入种子数据
    std.debug.print("🌱 插入种子数据...\n", .{});
    _ = try conn.exec(
        \\INSERT INTO zorm_examples.users (name, email, created_at, updated_at)
        \\VALUES
        \\    ('Alice', 'alice@example.com', EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW())),
        \\    ('Bob', 'bob@example.com', EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
        \\ON CONFLICT (email) DO NOTHING
    ,
        .{},
    );

    _ = try conn.exec(
        \\INSERT INTO zorm_examples.tags (name)
        \\VALUES ('Zig'), ('PostgreSQL'), ('ORM'), ('Tutorial')
        \\ON CONFLICT (name) DO NOTHING
    ,
        .{},
    );

    std.debug.print("✅ 数据库初始化完成！\n", .{});
    std.debug.print("\n📊 统计信息:\n", .{});

    // 查询统计信息
    {
        var user_count_opt = try conn.row("SELECT COUNT(*) FROM zorm_examples.users", .{});
        if (user_count_opt) |*user_count| {
            defer user_count.deinit() catch {};
            const users = user_count.get(i64, 0);
            std.debug.print("  用户数: {d}\n", .{users});
        }
    }

    {
        var tag_count_opt = try conn.row("SELECT COUNT(*) FROM zorm_examples.tags", .{});
        if (tag_count_opt) |*tag_count| {
            defer tag_count.deinit() catch {};
            const tags = tag_count.get(i64, 0);
            std.debug.print("  标签数: {d}\n", .{tags});
        }
    }
}
