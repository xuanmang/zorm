//! Schema Management Example
//!
//! 演示如何使用 ZORM 的 CREATE TABLE Query Builder API 创建数据库表。
//!
//! 本示例展示:
//! - 自动从 Zig struct 生成 CREATE TABLE 语句
//! - Zig 类型到 PostgreSQL 类型的自动映射
//! - 主键自动检测 (id 字段)
//! - 可选类型处理 (?T → NULL)
//! - IF NOT EXISTS 子句

const std = @import("std");
const zorm = @import("zorm");

// 定义 User 模型
const User = struct {
    id: i64, // 自动识别为 PRIMARY KEY, BIGINT NOT NULL
    name: []const u8, // TEXT NOT NULL
    email: []const u8, // TEXT NOT NULL
    age: u32, // INTEGER NOT NULL (无符号整数 → INTEGER)
    score: f64, // DOUBLE PRECISION NOT NULL
    is_active: bool, // BOOLEAN NOT NULL
    bio: ?[]const u8, // TEXT (可选类型，允许 NULL)

    pub const table_name = "users";
};

// 定义 Post 模型
const Post = struct {
    id: i64, // PRIMARY KEY, BIGINT NOT NULL
    user_id: i64, // BIGINT NOT NULL (外键引用 users.id)
    title: []const u8, // TEXT NOT NULL
    content: ?[]const u8, // TEXT (可选)
    view_count: u32, // INTEGER NOT NULL
    created_at: ?[]const u8, // TEXT (可选，用于存储时间戳字符串)

    pub const table_name = "posts";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM Schema Management Example ===\n\n", .{});

    // 示例 1: 使用自动模式创建 User 表
    std.debug.print("1. 自动从 struct 生成 CREATE TABLE 语句:\n", .{});
    std.debug.print("-------------------------------------------\n", .{});

    const user_sql = try zorm.reflection.generateCreateTableSQL(User, .postgresql, allocator);
    defer allocator.free(user_sql);

    std.debug.print("User 表 SQL:\n{s}\n\n", .{user_sql});

    // 示例 2: 创建 Post 表
    std.debug.print("2. Post 表 (包含外键引用):\n", .{});
    std.debug.print("-------------------------------------------\n", .{});

    const post_sql = try zorm.reflection.generateCreateTableSQL(Post, .postgresql, allocator);
    defer allocator.free(post_sql);

    std.debug.print("Post 表 SQL:\n{s}\n\n", .{post_sql});

    // 示例 3: 类型映射展示
    std.debug.print("3. Zig 类型到 PostgreSQL 类型映射:\n", .{});
    std.debug.print("-------------------------------------------\n", .{});
    std.debug.print("i8, i16, i32    → SMALLINT\n", .{});
    std.debug.print("i64             → BIGINT\n", .{});
    std.debug.print("u8, u16, u32    → INTEGER\n", .{});
    std.debug.print("u64             → BIGINT\n", .{});
    std.debug.print("f32             → REAL\n", .{});
    std.debug.print("f64             → DOUBLE PRECISION\n", .{});
    std.debug.print("bool            → BOOLEAN\n", .{});
    std.debug.print("[]const u8      → TEXT\n", .{});
    std.debug.print("?T              → 对应类型 + NULL 允许\n\n", .{});

    // 示例 4: 主键检测规则
    std.debug.print("4. 主键检测规则:\n", .{});
    std.debug.print("-------------------------------------------\n", .{});
    std.debug.print("- 字段名为 'id' → 自动设置为 PRIMARY KEY\n", .{});
    std.debug.print("- 主键字段 → 自动添加 NOT NULL 约束\n\n", .{});

    // 示例 5: 可选类型处理
    std.debug.print("5. 可选类型 (?T) 处理:\n", .{});
    std.debug.print("-------------------------------------------\n", .{});
    std.debug.print("- bio: ?[]const u8 → TEXT (不添加 NOT NULL)\n", .{});
    std.debug.print("- content: ?[]const u8 → TEXT (不添加 NOT NULL)\n", .{});
    std.debug.print("- created_at: ?[]const u8 → TEXT (不添加 NOT NULL)\n\n", .{});

    std.debug.print("=== 示例完成 ===\n", .{});
}
