//! 错误处理示例
//!
//! 学习目标:
//! - Zig 错误联合类型处理
//! - PostgreSQL 错误捕获
//! - 约束违反处理
//! - 事务错误回滚
//!
//! 对应功能需求: FR8
//! 难度: 中级

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 15: 错误处理 ===\n\n", .{});

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

    // 示例 1: 唯一约束违反
    try uniqueConstraintError(&conn);

    // 示例 2: 外键约束违反
    try foreignKeyError(&conn);

    // 示例 3: NOT NULL 约束违反
    try notNullError(&conn);

    // 示例 4: 事务错误和回滚
    try transactionErrorRollback(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn uniqueConstraintError(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 唯一约束违反\n", .{});

    // 先插入一条记录
    _ = conn.exec(
        \\INSERT INTO zorm_examples.tags (name)
        \\VALUES ('UniqueTest')
        \\ON CONFLICT (name) DO NOTHING
    ,
        .{},
    ) catch |err| {
        std.debug.print("  第一次插入失败: {}\n", .{err});
        if (conn.err) |pg_err| {
            std.debug.print("  PostgreSQL 错误: {s}\n", .{pg_err.message});
        }
    };

    // why: 尝试插入重复的 name，会违反 UNIQUE 约束
    const result = conn.exec(
        "INSERT INTO zorm_examples.tags (name) VALUES ('UniqueTest')",
        .{},
    );

    if (result) |_| {
        std.debug.print("  ✓ 插入成功（不应该发生）\n\n", .{});
    } else |err| {
        std.debug.print("  ✓ 预期的错误: {}\n", .{err});
        if (conn.err) |pg_err| {
            std.debug.print("  PostgreSQL 错误: {s}\n", .{pg_err.message});
            std.debug.print("  错误代码: {s}\n", .{pg_err.code});
        }
        std.debug.print("  说明: UNIQUE 约束保护数据完整性\n\n", .{});
    }
}

fn foreignKeyError(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: 外键约束违反\n", .{});

    const non_existent_user_id: i64 = 999999;

    // why: 尝试插入不存在的 user_id，会违反外键约束
    const result = conn.exec(
        \\INSERT INTO zorm_examples.posts (user_id, title, content, status, created_at, updated_at)
        \\VALUES ($1, $2, $3, $4, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
    ,
        .{ non_existent_user_id, "Test", "Content", "draft" },
    );

    if (result) |_| {
        std.debug.print("  ✓ 插入成功（不应该发生）\n\n", .{});
    } else |err| {
        std.debug.print("  ✓ 预期的错误: {}\n", .{err});
        if (conn.err) |pg_err| {
            std.debug.print("  PostgreSQL 错误: {s}\n", .{pg_err.message});
            std.debug.print("  错误代码: {s}\n", .{pg_err.code});
        }
        std.debug.print("  说明: 外键约束确保引用完整性\n\n", .{});
    }
}

fn notNullError(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: NOT NULL 约束违反\n", .{});

    // why: 尝试插入 NULL 到 NOT NULL 列
    const result = conn.exec(
        \\INSERT INTO zorm_examples.users (name, email, created_at, updated_at)
        \\VALUES (NULL, 'test@example.com', EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
    ,
        .{},
    );

    if (result) |_| {
        std.debug.print("  ✓ 插入成功（不应该发生）\n\n", .{});
    } else |err| {
        std.debug.print("  ✓ 预期的错误: {}\n", .{err});
        if (conn.err) |pg_err| {
            std.debug.print("  PostgreSQL 错误: {s}\n", .{pg_err.message});
            std.debug.print("  错误代码: {s}\n", .{pg_err.code});
        }
        std.debug.print("  说明: NOT NULL 约束防止空值\n\n", .{});
    }
}

fn transactionErrorRollback(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 4: 事务错误和回滚\n", .{});

    // 查询事务前的用户数
    var count_before_opt = try conn.row(
        "SELECT COUNT(*) FROM zorm_examples.users",
        .{},
    );

    var count_before: i64 = 0;
    if (count_before_opt) |*result| {
        defer result.deinit() catch {};
        count_before = result.get(i64, 0);
        std.debug.print("  事务前用户数: {d}\n", .{count_before});
    }

    // why: 使用 errdefer 确保错误时自动回滚
    const tx_result = performFailingTransaction(conn);

    if (tx_result) |_| {
        std.debug.print("  事务成功（不应该发生）\n", .{});
    } else |err| {
        std.debug.print("  ✓ 事务失败: {}\n", .{err});
        if (conn.err) |pg_err| {
            std.debug.print("  PostgreSQL 错误: {s}\n", .{pg_err.message});
        }
    }

    // 验证数据未被插入
    var count_after_opt = try conn.row(
        "SELECT COUNT(*) FROM zorm_examples.users",
        .{},
    );

    if (count_after_opt) |*result| {
        defer result.deinit() catch {};
        const count_after = result.get(i64, 0);
        std.debug.print("  事务后用户数: {d}\n", .{count_after});

        if (count_after == count_before) {
            std.debug.print("  ✓ 回滚成功，数据未提交\n", .{});
        } else {
            std.debug.print("  ❌ 回滚失败，数据已提交\n", .{});
        }
    }
}

fn performFailingTransaction(conn: *pg.Conn) !void {
    try conn.begin();
    errdefer conn.rollback() catch {};

    // 成功的插入
    _ = try conn.exec(
        \\INSERT INTO zorm_examples.users (name, email, created_at, updated_at)
        \\VALUES ($1, $2, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
    ,
        .{ "TX Error User", "tx_error@example.com" },
    );

    std.debug.print("  第一次插入成功\n", .{});

    // why: 故意违反唯一约束，触发错误
    _ = try conn.exec(
        \\INSERT INTO zorm_examples.users (name, email, created_at, updated_at)
        \\VALUES ($1, $2, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
    ,
        .{ "TX Error User 2", "tx_error@example.com" },
    );

    try conn.commit();
}
