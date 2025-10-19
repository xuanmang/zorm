//! Transaction Isolation Level 集成测试 (Story 2.5)
//!
//! 测试 PostgreSQL 事务隔离级别的实际行为:
//! - 验证默认隔离级别 (READ COMMITTED)
//! - 验证 REPEATABLE READ 隔离级别
//! - 验证 SERIALIZABLE 隔离级别
//! - 验证 PostgreSQL 实际使用的隔离级别设置
//!
//! 运行条件:
//! - 需要 PostgreSQL 14+ 数据库
//! - DSN: host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres

const std = @import("std");
const zorm = @import("zorm");
const PostgresDriver = zorm.PostgresDriver;
const DB = zorm.DB;
const QueryArg = zorm.QueryArg;
const IsolationLevel = zorm.IsolationLevel;
const TxOptions = zorm.TxOptions;
const Error = zorm.Error;

// 测试数据库连接配置
const TEST_DSN = "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres";

/// 辅助函数: 创建测试表
fn setupTestTable(driver: *PostgresDriver) !void {
    _ = try driver.exec(
        \\DROP TABLE IF EXISTS isolation_test_users;
        \\CREATE TABLE isolation_test_users (
        \\    id SERIAL PRIMARY KEY,
        \\    name TEXT NOT NULL,
        \\    value INTEGER DEFAULT 0
        \\);
    , &.{});

    // 插入测试数据
    _ = try driver.exec(
        \\INSERT INTO isolation_test_users (name, value) VALUES
        \\('user1', 100),
        \\('user2', 200);
    , &.{});
}

/// 辅助函数: 清理测试表
fn cleanupTestTable(driver: *PostgresDriver) !void {
    _ = try driver.exec("DROP TABLE IF EXISTS isolation_test_users", &.{});
}

/// 辅助函数: 获取当前事务的隔离级别
fn getCurrentIsolationLevel(driver: *PostgresDriver, allocator: std.mem.Allocator) ![]const u8 {
    var rows = try driver.query("SELECT current_setting('transaction_isolation')", &.{});
    defer rows.deinit();

    if (try rows.next()) |row| {
        const level = try row.getString(0);
        // 需要复制字符串,因为 row 会被释放
        return try allocator.dupe(u8, level);
    }
    return error.NoIsolationLevel;
}

/// 辅助函数: 获取用户值
fn getUserValue(driver: *PostgresDriver, name: []const u8) !i64 {
    const sql = "SELECT value FROM isolation_test_users WHERE name = $1";
    const args = [_]QueryArg{QueryArg.fromValue(name)};

    var rows = try driver.query(sql, &args);
    defer rows.deinit();

    if (try rows.next()) |row| {
        return try row.getInt(i64, 0);
    }
    return error.UserNotFound;
}

// ============================================
// 测试: 验证隔离级别设置 (AC2.5.4)
// ============================================

test "IsolationLevel: 默认隔离级别应为 READ COMMITTED" {
    const allocator = std.testing.allocator;

    // 连接数据库
    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    try setupTestTable(&driver);
    defer cleanupTestTable(&driver) catch {};

    // 创建 DB 实例
    var db = DB(.postgresql).init(allocator, driver.asConn(), .{});
    defer db.deinit();

    // 开始事务（不指定隔离级别,使用默认值）
    var tx = try db.beginTx(.{});
    defer tx.deinit();

    // 查询当前隔离级别（使用 driver 直接查询）
    const level = try getCurrentIsolationLevel(&driver, allocator);
    defer allocator.free(level);

    // PostgreSQL 默认隔离级别应为 "read committed"
    try std.testing.expectEqualStrings("read committed", level);
}

test "IsolationLevel: 显式设置 READ COMMITTED" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    try setupTestTable(&driver);
    defer cleanupTestTable(&driver) catch {};

    // 创建 DB 实例
    var db = DB(.postgresql).init(allocator, driver.asConn(), .{});
    defer db.deinit();

    // 开始事务并显式设置 READ COMMITTED 隔离级别
    var tx = try db.beginTx(.{ .isolation_level = .read_committed });
    defer tx.deinit();

    // 验证隔离级别
    const level = try getCurrentIsolationLevel(&driver, allocator);
    defer allocator.free(level);

    try std.testing.expectEqualStrings("read committed", level);
}

test "IsolationLevel: 设置 REPEATABLE READ" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    try setupTestTable(&driver);
    defer cleanupTestTable(&driver) catch {};

    // 创建 DB 实例
    var db = DB(.postgresql).init(allocator, driver.asConn(), .{});
    defer db.deinit();

    // 使用 TxOptions 设置 REPEATABLE READ 隔离级别
    var tx = try db.beginTx(.{ .isolation_level = .repeatable_read });
    defer tx.deinit();

    const level = try getCurrentIsolationLevel(&driver, allocator);
    defer allocator.free(level);

    try std.testing.expectEqualStrings("repeatable read", level);
}

test "IsolationLevel: 设置 SERIALIZABLE" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    try setupTestTable(&driver);
    defer cleanupTestTable(&driver) catch {};

    // 创建 DB 实例
    var db = DB(.postgresql).init(allocator, driver.asConn(), .{});
    defer db.deinit();

    // 使用 TxOptions 设置 SERIALIZABLE 隔离级别
    var tx = try db.beginTx(.{ .isolation_level = .serializable });
    defer tx.deinit();

    const level = try getCurrentIsolationLevel(&driver, allocator);
    defer allocator.free(level);

    try std.testing.expectEqualStrings("serializable", level);
}

