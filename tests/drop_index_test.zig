const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");
const Dialect = zorm.Dialect;
const schema_mod = @import("zorm").schema;

// 测试模型
const User = struct {
    id: i32,
    email: []const u8,
    username: []const u8,
    created_at: i64,

    pub const table_name = "users";
};

// 创建测试用的 DropIndexQuery 实例
const DropIndexQuery = schema_mod.DropIndexQuery(User, Dialect.postgresql);
const DBType = zorm.DB(Dialect.postgresql);

// ==================== 基本功能测试 ====================

test "DropIndexQuery - init() 正确初始化" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    try testing.expect(query.index_name == null);
    try testing.expect(!query.if_exists_flag);
    try testing.expect(!query.cascade_flag);
    try testing.expect(!query.restrict_flag);
}

test "DropIndexQuery - index() 方法设置索引名称" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");

    try testing.expectEqualStrings("idx_users_email", query.index_name.?);
}

test "DropIndexQuery - ifExists() 方法设置标志" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    try testing.expect(!query.if_exists_flag);

    _ = query.ifExists();

    try testing.expect(query.if_exists_flag);
}

test "DropIndexQuery - cascade() 方法设置标志" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    try testing.expect(!query.cascade_flag);

    _ = query.cascade();

    try testing.expect(query.cascade_flag);
}

test "DropIndexQuery - restrict() 方法设置标志" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    try testing.expect(!query.restrict_flag);

    _ = query.restrict();

    try testing.expect(query.restrict_flag);
}

test "DropIndexQuery - 链式调用组合" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email")
        .ifExists()
        .cascade();

    try testing.expectEqualStrings("idx_users_email", query.index_name.?);
    try testing.expect(query.if_exists_flag);
    try testing.expect(query.cascade_flag);
}

// ==================== CASCADE/RESTRICT 互斥逻辑测试 ====================

test "DropIndexQuery - cascade() 后调用 restrict() 应覆盖" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.cascade();
    try testing.expect(query.cascade_flag);
    try testing.expect(!query.restrict_flag);

    _ = query.restrict();
    try testing.expect(!query.cascade_flag);
    try testing.expect(query.restrict_flag);
}

test "DropIndexQuery - restrict() 后调用 cascade() 应覆盖" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.restrict();
    try testing.expect(query.restrict_flag);
    try testing.expect(!query.cascade_flag);

    _ = query.cascade();
    try testing.expect(query.cascade_flag);
    try testing.expect(!query.restrict_flag);
}

test "DropIndexQuery - 多次调用 cascade() 保持状态" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.cascade();
    _ = query.cascade();

    try testing.expect(query.cascade_flag);
    try testing.expect(!query.restrict_flag);
}

test "DropIndexQuery - 多次调用 restrict() 保持状态" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.restrict();
    _ = query.restrict();

    try testing.expect(query.restrict_flag);
    try testing.expect(!query.cascade_flag);
}

// ==================== SQL 生成测试 ====================

test "DropIndexQuery - 生成基本 DROP INDEX SQL" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("DROP INDEX idx_users_email", sql);
}

test "DropIndexQuery - 生成带 IF EXISTS 的 SQL" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");
    _ = query.ifExists();

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("DROP INDEX IF EXISTS idx_users_email", sql);
}

test "DropIndexQuery - 生成带 CASCADE 的 SQL" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");
    _ = query.cascade();

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("DROP INDEX idx_users_email CASCADE", sql);
}

test "DropIndexQuery - 生成带 RESTRICT 的 SQL" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");
    _ = query.restrict();

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("DROP INDEX idx_users_email RESTRICT", sql);
}

test "DropIndexQuery - 生成 IF EXISTS + CASCADE 组合 SQL" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");
    _ = query.ifExists();
    _ = query.cascade();

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("DROP INDEX IF EXISTS idx_users_email CASCADE", sql);
}

test "DropIndexQuery - 生成 IF EXISTS + RESTRICT 组合 SQL" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");
    _ = query.ifExists();
    _ = query.restrict();

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("DROP INDEX IF EXISTS idx_users_email RESTRICT", sql);
}

test "DropIndexQuery - CASCADE/RESTRICT 互斥: 先 cascade 后 restrict 只生成 RESTRICT" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");
    _ = query.cascade();
    _ = query.restrict();

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("DROP INDEX idx_users_email RESTRICT", sql);
}

test "DropIndexQuery - CASCADE/RESTRICT 互斥: 先 restrict 后 cascade 只生成 CASCADE" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");
    _ = query.restrict();
    _ = query.cascade();

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("DROP INDEX idx_users_email CASCADE", sql);
}

// ==================== 错误处理测试 ====================

test "DropIndexQuery - 未设置索引名称时 build() 返回 error.IndexNameRequired" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    const result = query.build();
    try testing.expectError(error.IndexNameRequired, result);
}

test "DropIndexQuery - 未设置索引名称时 exec() 返回 error.IndexNameRequired" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    const result = query.exec();
    try testing.expectError(error.IndexNameRequired, result);
}

// ==================== 资源管理测试 ====================

test "DropIndexQuery - 资源释放正确清理内存（检测内存泄漏）" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);

    _ = query.index("idx_test");
    _ = query.ifExists();
    _ = query.cascade();

    // 正常释放资源
    query.deinit();

    // 如果有内存泄漏，testing.allocator 会报告
}

test "DropIndexQuery - 多次链式调用后正确清理" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);

    _ = query.index("idx_test")
        .ifExists()
        .cascade()
        .restrict()
        .cascade();

    query.deinit();

    // 验证无内存泄漏
}

// ==================== PRD 示例代码验证测试 ====================

test "DropIndexQuery - PRD AC3.5.6 示例: 基本删除索引" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");

    const sql = try query.build();
    defer allocator.free(sql);

    // 预期 SQL: DROP INDEX idx_users_email
    try testing.expectEqualStrings("DROP INDEX idx_users_email", sql);
}

test "DropIndexQuery - PRD AC3.5.6 示例: 幂等删除（IF EXISTS）" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");
    _ = query.ifExists();

    const sql = try query.build();
    defer allocator.free(sql);

    // 预期 SQL: DROP INDEX IF EXISTS idx_users_email
    try testing.expectEqualStrings("DROP INDEX IF EXISTS idx_users_email", sql);
}

test "DropIndexQuery - PRD AC3.5.6 示例: 级联删除（CASCADE）" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");
    _ = query.ifExists();
    _ = query.cascade();

    const sql = try query.build();
    defer allocator.free(sql);

    // 预期 SQL: DROP INDEX IF EXISTS idx_users_email CASCADE
    try testing.expectEqualStrings("DROP INDEX IF EXISTS idx_users_email CASCADE", sql);
}

test "DropIndexQuery - PRD AC3.5.6 示例: 限制删除（RESTRICT）" {
    const allocator = testing.allocator;
    var mock_db: DBType = undefined;

    var query = try DropIndexQuery.init(allocator, &mock_db);
    defer query.deinit();

    _ = query.index("idx_users_email");
    _ = query.restrict();

    const sql = try query.build();
    defer allocator.free(sql);

    // 预期 SQL: DROP INDEX idx_users_email RESTRICT
    try testing.expectEqualStrings("DROP INDEX idx_users_email RESTRICT", sql);
}
