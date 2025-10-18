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
const hooks_mod = @import("hooks.zig");
const QueryHook = hooks_mod.QueryHook;
const types_mod = @import("../types.zig");
const QueryArg = types_mod.QueryArg;
const driver = @import("../driver/connection.zig");
const Rows = driver.Rows;

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
        exec: *const fn (ptr: *anyopaque, query: []const u8, args: []const QueryArg) anyerror!void,
        query: *const fn (ptr: *anyopaque, query: []const u8, args: []const QueryArg) anyerror!*Result,
        begin: *const fn (ptr: *anyopaque) anyerror!*Tx,
        close: *const fn (ptr: *anyopaque) void,
    };

    pub fn exec(self: Conn, query_str: []const u8, args: []const QueryArg) !void {
        return self.vtable.exec(self.ptr, query_str, args);
    }

    pub fn query(self: Conn, query_str: []const u8, args: []const QueryArg) !*Result {
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
    /// 底层行迭代器 (暴露给用户直接访问)
    rows: Rows,

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
        exec: *const fn (ptr: *anyopaque, query: []const u8, args: []const QueryArg) anyerror!void,
        query: *const fn (ptr: *anyopaque, query: []const u8, args: []const QueryArg) anyerror!*Result,
        commit: *const fn (ptr: *anyopaque) anyerror!void,
        rollback: *const fn (ptr: *anyopaque) anyerror!void,
    };

    pub fn exec(self: *Tx, query_str: []const u8, args: []const QueryArg) !void {
        return self.vtable.exec(self.ptr, query_str, args);
    }

    pub fn query(self: *Tx, query_str: []const u8, args: []const QueryArg) !*Result {
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
    const CreateTableQuery = query_mod.CreateTableQuery;

    return struct {
        const Self = @This();

        allocator: Allocator,
        conn: Conn,
        options: DBOptions,
        stats: DBStats,
        current_tx: ?*Tx,
        /// 查询钩子列表 (支持多个钩子)
        query_hooks: std.ArrayList(QueryHook),

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
                .query_hooks = std.ArrayList(QueryHook).init(allocator),
            };

            return self;
        }

        /// 销毁数据库实例
        ///
        /// 自动清理所有资源:
        /// - 回滚活动事务(如果有)
        /// - 清理查询钩子列表
        /// - 关闭数据库连接
        /// - 释放分配的内存
        pub fn deinit(self: *Self) void {
            // 如果有活动事务,回滚它
            if (self.current_tx) |tx| {
                tx.rollback() catch {};
                self.current_tx = null;
            }

            // 清理钩子列表
            self.query_hooks.deinit();

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

        /// 添加查询钩子
        ///
        /// ## 参数
        /// - hook: 查询钩子实例
        ///
        /// ## 示例
        /// ```zig
        /// var logging = LoggingHook.init(true, 1000);
        /// try db.addHook(logging.hook());
        /// ```
        pub fn addHook(self: *Self, hook: QueryHook) !void {
            try self.query_hooks.append(hook);
        }

        /// 设置查询钩子 (别名,为了向后兼容)
        pub fn setHook(self: *Self, hook: QueryHook) !void {
            try self.addHook(hook);
        }

        /// 清空所有查询钩子
        pub fn clearHooks(self: *Self) void {
            self.query_hooks.clearRetainingCapacity();
        }

        /// 移除查询钩子 (别名,为了向后兼容)
        pub fn removeHook(self: *Self) void {
            self.clearHooks();
        }

        /// 克隆 DB 实例
        ///
        /// 创建一个新的 DB 实例,共享相同的连接,但有独立的:
        /// - 查询钩子列表
        /// - 统计信息
        /// - 事务状态
        ///
        /// ## 返回
        /// 返回克隆的 DB 实例,调用者负责调用 deinit() 释放
        ///
        /// ## 示例
        /// ```zig
        /// const cloned = try db.clone();
        /// defer cloned.deinit();
        /// ```
        pub fn clone(self: *const Self) !*Self {
            const new_db = try self.allocator.create(Self);
            errdefer self.allocator.destroy(new_db);

            new_db.* = .{
                .allocator = self.allocator,
                .conn = self.conn,  // 共享连接
                .options = self.options,
                .stats = .{},  // 新的统计信息
                .current_tx = null,  // 新的事务状态
                .query_hooks = std.ArrayList(QueryHook).init(self.allocator),
            };

            // 复制钩子列表
            try new_db.query_hooks.appendSlice(self.query_hooks.items);

            return new_db;
        }

        /// 克隆实例并添加查询钩子
        ///
        /// 这是一个便捷方法,等价于:
        /// ```zig
        /// const new_db = try db.clone();
        /// try new_db.addHook(hook);
        /// ```
        ///
        /// ## 参数
        /// - hook: 要添加的查询钩子
        ///
        /// ## 返回
        /// 返回添加了钩子的新 DB 实例
        ///
        /// ## 示例
        /// ```zig
        /// var logging = LoggingHook.init(true, 1000);
        /// const logged_db = try db.withQueryHook(logging.hook());
        /// defer logged_db.deinit();
        /// ```
        pub fn withQueryHook(self: *const Self, hook: QueryHook) !*Self {
            const new_db = try self.clone();
            errdefer new_db.deinit();
            try new_db.addHook(hook);
            return new_db;
        }

        /// 扫描行到目标列表
        ///
        /// ## 参数
        /// - T: 目标类型
        /// - rows: 行迭代器
        /// - dest: 目标 ArrayList
        ///
        /// ## 示例
        /// ```zig
        /// var users = std.ArrayList(User).init(allocator);
        /// defer users.deinit();
        ///
        /// const result = try db.query("SELECT * FROM users", .{});
        /// defer result.close();
        ///
        /// try db.scanRows(User, &result.rows, &users);
        /// ```
        pub fn scanRows(
            self: *Self,
            comptime T: type,
            rows: *Rows,
            dest: *std.ArrayList(T),
        ) !void {
            _ = self;
            
            // TODO: 实现行扫描逻辑
            // 1. 遍历 rows
            // 2. 为每行创建 T 实例
            // 3. 填充字段值
            // 4. 添加到 dest
            
            // 临时实现,避免未使用参数警告
            _ = rows;
            _ = dest;
        }

        /// 执行 SQL 语句(不返回结果)
        ///
        /// ## 参数
        /// - query_str: SQL 查询字符串
        /// - args: 查询参数
        ///
        /// ## 错误
        /// 如果查询执行失败,返回相应的错误
        pub fn exec(self: *Self, query_str: []const u8, args: []const QueryArg) !void {
            self.stats.recordQuery();

            // 执行钩子 - beforeQuery
            for (self.query_hooks.items) |hook| {
                hook.beforeQuery(query_str, args) catch |err| {
                    std.log.warn("Query hook beforeQuery failed: {}", .{err});
                };
            }

            // 如果有活动事务,使用事务执行
            const result = if (self.current_tx) |tx|
                tx.exec(query_str, args)
            else
                self.conn.exec(query_str, args);

            // 处理结果
            if (result) |_| {
                // 执行钩子 - afterQuery
                for (self.query_hooks.items) |hook| {
                    hook.afterQuery(query_str, args) catch |err| {
                        std.log.warn("Query hook afterQuery failed: {}", .{err});
                    };
                }
            } else |err| {
                self.stats.recordError();
                
                // 执行钩子 - onError
                for (self.query_hooks.items) |hook| {
                    hook.onError(query_str, args, err) catch |hook_err| {
                        std.log.warn("Query hook onError failed: {}", .{hook_err});
                    };
                }
                
                return err;
            }
        }

        /// 执行查询(返回结果)
        ///
        /// ## 参数
        /// - query_str: SQL 查询字符串
        /// - args: 查询参数
        ///
        /// ## 返回
        /// 返回查询结果集,调用者负责调用 result.close() 释放资源
        pub fn query(self: *Self, query_str: []const u8, args: []const QueryArg) !*Result {
            self.stats.recordQuery();

            // 执行钩子 - beforeQuery
            for (self.query_hooks.items) |hook| {
                hook.beforeQuery(query_str, args) catch |err| {
                    std.log.warn("Query hook beforeQuery failed: {}", .{err});
                };
            }

            // 如果有活动事务,使用事务执行
            const result = if (self.current_tx) |tx|
                tx.query(query_str, args)
            else
                self.conn.query(query_str, args);

            // 处理结果
            if (result) |res| {
                // 执行钩子 - afterQuery
                for (self.query_hooks.items) |hook| {
                    hook.afterQuery(query_str, args) catch |err| {
                        std.log.warn("Query hook afterQuery failed: {}", .{err});
                    };
                }
                return res;
            } else |err| {
                self.stats.recordError();
                
                // 执行钩子 - onError
                for (self.query_hooks.items) |hook| {
                    hook.onError(query_str, args, err) catch |hook_err| {
                        std.log.warn("Query hook onError failed: {}", .{hook_err});
                    };
                }
                
                return err;
            }
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

        /// 创建 CREATE TABLE 查询构建器
        ///
        /// ## 参数
        /// - table_name: 表名
        ///
        /// ## 示例
        /// ```zig
        /// const Column = @import("schema").Column;
        ///
        /// var query = try db.newCreateTable("users");
        /// defer query.deinit();
        ///
        /// var id_col = Column.init("id", .bigint);
        /// _ = id_col.setPrimaryKey().setAutoIncrement();
        ///
        /// var name_col = Column.init("name", .varchar);
        /// _ = name_col.setNotNull();
        ///
        /// try query.ifNotExists()
        ///     .column(id_col)
        ///     .column(name_col)
        ///     .exec();
        /// ```
        pub fn newCreateTable(self: *Self, table_name: []const u8) !*CreateTableQuery(dialect) {
            return CreateTableQuery(dialect).init(self.allocator, self, table_name);
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

test "DB clone 和 withQueryHook" {
    // TODO: 实现完整的测试
    // 需要模拟 Conn 和 QueryHook
}
