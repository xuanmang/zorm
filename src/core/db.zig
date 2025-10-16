//! DB - 数据库实例和连接管理
//!
//! DB 是 ZORM 的核心结构,负责:
//! - 数据库连接管理
//! - 查询构建器工厂方法
//! - 事务管理
//! - 查询钩子管理
//! - 连接池统计

const std = @import("std");
const Allocator = std.mem.Allocator;
const dialect = @import("../dialect/dialect.zig");
const Dialect = dialect.Dialect;
const hooks = @import("../hooks/hooks.zig");

/// DB 配置选项
pub const DBOptions = struct {
    /// 忽略模型中未知的列
    discard_unknown_columns: bool = false,

    /// 最大打开连接数
    max_open_conns: u32 = 25,

    /// 最大空闲连接数
    max_idle_conns: u32 = 25,

    /// 连接最大生命周期(秒)
    conn_max_lifetime: u64 = 300,

    /// 连接最大空闲时间(秒)
    conn_max_idle_time: u64 = 60,

    /// 启用查询日志
    enable_query_log: bool = false,

    /// 启用查询计时
    enable_query_timing: bool = false,
};

/// 连接统计信息
pub const DBStats = struct {
    /// 已执行的查询数
    queries: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    /// 错误数
    errors: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    /// 当前打开的连接数
    open_connections: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    /// 空闲连接数
    idle_connections: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    pub fn recordQuery(self: *DBStats) void {
        _ = self.queries.fetchAdd(1, .monotonic);
    }

    pub fn recordError(self: *DBStats) void {
        _ = self.errors.fetchAdd(1, .monotonic);
    }

    pub fn getQueryCount(self: *const DBStats) u64 {
        return self.queries.load(.monotonic);
    }

    pub fn getErrorCount(self: *const DBStats) u64 {
        return self.errors.load(.monotonic);
    }
};

/// 数据库连接接口
/// 不同的数据库驱动需要实现这个接口
pub const Conn = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        exec: *const fn (ptr: *anyopaque, query: []const u8, args: []const []const u8) anyerror!void,
        query: *const fn (ptr: *anyopaque, query: []const u8, args: []const []const u8) anyerror!*Result,
        begin: *const fn (ptr: *anyopaque) anyerror!*Tx,
        close: *const fn (ptr: *anyopaque) void,
    };

    pub fn exec(self: Conn, query_str: []const u8, args: []const []const u8) !void {
        return self.vtable.exec(self.ptr, query_str, args);
    }

    pub fn query(self: Conn, query_str: []const u8, args: []const []const u8) !*Result {
        return self.vtable.query(self.ptr, query_str, args);
    }

    pub fn begin(self: Conn) !*Tx {
        return self.vtable.begin(self.ptr);
    }

    pub fn close(self: Conn) void {
        self.vtable.close(self.ptr);
    }
};

/// 查询结果接口
pub const Result = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        next: *const fn (ptr: *anyopaque) anyerror!bool,
        scan: *const fn (ptr: *anyopaque, dest: [][]u8) anyerror!void,
        close: *const fn (ptr: *anyopaque) void,
    };

    pub fn next(self: *Result) !bool {
        return self.vtable.next(self.ptr);
    }

    pub fn scan(self: *Result, dest: [][]u8) !void {
        return self.vtable.scan(self.ptr, dest);
    }

    pub fn close(self: *Result) void {
        self.vtable.close(self.ptr);
    }
};

/// 事务接口
pub const Tx = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        exec: *const fn (ptr: *anyopaque, query: []const u8, args: []const []const u8) anyerror!void,
        query: *const fn (ptr: *anyopaque, query: []const u8, args: []const []const u8) anyerror!*Result,
        commit: *const fn (ptr: *anyopaque) anyerror!void,
        rollback: *const fn (ptr: *anyopaque) anyerror!void,
    };

    pub fn exec(self: *Tx, query_str: []const u8, args: []const []const u8) !void {
        return self.vtable.exec(self.ptr, query_str, args);
    }

    pub fn query(self: *Tx, query_str: []const u8, args: []const []const u8) !*Result {
        return self.vtable.query(self.ptr, query_str, args);
    }

    pub fn commit(self: *Tx) !void {
        return self.vtable.commit(self.ptr);
    }

    pub fn rollback(self: *Tx) !void {
        return self.vtable.rollback(self.ptr);
    }
};

