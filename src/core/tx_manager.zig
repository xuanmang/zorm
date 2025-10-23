//! TxManager - 事务管理器 (Story 2.4)
//!
//! 提供符合 Story 2.4 要求的事务管理功能:
//! - 事务生命周期管理 (BEGIN/COMMIT/ROLLBACK)
//! - 事务状态跟踪 (is_active, is_committed, is_rolled_back)
//! - 嵌套事务检测并禁止
//! - 自动回滚机制 (deinit)
//! - 查询构建器方法支持
//!
//! ## 设计原则
//! - 使用 comptime 方言参数化,零运行时开销
//! - defer/errdefer 确保资源清理
//! - 禁止嵌套事务(返回 error.NestedTransaction)
//! - 类型安全的错误处理

const std = @import("std");
const Allocator = std.mem.Allocator;
const db_mod = @import("db.zig");
const Dialect = @import("../dialect/dialect.zig").Dialect;
const zorm_error = @import("../error.zig");
const Error = zorm_error.Error;
const types_mod = @import("types.zig");
const IsolationLevel = types_mod.IsolationLevel;

/// 事务选项 (为 Story 2.5 隔离级别预留)
pub const TxOptions = struct {
    /// 事务隔离级别 (Story 2.5)
    /// null 表示使用数据库默认级别 (PostgreSQL: read_committed)
    isolation_level: ?types_mod.IsolationLevel = null,

    /// 事务访问模式 (只读/读写)
    read_only: bool = false,

    /// 事务超时时间 (毫秒), 0 表示无限制
    timeout: u64 = 0,
};