test "IsolationLevel: 设置 READ UNCOMMITTED 自动升级为 READ COMMITTED" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    try setupTestTable(&driver);
    defer cleanupTestTable(&driver) catch {};

    // 创建 DB 实例
    var db = DB(.postgresql).init(allocator, driver.asConn(), .{});
    defer db.deinit();

    // PostgreSQL 不支持 READ UNCOMMITTED,会自动升级为 READ COMMITTED
    var tx = try db.beginTx(.{ .isolation_level = .read_uncommitted });
    defer tx.deinit();

    const level = try getCurrentIsolationLevel(&driver, allocator);
    defer allocator.free(level);

    // PostgreSQL 会将 READ UNCOMMITTED 升级为 READ COMMITTED
    try std.testing.expectEqualStrings("read committed", level);
}

// ============================================
// 测试: IsolationLevel.toSQL() 方法 (AC2.5.4)
// ============================================

test "IsolationLevel: toSQL() 转换正确性" {
    try std.testing.expectEqualStrings("READ UNCOMMITTED", IsolationLevel.read_uncommitted.toSQL());
    try std.testing.expectEqualStrings("READ COMMITTED", IsolationLevel.read_committed.toSQL());
    try std.testing.expectEqualStrings("REPEATABLE READ", IsolationLevel.repeatable_read.toSQL());
    try std.testing.expectEqualStrings("SERIALIZABLE", IsolationLevel.serializable.toSQL());
}

// ============================================
// 测试: 隔离级别实际行为验证
// ============================================

test "IsolationLevel: READ COMMITTED 允许不可重复读" {
    const allocator = std.testing.allocator;

    // 连接 1: 主事务
    var driver1 = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver1.close() catch {};

    // 连接 2: 并发事务
    var driver2 = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver2.close() catch {};

    try setupTestTable(&driver1);
    defer cleanupTestTable(&driver1) catch {};

    // 创建 DB 实例 1
    var db1 = DB(.postgresql).init(allocator, driver1.asConn(), .{});
    defer db1.deinit();

    // 创建 DB 实例 2
    var db2 = DB(.postgresql).init(allocator, driver2.asConn(), .{});
    defer db2.deinit();

    // 事务 1: READ COMMITTED
    var tx1 = try db1.beginTx(.{ .isolation_level = .read_committed });
    defer tx1.deinit();

    // 第一次读取
    const value1 = try getUserValue(&driver1, "user1");
    try std.testing.expectEqual(@as(i64, 100), value1);

    // 事务 2: 修改数据并提交
    var tx2 = try db2.beginTx(.{});
    _ = try driver2.exec("UPDATE isolation_test_users SET value = 150 WHERE name = 'user1'", &.{});
    try tx2.commit();

    // 事务 1: 第二次读取（READ COMMITTED 会看到已提交的修改）
    const value2 = try getUserValue(&driver1, "user1");
    try std.testing.expectEqual(@as(i64, 150), value2);

    // 验证：两次读取结果不同（不可重复读）
    try std.testing.expect(value1 != value2);
}

test "IsolationLevel: REPEATABLE READ 防止不可重复读" {
    const allocator = std.testing.allocator;

    var driver1 = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver1.close() catch {};

    var driver2 = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver2.close() catch {};

    try setupTestTable(&driver1);
    defer cleanupTestTable(&driver1) catch {};

    // 创建 DB 实例
    var db1 = DB(.postgresql).init(allocator, driver1.asConn(), .{});
    defer db1.deinit();

    var db2 = DB(.postgresql).init(allocator, driver2.asConn(), .{});
    defer db2.deinit();

    // 事务 1: REPEATABLE READ
    var tx1 = try db1.beginTx(.{ .isolation_level = .repeatable_read });
    defer tx1.deinit();

    // 第一次读取
    const value1 = try getUserValue(&driver1, "user1");
    try std.testing.expectEqual(@as(i64, 100), value1);

    // 事务 2: 修改数据并提交
    var tx2 = try db2.beginTx(.{});
    _ = try driver2.exec("UPDATE isolation_test_users SET value = 150 WHERE name = 'user1'", &.{});
    try tx2.commit();

    // 事务 1: 第二次读取（REPEATABLE READ 仍然看到事务开始时的快照）
    const value2 = try getUserValue(&driver1, "user1");
    try std.testing.expectEqual(@as(i64, 100), value2);

    // 验证：两次读取结果相同（可重复读）
    try std.testing.expectEqual(value1, value2);
}

test "IsolationLevel: SERIALIZABLE 完全隔离" {
    const allocator = std.testing.allocator;

    var driver1 = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver1.close() catch {};

    var driver2 = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver2.close() catch {};

    try setupTestTable(&driver1);
    defer cleanupTestTable(&driver1) catch {};

    // 创建 DB 实例
    var db1 = DB(.postgresql).init(allocator, driver1.asConn(), .{});
    defer db1.deinit();

    var db2 = DB(.postgresql).init(allocator, driver2.asConn(), .{});
    defer db2.deinit();

    // 事务 1: SERIALIZABLE
    var tx1 = try db1.beginTx(.{ .isolation_level = .serializable });
    defer tx1.deinit();

    // 读取初始值
    const value1 = try getUserValue(&driver1, "user1");
    try std.testing.expectEqual(@as(i64, 100), value1);

    // 事务 2: 修改数据并提交
    var tx2 = try db2.beginTx(.{});
    _ = try driver2.exec("UPDATE isolation_test_users SET value = 150 WHERE name = 'user1'", &.{});
    try tx2.commit();

    // 事务 1: 再次读取（SERIALIZABLE 看到事务开始时的快照）
    const value2 = try getUserValue(&driver1, "user1");
    try std.testing.expectEqual(@as(i64, 100), value2);

    // 验证：保持一致性快照
    try std.testing.expectEqual(value1, value2);
}
