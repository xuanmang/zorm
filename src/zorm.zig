//! ZORM - SQL-first ORM for Zig
//!
//! ZORM 是一个受 Bun ORM 启发,专为 Zig 语言设计的 SQL-first ORM 库。
//! 核心特性:
//! - 显式内存管理,使用 Allocator 模式
//! - comptime 泛型和零开销抽象
//! - 类型安全的查询构建器
//! - PostgreSQL 专用优化
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
pub const types = @import("core/types.zig");
pub const dialect = @import("dialect/dialect.zig");
pub const sql = @import("dialect/sql.zig");
pub const query = @import("query/query.zig");
pub const config = @import("config/db_config.zig");
pub const schema = struct {
    pub const ColumnType = @import("schema/schema.zig").ColumnType;
    pub const TableMeta = @import("schema/schema.zig").TableMeta;
    pub const ColumnMeta = @import("schema/schema.zig").ColumnMeta;
    pub const getTableMeta = @import("schema/schema.zig").getTableMeta;
    pub const Table = @import("schema/table.zig").Table;
    pub const Column = @import("schema/table.zig").Column;
    pub const Index = @import("schema/index.zig").Index;
    pub const IndexMethod = @import("schema/index.zig").IndexMethod;
    pub const Migration = @import("schema/migration.zig").Migration;
    pub const MigrationManager = @import("schema/migration.zig").MigrationManager;
    pub const Direction = @import("schema/migration.zig").Direction;
    pub const MigrationStatus = @import("schema/migration.zig").MigrationStatus;
    // Story 3.2: Schema Field Customization
    pub const FieldSchema = @import("schema/schema.zig").FieldSchema;
    pub const hasSchemaConfig = @import("schema/schema.zig").hasSchemaConfig;
    pub const getFieldSchema = @import("schema/schema.zig").getFieldSchema;
    pub const generateColumnDefinition = @import("schema/schema.zig").generateColumnDefinition;
    pub const generateColumnDefinitions = @import("schema/schema.zig").generateColumnDefinitions;
    // Story 3.5: DROP INDEX Query API
    pub const DropIndexQuery = @import("schema/schema.zig").DropIndexQuery;
};

// Reflection utilities for CREATE TABLE API
pub const reflection = @import("schema/reflection.zig");
pub const driver = struct {
    pub const postgres = @import("driver/postgres.zig");
    pub const connection = @import("driver/connection.zig");
    pub const pool = @import("driver/pool.zig");
};

// 导出 Mapper 模块
pub const mapper = struct {
    pub const type_info = @import("mapper/type_info.zig");
    pub const field_mapper = @import("mapper/field_mapper.zig");
    pub const result_scanner = @import("mapper/result_scanner.zig");
};

// 导出 Reflect 模块
pub const reflect = struct {
    pub const comptime_utils = @import("reflect/comptime_utils.zig");

    // 导出常用 comptime 函数（便于直接使用）
    pub const getTableName = comptime_utils.getTableName;
    pub const inferSQLType = comptime_utils.inferSQLType;
    pub const isOptional = comptime_utils.isOptional;
    pub const isPrimaryKeyField = comptime_utils.isPrimaryKeyField;
    pub const isTimestampField = comptime_utils.isTimestampField;
    pub const isForeignKeyField = comptime_utils.isForeignKeyField;
    pub const inferForeignKeyTable = comptime_utils.inferForeignKeyTable;
    pub const getDefaultValue = comptime_utils.getDefaultValue;
    pub const getCheckConstraint = comptime_utils.getCheckConstraint;
    pub const isUniqueField = comptime_utils.isUniqueField;
    pub const isAutoIncrementField = comptime_utils.isAutoIncrementField;
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

// 导出便捷 API
/// 简化的 PostgreSQL 连接函数 - 一行代码连接数据库
///
/// 示例:
/// ```zig
/// const db = try zorm.connect(allocator, "host=127.0.0.1 port=5432 user=pguser password=xxx dbname=mydb");
/// defer db.deinit();
/// ```
pub const connect = @import("convenience.zig").connect;

// 导出常用类型
pub const DB = core.DB;
pub const DBOptions = core.DBOptions;
pub const Transaction = transaction.Transaction;
pub const TransactionError = transaction.TransactionError;
// Story 2.4: 新事务管理系统
pub const TxOptions = core.TxOptions;
pub const TxManager = core.TxManager;
// Story 2.5: 事务隔离级别
pub const IsolationLevel = @import("core/types.zig").IsolationLevel;
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
pub const InsertResult = @import("types.zig").InsertResult; // Story 1.4
pub const UpdateQuery = query.UpdateQuery;
pub const UpdateResult = @import("types.zig").UpdateResult; // Story 2.1
pub const DeleteResult = @import("types.zig").DeleteResult; // Story 2.3
pub const DeleteQuery = query.DeleteQuery;
pub const CreateTableQuery = query.CreateTableQuery;
// Story 3.3 & 3.4: DROP TABLE & CREATE INDEX Query Builders
pub const DropTableQuery = query.DropTableQuery;
pub const CreateIndexQuery = query.CreateIndexQuery;
pub const DropIndexQuery = query.DropIndexQuery;
// Story 2.6: Raw SQL Query Support
pub const RawQuery = query.RawQuery;
pub const RawResult = @import("types.zig").RawResult;

// 导出 Mapper 类型和函数
pub const ScanOptions = mapper.result_scanner.ScanOptions;
pub const scanAll = mapper.result_scanner.scanAll;
pub const scanOne = mapper.result_scanner.scanOne;
pub const scanRow = mapper.field_mapper.scanRow;

// 导出 Schema 类型
pub const Table = schema.Table;
pub const Column = schema.Column;
pub const ColumnType = schema.ColumnType;
pub const Index = schema.Index;
pub const IndexMethod = schema.IndexMethod;
pub const Migration = schema.Migration;
pub const MigrationManager = schema.MigrationManager;
pub const Direction = schema.Direction;
pub const MigrationStatus = schema.MigrationStatus;

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
    // 显式引用所有子模块的测试
    _ = @import("reflect/comptime_utils.zig");
    _ = @import("core/types.zig");
}

test "version" {
    try std.testing.expectEqual(0, version.major);
    try std.testing.expectEqual(1, version.minor);
    try std.testing.expectEqual(0, version.patch);
}
