//! Hooks - 查询生命周期钩子系统
//!
//! 提供查询执行的生命周期钩子机制,支持:
//! - beforeQuery: 查询执行前的拦截和修改
//! - afterQuery: 查询执行后的统计和日志记录
//! - onError: 查询错误时的错误处理
//!
//! ## 设计模式
//! - VTable 模式实现多态,支持多种钩子实现
//! - 所有钩子方法都是必须实现的,确保完整的生命周期覆盖
//! - 支持链式调用多个钩子
//!
//! ## 使用示例
//! ```zig
//! var logging_hook = LoggingHook.init();
//! var hook = logging_hook.hook();
//!
//! const sql = "SELECT * FROM users WHERE id = $1";
//! const args = &[_]QueryArg{QueryArg.fromValue(1)};
//!
//! // 查询前
//! try hook.beforeQuery(sql, args);
//!
//! // 执行查询...
//! const result = db.query(sql, args) catch |err| {
//!     // 错误处理
//!     try hook.onError(sql, args, err);
//!     return err;
//! };
//!
//! // 查询后
//! const duration_ns = 1_500_000; // 1.5ms
//! try hook.afterQuery(sql, args, duration_ns);
//! ```

const std = @import("std");
const types = @import("../types.zig");
const QueryArg = types.QueryArg;

/// 查询钩子接口
///
/// 使用 VTable 模式实现运行时多态,支持多种钩子实现。
/// 所有钩子方法都是必需的,确保完整的生命周期覆盖。
pub const QueryHook = struct {
    const Self = @This();

    /// 指向具体钩子实现的指针
    ptr: *anyopaque,

    /// 虚函数表,包含所有钩子方法
    vtable: *const VTable,

    /// 虚函数表定义
    pub const VTable = struct {
        /// 查询执行前的钩子
        ///
        /// ## 参数
        /// - ptr: 钩子实例指针
        /// - sql: SQL 查询字符串
        /// - args: 查询参数数组
        ///
        /// ## 用途
        /// - 查询日志记录
        /// - SQL 语句验证
        /// - 参数验证
        /// - 查询计时开始
        beforeQuery: *const fn (ptr: *anyopaque, sql: []const u8, args: []const QueryArg) anyerror!void,

        /// 查询执行后的钩子
        ///
        /// ## 参数
        /// - ptr: 钩子实例指针
        /// - sql: SQL 查询字符串
        /// - args: 查询参数数组
        /// - duration_ns: 查询执行时长(纳秒)
        ///
        /// ## 用途
        /// - 性能统计
        /// - 慢查询日志
        /// - 查询结果缓存
        /// - 查询审计
        afterQuery: *const fn (ptr: *anyopaque, sql: []const u8, args: []const QueryArg, duration_ns: u64) anyerror!void,

        /// 查询错误时的钩子
        ///
        /// ## 参数
        /// - ptr: 钩子实例指针
        /// - sql: SQL 查询字符串
        /// - args: 查询参数数组
        /// - err: 错误类型
        ///
        /// ## 用途
        /// - 错误日志记录
        /// - 错误统计
        /// - 错误告警
        /// - 重试策略
        onError: *const fn (ptr: *anyopaque, sql: []const u8, args: []const QueryArg, err: anyerror) anyerror!void,
    };

    /// 调用 beforeQuery 钩子
    pub fn beforeQuery(self: Self, sql: []const u8, args: []const QueryArg) !void {
        try self.vtable.beforeQuery(self.ptr, sql, args);
    }

    /// 调用 afterQuery 钩子
    pub fn afterQuery(self: Self, sql: []const u8, args: []const QueryArg, duration_ns: u64) !void {
        try self.vtable.afterQuery(self.ptr, sql, args, duration_ns);
    }

    /// 调用 onError 钩子
    pub fn onError(self: Self, sql: []const u8, args: []const QueryArg, err: anyerror) !void {
        try self.vtable.onError(self.ptr, sql, args, err);
    }
};

