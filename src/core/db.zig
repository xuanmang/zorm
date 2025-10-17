//! DB - 数据库实例和连接管理
//!
//! DB 是 ZORM 的核心泛型结构,负责:
//! - 数据库连接管理
//! - 查询构建器工厂方法
//! - 事务管理
//! - 查询钩子管理
//! - 连接池统计
//!
//! ## 设计原则
//! - 使用 comptime 参数化方言,实现零运行时开销
//! - 显式 Allocator 管理,遵循 Zig 内存管理最佳实践
//! - 强制错误处理,所有可能失败的操作返回 !T

const std = @import("std");
const Allocator = std.mem.Allocator;
const dialect_mod = @import("../dialect/dialect.zig");
const Dialect = dialect_mod.Dialect;

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

    /// 查询超时 (毫秒)
    query_timeout: u64 = 30_000,

    /// 启用查询日志
    enable_query_log: bool = false,

    /// 启用慢查询日志
    enable_slow_query_log: bool = false,

    /// 慢查询阈值 (毫秒)
    slow_query_threshold: u64 = 1000,
};

/// 连接统计信息
/// 使用原子操作确保线程安全
pub const DBStats = struct {
    /// 总查询数
    total_queries: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    /// 总错误数
    total_errors: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    /// 当前打开的连接数
    open_connections: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    /// 当前空闲的连接数
    idle_connections: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    /// 记录一次查询
    pub fn recordQuery(self: *DBStats) void {
        _ = self.total_queries.fetchAdd(1, .monotonic);
    }

    /// 记录一次错误
    pub fn recordError(self: *DBStats) void {
        _ = self.total_errors.fetchAdd(1, .monotonic);
    }

    /// 获取查询总数
    pub fn getQueryCount(self: *const DBStats) u64 {
        return self.total_queries.load(.monotonic);
    }

    /// 获取错误总数
    pub fn getErrorCount(self: *const DBStats) u64 {
        return self.total_errors.load(.monotonic);
    }

    /// 获取打开的连接数
    pub fn getOpenConnections(self: *const DBStats) u32 {
        return self.open_connections.load(.monotonic);
    }

    /// 获取空闲连接数
    pub fn getIdleConnections(self: *const DBStats) u32 {
        return self.idle_connections.load(.monotonic);
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

/// DB - 泛型数据库实例
///
/// 使用 comptime 参数化方言,实现零运行时开销的多数据库支持
///
/// ## 示例
/// ```zig
/// const PostgresDB = DB(.postgresql);
/// const db = try PostgresDB.init(allocator, conn, .{});
/// defer db.deinit();
///
/// var query = try db.newSelect(User);
/// defer query.deinit();
/// ```
pub fn DB(comptime dialect: Dialect) type {
    // 前向声明查询构建器类型(将在 query.zig 中定义)
    const query_mod = @import("../query/query.zig");
    const SelectQuery = query_mod.SelectQuery;
    const InsertQuery = query_mod.InsertQuery;
    const UpdateQuery = query_mod.UpdateQuery;
    const DeleteQuery = query_mod.DeleteQuery;

    return struct {
        const Self = @This();

        allocator: Allocator,
        conn: Conn,
        options: DBOptions,
        stats: DBStats,
        current_tx: ?*Tx,

        /// 创建数据库实例
        ///
        /// ## 参数
        /// - allocator: 内存分配器
        /// - conn: 数据库连接
        /// - options: 数据库配置选项
        ///
        /// ## 返回
        /// 返回新创建的 DB 实例指针,失败时返回错误
        pub fn init(
            allocator: Allocator,
            conn: Conn,
            options: DBOptions,
        ) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.* = .{
                .allocator = allocator,
                .conn = conn,
                .options = options,
                .stats = .{},
                .current_tx = null,
            };

            return self;
        }

        /// 销毁数据库实例
        ///
        /// 自动清理所有资源:
        /// - 回滚活动事务(如果有)
        /// - 关闭数据库连接
        /// - 释放分配的内存
        pub fn deinit(self: *Self) void {
            // 如果有活动事务,回滚它
            if (self.current_tx) |tx| {
                tx.rollback() catch {};
                self.current_tx = null;
            }

            // 关闭连接
            self.conn.close();

            // 释放内存
            self.allocator.destroy(self);
        }

        /// 获取编译时确定的方言类型
        ///
        /// 这个方法是编译时已知的,调用它不会产生任何运行时开销
        pub fn getDialect() Dialect {
            return dialect;
        }

        /// 获取统计信息的副本
        pub fn getStats(self: *const Self) DBStats {
            return self.stats;
        }

        /// 执行 SQL 语句(不返回结果)
        ///
        /// ## 参数
        /// - query_str: SQL 查询字符串
        /// - args: 查询参数
        ///
        /// ## 错误
        /// 如果查询执行失败,返回相应的错误
        pub fn exec(self: *Self, query_str: []const u8, args: []const []const u8) !void {
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
        ///
        /// ## 参数
        /// - query_str: SQL 查询字符串
        /// - args: 查询参数
        ///
        /// ## 返回
        /// 返回查询结果集,调用者负责调用 result.close() 释放资源
        pub fn query(self: *Self, query_str: []const u8, args: []const []const u8) !*Result {
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
        ///
        /// ## 错误
        /// - TransactionAlreadyStarted: 已有活动事务
        pub fn begin(self: *Self) !*Tx {
            if (self.current_tx != null) {
                return error.TransactionAlreadyStarted;
            }

            const tx = try self.conn.begin();
            self.current_tx = tx;
            return tx;
        }

        /// 提交事务
        ///
        /// ## 错误
        /// - NoActiveTransaction: 没有活动事务
        pub fn commit(self: *Self) !void {
            const tx = self.current_tx orelse return error.NoActiveTransaction;
            defer self.current_tx = null;
            return tx.commit();
        }

        /// 回滚事务
        ///
        /// ## 错误
        /// - NoActiveTransaction: 没有活动事务
        pub fn rollback(self: *Self) !void {
            const tx = self.current_tx orelse return error.NoActiveTransaction;
            defer self.current_tx = null;
            return tx.rollback();
        }

        /// 在事务中执行函数
        ///
        /// 如果函数返回错误,自动回滚;否则自动提交
        ///
        /// ## 参数
        /// - func: 要执行的函数
        /// - args: 函数参数
        ///
        /// ## 示例
        /// ```zig
        /// try db.runInTx(struct {
        ///     fn execute(d: *DB(.postgresql)) !void {
        ///         try d.exec("INSERT INTO users (name) VALUES ($1)", .{"Alice"});
        ///     }
        /// }.execute, .{db});
        /// ```
        pub fn runInTx(self: *Self, comptime func: anytype, args: anytype) !@TypeOf(@call(.auto, func, args)) {
            _ = try self.begin();
            errdefer self.rollback() catch {};

            const result = try @call(.auto, func, args);
            try self.commit();
            return result;
        }

        // ============================================
        // 查询构建器工厂方法
        // ============================================

        /// 创建 SELECT 查询构建器
        ///
        /// ## 参数
        /// - T: 模型类型
        /// - table_name: 表名 (如果模型定义了 table_name 常量,可以不传)
        ///
        /// ## 示例
        /// ```zig
        /// const User = struct {
        ///     id: i64,
        ///     name: []const u8,
        ///     pub const table_name = "users";
        /// };
        ///
        /// var query = try db.newSelect(User);
        /// defer query.deinit();
        /// ```
        pub fn newSelect(self: *Self, comptime T: type) !*SelectQuery(T, dialect) {
            const table_name = comptime blk: {
                if (@hasDecl(T, "table_name")) {
                    break :blk T.table_name;
                } else {
                    break :blk @typeName(T);
                }
            };

            return SelectQuery(T, dialect).init(self.allocator, self, table_name);
        }

        /// 创建 INSERT 查询构建器
        ///
        /// ## 参数
        /// - T: 模型类型
        ///
        /// ## 示例
        /// ```zig
        /// var query = try db.newInsert(User);
        /// defer query.deinit();
        /// ```
        pub fn newInsert(self: *Self, comptime T: type) !*InsertQuery(T, dialect) {
            const table_name = comptime blk: {
                if (@hasDecl(T, "table_name")) {
                    break :blk T.table_name;
                } else {
                    break :blk @typeName(T);
                }
            };

            return InsertQuery(T, dialect).init(self.allocator, self, table_name);
        }

        /// 创建 UPDATE 查询构建器
        ///
        /// ## 参数
        /// - T: 模型类型
        ///
        /// ## 示例
        /// ```zig
        /// var query = try db.newUpdate(User);
        /// defer query.deinit();
        /// ```
        pub fn newUpdate(self: *Self, comptime T: type) !*UpdateQuery(T, dialect) {
            const table_name = comptime blk: {
                if (@hasDecl(T, "table_name")) {
                    break :blk T.table_name;
                } else {
                    break :blk @typeName(T);
                }
            };

            return UpdateQuery(T, dialect).init(self.allocator, self, table_name);
        }

        /// 创建 DELETE 查询构建器
        ///
        /// ## 参数
        /// - T: 模型类型
        ///
        /// ## 示例
        /// ```zig
        /// var query = try db.newDelete(User);
        /// defer query.deinit();
        /// ```
        pub fn newDelete(self: *Self, comptime T: type) !*DeleteQuery(T, dialect) {
            const table_name = comptime blk: {
                if (@hasDecl(T, "table_name")) {
                    break :blk T.table_name;
                } else {
                    break :blk @typeName(T);
                }
            };

            return DeleteQuery(T, dialect).init(self.allocator, self, table_name);
        }
    };
}

// ============================================
// 单元测试
// ============================================

test "DBStats 基本操作" {
    var stats = DBStats{};

    try std.testing.expectEqual(@as(u64, 0), stats.getQueryCount());
    try std.testing.expectEqual(@as(u64, 0), stats.getErrorCount());

    stats.recordQuery();
    stats.recordQuery();
    stats.recordError();

    try std.testing.expectEqual(@as(u64, 2), stats.getQueryCount());
    try std.testing.expectEqual(@as(u64, 1), stats.getErrorCount());
}

test "DB 泛型实例化" {
    // 验证可以为不同方言创建 DB 类型
    const PostgresDB = DB(.postgresql);
    const MySQLDB = DB(.mysql);
    const SQLiteDB = DB(.sqlite);

    // 验证它们是不同的类型
    try std.testing.expect(PostgresDB != MySQLDB);
    try std.testing.expect(PostgresDB != SQLiteDB);
    try std.testing.expect(MySQLDB != SQLiteDB);

    // 验证 getDialect 编译时求值
    try std.testing.expectEqual(Dialect.postgresql, PostgresDB.getDialect());
    try std.testing.expectEqual(Dialect.mysql, MySQLDB.getDialect());
    try std.testing.expectEqual(Dialect.sqlite, SQLiteDB.getDialect());
}

test "DBOptions 默认值" {
    const opts = DBOptions{};

    try std.testing.expectEqual(false, opts.discard_unknown_columns);
    try std.testing.expectEqual(@as(u32, 25), opts.max_open_conns);
    try std.testing.expectEqual(@as(u32, 25), opts.max_idle_conns);
    try std.testing.expectEqual(@as(u64, 300), opts.conn_max_lifetime);
    try std.testing.expectEqual(@as(u64, 30_000), opts.query_timeout);
}
