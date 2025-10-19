//! 测试辅助工具
//!
//! 提供统一的测试数据库管理功能:
//! - 数据库连接和清理
//! - 测试表创建和删除
//! - 测试数据准备和清理
//! - 测试环境隔离

const std = @import("std");
const zorm = @import("zorm");

// ============================================
// 测试数据库配置
// ============================================

/// 测试数据库连接字符串
pub const TEST_DSN = "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres";

/// 测试 Schema 名称
pub const TEST_SCHEMA = "zorm_test";

/// 测试超时时间 (毫秒)
pub const TEST_TIMEOUT_MS = 30_000;

// ============================================
// 数据库连接管理
// ============================================

/// 创建测试数据库连接
///
/// 自动初始化测试 schema 并设置 search_path
///
/// ## 使用方式
/// ```zig
/// const allocator = std.testing.allocator;
/// var db = try test_helper.setupTestDB(allocator);
/// defer test_helper.cleanupTestDB(db) catch {};
///
/// // 执行测试...
/// ```
pub fn setupTestDB(allocator: std.mem.Allocator) !*zorm.DB(.postgresql) {
    var driver = try allocator.create(zorm.PostgresDriver);
    errdefer allocator.destroy(driver);

    driver.* = try zorm.PostgresDriver.connect(allocator, TEST_DSN);
    errdefer driver.close() catch {};

    // 初始化测试 schema
    try initTestSchema(driver);

    // 创建 DB 实例 (使用适配器模式)
    const db = try createDBFromDriver(allocator, driver);
    errdefer db.deinit();

    return db;
}

/// 清理测试数据库连接
///
/// 删除测试 schema 并关闭连接
pub fn cleanupTestDB(db: *zorm.DB(.postgresql)) !void {
    const allocator = db.allocator;

    // 获取底层 driver
    const adapter: *DriverConnAdapter = @ptrCast(@alignCast(db.conn.ptr));
    const driver = adapter.driver;

    // 删除测试 schema
    try dropTestSchema(driver);

    // 关闭连接
    db.deinit();

    // 释放 driver 内存
    allocator.destroy(driver);
}

/// 创建测试 PostgreSQL 驱动
pub fn createTestDriver(allocator: std.mem.Allocator) !*zorm.PostgresDriver {
    const driver = try allocator.create(zorm.PostgresDriver);
    errdefer allocator.destroy(driver);

    driver.* = try zorm.PostgresDriver.connect(allocator, TEST_DSN);
    return driver;
}

/// 销毁测试驱动
pub fn destroyTestDriver(allocator: std.mem.Allocator, driver: *zorm.PostgresDriver) void {
    driver.close() catch {};
    allocator.destroy(driver);
}

// ============================================
// Schema 管理
// ============================================

/// 初始化测试 Schema
///
/// 删除旧的测试 schema 并创建新的
fn initTestSchema(driver: *zorm.PostgresDriver) !void {
    // 删除旧 schema (CASCADE 删除所有表和数据)
    const drop_sql = "DROP SCHEMA IF EXISTS " ++ TEST_SCHEMA ++ " CASCADE";
    _ = try driver.exec(drop_sql, &.{});

    // 创建新 schema
    const create_sql = "CREATE SCHEMA " ++ TEST_SCHEMA;
    _ = try driver.exec(create_sql, &.{});

    // 设置 search_path
    const set_path_sql = "SET search_path TO " ++ TEST_SCHEMA ++ ", public";
    _ = try driver.exec(set_path_sql, &.{});
}

/// 删除测试 Schema
fn dropTestSchema(driver: *zorm.PostgresDriver) !void {
    const drop_sql = "DROP SCHEMA IF EXISTS " ++ TEST_SCHEMA ++ " CASCADE";
    _ = try driver.exec(drop_sql, &.{});
}

// ============================================
// 表管理
// ============================================

/// 创建测试表
///
/// 根据模型类型自动推断表结构并创建
///
/// ## 参数
/// - db: 数据库实例
/// - T: 模型类型
///
/// ## 示例
/// ```zig
/// const User = struct {
///     id: i64,
///     name: []const u8,
///     email: []const u8,
///     pub const table_name = "users";
/// };
///
/// try test_helper.createTestTable(db, User);
/// ```
pub fn createTestTable(db: *zorm.DB(.postgresql), comptime T: type) !void {
    var query = try db.newCreateTable(T);
    defer query.deinit();

    try query.ifNotExists().exec();
}

/// 删除测试表
///
/// ## 参数
/// - db: 数据库实例
/// - table_name: 表名
pub fn dropTestTable(db: *zorm.DB(.postgresql), table_name: []const u8) !void {
    const sql = try std.fmt.allocPrint(
        db.allocator,
        "DROP TABLE IF EXISTS {s} CASCADE",
        .{table_name},
    );
    defer db.allocator.free(sql);

    try db.exec(sql, &.{});
}

/// 清空测试表数据
///
/// 使用 TRUNCATE 快速清空表,并重置自增序列
///
/// ## 参数
/// - db: 数据库实例
/// - table_name: 表名
pub fn truncateTable(db: *zorm.DB(.postgresql), table_name: []const u8) !void {
    const sql = try std.fmt.allocPrint(
        db.allocator,
        "TRUNCATE TABLE {s} RESTART IDENTITY CASCADE",
        .{table_name},
    );
    defer db.allocator.free(sql);

    try db.exec(sql, &.{});
}