/// 日志钩子实现
///
/// 提供基本的查询日志记录功能,可作为其他钩子实现的参考。
///
/// ## 功能
/// - beforeQuery: 输出查询 SQL 和参数
/// - afterQuery: 输出查询执行时间
/// - onError: 输出查询错误信息
///
/// ## 使用示例
/// ```zig
/// var logging_hook = LoggingHook.init();
/// var hook = logging_hook.hook();
/// ```
/// 性能统计数据
///
/// 用于记录和展示查询性能指标
pub const PerformanceStats = struct {
    /// 总查询数
    total_queries: u64,
    /// 总执行时间(纳秒)
    total_duration_ns: u64,
    /// 慢查询数量
    slow_queries: u64,
    /// 错误数量
    error_count: u64,
    /// 平均查询时间(纳秒)
    avg_duration_ns: u64,

    /// 格式化输出统计信息
    pub fn format(
        self: PerformanceStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print(
            "PerformanceStats{{ queries: {d}, avg: {d}ms, slow: {d}, errors: {d} }}",
            .{
                self.total_queries,
                self.avg_duration_ns / 1_000_000,
                self.slow_queries,
                self.error_count,
            },
        );
    }
};

/// 性能钩子实现
///
/// 提供查询性能追踪和慢查询检测功能
///
/// ## 功能
/// - beforeQuery: 记录查询开始时间
/// - afterQuery: 计算执行时长、更新统计、检测慢查询
/// - onError: 记录错误统计
/// - getStats: 获取性能统计数据
///
/// ## 线程安全
/// 使用原子操作确保多线程环境下的数据正确性
///
/// ## 使用示例
/// ```zig
/// var perf_hook = PerformanceHook.init(1000); // 1秒慢查询阈值
/// var hook = perf_hook.hook();
///
/// try db.addHook(hook);
///
/// // 执行查询...
///
/// const stats = perf_hook.getStats();
/// std.log.info("Performance: {}", .{stats});
/// ```
pub const PerformanceHook = struct {
    const Self = @This();

    /// 慢查询阈值(纳秒)
    slow_query_threshold_ns: u64,

    /// 总查询数
    total_queries: std.atomic.Value(u64),
    /// 总执行时间(纳秒)
    total_duration_ns: std.atomic.Value(u64),
    /// 慢查询计数
    slow_queries: std.atomic.Value(u64),
    /// 错误计数
    error_count: std.atomic.Value(u64),

    /// 创建性能钩子实例
    ///
    /// ## 参数
    /// - slow_query_threshold_ms: 慢查询阈值(毫秒)
    pub fn init(slow_query_threshold_ms: u64) Self {
        return .{
            .slow_query_threshold_ns = slow_query_threshold_ms * 1_000_000,
            .total_queries = std.atomic.Value(u64).init(0),
            .total_duration_ns = std.atomic.Value(u64).init(0),
            .slow_queries = std.atomic.Value(u64).init(0),
            .error_count = std.atomic.Value(u64).init(0),
        };
    }

    /// 获取 QueryHook 接口
    pub fn hook(self: *Self) QueryHook {
        return .{
            .ptr = self,
            .vtable = &.{
                .beforeQuery = beforeQueryImpl,
                .afterQuery = afterQueryImpl,
                .onError = onErrorImpl,
            },
        };
    }

    /// 获取性能统计数据
    pub fn getStats(self: *const Self) PerformanceStats {
        const total = self.total_queries.load(.monotonic);
        const duration = self.total_duration_ns.load(.monotonic);
        const avg = if (total > 0) duration / total else 0;

        return .{
            .total_queries = total,
            .total_duration_ns = duration,
            .slow_queries = self.slow_queries.load(.monotonic),
            .error_count = self.error_count.load(.monotonic),
            .avg_duration_ns = avg,
        };
    }

    /// 重置统计数据
    pub fn reset(self: *Self) void {
        self.total_queries.store(0, .monotonic);
        self.total_duration_ns.store(0, .monotonic);
        self.slow_queries.store(0, .monotonic);
        self.error_count.store(0, .monotonic);
    }

    fn beforeQueryImpl(ptr: *anyopaque, sql: []const u8, args: []const QueryArg) !void {
        _ = ptr;
        _ = sql;
        _ = args;
        // beforeQuery 不需要记录任何内容,仅为接口完整性
    }

    fn afterQueryImpl(ptr: *anyopaque, sql: []const u8, _: []const QueryArg, duration_ns: u64) !void {
        const self: *PerformanceHook = @ptrCast(@alignCast(ptr));

        // 更新总查询数
        _ = self.total_queries.fetchAdd(1, .monotonic);

        // 更新总时间
        _ = self.total_duration_ns.fetchAdd(duration_ns, .monotonic);

        // 检测慢查询
        if (duration_ns >= self.slow_query_threshold_ns) {
            _ = self.slow_queries.fetchAdd(1, .monotonic);
            const duration_ms = duration_ns / 1_000_000;
            std.log.warn("[ZORM] Performance: SLOW QUERY ({d}ms): {s}", .{ duration_ms, sql });
        }
    }

    fn onErrorImpl(ptr: *anyopaque, _: []const u8, _: []const QueryArg, _: anyerror) !void {
        const self: *PerformanceHook = @ptrCast(@alignCast(ptr));
        _ = self.error_count.fetchAdd(1, .monotonic);
    }
};

