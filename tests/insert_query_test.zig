//! InsertQuery 单元测试
//!
//! 验证 InsertQuery 的所有功能符合 Story 1.4 要求

const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");

// 测试用的用户模型
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: ?i32,

    pub const table_name = "users";
};

// Mock DB 用于测试
const MockDB = struct {
    allocator: std.mem.Allocator,
};

test "Story 1.4 AC1: InsertQuery 基本实例化" {
    const PostgresQuery = zorm.InsertQuery(User, .postgresql);
    const MySQLQuery = zorm.InsertQuery(User, .mysql);

    // 验证它们是不同的类型
    try testing.expect(PostgresQuery != MySQLQuery);
}

test "Story 1.4 AC2: value() 方法设置单行数据" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    // 添加单行数据
    _ = try query.value(.{
        .id = 1,
        .name = "Alice",
        .email = "alice@example.com",
        .age = 25,
    });

    // 验证列名和值被正确设置
    try testing.expectEqual(@as(usize, 4), query.columns.items.len);
    try testing.expectEqual(@as(usize, 1), query.values_list.items.len);
    try testing.expectEqualStrings("id", query.columns.items[0]);
    try testing.expectEqualStrings("name", query.columns.items[1]);
}

test "Story 1.4 AC6: 生成正确的 INSERT SQL" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.value(.{
        .id = 1,
        .name = "Alice",
        .email = "alice@example.com",
        .age = 25,
    });

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证 SQL 格式正确
    try testing.expectEqualStrings(
        "INSERT INTO users (id, name, email, age) VALUES ($1, $2, $3, $4)",
        sql,
    );
}

test "Story 1.4 AC6: PostgreSQL 占位符 $1, $2, $3" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.value(.{
        .id = 1,
        .name = "Alice",
        .email = "alice@example.com",
        .age = 25,
    });

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证使用 PostgreSQL 占位符
    try testing.expect(std.mem.indexOf(u8, sql, "$1") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "$2") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "$3") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "$4") != null);
}

test "Story 1.4 AC6: MySQL 占位符 ?" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .mysql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.value(.{
        .id = 1,
        .name = "Alice",
        .email = "alice@example.com",
        .age = 25,
    });

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证使用 MySQL 占位符
    try testing.expect(std.mem.indexOf(u8, sql, "?") != null);
    // 不应该包含 PostgreSQL 占位符
    try testing.expect(std.mem.indexOf(u8, sql, "$1") == null);
}

test "Story 1.4: NULL 值处理" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.value(.{
        .id = 1,
        .name = "Bob",
        .email = "bob@example.com",
        .age = null, // NULL 值
    });

    // 验证参数中包含 null
    try testing.expectEqual(@as(usize, 1), query.values_list.items.len);
    const args = query.values_list.items[0];
    try testing.expectEqual(@as(usize, 4), args.len);
    try testing.expect(args[3] == .null_val);
}

test "Story 1.4 AC4: returning() 方法设置 RETURNING (PostgreSQL)" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.value(.{
        .id = 1,
        .name = "Alice",
        .email = "alice@example.com",
        .age = 25,
    });

    _ = try query.returning(&.{ "id", "email" });

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证包含 RETURNING 子句
    try testing.expect(std.mem.indexOf(u8, sql, "RETURNING id, email") != null);
}

test "Story 1.4 AC4: RETURNING * (PostgreSQL)" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.value(.{
        .id = 1,
        .name = "Alice",
        .email = "alice@example.com",
        .age = 25,
    });

    _ = try query.returning(&.{"*"});

    const sql = try query.build();
    defer testing.allocator.free(sql);

    try testing.expect(std.mem.indexOf(u8, sql, "RETURNING *") != null);
}

test "InsertQuery: 批量插入 SQL 生成" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    const users = [_]@TypeOf(.{
        .id = @as(i64, 0),
        .name = @as([]const u8, ""),
        .email = @as([]const u8, ""),
        .age = @as(?i32, null),
    }){
        .{ .id = 1, .name = "Alice", .email = "alice@example.com", .age = 25 },
        .{ .id = 2, .name = "Bob", .email = "bob@example.com", .age = 30 },
    };

    _ = try query.values(&users);

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证包含多个 VALUES 子句
    try testing.expect(std.mem.indexOf(u8, sql, "VALUES ($1, $2, $3, $4), ($5, $6, $7, $8)") != null);
}

test "InsertQuery: ON CONFLICT DO NOTHING (PostgreSQL)" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.value(.{
        .id = 1,
        .name = "Alice",
        .email = "alice@example.com",
        .age = 25,
    });

    _ = try query.onConflict(.{
        .columns = &.{"email"},
        .action = .do_nothing,
        .update_columns = null,
    });

    const sql = try query.build();
    defer testing.allocator.free(sql);

    try testing.expect(std.mem.indexOf(u8, sql, "ON CONFLICT (email) DO NOTHING") != null);
}

test "InsertQuery: ON CONFLICT DO UPDATE (PostgreSQL)" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    _ = try query.value(.{
        .id = 1,
        .name = "Alice",
        .email = "alice@example.com",
        .age = 25,
    });

    _ = try query.onConflict(.{
        .columns = &.{"email"},
        .action = .do_update,
        .update_columns = &.{ "name", "age" },
    });

    const sql = try query.build();
    defer testing.allocator.free(sql);

    try testing.expect(std.mem.indexOf(u8, sql, "ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name, age = EXCLUDED.age") != null);
}

test "Story 1.4 AC3: InsertResult 结构" {
    const result = zorm.InsertResult{
        .rows_affected = 1,
        .last_insert_id = 42,
    };

    try testing.expectEqual(@as(usize, 1), result.rows_affected);
    try testing.expectEqual(@as(?i64, 42), result.last_insert_id);
}

test "Story 1.4 AC3: InsertResult NULL last_insert_id" {
    const result = zorm.InsertResult{
        .rows_affected = 5,
        .last_insert_id = null,
    };

    try testing.expectEqual(@as(usize, 5), result.rows_affected);
    try testing.expectEqual(@as(?i64, null), result.last_insert_id);
}
