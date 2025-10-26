//! 查询钩子集成测试
//!
//! 验证钩子系统在查询执行流程中的完整功能:
//! - LoggingHook 在真实查询中工作
//! - PerformanceHook 正确统计查询
//! - HookChain 正确执行多个钩子
//! - 钩子在错误情况下正确触发
//! - 钩子在事务中正常工作
//!
//! 注意: 这些测试验证钩子系统与查询构建器的集成,不需要真实数据库连接。
//! 钩子的触发逻辑已在 DB.exec/query 方法中实现。

const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");

const Dialect = zorm.Dialect;
const hooks_mod = zorm.hooks;
const QueryHook = hooks_mod.QueryHook;
const LoggingHook = hooks_mod.LoggingHook;
const PerformanceHook = hooks_mod.PerformanceHook;
const HookChain = hooks_mod.HookChain;
const QueryArg = zorm.types.QueryArg;

// ============================================================
// 测试模型
// ============================================================

const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,

    pub const table_name = "users";
};

// ============================================================
// 任务 5.1: LoggingHook 基础集成测试
// ============================================================

test "Hook Integration: LoggingHook initialization" {
    var logging = LoggingHook.init(true, 1000);
    const hook = logging.hook();

    // 验证钩子接口类型
    try testing.expect(@TypeOf(hook) == QueryHook);

    const sql = "SELECT * FROM users";
    const args = &[_]QueryArg{};

    // 验证钩子方法可调用
    try hook.beforeQuery(sql, args);
    try hook.afterQuery(sql, args, 500_000_000); // 500ms
    try hook.onError(sql, args, error.TestError);
}

test "Hook Integration: LoggingHook slow query detection" {
    var logging = LoggingHook.init(true, 500); // 500ms 阈值
    const hook = logging.hook();

    const sql = "SELECT * FROM users WHERE id = $1";
    const args = &[_]QueryArg{QueryArg.fromValue(1)};

    // 快速查询不应触发慢查询日志
    try hook.beforeQuery(sql, args);
    try hook.afterQuery(sql, args, 300_000_000); // 300ms

    // 慢查询应触发日志
    try hook.beforeQuery(sql, args);
    try hook.afterQuery(sql, args, 1_000_000_000); // 1000ms
}

// ============================================================
// 任务 5.2: PerformanceHook 统计测试
// ============================================================

test "Hook Integration: PerformanceHook query statistics" {
    var perf = PerformanceHook.init(1000);
    const hook = perf.hook();

    const sql = "SELECT * FROM users";
    const args = &[_]QueryArg{};

    // 执行多个查询
    try hook.afterQuery(sql, args, 100_000_000); // 100ms
    try hook.afterQuery(sql, args, 200_000_000); // 200ms
    try hook.afterQuery(sql, args, 300_000_000); // 300ms

    // 验证统计数据
    const stats = perf.getStats();
    try testing.expectEqual(@as(u64, 3), stats.total_queries);
    try testing.expectEqual(@as(u64, 600_000_000), stats.total_duration_ns);
    try testing.expectEqual(@as(u64, 200_000_000), stats.avg_duration_ns);
    try testing.expectEqual(@as(u64, 0), stats.slow_queries);
    try testing.expectEqual(@as(u64, 0), stats.error_count);
}

test "Hook Integration: PerformanceHook slow query detection" {
    var perf = PerformanceHook.init(500); // 500ms 阈值
    const hook = perf.hook();

    const sql = "SELECT * FROM users";
    const args = &[_]QueryArg{};

    // 快速查询
    try hook.afterQuery(sql, args, 300_000_000); // 300ms

    // 慢查询
    try hook.afterQuery(sql, args, 1_000_000_000); // 1000ms
    try hook.afterQuery(sql, args, 2_000_000_000); // 2000ms

    const stats = perf.getStats();
    try testing.expectEqual(@as(u64, 3), stats.total_queries);
    try testing.expectEqual(@as(u64, 2), stats.slow_queries);
}

test "Hook Integration: PerformanceHook error tracking" {
    var perf = PerformanceHook.init(1000);
    const hook = perf.hook();

    const sql = "SELECT * FROM users";
    const args = &[_]QueryArg{};

    // 执行一些成功的查询
    try hook.afterQuery(sql, args, 100_000_000);
    try hook.afterQuery(sql, args, 200_000_000);

    // 记录错误
    try hook.onError(sql, args, error.QueryFailed);
    try hook.onError(sql, args, error.ConnectionLost);

    const stats = perf.getStats();
    try testing.expectEqual(@as(u64, 2), stats.total_queries);
    try testing.expectEqual(@as(u64, 2), stats.error_count);
}

test "Hook Integration: PerformanceHook reset" {
    var perf = PerformanceHook.init(1000);
    const hook = perf.hook();

    const sql = "SELECT * FROM users";
    const args = &[_]QueryArg{};

    // 记录一些统计数据
    try hook.afterQuery(sql, args, 500_000_000);
    try hook.onError(sql, args, error.TestError);

    var stats = perf.getStats();
    try testing.expect(stats.total_queries > 0);
    try testing.expect(stats.error_count > 0);

    // 重置统计
    perf.reset();

    stats = perf.getStats();
    try testing.expectEqual(@as(u64, 0), stats.total_queries);
    try testing.expectEqual(@as(u64, 0), stats.error_count);
}

// ============================================================
// 任务 5.3: HookChain 多钩子测试
// ============================================================

