//! 子查询测试
//!
//! 验证 SelectQuery 的子查询功能:
//! - WHERE IN 子查询
//! - WHERE NOT IN 子查询
//! - WHERE EXISTS 子查询
//! - WHERE NOT EXISTS 子查询
//! - FROM 派生表
//! - 嵌套子查询
//! - 子查询参数合并

const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");

const Dialect = zorm.Dialect;
const query_mod = zorm.query;
const DBType = zorm.DB(Dialect.postgresql);

// 测试结构体
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
};

const Post = struct {
    id: i64,
    user_id: i64,
    title: []const u8,
    published: bool,
};

const UserStats = struct {
    id: i64,
    name: []const u8,
    post_count: i64,
};

test "WHERE IN 子查询: SQL 生成" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    // 创建子查询
    const SubSelectQuery = query_mod.SelectQuery(Post, Dialect.postgresql);
    var subquery = try SubSelectQuery.init(allocator, &mock_db, "posts");
    defer subquery.deinit();

    _ = try subquery.column("DISTINCT user_id");
    _ = try subquery.where("published = $1", .{true});

    // 创建主查询
    const SelectQuery = query_mod.SelectQuery(User, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users");
    defer query.deinit();

    _ = try query.whereIn("id", subquery);

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    // 验证 SQL 包含子查询
    try testing.expect(std.mem.indexOf(u8, sql, "WHERE id IN (") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "SELECT DISTINCT user_id FROM posts") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "WHERE published = $1") != null);
}

test "WHERE IN 子查询: 与常规WHERE组合" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    // 创建子查询
    const SubSelectQuery = query_mod.SelectQuery(Post, Dialect.postgresql);
    var subquery = try SubSelectQuery.init(allocator, &mock_db, "posts");
    defer subquery.deinit();

    _ = try subquery.column("DISTINCT user_id");
    _ = try subquery.where("published = $1", .{true});

    // 创建主查询
    const SelectQuery = query_mod.SelectQuery(User, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users");
    defer query.deinit();

    _ = try query.where("email LIKE $1", .{"%@example.com"});
    _ = try query.whereIn("id", subquery);

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    // 验证包含常规 WHERE 和子查询
    try testing.expect(std.mem.indexOf(u8, sql, "WHERE email LIKE $1") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "AND id IN (") != null);
}

test "WHERE NOT IN 子查询: SQL 生成" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    // 创建子查询
    const SubSelectQuery = query_mod.SelectQuery(Post, Dialect.postgresql);
    var subquery = try SubSelectQuery.init(allocator, &mock_db, "posts");
    defer subquery.deinit();

    _ = try subquery.column("DISTINCT user_id");
    _ = try subquery.where("published = $1", .{true});

    // 创建主查询
    const SelectQuery = query_mod.SelectQuery(User, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users");
    defer query.deinit();

    _ = try query.whereNotIn("id", subquery);

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    // 验证 SQL 包含 NOT IN 子查询
    try testing.expect(std.mem.indexOf(u8, sql, "WHERE id NOT IN (") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "SELECT DISTINCT user_id FROM posts") != null);
}

test "WHERE EXISTS 子查询: SQL 生成" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    // 创建子查询
    const SubSelectQuery = query_mod.SelectQuery(Post, Dialect.postgresql);
    var subquery = try SubSelectQuery.init(allocator, &mock_db, "posts");
    defer subquery.deinit();

    _ = try subquery.column("1");
    _ = try subquery.where("posts.user_id = users.id", .{});
    _ = try subquery.where("published = $1", .{true});

    // 创建主查询
    const SelectQuery = query_mod.SelectQuery(User, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users");
    defer query.deinit();

    _ = try query.whereExists(subquery);

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    // 验证 SQL 包含 EXISTS 子查询
    try testing.expect(std.mem.indexOf(u8, sql, "WHERE EXISTS (") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "SELECT 1 FROM posts") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "posts.user_id = users.id") != null);
}

test "WHERE NOT EXISTS 子查询: SQL 生成" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    // 创建子查询
    const SubSelectQuery = query_mod.SelectQuery(Post, Dialect.postgresql);
    var subquery = try SubSelectQuery.init(allocator, &mock_db, "posts");
    defer subquery.deinit();

    _ = try subquery.column("1");
    _ = try subquery.where("posts.user_id = users.id", .{});
    _ = try subquery.where("published = $1", .{true});

    // 创建主查询
    const SelectQuery = query_mod.SelectQuery(User, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users");
    defer query.deinit();

    _ = try query.whereNotExists(subquery);

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    // 验证 SQL 包含 NOT EXISTS 子查询
    try testing.expect(std.mem.indexOf(u8, sql, "WHERE NOT EXISTS (") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "SELECT 1 FROM posts") != null);
}

