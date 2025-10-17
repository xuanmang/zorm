//! Transaction 集成测试
//!
//! 验证事务管理的 ACID 特性:
//! - Atomicity (原子性): 事务中的所有操作要么全部成功,要么全部失败
//! - Consistency (一致性): 事务执行前后数据库状态保持一致
//! - Isolation (隔离性): 并发事务之间互不干扰
//! - Durability (持久性): 已提交的事务永久保存

const std = @import("std");
const zorm = @import("zorm");
const PostgresDriver = zorm.PostgresDriver;
const QueryArg = zorm.QueryArg;
const DB = zorm.DB;
const Transaction = zorm.Transaction;

// 测试数据库连接配置
const TEST_DSN = "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres";

/// 辅助函数: 创建测试表
fn setupTestTable(driver: *PostgresDriver) !void {
    _ = try driver.exec(
        \\DROP TABLE IF EXISTS tx_test_users;
        \\CREATE TABLE tx_test_users (
        \\    id SERIAL PRIMARY KEY,
        \\    name TEXT NOT NULL,
        \\    balance INTEGER DEFAULT 0
        \\);
    , &.{});
}

/// 辅助函数: 获取表中的行数
fn countRows(driver: *PostgresDriver) !i64 {
    var rows = try driver.query("SELECT COUNT(*) FROM tx_test_users", &.{});
    defer rows.deinit();

    if (try rows.next()) |row| {
        return try row.getInt(i64, 0);
    }
    return 0;
}

/// 辅助函数: 获取用户余额
fn getBalance(driver: *PostgresDriver, name: []const u8) !i64 {
    const sql = "SELECT balance FROM tx_test_users WHERE name = $1";
    const args = [_]QueryArg{QueryArg.fromValue(name)};

    var rows = try driver.query(sql, &args);
    defer rows.deinit();

    if (try rows.next()) |row| {
        return try row.getInt(i64, 0);
    }
    return error.UserNotFound;
}

test "Transaction - 基本事务提交" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    try setupTestTable(&driver);

    // 创建 DB 实例
    var db = try DB(.postgresql).init(allocator, driver.asConn(), .{});
    defer db.deinit();

    // 开始事务
    var tx = try Transaction(.postgresql).begin(db);
    errdefer tx.rollback() catch {};

    // 在事务中插入数据
    try db.exec("INSERT INTO tx_test_users (name, balance) VALUES ($1, $2)", &[_][]const u8{ "Alice", "100" });

    // 提交事务
    try tx.commit();

    // 验证数据已提交
    const count = try countRows(&driver);
    try std.testing.expectEqual(@as(i64, 1), count);

    const balance = try getBalance(&driver, "Alice");
    try std.testing.expectEqual(@as(i64, 100), balance);
}

test "Transaction - 事务回滚 (验证原子性)" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    try setupTestTable(&driver);

    var db = try DB(.postgresql).init(allocator, driver.asConn(), .{});
    defer db.deinit();

    // 开始事务
    var tx = try Transaction(.postgresql).begin(db);

    // 在事务中插入数据
    try db.exec("INSERT INTO tx_test_users (name, balance) VALUES ($1, $2)", &[_][]const u8{ "Bob", "200" });

    // 主动回滚事务
    try tx.rollback();

    // 验证数据未提交 (回滚成功)
    const count = try countRows(&driver);
    try std.testing.expectEqual(@as(i64, 0), count);
}

test "Transaction - errdefer 自动回滚" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    try setupTestTable(&driver);

    var db = try DB(.postgresql).init(allocator, driver.asConn(), .{});
    defer db.deinit();

    // 模拟错误发生时的自动回滚
    const result = blk: {
        var tx = try Transaction(.postgresql).begin(db);
        errdefer tx.rollback() catch {};

        // 插入第一条数据
        try db.exec("INSERT INTO tx_test_users (name, balance) VALUES ($1, $2)", &[_][]const u8{ "Charlie", "300" });

        // 模拟错误
        break :blk error.SimulatedError;

        // 这里的代码不会执行
        // try tx.commit();
    };

    // 验证错误
    try std.testing.expectError(error.SimulatedError, result);

    // 验证数据已回滚
    const count = try countRows(&driver);
    try std.testing.expectEqual(@as(i64, 0), count);
}

test "Transaction - 保存点 (savepoint) 基本操作" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    try setupTestTable(&driver);

    var db = try DB(.postgresql).init(allocator, driver.asConn(), .{});
    defer db.deinit();

    var tx = try Transaction(.postgresql).begin(db);
    defer tx.rollback() catch {};

    // 插入第一条数据
    try db.exec("INSERT INTO tx_test_users (name, balance) VALUES ($1, $2)", &[_][]const u8{ "David", "400" });

    // 创建保存点
    try tx.savepoint("sp1");

    // 插入第二条数据
    try db.exec("INSERT INTO tx_test_users (name, balance) VALUES ($1, $2)", &[_][]const u8{ "Eve", "500" });

    // 回滚到保存点 (第二条数据应该被撤销)
    try tx.rollbackTo("sp1");

    // 提交事务
    try tx.commit();

    // 验证: 只有第一条数据存在
    const count = try countRows(&driver);
    try std.testing.expectEqual(@as(i64, 1), count);

    const balance = try getBalance(&driver, "David");
    try std.testing.expectEqual(@as(i64, 400), balance);

    // Eve 不应该存在
    const eve_result = getBalance(&driver, "Eve");
    try std.testing.expectError(error.UserNotFound, eve_result);
}

