//! 自定义连接选项示例
//!
//! 本示例演示如何使用 DBOptions 自定义数据库连接配置:
//! 1. 启用 Debug 模式
//! 2. 配置连接池参数
//! 3. 配置超时和日志选项
//! 4. 验证配置已正确应用
//!
//! 运行方式:
//! ```sh
//! zig build run-example-custom-options
//! ```

const std = @import("std");
const zorm = @import("zorm");

// 定义简单的测试模型
const TestModel = struct {
    id: i64 = 0,
    name: []const u8,

    pub const table_name = "test_custom_options";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n" ++ "=" ** 70 ++ "\n", .{});
    std.debug.print("ZORM 自定义连接选项示例\n", .{});
    std.debug.print("=" ** 70 ++ "\n\n", .{});

    const dsn = "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres";

    // ========================================
    // 示例 1: 使用默认配置
    // ========================================
    std.debug.print("1️⃣  使用默认配置连接\n", .{});
    std.debug.print("   参数: zorm.connect(allocator, dsn, null)\n", .{});
    {
        const db = try zorm.connect(allocator, dsn, null);
        defer db.deinit();

        std.debug.print("   ✓ 连接成功\n", .{});
        std.debug.print("   配置: debug={}, max_open_conns={}, query_timeout={}ms\n\n", .{
            db.options.debug,
            db.options.max_open_conns,
            db.options.query_timeout,
        });
    }

    // ========================================
    // 示例 2: 开发环境配置 (启用 Debug 模式)
    // ========================================
    std.debug.print("2️⃣  开发环境配置 (Debug 模式)\n", .{});
    {
        const dev_options = zorm.DBOptions{
            .debug = true, // 开启 Debug 模式,自动打印所有 SQL
            .enable_query_log = true, // 启用查询日志
            .enable_slow_query_log = true, // 启用慢查询日志
            .slow_query_threshold = 500, // 慢查询阈值: 500ms
            .query_timeout = 60_000, // 查询超时: 60 秒
        };

        std.debug.print("   配置选项:\n", .{});
        std.debug.print("     - debug = true (自动打印 SQL)\n", .{});
        std.debug.print("     - enable_query_log = true\n", .{});
        std.debug.print("     - enable_slow_query_log = true\n", .{});
        std.debug.print("     - slow_query_threshold = 500ms\n", .{});
        std.debug.print("     - query_timeout = 60000ms\n\n", .{});

        const db = try zorm.connect(allocator, dsn, dev_options);
        defer db.deinit();

        std.debug.print("   ✓ 连接成功\n", .{});
        std.debug.print("   验证配置已应用:\n", .{});
        std.debug.print("     - db.options.debug = {}\n", .{db.options.debug});
        std.debug.print("     - db.options.enable_query_log = {}\n", .{db.options.enable_query_log});
        std.debug.print("     - db.options.slow_query_threshold = {}ms\n\n", .{db.options.slow_query_threshold});

        // 执行一个简单查询,验证 Debug 模式
        std.debug.print("   执行测试查询 (将自动打印 SQL):\n", .{});
        var raw = try db.newRaw("SELECT 1 as test");
        defer raw.deinit();
        _ = try raw.exec();
        std.debug.print("   ✓ 查询执行成功\n\n", .{});
    }

    // ========================================
    // 示例 3: 生产环境配置 (优化性能和连接池)
    // ========================================
    std.debug.print("3️⃣  生产环境配置 (优化性能)\n", .{});
    {
        const prod_options = zorm.DBOptions{
            .debug = false, // 关闭 Debug 模式
            .max_open_conns = 100, // 最大连接数
            .max_idle_conns = 20, // 最大空闲连接数
            .conn_max_lifetime = 600, // 连接最大生命周期: 10 分钟
            .conn_max_idle_time = 120, // 连接最大空闲时间: 2 分钟
            .query_timeout = 30_000, // 查询超时: 30 秒
            .enable_slow_query_log = true, // 启用慢查询日志
            .slow_query_threshold = 1000, // 慢查询阈值: 1 秒
        };

        std.debug.print("   配置选项:\n", .{});
        std.debug.print("     - debug = false\n", .{});
        std.debug.print("     - max_open_conns = 100\n", .{});
        std.debug.print("     - max_idle_conns = 20\n", .{});
        std.debug.print("     - conn_max_lifetime = 600s\n", .{});
        std.debug.print("     - conn_max_idle_time = 120s\n", .{});
        std.debug.print("     - query_timeout = 30000ms\n", .{});
        std.debug.print("     - slow_query_threshold = 1000ms\n\n", .{});

        const db = try zorm.connect(allocator, dsn, prod_options);
        defer db.deinit();

        std.debug.print("   ✓ 连接成功\n", .{});
        std.debug.print("   验证配置已应用:\n", .{});
        std.debug.print("     - db.options.max_open_conns = {}\n", .{db.options.max_open_conns});
        std.debug.print("     - db.options.max_idle_conns = {}\n", .{db.options.max_idle_conns});
        std.debug.print("     - db.options.conn_max_lifetime = {}s\n\n", .{db.options.conn_max_lifetime});
    }

    // ========================================
    // 示例 4: 自定义配置场景 (高并发场景)
    // ========================================
    std.debug.print("4️⃣  高并发场景配置\n", .{});
    {
        const high_concurrency_options = zorm.DBOptions{
            .max_open_conns = 200, // 更大的连接池
            .max_idle_conns = 50, // 更多的空闲连接
            .conn_max_lifetime = 300, // 缩短连接生命周期
            .query_timeout = 10_000, // 缩短查询超时
            .enable_query_log = false, // 关闭查询日志以提升性能
            .enable_slow_query_log = true, // 保留慢查询日志
            .slow_query_threshold = 500, // 更严格的慢查询阈值
        };

        std.debug.print("   配置选项:\n", .{});
        std.debug.print("     - max_open_conns = 200 (高并发)\n", .{});
        std.debug.print("     - max_idle_conns = 50\n", .{});
        std.debug.print("     - query_timeout = 10000ms (快速失败)\n", .{});
        std.debug.print("     - slow_query_threshold = 500ms (严格监控)\n\n", .{});

        const db = try zorm.connect(allocator, dsn, high_concurrency_options);
        defer db.deinit();

        std.debug.print("   ✓ 连接成功\n", .{});
        std.debug.print("   验证配置已应用:\n", .{});
        std.debug.print("     - db.options.max_open_conns = {}\n", .{db.options.max_open_conns});
        std.debug.print("     - db.options.query_timeout = {}ms\n", .{db.options.query_timeout});
        std.debug.print("     - db.options.slow_query_threshold = {}ms\n\n", .{db.options.slow_query_threshold});
    }

    std.debug.print("✅ 所有示例执行完成!\n", .{});
    std.debug.print("\n💡 提示:\n", .{});
    std.debug.print("   - 使用 null 参数可以使用默认配置\n", .{});
    std.debug.print("   - 根据不同环境(开发/生产)选择合适的配置\n", .{});
    std.debug.print("   - Debug 模式仅用于开发环境,生产环境应设为 false\n", .{});
    std.debug.print("   - 根据应用特点调整连接池和超时配置\n\n", .{});
}