/// 检查表是否存在
pub fn tableExists(db: *zorm.DB(.postgresql), table_name: []const u8) !bool {
    const sql =
        \\SELECT EXISTS (
        \\    SELECT 1 FROM information_schema.tables
        \\    WHERE table_schema = $1 AND table_name = $2
        \\)
    ;

    const args = [_]zorm.QueryArg{
        zorm.QueryArg.fromValue(TEST_SCHEMA),
        zorm.QueryArg.fromValue(table_name),
    };

    var result = try db.conn.query(sql, &args);
    defer result.close();

    if (try result.rows.next()) |row| {
        return try row.getBool(0);
    }

    return false;
}

// ============================================
// 数据管理
// ============================================

/// 获取表中的行数
pub fn countRows(db: *zorm.DB(.postgresql), table_name: []const u8) !i64 {
    const sql = try std.fmt.allocPrint(
        db.allocator,
        "SELECT COUNT(*) FROM {s}",
        .{table_name},
    );
    defer db.allocator.free(sql);

    var result = try db.conn.query(sql, &.{});
    defer result.close();

    if (try result.rows.next()) |row| {
        return try row.getInt(i64, 0);
    }

    return 0;
}

/// 执行原始 SQL (用于测试验证)
pub fn execSQL(db: *zorm.DB(.postgresql), sql: []const u8) !void {
    try db.exec(sql, &.{});
}

/// 查询单个值 (用于测试验证)
pub fn queryScalar(
    db: *zorm.DB(.postgresql),
    comptime T: type,
    sql: []const u8,
    args: []const zorm.QueryArg,
) !T {
    var result = try db.conn.query(sql, args);
    defer result.close();

    if (try result.rows.next()) |row| {
        return switch (T) {
            i64, i32 => try row.getInt(T, 0),
            []const u8 => try row.getString(0),
            bool => try row.getBool(0),
            f64 => try row.getFloat(f64, 0),
            else => @compileError("Unsupported scalar type: " ++ @typeName(T)),
        };
    }

    return error.NoRows;
}

// ============================================
// 内部辅助函数
// ============================================

/// Driver 到 Conn 的适配器
const DriverConnAdapter = struct {
    driver: *zorm.PostgresDriver,
    allocator: std.mem.Allocator,

    fn exec(ptr: *anyopaque, query_str: []const u8, args: []const zorm.QueryArg) anyerror!void {
        const self: *DriverConnAdapter = @ptrCast(@alignCast(ptr));
        _ = try self.driver.exec(query_str, args);
    }

    fn query(ptr: *anyopaque, query_str: []const u8, args: []const zorm.QueryArg) anyerror!*zorm.core.Result {
        const self: *DriverConnAdapter = @ptrCast(@alignCast(ptr));
        const rows = try self.driver.query(query_str, args);

        // 创建 ResultWrapper
        const wrapper = try self.allocator.create(ResultWrapper);
        wrapper.* = .{ .allocator = self.allocator };

        // 创建 Result VTable
        const result_vtable = try self.allocator.create(zorm.core.Result.VTable);
        result_vtable.* = .{
            .next = ResultWrapper.next,
            .scan = ResultWrapper.scan,
            .close = ResultWrapper.close,
        };

        // 创建 Result 接口
        const result = try self.allocator.create(zorm.core.Result);
        result.* = .{
            .ptr = wrapper,
            .vtable = result_vtable,
            .rows = rows,
        };
        return result;
    }

    fn begin(ptr: *anyopaque) anyerror!*zorm.core.Tx {
        _ = ptr;
        return error.NotImplemented;
    }

    fn close(ptr: *anyopaque) void {
        const self: *DriverConnAdapter = @ptrCast(@alignCast(ptr));
        self.driver.close() catch {};
    }

    const vtable = zorm.core.Conn.VTable{
        .exec = exec,
        .query = query,
        .begin = begin,
        .close = close,
    };
};

const ResultWrapper = struct {
    allocator: std.mem.Allocator,

    fn next(_: *anyopaque) anyerror!bool {
        return error.NotImplemented;
    }

    fn scan(_: *anyopaque, _: [][]u8) anyerror!void {
        return error.NotImplemented;
    }

    fn close(ptr: *anyopaque) void {
        const self: *ResultWrapper = @ptrCast(@alignCast(ptr));
        self.allocator.destroy(self);
    }
};

/// 从 Driver 创建 DB 实例
fn createDBFromDriver(allocator: std.mem.Allocator, driver: *zorm.PostgresDriver) !*zorm.DB(.postgresql) {
    const adapter = try allocator.create(DriverConnAdapter);
    errdefer allocator.destroy(adapter);

    adapter.* = .{
        .driver = driver,
        .allocator = allocator,
    };

    const conn = zorm.core.Conn{
        .ptr = adapter,
        .vtable = &DriverConnAdapter.vtable,
    };

    return try zorm.DB(.postgresql).init(allocator, conn, .{});
}

// ============================================
// 常用测试模型
// ============================================

/// 测试用户模型
pub const TestUser = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: ?i32,
    created_at: i64,
    updated_at: i64,

    pub const table_name = "test_users";
};

/// 测试文章模型
pub const TestPost = struct {
    id: i64,
    user_id: i64,
    title: []const u8,
    content: []const u8,
    published: bool,
    created_at: i64,

    pub const table_name = "test_posts";
};
