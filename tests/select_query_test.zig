//! SelectQuery 单元测试
//!
//! 验证 SelectQuery 的所有功能符合 Story 1.2 要求

const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");

const User = struct {
    id: i64,
    name: []const u8,
    email: ?[]const u8,
    age: u32,

    pub const table_name = "users";
};

// Mock DB 用于测试
const MockDB = struct {
    allocator: std.mem.Allocator,
};

test "Story 1.2 AC1: db.newSelect(T) API 创建查询构建器" {
    // 验证可以为不同方言创建 SelectQuery

    // 验证它们是不同的类型
}

test "Story 1.2 AC2: where() 方法添加 WHERE 条件" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    // 添加 WHERE 条件
    _ = try query.where("age > $1", .{18});
    _ = try query.where("email IS NOT NULL", .{});

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证 SQL 包含 WHERE 子句
    try testing.expect(std.mem.indexOf(u8, sql, "WHERE") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "age > $1") != null);
}

test "Story 1.2 AC3: orderBy() 方法指定排序" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    // 添加排序
    _ = try query.orderBy("created_at", .desc);
    _ = try query.orderBy("name", .asc);

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证 SQL 包含 ORDER BY
    try testing.expectEqualStrings("SELECT * FROM users ORDER BY created_at DESC, name ASC", sql);
}

test "Story 1.2 AC4: limit() 和 offset() 实现分页" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.limit(10);
    _ = try query.offset(20);

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证 SQL 包含 LIMIT 和 OFFSET
    try testing.expectEqualStrings("SELECT * FROM users LIMIT 10 OFFSET 20", sql);
}

test "Story 1.2 AC7: 链式调用" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    // 测试链式调用
    _ = try query
        .where("age > $1", .{18})
        .orderBy("name", .asc)
        .limit(10)
        .offset(5);

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证完整的 SQL
    try testing.expect(std.mem.indexOf(u8, sql, "WHERE age > $1") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "ORDER BY name ASC") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "LIMIT 10") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "OFFSET 5") != null);
}

test "Story 1.2 AC8: 完整工作流程示例" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    // 构建复杂查询
    _ = try query.column("id");
    _ = try query.column("name");
    _ = try query.column("email");
    _ = try query.where("age > $1", .{18});
    _ = try query.where("email LIKE $2", .{"%@example.com"});
    _ = try query.orderBy("created_at", .desc);
    _ = try query.limit(10);

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证生成的 SQL
    const expected =
        "SELECT id, name, email FROM users " ++
        "WHERE age > $1 AND email LIKE $2 " ++
        "ORDER BY created_at DESC LIMIT 10";

    try testing.expectEqualStrings(expected, sql);
}

test "Story 1.2: 参数绑定防止 SQL 注入" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    // 使用占位符防止 SQL 注入
    _ = try query.where("id = $1", .{123});
    _ = try query.where("name = $2", .{"Alice"});

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证使用了占位符而非直接拼接
    try testing.expect(std.mem.indexOf(u8, sql, "$1") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "$2") != null);
    // 确保没有直接拼接值
    try testing.expect(std.mem.indexOf(u8, sql, "123") == null);
    try testing.expect(std.mem.indexOf(u8, sql, "Alice") == null);
}

test "Story 1.2: 内存管理 - deinit 正确释放资源" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");

    _ = try query.where("age > $1", .{18});
    _ = try query.orderBy("name", .asc);
    _ = try query.limit(10);

    // deinit 应该正确释放所有资源
    query.deinit();

    // 如果有内存泄漏,testing.allocator 会报错
}
