//! 事务管理实战示例 - ACID属性保证数据一致性
//!
//! 本示例展示PostgreSQL事务管理（对标Bun ORM事务）:
//! - BEGIN/COMMIT/ROLLBACK 事务控制
//! - ACID属性实战演示
//! - 错误回滚和异常处理
//! - errdefer自动清理
//! - 多表操作一致性保证
//!
//! 🎯 学习目标: 理解事务的重要性和正确使用方式
//!
//! 运行方式: zig build run-example -Dexample=transaction

const std = @import("std");
const zorm = @import("zorm");

const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    balance: i64, // 账户余额 (分)
    created_at: i64,

    pub const table_name = "users";
};

const TransferLog = struct {
    id: i64,
    from_user_id: i64,
    to_user_id: i64,
    amount: i64,
    created_at: i64,

    pub const table_name = "transfer_logs";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n╔════════════════════════════════════════════╗\n", .{});
    std.debug.print("║   💼 ZORM 事务管理实战 - ACID属性演示        ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════╝\n\n", .{});

    // 连接数据库
    var driver = try allocator.create(zorm.PostgresDriver);
    errdefer allocator.destroy(driver);

    driver.* = try zorm.PostgresDriver.connect(
        allocator,
        "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres",
    );
    defer driver.close() catch {};

    try initSchema(driver);

    const db = try createDB(allocator, driver);
    defer {
        db.deinit();
        allocator.destroy(driver);
    }

    std.debug.print("✓ 数据库连接成功\n\n", .{});

    // 准备测试环境
    try setupTables(db);

    // 示例 1: 成功的事务 (COMMIT)
    std.debug.print("💰 示例 1: 成功转账 (COMMIT)\n", .{});
    std.debug.print("═══════════════════════════════════════\n", .{});
    try example_successfulTransaction(db);
    std.debug.print("\n", .{});

    // 示例 2: 失败的事务 (ROLLBACK)
    std.debug.print("⚠️  示例 2: 余额不足回滚 (ROLLBACK)\n", .{});
    std.debug.print("═══════════════════════════════════════\n", .{});
    try example_rollbackTransaction(db);
    std.debug.print("\n", .{});

    // 示例 3: errdefer自动回滚
    std.debug.print("🛡️  示例 3: errdefer 自动回滚\n", .{});
    std.debug.print("═══════════════════════════════════════\n", .{});
    try example_errdefer(db);
    std.debug.print("\n", .{});

    std.debug.print("╔════════════════════════════════════════════╗\n", .{});
    std.debug.print("║   ✅ 事务管理示例完成！                      ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n📚 关键要点:\n", .{});
    std.debug.print("  1. 使用事务保证多操作的原子性\n", .{});
    std.debug.print("  2. 总是用 errdefer 确保错误时回滚\n", .{});
    std.debug.print("  3. 敏感操作（如转账）必须在事务中\n", .{});
    std.debug.print("  4. 事务隔离级别影响并发性能和一致性\n\n", .{});
}

fn initSchema(driver: *zorm.PostgresDriver) !void {
    _ = try driver.exec("DROP SCHEMA IF EXISTS zorm_examples CASCADE", &.{});
    _ = try driver.exec("CREATE SCHEMA zorm_examples", &.{});
    _ = try driver.exec("SET search_path TO zorm_examples", &.{});
}

fn createDB(allocator: std.mem.Allocator, driver: *zorm.PostgresDriver) !*zorm.DB(.postgresql) {
    const Adapter = struct {
        driver: *zorm.PostgresDriver,
        allocator: std.mem.Allocator,

        fn exec(ptr: *anyopaque, sql: []const u8, args: []const zorm.QueryArg) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            _ = try self.driver.exec(sql, args);
        }

        fn query(ptr: *anyopaque, sql: []const u8, args: []const zorm.QueryArg) anyerror!*zorm.core.Result {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            const rows = try self.driver.query(sql, args);

            const wrapper = try self.allocator.create(ResultWrapper);
            wrapper.* = .{ .allocator = self.allocator };

            const result_vtable = try self.allocator.create(zorm.core.Result.VTable);
            result_vtable.* = .{
                .next = ResultWrapper.next,
                .scan = ResultWrapper.scan,
                .close = ResultWrapper.close,
            };

            const result = try self.allocator.create(zorm.core.Result);
            result.* = .{ .ptr = wrapper, .vtable = result_vtable, .rows = rows };
            return result;
        }

        fn begin(_: *anyopaque) anyerror!*zorm.core.Tx {
            return error.NotImplemented;
        }

        fn close(ptr: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
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
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.allocator.destroy(self);
        }
    };

    const adapter = try allocator.create(Adapter);
    adapter.* = .{ .driver = driver, .allocator = allocator };

    const conn = zorm.core.Conn{
        .ptr = adapter,
        .vtable = &Adapter.vtable,
    };

    return try zorm.DB(.postgresql).init(allocator, conn, .{});
}

fn setupTables(db: *zorm.DB(.postgresql)) !void {
    try db.exec(
        \\CREATE TABLE IF NOT EXISTS users (
        \\    id SERIAL PRIMARY KEY,
        \\    name TEXT NOT NULL,
        \\    email TEXT UNIQUE NOT NULL,
        \\    balance BIGINT NOT NULL DEFAULT 0,
        \\    created_at BIGINT NOT NULL
        \\)
    , &.{});

    try db.exec(
        \\CREATE TABLE IF NOT EXISTS transfer_logs (
        \\    id SERIAL PRIMARY KEY,
        \\    from_user_id INTEGER NOT NULL REFERENCES users(id),
        \\    to_user_id INTEGER NOT NULL REFERENCES users(id),
        \\    amount BIGINT NOT NULL,
        \\    created_at BIGINT NOT NULL
        \\)
    , &.{});

    const now = std.time.timestamp();
    try db.exec("TRUNCATE TABLE transfer_logs, users RESTART IDENTITY CASCADE", &.{});

    try db.exec(
        \\INSERT INTO users (name, email, balance, created_at) VALUES
        \\  ('Alice', 'alice@example.com', 100000, $1),
        \\  ('Bob', 'bob@example.com', 50000, $1)
    , &[_]zorm.QueryArg{zorm.QueryArg.fromValue(now)});
}