pub const LoggingHook = struct {
    /// 是否启用日志记录
    enabled: bool,

    /// 慢查询阈值(纳秒)
    slow_query_threshold_ns: u64,

    /// 创建日志钩子实例
    ///
    /// ## 参数
    /// - enabled: 是否启用日志
    /// - slow_query_threshold_ms: 慢查询阈值(毫秒)
    pub fn init(enabled: bool, slow_query_threshold_ms: u64) LoggingHook {
        return .{
            .enabled = enabled,
            .slow_query_threshold_ns = slow_query_threshold_ms * 1_000_000,
        };
    }

    /// 获取 QueryHook 接口
    pub fn hook(self: *LoggingHook) QueryHook {
        return .{
            .ptr = self,
            .vtable = &.{
                .beforeQuery = beforeQueryImpl,
                .afterQuery = afterQueryImpl,
                .onError = onErrorImpl,
            },
        };
    }

    fn beforeQueryImpl(ptr: *anyopaque, sql: []const u8, args: []const QueryArg) !void {
        const self: *LoggingHook = @ptrCast(@alignCast(ptr));
        if (!self.enabled) return;

        std.log.info("[ZORM] Executing query: {s}", .{sql});
        if (args.len > 0) {
            std.log.info("[ZORM] Arguments: {any}", .{args});
        }
    }

    fn afterQueryImpl(ptr: *anyopaque, sql: []const u8, _: []const QueryArg, duration_ns: u64) !void {
        const self: *LoggingHook = @ptrCast(@alignCast(ptr));
        if (!self.enabled) return;

        const duration_ms = duration_ns / 1_000_000;

        if (duration_ns >= self.slow_query_threshold_ns) {
            std.log.warn("[ZORM] SLOW QUERY ({d}ms): {s}", .{ duration_ms, sql });
        } else {
            std.log.info("[ZORM] Query completed in {d}ms", .{duration_ms});
        }
    }

    fn onErrorImpl(ptr: *anyopaque, sql: []const u8, args: []const QueryArg, err: anyerror) !void {
        const self: *LoggingHook = @ptrCast(@alignCast(ptr));
        if (!self.enabled) return;

        std.log.err("[ZORM] Query failed: {s}", .{sql});
        std.log.err("[ZORM] Error: {}", .{err});
        if (args.len > 0) {
            std.log.err("[ZORM] Arguments: {any}", .{args});
        }
    }
};

