//! 数据库初始化脚本
//!
//! 创建示例应用所需的 schema 和表。
//! 运行方式: zig build run-setup
//!
//! 本脚本使用直接的 SQL 语句，简洁明了。

const std = @import("std");
const db_config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 数据库初始化 ===\n\n", .{});

    // 连接数据库
    std.debug.print("连接到 PostgreSQL...\n", .{});
    var driver = try db_config.createDefaultDriver(allocator);
    defer driver.close() catch {};
    std.debug.print("✓ 数据库连接成功\n\n", .{});

    // 创建 schema
    std.debug.print("创建 schema...\n", .{});
    _ = try driver.exec("CREATE SCHEMA IF NOT EXISTS zorm_examples", &.{});
    _ = try driver.exec("SET search_path TO zorm_examples", &.{});
    std.debug.print("✓ Schema 创建成功\n\n", .{});

    // 创建表
    std.debug.print("创建数据表...\n", .{});
    try createTables(&driver);
    std.debug.print("✓ 所有表创建成功\n\n", .{});

    // 创建索引
    std.debug.print("创建索引...\n", .{});
    try createIndexes(&driver);
    std.debug.print("✓ 所有索引创建成功\n\n", .{});

    std.debug.print("✅ 数据库初始化完成！\n", .{});
}

/// 创建所有数据表
fn createTables(driver: *@TypeOf(driver.*)) !void {
    // 1. 用户表
    _ = try driver.exec(
        \\CREATE TABLE IF NOT EXISTS users (
        \\  id BIGSERIAL PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  email TEXT NOT NULL UNIQUE,
        \\  created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT,
        \\  updated_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT
        \\)
    , &.{});
    std.debug.print("  ✓ users\n", .{});

    // 2. 文章表
    _ = try driver.exec(
        \\CREATE TABLE IF NOT EXISTS posts (
        \\  id BIGSERIAL PRIMARY KEY,
        \\  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        \\  title TEXT NOT NULL,
        \\  content TEXT NOT NULL,
        \\  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'archived')),
        \\  published_at BIGINT,
        \\  created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT,
        \\  updated_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT
        \\)
    , &.{});
    std.debug.print("  ✓ posts\n", .{});

    // 3. 评论表
    _ = try driver.exec(
        \\CREATE TABLE IF NOT EXISTS comments (
        \\  id BIGSERIAL PRIMARY KEY,
        \\  post_id BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
        \\  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        \\  content TEXT NOT NULL,
        \\  created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT
        \\)
    , &.{});
    std.debug.print("  ✓ comments\n", .{});

    // 4. 标签表
    _ = try driver.exec(
        \\CREATE TABLE IF NOT EXISTS tags (
        \\  id BIGSERIAL PRIMARY KEY,
        \\  name TEXT NOT NULL UNIQUE
        \\)
    , &.{});
    std.debug.print("  ✓ tags\n", .{});

    // 5. 文章-标签关联表
    _ = try driver.exec(
        \\CREATE TABLE IF NOT EXISTS post_tags (
        \\  post_id BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
        \\  tag_id BIGINT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
        \\  PRIMARY KEY (post_id, tag_id)
        \\)
    , &.{});
    std.debug.print("  ✓ post_tags\n", .{});
}

/// 创建所有索引
fn createIndexes(driver: *@TypeOf(driver.*)) !void {
    // 文章相关索引
    _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id)", &.{});
    _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_posts_status ON posts(status)", &.{});
    std.debug.print("  ✓ posts 索引\n", .{});

    // 评论相关索引
    _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_comments_post_id ON comments(post_id)", &.{});
    _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_comments_user_id ON comments(user_id)", &.{});
    std.debug.print("  ✓ comments 索引\n", .{});

    // 标签关联索引
    _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_post_tags_tag_id ON post_tags(tag_id)", &.{});
    std.debug.print("  ✓ post_tags 索引\n", .{});
}
