//! Schema 管理和迁移示例
//!
//! 学习目标:
//! - 创建和修改数据库表结构
//! - 使用迁移管理 Schema 变更
//! - 添加索引和约束
//! - 迁移版本控制
//!
//! 对应功能需求: FR6
//! 难度: 高级

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 11: Schema 管理和迁移 ===\n\n", .{});

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

    // 示例 1: 创建迁移记录表
    try createMigrationTable(&conn);

    // 示例 2: 创建新表
    try createNewTable(&conn);

    // 示例 3: 添加列（修改表结构）
    try addColumn(&conn);

    // 示例 4: 创建索引
    try createIndex(&conn);

    // 示例 5: 数据迁移
    try migrateData(&conn);

    // 示例 6: 查看迁移历史
    try showMigrationHistory(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn createMigrationTable(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: 创建迁移记录表\n", .{});

    // why: 迁移记录表用于跟踪已执行的迁移
    _ = try conn.exec(
        \\CREATE TABLE IF NOT EXISTS zorm_examples.schema_migrations (
        \\    id SERIAL PRIMARY KEY,
        \\    version VARCHAR(255) NOT NULL UNIQUE,
        \\    name VARCHAR(255) NOT NULL,
        \\    applied_at DOUBLE PRECISION NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())
        \\)
    ,
        .{},
    );

    std.debug.print("  ✓ 迁移记录表已创建\n\n", .{});
}

fn createNewTable(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: 创建新表（迁移 001）\n", .{});

    const version = "001";
    const migration_name = "create_categories_table";

    // 检查是否已执行
    var check_opt = try conn.row(
        "SELECT COUNT(*) FROM zorm_examples.schema_migrations WHERE version = $1",
        .{version},
    );

    var already_applied = false;
    if (check_opt) |*result| {
        defer result.deinit() catch {};
        const count = result.get(i64, 0);
        already_applied = count > 0;
    }

    if (already_applied) {
        std.debug.print("  ⏭ 迁移 {s} 已执行，跳过\n\n", .{version});
        return;
    }

    // 执行迁移
    _ = try conn.exec(
        \\CREATE TABLE IF NOT EXISTS zorm_examples.categories (
        \\    id SERIAL PRIMARY KEY,
        \\    name VARCHAR(100) NOT NULL UNIQUE,
        \\    description TEXT,
        \\    created_at DOUBLE PRECISION NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW()),
        \\    updated_at DOUBLE PRECISION NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())
        \\)
    ,
        .{},
    );

    // 记录迁移
    _ = try conn.exec(
        \\INSERT INTO zorm_examples.schema_migrations (version, name)
        \\VALUES ($1, $2)
    ,
        .{ version, migration_name },
    );

    std.debug.print("  ✓ 迁移 {s}: {s} 已执行\n\n", .{ version, migration_name });
}

fn addColumn(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: 添加列（迁移 002）\n", .{});

    const version = "002";
    const migration_name = "add_slug_to_posts";

    // 检查是否已执行
    var check_opt = try conn.row(
        "SELECT COUNT(*) FROM zorm_examples.schema_migrations WHERE version = $1",
        .{version},
    );

    var already_applied = false;
    if (check_opt) |*result| {
        defer result.deinit() catch {};
        const count = result.get(i64, 0);
        already_applied = count > 0;
    }

    if (already_applied) {
        std.debug.print("  ⏭ 迁移 {s} 已执行，跳过\n\n", .{version});
        return;
    }

    // why: 使用 IF NOT EXISTS 避免重复添加列
    _ = try conn.exec(
        \\ALTER TABLE zorm_examples.posts
        \\ADD COLUMN IF NOT EXISTS slug VARCHAR(255)
    ,
        .{},
    );

    // 为现有记录生成 slug
    _ = try conn.exec(
        \\UPDATE zorm_examples.posts
        \\SET slug = LOWER(REPLACE(title, ' ', '-'))
        \\WHERE slug IS NULL
    ,
        .{},
    );

    // 记录迁移
    _ = try conn.exec(
        \\INSERT INTO zorm_examples.schema_migrations (version, name)
        \\VALUES ($1, $2)
    ,
        .{ version, migration_name },
    );

    std.debug.print("  ✓ 迁移 {s}: {s} 已执行\n\n", .{ version, migration_name });
}

