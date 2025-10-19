//! 测试数据种子
//!
//! 提供标准化的测试数据,确保测试的可重复性和一致性
//!
//! ## 使用方式
//! ```zig
//! var db = try test_helper.setupTestDB(allocator);
//! defer test_helper.cleanupTestDB(db) catch {};
//!
//! // 创建表
//! try test_helper.createTestTable(db, test_helper.TestUser);
//!
//! // 填充测试数据
//! try seed_data.seedUsers(db);
//!
//! // 执行测试...
//!
//! // 清理数据
//! try seed_data.clearAllData(db);
//! ```

const std = @import("std");
const zorm = @import("zorm");
const test_helper = @import("test_helper");

// ============================================
// 用户数据种子
// ============================================

/// 填充测试用户数据
///
/// 创建 5 个标准测试用户:
/// - Alice: id=1, age=25
/// - Bob: id=2, age=30
/// - Charlie: id=3, age=28
/// - Diana: id=4, age=35
/// - Eve: id=5, age=22
pub fn seedUsers(db: *zorm.DB(.postgresql)) !void {
    const now = std.time.timestamp();

    const sql =
        \\INSERT INTO test_users (id, name, email, age, created_at, updated_at) VALUES
        \\  (1, 'Alice', 'alice@example.com', 25, $1, $1),
        \\  (2, 'Bob', 'bob@example.com', 30, $1, $1),
        \\  (3, 'Charlie', 'charlie@example.com', 28, $1, $1),
        \\  (4, 'Diana', 'diana@example.com', 35, $1, $1),
        \\  (5, 'Eve', 'eve@example.com', 22, $1, $1)
    ;

    const args = [_]zorm.QueryArg{zorm.QueryArg.fromValue(now)};
    try db.exec(sql, &args);

    // 重置序列到正确的值
    try db.exec("SELECT setval('test_users_id_seq', 5, true)", &.{});
}

/// 填充单个用户
pub fn seedUser(
    db: *zorm.DB(.postgresql),
    name: []const u8,
    email: []const u8,
    age: ?i32,
) !void {
    const now = std.time.timestamp();

    const sql =
        \\INSERT INTO test_users (name, email, age, created_at, updated_at)
        \\VALUES ($1, $2, $3, $4, $4)
    ;

    const args = [_]zorm.QueryArg{
        zorm.QueryArg.fromValue(name),
        zorm.QueryArg.fromValue(email),
        if (age) |a| zorm.QueryArg.fromValue(a) else zorm.QueryArg.null_val,
        zorm.QueryArg.fromValue(now),
    };

    try db.exec(sql, &args);
}

/// 填充多个用户 (用于批量测试)
pub fn seedManyUsers(db: *zorm.DB(.postgresql), count: usize) !void {
    const now = std.time.timestamp();

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const name = try std.fmt.allocPrint(
            db.allocator,
            "User{d}",
            .{i + 1},
        );
        defer db.allocator.free(name);

        const email = try std.fmt.allocPrint(
            db.allocator,
            "user{d}@example.com",
            .{i + 1},
        );
        defer db.allocator.free(email);

        const sql =
            \\INSERT INTO test_users (name, email, age, created_at, updated_at)
            \\VALUES ($1, $2, $3, $4, $4)
        ;

        const age = @as(i32, @intCast(20 + (i % 30))); // 年龄 20-49

        const args = [_]zorm.QueryArg{
            zorm.QueryArg.fromValue(name),
            zorm.QueryArg.fromValue(email),
            zorm.QueryArg.fromValue(age),
            zorm.QueryArg.fromValue(now),
        };

        try db.exec(sql, &args);
    }
}

// ============================================
// 文章数据种子
// ============================================

/// 填充测试文章数据
///
/// 为每个用户创建 2 篇文章 (总共 10 篇)
pub fn seedPosts(db: *zorm.DB(.postgresql)) !void {
    const now = std.time.timestamp();

    const sql =
        \\INSERT INTO test_posts (id, user_id, title, content, published, created_at) VALUES
        \\  (1, 1, 'Alice Post 1', 'Content by Alice 1', true, $1),
        \\  (2, 1, 'Alice Post 2', 'Content by Alice 2', false, $1),
        \\  (3, 2, 'Bob Post 1', 'Content by Bob 1', true, $1),
        \\  (4, 2, 'Bob Post 2', 'Content by Bob 2', true, $1),
        \\  (5, 3, 'Charlie Post 1', 'Content by Charlie 1', false, $1),
        \\  (6, 3, 'Charlie Post 2', 'Content by Charlie 2', true, $1),
        \\  (7, 4, 'Diana Post 1', 'Content by Diana 1', true, $1),
        \\  (8, 4, 'Diana Post 2', 'Content by Diana 2', false, $1),
        \\  (9, 5, 'Eve Post 1', 'Content by Eve 1', true, $1),
        \\  (10, 5, 'Eve Post 2', 'Content by Eve 2', true, $1)
    ;

    const args = [_]zorm.QueryArg{zorm.QueryArg.fromValue(now)};
    try db.exec(sql, &args);

    // 重置序列
    try db.exec("SELECT setval('test_posts_id_seq', 10, true)", &.{});
}

