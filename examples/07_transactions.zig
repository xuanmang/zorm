//! 事务管理示例
//!
//! 学习目标:
//! - 理解事务的 ACID 特性
//! - 掌握事务提交和回滚
//! - 学习事务中的错误处理
//!
//! 对应功能需求: FR4
//! 难度: 中级

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 07: 事务管理 ===\n\n", .{});

    const db_config = config.Config.default();
    var pool = try pg.Pool.init(allocator, .{
        .size = 5,
        .connect = .{
            .host = db_config.host,
            .port = db_config.port,
        },
        .auth = .{
            .username = db_config.user,
            .password = db_config.password,
            .database = db_config.database,
        },
    });
    defer pool.deinit();

    var conn = try pool.acquire();
    defer conn.release();

    // 示例 1: 基础事务提交
    try basicTransaction(&conn);

    // 示例 2: 事务回滚
    try transactionRollback(&conn);

    // 示例 3: 错误自动回滚
    try automaticRollback(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn basicTransaction(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 基础事务提交\n", .{});

    // 开始事务
    try conn.begin();
    errdefer conn.rollback() catch {}; // why: 发生错误时自动回滚

    std.debug.print("  事务已开始\n", .{});

    // 在事务中执行多个操作
    var user_result_opt = try conn.row(
        \\INSERT INTO zorm_examples.users (name, email, created_at, updated_at)
        \\VALUES ($1, $2, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
        \\RETURNING id
    ,
        .{ "Transaction User", "transaction@example.com" },
    );

    if (user_result_opt) |*user_result| {
        defer user_result.deinit() catch {};
        const user_id = user_result.get(i64, 0);
        std.debug.print("  创建用户，ID: {d}\n", .{user_id});

        // 为用户创建文章
        _ = try conn.exec(
            \\INSERT INTO zorm_examples.posts (user_id, title, content, status, created_at, updated_at)
            \\VALUES ($1, $2, $3, $4, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
        ,
            .{ user_id, "Transaction Post", "This is content", "published" },
        );
        std.debug.print("  创建文章\n", .{});

        // 提交事务
        try conn.commit();
        std.debug.print("  ✓ 事务提交成功\n\n", .{});
    }
}

fn transactionRollback(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: 事务回滚\n", .{});

    // 查询当前用户数
    var count_before_opt = try conn.row("SELECT COUNT(*) FROM zorm_examples.users", .{});
    var count_before: i64 = 0;
    if (count_before_opt) |*result| {
        defer result.deinit() catch {};
        count_before = result.get(i64, 0);
        std.debug.print("  事务前用户数: {d}\n", .{count_before});
    }

    // 开始事务
    try conn.begin();
    std.debug.print("  事务已开始\n", .{});

    // 插入测试数据
    _ = try conn.exec(
        \\INSERT INTO zorm_examples.users (name, email, created_at, updated_at)
        \\VALUES ($1, $2, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
    ,
        .{ "Rollback User", "rollback@example.com" },
    );
    std.debug.print("  插入了测试数据\n", .{});

    // 故意回滚
    try conn.rollback();
    std.debug.print("  ✓ 事务已回滚\n", .{});

    // 验证数据未被插入
    var count_after_opt = try conn.row("SELECT COUNT(*) FROM zorm_examples.users", .{});
    if (count_after_opt) |*result| {
        defer result.deinit() catch {};
        const count_after = result.get(i64, 0);
        std.debug.print("  事务后用户数: {d} (应该等于事务前)\n", .{count_after});
        if (count_after == count_before) {
            std.debug.print("  ✓ 回滚成功，数据未提交\n\n", .{});
        }
    }
}

fn automaticRollback(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: 错误自动回滚\n", .{});

    var count_before_opt = try conn.row("SELECT COUNT(*) FROM zorm_examples.users", .{});
    var count_before: i64 = 0;
    if (count_before_opt) |*result| {
        defer result.deinit() catch {};
        count_before = result.get(i64, 0);
        std.debug.print("  事务前用户数: {d}\n", .{count_before});
    }

    // 使用 errdefer 实现错误时自动回滚
    const result = performFailingTransaction(conn);

    if (result) |_| {
        std.debug.print("  事务成功（不应该发生）\n", .{});
    } else |err| {
        std.debug.print("  预期的错误: {}\n", .{err});
        std.debug.print("  ✓ 事务已自动回滚\n", .{});
    }

    // 验证数据未被插入
    var count_after_opt = try conn.row("SELECT COUNT(*) FROM zorm_examples.users", .{});
    if (count_after_opt) |*result| {
        defer result.deinit() catch {};
        const count_after = result.get(i64, 0);
        std.debug.print("  事务后用户数: {d} (应该等于事务前)\n", .{count_after});
        if (count_after == count_before) {
            std.debug.print("  ✓ 自动回滚成功\n", .{});
        }
    }
}

fn performFailingTransaction(conn: *pg.Conn) !void {
    try conn.begin();
    errdefer conn.rollback() catch {}; // why: errdefer 确保错误时回滚

    // 插入数据
    _ = try conn.exec(
        \\INSERT INTO zorm_examples.users (name, email, created_at, updated_at)
        \\VALUES ($1, $2, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
    ,
        .{ "Error User", "error@example.com" },
    );

    // 模拟错误
    return error.SimulatedError;
}
