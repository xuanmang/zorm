// tests/pool_test.zig
// ZORM 连接池单元测试和并发测试

const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");

// 导入 pool 模块和相关类型
const Pool = zorm.Pool;
const PoolConfig = zorm.PoolConfig;
const Connection = zorm.Connection;
const Result = zorm.Result;
const Rows = zorm.Rows;
const QueryArg = zorm.QueryArg;
const Error = zorm.Error;

// ========== Mock Driver ==========

/// Mock 驱动用于测试连接池功能
const MockDriver = struct {
    allocator: std.mem.Allocator,
    is_closed: bool = false,
    exec_count: u32 = 0,

    pub fn connect(allocator: std.mem.Allocator, dsn: []const u8) !MockDriver {
        _ = dsn;
        return MockDriver{
            .allocator = allocator,
            .is_closed = false,
            .exec_count = 0,
        };
    }

    pub fn exec(self: *MockDriver, sql: []const u8, args: []const QueryArg) !Result {
        _ = sql;
        _ = args;
        if (self.is_closed) {
            return Error.ConnectionClosed;
        }
        self.exec_count += 1;
        return Result{
            .last_insert_id = 1,
            .rows_affected = 1,
        };
    }

    pub fn query(self: *MockDriver, sql: []const u8, args: []const QueryArg) !Rows {
        _ = sql;
        _ = args;
        if (self.is_closed) {
            return Error.ConnectionClosed;
        }
        return Error.UnsupportedFeature;
    }

    pub fn close(self: *MockDriver) !void {
        if (self.is_closed) {
            return Error.ConnectionClosed;
        }
        self.is_closed = true;
    }
};

const MockPool = Pool(MockDriver);
const MockConn = Connection(MockDriver);

// ========== 单元测试 ==========

test "Pool: init and deinit" {
    const allocator = testing.allocator;

    const pool = try MockPool.init(allocator, "mock://test", .{
        .max_open_conns = 10,
        .max_idle_conns = 5,
        .conn_max_lifetime = 300,
    });
    defer pool.deinit();

    try testing.expectEqual(@as(u32, 0), pool.open_count);
    try testing.expectEqual(@as(u32, 10), pool.config.max_open_conns);
    try testing.expectEqual(@as(u32, 5), pool.config.max_idle_conns);
}

test "Pool: acquire single connection" {
    const allocator = testing.allocator;

    const pool = try MockPool.init(allocator, "mock://test", .{
        .max_open_conns = 10,
    });
    defer pool.deinit();

    const conn = try pool.acquire();
    defer pool.release(conn) catch {};

    try testing.expectEqual(@as(u32, 1), pool.open_count);

    // 测试连接可以执行操作
    const result = try conn.exec("INSERT INTO test VALUES (1)", &.{});
    try testing.expectEqual(@as(i64, 1), result.last_insert_id);
}

test "Pool: acquire and release multiple connections" {
    const allocator = testing.allocator;

    const pool = try MockPool.init(allocator, "mock://test", .{
        .max_open_conns = 10,
        .max_idle_conns = 5,
    });
    defer pool.deinit();

    // 获取 3 个连接
    const conn1 = try pool.acquire();
    const conn2 = try pool.acquire();
    const conn3 = try pool.acquire();

    try testing.expectEqual(@as(u32, 3), pool.open_count);

    // 释放连接
    try pool.release(conn1);
    try pool.release(conn2);
    try pool.release(conn3);

    try testing.expectEqual(@as(u32, 3), pool.open_count);

    // 再次获取连接 (应该复用)
    const conn4 = try pool.acquire();
    try testing.expectEqual(@as(u32, 3), pool.open_count);
    try pool.release(conn4);
}

test "Pool: connection pool exhaustion" {
    const allocator = testing.allocator;

    const pool = try MockPool.init(allocator, "mock://test", .{
        .max_open_conns = 2,
        .max_idle_conns = 2,
    });
    defer pool.deinit();

    // 获取最大数量的连接
    const conn1 = try pool.acquire();
    const conn2 = try pool.acquire();

    try testing.expectEqual(@as(u32, 2), pool.open_count);

    // 尝试获取第 3 个连接应该失败
    try testing.expectError(Error.ConnectionPoolExhausted, pool.acquire());

    // 释放连接后应该可以再次获取
    try pool.release(conn1);
    const conn3 = try pool.acquire();
    try testing.expectEqual(@as(u32, 2), pool.open_count);

    try pool.release(conn2);
    try pool.release(conn3);
}

