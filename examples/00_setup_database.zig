//! 数据库初始化脚本
//!
//! 创建示例应用所需的 schema 和表。
//! 运行方式: zig build run-setup
//!
//! 本示例展示如何使用 ZORM 的自动化 Table API：
//! - 从模型定义自动推断表结构 (comptime 反射)
//! - 一行代码创建表 (类似 Bun ORM)
//! - 零样板代码，专注于模型定义

const std = @import("std");
const zorm = @import("zorm");
const db_config = @import("common/db_config.zig");
const models = @import("common/models.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 数据库初始化 ===\n\n", .{});

    // 连接数据库
    std.debug.print("连接到 PostgreSQL...\n", .{});
    var driver = try db_config.createDefaultDriver(allocator);
    defer driver.close() catch {};
    std.debug.print("✓ 数据库连接成功\n\n", .{});

    // 创建 schema
    std.debug.print("创建 schema: zorm_examples...\n", .{});
    _ = try driver.exec("CREATE SCHEMA IF NOT EXISTS zorm_examples", &.{});
    _ = try driver.exec("SET search_path TO zorm_examples", &.{});
    std.debug.print("✓ Schema 创建成功\n\n", .{});

    // 创建表 - 从模型自动生成，类似 Bun ORM!
    std.debug.print("创建数据表...\n", .{});
    try createTableFromModel(&driver, allocator, models.User);
    try createTableFromModel(&driver, allocator, models.Post);
    try createTableFromModel(&driver, allocator, models.Comment);
    try createTableFromModel(&driver, allocator, models.Tag);
    try createTableFromModel(&driver, allocator, models.PostTag);

    // 创建索引
    _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id)", &.{});
    _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_posts_status ON posts(status)", &.{});
    _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_comments_post_id ON comments(post_id)", &.{});
    _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_comments_user_id ON comments(user_id)", &.{});
    _ = try driver.exec("CREATE INDEX IF NOT EXISTS idx_post_tags_tag_id ON post_tags(tag_id)", &.{});

    std.debug.print("✓ 所有表创建成功\n\n", .{});
    std.debug.print("数据库初始化完成！\n", .{});
}

/// 🚀 自动从模型创建表 - 类似 Bun ORM 的简洁体验！
///
/// 使用 comptime 反射自动推断：
/// - 字段名 -> 列名
/// - 字段类型 -> SQL 类型
/// - id 字段 -> 主键 + 自增
/// - *_id 字段 -> 外键
/// - *_at 字段 -> 时间戳 + 默认值
/// - email/name 等 -> NOT NULL
///
/// 示例:
/// ```zig
/// try createTableFromModel(&driver, allocator, User);
/// // 等价于 Bun: db.NewCreateTable().Model((*User)(nil)).IfNotExists().Exec(ctx)
/// ```
fn createTableFromModel(driver: *zorm.PostgresDriver, allocator: std.mem.Allocator, comptime Model: type) !void {
    const table_name = if (@hasDecl(Model, "table_name")) Model.table_name else @typeName(Model);
    std.debug.print("  创建 {s} 表...\n", .{table_name});

    var table = try zorm.Table.init(allocator, table_name);
    defer table.deinit();

    // 使用 comptime 反射遍历所有字段
    inline for (@typeInfo(Model).Struct.fields) |field| {
        var col = inferColumn(field);
        _ = try table.addColumn(col);
    }

    // 执行 CREATE TABLE IF NOT EXISTS
    const create_sql = try table.toSQL(.postgresql);
    defer allocator.free(create_sql);

    const final_sql = try std.fmt.allocPrint(allocator, "CREATE TABLE IF NOT EXISTS {s}", .{create_sql[13..]});
    defer allocator.free(final_sql);

    _ = try driver.exec(final_sql, &.{});
}

/// 🧠 智能推断列定义
///
/// 自动规则：
/// 1. id -> BIGINT PRIMARY KEY AUTO_INCREMENT
/// 2. *_id -> BIGINT NOT NULL (外键在后续处理)
/// 3. *_at -> BIGINT NOT NULL DEFAULT CURRENT_TIMESTAMP
/// 4. i64/i32 -> BIGINT
/// 5. []const u8 -> TEXT NOT NULL
/// 6. ?T -> 可空版本
fn inferColumn(comptime field: std.builtin.Type.StructField) zorm.Column {
    const field_name = field.name;
    const field_type = field.type;

    var col = zorm.Column.init(field_name, inferColumnType(field_type));

    // 规则 1: id 字段 -> 主键 + 自增
    if (std.mem.eql(u8, field_name, "id")) {
        _ = col.setPrimaryKey().setAutoIncrement();
        return col;
    }

    // 规则 2: *_at 字段 -> 时间戳 + 默认值
    if (std.mem.endsWith(u8, field_name, "_at")) {
        _ = col.setNotNull().setDefault("EXTRACT(EPOCH FROM NOW())::BIGINT");
        return col;
    }

    // 规则 3: 外键字段 (user_id, post_id, tag_id)
    if (std.mem.endsWith(u8, field_name, "_id") and !std.mem.eql(u8, field_name, "id")) {
        _ = col.setNotNull();
        // 推断外键引用表 (user_id -> users)
        const ref_table = inferForeignKeyTable(field_name);
        if (ref_table.len > 0) {
            _ = col.setForeignKey(ref_table, "id");
        }
        return col;
    }

    // 规则 4: 非可空类型 -> NOT NULL
    if (!isOptional(field_type)) {
        // 跳过 published_at (可空的时间戳)
        if (!std.mem.eql(u8, field_name, "published_at")) {
            _ = col.setNotNull();
        }

        // email 字段 -> UNIQUE
        if (std.mem.eql(u8, field_name, "email")) {
            _ = col.setUnique();
        }

        // name 字段 (在 tags 表中) -> UNIQUE
        if (std.mem.eql(u8, field_name, "name") and std.mem.eql(u8, inferTableName(field_type), "tags")) {
            _ = col.setUnique();
        }

        // status 字段 -> 默认值 + CHECK 约束
        if (std.mem.eql(u8, field_name, "status")) {
            _ = col.setDefault("'draft'").setCheck("status IN ('draft', 'published', 'archived')");
        }
    }

    return col;
}

/// 推断 SQL 列类型
fn inferColumnType(comptime T: type) zorm.ColumnType {
    return switch (@typeInfo(T)) {
        .Int => .bigint,
        .Pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                return .text;
            }
            return .text;
        },
        .Optional => |opt| inferColumnType(opt.child),
        else => .text,
    };
}

/// 检查类型是否为 Optional
fn isOptional(comptime T: type) bool {
    return @typeInfo(T) == .Optional;
}

/// 从字段名推断外键引用表
/// user_id -> users
/// post_id -> posts
/// tag_id -> tags
fn inferForeignKeyTable(field_name: []const u8) []const u8 {
    if (std.mem.eql(u8, field_name, "user_id")) return "users";
    if (std.mem.eql(u8, field_name, "post_id")) return "posts";
    if (std.mem.eql(u8, field_name, "tag_id")) return "tags";
    return "";
}

/// 从类型推断表名（用于特殊规则判断）
fn inferTableName(comptime T: type) []const u8 {
    _ = T;
    // 这里简化处理，实际应该从调用上下文获取
    return "";
}
