//! Transaction - 事务管理模块
//!
//! 提供高级事务管理功能:
//! - 事务生命周期管理 (BEGIN/COMMIT/ROLLBACK)
//! - 嵌套事务支持 (通过保存点实现)
//! - 自动回滚机制 (defer/errdefer)
//! - 便捷的 withTransaction 辅助函数
//!
//! ## 设计原则
//! - 使用 comptime 方言参数化,零运行时开销
//! - defer/errdefer 确保资源清理
//! - 支持嵌套事务通过保存点机制
//! - 类型安全的错误处理

const std = @import("std");
const Allocator = std.mem.Allocator;
const db_mod = @import("db.zig");
const DB = db_mod.DB;
const Tx = db_mod.Tx;
const dialect_mod = @import("../dialect/dialect.zig");
const Dialect = dialect_mod.Dialect;

/// 事务错误类型
pub const TransactionError = error{
    /// 没有活动事务
    NoActiveTransaction,
    /// 事务已经开始
    TransactionAlreadyStarted,
    /// 事务提交失败
    TransactionCommitFailed,
    /// 事务回滚失败
    TransactionRollbackFailed,
    /// 保存点不存在
    SavepointNotFound,
    /// 保存点已存在
    SavepointAlreadyExists,
};

/// Transaction - 泛型事务管理器
///
/// 使用编译时方言参数化,提供类型安全的事务管理
///
/// ## 示例
/// ```zig
/// // 方式1: 手动管理
/// var tx = try Transaction(.postgresql).begin(db);
/// defer tx.rollback() catch {}; // 确保异常时回滚
///
/// try db.exec("INSERT INTO users (name) VALUES ($1)", &[_][]const u8{"Alice"});
/// try tx.commit();
///
/// // 方式2: 自动管理
/// try Transaction(.postgresql).withTransaction(db, struct {
///     fn execute(d: *DB(.postgresql)) !void {
///         try d.exec("INSERT INTO users (name) VALUES ($1)", &[_][]const u8{"Bob"});
///     }
/// }.execute, .{db});
/// ```
pub fn Transaction(comptime dialect: Dialect) type {
    return struct {
        const Self = @This();
        const DBType = DB(dialect);

        /// 关联的 DB 实例
        db: *DBType,
        /// 底层事务对象
        tx: *Tx,
        /// 事务是否处于活动状态
        active: bool,
        /// 当前保存点层级
        savepoint_level: u32,
        /// 内存分配器
        allocator: Allocator,

        /// 开始事务
        ///
        /// ## 参数
        /// - db: 数据库实例
        ///
        /// ## 返回
        /// 返回新创建的事务实例
        ///
        /// ## 错误
        /// - TransactionAlreadyStarted: 数据库已有活动事务
        pub fn begin(db: *DBType) !Self {
            const tx = try db.begin();

            return .{
                .db = db,
                .tx = tx,
                .active = true,
                .savepoint_level = 0,
                .allocator = db.allocator,
            };
        }

        /// 提交事务
        ///
        /// ## 错误
        /// - NoActiveTransaction: 事务未激活
        /// - TransactionCommitFailed: 提交失败
        pub fn commit(self: *Self) !void {
            if (!self.active) {
                return TransactionError.NoActiveTransaction;
            }

            self.tx.commit() catch |err| {
                self.active = false;
                return err;
            };

            self.active = false;
        }

        /// 回滚事务
        ///
        /// ## 错误
        /// - NoActiveTransaction: 事务未激活
        /// - TransactionRollbackFailed: 回滚失败
        pub fn rollback(self: *Self) !void {
            if (!self.active) {
                return TransactionError.NoActiveTransaction;
            }

            self.tx.rollback() catch |err| {
                self.active = false;
                return err;
            };

            self.active = false;
        }

        /// 创建保存点 (嵌套事务)
        ///
        /// ## 参数
        /// - name: 保存点名称
        ///
        /// ## 错误
        /// - NoActiveTransaction: 事务未激活
        pub fn savepoint(self: *Self, name: []const u8) !void {
            if (!self.active) {
                return TransactionError.NoActiveTransaction;
            }

            // 构建 SAVEPOINT SQL
            const sql = try std.fmt.allocPrint(
                self.allocator,
                "SAVEPOINT {s}",
                .{name},
            );
            defer self.allocator.free(sql);

            try self.tx.exec(sql, &.{});
            self.savepoint_level += 1;
        }

        /// 回滚到指定保存点
        ///
        /// ## 参数
        /// - name: 保存点名称
        ///
        /// ## 错误
        /// - NoActiveTransaction: 事务未激活
        pub fn rollbackTo(self: *Self, name: []const u8) !void {
            if (!self.active) {
                return TransactionError.NoActiveTransaction;
            }

            // 构建 ROLLBACK TO SAVEPOINT SQL
            const sql = try std.fmt.allocPrint(
                self.allocator,
                "ROLLBACK TO SAVEPOINT {s}",
                .{name},
            );
            defer self.allocator.free(sql);

            try self.tx.exec(sql, &.{});
        }

        /// 释放保存点
        ///
        /// 释放保存点会删除该保存点,但保留其之前的所有更改
        ///
        /// ## 参数
        /// - name: 保存点名称
        ///
        /// ## 错误
        /// - NoActiveTransaction: 事务未激活
        pub fn releaseSavepoint(self: *Self, name: []const u8) !void {
            if (!self.active) {
                return TransactionError.NoActiveTransaction;
            }

            // 构建 RELEASE SAVEPOINT SQL
            const sql = try std.fmt.allocPrint(
                self.allocator,
                "RELEASE SAVEPOINT {s}",
                .{name},
            );
            defer self.allocator.free(sql);

            try self.tx.exec(sql, &.{});

            if (self.savepoint_level > 0) {
                self.savepoint_level -= 1;
            }
        }

        /// 在事务中执行函数 (自动管理)
        ///
        /// 如果函数返回错误,自动回滚;否则自动提交
        ///
        /// ## 参数
        /// - db: 数据库实例
        /// - func: 要执行的函数
        /// - args: 函数参数
        ///
        /// ## 返回
        /// 返回函数的返回值
        ///
        /// ## 示例
        /// ```zig
        /// const result = try Transaction(.postgresql).withTransaction(db, struct {
        ///     fn execute(d: *DB(.postgresql)) !u64 {
        ///         try d.exec("INSERT INTO users (name) VALUES ($1)", &[_][]const u8{"Alice"});
        ///         return 123;
        ///     }
        /// }.execute, .{db});
        /// ```
        pub fn withTransaction(
            db: *DBType,
            comptime func: anytype,
            args: anytype,
        ) !@TypeOf(@call(.auto, func, args)) {
            var tx = try Self.begin(db);
            errdefer tx.rollback() catch {};

            const result = try @call(.auto, func, args);
            try tx.commit();

            return result;
        }

        /// 在保存点中执行函数 (自动管理)
        ///
        /// 如果函数返回错误,自动回滚到保存点;否则释放保存点
        ///
        /// ## 参数
        /// - name: 保存点名称
        /// - func: 要执行的函数
        /// - args: 函数参数
        ///
        /// ## 返回
        /// 返回函数的返回值
        ///
        /// ## 示例
        /// ```zig
        /// var tx = try Transaction(.postgresql).begin(db);
        /// defer tx.rollback() catch {};
        ///
        /// try tx.withSavepoint("sp1", struct {
        ///     fn execute(d: *DB(.postgresql)) !void {
        ///         try d.exec("INSERT INTO users (name) VALUES ($1)", &[_][]const u8{"Alice"});
        ///     }
        /// }.execute, .{tx.db});
        ///
        /// try tx.commit();
        /// ```
        pub fn withSavepoint(
            self: *Self,
            name: []const u8,
            comptime func: anytype,
            args: anytype,
        ) !@TypeOf(@call(.auto, func, args)) {
            try self.savepoint(name);
            errdefer self.rollbackTo(name) catch {};

            const result = try @call(.auto, func, args);
            try self.releaseSavepoint(name);

            return result;
        }
    };
}

// ============================================
// 单元测试
// ============================================

test "Transaction 类型实例化" {
    // 验证可以为不同方言创建 Transaction 类型
    const PostgresTx = Transaction(.postgresql);
    const MySQLTx = Transaction(.mysql);
    const SQLiteTx = Transaction(.sqlite);

    // 验证它们是不同的类型
    try std.testing.expect(PostgresTx != MySQLTx);
    try std.testing.expect(PostgresTx != SQLiteTx);
    try std.testing.expect(MySQLTx != SQLiteTx);
}

test "TransactionError 错误类型" {
    const err1 = TransactionError.NoActiveTransaction;
    const err2 = TransactionError.TransactionAlreadyStarted;

    try std.testing.expect(err1 != err2);
}
