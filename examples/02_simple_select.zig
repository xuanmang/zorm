//! 简单 SELECT 查询示例
//!
//! 学习目标:
//! - 执行基本的 SELECT 查询
//! - 扫描查询结果
//! - 处理单行和多行结果
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

    std.debug.print("=== ZORM 示例 02: 简单 SELECT 查询 ===\n\n", .{});

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

    var conn = try pool.acquire();
    defer conn.release();

    // 示例 1: 查询单行
    try querySingleRow(&conn);

    // 示例 2: 查询多行
    try queryMultipleRows(&conn);

    // 示例 3: 使用 WHERE 条件
    try queryWithWhere(&conn);

    // 示例 4: 查询指定列
    try querySpecificColumns(&conn);

    // 示例 5: 使用 ORDER BY
    try queryWithOrderBy(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn querySingleRow(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 查询单行\n", .{});

    var result_opt = try conn.row(
        "SELECT id, name, email FROM zorm_examples.users WHERE id = $1",
        .{1},
    );

    if (result_opt) |*result| {
        defer result.deinit() catch {};
        const id = result.get(i64, 0);
        const name = result.get([]const u8, 1);
        const email = result.get([]const u8, 2);

        std.debug.print("  用户 #{d}: {s} <{s}>\n\n", .{ id, name, email });
    } else {
        std.debug.print("  未找到 id=1 的用户\n\n", .{});
    }
}

fn queryMultipleRows(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: 查询多行\n", .{});

    var result = try conn.query(
        "SELECT id, name, email FROM zorm_examples.users ORDER BY id",
        .{},
    );
    defer result.deinit();

    var count: usize = 0;
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const name = row.get([]const u8, 1);
        const email = row.get([]const u8, 2);

        std.debug.print("  用户 #{d}: {s} <{s}>\n", .{ id, name, email });
        count += 1;
    }

    std.debug.print("  总计: {d} 条记录\n\n", .{count});
}

fn queryWithWhere(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: 使用 WHERE 条件\n", .{});

    // 使用参数化查询防止 SQL 注入
    // why: $1, $2 等占位符确保参数被正确转义
    var result = try conn.query(
        "SELECT id, name, email FROM zorm_examples.users WHERE email LIKE $1",
        .{"%example.com%"},
    );
    defer result.deinit();

    var count: usize = 0;
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const name = row.get([]const u8, 1);
        const email = row.get([]const u8, 2);

        std.debug.print("  用户 #{d}: {s} <{s}>\n", .{ id, name, email });
        count += 1;
    }

    std.debug.print("  找到 {d} 个 example.com 域名的用户\n\n", .{count});
}

fn querySpecificColumns(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 4: 查询指定列\n", .{});

    // 只查询需要的列，提升性能
    var result = try conn.query(
        "SELECT name FROM zorm_examples.users ORDER BY name",
        .{},
    );
    defer result.deinit();

    std.debug.print("  用户名列表:\n", .{});
    while (try result.next()) |row| {
        const name = row.get([]const u8, 0);
        std.debug.print("    - {s}\n", .{name});
    }
    std.debug.print("\n", .{});
}

fn queryWithOrderBy(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 5: 使用 ORDER BY 排序\n", .{});

    var result = try conn.query(
        "SELECT id, name FROM zorm_examples.users ORDER BY name DESC LIMIT 3",
        .{},
    );
    defer result.deinit();

    std.debug.print("  前 3 个用户（按名称降序）:\n", .{});
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const name = row.get([]const u8, 1);
        std.debug.print("    #{d}: {s}\n", .{ id, name });
    }
}