test "Transaction - 释放保存点 (releaseSavepoint)" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    try setupTestTable(&driver);

    var db = try DB(.postgresql).init(allocator, driver.asConn(), .{});
    defer db.deinit();

    var tx = try Transaction(.postgresql).begin(db);
    defer tx.rollback() catch {};

    // 插入第一条数据
    try db.exec("INSERT INTO tx_test_users (name, balance) VALUES ($1, $2)", &[_][]const u8{ "Frank", "600" });

    // 创建保存点
    try tx.savepoint("sp1");

    // 插入第二条数据
    try db.exec("INSERT INTO tx_test_users (name, balance) VALUES ($1, $2)", &[_][]const u8{ "Grace", "700" });

    // 释放保存点 (保留所有更改)
    try tx.releaseSavepoint("sp1");

    // 提交事务
    try tx.commit();

    // 验证: 两条数据都存在
    const count = try countRows(&driver);
    try std.testing.expectEqual(@as(i64, 2), count);

    const frank_balance = try getBalance(&driver, "Frank");
    try std.testing.expectEqual(@as(i64, 600), frank_balance);

    const grace_balance = try getBalance(&driver, "Grace");
    try std.testing.expectEqual(@as(i64, 700), grace_balance);
}

test "Transaction - withTransaction 辅助函数 (成功)" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    try setupTestTable(&driver);

    var db = try DB(.postgresql).init(allocator, driver.asConn(), .{});
    defer db.deinit();

    // 使用 withTransaction 自动管理事务
    const TestFn = struct {
        fn execute(d: *DB(.postgresql)) !void {
            try d.exec("INSERT INTO tx_test_users (name, balance) VALUES ($1, $2)", &[_][]const u8{ "Helen", "800" });
        }
    };

    try Transaction(.postgresql).withTransaction(db, TestFn.execute, .{db});

    // 验证数据已提交
    const count = try countRows(&driver);
    try std.testing.expectEqual(@as(i64, 1), count);

    const balance = try getBalance(&driver, "Helen");
    try std.testing.expectEqual(@as(i64, 800), balance);
}

test "Transaction - withTransaction 辅助函数 (失败自动回滚)" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    try setupTestTable(&driver);

    var db = try DB(.postgresql).init(allocator, driver.asConn(), .{});
    defer db.deinit();

    // 使用 withTransaction,模拟失败
    const TestFn = struct {
        fn execute(d: *DB(.postgresql)) !void {
            try d.exec("INSERT INTO tx_test_users (name, balance) VALUES ($1, $2)", &[_][]const u8{ "Ian", "900" });
            return error.SimulatedError; // 模拟错误
        }
    };

    const result = Transaction(.postgresql).withTransaction(db, TestFn.execute, .{db});
    try std.testing.expectError(error.SimulatedError, result);

    // 验证数据已回滚
    const count = try countRows(&driver);
    try std.testing.expectEqual(@as(i64, 0), count);
}

test "Transaction - 转账场景 (验证一致性)" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    try setupTestTable(&driver);

    // 初始化两个账户
    _ = try driver.exec(
        \\INSERT INTO tx_test_users (name, balance) VALUES ('Alice', 1000);
        \\INSERT INTO tx_test_users (name, balance) VALUES ('Bob', 500);
    , &.{});

    var db = try DB(.postgresql).init(allocator, driver.asConn(), .{});
    defer db.deinit();

    // 转账函数
    const TransferFn = struct {
        fn execute(d: *DB(.postgresql)) !void {
            // Alice 转 300 给 Bob
            try d.exec("UPDATE tx_test_users SET balance = balance - $1 WHERE name = $2", &[_][]const u8{ "300", "Alice" });
            try d.exec("UPDATE tx_test_users SET balance = balance + $1 WHERE name = $2", &[_][]const u8{ "300", "Bob" });
        }
    };

    // 执行转账
    try Transaction(.postgresql).withTransaction(db, TransferFn.execute, .{db});

    // 验证余额一致性
    const alice_balance = try getBalance(&driver, "Alice");
    const bob_balance = try getBalance(&driver, "Bob");

    try std.testing.expectEqual(@as(i64, 700), alice_balance);
    try std.testing.expectEqual(@as(i64, 800), bob_balance);

    // 总金额应该不变
    try std.testing.expectEqual(@as(i64, 1500), alice_balance + bob_balance);
}

test "Transaction - 清理测试数据" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    // 清理测试表
    _ = try driver.exec("DROP TABLE IF EXISTS tx_test_users", &.{});
}
