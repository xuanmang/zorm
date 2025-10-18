//! DELETE 操作示例
//!
//! 学习目标:
//! - 执行 DELETE 操作
//! - 条件删除
//! - 软删除 vs 硬删除
//!
//! 对应功能需求: FR2
//! 难度: 基础

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 05: DELETE 操作 ===\n\n", .{});

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

    // 示例 1: 单条删除
    try singleDelete(&conn);

    // 示例 2: 条件删除
    try conditionalDelete(&conn);

    // 示例 3: 使用 RETURNING
    try deleteWithReturning(&conn);

    // 示例 4: 级联删除
    try cascadeDelete(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn singleDelete(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 单条删除\n", .{});

    // 先插入一条测试数据
    var insert_result_opt = try conn.row(
        \\INSERT INTO zorm_examples.users (name, email, created_at, updated_at)
        \\VALUES ($1, $2, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
        \\RETURNING id
    ,
        .{ "Test User", "test@example.com" },
    );

    if (insert_result_opt) |*insert_result| {
        defer insert_result.deinit() catch {};
        const user_id = insert_result.get(i64, 0);
        std.debug.print("  创建测试用户，ID: {d}\n", .{user_id});

        // 删除刚创建的用户
        const affected = try conn.exec(
            "DELETE FROM zorm_examples.users WHERE id = $1",
            .{user_id},
        );

        if (affected) |rows| {
            std.debug.print("  ✓ 删除成功，影响 {d} 行\n\n", .{rows});
        }
    }
}

fn conditionalDelete(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: 条件删除\n", .{});

    // 删除所有归档状态的文章
    const affected = try conn.exec(
        "DELETE FROM zorm_examples.posts WHERE status = 'archived'",
        .{},
    );

    if (affected) |rows| {
        std.debug.print("  ✓ 删除了 {d} 篇归档文章\n\n", .{rows});
    }
}

fn deleteWithReturning(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: 使用 RETURNING 获取删除的记录\n", .{});

    // 先插入测试数据
    _ = try conn.exec(
        \\INSERT INTO zorm_examples.tags (name)
        \\VALUES ('ToDelete1'), ('ToDelete2')
        \\ON CONFLICT (name) DO NOTHING
    ,
        .{},
    );

    // 删除并返回删除的记录
    var result = try conn.query(
        \\DELETE FROM zorm_examples.tags
        \\WHERE name LIKE 'ToDelete%'
        \\RETURNING id, name
    ,
        .{},
    );
    defer result.deinit();

    std.debug.print("  删除的标签:\n", .{});
    var count: usize = 0;
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const name = row.get([]const u8, 1);
        std.debug.print("    - [{d}] {s}\n", .{ id, name });
        count += 1;
    }
    std.debug.print("  总计删除: {d} 条\n\n", .{count});
}

fn cascadeDelete(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 4: 级联删除\n", .{});

    // 先创建测试用户和文章
    var user_result_opt = try conn.row(
        \\INSERT INTO zorm_examples.users (name, email, created_at, updated_at)
        \\VALUES ($1, $2, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
        \\RETURNING id
    ,
        .{ "Cascade Test User", "cascade@example.com" },
    );

    if (user_result_opt) |*user_result| {
        defer user_result.deinit() catch {};
        const user_id = user_result.get(i64, 0);
        std.debug.print("  创建测试用户，ID: {d}\n", .{user_id});

        // 为该用户创建文章
        _ = try conn.exec(
            \\INSERT INTO zorm_examples.posts (user_id, title, content, status, created_at, updated_at)
            \\VALUES ($1, $2, $3, $4, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
        ,
            .{ user_id, "Test Post", "Content", "draft" },
        );
        std.debug.print("  为用户创建了一篇文章\n", .{});

        // 查询该用户的文章数
        {
            var count_opt = try conn.row(
                "SELECT COUNT(*) FROM zorm_examples.posts WHERE user_id = $1",
                .{user_id},
            );
            if (count_opt) |*count_result| {
                defer count_result.deinit() catch {};
                const post_count = count_result.get(i64, 0);
                std.debug.print("  用户当前文章数: {d}\n", .{post_count});
            }
        }

        // 删除用户（由于设置了 ON DELETE CASCADE，相关文章会自动删除）
        // why: 级联删除确保数据一致性，避免孤立记录
        const affected = try conn.exec(
            "DELETE FROM zorm_examples.users WHERE id = $1",
            .{user_id},
        );

        if (affected) |rows| {
            std.debug.print("  ✓ 删除用户成功，影响 {d} 行\n", .{rows});
        }

        // 验证文章已被级联删除
        {
            var count_opt = try conn.row(
                "SELECT COUNT(*) FROM zorm_examples.posts WHERE user_id = $1",
                .{user_id},
            );
            if (count_opt) |*count_result| {
                defer count_result.deinit() catch {};
                const post_count = count_result.get(i64, 0);
                std.debug.print("  用户删除后文章数: {d} (已级联删除)\n", .{post_count});
            }
        }
    }
}