/// 填充单篇文章
pub fn seedPost(
    db: *zorm.DB(.postgresql),
    user_id: i64,
    title: []const u8,
    content: []const u8,
    published: bool,
) !void {
    const now = std.time.timestamp();

    const sql =
        \\INSERT INTO test_posts (user_id, title, content, published, created_at)
        \\VALUES ($1, $2, $3, $4, $5)
    ;

    const args = [_]zorm.QueryArg{
        zorm.QueryArg.fromValue(user_id),
        zorm.QueryArg.fromValue(title),
        zorm.QueryArg.fromValue(content),
        zorm.QueryArg.fromValue(published),
        zorm.QueryArg.fromValue(now),
    };

    try db.exec(sql, &args);
}

// ============================================
// 数据清理
// ============================================

/// 清空所有测试数据
///
/// 清空所有测试表的数据,但保留表结构
pub fn clearAllData(db: *zorm.DB(.postgresql)) !void {
    // 按依赖关系顺序删除 (先删除依赖表,后删除主表)
    try test_helper.truncateTable(db, "test_posts");
    try test_helper.truncateTable(db, "test_users");
}

/// 清空用户数据
pub fn clearUsers(db: *zorm.DB(.postgresql)) !void {
    try test_helper.truncateTable(db, "test_users");
}

/// 清空文章数据
pub fn clearPosts(db: *zorm.DB(.postgresql)) !void {
    try test_helper.truncateTable(db, "test_posts");
}

// ============================================
// 数据验证辅助函数
// ============================================

/// 验证用户数量
pub fn verifyUserCount(db: *zorm.DB(.postgresql), expected_count: i64) !void {
    const actual_count = try test_helper.countRows(db, "test_users");
    if (actual_count != expected_count) {
        std.debug.print(
            "❌ 用户数量不匹配! 期望: {d}, 实际: {d}\n",
            .{ expected_count, actual_count },
        );
        return error.CountMismatch;
    }
}

/// 验证文章数量
pub fn verifyPostCount(db: *zorm.DB(.postgresql), expected_count: i64) !void {
    const actual_count = try test_helper.countRows(db, "test_posts");
    if (actual_count != expected_count) {
        std.debug.print(
            "❌ 文章数量不匹配! 期望: {d}, 实际: {d}\n",
            .{ expected_count, actual_count },
        );
        return error.CountMismatch;
    }
}

/// 获取用户信息 (用于验证)
pub fn getUser(
    db: *zorm.DB(.postgresql),
    user_id: i64,
) !test_helper.TestUser {
    const sql = "SELECT id, name, email, age, created_at, updated_at FROM test_users WHERE id = $1";
    const args = [_]zorm.QueryArg{zorm.QueryArg.fromValue(user_id)};

    var result = try db.conn.query(sql, &args);
    defer result.close();

    if (try result.rows.next()) |row| {
        return test_helper.TestUser{
            .id = try row.getInt(i64, 0),
            .name = try row.getString(1),
            .email = try row.getString(2),
            .age = if (row.isNull(3)) null else try row.getInt(i32, 3),
            .created_at = try row.getInt(i64, 4),
            .updated_at = try row.getInt(i64, 5),
        };
    }

    return error.UserNotFound;
}

/// 获取文章信息 (用于验证)
pub fn getPost(
    db: *zorm.DB(.postgresql),
    post_id: i64,
) !test_helper.TestPost {
    const sql = "SELECT id, user_id, title, content, published, created_at FROM test_posts WHERE id = $1";
    const args = [_]zorm.QueryArg{zorm.QueryArg.fromValue(post_id)};

    var result = try db.conn.query(sql, &args);
    defer result.close();

    if (try result.rows.next()) |row| {
        return test_helper.TestPost{
            .id = try row.getInt(i64, 0),
            .user_id = try row.getInt(i64, 1),
            .title = try row.getString(2),
            .content = try row.getString(3),
            .published = try row.getBool(4),
            .created_at = try row.getInt(i64, 5),
        };
    }

    return error.PostNotFound;
}

// ============================================
// 特殊场景数据
// ============================================

/// 填充 NULL 值测试数据
///
/// 创建包含 NULL 值的用户,用于测试 NULL 处理
pub fn seedUsersWithNulls(db: *zorm.DB(.postgresql)) !void {
    const now = std.time.timestamp();

    const sql =
        \\INSERT INTO test_users (name, email, age, created_at, updated_at) VALUES
        \\  ('User With Null Age', 'null_age@example.com', NULL, $1, $1)
    ;

    const args = [_]zorm.QueryArg{zorm.QueryArg.fromValue(now)};
    try db.exec(sql, &args);
}

/// 填充边界值测试数据
///
/// 创建包含边界值的用户,用于测试边界条件
pub fn seedUsersWithBoundaryValues(db: *zorm.DB(.postgresql)) !void {
    const now = std.time.timestamp();

    const sql =
        \\INSERT INTO test_users (name, email, age, created_at, updated_at) VALUES
        \\  ('Min Age User', 'min@example.com', 0, $1, $1),
        \\  ('Max Age User', 'max@example.com', 2147483647, $1, $1)
    ;

    const args = [_]zorm.QueryArg{zorm.QueryArg.fromValue(now)};
    try db.exec(sql, &args);
}

/// 填充重复数据 (用于测试唯一约束)
///
/// 尝试插入重复 email,应该失败
pub fn seedDuplicateUser(db: *zorm.DB(.postgresql)) !void {
    const now = std.time.timestamp();

    const sql =
        \\INSERT INTO test_users (name, email, age, created_at, updated_at)
        \\VALUES ('Duplicate', 'alice@example.com', 25, $1, $1)
    ;

    const args = [_]zorm.QueryArg{zorm.QueryArg.fromValue(now)};
    try db.exec(sql, &args);
}