/// DB - 数据库实例
pub const DB = struct {
    allocator: Allocator,
    conn: Conn,
    dialect_type: Dialect,
    options: DBOptions,
    query_hooks: std.ArrayList(*hooks.QueryHook),
    stats: DBStats,
    current_tx: ?*Tx,

    /// 创建数据库实例
    pub fn init(
        allocator: Allocator,
        conn: Conn,
        dialect_type: Dialect,
        options: DBOptions,
    ) !*DB {
        const self = try allocator.create(DB);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .conn = conn,
            .dialect_type = dialect_type,
            .options = options,
            .query_hooks = std.ArrayList(*hooks.QueryHook).init(allocator),
            .stats = .{},
            .current_tx = null,
        };

        return self;
    }

    /// 销毁数据库实例
    pub fn deinit(self: *DB) void {
        // 如果有活动事务,回滚它
        if (self.current_tx) |tx| {
            tx.rollback() catch {};
        }

        // 清理查询钩子
        self.query_hooks.deinit();

        // 关闭连接
        self.conn.close();

        // 释放内存
        self.allocator.destroy(self);
    }

    /// 添加查询钩子
    pub fn addQueryHook(self: *DB, hook: *hooks.QueryHook) !void {
        try self.query_hooks.append(hook);
    }

    /// 执行 SQL 语句(不返回结果)
    pub fn exec(self: *DB, query_str: []const u8, args: []const []const u8) !void {
        self.stats.recordQuery();

        // 如果有活动事务,使用事务执行
        if (self.current_tx) |tx| {
            return tx.exec(query_str, args);
        }

        // 否则使用连接执行
        return self.conn.exec(query_str, args) catch |err| {
            self.stats.recordError();
            return err;
        };
    }

    /// 执行查询(返回结果)
    pub fn query(self: *DB, query_str: []const u8, args: []const []const u8) !*Result {
        self.stats.recordQuery();

        // 如果有活动事务,使用事务执行
        if (self.current_tx) |tx| {
            return tx.query(query_str, args);
        }

        // 否则使用连接执行
        return self.conn.query(query_str, args) catch |err| {
            self.stats.recordError();
            return err;
        };
    }

    /// 开始事务
    pub fn begin(self: *DB) !*Tx {
        if (self.current_tx != null) {
            return error.TransactionAlreadyStarted;
        }

        const tx = try self.conn.begin();
        self.current_tx = tx;
        return tx;
    }

    /// 提交事务
    pub fn commit(self: *DB) !void {
        const tx = self.current_tx orelse return error.NoActiveTransaction;
        defer self.current_tx = null;
        return tx.commit();
    }

    /// 回滚事务
    pub fn rollback(self: *DB) !void {
        const tx = self.current_tx orelse return error.NoActiveTransaction;
        defer self.current_tx = null;
        return tx.rollback();
    }

    /// 获取方言类型
    pub fn getDialect(self: *const DB) Dialect {
        return self.dialect_type;
    }

    /// 获取统计信息
    pub fn getStats(self: *const DB) DBStats {
        return self.stats;
    }

    /// 在事务中执行函数
    /// 如果函数返回错误,自动回滚;否则自动提交
    pub fn runInTx(self: *DB, comptime func: anytype, args: anytype) !@TypeOf(@call(.auto, func, args)) {
        _ = try self.begin();
        errdefer self.rollback() catch {};

        const result = try @call(.auto, func, args);
        try self.commit();
        return result;
    }
};

test "DB stats" {
    var stats = DBStats{};

    try std.testing.expectEqual(0, stats.getQueryCount());
    try std.testing.expectEqual(0, stats.getErrorCount());

    stats.recordQuery();
    stats.recordQuery();
    stats.recordError();

    try std.testing.expectEqual(2, stats.getQueryCount());
    try std.testing.expectEqual(1, stats.getErrorCount());
}
