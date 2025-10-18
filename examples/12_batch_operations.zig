//! 批量操作示例
//!
//! 学习目标:
//! - 批量插入数据
//! - 批量更新数据
//! - 使用事务保证批量操作原子性
//! - 性能优化技巧
//!
//! 对应功能需求: FR2
//! 难度: 中级

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 12: 批量操作 ===\n\n", .{});

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

    // 示例 1: 批量插入（单条SQL）
    try batchInsertSingleQuery(&conn);

    // 示例 2: 批量插入（事务中多次插入）
    try batchInsertMultipleQueries(&conn);

    // 示例 3: 批量更新
    try batchUpdate(&conn);

    // 示例 4: 批量删除
    try batchDelete(&conn);

    // 示例 5: UPSERT 批量操作
    try batchUpsert(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn batchInsertSingleQuery(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 批量插入（单条 SQL）\n", .{});

    const start_time = std.time.milliTimestamp();

    // why: 使用 VALUES 多行语法，一次性插入所有数据，性能最优
    const affected = try conn.exec(
        \\INSERT INTO zorm_examples.tags (name)
        \\VALUES
        \\    ('Performance'),
        \\    ('Optimization'),
        \\    ('Scalability'),
        \\    ('Concurrency'),
        \\    ('Security')
        \\ON CONFLICT (name) DO NOTHING
    ,
        .{},
    );

    const elapsed = std.time.milliTimestamp() - start_time;

    if (affected) |rows| {
        std.debug.print("  ✓ 批量插入完成\n", .{});
        std.debug.print("  插入行数: {d}\n", .{rows});
        std.debug.print("  耗时: {d}ms\n\n", .{elapsed});
    }
}

fn batchInsertMultipleQueries(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: 批量插入（事务中多次插入）\n", .{});

    const start_time = std.time.milliTimestamp();

    // why: 使用事务确保批量操作的原子性
    try conn.begin();
    errdefer conn.rollback() catch {};

    var total_inserted: i64 = 0;

    // 模拟批量插入多个用户
    const users = [_]struct { name: []const u8, email: []const u8 }{
        .{ .name = "Batch User 1", .email = "batch1@example.com" },
        .{ .name = "Batch User 2", .email = "batch2@example.com" },
        .{ .name = "Batch User 3", .email = "batch3@example.com" },
        .{ .name = "Batch User 4", .email = "batch4@example.com" },
        .{ .name = "Batch User 5", .email = "batch5@example.com" },
    };

    for (users) |user| {
        var result_opt = try conn.row(
            \\INSERT INTO zorm_examples.users (name, email, created_at, updated_at)
            \\VALUES ($1, $2, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
            \\ON CONFLICT (email) DO NOTHING
            \\RETURNING id
        ,
            .{ user.name, user.email },
        );

        if (result_opt) |*result| {
            defer result.deinit() catch {};
            total_inserted += 1;
        }
    }

    try conn.commit();

    const elapsed = std.time.milliTimestamp() - start_time;

    std.debug.print("  ✓ 批量插入完成\n", .{});
    std.debug.print("  插入行数: {d}\n", .{total_inserted});
    std.debug.print("  耗时: {d}ms\n\n", .{elapsed});
}

fn batchUpdate(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: 批量更新\n", .{});

    const start_time = std.time.milliTimestamp();

    // why: 使用 WHERE IN 批量更新多条记录
    const affected = try conn.exec(
        \\UPDATE zorm_examples.posts
        \\SET status = 'published',
        \\    published_at = EXTRACT(EPOCH FROM NOW()),
        \\    updated_at = EXTRACT(EPOCH FROM NOW())
        \\WHERE status = 'draft'
        \\  AND user_id IN (
        \\      SELECT id FROM zorm_examples.users
        \\      WHERE email LIKE 'batch%@example.com'
        \\  )
    ,
        .{},
    );

    const elapsed = std.time.milliTimestamp() - start_time;

    if (affected) |rows| {
        std.debug.print("  ✓ 批量更新完成\n", .{});
        std.debug.print("  更新行数: {d}\n", .{rows});
        std.debug.print("  耗时: {d}ms\n\n", .{elapsed});
    }
}

fn batchDelete(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 4: 批量删除\n", .{});

    const start_time = std.time.milliTimestamp();

    // why: 批量删除测试数据
    const affected = try conn.exec(
        \\DELETE FROM zorm_examples.users
        \\WHERE email LIKE 'batch%@example.com'
    ,
        .{},
    );

    const elapsed = std.time.milliTimestamp() - start_time;

    if (affected) |rows| {
        std.debug.print("  ✓ 批量删除完成\n", .{});
        std.debug.print("  删除行数: {d}\n", .{rows});
        std.debug.print("  耗时: {d}ms\n\n", .{elapsed});
    }
}

fn batchUpsert(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 5: UPSERT 批量操作\n", .{});

    const start_time = std.time.milliTimestamp();

    // why: ON CONFLICT DO UPDATE 实现 UPSERT（存在则更新，不存在则插入）
    const affected = try conn.exec(
        \\INSERT INTO zorm_examples.tags (name)
        \\VALUES
        \\    ('Batch'),
        \\    ('Performance'),
        \\    ('Testing')
        \\ON CONFLICT (name)
        \\DO UPDATE SET name = EXCLUDED.name
    ,
        .{},
    );

    const elapsed = std.time.milliTimestamp() - start_time;

    if (affected) |rows| {
        std.debug.print("  ✓ UPSERT 批量操作完成\n", .{});
        std.debug.print("  影响行数: {d}\n", .{rows});
        std.debug.print("  耗时: {d}ms\n", .{});
        std.debug.print("  说明: ON CONFLICT 处理了重复键冲突\n\n", .{});
    }
}