/// 钩子链 - 支持链式调用多个钩子
///
/// 允许按顺序执行多个钩子,实现复杂的查询生命周期管理。
///
/// ## 使用示例
/// ```zig
/// const allocator = std.heap.page_allocator;
/// var chain = try HookChain.init(allocator);
/// defer chain.deinit();
///
/// var logging = LoggingHook.init(true, 1000);
/// try chain.add(logging.hook());
///
/// var metrics = MetricsHook.init();
/// try chain.add(metrics.hook());
///
/// var hook = chain.hook();
/// try hook.beforeQuery("SELECT * FROM users", &.{});
/// ```
pub const HookChain = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    hooks: std.ArrayList(QueryHook),

    /// 创建钩子链
    pub fn init(allocator: std.mem.Allocator) !*Self {
        const chain = try allocator.create(Self);
        chain.* = .{
            .allocator = allocator,
            .hooks = .{},
        };
        chain.hooks = try std.ArrayList(QueryHook).initCapacity(allocator, 0);
        return chain;
    }

    /// 销毁钩子链
    pub fn deinit(self: *Self) void {
        self.hooks.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// 添加钩子到链中
    pub fn add(self: *Self, h: QueryHook) !void {
        try self.hooks.append(self.allocator, h);
    }

    /// 获取 QueryHook 接口
    pub fn hook(self: *Self) QueryHook {
        return .{
            .ptr = self,
            .vtable = &.{
                .beforeQuery = beforeQueryImpl,
                .afterQuery = afterQueryImpl,
                .onError = onErrorImpl,
            },
        };
    }

    fn beforeQueryImpl(ptr: *anyopaque, sql: []const u8, args: []const QueryArg) !void {
        const self: *HookChain = @ptrCast(@alignCast(ptr));
        for (self.hooks.items) |h| {
            try h.beforeQuery(sql, args);
        }
    }

    fn afterQueryImpl(ptr: *anyopaque, sql: []const u8, args: []const QueryArg, duration_ns: u64) !void {
        const self: *HookChain = @ptrCast(@alignCast(ptr));
        for (self.hooks.items) |h| {
            try h.afterQuery(sql, args, duration_ns);
        }
    }

    fn onErrorImpl(ptr: *anyopaque, sql: []const u8, args: []const QueryArg, err: anyerror) !void {
        const self: *HookChain = @ptrCast(@alignCast(ptr));
        for (self.hooks.items) |h| {
            try h.onError(sql, args, err);
        }
    }
};

// ============================================
// 单元测试
// ============================================

test "LoggingHook basic functionality" {
    var logging = LoggingHook.init(true, 1000);
    var h = logging.hook();

    const sql = "SELECT * FROM users WHERE id = $1";
    const args = &[_]QueryArg{QueryArg.fromValue(1)};

    // 测试 beforeQuery
    try h.beforeQuery(sql, args);

    // 测试 afterQuery (快速查询)
    try h.afterQuery(sql, args, 500_000); // 0.5ms

    // 测试 afterQuery (慢查询)
    try h.afterQuery(sql, args, 2_000_000_000); // 2000ms

    // 测试 onError
    try h.onError(sql, args, error.TestError);
}

test "LoggingHook disabled" {
    var logging = LoggingHook.init(false, 1000);
    var h = logging.hook();

    const sql = "SELECT * FROM users";
    const args = &[_]QueryArg{};

    // 禁用时不应输出日志
    try h.beforeQuery(sql, args);
    try h.afterQuery(sql, args, 1_000_000);
    try h.onError(sql, args, error.TestError);
}

test "HookChain with multiple hooks" {
    const allocator = std.testing.allocator;

    var chain = try HookChain.init(allocator);
    defer chain.deinit();

    // 添加第一个钩子
    var logging1 = LoggingHook.init(true, 1000);
    try chain.add(logging1.hook());

    // 添加第二个钩子
    var logging2 = LoggingHook.init(true, 500);
    try chain.add(logging2.hook());

    // 获取链式钩子
    var h = chain.hook();

    const sql = "SELECT * FROM users";
    const args = &[_]QueryArg{};

    // 测试链式调用
    try h.beforeQuery(sql, args);
    try h.afterQuery(sql, args, 1_000_000);
    try h.onError(sql, args, error.TestError);
}

test "HookChain empty chain" {
    const allocator = std.testing.allocator;

    var chain = try HookChain.init(allocator);
    defer chain.deinit();

    var h = chain.hook();

    const sql = "SELECT * FROM users";
    const args = &[_]QueryArg{};

    // 空链不应报错
    try h.beforeQuery(sql, args);
    try h.afterQuery(sql, args, 1_000_000);
    try h.onError(sql, args, error.TestError);
}

test "QueryHook interface" {
    var logging = LoggingHook.init(true, 1000);
    const h = logging.hook();

    // 验证接口类型
    try std.testing.expect(@TypeOf(h) == QueryHook);

    // 验证可以调用钩子方法
    const sql = "SELECT * FROM test";
    const args = &[_]QueryArg{};
    try h.beforeQuery(sql, args);
    try h.afterQuery(sql, args, 1_000_000);
    try h.onError(sql, args, error.TestError);
}

