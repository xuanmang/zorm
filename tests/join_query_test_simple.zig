//! JOIN 查询测试 - 简化版
//!
//! 验证 SelectQuery 的 JOIN 功能 SQL 生成

const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");

const Dialect = zorm.Dialect;
const query_mod = zorm.query;
const DBType = zorm.DB(Dialect.postgresql);

// 测试结构体
const TestResult = struct {
    user_id: i64,
    user_name: []const u8,
    profile_bio: ?[]const u8,
};

test "INNER JOIN: Basic SQL generation" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const SelectQuery = query_mod.SelectQuery(TestResult, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users AS u");
    defer query.deinit();

    _ = try query.column("u.id AS user_id");
    _ = try query.column("u.name AS user_name");
    _ = try query.column("p.bio AS profile_bio");
    _ = try query.innerJoin("profiles AS p", "p.user_id = u.id");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expect(std.mem.indexOf(u8, sql, "SELECT") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "FROM users AS u") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "INNER JOIN profiles AS p ON p.user_id = u.id") != null);
}

test "LEFT JOIN: SQL generation" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const SelectQuery = query_mod.SelectQuery(TestResult, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users AS u");
    defer query.deinit();

    _ = try query.column("u.id AS user_id");
    _ = try query.column("u.name AS user_name");
    _ = try query.column("p.bio AS profile_bio");
    _ = try query.leftJoin("profiles AS p", "p.user_id = u.id");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expect(std.mem.indexOf(u8, sql, "LEFT JOIN profiles AS p ON p.user_id = u.id") != null);
}

test "RIGHT JOIN: SQL generation" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const SelectQuery = query_mod.SelectQuery(TestResult, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users AS u");
    defer query.deinit();

    _ = try query.column("u.id AS user_id");
    _ = try query.column("u.name AS user_name");
    _ = try query.column("p.bio AS profile_bio");
    _ = try query.rightJoin("profiles AS p", "p.user_id = u.id");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expect(std.mem.indexOf(u8, sql, "RIGHT JOIN profiles AS p ON p.user_id = u.id") != null);
}

test "FULL OUTER JOIN: SQL generation" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const SelectQuery = query_mod.SelectQuery(TestResult, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users AS u");
    defer query.deinit();

    _ = try query.column("u.id AS user_id");
    _ = try query.column("u.name AS user_name");
    _ = try query.column("p.bio AS profile_bio");
    _ = try query.fullJoin("profiles AS p", "p.user_id = u.id");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expect(std.mem.indexOf(u8, sql, "FULL OUTER JOIN profiles AS p ON p.user_id = u.id") != null);
}

test "CROSS JOIN: SQL generation" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const TestCross = struct {
        cat_id: i64,
        prod_id: i64,
    };

    const SelectQuery = query_mod.SelectQuery(TestCross, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "categories AS c");
    defer query.deinit();

    _ = try query.column("c.id AS cat_id");
    _ = try query.column("p.id AS prod_id");
    _ = try query.crossJoin("products AS p");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expect(std.mem.indexOf(u8, sql, "CROSS JOIN products AS p") != null);
}

test "Multiple JOINs: Two joins" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const TestMulti = struct {
        user_id: i64,
        profile_bio: ?[]const u8,
        order_id: ?i64,
    };

    const SelectQuery = query_mod.SelectQuery(TestMulti, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users AS u");
    defer query.deinit();

    _ = try query.column("u.id AS user_id");
    _ = try query.column("p.bio AS profile_bio");
    _ = try query.column("o.id AS order_id");
    _ = try query.leftJoin("profiles AS p", "p.user_id = u.id");
    _ = try query.leftJoin("orders AS o", "o.user_id = u.id");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expect(std.mem.indexOf(u8, sql, "LEFT JOIN profiles AS p ON p.user_id = u.id") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "LEFT JOIN orders AS o ON o.user_id = u.id") != null);
}

test "JOIN with WHERE clause" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const SelectQuery = query_mod.SelectQuery(TestResult, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users AS u");
    defer query.deinit();

    _ = try query.column("u.id AS user_id");
    _ = try query.column("u.name AS user_name");
    _ = try query.column("p.bio AS profile_bio");
    _ = try query.innerJoin("profiles AS p", "p.user_id = u.id");
    _ = try query.where("u.is_active = $1", .{true});

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    const join_idx = std.mem.indexOf(u8, sql, "INNER JOIN") orelse return error.TestFailed;
    const where_idx = std.mem.indexOf(u8, sql, "WHERE") orelse return error.TestFailed;
    try testing.expect(join_idx < where_idx);
}

test "JOIN with ORDER BY" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const SelectQuery = query_mod.SelectQuery(TestResult, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users AS u");
    defer query.deinit();

    _ = try query.column("u.id AS user_id");
    _ = try query.column("u.name AS user_name");
    _ = try query.column("p.bio AS profile_bio");
    _ = try query.innerJoin("profiles AS p", "p.user_id = u.id");
    _ = try query.orderBy("u.name", .asc);

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expect(std.mem.indexOf(u8, sql, "ORDER BY u.name ASC") != null);
}

test "JOIN with LIMIT and OFFSET" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const SelectQuery = query_mod.SelectQuery(TestResult, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users AS u");
    defer query.deinit();

    _ = try query.column("u.id AS user_id");
    _ = try query.column("u.name AS user_name");
    _ = try query.column("p.bio AS profile_bio");
    _ = try query.innerJoin("profiles AS p", "p.user_id = u.id");
    _ = try query.limit(10);
    _ = try query.offset(5);

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expect(std.mem.indexOf(u8, sql, "LIMIT 10") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "OFFSET 5") != null);
}
