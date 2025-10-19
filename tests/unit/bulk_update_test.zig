// tests/unit/bulk_update_test.zig
// 批量 UPDATE 功能单元测试

const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");
const Dialect = zorm.Dialect;
const DB = zorm.DB(.postgresql);
const UpdateQuery = zorm.query.UpdateQuery;

// 测试用模型
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    status: []const u8,
    age: i32,

    pub const table_name = "users";
};

test "UpdateQuery: whereIn() SQL generation" {
    const allocator = testing.allocator;

    // 创建 mock DB（仅用于测试 SQL 生成）
    var mock_db = try DB.initMock(allocator);
    defer mock_db.deinit();

    var query = try UpdateQuery(User, .postgresql).init(allocator, &mock_db, "users");
    defer query.deinit();

    const user_ids = [_]i64{ 1, 2, 3, 5, 8 };
    _ = try query.set("status = ?", .{"verified"});
    _ = try query.whereIn("id", &user_ids);

    const sql = try query.build();
    defer allocator.free(sql);

    // 验证 SQL
    try testing.expect(std.mem.containsAtLeast(u8, sql, 1, "UPDATE users"));
    try testing.expect(std.mem.containsAtLeast(u8, sql, 1, "SET status = $1"));
    try testing.expect(std.mem.containsAtLeast(u8, sql, 1, "WHERE id IN ($2, $3, $4, $5, $6)"));
}

test "UpdateQuery: whereNotIn() SQL generation" {
    const allocator = testing.allocator;

    var mock_db = try DB.initMock(allocator);
    defer mock_db.deinit();

    var query = try UpdateQuery(User, .postgresql).init(allocator, &mock_db, "users");
    defer query.deinit();

    const banned_ids = [_]i64{ 99, 100 };
    _ = try query.set("status = ?", .{"banned"});
    _ = try query.whereNotIn("id", &banned_ids);

    const sql = try query.build();
    defer allocator.free(sql);

    // 验证 SQL
    try testing.expect(std.mem.containsAtLeast(u8, sql, 1, "UPDATE users"));
    try testing.expect(std.mem.containsAtLeast(u8, sql, 1, "SET status = $1"));
    try testing.expect(std.mem.containsAtLeast(u8, sql, 1, "WHERE id NOT IN ($2, $3)"));
}

test "UpdateQuery: whereIn() with complex WHERE conditions" {
    const allocator = testing.allocator;

    var mock_db = try DB.initMock(allocator);
    defer mock_db.deinit();

    var query = try UpdateQuery(User, .postgresql).init(allocator, &mock_db, "users");
    defer query.deinit();

    const user_ids = [_]i64{ 1, 2, 3 };
    _ = try query.set("status = ?", .{"active"});
    _ = try query.where("age > ?", .{18});
    _ = try query.whereIn("id", &user_ids);

    const sql = try query.build();
    defer allocator.free(sql);

    // 验证 SQL
    try testing.expect(std.mem.containsAtLeast(u8, sql, 1, "UPDATE users"));
    try testing.expect(std.mem.containsAtLeast(u8, sql, 1, "SET status = $1"));
    try testing.expect(std.mem.containsAtLeast(u8, sql, 1, "WHERE age > $2 AND id IN ($3, $4, $5)"));
}

test "UpdateQuery: whereIn() with OR condition" {
    const allocator = testing.allocator;

    var mock_db = try DB.initMock(allocator);
    defer mock_db.deinit();

    var query = try UpdateQuery(User, .postgresql).init(allocator, &mock_db, "users");
    defer query.deinit();

    const user_ids = [_]i64{ 1, 2 };
    const admin_ids = [_]i64{ 100, 101 };

    _ = try query.set("verified = ?", .{true});
    _ = try query.whereIn("id", &user_ids);
    _ = try query.whereOr("email = ?", .{"admin@example.com"});

    const sql = try query.build();
    defer allocator.free(sql);

    // 验证包含 OR 运算符
    try testing.expect(std.mem.containsAtLeast(u8, sql, 1, "OR"));
    try testing.expect(std.mem.containsAtLeast(u8, sql, 1, "id IN ($2, $3)"));
}

test "UpdateQuery: empty whereIn() returns error" {
    const allocator = testing.allocator;

    var mock_db = try DB.initMock(allocator);
    defer mock_db.deinit();

    var query = try UpdateQuery(User, .postgresql).init(allocator, &mock_db, "users");
    defer query.deinit();

    const empty_ids = [_]i64{};
    _ = try query.set("status = ?", .{"active"});

    // 空数组应该返回错误
    const result = query.whereIn("id", &empty_ids);
    try testing.expectError(error.EmptyWhereIn, result);
}

