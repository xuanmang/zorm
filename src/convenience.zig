//! ZORM 便捷 API
//!
//! 提供简化的、用户友好的 API，隐藏底层实现细节

const std = @import("std");
const core = @import("core/db.zig");
const postgres = @import("driver/postgres.zig");
const Dialect = @import("dialect/dialect.zig").Dialect;
const QueryArg = @import("types.zig").QueryArg;

/// PostgreSQL 连接适配器
const PostgresDriverConnAdapter = struct {
    driver: *postgres.PostgresDriver,
    allocator: std.mem.Allocator,

    fn exec(ptr: *anyopaque, query_str: []const u8, args: []const QueryArg) anyerror!void {
        const self: *PostgresDriverConnAdapter = @ptrCast(@alignCast(ptr));
        _ = try self.driver.exec(query_str, args);
    }

    fn query(ptr: *anyopaque, query_str: []const u8, args: []const QueryArg) anyerror!*core.Result {
        const self: *PostgresDriverConnAdapter = @ptrCast(@alignCast(ptr));
        const rows = try self.driver.query(query_str, args);

        const result_vtable = try self.allocator.create(core.Result.VTable);
        errdefer self.allocator.destroy(result_vtable);
        result_vtable.* = .{
            .next = ResultWrapper.next,
            .scan = ResultWrapper.scan,
            .close = ResultWrapper.close,
        };

        const result = try self.allocator.create(core.Result);
        errdefer self.allocator.destroy(result);

        const wrapper = try self.allocator.create(ResultWrapper);
        errdefer self.allocator.destroy(wrapper);
        wrapper.* = .{
            .allocator = self.allocator,
            .vtable = result_vtable,
            .result = result,
        };

        result.* = .{
            .ptr = wrapper,
            .vtable = result_vtable,
            .rows = rows,
        };
        return result;
    }

    fn begin(ptr: *anyopaque) anyerror!*core.Tx {
        const self: *PostgresDriverConnAdapter = @ptrCast(@alignCast(ptr));

        // 执行 BEGIN 语句
        _ = try self.driver.exec("BEGIN", &[_]QueryArg{});

        // 创建 Tx 适配器
        const tx_adapter = try self.allocator.create(PostgresTxAdapter);
        errdefer self.allocator.destroy(tx_adapter);
        tx_adapter.* = .{
            .driver = self.driver,
            .allocator = self.allocator,
        };

        // 创建 Tx VTable
        const tx_vtable = try self.allocator.create(core.Tx.VTable);
        errdefer self.allocator.destroy(tx_vtable);
        tx_vtable.* = PostgresTxAdapter.vtable;

        // 创建 Tx 接口
        const tx = try self.allocator.create(core.Tx);
        errdefer self.allocator.destroy(tx);
        tx.* = .{
            .ptr = tx_adapter,
            .vtable = tx_vtable,
        };

        return tx;
    }

    fn close(ptr: *anyopaque) void {
        const self: *PostgresDriverConnAdapter = @ptrCast(@alignCast(ptr));
        self.driver.close() catch {};
        self.allocator.destroy(self.driver);
        self.allocator.destroy(self);
    }

    const vtable = core.Conn.VTable{
        .exec = exec,
        .query = query,
        .begin = begin,
        .close = close,
    };
};

const ResultWrapper = struct {
    allocator: std.mem.Allocator,
    vtable: *core.Result.VTable,
    result: *core.Result,

    fn next(ptr: *anyopaque) anyerror!bool {
        _ = ptr;
        return error.NotImplemented;
    }

    fn scan(ptr: *anyopaque, dest: [][]u8) anyerror!void {
        _ = ptr;
        _ = dest;
        return error.NotImplemented;
    }

    fn close(ptr: *anyopaque) void {
        const self: *ResultWrapper = @ptrCast(@alignCast(ptr));
        // 释放所有创建的资源
        self.allocator.destroy(self.vtable);
        self.allocator.destroy(self.result);
        self.allocator.destroy(self);
    }
};

