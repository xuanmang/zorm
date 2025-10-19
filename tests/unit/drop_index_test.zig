//! 单元测试: DropIndexQuery - DROP INDEX 查询构建器
//!
//! 测试范围:
//! - 基础 DROP INDEX SQL 生成
//! - IF EXISTS 子句
//! - CASCADE 选项
//! - 参数验证
//! - 内存泄漏检测

const std = @import("std");
const testing = std.testing;
const schema = @import("../../src/schema/schema.zig");
const DropIndexQuery = schema.DropIndexQuery;
const dialect_mod = @import("../../src/dialect/dialect.zig");
const Dialect = dialect_mod.Dialect;

// 测试用的模拟 DB 结构
const MockDB = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MockDB {
        return .{ .allocator = allocator };
    }
};

// 测试用的简单结构体
const User = struct {
    id: i64,
    email: []const u8,

    pub const table_name = "users";
};

test "DropIndexQuery: 基础 DROP INDEX" {
    const allocator = testing.allocator;

    var mock_db = MockDB.init(allocator);
    var query = try DropIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.index("idx_users_email");

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("DROP INDEX idx_users_email", sql);
}

test "DropIndexQuery: IF EXISTS 子句" {
    const allocator = testing.allocator;

    var mock_db = MockDB.init(allocator);
    var query = try DropIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.index("idx_users_email").ifExists();

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("DROP INDEX IF EXISTS idx_users_email", sql);
}

test "DropIndexQuery: CASCADE 选项" {
    const allocator = testing.allocator;

    var mock_db = MockDB.init(allocator);
    var query = try DropIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.index("idx_users_email").cascade();

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("DROP INDEX idx_users_email CASCADE", sql);
}

test "DropIndexQuery: IF EXISTS + CASCADE 组合" {
    const allocator = testing.allocator;

    var mock_db = MockDB.init(allocator);
    var query = try DropIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.index("idx_users_email").ifExists().cascade();

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("DROP INDEX IF EXISTS idx_users_email CASCADE", sql);
}

test "DropIndexQuery: 参数验证 - index_name 必需" {
    const allocator = testing.allocator;

    var mock_db = MockDB.init(allocator);
    var query = try DropIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query.deinit();

    // 不调用 .index() 直接 build 应该失败
    const result = query.build();
    try testing.expectError(error.IndexNameRequired, result);
}

test "DropIndexQuery: 链式调用顺序无关" {
    const allocator = testing.allocator;

    var mock_db = MockDB.init(allocator);

    // 测试不同的链式调用顺序
    var query1 = try DropIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query1.deinit();
    _ = query1.ifExists().index("idx_test").cascade();

    const sql1 = try query1.build();
    defer allocator.free(sql1);

    var query2 = try DropIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query2.deinit();
    _ = query2.cascade().ifExists().index("idx_test");

    const sql2 = try query2.build();
    defer allocator.free(sql2);

    // 不同顺序调用应该生成相同的 SQL
    try testing.expectEqualStrings(sql1, sql2);
    try testing.expectEqualStrings("DROP INDEX IF EXISTS idx_test CASCADE", sql1);
}

test "DropIndexQuery: 内存泄漏检测" {
    const allocator = testing.allocator;

    var mock_db = MockDB.init(allocator);

    // 创建并销毁多个查询,检测内存泄漏
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var query = try DropIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
        defer query.deinit();

        _ = query.index("idx_test").ifExists().cascade();

        const sql = try query.build();
        defer allocator.free(sql);

        try testing.expect(sql.len > 0);
    }

    // testing.allocator 会自动检测内存泄漏
}

test "DropIndexQuery: 不同索引名称" {
    const allocator = testing.allocator;

    var mock_db = MockDB.init(allocator);

    const test_cases = [_]struct {
        name: []const u8,
        expected: []const u8,
    }{
        .{ .name = "idx_users_email", .expected = "DROP INDEX idx_users_email" },
        .{ .name = "idx_posts_author", .expected = "DROP INDEX idx_posts_author" },
        .{ .name = "unique_username_idx", .expected = "DROP INDEX unique_username_idx" },
    };

    for (test_cases) |tc| {
        var query = try DropIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
        defer query.deinit();

        _ = query.index(tc.name);

        const sql = try query.build();
        defer allocator.free(sql);

        try testing.expectEqualStrings(tc.expected, sql);
    }
}

test "DropIndexQuery: exec() 参数验证" {
    const allocator = testing.allocator;

    var mock_db = MockDB.init(allocator);
    var query = try DropIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query.deinit();

    // 不设置 index_name 直接 exec 应该失败
    const result = query.exec();
    try testing.expectError(error.IndexNameRequired, result);
}