/// 示例 1: 成功的转账事务
fn example_successfulTransaction(db: *zorm.DB(.postgresql)) !void {
    const now = std.time.timestamp();

    std.debug.print("  初始状态:\n", .{});
    try printBalances(db);

    std.debug.print("\n  开始转账: Alice → Bob, 金额: 20000 分 (¥200.00)\n", .{});

    // ===== 开启事务 =====
    try db.exec("BEGIN", &.{});
    errdefer db.exec("ROLLBACK", &.{}) catch {};

    // 步骤 1: 扣除 Alice 的余额
    try db.exec(
        "UPDATE users SET balance = balance - $1 WHERE name = 'Alice'",
        &[_]zorm.QueryArg{zorm.QueryArg.fromValue(@as(i64, 20000))},
    );
    std.debug.print("  ✓ 步骤 1: Alice 余额 -20000\n", .{});

    // 步骤 2: 增加 Bob 的余额
    try db.exec(
        "UPDATE users SET balance = balance + $1 WHERE name = 'Bob'",
        &[_]zorm.QueryArg{zorm.QueryArg.fromValue(@as(i64, 20000))},
    );
    std.debug.print("  ✓ 步骤 2: Bob 余额 +20000\n", .{});

    // 步骤 3: 记录转账日志
    try db.exec(
        "INSERT INTO transfer_logs (from_user_id, to_user_id, amount, created_at) VALUES (1, 2, $1, $2)",
        &[_]zorm.QueryArg{
            zorm.QueryArg.fromValue(@as(i64, 20000)),
            zorm.QueryArg.fromValue(now),
        },
    );
    std.debug.print("  ✓ 步骤 3: 转账日志已记录\n", .{});

    // ===== 提交事务 =====
    try db.exec("COMMIT", &.{});
    std.debug.print("  ✅ 事务已提交 (COMMIT)\n", .{});

    std.debug.print("\n  最终状态:\n", .{});
    try printBalances(db);
}

/// 示例 2: 余额不足导致回滚
fn example_rollbackTransaction(db: *zorm.DB(.postgresql)) !void {
    std.debug.print("  当前状态:\n", .{});
    try printBalances(db);

    std.debug.print("\n  尝试转账: Bob → Alice, 金额: 100000 分 (¥1000.00)\n", .{});
    std.debug.print("  (Bob 只有 70000 分余额)\n", .{});

    // ===== 开启事务 =====
    try db.exec("BEGIN", &.{});

    // 检查余额
    var result = try db.conn.query(
        "SELECT balance FROM users WHERE name = 'Bob'",
        &.{},
    );
    defer result.close();

    var bob_balance: i64 = 0;
    if (try result.rows.next()) |row| {
        bob_balance = try row.getInt(i64, 0);
    }

    const transfer_amount: i64 = 100000;
    if (bob_balance < transfer_amount) {
        std.debug.print("  ❌ 余额不足! Bob 余额: {d}, 需要: {d}\n", .{ bob_balance, transfer_amount });
        std.debug.print("  🔄 执行 ROLLBACK...\n", .{});

        try db.exec("ROLLBACK", &.{});
        std.debug.print("  ✓ 事务已回滚，数据未改变\n", .{});
    }

    std.debug.print("\n  回滚后状态:\n", .{});
    try printBalances(db);
}

/// 示例 3: errdefer自动回滚
fn example_errdefer(db: *zorm.DB(.postgresql)) !void {
    std.debug.print("  演示: 模拟业务逻辑错误时的自动回滚\n\n", .{});

    const result = transferWithValidation(db, 1, 2, 50000) catch |err| {
        std.debug.print("  ✓ 捕获错误: {}\n", .{err});
        std.debug.print("  ✓ errdefer 已自动执行 ROLLBACK\n", .{});
        return;
    };

    _ = result;
}

/// 带验证的转账函数
fn transferWithValidation(
    db: *zorm.DB(.postgresql),
    from_id: i64,
    to_id: i64,
    amount: i64,
) !void {
    try db.exec("BEGIN", &.{});
    errdefer db.exec("ROLLBACK", &.{}) catch {};

    // 模拟业务规则: 单笔转账不能超过 30000
    if (amount > 30000) {
        std.debug.print("  ❌ 业务规则错误: 单笔转账不能超过 ¥300.00\n", .{});
        return error.AmountExceedsLimit;
    }

    _ = from_id;
    _ = to_id;
    // 这里会触发错误,errdefer 自动回滚
}

/// 打印账户余额
fn printBalances(db: *zorm.DB(.postgresql)) !void {
    var result = try db.conn.query(
        "SELECT name, balance FROM users ORDER BY id",
        &.{},
    );
    defer result.close();

    while (try result.rows.next()) |row| {
        const name = try row.getString(0);
        const balance = try row.getInt(i64, 1);
        const yuan = @divTrunc(balance, 100);
        const fen = @mod(balance, 100);
        std.debug.print("    • {s}: {d} 分 (¥{d}.{d:0>2})\n", .{ name, balance, yuan, fen });
    }
}
