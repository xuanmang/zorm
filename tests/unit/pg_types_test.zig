//! PostgreSQL 特有类型单元测试
//!
//! 测试 JSONB、UUID、数组等 PostgreSQL 特有类型的映射和序列化

const std = @import("std");
const types = @import("../../src/core/types.zig");

// 测试类型别名
const JSONB = types.JSONB;
const UUID = types.UUID;
const TimestampTz = types.TimestampTz;
const Timestamp = types.Timestamp;

// ============ 类型映射测试 ============

test "zigToSQLType: JSONB type" {
    comptime {
        const sql_type = types.zigToSQLType(JSONB);
        try std.testing.expectEqualStrings("JSONB", sql_type);
    }
}

test "zigToSQLType: UUID type" {
    comptime {
        const sql_type = types.zigToSQLType(UUID);
        try std.testing.expectEqualStrings("UUID", sql_type);
    }
}

test "zigToSQLType: TimestampTz type" {
    comptime {
        const sql_type = types.zigToSQLType(TimestampTz);
        try std.testing.expectEqualStrings("TIMESTAMP WITH TIME ZONE", sql_type);
    }
}

test "zigToSQLType: Timestamp type" {
    comptime {
        const sql_type = types.zigToSQLType(Timestamp);
        try std.testing.expectEqualStrings("TIMESTAMP WITHOUT TIME ZONE", sql_type);
    }
}

test "zigToSQLType: integer array" {
    comptime {
        const sql_type = types.zigToSQLType([]i32);
        try std.testing.expectEqualStrings("INTEGER[]", sql_type);
    }
}

test "zigToSQLType: bigint array" {
    comptime {
        const sql_type = types.zigToSQLType([]i64);
        try std.testing.expectEqualStrings("BIGINT[]", sql_type);
    }
}

test "zigToSQLType: text array" {
    comptime {
        const sql_type = types.zigToSQLType([][]const u8);
        try std.testing.expectEqualStrings("TEXT[]", sql_type);
    }
}

test "zigToSQLType: float array" {
    comptime {
        const sql_type = types.zigToSQLType([]f64);
        try std.testing.expectEqualStrings("DOUBLE PRECISION[]", sql_type);
    }
}

test "zigToSQLType: boolean array" {
    comptime {
        const sql_type = types.zigToSQLType([]bool);
        try std.testing.expectEqualStrings("BOOLEAN[]", sql_type);
    }
}

test "zigToSQLType: fixed-size array" {
    comptime {
        const sql_type = types.zigToSQLType([10]i32);
        try std.testing.expectEqualStrings("INTEGER[]", sql_type);
    }
}

// ============ 数组序列化测试 ============

