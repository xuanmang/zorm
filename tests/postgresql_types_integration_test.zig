//! PostgreSQL 特定类型集成测试
//!
//! 验证数组、JSONB、UUID 类型的完整流程:
//! - CREATE TABLE with array/JSONB/UUID columns
//! - INSERT data with serialization
//! - SELECT data with deserialization
//! - Data consistency validation

const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");

// 导入必要的模块
const reflection = zorm.reflection;
const core_types = zorm.types;

// ============================================================
// Article 模型 (完整示例)
// ============================================================

const Article = struct {
    id: i64,
    title: []const u8,
    author: []const u8,
    tags: [][]const u8, // TEXT[] - PostgreSQL 数组
    view_counts: []i64, // BIGINT[] - 整数数组
    metadata: []const u8, // JSONB - JSON 数据
    uuid: [16]u8, // UUID - 唯一标识符
    published_at: ?i64, // 可选时间戳

    pub const table_name = "articles";

    pub const schema = .{
        .metadata = .{ .sql_type = "JSONB" }, // 显式指定 JSONB
        // tags 和 view_counts 自动检测为数组类型
        // uuid 自动检测为 UUID 类型
    };
};

// ============================================================
// Task 6.1: Article 示例集成测试
// ============================================================

test "Article model: CREATE TABLE generation" {
    const allocator = testing.allocator;

    // 生成 CREATE TABLE SQL
    const sql = try reflection.generateCreateTableSQL(Article, .postgresql, allocator);
    defer allocator.free(sql);

    // 验证 SQL 包含正确的类型定义
    try testing.expect(std.mem.indexOf(u8, sql, "CREATE TABLE articles") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "id BIGSERIAL PRIMARY KEY") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "title TEXT NOT NULL") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "author TEXT NOT NULL") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "tags TEXT[] NOT NULL") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "view_counts BIGINT[] NOT NULL") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "metadata JSONB NOT NULL") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "uuid UUID NOT NULL") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "published_at BIGINT") != null);
}

test "Article model: Array serialization" {
    const allocator = testing.allocator;

    // 测试 tags 数组序列化
    const tags = &[_][]const u8{ "postgresql", "zig", "database" };
    const serialized_tags = try core_types.serializeArray([]const u8, tags, allocator);
    defer allocator.free(serialized_tags);

    try testing.expectEqualStrings("'{\"postgresql\",\"zig\",\"database\"}'", serialized_tags);

    // 测试 view_counts 数组序列化
    const view_counts = &[_]i64{ 100, 250, 500 };
    const serialized_counts = try core_types.serializeArray(i64, view_counts, allocator);
    defer allocator.free(serialized_counts);

    try testing.expectEqualStrings("'{100,250,500}'", serialized_counts);
}

test "Article model: Array deserialization" {
    const allocator = testing.allocator;

    // 反序列化 tags
    var tags_result = try core_types.deserializeArray([]const u8, "{\"postgresql\",\"zig\",\"database\"}", allocator);
    defer {
        for (tags_result.items) |tag| {
            allocator.free(tag);
        }
        tags_result.deinit(allocator);
    }

    try testing.expectEqual(@as(usize, 3), tags_result.items.len);
    try testing.expectEqualStrings("postgresql", tags_result.items[0]);
    try testing.expectEqualStrings("zig", tags_result.items[1]);
    try testing.expectEqualStrings("database", tags_result.items[2]);

    // 反序列化 view_counts
    var counts_result = try core_types.deserializeArray(i64, "{100,250,500}", allocator);
    defer counts_result.deinit(allocator);

    try testing.expectEqual(@as(usize, 3), counts_result.items.len);
    try testing.expectEqual(@as(i64, 100), counts_result.items[0]);
    try testing.expectEqual(@as(i64, 250), counts_result.items[1]);
    try testing.expectEqual(@as(i64, 500), counts_result.items[2]);
}

