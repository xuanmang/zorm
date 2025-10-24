const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");
const Dialect = zorm.Dialect;
const query_mod = @import("zorm").query;

// 测试模型
const User = struct {
    id: i32,
    email: []const u8,
    username: []const u8,
    created_at: i64,

    pub const table_name = "users";
};

// 创建测试用的 CreateIndexQuery 实例
const CreateIndexQuery = query_mod.CreateIndexQuery(User, Dialect.postgresql);
const DBType = zorm.DB(Dialect.postgresql);

// ==================== 基本功能测试 ====================

test "CreateIndexQuery - index() 方法设置索引名称" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");

    try testing.expectEqualStrings("idx_users_email", query.index_name.?);
}

test "CreateIndexQuery - column() 方法添加单列" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = try query.column("email");

    try testing.expectEqual(@as(usize, 1), query.columns.items.len);
    try testing.expectEqualStrings("email", query.columns.items[0]);
}

test "CreateIndexQuery - column() 方法添加多列（复合索引）" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = try query.column("email");
    _ = try query.column("username");

    try testing.expectEqual(@as(usize, 2), query.columns.items.len);
    try testing.expectEqualStrings("email", query.columns.items[0]);
    try testing.expectEqualStrings("username", query.columns.items[1]);
}

test "CreateIndexQuery - unique() 方法设置唯一索引标志" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    try testing.expect(!query.unique_flag);

    _ = query.unique();

    try testing.expect(query.unique_flag);
}

test "CreateIndexQuery - ifNotExists() 方法设置标志" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    try testing.expect(!query.if_not_exists_flag);

    _ = query.ifNotExists();

    try testing.expect(query.if_not_exists_flag);
}

test "CreateIndexQuery - where() 方法设置部分索引条件" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    try testing.expect(query.where_condition == null);

    _ = query.where("email IS NOT NULL");

    try testing.expectEqualStrings("email IS NOT NULL", query.where_condition.?);
}

test "CreateIndexQuery - 链式调用组合" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email_unique");
    _ = try query.column("email");
    _ = query.unique();
    _ = query.ifNotExists();
    _ = query.where("email IS NOT NULL");

    try testing.expectEqualStrings("idx_users_email_unique", query.index_name.?);
    try testing.expectEqual(@as(usize, 1), query.columns.items.len);
    try testing.expect(query.unique_flag);
    try testing.expect(query.if_not_exists_flag);
    try testing.expectEqualStrings("email IS NOT NULL", query.where_condition.?);
}

// ==================== SQL 生成测试 ====================

test "CreateIndexQuery - 生成基本索引 SQL（单列）" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");
    _ = try query.column("email");

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX idx_users_email ON users (email)", sql);
}

test "CreateIndexQuery - 生成复合索引 SQL（多列）" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email_username");
    _ = try query.column("email");
    _ = try query.column("username");

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX idx_users_email_username ON users (email, username)", sql);
}

test "CreateIndexQuery - 生成唯一索引 SQL（包含 UNIQUE 关键字）" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email_unique");
    _ = try query.column("email");
    _ = query.unique();

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("CREATE UNIQUE INDEX idx_users_email_unique ON users (email)", sql);
}

test "CreateIndexQuery - 生成 IF NOT EXISTS SQL" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");
    _ = try query.column("email");
    _ = query.ifNotExists();

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX IF NOT EXISTS idx_users_email ON users (email)", sql);
}

test "CreateIndexQuery - 生成部分索引 SQL（包含 WHERE 子句）" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email_active");
    _ = try query.column("email");
    _ = query.where("email IS NOT NULL");

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX idx_users_email_active ON users (email) WHERE email IS NOT NULL", sql);
}

test "CreateIndexQuery - 生成表达式索引 SQL（如 LOWER(email)）" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email_lower");
    _ = try query.column("LOWER(email)");

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX idx_users_email_lower ON users (LOWER(email))", sql);
}

test "CreateIndexQuery - 生成组合场景 SQL（唯一 + IF NOT EXISTS + WHERE）" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email_unique_active");
    _ = try query.column("email");
    _ = query.unique();
    _ = query.ifNotExists();
    _ = query.where("email IS NOT NULL");

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_unique_active ON users (email) WHERE email IS NOT NULL", sql);
}

test "CreateIndexQuery - 生成复合表达式索引 SQL" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_fulltext");
    _ = try query.column("LOWER(email)");
    _ = try query.column("LOWER(username)");

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX idx_users_fulltext ON users (LOWER(email), LOWER(username))", sql);
}

// ==================== 错误处理测试 ====================

test "CreateIndexQuery - 未设置索引名称时返回 error.IndexNameRequired" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = try query.column("email");

    const result = query.build();
    try testing.expectError(error.IndexNameRequired, result);
}

test "CreateIndexQuery - 未添加列时返回 error.ColumnsRequired" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_test");

    const result = query.build();
    try testing.expectError(error.ColumnsRequired, result);
}

test "CreateIndexQuery - 资源释放正确清理内存（检测内存泄漏）" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);

    _ = query.index("idx_test");
    _ = try query.column("email");
    _ = try query.column("username");
    _ = query.unique();
    _ = query.ifNotExists();
    _ = query.where("email IS NOT NULL");

    // 正常释放资源
    query.deinit();

    // 如果有内存泄漏，testing.allocator 会报告
}

test "CreateIndexQuery - deinit() 在多次 column() 调用后正确清理" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try CreateIndexQuery.init(allocator, &mock_db);

    _ = try query.column("col1");
    _ = try query.column("col2");
    _ = try query.column("col3");
    _ = try query.column("col4");
    _ = try query.column("col5");

    query.deinit();

    // 验证无内存泄漏
}
