//! 示例 02: 简单 SELECT 查询
//!
//! 本示例展示如何:
//! - 使用 SelectQuery 构建器查询数据
//! - 查询所有记录和单条记录
//! - 添加 WHERE 条件过滤
//! - 使用 ORDER BY 排序
//! - 使用 LIMIT 和 OFFSET 分页
//! - 处理查询错误和空结果
//!
//! 运行方式: zig build run-example -Dexample=02_simple_select

const std = @import("std");
const zorm = @import("zorm");
const db_config = @import("common/db_config.zig");
const models = @import("common/models.zig");

const User = models.User;

pub fn main() !void {
    // 使用 GPA allocator 确保内存安全
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("⚠️  内存泄漏检测到!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 02: SELECT 查询 ===\n\n", .{});

    // 连接数据库
    std.debug.print("连接到数据库...\n", .{});
    var db = try db_config.createDefaultDBInstance(allocator);
    defer db.deinit();
    std.debug.print("✓ 连接成功\n\n", .{});

    // 设置 search_path
    try db.exec("SET search_path TO zorm_examples", &.{});

    // 准备测试数据
    std.debug.print("准备测试数据...\n", .{});
    try prepareTestData(db);
    std.debug.print("✓ 测试数据就绪\n\n", .{});

    // 示例 1: 查询所有用户
    std.debug.print("示例 1: 查询所有用户\n", .{});
    std.debug.print("---------------------------------------\n", .{});
    try example1_selectAll(db, allocator);

    // 示例 2: 带 WHERE 条件查询
    std.debug.print("\n示例 2: 带 WHERE 条件查询\n", .{});
    std.debug.print("---------------------------------------\n", .{});
    try example2_whereClause(db, allocator);

    // 示例 3: 使用 ORDER BY 排序
    std.debug.print("\n示例 3: 使用 ORDER BY 排序\n", .{});
    std.debug.print("---------------------------------------\n", .{});
    try example3_orderBy(db, allocator);

    // 示例 4: 使用 LIMIT 和 OFFSET 分页
    std.debug.print("\n示例 4: 使用 LIMIT 和 OFFSET 分页\n", .{});
    std.debug.print("---------------------------------------\n", .{});
    try example4_pagination(db, allocator);

    // 示例 5: 查询单条记录
    std.debug.print("\n示例 5: 查询单条记录\n", .{});
    std.debug.print("---------------------------------------\n", .{});
    try example5_scanOne(db, allocator);

    // 示例 6: 错误处理 - NoRows
    std.debug.print("\n示例 6: 错误处理 - NoRows\n", .{});
    std.debug.print("---------------------------------------\n", .{});
    try example6_errorHandling(db, allocator);

    std.debug.print("\n✅ 示例执行完成!\n", .{});
    std.debug.print("\n📚 下一步:\n", .{});
    std.debug.print("  - 示例 03: 学习 INSERT 操作\n", .{});
    std.debug.print("  - 示例 04: 学习 UPDATE 操作\n\n", .{});
}

/// 准备测试数据
fn prepareTestData(db: *zorm.DB(.postgresql)) !void {
    // 清空现有数据
    try db.exec("TRUNCATE TABLE users RESTART IDENTITY CASCADE", &.{});

    // 插入测试用户
    try db.exec(
        \\INSERT INTO users (name, email, created_at, updated_at) VALUES
        \\  ('Alice', 'alice@example.com', EXTRACT(EPOCH FROM NOW())::BIGINT, EXTRACT(EPOCH FROM NOW())::BIGINT),
        \\  ('Bob', 'bob@example.com', EXTRACT(EPOCH FROM NOW())::BIGINT, EXTRACT(EPOCH FROM NOW())::BIGINT),
        \\  ('Charlie', 'charlie@example.com', EXTRACT(EPOCH FROM NOW())::BIGINT, EXTRACT(EPOCH FROM NOW())::BIGINT),
        \\  ('Diana', 'diana@example.com', EXTRACT(EPOCH FROM NOW())::BIGINT, EXTRACT(EPOCH FROM NOW())::BIGINT),
        \\  ('Eve', 'eve@example.com', EXTRACT(EPOCH FROM NOW())::BIGINT, EXTRACT(EPOCH FROM NOW())::BIGINT)
    , &.{});
}

