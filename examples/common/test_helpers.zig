//! 测试辅助函数
//!
//! 为示例提供数据清理、生成和验证功能

const std = @import("std");
const pg = @import("pg");
const config = @import("db_config.zig");

/// 清理指定表的所有数据
pub fn truncateTable(conn: *pg.Conn, table_name: []const u8) !void {
    const allocator = conn.allocator;
    const sql = try std.fmt.allocPrint(
        allocator,
        "TRUNCATE TABLE {s}.{s} CASCADE",
        .{ config.EXAMPLES_SCHEMA, table_name },
    );
    defer allocator.free(sql);

    _ = try conn.exec(sql, .{});
}

/// 清理所有示例表
pub fn cleanupAllTables(conn: *pg.Conn) !void {
    const tables = [_][]const u8{
        "post_tags",
        "comments",
        "posts",
        "tags",
        "users",
    };

    for (tables) |table| {
        try truncateTable(conn, table);
    }
}

/// 生成测试用户
pub fn createTestUser(
    conn: *pg.Conn,
    name: []const u8,
    email: []const u8,
) !i64 {
    const allocator = conn.allocator;
    const sql = try std.fmt.allocPrint(
        allocator,
        \\INSERT INTO {s}.users (name, email, created_at, updated_at)
        \\VALUES ($1, $2, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
        \\RETURNING id
    ,
        .{config.EXAMPLES_SCHEMA},
    );
    defer allocator.free(sql);

    var result = (try conn.row(sql, .{ name, email })) orelse return error.NoResult;
    defer result.deinit() catch {};

    return result.get(i64, 0);
}

/// 验证记录数量
pub fn assertCount(
    conn: *pg.Conn,
    table_name: []const u8,
    expected: i64,
) !void {
    const allocator = conn.allocator;
    const sql = try std.fmt.allocPrint(
        allocator,
        "SELECT COUNT(*) FROM {s}.{s}",
        .{ config.EXAMPLES_SCHEMA, table_name },
    );
    defer allocator.free(sql);

    var result = (try conn.row(sql, .{})) orelse return error.NoResult;
    defer result.deinit() catch {};

    const actual = result.get(i64, 0);
    if (actual != expected) {
        std.debug.print(
            "❌ 断言失败: 表 {s} 期望 {d} 条记录，实际 {d} 条\n",
            .{ table_name, expected, actual },
        );
        return error.AssertionFailed;
    }
}