fn createIndex(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 4: 创建索引（迁移 003）\n", .{});

    const version = "003";
    const migration_name = "create_posts_indexes";

    // 检查是否已执行
    var check_opt = try conn.row(
        "SELECT COUNT(*) FROM zorm_examples.schema_migrations WHERE version = $1",
        .{version},
    );

    var already_applied = false;
    if (check_opt) |*result| {
        defer result.deinit() catch {};
        const count = result.get(i64, 0);
        already_applied = count > 0;
    }

    if (already_applied) {
        std.debug.print("  ⏭ 迁移 {s} 已执行，跳过\n\n", .{version});
        return;
    }

    // why: 索引可以大幅提升查询性能
    _ = try conn.exec(
        "CREATE INDEX IF NOT EXISTS idx_posts_user_id ON zorm_examples.posts(user_id)",
        .{},
    );

    _ = try conn.exec(
        "CREATE INDEX IF NOT EXISTS idx_posts_status ON zorm_examples.posts(status)",
        .{},
    );

    _ = try conn.exec(
        "CREATE INDEX IF NOT EXISTS idx_posts_slug ON zorm_examples.posts(slug)",
        .{},
    );

    // 记录迁移
    _ = try conn.exec(
        \\INSERT INTO zorm_examples.schema_migrations (version, name)
        \\VALUES ($1, $2)
    ,
        .{ version, migration_name },
    );

    std.debug.print("  ✓ 迁移 {s}: {s} 已执行\n", .{ version, migration_name });
    std.debug.print("  创建了 3 个索引:\n", .{});
    std.debug.print("    - idx_posts_user_id\n", .{});
    std.debug.print("    - idx_posts_status\n", .{});
    std.debug.print("    - idx_posts_slug\n\n", .{});
}

fn migrateData(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 5: 数据迁移（迁移 004）\n", .{});

    const version = "004";
    const migration_name = "normalize_post_status";

    // 检查是否已执行
    var check_opt = try conn.row(
        "SELECT COUNT(*) FROM zorm_examples.schema_migrations WHERE version = $1",
        .{version},
    );

    var already_applied = false;
    if (check_opt) |*result| {
        defer result.deinit() catch {};
        const count = result.get(i64, 0);
        already_applied = count > 0;
    }

    if (already_applied) {
        std.debug.print("  ⏭ 迁移 {s} 已执行，跳过\n\n", .{version});
        return;
    }

    // why: 数据迁移用于调整现有数据以符合新规则
    const affected = try conn.exec(
        \\UPDATE zorm_examples.posts
        \\SET status = 'archived'
        \\WHERE status = 'deleted'
    ,
        .{},
    );

    if (affected) |rows| {
        std.debug.print("  ✓ 数据迁移完成，更新了 {d} 行\n", .{rows});
    }

    // 记录迁移
    _ = try conn.exec(
        \\INSERT INTO zorm_examples.schema_migrations (version, name)
        \\VALUES ($1, $2)
    ,
        .{ version, migration_name },
    );

    std.debug.print("  ✓ 迁移 {s}: {s} 已执行\n\n", .{ version, migration_name });
}

fn showMigrationHistory(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 6: 查看迁移历史\n", .{});

    var result = try conn.query(
        \\SELECT version, name, applied_at
        \\FROM zorm_examples.schema_migrations
        \\ORDER BY id
    ,
        .{},
    );
    defer result.deinit();

    std.debug.print("  迁移历史:\n", .{});
    var count: usize = 0;
    while (try result.next()) |row| {
        const version = row.get([]const u8, 0);
        const name = row.get([]const u8, 1);
        const applied_at = row.get(f64, 2);

        std.debug.print("    [{s}] {s} (applied: {d})\n", .{ version, name, applied_at });
        count += 1;
    }
    std.debug.print("  总计: {d} 个迁移\n", .{count});
}
