//! 连接池管理示例
//!
//! 学习目标:
//! - 连接池配置
//! - 连接获取和释放
//! - 并发连接管理
//! - 连接池性能优化
//!
//! 对应功能需求: FR1
//! 难度: 中级

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 17: 连接池管理 ===\n\n", .{});

    const db_config = config.Config.default();

    // 示例 1: 基础连接池配置
    try basicPoolConfiguration(allocator, &db_config);

    // 示例 2: 连接获取和释放
    try connectionAcquireRelease(allocator, &db_config);

    // 示例 3: 并发连接管理
    try concurrentConnections(allocator, &db_config);

    // 示例 4: 连接池统计
    try poolStatistics(allocator, &db_config);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn basicPoolConfiguration(allocator: std.mem.Allocator, db_config: *const config.Config) !void {
    std.debug.print("📌 示例 1: 基础连接池配置\n", .{});

    // why: 连接池大小决定最大并发连接数
    var pool = try pg.Pool.init(allocator, .{
        .size = 3, // 最多 3 个并发连接
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

    std.debug.print("  ✓ 连接池创建成功\n", .{});
    std.debug.print("  配置:\n", .{});
    std.debug.print("    - 池大小: 3\n", .{});
    std.debug.print("    - 主机: {s}\n", .{db_config.host});
    std.debug.print("    - 端口: {d}\n", .{db_config.port});
    std.debug.print("    - 数据库: {s}\n\n", .{db_config.database});
}

fn connectionAcquireRelease(allocator: std.mem.Allocator, db_config: *const config.Config) !void {
    std.debug.print("📌 示例 2: 连接获取和释放\n", .{});

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

    // why: 使用 defer 确保连接正确释放
    {
        var conn1 = try pool.acquire();
        defer conn1.release();
        std.debug.print("  ✓ 获取连接 1\n", .{});

        var result1_opt = try conn1.row("SELECT 1", .{});
        if (result1_opt) |*result1| {
            defer result1.deinit() catch {};
            const val = result1.get(i32, 0);
            std.debug.print("    查询结果: {d}\n", .{val});
        }
    } // conn1 在这里自动释放

    std.debug.print("  ✓ 连接 1 已释放\n", .{});

    {
        var conn2 = try pool.acquire();
        defer conn2.release();
        std.debug.print("  ✓ 获取连接 2（复用连接池）\n", .{});

        var result2_opt = try conn2.row("SELECT 2", .{});
        if (result2_opt) |*result2| {
            defer result2.deinit() catch {};
            const val = result2.get(i32, 0);
            std.debug.print("    查询结果: {d}\n\n", .{val});
        }
    }
}

fn concurrentConnections(allocator: std.mem.Allocator, db_config: *const config.Config) !void {
    std.debug.print("📌 示例 3: 并发连接管理\n", .{});

    var pool = try pg.Pool.init(allocator, .{
        .size = 3,
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

    // why: 模拟多个并发连接
    var conn1 = try pool.acquire();
    defer conn1.release();
    std.debug.print("  ✓ 并发连接 1 已获取\n", .{});

    var conn2 = try pool.acquire();
    defer conn2.release();
    std.debug.print("  ✓ 并发连接 2 已获取\n", .{});

    var conn3 = try pool.acquire();
    defer conn3.release();
    std.debug.print("  ✓ 并发连接 3 已获取（池已满）\n", .{});

    // 并发执行查询
    var result1 = try conn1.query("SELECT 'Connection 1' as conn", .{});
    defer result1.deinit();

    var result2 = try conn2.query("SELECT 'Connection 2' as conn", .{});
    defer result2.deinit();

    var result3 = try conn3.query("SELECT 'Connection 3' as conn", .{});
    defer result3.deinit();

    std.debug.print("  ✓ 3 个并发查询执行中\n", .{});

    // 读取结果
    if (try result1.next()) |row| {
        const conn_name = row.get([]const u8, 0);
        std.debug.print("    {s}\n", .{conn_name});
    }

    if (try result2.next()) |row| {
        const conn_name = row.get([]const u8, 0);
        std.debug.print("    {s}\n", .{conn_name});
    }

    if (try result3.next()) |row| {
        const conn_name = row.get([]const u8, 0);
        std.debug.print("    {s}\n\n", .{conn_name});
    }
}

fn poolStatistics(allocator: std.mem.Allocator, db_config: *const config.Config) !void {
    std.debug.print("📌 示例 4: 连接池统计\n", .{});

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

    std.debug.print("  连接池信息:\n", .{});
    std.debug.print("    - 池容量: 5\n", .{});

    // 获取 2 个连接
    var conn1 = try pool.acquire();
    defer conn1.release();

    var conn2 = try pool.acquire();
    defer conn2.release();

    std.debug.print("    - 当前已获取: 2\n", .{});
    std.debug.print("    - 可用连接: 3\n", .{});

    // 执行一些查询
    _ = try conn1.exec("SELECT pg_sleep(0.01)", .{});
    _ = try conn2.exec("SELECT pg_sleep(0.01)", .{});

    std.debug.print("  ✓ 连接池性能良好\n", .{});
    std.debug.print("\n说明:\n", .{});
    std.debug.print("  - 连接池复用连接，避免频繁建立/关闭\n", .{});
    std.debug.print("  - 合理配置池大小平衡并发和资源\n", .{});
    std.debug.print("  - 始终使用 defer 确保连接释放\n", .{});
}