/// PostgreSQL 事务适配器
const PostgresTxAdapter = struct {
    driver: *postgres.PostgresDriver,
    allocator: std.mem.Allocator,

    fn exec(ptr: *anyopaque, query_str: []const u8, args: []const QueryArg) anyerror!void {
        const self: *PostgresTxAdapter = @ptrCast(@alignCast(ptr));
        _ = try self.driver.exec(query_str, args);
    }

    fn query(ptr: *anyopaque, query_str: []const u8, args: []const QueryArg) anyerror!*core.Result {
        const self: *PostgresTxAdapter = @ptrCast(@alignCast(ptr));
        const rows = try self.driver.query(query_str, args);

        const result_vtable = try self.allocator.create(core.Result.VTable);
        errdefer self.allocator.destroy(result_vtable);
        result_vtable.* = .{
            .next = ResultWrapper.next,
            .scan = ResultWrapper.scan,
            .close = ResultWrapper.close,
        };

        const result = try self.allocator.create(core.Result);
        errdefer self.allocator.destroy(result);

        const wrapper = try self.allocator.create(ResultWrapper);
        errdefer self.allocator.destroy(wrapper);
        wrapper.* = .{
            .allocator = self.allocator,
            .vtable = result_vtable,
            .result = result,
        };

        result.* = .{
            .ptr = wrapper,
            .vtable = result_vtable,
            .rows = rows,
        };
        return result;
    }

    fn commit(ptr: *anyopaque) anyerror!void {
        const self: *PostgresTxAdapter = @ptrCast(@alignCast(ptr));
        _ = try self.driver.exec("COMMIT", &[_]QueryArg{});
    }

    fn rollback(ptr: *anyopaque) anyerror!void {
        const self: *PostgresTxAdapter = @ptrCast(@alignCast(ptr));
        _ = try self.driver.exec("ROLLBACK", &[_]QueryArg{});
    }

    fn cleanup(tx_ptr: *core.Tx, allocator: std.mem.Allocator) void {
        // 释放 tx.ptr 指向的 PostgresTxAdapter
        const adapter = @as(*PostgresTxAdapter, @ptrCast(@alignCast(tx_ptr.ptr)));
        allocator.destroy(adapter);

        // 释放 tx.vtable
        allocator.destroy(@constCast(tx_ptr.vtable));

        // 释放 tx 本身
        allocator.destroy(tx_ptr);
    }

    const vtable = core.Tx.VTable{
        .exec = exec,
        .query = query,
        .commit = commit,
        .rollback = rollback,
        .cleanup = cleanup,
    };
};

/// 简化的 PostgreSQL 连接函数
///
/// 参数:
///   - allocator: 内存分配器
///   - dsn: PostgreSQL 连接字符串
///   - options: 可选的数据库配置选项(为 null 时使用默认配置)
///
/// 基本用法示例:
/// ```zig
/// var db = try zorm.connect(allocator, "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres", null);
/// defer db.deinit();
/// ```
///
/// 高级用法示例(自定义配置):
/// ```zig
/// const options = zorm.DBOptions{
///     .debug = true,
///     .max_open_conns = 50,
///     .query_timeout = 60_000,
/// };
/// var db = try zorm.connect(allocator, "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres", options);
/// defer db.deinit();
/// ```
pub fn connect(allocator: std.mem.Allocator, dsn: []const u8, options: ?core.DBOptions) !*core.DB(.postgresql) {
    // 创建 driver
    const driver = try allocator.create(postgres.PostgresDriver);
    errdefer allocator.destroy(driver);
    driver.* = try postgres.PostgresDriver.connect(allocator, dsn);

    // 创建适配器
    const adapter = try allocator.create(PostgresDriverConnAdapter);
    adapter.* = .{
        .driver = driver,
        .allocator = allocator,
    };

    // 创建 Conn 接口
    const conn = core.Conn{
        .ptr = adapter,
        .vtable = &PostgresDriverConnAdapter.vtable,
    };

    // 使用提供的 options 或默认配置
    const db_options = options orelse core.DBOptions{};

    // 创建并返回 DB 实例
    return try core.DB(.postgresql).init(allocator, conn, db_options);
}

// ============================================================================
// 测试
// ============================================================================

test "connect with default options" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 测试不传 options 参数的向后兼容性
    const dsn = "host=127.0.0.1 port=5432 user=test password=test dbname=test";
    var db = connect(allocator, dsn, null) catch |err| {
        // 连接失败是预期的(测试环境可能没有数据库),只要编译通过即可
        std.debug.print("Connection failed as expected: {}\n", .{err});
        return;
    };
    defer db.deinit();

    // 验证默认配置已应用
    try testing.expect(db.options.debug == false);
    try testing.expect(db.options.max_open_conns == 25);
}

test "connect with custom options" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 测试传递自定义 options
    const options = core.DBOptions{
        .debug = true,
        .max_open_conns = 50,
        .max_idle_conns = 10,
        .query_timeout = 60_000,
        .enable_query_log = true,
    };

    const dsn = "host=127.0.0.1 port=5432 user=test password=test dbname=test";
    var db = connect(allocator, dsn, options) catch |err| {
        // 连接失败是预期的(测试环境可能没有数据库),只要编译通过即可
        std.debug.print("Connection failed as expected: {}\n", .{err});
        return;
    };
    defer db.deinit();

    // 验证自定义配置已应用
    try testing.expect(db.options.debug == true);
    try testing.expect(db.options.max_open_conns == 50);
    try testing.expect(db.options.max_idle_conns == 10);
}

test "custom options applied to DB instance" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 测试 options 是否正确应用到 DB 实例
    const options = core.DBOptions{
        .debug = true,
        .max_open_conns = 100,
        .conn_max_lifetime = 600,
        .slow_query_threshold = 2000,
    };

    const dsn = "host=127.0.0.1 port=5432 user=test password=test dbname=test";
    var db = connect(allocator, dsn, options) catch |err| {
        // 连接失败是预期的(测试环境可能没有数据库),只要编译通过即可
        std.debug.print("Connection failed as expected: {}\n", .{err});
        return;
    };
    defer db.deinit();

    // 验证配置已正确应用
    try testing.expect(db.options.debug == true);
    try testing.expect(db.options.max_open_conns == 100);
    try testing.expect(db.options.conn_max_lifetime == 600);
    try testing.expect(db.options.slow_query_threshold == 2000);
}