test "UpdateQuery: whereIn() parameter binding correctness" {
    const allocator = testing.allocator;

    var mock_db = try DB.initMock(allocator);
    defer mock_db.deinit();

    var query = try UpdateQuery(User, .postgresql).init(allocator, &mock_db, "users");
    defer query.deinit();

    const user_ids = [_]i64{ 42, 43, 44 };
    _ = try query.set("age = ?", .{25});
    _ = try query.whereIn("id", &user_ids);

    // 验证参数收集正确
    try testing.expectEqual(@as(usize, 1), query.set_clauses.items.len);
    try testing.expectEqual(@as(usize, 1), query.set_clauses.items[0].args.len);

    try testing.expectEqual(@as(usize, 1), query.where_clauses.items.len);
    try testing.expectEqual(@as(usize, 3), query.where_clauses.items[0].args.len);

    // 验证参数值
    try testing.expectEqual(@as(i64, 25), query.set_clauses.items[0].args[0].int);
    try testing.expectEqual(@as(i64, 42), query.where_clauses.items[0].args[0].int);
    try testing.expectEqual(@as(i64, 43), query.where_clauses.items[0].args[1].int);
    try testing.expectEqual(@as(i64, 44), query.where_clauses.items[0].args[2].int);
}

test "UpdateQuery: multiple whereIn() conditions" {
    const allocator = testing.allocator;

    var mock_db = try DB.initMock(allocator);
    defer mock_db.deinit();

    var query = try UpdateQuery(User, .postgresql).init(allocator, &mock_db, "users");
    defer query.deinit();

    const user_ids = [_]i64{ 1, 2 };
    const age_values = [_]i32{ 18, 25, 30 };

    _ = try query.set("status = ?", .{"active"});
    _ = try query.whereIn("id", &user_ids);
    _ = try query.whereIn("age", &age_values);

    const sql = try query.build();
    defer allocator.free(sql);

    // 验证两个 IN 子句
    try testing.expect(std.mem.containsAtLeast(u8, sql, 1, "id IN ($2, $3)"));
    try testing.expect(std.mem.containsAtLeast(u8, sql, 1, "age IN ($4, $5, $6)"));
}

test "UpdateQuery: whereNotIn() parameter types" {
    const allocator = testing.allocator;

    var mock_db = try DB.initMock(allocator);
    defer mock_db.deinit();

    var query = try UpdateQuery(User, .postgresql).init(allocator, &mock_db, "users");
    defer query.deinit();

    // 测试字符串类型
    const statuses = [_][]const u8{ "banned", "suspended" };
    _ = try query.set("active = ?", .{false});
    _ = try query.whereNotIn("status", &statuses);

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expect(std.mem.containsAtLeast(u8, sql, 1, "WHERE status NOT IN ($2, $3)"));
}

test "UpdateQuery: memory leak detection with whereIn()" {
    const allocator = testing.allocator;

    var mock_db = try DB.initMock(allocator);
    defer mock_db.deinit();

    var query = try UpdateQuery(User, .postgresql).init(allocator, &mock_db, "users");
    defer query.deinit();

    const user_ids = [_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    _ = try query.set("verified = ?", .{true});
    _ = try query.whereIn("id", &user_ids);

    const sql = try query.build();
    defer allocator.free(sql);

    // 测试 allocator 会自动检测内存泄漏
}

test "UpdateQuery: large whereIn() array (100 values)" {
    const allocator = testing.allocator;

    var mock_db = try DB.initMock(allocator);
    defer mock_db.deinit();

    var query = try UpdateQuery(User, .postgresql).init(allocator, &mock_db, "users");
    defer query.deinit();

    // 创建 100 个 ID 的数组
    var ids: [100]i64 = undefined;
    for (&ids, 0..) |*id, i| {
        id.* = @intCast(i + 1);
    }

    _ = try query.set("status = ?", .{"processed"});
    _ = try query.whereIn("id", &ids);

    const sql = try query.build();
    defer allocator.free(sql);

    // 验证生成了 100 个占位符
    var count: usize = 0;
    var i: usize = 0;
    while (i < sql.len) : (i += 1) {
        if (sql[i] == '$') {
            count += 1;
        }
    }
    // SET 有 1 个参数，WHERE IN 有 100 个参数 = 101 个占位符
    try testing.expectEqual(@as(usize, 101), count);
}