test "Pool: max idle connections limit" {
    const allocator = testing.allocator;

    const pool = try MockPool.init(allocator, "mock://test", .{
        .max_open_conns = 10,
        .max_idle_conns = 2,
    });
    defer pool.deinit();

    // 获取 5 个连接
    var conns: [5]*MockConn = undefined;
    for (&conns) |*conn| {
        conn.* = try pool.acquire();
    }

    try testing.expectEqual(@as(u32, 5), pool.open_count);

    // 释放所有连接 (超过 max_idle_conns 的连接应该被关闭)
    for (conns) |conn| {
        try pool.release(conn);
    }

    // 由于 max_idle_conns = 2,应该只保留 2 个连接
    try testing.expectEqual(@as(u32, 2), pool.open_count);
}

test "Pool: connection lifecycle expiration" {
    const allocator = testing.allocator;

    // 使用非常短的过期时间用于测试
    const pool = try MockPool.init(allocator, "mock://test", .{
        .max_open_conns = 10,
        .max_idle_conns = 5,
        .conn_max_lifetime = 1, // 1 纳秒后过期 (实际上立即过期,因为时间单位是秒)
        .conn_max_idle_time = 1, // 1 纳秒空闲后过期
    });
    defer pool.deinit();

    // 获取连接
    const conn1 = try pool.acquire();
    const now = std.time.nanoTimestamp();
    try pool.release(conn1);

    try testing.expectEqual(@as(u32, 1), pool.open_count);

    // 睡眠 1.1 秒确保连接过期 (因为配置单位是秒)
    std.Thread.sleep(1100 * std.time.ns_per_ms);

    // 验证时间确实过了 1 秒
    const elapsed = std.time.nanoTimestamp() - now;
    try testing.expect(elapsed > 1 * std.time.ns_per_s);

    // 手动触发清理
    const cleaned = try pool.cleanupExpiredConnections();
    try testing.expect(cleaned > 0);
    try testing.expectEqual(@as(u32, 0), pool.open_count);
}

test "Pool: stats reporting" {
    const allocator = testing.allocator;

    const pool = try MockPool.init(allocator, "mock://test", .{
        .max_open_conns = 10,
        .max_idle_conns = 5,
    });
    defer pool.deinit();

    // 初始状态
    var pool_stats = pool.stats();
    try testing.expectEqual(@as(u32, 0), pool_stats.total_connections);
    try testing.expectEqual(@as(u32, 0), pool_stats.idle_connections);
    try testing.expectEqual(@as(u32, 0), pool_stats.in_use_connections);

    // 获取 3 个连接
    const conn1 = try pool.acquire();
    const conn2 = try pool.acquire();
    const conn3 = try pool.acquire();

    pool_stats = pool.stats();
    try testing.expectEqual(@as(u32, 3), pool_stats.total_connections);
    try testing.expectEqual(@as(u32, 0), pool_stats.idle_connections);
    try testing.expectEqual(@as(u32, 3), pool_stats.in_use_connections);

    // 释放 2 个连接
    try pool.release(conn1);
    try pool.release(conn2);

    pool_stats = pool.stats();
    try testing.expectEqual(@as(u32, 3), pool_stats.total_connections);
    try testing.expectEqual(@as(u32, 2), pool_stats.idle_connections);
    try testing.expectEqual(@as(u32, 1), pool_stats.in_use_connections);

    try pool.release(conn3);
}

test "Pool: double release error" {
    const allocator = testing.allocator;

    const pool = try MockPool.init(allocator, "mock://test", .{
        .max_open_conns = 10,
    });
    defer pool.deinit();

    const conn = try pool.acquire();
    try pool.release(conn);

    // 尝试再次释放同一个连接应该返回错误
    try testing.expectError(Error.ConnectionClosed, pool.release(conn));
}

// ========== 并发测试 ==========

