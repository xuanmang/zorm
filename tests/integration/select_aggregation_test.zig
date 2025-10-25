//! SELECT 聚合函数集成测试
//!
//! 验证 GROUP BY 和聚合函数的完整功能:
//! - 基础聚合函数(COUNT, SUM, AVG, MAX, MIN)
//! - DISTINCT 聚合
//! - 多列 GROUP BY
//! - JOIN + GROUP BY + HAVING 组合
//! - 聚合结果映射到自定义结构体
//!
//! 注意: 这些测试验证 SQL 生成的正确性。
//! 要在真实 PostgreSQL 数据库中运行,需要:
//! 1. 配置数据库连接
//! 2. 创建测试表(users, posts)
//! 3. 插入测试数据
//! 4. 执行查询并验证结果

const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");

const Dialect = zorm.Dialect;
const query_mod = zorm.query;
const DBType = zorm.DB(Dialect.postgresql);

// ============================================================
// 测试数据模型
// ============================================================

const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,

    pub const table_name = "users";
};

const Post = struct {
    id: i64,
    user_id: i64,
    title: []const u8,
    view_count: i64,
    category: []const u8,

    pub const table_name = "posts";
};

// 用户统计结果结构体
const UserStats = struct {
    user_id: i64,
    user_name: []const u8,
    post_count: i64,
    total_views: i64,
    avg_views: f64,
    max_views: i64,
    min_views: i64,
    unique_categories: i64,
};

// 部门统计结构体
const DepartmentStats = struct {
    department: []const u8,
    user_count: i64,
};

// ============================================================
// 任务 4.1: 基础聚合结果映射测试
// ============================================================

test "Aggregation result mapping: COUNT aggregation" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const SelectQuery = query_mod.SelectQuery(DepartmentStats, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users");
    defer query.deinit();

    _ = try query.column("department");
    _ = try query.column("COUNT(*) as user_count");
    _ = try query.groupBy("department");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expectEqualStrings("SELECT department, COUNT(*) as user_count FROM users GROUP BY department", sql);
}

test "Aggregation result mapping: SUM aggregation" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const OrderStats = struct {
        user_id: i64,
        total_amount: i64,
    };

    const SelectQuery = query_mod.SelectQuery(OrderStats, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "orders");
    defer query.deinit();

    _ = try query.column("user_id");
    _ = try query.column("SUM(amount) as total_amount");
    _ = try query.groupBy("user_id");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expectEqualStrings("SELECT user_id, SUM(amount) as total_amount FROM orders GROUP BY user_id", sql);
}

test "Aggregation result mapping: AVG aggregation" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const PostAvgStats = struct {
        user_id: i64,
        avg_views: f64,
    };

    const SelectQuery = query_mod.SelectQuery(PostAvgStats, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "posts");
    defer query.deinit();

    _ = try query.column("user_id");
    _ = try query.column("AVG(view_count) as avg_views");
    _ = try query.groupBy("user_id");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expectEqualStrings("SELECT user_id, AVG(view_count) as avg_views FROM posts GROUP BY user_id", sql);
}

test "Aggregation result mapping: MAX and MIN aggregation" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const PriceStats = struct {
        category: []const u8,
        max_price: i64,
        min_price: i64,
    };

    const SelectQuery = query_mod.SelectQuery(PriceStats, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "products");
    defer query.deinit();

    _ = try query.column("category");
    _ = try query.column("MAX(price) as max_price");
    _ = try query.column("MIN(price) as min_price");
    _ = try query.groupBy("category");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expectEqualStrings("SELECT category, MAX(price) as max_price, MIN(price) as min_price FROM products GROUP BY category", sql);
}

// ============================================================
// 任务 4.2: DISTINCT 聚合结果映射测试
// ============================================================

test "Aggregation result mapping: COUNT DISTINCT" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const UniqueUserStats = struct {
        unique_users: i64,
    };

    const SelectQuery = query_mod.SelectQuery(UniqueUserStats, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "orders");
    defer query.deinit();

    _ = try query.column("COUNT(DISTINCT user_id) as unique_users");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expectEqualStrings("SELECT COUNT(DISTINCT user_id) as unique_users FROM orders", sql);
}

