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

/// 测试 Schema 名称（基础名称，实际使用时会添加随机后缀）
const TEST_SCHEMA_BASE = "zorm_test";

/// 生成唯一的测试 Schema 名称
fn generateTestSchemaName(allocator: std.mem.Allocator) ![]const u8 {
    var rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random_id = rng.random().int(u32);
    return try std.fmt.allocPrint(allocator, "{s}_{x}", .{ TEST_SCHEMA_BASE, random_id });
}

/// 当前测试使用的 Schema 名称（向后兼容）
pub const TEST_SCHEMA = TEST_SCHEMA_BASE;

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

    // 生成唯一的测试 schema 名称
    const schema_name = try generateTestSchemaName(allocator);
    errdefer allocator.free(schema_name);

    // 初始化测试 schema
    try initTestSchema(driver, allocator, schema_name);

    // 创建 DB 实例 (使用适配器模式)
    const db = try createDBFromDriver(allocator, driver, schema_name);
    errdefer db.deinit();

    return db;
}

/// 清理测试数据库连接
///
/// 删除测试 schema 并关闭连接
pub fn cleanupTestDB(db: *zorm.DB(.postgresql)) !void {
    const allocator = db.allocator;

    // 获取底层 driver 和 adapter（在 db.deinit() 之前保存）
    const adapter: *DriverConnAdapter = @ptrCast(@alignCast(db.conn.ptr));
    const driver = adapter.driver;
    const schema_name = adapter.schema_name;

    // 删除测试 schema
    try dropTestSchema(driver, allocator, schema_name);

    // 释放 schema_name
    allocator.free(schema_name);

    // 关闭并释放 DB（会调用 conn.close() 但不会释放 adapter）
    db.deinit();

    // 释放 adapter（DriverConnAdapter 本身）
    allocator.destroy(adapter);

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
fn initTestSchema(driver: *zorm.PostgresDriver, allocator: std.mem.Allocator, schema_name: []const u8) !void {
    // 删除旧 schema (CASCADE 删除所有表和数据)
    const drop_sql = try std.fmt.allocPrint(allocator, "DROP SCHEMA IF EXISTS {s} CASCADE", .{schema_name});
    defer allocator.free(drop_sql);
    _ = try driver.exec(drop_sql, &.{});

    // 创建新 schema
    const create_sql = try std.fmt.allocPrint(allocator, "CREATE SCHEMA {s}", .{schema_name});
    defer allocator.free(create_sql);
    _ = try driver.exec(create_sql, &.{});

    // 设置 search_path
    const set_path_sql = try std.fmt.allocPrint(allocator, "SET search_path TO {s}, public", .{schema_name});
    defer allocator.free(set_path_sql);
    _ = try driver.exec(set_path_sql, &.{});
}

/// 删除测试 Schema
fn dropTestSchema(driver: *zorm.PostgresDriver, allocator: std.mem.Allocator, schema_name: []const u8) !void {
    const drop_sql = try std.fmt.allocPrint(allocator, "DROP SCHEMA IF EXISTS {s} CASCADE", .{schema_name});
    defer allocator.free(drop_sql);
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
            []const u8 => {
                // 字符串需要复制，因为 result.close() 会释放内存
                const str = try row.getString(0);
                return try db.allocator.dupe(u8, str);
            },
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
    schema_name: []const u8,

    fn exec(ptr: *anyopaque, query_str: []const u8, args: []const zorm.QueryArg) anyerror!void {
        const self: *DriverConnAdapter = @ptrCast(@alignCast(ptr));
        _ = try self.driver.exec(query_str, args);
    }

    fn query(ptr: *anyopaque, query_str: []const u8, args: []const zorm.QueryArg) anyerror!*zorm.core.Result {
        const self: *DriverConnAdapter = @ptrCast(@alignCast(ptr));
        const rows = try self.driver.query(query_str, args);

        // 创建 Result VTable
        const result_vtable = try self.allocator.create(zorm.core.Result.VTable);
        errdefer self.allocator.destroy(result_vtable);

        result_vtable.* = .{
            .next = ResultWrapper.next,
            .scan = ResultWrapper.scan,
            .close = ResultWrapper.close,
        };

        // 创建 Result 接口
        const result = try self.allocator.create(zorm.core.Result);
        errdefer self.allocator.destroy(result);

        // 创建 ResultWrapper（持有 result 和 vtable 指针以便在 close 时释放）
        const wrapper = try self.allocator.create(ResultWrapper);
        errdefer self.allocator.destroy(wrapper);

        wrapper.* = .{
            .allocator = self.allocator,
            .result = result,
            .vtable = result_vtable,
        };

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
    result: *zorm.core.Result, // 持有 Result 指针以便释放
    vtable: *zorm.core.Result.VTable, // 持有 VTable 指针以便释放

    fn next(_: *anyopaque) anyerror!bool {
        return error.NotImplemented;
    }

    fn scan(_: *anyopaque, _: [][]u8) anyerror!void {
        return error.NotImplemented;
    }

    fn close(ptr: *anyopaque) void {
        const self: *ResultWrapper = @ptrCast(@alignCast(ptr));
        const allocator = self.allocator;
        const result = self.result;
        const vtable = self.vtable;

        // 释放 wrapper 自身
        allocator.destroy(self);

        // 释放 VTable
        allocator.destroy(vtable);

        // 释放 Result
        allocator.destroy(result);
    }
};

/// 从 Driver 创建 DB 实例
fn createDBFromDriver(allocator: std.mem.Allocator, driver: *zorm.PostgresDriver, schema_name: []const u8) !*zorm.DB(.postgresql) {
    const adapter = try allocator.create(DriverConnAdapter);
    errdefer allocator.destroy(adapter);

    adapter.* = .{
        .driver = driver,
        .allocator = allocator,
        .schema_name = schema_name,
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
/// 测试用户模型
pub const TestUser = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: ?i32,
    created_at: i64,
    updated_at: i64,

    pub const table_name = "test_users";

    /// Schema 配置
    pub const schema = .{
        .id = .{ .primary_key = true, .auto_increment = true },
        .email = .{ .unique = true },
    };
};

/// 测试文章模型
/// 测试文章模型
pub const TestPost = struct {
    id: i64,
    user_id: i64,
    title: []const u8,
    content: []const u8,
    published: bool,
    created_at: i64,

    pub const table_name = "test_posts";

    /// Schema 配置
    pub const schema = .{
        .id = .{ .primary_key = true, .auto_increment = true },
    };
};