test "Pool: concurrent acquire and release" {
    const allocator = testing.allocator;

    const pool = try MockPool.init(allocator, "mock://test", .{
        .max_open_conns = 5,
        .max_idle_conns = 5,
    });
    defer pool.deinit();

    const ThreadContext = struct {
        pool: *MockPool,
        iterations: u32,

        fn worker(ctx: *@This()) void {
            var i: u32 = 0;
            while (i < ctx.iterations) : (i += 1) {
                const conn = ctx.pool.acquire() catch continue;
                defer ctx.pool.release(conn) catch {};

                // 执行一些操作
                _ = conn.exec("INSERT INTO test VALUES (1)", &.{}) catch {};

                // 模拟一些工作
                std.Thread.sleep(1 * std.time.ns_per_ms);
            }
        }
    };

    var threads: [10]std.Thread = undefined;
    var contexts: [10]ThreadContext = undefined;

    // 启动 10 个线程,每个执行 20 次操作
    for (&threads, &contexts) |*thread, *ctx| {
        ctx.* = ThreadContext{
            .pool = pool,
            .iterations = 20,
        };
        thread.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ctx});
    }

    // 等待所有线程完成
    for (threads) |thread| {
        thread.join();
    }

    // 验证连接池状态
    const pool_stats = pool.stats();
    try testing.expect(pool_stats.total_connections <= 5);
    try testing.expectEqual(@as(u32, 0), pool_stats.in_use_connections);
}

test "Pool: stress test with many threads" {
    const allocator = testing.allocator;

    const pool = try MockPool.init(allocator, "mock://test", .{
        .max_open_conns = 10,
        .max_idle_conns = 5,
    });
    defer pool.deinit();

    const ThreadContext = struct {
        pool: *MockPool,

        fn worker(ctx: *@This()) void {
            var i: u32 = 0;
            while (i < 100) : (i += 1) {
                const conn = ctx.pool.acquire() catch {
                    // 连接池耗尽时等待一下再重试
                    std.Thread.sleep(1 * std.time.ns_per_ms);
                    continue;
                };
                defer ctx.pool.release(conn) catch {};

                _ = conn.exec("SELECT 1", &.{}) catch {};
            }
        }
    };

    var threads: [20]std.Thread = undefined;
    var contexts: [20]ThreadContext = undefined;

    for (&threads, &contexts) |*thread, *ctx| {
        ctx.* = ThreadContext{ .pool = pool };
        thread.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ctx});
    }

    for (threads) |thread| {
        thread.join();
    }

    // 验证最终状态
    try testing.expectEqual(@as(u32, 0), pool.stats().in_use_connections);
}

test "Pool: cleanup expired connections during concurrent access" {
    const allocator = testing.allocator;

    const pool = try MockPool.init(allocator, "mock://test", .{
        .max_open_conns = 10,
        .max_idle_conns = 10,
        .conn_max_idle_time = 1, // 1秒后过期
    });
    defer pool.deinit();

    const WorkerContext = struct {
        pool: *MockPool,
        done: *std.atomic.Value(bool),

        fn worker(ctx: *@This()) void {
            while (!ctx.done.load(.acquire)) {
                const conn = ctx.pool.acquire() catch continue;
                std.Thread.sleep(5 * std.time.ns_per_ms);
                ctx.pool.release(conn) catch {};
            }
        }
    };

    const CleanupContext = struct {
        pool: *MockPool,
        done: *std.atomic.Value(bool),

        fn cleaner(ctx: *@This()) void {
            while (!ctx.done.load(.acquire)) {
                _ = ctx.pool.cleanupExpiredConnections() catch {};
                std.Thread.sleep(10 * std.time.ns_per_ms);
            }
        }
    };

    var done = std.atomic.Value(bool).init(false);

    var worker_contexts: [5]WorkerContext = undefined;
    var worker_threads: [5]std.Thread = undefined;

    for (&worker_contexts, &worker_threads) |*ctx, *thread| {
        ctx.* = WorkerContext{ .pool = pool, .done = &done };
        thread.* = try std.Thread.spawn(.{}, WorkerContext.worker, .{ctx});
    }

    var cleanup_ctx = CleanupContext{ .pool = pool, .done = &done };
    const cleanup_thread = try std.Thread.spawn(.{}, CleanupContext.cleaner, .{&cleanup_ctx});

    // 运行 100ms
    std.Thread.sleep(100 * std.time.ns_per_ms);

    // 停止所有线程
    done.store(true, .release);

    for (worker_threads) |thread| {
        thread.join();
    }
    cleanup_thread.join();

    // 验证没有连接泄漏
    try testing.expectEqual(@as(u32, 0), pool.stats().in_use_connections);
}
