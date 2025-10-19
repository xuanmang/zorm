//! DB 单元测试
//!
//! 测试 DB 核心功能:
//! - DB.init() 和 DB.deinit()
//! - 配置选项
//! - 内存泄漏检测
//! - 资源清理

const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");

// 导入需要的类型
const DB = zorm.DB;
const DBOptions = zorm.DBOptions;
const QueryArg = zorm.QueryArg;
const Conn = zorm.core.Conn;
const Result = zorm.core.Result;
const Tx = zorm.core.Tx;
const Dialect = zorm.Dialect;

// ============================================
// Mock 实现用于测试
// ============================================

/// Mock Connection 用于测试
const MockConn = struct {
    closed: bool = false,

    pub fn init() MockConn {
        return .{};
    }

    pub fn exec(_: *MockConn, _: []const u8, _: []const QueryArg) !void {}

    pub fn query(_: *MockConn, _: []const u8, _: []const QueryArg) !*MockResult {
        return error.NotImplemented;
    }

    pub fn begin(_: *MockConn) !*MockTx {
        return error.NotImplemented;
    }

    pub fn close(self: *MockConn) void {
        self.closed = true;
    }

    /// 转换为 db.Conn 接口
    pub fn toConn(self: *MockConn) Conn {
        const vtable = struct {
            fn execFn(ptr: *anyopaque, sql: []const u8, args: []const QueryArg) anyerror!void {
                const conn: *MockConn = @ptrCast(@alignCast(ptr));
                return conn.exec(sql, args);
            }

            fn queryFn(ptr: *anyopaque, query_str: []const u8, args: []const QueryArg) anyerror!*Result {
                const conn: *MockConn = @ptrCast(@alignCast(ptr));
                _ = try conn.query(query_str, args);
                return error.NotImplemented;
            }

            fn beginFn(ptr: *anyopaque) anyerror!*Tx {
                const conn: *MockConn = @ptrCast(@alignCast(ptr));
                _ = try conn.begin();
                return error.NotImplemented;
            }

            fn closeFn(ptr: *anyopaque) void {
                const conn: *MockConn = @ptrCast(@alignCast(ptr));
                conn.close();
            }
        };

        const static = struct {
            var v: Conn.VTable = .{
                .exec = vtable.execFn,
                .query = vtable.queryFn,
                .begin = vtable.beginFn,
                .close = vtable.closeFn,
            };
        };

        return .{
            .ptr = self,
            .vtable = &static.v,
        };
    }
};

const MockResult = struct {};
const MockTx = struct {};

// ============================================
// 测试用例
// ============================================

test "DB: init and deinit without memory leak" {
    const allocator = testing.allocator;

    var mock_conn = MockConn.init();
    const conn = mock_conn.toConn();

    const PostgresDB = DB(.postgresql);

    const db = try PostgresDB.init(allocator, conn, .{});
    defer db.deinit();

    // 验证 DB 初始化成功
    try testing.expect(db.allocator.ptr == allocator.ptr);
    try testing.expectEqual(PostgresDB.getDialect(), .postgresql);
}

test "DB: default configuration" {
    const opts = DBOptions{};

    // 验证默认值
    try testing.expectEqual(false, opts.discard_unknown_columns);
    try testing.expectEqual(@as(u32, 25), opts.max_open_conns);
    try testing.expectEqual(@as(u32, 25), opts.max_idle_conns);
    try testing.expectEqual(@as(u64, 300), opts.conn_max_lifetime);
    try testing.expectEqual(@as(u64, 60), opts.conn_max_idle_time);
    try testing.expectEqual(@as(u64, 30_000), opts.query_timeout);
    try testing.expectEqual(false, opts.enable_query_log);
    try testing.expectEqual(false, opts.enable_slow_query_log);
    try testing.expectEqual(@as(u64, 1000), opts.slow_query_threshold);
}

test "DB: custom configuration" {
    const allocator = testing.allocator;

    var mock_conn = MockConn.init();
    const conn = mock_conn.toConn();

    const PostgresDB = DB(.postgresql);

    const custom_opts = DBOptions{
        .max_open_conns = 50,
        .max_idle_conns = 10,
        .conn_max_lifetime = 600,
        .query_timeout = 60_000,
        .enable_query_log = true,
    };

    const db = try PostgresDB.init(allocator, conn, custom_opts);
    defer db.deinit();

    // 验证自定义配置
    try testing.expectEqual(@as(u32, 50), db.options.max_open_conns);
    try testing.expectEqual(@as(u32, 10), db.options.max_idle_conns);
    try testing.expectEqual(@as(u64, 600), db.options.conn_max_lifetime);
    try testing.expectEqual(@as(u64, 60_000), db.options.query_timeout);
    try testing.expectEqual(true, db.options.enable_query_log);
}

