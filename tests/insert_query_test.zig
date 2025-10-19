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

    const users = [_]User{
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

// ============================================
// Story 1.5: Batch INSERT Support Tests
// ============================================

test "Story 1.5 AC1: values() 批量插入 5 行" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    const users = [_]User{
        .{ .id = 1, .name = "Alice", .email = "alice@example.com", .age = 25 },
        .{ .id = 2, .name = "Bob", .email = "bob@example.com", .age = 30 },
        .{ .id = 3, .name = "Carol", .email = "carol@example.com", .age = 28 },
        .{ .id = 4, .name = "David", .email = "david@example.com", .age = 35 },
        .{ .id = 5, .name = "Eve", .email = "eve@example.com", .age = 22 },
    };

    _ = try query.values(&users);

    // 验证 values_list 包含 5 行
    try testing.expectEqual(@as(usize, 5), query.values_list.items.len);
}

test "Story 1.5 AC2: 批量插入生成单条 SQL 语句" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    const users = [_]User{
        .{ .id = 1, .name = "Alice", .email = "alice@example.com", .age = 25 },
        .{ .id = 2, .name = "Bob", .email = "bob@example.com", .age = 30 },
        .{ .id = 3, .name = "Carol", .email = "carol@example.com", .age = 28 },
    };

    _ = try query.values(&users);
    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证是单条 SQL 语句(包含 3 组 VALUES)
    const expected = "INSERT INTO users (id, name, email, age) VALUES ($1, $2, $3, $4), ($5, $6, $7, $8), ($9, $10, $11, $12)";
    try testing.expectEqualStrings(expected, sql);
}

test "Story 1.5 AC2: PostgreSQL 占位符连续递增" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    const users = [_]User{
        .{ .id = 1, .name = "Alice", .email = "alice@example.com", .age = 25 },
        .{ .id = 2, .name = "Bob", .email = "bob@example.com", .age = 30 },
    };

    _ = try query.values(&users);
    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证占位符连续递增: $1, $2, ..., $8
    try testing.expect(std.mem.indexOf(u8, sql, "$1") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "$2") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "$3") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "$4") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "$5") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "$6") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "$7") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "$8") != null);
}

test "Story 1.5 AC3: 批量插入支持 RETURNING" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    const users = [_]User{
        .{ .id = 1, .name = "Alice", .email = "alice@example.com", .age = 25 },
        .{ .id = 2, .name = "Bob", .email = "bob@example.com", .age = 30 },
    };

    _ = try query.values(&users);
    _ = try query.returning(&.{"*"});

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证包含 RETURNING 子句
    try testing.expect(std.mem.indexOf(u8, sql, "RETURNING *") != null);
}

test "Story 1.5: 批量插入 10 行" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    var users: [10]User = undefined;
    for (&users, 0..) |*user, i| {
        user.* = User{
            .id = @intCast(i + 1),
            .name = "User",
            .email = "user@example.com",
            .age = 25,
        };
    }

    _ = try query.values(&users);
    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证包含 10 组 VALUES
    // 计算逗号分隔的 VALUES 数量
    var count: usize = 1; // 至少有 1 组
    var idx: usize = 0;
    while (std.mem.indexOfPos(u8, sql, idx, "), (")) |pos| {
        count += 1;
        idx = pos + 1;
    }
    try testing.expectEqual(@as(usize, 10), count);
}

test "Story 1.5: 批量大小限制检查" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    // 创建超过限制的批量数据 (> 1000)
    const large_batch = try testing.allocator.alloc(User, 1001);
    defer testing.allocator.free(large_batch);

    for (large_batch, 0..) |*user, i| {
        user.* = User{
            .id = @intCast(i + 1),
            .name = "User",
            .email = "user@example.com",
            .age = 25,
        };
    }

    // 应返回 BatchSizeTooLarge 错误
    try testing.expectError(error.BatchSizeTooLarge, query.values(large_batch));
}