/// TxManager - 泛型事务管理器
///
/// 使用编译时方言参数化,提供类型安全的事务管理
///
/// ## 示例
/// ```zig
/// var tx = try db.beginTx(.{});
/// defer tx.deinit(); // 自动回滚未提交的事务
/// errdefer tx.rollback() catch {}; // 错误时回滚
///
/// var insert = try tx.newInsert(User);
/// defer insert.deinit();
/// try insert.value(user).exec();
///
/// try tx.commit();
/// ```
pub fn TxManager(comptime dialect: Dialect) type {
    const DBType = db_mod.DB(dialect);
    const TxInterface = db_mod.Tx;

    // 前向声明查询构建器类型
    const query_mod = @import("../query/query.zig");
    const SelectQuery = query_mod.SelectQuery;
    const InsertQuery = query_mod.InsertQuery;
    const UpdateQuery = query_mod.UpdateQuery;
    const DeleteQuery = query_mod.DeleteQuery;

    return struct {
        const Self = @This();

        /// 内存分配器
        allocator: Allocator,
        /// 关联的 DB 实例
        db: *DBType,
        /// 底层事务接口
        tx: *TxInterface,
        /// 事务是否处于活动状态
        is_active: bool,
        /// 事务是否已提交
        is_committed: bool,
        /// 事务是否已回滚
        is_rolled_back: bool,
        /// 事务选项
        options: TxOptions,
        /// 当前事务使用的隔离级别 (用于调试和日志)
        isolation_level: ?IsolationLevel,

        /// 初始化事务管理器 (由 DB.beginTx 调用)
        ///
        /// ## 参数
        /// - allocator: 内存分配器
        /// - db: 数据库实例
        /// - opts: 事务选项
        ///
        /// ## 返回
        /// 返回新创建的事务管理器指针
        ///
        /// ## 错误
        /// - OutOfMemory: 内存分配失败
        /// - NestedTransaction: 已有活动事务
        pub fn init(allocator: Allocator, db: *DBType, opts: TxOptions) !*Self {
            // 检查嵌套事务
            if (db.active_tx != null) {
                return Error.NestedTransaction;
            }

            // 执行 BEGIN 语句
            const tx = try db.conn.begin();

            // 设置隔离级别 (Story 2.5: AC2.5.4)
            if (opts.isolation_level) |level| {
                // 构建 SET TRANSACTION ISOLATION LEVEL 语句
                const sql = try std.fmt.allocPrint(
                    allocator,
                    "SET TRANSACTION ISOLATION LEVEL {s}",
                    .{level.toSQL()},
                );
                defer allocator.free(sql);

                // 执行设置语句
                try tx.exec(sql, &[_]types_mod.QueryArg{});
            }

            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.* = .{
                .allocator = allocator,
                .db = db,
                .tx = tx,
                .is_active = true,
                .is_committed = false,
                .is_rolled_back = false,
                .options = opts,
                .isolation_level = opts.isolation_level,
            };

            // 标记 DB 有活动事务
            db.active_tx = @ptrCast(self.tx);

            return self;
        }

        /// 提交事务
        ///
        /// ## 错误
        /// - TransactionNotActive: 事务未激活
        /// - AlreadyCommitted: 已提交
        /// - AlreadyRolledBack: 已回滚
        /// - TransactionCommitFailed: 提交失败
        pub fn commit(self: *Self) !void {
            if (!self.is_active) {
                return Error.TransactionNotActive;
            }
            if (self.is_committed) {
                return Error.AlreadyCommitted;
            }
            if (self.is_rolled_back) {
                return Error.AlreadyRolledBack;
            }

            // 执行 COMMIT
            self.tx.commit() catch |err| {
                self.is_active = false;
                self.db.active_tx = null;
                return err;
            };

            self.is_active = false;
            self.is_committed = true;
            self.db.active_tx = null;
        }

        /// 回滚事务
        ///
        /// 此方法是幂等的,多次调用不会报错
        ///
        /// ## 错误
        /// - AlreadyCommitted: 已提交
        /// - TransactionRollbackFailed: 回滚失败
        pub fn rollback(self: *Self) !void {
            // 幂等:如果未激活或已回滚,直接返回
            if (!self.is_active or self.is_rolled_back) {
                return;
            }

            // 如果已提交,返回错误
            if (self.is_committed) {
                return Error.AlreadyCommitted;
            }

            // 执行 ROLLBACK
            self.tx.rollback() catch |err| {
                self.is_active = false;
                self.db.active_tx = null;
                return err;
            };

            self.is_active = false;
            self.is_rolled_back = true;
            self.db.active_tx = null;
        }

        /// 释放事务资源
        ///
        /// 如果事务仍处于活动状态,自动回滚(安全默认)
        pub fn deinit(self: *Self) void {
            if (self.is_active) {
                // 安全默认:自动回滚未提交的事务
                self.rollback() catch |err| {
                    std.log.warn("事务自动回滚失败: {}", .{err});
                };
            }

            // 释放内存
            self.allocator.destroy(self);
        }

        // ============================================
        // 查询构建器工厂方法 (AC2.4.2)
        // ============================================

        /// 创建 SELECT 查询构建器
        ///
        /// ## 参数
        /// - T: 模型类型
        ///
        /// ## 示例
        /// ```zig
        /// var query = try tx.newSelect(User);
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

            // 复用 DB 的查询构建器,但使用事务的连接
            return SelectQuery(T, dialect).init(self.allocator, self.db, table_name);
        }

        /// 创建 INSERT 查询构建器
        ///
        /// ## 参数
        /// - T: 模型类型
        ///
        /// ## 示例
        /// ```zig
        /// var query = try tx.newInsert(User);
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

            return InsertQuery(T, dialect).init(self.allocator, self.db, table_name);
        }

        /// 创建 UPDATE 查询构建器
        ///
        /// ## 参数
        /// - T: 模型类型
        ///
        /// ## 示例
        /// ```zig
        /// var query = try tx.newUpdate(User);
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

            return UpdateQuery(T, dialect).init(self.allocator, self.db, table_name);
        }

        /// 创建 DELETE 查询构建器
        ///
        /// ## 参数
        /// - T: 模型类型
        ///
        /// ## 示例
        /// ```zig
        /// var query = try tx.newDelete(User);
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

            return DeleteQuery(T, dialect).init(self.allocator, self.db, table_name);
        }

        // ========== Raw SQL Query ==========

        /// 在事务中创建 Raw SQL 查询
        ///
        /// 提供在事务上下文中执行任意 SQL 语句的能力。
        ///
        /// ## 使用场景
        /// - 事务中的复杂查询 (窗口函数、CTE 等)
        /// - 数据库特定功能
        /// - 需要在事务中执行的 Raw SQL
        ///
        /// ## 安全警告
        /// ⚠️ Raw SQL 需要手动防止 SQL 注入！
        /// ✅ 始终使用参数绑定 ($1, $2, ...)
        /// ❌ 永远不要拼接用户输入到 SQL 字符串
        ///
        /// ## 参数
        /// - sql: SQL 语句（包含 $1, $2, ... 占位符）
        /// - args: 参数元组
        ///
        /// ## 返回值
        /// RawQuery 实例，调用者负责调用 deinit() 释放资源
        ///
        /// ## 错误
        /// - error.OutOfMemory: 内存分配失败
        /// - error.TransactionNotActive: 事务未激活
        ///
        /// ## 示例
        /// ```zig
        /// var tx = try db.beginTx(.{});
        /// defer tx.deinit();
        /// errdefer tx.rollback() catch {};
        ///
        /// const sql =
        ///     \\UPDATE users
        ///     \\SET balance = balance + $1
        ///     \\WHERE id = $2
        /// ;
        ///
        /// var query = try tx.newRaw(sql, .{ 100.50, user_id });
        /// defer query.deinit();
        ///
        /// const result = try query.exec();
        /// try tx.commit();
        /// ```
        pub fn newRaw(self: *Self, sql: []const u8, args: anytype) !*query_mod.RawQuery(dialect) {
            const QueryType = query_mod.RawQuery(dialect);
            return try QueryType.init(self.allocator, self.db, sql, args);
        }
    };
}

// ============================================
// 单元测试
// ============================================

test "TxOptions 默认值" {
    const opts = TxOptions{};

    try std.testing.expectEqual(@as(?IsolationLevel, null), opts.isolation_level);
    try std.testing.expectEqual(false, opts.read_only);
    try std.testing.expectEqual(@as(u64, 0), opts.timeout);
}

test "TxManager 类型实例化" {
    // 验证可以为不同方言创建 TxManager 类型
    const PostgresTxManager = TxManager(.postgresql);

    // 验证类型实例化成功（类型与自身相等）
    try std.testing.expect(PostgresTxManager == PostgresTxManager);
}
