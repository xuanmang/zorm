//! 类型映射示例
//!
//! 学习目标:
//! - PostgreSQL 类型到 Zig 类型的映射
//! - 处理 NULL 值
//! - 时间戳和日期处理
//! - 数组和 JSON 类型
//!
//! 对应功能需求: FR7
//! 难度: 中级

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 14: 类型映射 ===\n\n", .{});

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

    // 示例 1: 基础类型映射
    try basicTypeMapping(&conn);

    // 示例 2: NULL 值处理
    try nullHandling(&conn);

    // 示例 3: 时间戳处理
    try timestampHandling(&conn);

    // 示例 4: 布尔和枚举类型
    try booleanAndEnum(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn basicTypeMapping(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 基础类型映射\n", .{});

    // why: 演示 PostgreSQL 各种基础类型到 Zig 的映射
    var result_opt = try conn.row(
        \\SELECT
        \\    1::SMALLINT as small_int,
        \\    100::INTEGER as int,
        \\    1000000::BIGINT as big_int,
        \\    3.14::REAL as float,
        \\    3.14159265::DOUBLE PRECISION as double,
        \\    'Hello'::VARCHAR as varchar,
        \\    'World'::TEXT as text
    ,
        .{},
    );

    if (result_opt) |*result| {
        defer result.deinit() catch {};

        const small_int = result.get(i16, 0);
        const int = result.get(i32, 1);
        const big_int = result.get(i64, 2);
        const float = result.get(f32, 3);
        const double = result.get(f64, 4);
        const varchar = result.get([]const u8, 5);
        const text = result.get([]const u8, 6);

        std.debug.print("  类型映射结果:\n", .{});
        std.debug.print("    SMALLINT → i16: {d}\n", .{small_int});
        std.debug.print("    INTEGER → i32: {d}\n", .{int});
        std.debug.print("    BIGINT → i64: {d}\n", .{big_int});
        std.debug.print("    REAL → f32: {d}\n", .{float});
        std.debug.print("    DOUBLE PRECISION → f64: {d}\n", .{double});
        std.debug.print("    VARCHAR → []const u8: {s}\n", .{varchar});
        std.debug.print("    TEXT → []const u8: {s}\n\n", .{text});
    }
}

fn nullHandling(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: NULL 值处理\n", .{});

    // why: 使用可选类型 ?T 处理 NULL
    var result_opt = try conn.row(
        \\SELECT
        \\    id,
        \\    title,
        \\    published_at,
        \\    slug
        \\FROM zorm_examples.posts
        \\WHERE id = 1
    ,
        .{},
    );

    if (result_opt) |*result| {
        defer result.deinit() catch {};

        const id = result.get(i64, 0);
        const title = result.get([]const u8, 1);
        const published_at_opt = result.get(?f64, 2);
        const slug_opt = result.get(?[]const u8, 3);

        std.debug.print("  文章信息:\n", .{});
        std.debug.print("    ID: {d}\n", .{id});
        std.debug.print("    标题: {s}\n", .{title});

        // why: 使用 if 解包可选类型
        if (published_at_opt) |published_at| {
            std.debug.print("    发布时间: {d}\n", .{published_at});
        } else {
            std.debug.print("    发布时间: NULL (未发布)\n", .{});
        }

        if (slug_opt) |slug| {
            std.debug.print("    Slug: {s}\n\n", .{slug});
        } else {
            std.debug.print("    Slug: NULL (未设置)\n\n", .{});
        }
    }
}

fn timestampHandling(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: 时间戳处理\n", .{});

    // why: PostgreSQL EXTRACT(EPOCH) 返回浮点数秒，Zig 用 f64 接收
    var result_opt = try conn.row(
        \\SELECT
        \\    EXTRACT(EPOCH FROM NOW()) as current_timestamp,
        \\    EXTRACT(EPOCH FROM NOW())::BIGINT as timestamp_int,
        \\    EXTRACT(EPOCH FROM NOW() + INTERVAL '1 day') as tomorrow,
        \\    EXTRACT(EPOCH FROM NOW() - INTERVAL '1 day') as yesterday
    ,
        .{},
    );

    if (result_opt) |*result| {
        defer result.deinit() catch {};

        const current_timestamp = result.get(f64, 0);
        const timestamp_int = result.get(i64, 1);
        const tomorrow = result.get(f64, 2);
        const yesterday = result.get(f64, 3);

        std.debug.print("  时间戳处理:\n", .{});
        std.debug.print("    当前时间（f64）: {d}\n", .{current_timestamp});
        std.debug.print("    当前时间（i64）: {d}\n", .{timestamp_int});
        std.debug.print("    明天: {d}\n", .{tomorrow});
        std.debug.print("    昨天: {d}\n", .{yesterday});

        // 计算时间差
        const day_diff = tomorrow - yesterday;
        std.debug.print("    明天 - 昨天 = {d} 秒 ({d} 天)\n\n", .{ day_diff, day_diff / 86400.0 });
    }
}

fn booleanAndEnum(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 4: 布尔和枚举类型\n", .{});

    // why: PostgreSQL BOOLEAN 映射到 Zig bool，枚举用 VARCHAR
    var result = try conn.query(
        \\SELECT
        \\    id,
        \\    title,
        \\    status,
        \\    (status = 'published') as is_published,
        \\    (published_at IS NOT NULL) as has_published_at
        \\FROM zorm_examples.posts
        \\ORDER BY id
        \\LIMIT 5
    ,
        .{},
    );
    defer result.deinit();

    std.debug.print("  布尔和状态信息:\n", .{});
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const title = row.get([]const u8, 1);
        const status = row.get([]const u8, 2);
        const is_published = row.get(bool, 3);
        const has_published_at = row.get(bool, 4);

        std.debug.print("    [{d}] {s}\n", .{ id, title });
        std.debug.print("         状态: {s}\n", .{status});
        std.debug.print("         是否已发布: {}\n", .{is_published});
        std.debug.print("         有发布时间: {}\n", .{has_published_at});

        // why: 根据布尔值进行条件判断
        if (is_published and has_published_at) {
            std.debug.print("         ✓ 状态一致\n", .{});
        } else if (is_published and !has_published_at) {
            std.debug.print("         ⚠ 状态不一致（已发布但无时间戳）\n", .{});
        }
    }
}
