//! 基础数据库连接示例
//!
//! 学习目标:
//! - 建立 PostgreSQL 数据库连接
//! - 配置连接参数
//! - 正确的错误处理和资源清理
//!
//! 对应功能需求: FR1
//! 难度: 基础

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("⚠️  检测到内存泄漏！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 01: 基础数据库连接 ===\n\n", .{});

    // 获取数据库配置
    // why: 使用配置模块统一管理连接参数，支持环境变量覆盖
    const db_config = config.Config.default();

    std.debug.print("📋 连接配置:\n", .{});
    std.debug.print("  主机: {s}\n", .{db_config.host});
    std.debug.print("  端口: {d}\n", .{db_config.port});
    std.debug.print("  用户: {s}\n", .{db_config.user});
    std.debug.print("  数据库: {s}\n\n", .{db_config.database});

    // 方式 1: 使用连接池（推荐用于生产环境）
    std.debug.print("🔌 方式 1: 使用连接池\n", .{});
    try demonstratePoolConnection(allocator, db_config);

    std.debug.print("\n", .{});

    // 方式 2: 单个连接（适合简单场景）
    std.debug.print("🔌 方式 2: 单个连接\n", .{});
    try demonstrateSingleConnection(allocator, db_config);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

/// 演示连接池的使用
fn demonstratePoolConnection(
    allocator: std.mem.Allocator,
    db_config: config.Config,
) !void {
    // 创建连接池
    // why: 连接池可以复用连接，提升性能，适合高并发场景
    var pool = try pg.Pool.init(allocator, .{
        .size = 5, // 连接池大小
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

    std.debug.print("  ✓ 连接池创建成功 (大小: 5)\n", .{});

    // 从池中获取连接
    var conn = try pool.acquire();
    defer conn.release(); // why: 使用 defer 确保连接归还到池中

    std.debug.print("  ✓ 从池中获取连接\n", .{});

    // 执行简单查询测试连接
    var result_opt = try conn.row("SELECT version()", .{});
    if (result_opt) |*result| {
        defer result.deinit() catch {};
        const version = result.get([]const u8, 0);
        std.debug.print("  ✓ PostgreSQL 版本: {s}\n", .{version});
    }
}

/// 演示单个连接的使用
fn demonstrateSingleConnection(
    allocator: std.mem.Allocator,
    db_config: config.Config,
) !void {
    // 创建单个连接
    // why: 对于简单脚本或低并发场景，单连接更简单
    var conn = try pg.Conn.openAndAuth(allocator, .{
        .host = db_config.host,
        .port = db_config.port,
    }, .{
        .username = db_config.user,
        .password = db_config.password,
        .database = db_config.database,
    });
    defer conn.deinit(); // why: 使用 defer 确保连接关闭

    std.debug.print("  ✓ 单个连接创建成功\n", .{});

    // 查询当前数据库名称
    {
        var result_opt = try conn.row("SELECT current_database()", .{});
        if (result_opt) |*result| {
            defer result.deinit() catch {};
            const db_name = result.get([]const u8, 0);
            std.debug.print("  ✓ 当前数据库: {s}\n", .{db_name});
        }
    }

    // 查询当前用户
    {
        var result_opt = try conn.row("SELECT current_user", .{});
        if (result_opt) |*result| {
            defer result.deinit() catch {};
            const user = result.get([]const u8, 0);
            std.debug.print("  ✓ 当前用户: {s}\n", .{user});
        }
    }
}