test "Story 1.5: PostgreSQL 参数限制检查" {
    // 创建一个有 70 个字段的类型
    // 70 字段 x 950 行 = 66500 参数 > 65535
    // 但 950 行 < 1000,所以不会触发批量大小限制
    const LargeUser = struct {
        f1: i64,
        f2: i64,
        f3: i64,
        f4: i64,
        f5: i64,
        f6: i64,
        f7: i64,
        f8: i64,
        f9: i64,
        f10: i64,
        f11: i64,
        f12: i64,
        f13: i64,
        f14: i64,
        f15: i64,
        f16: i64,
        f17: i64,
        f18: i64,
        f19: i64,
        f20: i64,
        f21: i64,
        f22: i64,
        f23: i64,
        f24: i64,
        f25: i64,
        f26: i64,
        f27: i64,
        f28: i64,
        f29: i64,
        f30: i64,
        f31: i64,
        f32: i64,
        f33: i64,
        f34: i64,
        f35: i64,
        f36: i64,
        f37: i64,
        f38: i64,
        f39: i64,
        f40: i64,
        f41: i64,
        f42: i64,
        f43: i64,
        f44: i64,
        f45: i64,
        f46: i64,
        f47: i64,
        f48: i64,
        f49: i64,
        f50: i64,
        f51: i64,
        f52: i64,
        f53: i64,
        f54: i64,
        f55: i64,
        f56: i64,
        f57: i64,
        f58: i64,
        f59: i64,
        f60: i64,
        f61: i64,
        f62: i64,
        f63: i64,
        f64: i64,
        f65: i64,
        f66: i64,
        f67: i64,
        f68: i64,
        f69: i64,
        f70: i64,
        pub const table_name = "large_users";
    };

    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(LargeUser, .postgresql).init(testing.allocator, @ptrCast(&db), "large_users");
    defer query.deinit();

    // 70 字段 x 950 行 = 66500 参数 > 65535
    const large_batch = try testing.allocator.alloc(LargeUser, 950);
    defer testing.allocator.free(large_batch);

    for (large_batch) |*row| {
        row.* = .{
            .f1 = 1,
            .f2 = 2,
            .f3 = 3,
            .f4 = 4,
            .f5 = 5,
            .f6 = 6,
            .f7 = 7,
            .f8 = 8,
            .f9 = 9,
            .f10 = 10,
            .f11 = 11,
            .f12 = 12,
            .f13 = 13,
            .f14 = 14,
            .f15 = 15,
            .f16 = 16,
            .f17 = 17,
            .f18 = 18,
            .f19 = 19,
            .f20 = 20,
            .f21 = 21,
            .f22 = 22,
            .f23 = 23,
            .f24 = 24,
            .f25 = 25,
            .f26 = 26,
            .f27 = 27,
            .f28 = 28,
            .f29 = 29,
            .f30 = 30,
            .f31 = 31,
            .f32 = 32,
            .f33 = 33,
            .f34 = 34,
            .f35 = 35,
            .f36 = 36,
            .f37 = 37,
            .f38 = 38,
            .f39 = 39,
            .f40 = 40,
            .f41 = 41,
            .f42 = 42,
            .f43 = 43,
            .f44 = 44,
            .f45 = 45,
            .f46 = 46,
            .f47 = 47,
            .f48 = 48,
            .f49 = 49,
            .f50 = 50,
            .f51 = 51,
            .f52 = 52,
            .f53 = 53,
            .f54 = 54,
            .f55 = 55,
            .f56 = 56,
            .f57 = 57,
            .f58 = 58,
            .f59 = 59,
            .f60 = 60,
            .f61 = 61,
            .f62 = 62,
            .f63 = 63,
            .f64 = 64,
            .f65 = 65,
            .f66 = 66,
            .f67 = 67,
            .f68 = 68,
            .f69 = 69,
            .f70 = 70,
        };
    }

    // 应返回 ExceedsPostgreSQLParamLimit 错误
    try testing.expectError(error.ExceedsPostgreSQLParamLimit, query.values(large_batch));
}

test "Story 1.5: 批量插入内存预分配优化" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    const users = [_]User{
        .{ .id = 1, .name = "Alice", .email = "alice@example.com", .age = 25 },
        .{ .id = 2, .name = "Bob", .email = "bob@example.com", .age = 30 },
        .{ .id = 3, .name = "Carol", .email = "carol@example.com", .age = 28 },
    };

    // 预分配应该成功,不应该抛出 OOM
    _ = try query.values(&users);

    // 验证 values_list 容量足够
    try testing.expect(query.values_list.capacity >= 3);
}

test "Story 1.5: 批量插入与 ON CONFLICT 结合" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .postgresql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    const users = [_]User{
        .{ .id = 1, .name = "Alice", .email = "alice@example.com", .age = 25 },
        .{ .id = 2, .name = "Bob", .email = "bob@example.com", .age = 30 },
    };

    _ = try query.values(&users);
    _ = try query.onConflict(.{
        .columns = &.{"email"},
        .action = .do_update,
        .update_columns = &.{ "name", "age" },
    });

    const sql = try query.build();
    defer testing.allocator.free(sql);

    // 验证同时包含批量 VALUES 和 ON CONFLICT
    try testing.expect(std.mem.indexOf(u8, sql, "VALUES ($1, $2, $3, $4), ($5, $6, $7, $8)") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name, age = EXCLUDED.age") != null);
}

test "Story 1.5: MySQL 批量插入占位符" {
    var db = MockDB{ .allocator = testing.allocator };

    var query = try zorm.InsertQuery(User, .mysql).init(testing.allocator, @ptrCast(&db), "users");
    defer query.deinit();

    const users = [_]User{
        .{ .id = 1, .name = "Alice", .email = "alice@example.com", .age = 25 },
        .{ .id = 2, .name = "Bob", .email = "bob@example.com", .age = 30 },
    };

    _ = try query.values(&users);
    const sql = try query.build();
    defer testing.allocator.free(sql);

    // MySQL 应该使用 ? 占位符
    try testing.expect(std.mem.indexOf(u8, sql, "VALUES (?, ?, ?, ?), (?, ?, ?, ?)") != null);
    // 不应该包含 PostgreSQL 占位符
    try testing.expect(std.mem.indexOf(u8, sql, "$1") == null);
}
