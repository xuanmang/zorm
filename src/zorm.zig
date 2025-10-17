//! ZORM - SQL-first ORM for Zig
//!
//! ZORM 是一个受 Bun ORM 启发,专为 Zig 语言设计的 SQL-first ORM 库。
//! 核心特性:
//! - 显式内存管理,使用 Allocator 模式
//! - comptime 泛型和零开销抽象
//! - 类型安全的查询构建器
//! - 多数据库方言支持 (PostgreSQL, MySQL, SQLite, MSSQL, Oracle)
//! - 强制错误处理
//!
//! 基本使用:
//! ```zig
//! const zorm = @import("zorm");
//!
//! const User = struct {
//!     id: i64,
//!     name: []const u8,
//!     email: []const u8,
//! };
//!
//! // 创建数据库连接
//! var db = try zorm.DB.open(allocator, .{
//!     .dialect = .postgresql,
//!     .dsn = "postgres://user:pass@localhost/mydb",
//! });
//! defer db.close();
//!
//! // 构建查询
//! var query = try db.newSelect(User);
//! defer query.deinit();
//! try query.where("email = ?", .{"user@example.com"});
//!
//! // 执行查询
//! const user = try query.scanOne();
//! ```

const std = @import("std");
const builtin = @import("builtin");

// 导出核心模块
pub const core = @import("core/db.zig");
pub const transaction = @import("core/transaction.zig");
pub const hooks = @import("core/hooks.zig");
pub const dialect = @import("dialect/dialect.zig");
pub const sql = @import("dialect/sql.zig");
pub const query = @import("query/query.zig");
pub const schema = @import("schema/schema.zig");
pub const driver = struct {
    pub const postgres = @import("driver/postgres.zig");
    pub const connection = @import("driver/connection.zig");
    pub const pool = @import("driver/pool.zig");
};

// 导出常用驱动类型
pub const PostgresDriver = driver.postgres.PostgresDriver;
pub const Connection = driver.connection.Connection;
pub const Result = driver.connection.Result;
pub const Rows = driver.connection.Rows;
pub const Row = driver.connection.Row;
pub const Pool = driver.pool.Pool;
pub const PoolConfig = driver.pool.PoolConfig;
pub const PoolStats = driver.pool.PoolStats;

// 导出常用类型
pub const DB = core.DB;
pub const DBOptions = core.DBOptions;
pub const Transaction = transaction.Transaction;
pub const TransactionError = transaction.TransactionError;
pub const Dialect = dialect.Dialect;
pub const Feature = dialect.Feature;
pub const QueryArg = @import("types.zig").QueryArg;

// 导出钩子类型
pub const QueryHook = hooks.QueryHook;
pub const LoggingHook = hooks.LoggingHook;
pub const HookChain = hooks.HookChain;

// 导出查询构建器
pub const SelectQuery = query.SelectQuery;
pub const InsertQuery = query.InsertQuery;
pub const UpdateQuery = query.UpdateQuery;
pub const DeleteQuery = query.DeleteQuery;

// 导出完整的错误类型模块
pub const errors = @import("error.zig");
pub const Error = errors.Error;

// 版本信息
pub const version = std.SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 0,
};

// 测试
test {
    std.testing.refAllDecls(@This());
}

test "version" {
    try std.testing.expectEqual(0, version.major);
    try std.testing.expectEqual(1, version.minor);
    try std.testing.expectEqual(0, version.patch);
}