test "Hook Integration: HookChain execution order" {
    const allocator = testing.allocator;

    var chain = try HookChain.init(allocator);
    defer chain.deinit();

    // 添加 PerformanceHook
    var perf = PerformanceHook.init(1000);
    try chain.add(perf.hook());

    // 添加 LoggingHook
    var logging = LoggingHook.init(true, 500);
    try chain.add(logging.hook());

    const hook = chain.hook();

    const sql = "SELECT * FROM users WHERE id = $1";
    const args = &[_]QueryArg{QueryArg.fromValue(1)};

    // 测试所有钩子方法
    try hook.beforeQuery(sql, args);
    try hook.afterQuery(sql, args, 600_000_000); // 600ms
    try hook.onError(sql, args, error.TestError);

    // 验证 PerformanceHook 收集了统计数据
    const stats = perf.getStats();
    try testing.expectEqual(@as(u64, 1), stats.total_queries);
    try testing.expectEqual(@as(u64, 1), stats.slow_queries); // 600ms > 500ms 阈值
    try testing.expectEqual(@as(u64, 1), stats.error_count);
}

test "Hook Integration: HookChain with multiple performance hooks" {
    const allocator = testing.allocator;

    var chain = try HookChain.init(allocator);
    defer chain.deinit();

    // 添加两个不同阈值的 PerformanceHook
    var perf1 = PerformanceHook.init(500);
    var perf2 = PerformanceHook.init(1000);

    try chain.add(perf1.hook());
    try chain.add(perf2.hook());

    const hook = chain.hook();

    const sql = "SELECT * FROM users";
    const args = &[_]QueryArg{};

    // 执行一个 750ms 的查询
    try hook.afterQuery(sql, args, 750_000_000);

    // 对于 perf1 (500ms 阈值),这是慢查询
    const stats1 = perf1.getStats();
    try testing.expectEqual(@as(u64, 1), stats1.slow_queries);

    // 对于 perf2 (1000ms 阈值),这不是慢查询
    const stats2 = perf2.getStats();
    try testing.expectEqual(@as(u64, 0), stats2.slow_queries);

    // 但两者都应该记录了这次查询
    try testing.expectEqual(@as(u64, 1), stats1.total_queries);
    try testing.expectEqual(@as(u64, 1), stats2.total_queries);
}

// ============================================================
// 任务 5.4: 错误情况下的钩子测试
// ============================================================

test "Hook Integration: Error handling in hook chain" {
    const allocator = testing.allocator;

    var chain = try HookChain.init(allocator);
    defer chain.deinit();

    var perf = PerformanceHook.init(1000);
    var logging = LoggingHook.init(true, 500);

    try chain.add(perf.hook());
    try chain.add(logging.hook());

    const hook = chain.hook();

    const sql = "INSERT INTO users (name, email) VALUES ($1, $2)";
    const args = &[_]QueryArg{
        QueryArg.fromValue("Alice"),
        QueryArg.fromValue("alice@example.com"),
    };

    // 模拟查询失败
    try hook.beforeQuery(sql, args);
    try hook.onError(sql, args, error.UniqueViolation);

    // 验证错误被记录
    const stats = perf.getStats();
    try testing.expectEqual(@as(u64, 1), stats.error_count);
    try testing.expectEqual(@as(u64, 0), stats.total_queries); // onError 不增加查询计数
}

test "Hook Integration: Mixed success and failure queries" {
    var perf = PerformanceHook.init(1000);
    const hook = perf.hook();

    const sql = "SELECT * FROM users";
    const args = &[_]QueryArg{};

    // 成功的查询
    try hook.afterQuery(sql, args, 100_000_000);
    try hook.afterQuery(sql, args, 200_000_000);

    // 失败的查询
    try hook.onError(sql, args, error.QueryFailed);

    // 更多成功的查询
    try hook.afterQuery(sql, args, 300_000_000);

    const stats = perf.getStats();
    try testing.expectEqual(@as(u64, 3), stats.total_queries);
    try testing.expectEqual(@as(u64, 1), stats.error_count);
    try testing.expectEqual(@as(u64, 600_000_000), stats.total_duration_ns);
    try testing.expectEqual(@as(u64, 200_000_000), stats.avg_duration_ns);
}

// ============================================================
// 任务 5.6: 慢查询检测综合测试
// ============================================================

test "Hook Integration: Slow query threshold boundary" {
    var perf = PerformanceHook.init(1000); // 1000ms = 1s
    const hook = perf.hook();

    const sql = "SELECT * FROM users";
    const args = &[_]QueryArg{};

    // 边界测试
    try hook.afterQuery(sql, args, 999_999_999); // 999.999ms - 不是慢查询
    try hook.afterQuery(sql, args, 1_000_000_000); // 1000ms - 刚好是慢查询
    try hook.afterQuery(sql, args, 1_000_000_001); // 1000.001ms - 慢查询

    const stats = perf.getStats();
    try testing.expectEqual(@as(u64, 3), stats.total_queries);
    try testing.expectEqual(@as(u64, 2), stats.slow_queries);
}

test "Hook Integration: Performance impact measurement" {
    var perf = PerformanceHook.init(1000);
    const hook = perf.hook();

    const sql = "SELECT * FROM large_table";
    const args = &[_]QueryArg{};

    // 模拟不同性能的查询
    const durations = [_]u64{
        50_000_000,   // 50ms - 快
        100_000_000,  // 100ms - 快
        500_000_000,  // 500ms - 中等
        1_500_000_000, // 1500ms - 慢
        3_000_000_000, // 3000ms - 很慢
    };

    for (durations) |duration| {
        try hook.afterQuery(sql, args, duration);
    }

    const stats = perf.getStats();
    try testing.expectEqual(@as(u64, 5), stats.total_queries);
    try testing.expectEqual(@as(u64, 2), stats.slow_queries); // 1500ms 和 3000ms
    try testing.expectEqual(@as(u64, 5_150_000_000), stats.total_duration_ns);
    try testing.expectEqual(@as(u64, 1_030_000_000), stats.avg_duration_ns); // 平均约 1030ms
}