test "serializeArray: integer array" {
    const allocator = std.testing.allocator;

    const nums = &[_]i32{ 1, 2, 3 };
    const result = try types.serializeArray(i32, nums, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("'{1,2,3}'", result);
}

test "serializeArray: bigint array" {
    const allocator = std.testing.allocator;

    const nums = &[_]i64{ 100, 200, 300 };
    const result = try types.serializeArray(i64, nums, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("'{100,200,300}'", result);
}

test "serializeArray: string array" {
    const allocator = std.testing.allocator;

    const strings = &[_][]const u8{ "hello", "world" };
    const result = try types.serializeArray([]const u8, strings, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("'{\"hello\",\"world\"}'", result);
}

test "serializeArray: float array" {
    const allocator = std.testing.allocator;

    const nums = &[_]f64{ 1.5, 2.5, 3.5 };
    const result = try types.serializeArray(f64, nums, allocator);
    defer allocator.free(result);

    // 浮点数格式可能有变化,只检查包含关键部分
    try std.testing.expect(std.mem.indexOf(u8, result, "1.5") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "2.5") != null);
}

test "serializeArray: boolean array" {
    const allocator = std.testing.allocator;

    const bools = &[_]bool{ true, false, true };
    const result = try types.serializeArray(bool, bools, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("'{true,false,true}'", result);
}

test "serializeArray: empty array" {
    const allocator = std.testing.allocator;

    const nums: []const i32 = &[_]i32{};
    const result = try types.serializeArray(i32, nums, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("'{}'", result);
}

// ============ 数组反序列化测试 ============

test "deserializeArray: integer array" {
    const allocator = std.testing.allocator;

    var result = try types.deserializeArray(i32, "{1,2,3}", allocator);
    defer result.deinit(allocator);

    try std.testing.expectEqual(3, result.items.len);
    try std.testing.expectEqual(@as(i32, 1), result.items[0]);
    try std.testing.expectEqual(@as(i32, 2), result.items[1]);
    try std.testing.expectEqual(@as(i32, 3), result.items[2]);
}

test "deserializeArray: bigint array" {
    const allocator = std.testing.allocator;

    var result = try types.deserializeArray(i64, "{100,200,300}", allocator);
    defer result.deinit(allocator);

    try std.testing.expectEqual(3, result.items.len);
    try std.testing.expectEqual(@as(i64, 100), result.items[0]);
    try std.testing.expectEqual(@as(i64, 200), result.items[1]);
}

test "deserializeArray: string array" {
    const allocator = std.testing.allocator;

    var result = try types.deserializeArray([]const u8, "{\"hello\",\"world\"}", allocator);
    defer {
        for (result.items) |item| {
            allocator.free(item);
        }
        result.deinit(allocator);
    }

    try std.testing.expectEqual(2, result.items.len);
    try std.testing.expectEqualStrings("hello", result.items[0]);
    try std.testing.expectEqualStrings("world", result.items[1]);
}

test "deserializeArray: float array" {
    const allocator = std.testing.allocator;

    var result = try types.deserializeArray(f64, "{1.5,2.5,3.5}", allocator);
    defer result.deinit(allocator);

    try std.testing.expectEqual(3, result.items.len);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), result.items[0], 0.001);
}

test "deserializeArray: boolean array" {
    const allocator = std.testing.allocator;

    var result = try types.deserializeArray(bool, "{t,f,true,false}", allocator);
    defer result.deinit(allocator);

    try std.testing.expectEqual(4, result.items.len);
    try std.testing.expectEqual(true, result.items[0]);
    try std.testing.expectEqual(false, result.items[1]);
    try std.testing.expectEqual(true, result.items[2]);
    try std.testing.expectEqual(false, result.items[3]);
}

test "deserializeArray: empty array" {
    const allocator = std.testing.allocator;

    var result = try types.deserializeArray(i32, "{}", allocator);
    defer result.deinit(allocator);

    try std.testing.expectEqual(0, result.items.len);
}

test "deserializeArray: invalid format" {
    const allocator = std.testing.allocator;

    const result = types.deserializeArray(i32, "invalid", allocator);
    try std.testing.expectError(error.InvalidFormat, result);
}

// ============ UUID 序列化测试 ============

test "uuidToString: standard UUID" {
    const allocator = std.testing.allocator;

    const uuid: UUID = [_]u8{
        0x55, 0x0e, 0x84, 0x00,
        0xe2, 0x9b, 0x41, 0xd4,
        0xa7, 0x16, 0x44, 0x66,
        0x55, 0x44, 0x00, 0x00,
    };

    const result = try types.uuidToString(uuid, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("550e8400-e29b-41d4-a716-446655440000", result);
}

test "uuidToString: all zeros" {
    const allocator = std.testing.allocator;

    const uuid: UUID = [_]u8{0} ** 16;

    const result = try types.uuidToString(uuid, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000000", result);
}

// ============ UUID 反序列化测试 ============

test "stringToUuid: with hyphens" {
    const result = try types.stringToUuid("550e8400-e29b-41d4-a716-446655440000");

    try std.testing.expectEqual(@as(u8, 0x55), result[0]);
    try std.testing.expectEqual(@as(u8, 0x0e), result[1]);
    try std.testing.expectEqual(@as(u8, 0x84), result[2]);
    try std.testing.expectEqual(@as(u8, 0x00), result[3]);
}

test "stringToUuid: without hyphens" {
    const result = try types.stringToUuid("550e8400e29b41d4a716446655440000");

    try std.testing.expectEqual(@as(u8, 0x55), result[0]);
    try std.testing.expectEqual(@as(u8, 0x0e), result[1]);
}

test "stringToUuid: all zeros" {
    const result = try types.stringToUuid("00000000-0000-0000-0000-000000000000");

    for (result) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "stringToUuid: invalid format" {
    const result = types.stringToUuid("invalid");
    try std.testing.expectError(error.InvalidFormat, result);
}

test "stringToUuid: too short" {
    const result = types.stringToUuid("550e8400");
    try std.testing.expectError(error.InvalidFormat, result);
}

// ============ JSONB 测试 ============

test "JSONB: init and access" {
    const json_str = "{\"author\": \"John\", \"draft\": false}";
    const jsonb = JSONB.init(json_str);

    try std.testing.expectEqualStrings(json_str, jsonb.data);
}

test "JSONB: struct literal" {
    const jsonb = JSONB{ .data = "{\"test\": true}" };

    try std.testing.expectEqualStrings("{\"test\": true}", jsonb.data);
}

// ============ 集成类型测试 ============

test "Article struct with PostgreSQL types" {
    const Article = struct {
        id: i64,
        title: []const u8,
        tags: [][]const u8,
        metadata: JSONB,
        view_counts: []i32,
        created_at: TimestampTz,

        pub const table_name = "articles";
    };

    comptime {
        const fields = types.getFields(Article);
        try std.testing.expectEqual(6, fields.len);

        // 验证字段类型映射
        try std.testing.expectEqualStrings("BIGINT", types.zigToSQLType(i64));
        try std.testing.expectEqualStrings("TEXT", types.zigToSQLType([]const u8));
        try std.testing.expectEqualStrings("TEXT[]", types.zigToSQLType([][]const u8));
        try std.testing.expectEqualStrings("JSONB", types.zigToSQLType(JSONB));
        try std.testing.expectEqualStrings("INTEGER[]", types.zigToSQLType([]i32));
        try std.testing.expectEqualStrings("TIMESTAMP WITH TIME ZONE", types.zigToSQLType(TimestampTz));
    }
}