test "Aggregation result mapping: Multiple DISTINCT aggregations" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const EventStats = struct {
        event_type: []const u8,
        unique_users: i64,
        unique_sessions: i64,
    };

    const SelectQuery = query_mod.SelectQuery(EventStats, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "events");
    defer query.deinit();

    _ = try query.column("event_type");
    _ = try query.column("COUNT(DISTINCT user_id) as unique_users");
    _ = try query.column("COUNT(DISTINCT session_id) as unique_sessions");
    _ = try query.groupBy("event_type");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expectEqualStrings("SELECT event_type, COUNT(DISTINCT user_id) as unique_users, COUNT(DISTINCT session_id) as unique_sessions FROM events GROUP BY event_type", sql);
}

// ============================================================
// 任务 4.3: NULL 值聚合测试
// ============================================================

test "Aggregation with NULL values: COUNT(*) vs COUNT(column)" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const NullStats = struct {
        total_rows: i64,
        non_null_emails: i64,
    };

    const SelectQuery = query_mod.SelectQuery(NullStats, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users");
    defer query.deinit();

    _ = try query.column("COUNT(*) as total_rows");
    _ = try query.column("COUNT(email) as non_null_emails");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expectEqualStrings("SELECT COUNT(*) as total_rows, COUNT(email) as non_null_emails FROM users", sql);
}

// ============================================================
// 任务 5: JOIN + GROUP BY + HAVING 组合测试
// ============================================================

test "JOIN + GROUP BY + HAVING: Complete aggregation query" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const SelectQuery = query_mod.SelectQuery(UserStats, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users");
    defer query.deinit();

    _ = try query.column("users.id as user_id");
    _ = try query.column("users.name as user_name");
    _ = try query.column("COUNT(posts.id) as post_count");
    _ = try query.column("SUM(posts.view_count) as total_views");
    _ = try query.column("AVG(posts.view_count) as avg_views");
    _ = try query.column("MAX(posts.view_count) as max_views");
    _ = try query.column("MIN(posts.view_count) as min_views");
    _ = try query.column("COUNT(DISTINCT posts.category) as unique_categories");
    _ = try query.innerJoin("posts", "posts.user_id = users.id");
    _ = try query.groupBy("users.id, users.name");
    _ = try query.having("COUNT(posts.id) > $1", .{5});

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    const expected = "SELECT users.id as user_id, users.name as user_name, COUNT(posts.id) as post_count, SUM(posts.view_count) as total_views, AVG(posts.view_count) as avg_views, MAX(posts.view_count) as max_views, MIN(posts.view_count) as min_views, COUNT(DISTINCT posts.category) as unique_categories FROM users INNER JOIN posts ON posts.user_id = users.id GROUP BY users.id, users.name HAVING COUNT(posts.id) > $1";
    try testing.expectEqualStrings(expected, sql);
}

test "JOIN + GROUP BY + HAVING: Multiple HAVING conditions" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const SelectQuery = query_mod.SelectQuery(UserStats, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users");
    defer query.deinit();

    _ = try query.column("users.id as user_id");
    _ = try query.column("users.name as user_name");
    _ = try query.column("COUNT(posts.id) as post_count");
    _ = try query.column("SUM(posts.view_count) as total_views");
    _ = try query.column("AVG(posts.view_count) as avg_views");
    _ = try query.column("MAX(posts.view_count) as max_views");
    _ = try query.column("MIN(posts.view_count) as min_views");
    _ = try query.column("COUNT(DISTINCT posts.category) as unique_categories");
    _ = try query.innerJoin("posts", "posts.user_id = users.id");
    _ = try query.groupBy("users.id, users.name");
    _ = try query.having("COUNT(posts.id) > $1", .{10});
    _ = try query.having("SUM(posts.view_count) > $2", .{1000});
    _ = try query.orderBy("total_views", .desc);

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    const expected = "SELECT users.id as user_id, users.name as user_name, COUNT(posts.id) as post_count, SUM(posts.view_count) as total_views, AVG(posts.view_count) as avg_views, MAX(posts.view_count) as max_views, MIN(posts.view_count) as min_views, COUNT(DISTINCT posts.category) as unique_categories FROM users INNER JOIN posts ON posts.user_id = users.id GROUP BY users.id, users.name HAVING COUNT(posts.id) > $1 AND SUM(posts.view_count) > $2 ORDER BY total_views DESC";
    try testing.expectEqualStrings(expected, sql);
}

