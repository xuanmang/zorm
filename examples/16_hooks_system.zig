//! Hooks 系统示例
//!
//! 学习目标:
//! - 查询前后钩子
//! - 日志和审计
//! - 性能监控
//! - 查询修改和拦截
//!
//! 注意: ZORM hooks 系统尚未完全实现，此示例展示概念
//!
//! 对应功能需求: FR9
//! 难度: 高级

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

// 模拟 Hook 接口
const QueryHook = struct {
    name: []const u8,

    pub fn beforeQuery(self: *const QueryHook, sql: []const u8) void {
        std.debug.print("  [{s}] BEFORE: {s}\n", .{ self.name, sql });
    }

    pub fn afterQuery(self: *const QueryHook, sql: []const u8, elapsed_ms: i64) void {
        std.debug.print("  [{s}] AFTER: {s} ({d}ms)\n", .{ self.name, sql, elapsed_ms });
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 16: Hooks 系统 ===\n\n", .{});

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

    // 示例 1: 日志钩子
    try loggingHook(&conn);

    // 示例 2: 性能监控钩子
    try performanceHook(&conn);

    // 示例 3: 审计钩子
    try auditHook(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
    std.debug.print("\n说明: 完整的 Hooks 系统需要 ZORM 核心实现支持\n", .{});
}

fn loggingHook(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 日志钩子\n", .{});

    const hook = QueryHook{ .name = "LoggingHook" };
    const sql = "SELECT COUNT(*) FROM zorm_examples.users";

    // why: 在查询前后记录日志
    hook.beforeQuery(sql);

    const start = std.time.milliTimestamp();
    var result_opt = try conn.row(sql, .{});
    const elapsed = std.time.milliTimestamp() - start;

    if (result_opt) |*result| {
        defer result.deinit() catch {};
        const count = result.get(i64, 0);
        std.debug.print("  查询结果: {d} 个用户\n", .{count});
    }

    hook.afterQuery(sql, elapsed);
    std.debug.print("\n", .{});
}

fn performanceHook(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: 性能监控钩子\n", .{});

    const hook = QueryHook{ .name = "PerformanceHook" };

    // why: 监控慢查询，记录性能指标
    const queries = [_][]const u8{
        "SELECT COUNT(*) FROM zorm_examples.posts",
        "SELECT COUNT(*) FROM zorm_examples.tags",
        \\SELECT u.name, COUNT(p.id)
        \\FROM zorm_examples.users u
        \\LEFT JOIN zorm_examples.posts p ON u.id = p.user_id
        \\GROUP BY u.id, u.name
        ,
    };

    const slow_query_threshold_ms: i64 = 10;

    for (queries) |sql| {
        hook.beforeQuery(sql);

        const start = std.time.milliTimestamp();
        var result = try conn.query(sql, .{});
        defer result.deinit();

        // 消费结果
        while (try result.next()) |_| {}

        const elapsed = std.time.milliTimestamp() - start;
        hook.afterQuery(sql, elapsed);

        // why: 标记慢查询
        if (elapsed > slow_query_threshold_ms) {
            std.debug.print("  ⚠ 慢查询警告: {d}ms > {d}ms\n", .{ elapsed, slow_query_threshold_ms });
        }
    }

    std.debug.print("\n", .{});
}

fn auditHook(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: 审计钩子\n", .{});

    const hook = QueryHook{ .name = "AuditHook" };

    // why: 记录数据修改操作用于审计
    const audit_operations = [_]struct {
        operation: []const u8,
        sql: []const u8,
    }{
        .{
            .operation = "INSERT",
            .sql =
            \\INSERT INTO zorm_examples.tags (name)
            \\VALUES ('AuditTest')
            \\ON CONFLICT (name) DO NOTHING
            ,
        },
        .{
            .operation = "UPDATE",
            .sql = "UPDATE zorm_examples.tags SET name = name WHERE name = 'AuditTest'",
        },
        .{
            .operation = "DELETE",
            .sql = "DELETE FROM zorm_examples.tags WHERE name = 'AuditTest'",
        },
    };

    for (audit_operations) |op| {
        std.debug.print("  审计操作: {s}\n", .{op.operation});

        hook.beforeQuery(op.sql);

        const start = std.time.milliTimestamp();
        const affected = try conn.exec(op.sql, .{});
        const elapsed = std.time.milliTimestamp() - start;

        if (affected) |rows| {
            std.debug.print("  影响行数: {d}\n", .{rows});
        }

        hook.afterQuery(op.sql, elapsed);

        // why: 记录到审计日志
        std.debug.print("  ✓ 已记录审计日志\n\n", .{});
    }
}