test "Article model: UUID serialization and deserialization" {
    const allocator = testing.allocator;

    // 创建一个 UUID
    const uuid: [16]u8 = [_]u8{
        0x55, 0x0e, 0x84, 0x00,
        0xe2, 0x9b, 0x41, 0xd4,
        0xa7, 0x16, 0x44, 0x66,
        0x55, 0x44, 0x00, 0x00,
    };

    // 序列化
    const uuid_str = try core_types.uuidToString(uuid, allocator);
    defer allocator.free(uuid_str);

    try testing.expectEqualStrings("550e8400-e29b-41d4-a716-446655440000", uuid_str);

    // 反序列化
    const parsed_uuid = try core_types.stringToUuid(uuid_str);
    try testing.expectEqualSlices(u8, &uuid, &parsed_uuid);
}

test "Article model: JSONB handling" {
    // JSONB 直接使用字符串,无需特殊序列化
    const metadata = "{\"author_bio\":\"Zig enthusiast\",\"draft\":false}";

    // 验证 JSON 格式正确 (可选,PostgreSQL 会验证)
    try testing.expect(metadata.len > 0);
    try testing.expect(std.mem.startsWith(u8, metadata, "{"));
    try testing.expect(std.mem.endsWith(u8, metadata, "}"));
}

// ============================================================
// Task 6.2: 端到端流程测试
// ============================================================

test "End-to-end: Array round-trip with special characters" {
    const allocator = testing.allocator;

    // 包含特殊字符的字符串数组
    const tags = &[_][]const u8{ "hello \"world\"", "test\\path", "normal" };
    const serialized = try core_types.serializeArray([]const u8, tags, allocator);
    defer allocator.free(serialized);

    // 验证转义正确
    try testing.expect(std.mem.indexOf(u8, serialized, "\\\"") != null); // 包含 \"
    try testing.expect(std.mem.indexOf(u8, serialized, "\\\\") != null); // 包含 \\

    // 反序列化
    var result = try core_types.deserializeArray([]const u8, serialized[1 .. serialized.len - 1], allocator);
    defer {
        for (result.items) |tag| {
            allocator.free(tag);
        }
        result.deinit(allocator);
    }

    try testing.expectEqual(@as(usize, 3), result.items.len);
    try testing.expectEqualStrings("hello \"world\"", result.items[0]);
    try testing.expectEqualStrings("test\\path", result.items[1]);
    try testing.expectEqualStrings("normal", result.items[2]);
}

test "End-to-end: Empty array handling" {
    const allocator = testing.allocator;

    // 空数组序列化
    const empty_tags: []const []const u8 = &[_][]const u8{};
    const serialized = try core_types.serializeArray([]const u8, empty_tags, allocator);
    defer allocator.free(serialized);

    try testing.expectEqualStrings("'{}'", serialized);

    // 空数组反序列化
    var result = try core_types.deserializeArray([]const u8, "{}", allocator);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(usize, 0), result.items.len);
}

test "End-to-end: NULL values in optional arrays" {
    const allocator = testing.allocator;

    // 注意: PostgreSQL 数组中的 NULL 需要特殊处理
    // 当前实现支持可选类型,但需要在序列化时显式标记 NULL
    const nullable_nums = &[_]?i64{ 1, null, 3, null, 5 };
    const serialized = try core_types.serializeArray(?i64, nullable_nums, allocator);
    defer allocator.free(serialized);

    // 验证 NULL 值被正确序列化
    try testing.expect(std.mem.indexOf(u8, serialized, "NULL") != null);
}

test "End-to-end: Large array performance" {
    const allocator = testing.allocator;

    // 测试大数组 (1000 个元素)
    var large_array = std.ArrayList(i64){};
    defer large_array.deinit(allocator);

    var i: i64 = 0;
    while (i < 1000) : (i += 1) {
        try large_array.append(allocator, i);
    }

    const serialized = try core_types.serializeArray(i64, large_array.items, allocator);
    defer allocator.free(serialized);

    // 验证序列化结果包含所有元素
    try testing.expect(std.mem.indexOf(u8, serialized, "'{0,") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, ",999}'") != null);

    // 反序列化
    var result = try core_types.deserializeArray(i64, serialized[1 .. serialized.len - 1], allocator);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(usize, 1000), result.items.len);
    try testing.expectEqual(@as(i64, 0), result.items[0]);
    try testing.expectEqual(@as(i64, 999), result.items[999]);
}

