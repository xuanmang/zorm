const std = @import("std");
const testing = std.testing;

const query_mod = @import("../../src/query/query.zig");
const DropTableQuery = query_mod.DropTableQuery;
const Dialect = @import("../../src/dialect/dialect.zig").Dialect;

// 测试用模型定义
const User = struct {
    id: i64,
    name: []const u8,
    email: ?[]const u8,

    pub const table_name = "users";
};

const Product = struct {
    id: i64,
    title: []const u8,
    // 没有 table_name,使用类型名
};

// Mock DB 结构体用于测试
const MockDB = struct {
    allocator: std.mem.Allocator,

    pub fn exec(_: *@This(), _: []const u8, _: []const @import("../../src/core/types.zig").QueryArg) !void {
        // Mock 实现,不执行真实数据库操作
    }
};

test "DropTableQuery: 基础 DROP TABLE SQL 生成" {
    var mock_db = MockDB{ .allocator = testing.allocator };

    var query = try DropTableQuery(User, .postgresql).init(testing.allocator, @ptrCast(&mock_db));
    defer query.deinit();

    const sql = try query.build();
    defer testing.allocator.free(sql);

    try testing.expectEqualStrings("DROP TABLE users", sql);
}

test "DropTableQuery: 使用类型名作为表名" {
    var mock_db = MockDB{ .allocator = testing.allocator };

    var query = try DropTableQuery(Product, .postgresql).init(testing.allocator, @ptrCast(&mock_db));
    defer query.deinit();

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 类型名包含完整路径,应该包含 "Product"
    try testing.expect(std.mem.indexOf(u8, sql, "Product") != null);
}

test "DropTableQuery: IF EXISTS 子句" {
    var mock_db = MockDB{ .allocator = testing.allocator };

    var query = try DropTableQuery(User, .postgresql).init(testing.allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.ifExists();

    const sql = try query.build();
    defer testing.allocator.free(sql);

    try testing.expectEqualStrings("DROP TABLE IF EXISTS users", sql);
}

test "DropTableQuery: CASCADE 选项" {
    var mock_db = MockDB{ .allocator = testing.allocator };

    var query = try DropTableQuery(User, .postgresql).init(testing.allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.cascade();

    const sql = try query.build();
    defer testing.allocator.free(sql);

    try testing.expectEqualStrings("DROP TABLE users CASCADE", sql);
}

test "DropTableQuery: RESTRICT 选项" {
    var mock_db = MockDB{ .allocator = testing.allocator };

    var query = try DropTableQuery(User, .postgresql).init(testing.allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.restrict();

    const sql = try query.build();
    defer testing.allocator.free(sql);

    try testing.expectEqualStrings("DROP TABLE users RESTRICT", sql);
}

test "DropTableQuery: IF EXISTS + CASCADE" {
    var mock_db = MockDB{ .allocator = testing.allocator };

    var query = try DropTableQuery(User, .postgresql).init(testing.allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.ifExists().cascade();

    const sql = try query.build();
    defer testing.allocator.free(sql);

    try testing.expectEqualStrings("DROP TABLE IF EXISTS users CASCADE", sql);
}

test "DropTableQuery: IF EXISTS + RESTRICT" {
    var mock_db = MockDB{ .allocator = testing.allocator };

    var query = try DropTableQuery(User, .postgresql).init(testing.allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.ifExists().restrict();

    const sql = try query.build();
    defer testing.allocator.free(sql);

    try testing.expectEqualStrings("DROP TABLE IF EXISTS users RESTRICT", sql);
}

test "DropTableQuery: CASCADE 和 RESTRICT 互斥性 - CASCADE 优先" {
    var mock_db = MockDB{ .allocator = testing.allocator };

    var query = try DropTableQuery(User, .postgresql).init(testing.allocator, @ptrCast(&mock_db));
    defer query.deinit();

    // 先设置 RESTRICT,再设置 CASCADE
    _ = query.restrict();
    _ = query.cascade(); // 应该覆盖 RESTRICT

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 只包含 CASCADE,不包含 RESTRICT
    try testing.expectEqualStrings("DROP TABLE users CASCADE", sql);
}

test "DropTableQuery: CASCADE 和 RESTRICT 互斥性 - RESTRICT 优先" {
    var mock_db = MockDB{ .allocator = testing.allocator };

    var query = try DropTableQuery(User, .postgresql).init(testing.allocator, @ptrCast(&mock_db));
    defer query.deinit();

    // 先设置 CASCADE,再设置 RESTRICT
    _ = query.cascade();
    _ = query.restrict(); // 应该覆盖 CASCADE

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 只包含 RESTRICT,不包含 CASCADE
    try testing.expectEqualStrings("DROP TABLE users RESTRICT", sql);
}

test "DropTableQuery: 链式调用" {
    var mock_db = MockDB{ .allocator = testing.allocator };

    var query = try DropTableQuery(User, .postgresql).init(testing.allocator, @ptrCast(&mock_db));
    defer query.deinit();

    // 测试链式调用返回 self
    const q1 = query.ifExists();
    const q2 = q1.cascade();

    try testing.expectEqual(query, q1);
    try testing.expectEqual(query, q2);
}

test "DropTableQuery: 内存泄漏检测" {
    var mock_db = MockDB{ .allocator = testing.allocator };

    var query = try DropTableQuery(User, .postgresql).init(testing.allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.ifExists().cascade();

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 如果有内存泄漏,testing.allocator 会自动检测并报告
}
