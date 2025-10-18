//! INSERT 操作示例
//!
//! 学习目标:
//! - 执行单条 INSERT
//! - 批量 INSERT 操作
//! - 使用 RETURNING 获取插入的 ID
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

    std.debug.print("=== ZORM 示例 03: INSERT 操作 ===\n\n", .{});

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

    // 示例 1: 单条插入
    try singleInsert(&conn);

    // 示例 2: 插入并返回 ID
    try insertWithReturning(&conn);

    // 示例 3: 批量插入
    try batchInsert(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn singleInsert(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 单条插入\n", .{});

    // 插入一个新用户
    const affected = try conn.exec(
        \\INSERT INTO zorm_examples.users (name, email, created_at, updated_at)
        \\VALUES ($1, $2, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
    ,
        .{ "Charlie", "charlie@example.com" },
    );

    if (affected) |rows| {
        std.debug.print("  ✓ 插入成功，影响 {d} 行\n\n", .{rows});
    }
}

fn insertWithReturning(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: 插入并返回 ID\n", .{});

    // 使用 RETURNING 获取插入记录的 ID
    // why: 避免额外的查询来获取自动生成的 ID
    var result_opt = try conn.row(
        \\INSERT INTO zorm_examples.users (name, email, created_at, updated_at)
        \\VALUES ($1, $2, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
        \\RETURNING id
    ,
        .{ "David", "david@example.com" },
    );

    if (result_opt) |*result| {
        defer result.deinit() catch {};
        const user_id = result.get(i64, 0);
        std.debug.print("  ✓ 新用户 ID: {d}\n", .{user_id});

        // 使用返回的 ID 插入关联数据
        _ = try conn.exec(
            \\INSERT INTO zorm_examples.posts (user_id, title, content, status, created_at, updated_at)
            \\VALUES ($1, $2, $3, $4, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
        ,
            .{ user_id, "David 的第一篇文章", "这是内容", "published" },
        );

        std.debug.print("  ✓ 为用户 {d} 创建了一篇文章\n\n", .{user_id});
    }
}

fn batchInsert(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: 批量插入\n", .{});

    // 使用 VALUES 多行语法进行批量插入
    // why: 比逐条插入性能更好，减少网络往返
    const affected = try conn.exec(
        \\INSERT INTO zorm_examples.tags (name)
        \\VALUES ('Zig'), ('WebDev'), ('Database'), ('Performance')
        \\ON CONFLICT (name) DO NOTHING
    ,
        .{},
    );

    if (affected) |rows| {
        std.debug.print("  ✓ 批量插入成功，影响 {d} 行\n", .{rows});
    }

    // 查询插入的标签
    var result = try conn.query(
        "SELECT id, name FROM zorm_examples.tags ORDER BY name",
        .{},
    );
    defer result.deinit();

    std.debug.print("  标签列表:\n", .{});
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const name = row.get([]const u8, 1);
        std.debug.print("    - [{d}] {s}\n", .{ id, name });
    }
}