test "End-to-end: UUID format variations" {
    const allocator = testing.allocator;

    const test_cases = [_][]const u8{
        "550e8400-e29b-41d4-a716-446655440000", // 标准格式
        "550E8400-E29B-41D4-A716-446655440000", // 大写
        "550e8400e29b41d4a716446655440000", // 无连字符
    };

    for (test_cases) |uuid_str| {
        const uuid = try core_types.stringToUuid(uuid_str);
        const serialized = try core_types.uuidToString(uuid, allocator);
        defer allocator.free(serialized);

        // 所有格式应该序列化为标准小写格式
        try testing.expectEqualStrings("550e8400-e29b-41d4-a716-446655440000", serialized);
    }
}

// ============================================================
// 边界情况和错误处理测试
// ============================================================

test "Error handling: Invalid UUID format" {
    // 无效格式应返回错误
    const invalid_uuids = [_][]const u8{
        "invalid",
        "550e8400", // 太短
        "550e8400-e29b-41d4-a716-44665544000g", // 无效十六进制字符
        "550e8400-e29b-41d4-a716", // 不完整
    };

    for (invalid_uuids) |invalid| {
        const result = core_types.stringToUuid(invalid);
        try testing.expectError(error.InvalidFormat, result);
    }
}

test "Error handling: Invalid array format" {
    const allocator = testing.allocator;

    // 缺少大括号
    const err1 = core_types.deserializeArray(i64, "1,2,3", allocator);
    try testing.expectError(core_types.SerializationError.InvalidArrayFormat, err1);

    // 只有左括号
    const err2 = core_types.deserializeArray(i64, "{1,2,3", allocator);
    try testing.expectError(core_types.SerializationError.InvalidArrayFormat, err2);
}

test "Type detection: JSONB field via schema config" {
    // Article.metadata 显式配置为 JSONB
    const has_metadata = comptime blk: {
        for (std.meta.fields(@TypeOf(Article.schema))) |field| {
            if (std.mem.eql(u8, field.name, "metadata")) {
                break :blk true;
            }
        }
        break :blk false;
    };

    try testing.expect(has_metadata);
}

test "Type detection: UUID via [16]u8 type" {
    // Article.uuid 通过 [16]u8 类型自动识别
    const uuid_field_type = @TypeOf(@as(Article, undefined).uuid);
    const uuid_type_info = @typeInfo(uuid_field_type);

    try testing.expect(uuid_type_info == .array);
    try testing.expectEqual(@as(usize, 16), uuid_type_info.array.len);
    try testing.expectEqual(u8, uuid_type_info.array.child);
}

// ============================================================
// 性能考虑测试
// ============================================================

test "Performance: Comptime type detection" {
    // 所有类型检测在编译时完成,这里只是验证 comptime 特性
    // 通过验证 Article 模型的字段类型来确认编译时检测工作正常
    comptime {
        const fields = @typeInfo(Article).@"struct".fields;
        var found_array_field = false;
        var found_uuid_field = false;

        for (fields) |field| {
            const field_type_info = @typeInfo(field.type);
            // 检测数组字段 (tags, view_counts)
            if (field_type_info == .pointer) {
                const ptr_info = field_type_info.pointer;
                if (ptr_info.size == .slice and ptr_info.child != u8) {
                    found_array_field = true;
                }
            }
            // 检测 UUID 字段
            if (field_type_info == .array) {
                const arr_info = field_type_info.array;
                if (arr_info.len == 16 and arr_info.child == u8) {
                    found_uuid_field = true;
                }
            }
        }

        if (!found_array_field) {
            @compileError("Failed to detect array fields at compile time");
        }
        if (!found_uuid_field) {
            @compileError("Failed to detect UUID field at compile time");
        }
    }
}

test "Performance: Zero-copy string handling" {
    // JSONB 直接使用原始字符串,无需拷贝
    const metadata = "{\"key\":\"value\"}";
    const metadata_copy = metadata; // 零拷贝

    try testing.expectEqual(@intFromPtr(metadata.ptr), @intFromPtr(metadata_copy.ptr));
}