test "DB: getDialect is comptime" {
    // 验证 getDialect 可以在编译时调用
    const PostgresDB = DB(.postgresql);
    const MySQLDB = DB(.mysql);
    const SQLiteDB = DB(.sqlite);

    try testing.expectEqual(.postgresql, PostgresDB.getDialect());
    try testing.expectEqual(.mysql, MySQLDB.getDialect());
    try testing.expectEqual(.sqlite, SQLiteDB.getDialect());
}

test "DB: stats initialization" {
    const allocator = testing.allocator;

    var mock_conn = MockConn.init();
    const conn = mock_conn.toConn();

    const PostgresDB = DB(.postgresql);

    const db = try PostgresDB.init(allocator, conn, .{});
    defer db.deinit();

    // 验证统计信息初始化为 0
    try testing.expectEqual(@as(u64, 0), db.stats.getQueryCount());
    try testing.expectEqual(@as(u64, 0), db.stats.getErrorCount());
}

test "DB: deinit closes connection" {
    const allocator = testing.allocator;

    var mock_conn = MockConn.init();
    const conn = mock_conn.toConn();

    const PostgresDB = DB(.postgresql);

    const db = try PostgresDB.init(allocator, conn, .{});

    // 验证连接初始状态
    try testing.expect(!mock_conn.closed);

    // 调用 deinit
    db.deinit();

    // 验证连接已关闭
    try testing.expect(mock_conn.closed);
}

test "DB: query hooks initialization" {
    const allocator = testing.allocator;

    var mock_conn = MockConn.init();
    const conn = mock_conn.toConn();

    const PostgresDB = DB(.postgresql);

    const db = try PostgresDB.init(allocator, conn, .{});
    defer db.deinit();

    // 验证钩子列表初始为空
    try testing.expectEqual(@as(usize, 0), db.query_hooks.items.len);
}

test "DB: clone creates independent instance" {
    const allocator = testing.allocator;

    var mock_conn = MockConn.init();
    const conn = mock_conn.toConn();

    const PostgresDB = DB(.postgresql);

    const db = try PostgresDB.init(allocator, conn, .{});
    defer db.deinit();

    // 克隆 DB 实例
    const cloned = try db.clone();
    defer cloned.deinit();

    // 验证克隆实例是独立的
    try testing.expect(db != cloned);
    try testing.expectEqual(db.allocator.ptr, cloned.allocator.ptr);

    // 验证统计信息是独立的
    try testing.expectEqual(@as(u64, 0), cloned.stats.getQueryCount());
}

test "DBStats: record operations" {
    var stats = zorm.core.DBStats{};

    // 初始状态
    try testing.expectEqual(@as(u64, 0), stats.getQueryCount());
    try testing.expectEqual(@as(u64, 0), stats.getErrorCount());

    // 记录查询
    stats.recordQuery();
    stats.recordQuery();
    stats.recordQuery();
    try testing.expectEqual(@as(u64, 3), stats.getQueryCount());

    // 记录错误
    stats.recordError();
    stats.recordError();
    try testing.expectEqual(@as(u64, 2), stats.getErrorCount());

    // 验证查询计数不受影响
    try testing.expectEqual(@as(u64, 3), stats.getQueryCount());
}

test "DBOptions: all fields have defaults" {
    // 使用默认构造
    const opts = DBOptions{};

    // 验证所有字段都有默认值
    _ = opts.discard_unknown_columns;
    _ = opts.max_open_conns;
    _ = opts.max_idle_conns;
    _ = opts.conn_max_lifetime;
    _ = opts.conn_max_idle_time;
    _ = opts.query_timeout;
    _ = opts.enable_query_log;
    _ = opts.enable_slow_query_log;
    _ = opts.slow_query_threshold;

    // 如果任何字段没有默认值,上面的代码会编译失败
}

test "DB: multiple instances with different dialects" {
    const allocator = testing.allocator;

    var mock_conn1 = MockConn.init();
    var mock_conn2 = MockConn.init();
    const conn1 = mock_conn1.toConn();
    const conn2 = mock_conn2.toConn();

    // 创建不同方言的 DB 实例
    const PostgresDB = DB(.postgresql);
    const MySQLDB = DB(.mysql);

    const pg_db = try PostgresDB.init(allocator, conn1, .{});
    defer pg_db.deinit();

    const mysql_db = try MySQLDB.init(allocator, conn2, .{});
    defer mysql_db.deinit();

    // 验证它们是不同的类型
    try testing.expectEqual(PostgresDB.getDialect(), .postgresql);
    try testing.expectEqual(MySQLDB.getDialect(), .mysql);
}
