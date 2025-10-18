//! UPDATE 操作示例
//!
//! 学习目标:
//! - 执行单条 UPDATE
//! - 条件更新
//! - 批量更新
//!
//! 对应功能需求: FR2
//! 难度: 基础

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 04: UPDATE 操作 ===\n\n", .{});

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

    var conn = try pool.acquire();
    defer conn.release();

    // 示例 1: 单条更新
    try singleUpdate(&conn);

    // 示例 2: 条件更新
    try conditionalUpdate(&conn);

    // 示例 3: 批量更新
    try batchUpdate(&conn);

    // 示例 4: 使用 RETURNING
    try updateWithReturning(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn singleUpdate(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 单条更新\n", .{});

    // 更新指定用户的邮箱
    const affected = try conn.exec(
        \\UPDATE zorm_examples.users
        \\SET email = $1, updated_at = EXTRACT(EPOCH FROM NOW())
        \\WHERE id = $2
    ,
        .{ "alice.new@example.com", 1 },
    );

    if (affected) |rows| {
        std.debug.print("  ✓ 更新成功，影响 {d} 行\n\n", .{rows});
    }
}

fn conditionalUpdate(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: 条件更新\n", .{});

    // 更新所有草稿状态的文章为已发布
    const affected = try conn.exec(
        \\UPDATE zorm_examples.posts
        \\SET status = 'published',
        \\    published_at = EXTRACT(EPOCH FROM NOW()),
        \\    updated_at = EXTRACT(EPOCH FROM NOW())
        \\WHERE status = 'draft' AND user_id = $1
    ,
        .{1},
    );

    if (affected) |rows| {
        std.debug.print("  ✓ 发布了 {d} 篇草稿文章\n\n", .{rows});
    }
}

fn batchUpdate(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: 批量更新\n", .{});

    // 批量更新所有用户的 updated_at
    // why: 有时需要批量更新多条记录
    const affected = try conn.exec(
        \\UPDATE zorm_examples.users
        \\SET updated_at = EXTRACT(EPOCH FROM NOW())
        \\WHERE email LIKE '%example.com%'
    ,
        .{},
    );

    if (affected) |rows| {
        std.debug.print("  ✓ 批量更新成功，影响 {d} 行\n\n", .{rows});
    }
}

fn updateWithReturning(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 4: 使用 RETURNING 获取更新后的值\n", .{});

    // 更新并返回更新后的完整记录
    var result_opt = try conn.row(
        \\UPDATE zorm_examples.users
        \\SET name = $1, updated_at = EXTRACT(EPOCH FROM NOW())
        \\WHERE id = $2
        \\RETURNING id, name, email, updated_at
    ,
        .{ "Alice Smith", 1 },
    );

    if (result_opt) |*result| {
        defer result.deinit() catch {};
        const id = result.get(i64, 0);
        const name = result.get([]const u8, 1);
        const email = result.get([]const u8, 2);
        const updated_at = result.get(f64, 3);

        std.debug.print("  更新后的用户信息:\n", .{});
        std.debug.print("    ID: {d}\n", .{id});
        std.debug.print("    姓名: {s}\n", .{name});
        std.debug.print("    邮箱: {s}\n", .{email});
        std.debug.print("    更新时间: {d}\n", .{updated_at});
    }
}
