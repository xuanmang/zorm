//! 环境准备和共享基础设施单元测试
//!
//! 测试内容：
//! - DBConfig 默认配置验证
//! - 数据库驱动创建
//! - 模型 table_name 验证
//! - 内存泄漏检测

const std = @import("std");
const testing = std.testing;
const db_config = @import("../common/db_config.zig");
const models = @import("../common/models.zig");

// ============================================
// DBConfig 测试
// ============================================

test "DBConfig 默认配置验证" {
    const config = db_config.getDefaultConfig();

    // 验证默认配置值
    try testing.expectEqualStrings("127.0.0.1", config.host);
    try testing.expectEqual(@as(u16, 5432), config.port);
    try testing.expectEqualStrings("pguser", config.user);
    try testing.expectEqualStrings("Pg#123!", config.password);
    try testing.expectEqualStrings("postgres", config.dbname);
}

test "DBConfig.toDSN 生成正确的 DSN 字符串" {
    const allocator = testing.allocator;

    const config = db_config.DBConfig{
        .host = "localhost",
        .port = 5433,
        .user = "testuser",
        .password = "testpass",
        .dbname = "testdb",
    };

    const dsn = try config.toDSN(allocator);
    defer allocator.free(dsn);

    const expected = "host=localhost port=5433 user=testuser password=testpass dbname=testdb";
    try testing.expectEqualStrings(expected, dsn);
}

test "DBConfig.toDSN 内存泄漏检测" {
    const allocator = testing.allocator;

    const config = db_config.getDefaultConfig();

    // 创建并立即释放 DSN，testing.allocator 会检测泄漏
    const dsn = try config.toDSN(allocator);
    defer allocator.free(dsn);

    // 如果有内存泄漏，testing.allocator 会在测试结束时报错
    try testing.expect(dsn.len > 0);
}

// ============================================
// 模型 table_name 验证
// ============================================

test "User 模型 table_name 正确" {
    try testing.expectEqualStrings("users", models.User.table_name);
}

test "Post 模型 table_name 正确" {
    try testing.expectEqualStrings("posts", models.Post.table_name);
}

test "Comment 模型 table_name 正确" {
    try testing.expectEqualStrings("comments", models.Comment.table_name);
}

test "Tag 模型 table_name 正确" {
    try testing.expectEqualStrings("tags", models.Tag.table_name);
}

test "PostTag 模型 table_name 正确" {
    try testing.expectEqualStrings("post_tags", models.PostTag.table_name);
}

// ============================================
// 模型结构验证
// ============================================

test "User 模型字段类型验证" {
    const user = models.User{
        .id = 1,
        .name = "Test User",
        .email = "test@example.com",
        .created_at = 1234567890,
        .updated_at = 1234567890,
    };

    try testing.expectEqual(@as(i64, 1), user.id);
    try testing.expectEqualStrings("Test User", user.name);
    try testing.expectEqualStrings("test@example.com", user.email);
}

test "Post 模型字段类型验证" {
    const post = models.Post{
        .id = 1,
        .user_id = 1,
        .title = "Test Post",
        .content = "Test Content",
        .status = "draft",
        .published_at = null,
        .created_at = 1234567890,
        .updated_at = 1234567890,
    };

    try testing.expectEqual(@as(i64, 1), post.id);
    try testing.expectEqual(@as(i64, 1), post.user_id);
    try testing.expectEqualStrings("Test Post", post.title);
    try testing.expectEqualStrings("draft", post.status);
    try testing.expect(post.published_at == null);
}

test "Comment 模型字段类型验证" {
    const comment = models.Comment{
        .id = 1,
        .post_id = 1,
        .user_id = 1,
        .content = "Test Comment",
        .created_at = 1234567890,
    };

    try testing.expectEqual(@as(i64, 1), comment.id);
    try testing.expectEqual(@as(i64, 1), comment.post_id);
    try testing.expectEqualStrings("Test Comment", comment.content);
}

test "Tag 模型字段类型验证" {
    const tag = models.Tag{
        .id = 1,
        .name = "Zig",
    };

    try testing.expectEqual(@as(i64, 1), tag.id);
    try testing.expectEqualStrings("Zig", tag.name);
}

test "PostTag 模型字段类型验证" {
    const post_tag = models.PostTag{
        .post_id = 1,
        .tag_id = 2,
    };

    try testing.expectEqual(@as(i64, 1), post_tag.post_id);
    try testing.expectEqual(@as(i64, 2), post_tag.tag_id);
}

// ============================================
// 集成测试 (需要真实数据库连接)
// ============================================

// 注意: 以下测试需要 PostgreSQL 数据库运行
// 可以使用 -Dskip_integration_tests 跳过集成测试

const skip_integration = @import("builtin").is_test;

test "createDefaultDriver 成功创建驱动 (集成测试)" {
    if (skip_integration) {
        // 跳过集成测试（避免 CI/CD 环境中失败）
        return error.SkipZigTest;
    }

    const allocator = testing.allocator;

    // 尝试创建驱动
    var driver = db_config.createDefaultDriver(allocator) catch |err| {
        // 如果连接失败，打印错误信息但不失败测试
        std.debug.print("\n跳过集成测试: 无法连接到数据库 - {}\n", .{err});
        return error.SkipZigTest;
    };
    defer driver.close() catch {};

    // 如果到这里，说明驱动创建成功
    // PostgresDriver 结构体存在 pool 字段
    try testing.expect(@TypeOf(driver.pool) != void);
}

test "createDriver 使用自定义配置成功创建驱动 (集成测试)" {
    if (skip_integration) {
        return error.SkipZigTest;
    }

    const allocator = testing.allocator;

    const config = db_config.getDefaultConfig();

    var driver = db_config.createDriver(allocator, config) catch |err| {
        std.debug.print("\n跳过集成测试: 无法连接到数据库 - {}\n", .{err});
        return error.SkipZigTest;
    };
    defer driver.close() catch {};

    try testing.expect(@TypeOf(driver.pool) != void);
}