test "JOIN + GROUP BY + HAVING: ORDER BY aggregation result" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    const SimpleStats = struct {
        user_id: i64,
        post_count: i64,
    };

    const SelectQuery = query_mod.SelectQuery(SimpleStats, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users");
    defer query.deinit();

    _ = try query.column("users.id as user_id");
    _ = try query.column("COUNT(posts.id) as post_count");
    _ = try query.innerJoin("posts", "posts.user_id = users.id");
    _ = try query.groupBy("users.id");
    _ = try query.having("COUNT(posts.id) > $1", .{3});
    _ = try query.orderBy("post_count", .desc);
    _ = try query.limit(10);

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    const expected = "SELECT users.id as user_id, COUNT(posts.id) as post_count FROM users INNER JOIN posts ON posts.user_id = users.id GROUP BY users.id HAVING COUNT(posts.id) > $1 ORDER BY post_count DESC LIMIT 10";
    try testing.expectEqualStrings(expected, sql);
}

// ============================================================
// 真实数据库集成测试指南
// ============================================================

// 注意: 以下是真实数据库集成测试的示例代码结构
// 需要配置 PostgreSQL 连接才能运行
//
// test "Real DB: Aggregation with actual data" {
//     const allocator = testing.allocator;
//
//     // 1. 连接数据库
//     var db = try zorm.DB(Dialect.postgresql).init(allocator, .{
//         .host = "localhost",
//         .port = 5432,
//         .database = "test_zorm",
//         .username = "postgres",
//         .password = "postgres",
//     });
//     defer db.deinit();
//
//     // 2. 创建测试表
//     _ = try db.exec("CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, name TEXT NOT NULL, department TEXT)", .{});
//     _ = try db.exec("CREATE TABLE IF NOT EXISTS posts (id SERIAL PRIMARY KEY, user_id INT, view_count INT, category TEXT)", .{});
//
//     // 3. 插入测试数据
//     _ = try db.exec("INSERT INTO users (name, department) VALUES ($1, $2)", .{"Alice", "Engineering"});
//     _ = try db.exec("INSERT INTO users (name, department) VALUES ($1, $2)", .{"Bob", "Engineering"});
//     _ = try db.exec("INSERT INTO posts (user_id, view_count, category) VALUES ($1, $2, $3)", .{1, 100, "Tech"});
//     _ = try db.exec("INSERT INTO posts (user_id, view_count, category) VALUES ($1, $2, $3)", .{1, 200, "Science"});
//
//     // 4. 执行聚合查询
//     const SelectQuery = query_mod.SelectQuery(UserStats, Dialect.postgresql);
//     var query = try SelectQuery.init(allocator, &db, "users");
//     defer query.deinit();
//
//     _ = try query.column("users.id as user_id");
//     _ = try query.column("users.name as user_name");
//     _ = try query.column("COUNT(posts.id) as post_count");
//     _ = try query.column("SUM(posts.view_count) as total_views");
//     _ = try query.innerJoin("posts", "posts.user_id = users.id");
//     _ = try query.groupBy("users.id, users.name");
//
//     const results = try query.all();
//     defer results.deinit();
//
//     // 5. 验证结果
//     try testing.expectEqual(@as(usize, 1), results.items.len);
//     try testing.expectEqual(@as(i64, 1), results.items[0].user_id);
//     try testing.expectEqualStrings("Alice", results.items[0].user_name);
//     try testing.expectEqual(@as(i64, 2), results.items[0].post_count);
//     try testing.expectEqual(@as(i64, 300), results.items[0].total_views);
//
//     // 6. 清理测试数据
//     _ = try db.exec("DROP TABLE IF EXISTS posts", .{});
//     _ = try db.exec("DROP TABLE IF EXISTS users", .{});
// }