/// 示例 1: 查询所有用户
fn example1_selectAll(db: *zorm.DB(.postgresql), allocator: std.mem.Allocator) !void {
    std.debug.print("使用 ZORM SelectQuery 查询所有用户...\n\n", .{});

    // 创建查询构建器
    var query = try db.newSelect(User);
    defer query.deinit();

    // 执行查询并扫描结果
    const users = try query.scan();
    defer allocator.free(users);

    std.debug.print("查询到 {d} 个用户:\n", .{users.len});
    for (users) |user| {
        std.debug.print("  ID: {d}, Name: {s}, Email: {s}\n", .{
            user.id,
            user.name,
            user.email,
        });
    }
}

/// 示例 2: 带 WHERE 条件查询
fn example2_whereClause(db: *zorm.DB(.postgresql), allocator: std.mem.Allocator) !void {
    std.debug.print("查询 ID > 2 的用户...\n\n", .{});

    var query = try db.newSelect(User);
    defer query.deinit();

    // 添加 WHERE 条件
    _ = try query.where("id > $1", .{@as(i64, 2)});

    const users = try query.scan();
    defer allocator.free(users);

    std.debug.print("查询到 {d} 个用户:\n", .{users.len});
    for (users) |user| {
        std.debug.print("  ID: {d}, Name: {s}\n", .{ user.id, user.name });
    }
}

/// 示例 3: 使用 ORDER BY 排序
fn example3_orderBy(db: *zorm.DB(.postgresql), allocator: std.mem.Allocator) !void {
    std.debug.print("按 name 降序排列用户...\n\n", .{});

    var query = try db.newSelect(User);
    defer query.deinit();

    // 添加 ORDER BY 子句
    _ = try query.orderBy("name", .desc);

    const users = try query.scan();
    defer allocator.free(users);

    std.debug.print("排序结果:\n", .{});
    for (users) |user| {
        std.debug.print("  {s}\n", .{user.name});
    }
}

/// 示例 4: 使用 LIMIT 和 OFFSET 分页
fn example4_pagination(db: *zorm.DB(.postgresql), allocator: std.mem.Allocator) !void {
    std.debug.print("分页查询 - 每页 2 条,第 2 页...\n\n", .{});

    var query = try db.newSelect(User);
    defer query.deinit();

    // 设置分页参数
    _ = try query
        .orderBy("id", .asc)
        .limit(2)
        .offset(2);

    const users = try query.scan();
    defer allocator.free(users);

    std.debug.print("第 2 页结果 (跳过前 2 条):\n", .{});
    for (users) |user| {
        std.debug.print("  ID: {d}, Name: {s}\n", .{ user.id, user.name });
    }
}

/// 示例 5: 查询单条记录
fn example5_scanOne(db: *zorm.DB(.postgresql), allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("查询 ID=1 的用户...\n\n", .{});

    var query = try db.newSelect(User);
    defer query.deinit();

    // 添加精确条件
    _ = try query.where("id = $1", .{@as(i64, 1)});

    // 使用 scanOne 查询单条记录
    const user = try query.scanOne();

    std.debug.print("找到用户:\n", .{});
    std.debug.print("  ID:    {d}\n", .{user.id});
    std.debug.print("  Name:  {s}\n", .{user.name});
    std.debug.print("  Email: {s}\n", .{user.email});
}

/// 示例 6: 错误处理
fn example6_errorHandling(db: *zorm.DB(.postgresql), allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("查询不存在的用户 (ID=999)...\n\n", .{});

    var query = try db.newSelect(User);
    defer query.deinit();

    _ = try query.where("id = $1", .{@as(i64, 999)});

    // 捕获 NoRows 错误
    const user = query.scanOne() catch |err| {
        if (err == error.NoRows) {
            std.debug.print("✓ 正确捕获 NoRows 错误\n", .{});
            std.debug.print("  提示: 没有找到匹配的记录\n", .{});
            return;
        }
        return err;
    };

    // 如果没有报错,打印用户信息
    std.debug.print("找到用户: {s}\n", .{user.name});
}
