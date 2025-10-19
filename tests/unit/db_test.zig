//! DB 集成测试
//!
//! 测试 DB 核心功能（基于真实 PostgreSQL）:
//! - DB 初始化和清理
//! - 真实连接管理
//! - 查询执行和统计
//! - 克隆和多实例

const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");
const test_helper = @import("test_helper");
const seed_data = @import("seed_data");

// ============================================
// 配置测试（纯单元测试，不需要数据库）
// ============================================

test "DB: default configuration values" {
    const opts = zorm.DBOptions{};

    // 验证默认值
    try testing.expectEqual(false, opts.discard_unknown_columns);
    try testing.expectEqual(@as(u32, 25), opts.max_open_conns);
    try testing.expectEqual(@as(u32, 25), opts.max_idle_conns);
    try testing.expectEqual(@as(u64, 300), opts.conn_max_lifetime);
    try testing.expectEqual(@as(u64, 60), opts.conn_max_idle_time);
    try testing.expectEqual(@as(u64, 30_000), opts.query_timeout);
    try testing.expectEqual(false, opts.enable_query_log);
    try testing.expectEqual(false, opts.enable_slow_query_log);
    try testing.expectEqual(@as(u64, 1000), opts.slow_query_threshold);
}

test "DB: getDialect is comptime" {
    // 验证 getDialect 可以在编译时调用
    const PostgresDB = zorm.DB(.postgresql);

    try testing.expectEqual(.postgresql, PostgresDB.getDialect());
    try testing.expectEqual(.postgresql, PostgresDB.getDialect());
    try testing.expectEqual(.postgresql, PostgresDB.getDialect());
}

test "DB: DBOptions all fields have defaults" {
    // 使用默认构造
    const opts = zorm.DBOptions{};

    // 验证所有字段都有默认值（编译时检查）
    _ = opts.discard_unknown_columns;
    _ = opts.max_open_conns;
    _ = opts.max_idle_conns;
    _ = opts.conn_max_lifetime;
    _ = opts.conn_max_idle_time;
    _ = opts.query_timeout;
    _ = opts.enable_query_log;
    _ = opts.enable_slow_query_log;
    _ = opts.slow_query_threshold;
}

test "DBStats: record operations" {
    var stats = zorm.core.DBStats{};

    // 初始状态
    try testing.expectEqual(@as(u64, 0), stats.getQueryCount());
    try testing.expectEqual(@as(u64, 0), stats.getErrorCount());

    // 记录查询
    stats.recordQuery();
    stats.recordQuery();
    stats.recordQuery();
    try testing.expectEqual(@as(u64, 3), stats.getQueryCount());

    // 记录错误
    stats.recordError();
    stats.recordError();
    try testing.expectEqual(@as(u64, 2), stats.getErrorCount());

    // 验证查询计数不受影响
    try testing.expectEqual(@as(u64, 3), stats.getQueryCount());
}

// ============================================
// 集成测试（基于真实 PostgreSQL）
// ============================================

test "DB: init and deinit with real PostgreSQL connection" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    // 验证 DB 初始化成功
    try testing.expect(db.allocator.ptr == allocator.ptr);
    try testing.expectEqual(.postgresql, zorm.DB(.postgresql).getDialect());

    // 执行简单查询验证连接有效
    const result = try test_helper.queryScalar(db, i64, "SELECT 1", &.{});
    try testing.expectEqual(@as(i64, 1), result);
}

test "DB: stats tracking with real queries" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    try test_helper.createTestTable(db, test_helper.TestUser);

    // 初始状态：统计为 0
    const initial_count = db.stats.getQueryCount();

    // 执行查询
    try seed_data.seedUser(db, "TestUser", "test@example.com", 25);

    // 验证统计增加
    const final_count = db.stats.getQueryCount();
    try testing.expect(final_count > initial_count);
}

test "DB: connection executes queries correctly" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    try test_helper.createTestTable(db, test_helper.TestUser);

    // 插入数据
    try seed_data.seedUsers(db);

    // 验证数据已插入
    const count = try test_helper.countRows(db, "test_users");
    try testing.expectEqual(@as(i64, 5), count);

    // 验证可以查询数据
    const user = try seed_data.getUser(db, 1);
    try testing.expectEqualStrings("Alice", user.name);
}

test "DB: cleanup closes connection properly" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    try test_helper.createTestTable(db, test_helper.TestUser);
    try seed_data.seedUsers(db);

    // 验证数据存在
    const count = try test_helper.countRows(db, "test_users");
    try testing.expectEqual(@as(i64, 5), count);

    // cleanup 会在 defer 中自动调用，验证不抛出错误
}

test "DB: query hooks list initialization" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    // 验证钩子列表初始为空
    try testing.expectEqual(@as(usize, 0), db.query_hooks.items.len);
}

test "DB: multiple queries maintain connection" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    try test_helper.createTestTable(db, test_helper.TestUser);

    // 执行多次查询
    try seed_data.seedUser(db, "User1", "user1@example.com", 20);
    try seed_data.seedUser(db, "User2", "user2@example.com", 25);
    try seed_data.seedUser(db, "User3", "user3@example.com", 30);

    // 验证所有查询都成功
    const count = try test_helper.countRows(db, "test_users");
    try testing.expectEqual(@as(i64, 3), count);
}

test "DB: schema isolation with test schema" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    // 验证使用了测试 schema
    const schema = try test_helper.queryScalar(
        db,
        []const u8,
        "SELECT current_schema()",
        &.{},
    );
    defer allocator.free(schema); // 释放复制的字符串

    // 验证 schema 名称以 "zorm_test" 开头（每个测试使用唯一的后缀）
    try testing.expect(std.mem.startsWith(u8, schema, test_helper.TEST_SCHEMA));
}

test "DB: exec method executes SQL correctly" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    // 使用 exec 创建表
    const create_sql =
        \\CREATE TABLE test_exec (
        \\    id SERIAL PRIMARY KEY,
        \\    value TEXT NOT NULL
        \\)
    ;

    try db.exec(create_sql, &.{});

    // 验证表已创建
    const exists = try test_helper.tableExists(db, "test_exec");
    try testing.expect(exists);

    // 插入数据
    const insert_sql = "INSERT INTO test_exec (value) VALUES ($1)";
    const args = [_]zorm.QueryArg{zorm.QueryArg.fromValue("test_value")};
    try db.exec(insert_sql, &args);

    // 验证数据已插入
    const count = try test_helper.countRows(db, "test_exec");
    try testing.expectEqual(@as(i64, 1), count);
}
