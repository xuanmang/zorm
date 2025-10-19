//! PostgreSQL 特有类型使用示例
//!
//! 演示 JSONB、UUID、数组等 PostgreSQL 特有类型的使用

const std = @import("std");
const types = @import("../src/core/types.zig");

// 定义使用 PostgreSQL 特有类型的结构体
const Article = struct {
    id: i64,
    title: []const u8,
    tags: [][]const u8, // TEXT[] 数组
    metadata: types.JSONB, // JSONB 字段
    view_counts: []i32, // INTEGER[] 数组
    article_uuid: types.UUID, // UUID 字段
    created_at: types.TimestampTz, // TIMESTAMP WITH TIME ZONE
    updated_at: types.Timestamp, // TIMESTAMP WITHOUT TIME ZONE

    pub const table_name = "articles";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== PostgreSQL 特有类型示例 ===\n\n", .{});

    // 1. 类型映射验证
    std.debug.print("1. 类型映射:\n", .{});
    comptime {
        std.debug.print("  i64 -> {s}\n", .{types.zigToSQLType(i64)});
        std.debug.print("  []const u8 -> {s}\n", .{types.zigToSQLType([]const u8)});
        std.debug.print("  []i32 -> {s}\n", .{types.zigToSQLType([]i32)});
        std.debug.print("  [][]const u8 -> {s}\n", .{types.zigToSQLType([][]const u8)});
        std.debug.print("  JSONB -> {s}\n", .{types.zigToSQLType(types.JSONB)});
        std.debug.print("  UUID -> {s}\n", .{types.zigToSQLType(types.UUID)});
        std.debug.print("  TimestampTz -> {s}\n", .{types.zigToSQLType(types.TimestampTz)});
        std.debug.print("  Timestamp -> {s}\n", .{types.zigToSQLType(types.Timestamp)});
    }

    // 2. 数组序列化
    std.debug.print("\n2. 数组序列化:\n", .{});

    const int_array = &[_]i32{ 100, 200, 150 };
    const int_array_str = try types.serializeArray(i32, int_array, allocator);
    defer allocator.free(int_array_str);
    std.debug.print("  INTEGER[]: {s}\n", .{int_array_str});

    const str_array = &[_][]const u8{ "zig", "orm", "postgresql" };
    const str_array_str = try types.serializeArray([]const u8, str_array, allocator);
    defer allocator.free(str_array_str);
    std.debug.print("  TEXT[]: {s}\n", .{str_array_str});

    // 3. 数组反序列化
    std.debug.print("\n3. 数组反序列化:\n", .{});

    var deserialized_ints = try types.deserializeArray(i32, "{1,2,3}", allocator);
    defer deserialized_ints.deinit(allocator);
    std.debug.print("  解析 {{1,2,3}}: [", .{});
    for (deserialized_ints.items, 0..) |item, i| {
        if (i > 0) std.debug.print(", ", .{});
        std.debug.print("{d}", .{item});
    }
    std.debug.print("]\n", .{});

    // 4. UUID 序列化
    std.debug.print("\n4. UUID 序列化:\n", .{});

    const uuid: types.UUID = [_]u8{
        0x55, 0x0e, 0x84, 0x00,
        0xe2, 0x9b, 0x41, 0xd4,
        0xa7, 0x16, 0x44, 0x66,
        0x55, 0x44, 0x00, 0x00,
    };
    const uuid_str = try types.uuidToString(uuid, allocator);
    defer allocator.free(uuid_str);
    std.debug.print("  UUID: {s}\n", .{uuid_str});

    // 5. UUID 反序列化
    std.debug.print("\n5. UUID 反序列化:\n", .{});

    const parsed_uuid = try types.stringToUuid("550e8400-e29b-41d4-a716-446655440000");
    std.debug.print("  解析 UUID: [", .{});
    for (parsed_uuid, 0..) |byte, i| {
        if (i > 0) std.debug.print(" ", .{});
        std.debug.print("{x:0>2}", .{byte});
    }
    std.debug.print("]\n", .{});

    // 6. JSONB 使用
    std.debug.print("\n6. JSONB 使用:\n", .{});

    const metadata = types.JSONB.init("{\"author\": \"John\", \"draft\": false}");
    std.debug.print("  JSONB 数据: {s}\n", .{metadata.data});

    // 7. Article 结构体示例
    std.debug.print("\n7. Article 结构体示例:\n", .{});

    const article = Article{
        .id = 1,
        .title = "Introduction to ZORM",
        .tags = &[_][]const u8{ "zig", "orm", "postgresql" },
        .metadata = types.JSONB.init("{\"author\": \"John\", \"draft\": false}"),
        .view_counts = &[_]i32{ 100, 200, 150 },
        .article_uuid = uuid,
        .created_at = std.time.timestamp(),
        .updated_at = std.time.timestamp(),
    };

    std.debug.print("  ID: {d}\n", .{article.id});
    std.debug.print("  Title: {s}\n", .{article.title});
    std.debug.print("  Tags: {any}\n", .{article.tags});
    std.debug.print("  Metadata: {s}\n", .{article.metadata.data});
    std.debug.print("  View Counts: {any}\n", .{article.view_counts});
    std.debug.print("  Created At: {d}\n", .{article.created_at});

    std.debug.print("\n=== 示例完成 ===\n", .{});
}
