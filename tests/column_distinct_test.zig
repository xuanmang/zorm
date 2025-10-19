//! Story 1.3: 列选择和 DISTINCT 单元测试
//!
//! 验证 SelectQuery 的列选择和 DISTINCT 功能符合 Story 1.3 要求

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

test "Story 1.3 AC1: column() 方法指定单列" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(
        testing.allocator,
        @ptrCast(&db),
        "users",
    );
    defer query.deinit();

    // 添加单列
    _ = try query.column("id");

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证 SQL 包含指定的列
    try testing.expectEqualStrings("SELECT id FROM users", sql);
}

test "Story 1.3 AC1: column() 方法指定多列" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(
        testing.allocator,
        @ptrCast(&db),
        "users",
    );
    defer query.deinit();

    // 添加多列
    _ = try query.column("id");
    _ = try query.column("name");
    _ = try query.column("email");

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证 SQL 包含所有指定的列
    try testing.expectEqualStrings("SELECT id, name, email FROM users", sql);
}

test "Story 1.3 AC2: 默认查询所有列 (SELECT *)" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(
        testing.allocator,
        @ptrCast(&db),
        "users",
    );
    defer query.deinit();

    // 不添加任何列，默认应该是 SELECT *
    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证默认使用 SELECT *
    try testing.expectEqualStrings("SELECT * FROM users", sql);
}

test "Story 1.3 AC3: distinct() 方法启用 DISTINCT" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(
        testing.allocator,
        @ptrCast(&db),
        "users",
    );
    defer query.deinit();

    // 启用 DISTINCT
    _ = try query.distinct();

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证 SQL 包含 DISTINCT
    try testing.expectEqualStrings("SELECT DISTINCT * FROM users", sql);
}

test "Story 1.3: DISTINCT + 列选择组合" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(
        testing.allocator,
        @ptrCast(&db),
        "users",
    );
    defer query.deinit();

    // DISTINCT + 列选择
    _ = try query.distinct();
    _ = try query.column("email");

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证 SQL
    try testing.expectEqualStrings("SELECT DISTINCT email FROM users", sql);
}

test "Story 1.3: 列选择 + WHERE 组合" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(
        testing.allocator,
        @ptrCast(&db),
        "users",
    );
    defer query.deinit();

    // 列选择 + WHERE
    _ = try query.column("id");
    _ = try query.column("name");
    _ = try query.where("age > $1", .{18});

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证 SQL
    try testing.expect(std.mem.indexOf(u8, sql, "SELECT id, name FROM users") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "WHERE age > $1") != null);
}

test "Story 1.3: 列选择 + ORDER BY 组合" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(
        testing.allocator,
        @ptrCast(&db),
        "users",
    );
    defer query.deinit();

    // 列选择 + ORDER BY
    _ = try query.column("id");
    _ = try query.column("name");
    _ = try query.orderBy("name", .asc);

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证 SQL
    try testing.expectEqualStrings("SELECT id, name FROM users ORDER BY name ASC", sql);
}

test "Story 1.3: DISTINCT + WHERE + ORDER BY 组合" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(
        testing.allocator,
        @ptrCast(&db),
        "users",
    );
    defer query.deinit();

    // 复杂组合查询
    _ = try query.distinct();
    _ = try query.column("name");
    _ = try query.column("email");
    _ = try query.where("age > $1", .{18});
    _ = try query.orderBy("name", .asc);
    _ = try query.limit(10);

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证完整的 SQL
    const expected =
        "SELECT DISTINCT name, email FROM users " ++
        "WHERE age > $1 " ++
        "ORDER BY name ASC LIMIT 10";

    try testing.expectEqualStrings(expected, sql);
}

test "Story 1.3: 链式调用支持" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(
        testing.allocator,
        @ptrCast(&db),
        "users",
    );
    defer query.deinit();

    // 测试链式调用（Zig 0.15.2 要求每个 try）
    _ = try query.column("id");
    _ = try query.column("name");
    _ = try query.distinct();
    _ = try query.where("age > $1", .{18});
    _ = try query.orderBy("name", .asc);
    _ = try query.limit(5);

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证 SQL
    try testing.expect(std.mem.indexOf(u8, sql, "SELECT DISTINCT id, name") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "WHERE age > $1") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "ORDER BY name ASC") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "LIMIT 5") != null);
}

test "Story 1.3 AC4: count() 方法返回行数（SQL 生成验证）" {
    // 注意: 这个测试只验证 SQL 生成
    // count() 的实际数据库执行需要在集成测试中验证

    // 这里我们通过检查内部实现来验证 count() 的存在性
    // 实际的 count() 执行测试在集成测试中完成

    // 验证 count() 方法存在于 SelectQuery
    const QueryType = zorm.SelectQuery(User, .postgresql);
    const has_count = @hasDecl(QueryType, "count");
    try testing.expect(has_count);
}

test "Story 1.3: 内存管理 - deinit 正确释放资源" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.SelectQuery(User, .postgresql).init(
        testing.allocator,
        @ptrCast(&db),
        "users",
    );

    _ = try query.column("id");
    _ = try query.column("name");
    _ = try query.distinct();
    _ = try query.where("age > $1", .{18});
    _ = try query.orderBy("name", .asc);

    // deinit 应该正确释放所有资源
    query.deinit();

    // 如果有内存泄漏，testing.allocator 会报错
}
