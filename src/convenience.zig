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

    const vtable = core.Tx.VTable{
        .exec = exec,
        .query = query,
        .commit = commit,
        .rollback = rollback,
    };
};

/// 简化的 PostgreSQL 连接函数
///
/// 示例:
/// ```zig
/// var db = try zorm.connect(allocator, "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres");
/// defer db.deinit();
/// ```
pub fn connect(allocator: std.mem.Allocator, dsn: []const u8) !*core.DB(.postgresql) {
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

    // 创建并返回 DB 实例
    return try core.DB(.postgresql).init(allocator, conn, .{});
}