test "PerformanceHook basic functionality" {
    var perf = PerformanceHook.init(1000); // 1秒阈值
    var h = perf.hook();

    const sql = "SELECT * FROM users WHERE id = $1";
    const args = &[_]QueryArg{QueryArg.fromValue(1)};

    // 初始统计应该为 0
    var stats = perf.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.total_queries);
    try std.testing.expectEqual(@as(u64, 0), stats.slow_queries);
    try std.testing.expectEqual(@as(u64, 0), stats.error_count);

    // 测试快速查询
    try h.beforeQuery(sql, args);
    try h.afterQuery(sql, args, 500_000_000); // 500ms
    
    stats = perf.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.total_queries);
    try std.testing.expectEqual(@as(u64, 0), stats.slow_queries);
    try std.testing.expectEqual(@as(u64, 500_000_000), stats.total_duration_ns);

    // 测试慢查询
    try h.beforeQuery(sql, args);
    try h.afterQuery(sql, args, 2_000_000_000); // 2000ms
    
    stats = perf.getStats();
    try std.testing.expectEqual(@as(u64, 2), stats.total_queries);
    try std.testing.expectEqual(@as(u64, 1), stats.slow_queries);
    try std.testing.expectEqual(@as(u64, 2_500_000_000), stats.total_duration_ns);
    try std.testing.expectEqual(@as(u64, 1_250_000_000), stats.avg_duration_ns);

    // 测试错误统计
    try h.onError(sql, args, error.TestError);
    stats = perf.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.error_count);
}

test "PerformanceHook reset" {
    var perf = PerformanceHook.init(1000);
    var h = perf.hook();

    const sql = "SELECT * FROM users";
    const args = &[_]QueryArg{};

    // 记录一些查询
    try h.afterQuery(sql, args, 1_000_000);
    try h.afterQuery(sql, args, 2_000_000);
    try h.onError(sql, args, error.TestError);

    var stats = perf.getStats();
    try std.testing.expect(stats.total_queries > 0);

    // 重置统计
    perf.reset();
    stats = perf.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.total_queries);
    try std.testing.expectEqual(@as(u64, 0), stats.total_duration_ns);
    try std.testing.expectEqual(@as(u64, 0), stats.slow_queries);
    try std.testing.expectEqual(@as(u64, 0), stats.error_count);
}

test "PerformanceHook average calculation" {
    var perf = PerformanceHook.init(1000);
    var h = perf.hook();

    const sql = "SELECT * FROM test";
    const args = &[_]QueryArg{};

    // 添加 3 个查询: 100ms, 200ms, 300ms
    try h.afterQuery(sql, args, 100_000_000);
    try h.afterQuery(sql, args, 200_000_000);
    try h.afterQuery(sql, args, 300_000_000);

    const stats = perf.getStats();
    try std.testing.expectEqual(@as(u64, 3), stats.total_queries);
    try std.testing.expectEqual(@as(u64, 600_000_000), stats.total_duration_ns);
    try std.testing.expectEqual(@as(u64, 200_000_000), stats.avg_duration_ns);
}

test "HookChain with PerformanceHook and LoggingHook" {
    const allocator = std.testing.allocator;

    var chain = try HookChain.init(allocator);
    defer chain.deinit();

    // 添加 PerformanceHook
    var perf = PerformanceHook.init(1000);
    try chain.add(perf.hook());

    // 添加 LoggingHook
    var logging = LoggingHook.init(true, 500);
    try chain.add(logging.hook());

    // 获取链式钩子
    var h = chain.hook();

    const sql = "SELECT * FROM users WHERE id = $1";
    const args = &[_]QueryArg{QueryArg.fromValue(1)};

    // 测试快速查询
    try h.beforeQuery(sql, args);
    try h.afterQuery(sql, args, 300_000_000); // 300ms

    // 测试慢查询
    try h.beforeQuery(sql, args);
    try h.afterQuery(sql, args, 1_500_000_000); // 1500ms

    // 测试错误
    try h.onError(sql, args, error.TestError);

    // 验证 PerformanceHook 统计
    const stats = perf.getStats();
    try std.testing.expectEqual(@as(u64, 2), stats.total_queries);
    try std.testing.expectEqual(@as(u64, 1), stats.slow_queries);
    try std.testing.expectEqual(@as(u64, 1), stats.error_count);
}
