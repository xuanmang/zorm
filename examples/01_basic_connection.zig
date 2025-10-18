//! 示例 01: 基础数据库连接
//!
//! 本示例展示如何:
//! - 建立数据库连接
//! - 配置连接选项
//! - 测试连接是否成功
//! - 正确处理错误和资源清理
//!
//! 运行方式: zig build run-example -Dexample=01_basic_connection

const std = @import("std");
const zorm = @import("zorm");
const db_config = @import("common/db_config.zig");

pub fn main() !void {
    // 使用 GPA allocator 确保内存安全
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("⚠️  内存泄漏检测到!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 01: 基础数据库连接 ===\n\n", .{});

    // ========================================
    // 方式 1: 使用默认配置连接
    // ========================================
    std.debug.print("方式 1: 使用默认配置连接数据库\n", .{});
    std.debug.print("---------------------------------------\n", .{});

    const default_config = db_config.getDefaultConfig();
    std.debug.print("配置信息:\n", .{});
    std.debug.print("  Host:     {s}\n", .{default_config.host});
    std.debug.print("  Port:     {d}\n", .{default_config.port});
    std.debug.print("  User:     {s}\n", .{default_config.user});
    std.debug.print("  Database: {s}\n\n", .{default_config.dbname});

    std.debug.print("正在连接...\n", .{});
    var db = db_config.createDefaultDBInstance(allocator) catch |err| {
        // 错误处理: 友好的错误提示
        std.debug.print("❌ 连接失败: {}\n", .{err});
        std.debug.print("\n💡 提示:\n", .{});
        std.debug.print("  1. 确保 PostgreSQL 服务正在运行\n", .{});
        std.debug.print("  2. 检查数据库配置是否正确\n", .{});
        std.debug.print("  3. 运行 'zig build run-setup' 初始化数据库\n\n", .{});
        return err;
    };
    defer db.deinit();
    std.debug.print("✓ 数据库连接成功!\n\n", .{});

    // ========================================
    // 测试连接
    // ========================================
    std.debug.print("测试连接状态\n", .{});
    std.debug.print("---------------------------------------\n", .{});

    // 使用简单查询测试连接
    std.debug.print("执行测试查询: SELECT 1 AS test...\n", .{});
    const test_result = db.conn.query("SELECT 1 AS test", &.{}) catch |err| {
        std.debug.print("❌ 查询失败: {}\n\n", .{err});
        return err;
    };
    defer test_result.close();

    std.debug.print("✓ 查询执行成功\n", .{});

    // 获取数据库版本信息
    std.debug.print("\n获取数据库版本...\n", .{});
    const version_result = db.conn.query("SELECT version()", &.{}) catch |err| {
        std.debug.print("❌ 获取版本失败: {}\n\n", .{err});
        return err;
    };
    defer version_result.close();

    var version_rows = version_result.rows;
    if (try version_rows.next()) |row| {
        const version = try row.get([]const u8, 0);
        // 只打印版本号的前80个字符以保持输出简洁
        const display_len = @min(80, version.len);
        std.debug.print("✓ PostgreSQL: {s}...\n", .{version[0..display_len]});
    }

    // ========================================
    // 方式 2: 使用自定义配置
    // ========================================
    std.debug.print("\n方式 2: 使用自定义配置\n", .{});
    std.debug.print("---------------------------------------\n", .{});

    const custom_config = db_config.DBConfig{
        .host = "127.0.0.1",
        .port = 5432,
        .user = "pguser",
        .password = "Pg#123!",
        .dbname = "postgres",
    };

    std.debug.print("使用自定义配置连接...\n", .{});
    var custom_db = db_config.createDBInstance(allocator, custom_config) catch |err| {
        std.debug.print("❌ 连接失败: {}\n\n", .{err});
        return err;
    };
    defer custom_db.deinit();
    std.debug.print("✓ 自定义配置连接成功\n\n", .{});

    // ========================================
    // 查看连接统计信息
    // ========================================
    std.debug.print("连接统计信息\n", .{});
    std.debug.print("---------------------------------------\n", .{});
    std.debug.print("执行的查询数: {d}\n", .{db.stats.total_queries});
    std.debug.print("错误数:       {d}\n", .{db.stats.total_errors});
    std.debug.print("活动事务数:   {d}\n", .{db.stats.active_transactions});

    std.debug.print("\n✅ 示例执行完成!\n", .{});
    std.debug.print("\n📚 下一步:\n", .{});
    std.debug.print("  - 示例 02: 学习 SELECT 查询\n", .{});
    std.debug.print("  - 示例 03: 学习 INSERT 操作\n\n", .{});
}