test "FROM 派生表: SQL 生成" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    // 创建派生表子查询
    const SubSelectQuery = query_mod.SelectQuery(User, Dialect.postgresql);
    var subquery = try SubSelectQuery.init(allocator, &mock_db, "users");
    defer subquery.deinit();

    _ = try subquery.column("id");
    _ = try subquery.column("name");
    _ = try subquery.column("COUNT(*) AS post_count");
    _ = try subquery.leftJoin("posts", "posts.user_id = users.id");
    _ = try subquery.groupBy("id, name");

    // 创建外部查询
    const SelectQuery = query_mod.SelectQuery(UserStats, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users");
    defer query.deinit();

    _ = try query.column("*");
    _ = try query.fromSubquery(subquery, "user_stats");
    _ = try query.where("post_count > $1", .{5});

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    // 验证 SQL 包含派生表
    try testing.expect(std.mem.indexOf(u8, sql, "FROM (SELECT id, name, COUNT(*) AS post_count") != null);
    try testing.expect(std.mem.indexOf(u8, sql, ") AS user_stats") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "WHERE post_count > $1") != null);
}

test "多个子查询: SQL 生成" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    // 创建第一个子查询 (WHERE IN)
    const SubSelectQuery1 = query_mod.SelectQuery(Post, Dialect.postgresql);
    var subquery1 = try SubSelectQuery1.init(allocator, &mock_db, "posts");
    defer subquery1.deinit();

    _ = try subquery1.column("DISTINCT user_id");
    _ = try subquery1.where("published = $1", .{true});

    // 创建第二个子查询 (WHERE EXISTS)
    const SubSelectQuery2 = query_mod.SelectQuery(Post, Dialect.postgresql);
    var subquery2 = try SubSelectQuery2.init(allocator, &mock_db, "posts");
    defer subquery2.deinit();

    _ = try subquery2.column("1");
    _ = try subquery2.where("posts.user_id = users.id", .{});
    _ = try subquery2.where("created_at > $1", .{"2024-01-01"});

    // 创建主查询
    const SelectQuery = query_mod.SelectQuery(User, Dialect.postgresql);
    var query = try SelectQuery.init(allocator, &mock_db, "users");
    defer query.deinit();

    _ = try query.where("email LIKE $1", .{"%@example.com"});
    _ = try query.whereIn("id", subquery1);
    _ = try query.whereExists(subquery2);

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    // 验证 SQL 包含两个子查询
    try testing.expect(std.mem.indexOf(u8, sql, "id IN (") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "EXISTS (") != null);
}

test "嵌套子查询: SQL 生成" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    // 创建最内层子查询
    const InnerQuery = query_mod.SelectQuery(Post, Dialect.postgresql);
    var inner_query = try InnerQuery.init(allocator, &mock_db, "posts");
    defer inner_query.deinit();

    _ = try inner_query.column("user_id");
    _ = try inner_query.where("published = $1", .{true});
    _ = try inner_query.groupBy("user_id");
    _ = try inner_query.having("COUNT(*) > $1", .{10});

    // 创建中间层子查询
    const MiddleQuery = query_mod.SelectQuery(User, Dialect.postgresql);
    var middle_query = try MiddleQuery.init(allocator, &mock_db, "users");
    defer middle_query.deinit();

    _ = try middle_query.column("id");
    _ = try middle_query.whereIn("id", inner_query);

    // 创建最外层查询
    const OuterQuery = query_mod.SelectQuery(User, Dialect.postgresql);
    var outer_query = try OuterQuery.init(allocator, &mock_db, "users");
    defer outer_query.deinit();

    _ = try outer_query.column("*");
    _ = try outer_query.whereIn("id", middle_query);

    const sql = try outer_query.buildSQL();
    defer allocator.free(sql);

    // 验证嵌套子查询
    try testing.expect(std.mem.indexOf(u8, sql, "WHERE id IN (") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "SELECT id FROM users") != null);
}

test "FROM 派生表与 WHERE 子句组合: SQL 生成" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    // 创建派生表
    const SubSelectQuery = query_mod.SelectQuery(User, Dialect.postgresql);
    var subquery = try SubSelectQuery.init(allocator, &mock_db, "users");
    defer subquery.deinit();

    _ = try subquery.column("id");
    _ = try subquery.column("name");
    _ = try subquery.column("COUNT(*) AS post_count");
    _ = try subquery.leftJoin("posts", "posts.user_id = users.id");
    _ = try subquery.where("users.active = $1", .{true});
    _ = try subquery.groupBy("id, name");

    // 创建子查询 (用于外层 WHERE IN)
    const WhereInQuery = query_mod.SelectQuery(User, Dialect.postgresql);
    var where_in_query = try WhereInQuery.init(allocator, &mock_db, "users");
    defer where_in_query.deinit();

    _ = try where_in_query.column("id");
    _ = try where_in_query.where("email LIKE $1", .{"%@admin.com"});

    // 创建外层查询
    const OuterQuery = query_mod.SelectQuery(UserStats, Dialect.postgresql);
    var outer_query = try OuterQuery.init(allocator, &mock_db, "users");
    defer outer_query.deinit();

    _ = try outer_query.column("*");
    _ = try outer_query.fromSubquery(subquery, "user_stats");
    _ = try outer_query.where("post_count > $1", .{5});
    _ = try outer_query.whereIn("id", where_in_query);

    const sql = try outer_query.buildSQL();
    defer allocator.free(sql);

    // 验证派生表
    try testing.expect(std.mem.indexOf(u8, sql, "FROM (") != null);
    try testing.expect(std.mem.indexOf(u8, sql, ") AS user_stats") != null);

    // 验证 WHERE 子句
    try testing.expect(std.mem.indexOf(u8, sql, "WHERE post_count > $1") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "AND id IN (") != null);
}
