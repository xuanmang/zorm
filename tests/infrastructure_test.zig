//! 基础设施验证测试
//!
//! 验证 test_helper 和 seed_data 是否正常工作

const std = @import("std");
const testing = std.testing;
const test_helper = @import("test_helper.zig");
const seed_data = @import("seed_data.zig");

test "Infrastructure: setupTestDB and cleanupTestDB" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    // 验证数据库连接成功
    try testing.expect(db.allocator.ptr == allocator.ptr);
}

test "Infrastructure: createTestTable" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    // 创建测试表
    try test_helper.createTestTable(db, test_helper.TestUser);

    // 验证表存在
    const exists = try test_helper.tableExists(db, "test_users");
    try testing.expect(exists);
}

test "Infrastructure: seedUsers" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    // 创建表
    try test_helper.createTestTable(db, test_helper.TestUser);

    // 填充数据
    try seed_data.seedUsers(db);

    // 验证数据量
    const count = try test_helper.countRows(db, "test_users");
    try testing.expectEqual(@as(i64, 5), count);
}

test "Infrastructure: seedUser - single insert" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    try test_helper.createTestTable(db, test_helper.TestUser);

    // 插入单个用户
    try seed_data.seedUser(db, "TestUser", "test@example.com", 25);

    // 验证数据
    const count = try test_helper.countRows(db, "test_users");
    try testing.expectEqual(@as(i64, 1), count);
}

test "Infrastructure: truncateTable" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    try test_helper.createTestTable(db, test_helper.TestUser);
    try seed_data.seedUsers(db);

    // 验证有数据
    var count = try test_helper.countRows(db, "test_users");
    try testing.expectEqual(@as(i64, 5), count);

    // 清空表
    try test_helper.truncateTable(db, "test_users");

    // 验证数据已清空
    count = try test_helper.countRows(db, "test_users");
    try testing.expectEqual(@as(i64, 0), count);
}

test "Infrastructure: getUser" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    try test_helper.createTestTable(db, test_helper.TestUser);
    try seed_data.seedUsers(db);

    // 获取用户信息
    const user = try seed_data.getUser(db, 1);

    // 验证数据
    try testing.expectEqual(@as(i64, 1), user.id);
    try testing.expectEqualStrings("Alice", user.name);
    try testing.expectEqualStrings("alice@example.com", user.email);
    try testing.expectEqual(@as(?i32, 25), user.age);
}

test "Infrastructure: queryScalar" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    // 测试查询标量值
    const result = try test_helper.queryScalar(
        db,
        i64,
        "SELECT 42",
        &.{},
    );

    try testing.expectEqual(@as(i64, 42), result);
}

test "Infrastructure: seedManyUsers" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    try test_helper.createTestTable(db, test_helper.TestUser);

    // 插入100个用户
    try seed_data.seedManyUsers(db, 100);

    // 验证数量
    const count = try test_helper.countRows(db, "test_users");
    try testing.expectEqual(@as(i64, 100), count);
}

test "Infrastructure: clearAllData" {
    const allocator = testing.allocator;

    const db = try test_helper.setupTestDB(allocator);
    defer test_helper.cleanupTestDB(db) catch {};

    try test_helper.createTestTable(db, test_helper.TestUser);
    try test_helper.createTestTable(db, test_helper.TestPost);

    try seed_data.seedUsers(db);
    try seed_data.seedPosts(db);

    // 验证有数据
    var user_count = try test_helper.countRows(db, "test_users");
    var post_count = try test_helper.countRows(db, "test_posts");
    try testing.expectEqual(@as(i64, 5), user_count);
    try testing.expectEqual(@as(i64, 10), post_count);

    // 清空所有数据
    try seed_data.clearAllData(db);

    // 验证数据已清空
    user_count = try test_helper.countRows(db, "test_users");
    post_count = try test_helper.countRows(db, "test_posts");
    try testing.expectEqual(@as(i64, 0), user_count);
    try testing.expectEqual(@as(i64, 0), post_count);
}
