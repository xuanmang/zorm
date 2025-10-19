//! CREATE TABLE 基础示例
//!
//! 演示如何使用 ZORM CREATE TABLE 查询构建器从 Zig 结构体自动创建数据库表。
//!
//! ## 运行方式
//! ```bash
//! zig build-exe examples/create_table_basic.zig --mod zorm::src/zorm.zig
//! ./create_table_basic
//! ```
//!
//! ## 功能演示
//! - 从 Zig struct 自动生成表定义
//! - 类型映射 (Zig类型 → PostgreSQL类型)
//! - 可选类型处理 (NULLABLE)
//! - 主键自动检测
//! - IF NOT EXISTS 子句
//! - SQL 预览和执行

const std = @import("std");
const zorm = @import("zorm");

// ============================================================================
// 数据模型定义
// ============================================================================

/// 用户模型
///
/// 演示完整的表定义，包含:
/// - 主键 (id)
/// - 非空字段 (name, email, age)
/// - 可选字段 (bio)
/// - 布尔字段 (is_active)
/// - 时间戳 (created_at)
const User = struct {
    id: i64, // 自动检测为主键
    name: []const u8, // TEXT NOT NULL
    email: []const u8, // TEXT NOT NULL
    age: i32, // INTEGER NOT NULL
    bio: ?[]const u8, // TEXT (可空)
    is_active: bool, // BOOLEAN NOT NULL
    created_at: i64, // BIGINT NOT NULL (Unix timestamp)

    pub const table_name = "users";
};

/// 产品模型
///
/// 演示不同的数据类型:
/// - 整数类型 (id, stock)
/// - 浮点类型 (price)
/// - 文本类型 (title, description)
/// - 可选类型 (description)
const Product = struct {
    id: i64, // 主键
    title: []const u8, // TEXT NOT NULL
    price: f64, // DOUBLE PRECISION NOT NULL
    stock: u32, // INTEGER NOT NULL
    description: ?[]const u8, // TEXT (可空)

    pub const table_name = "products";
};

/// 简单模型
///
/// 最小化示例，只包含 id 和一个字段
const Simple = struct {
    id: i64,
    value: i32,

    pub const table_name = "simple_items";
};

// ============================================================================
// 示例函数
// ============================================================================

/// 示例 1: 基础 CREATE TABLE (无连接)
///
/// 演示如何生成 CREATE TABLE SQL 语句而不实际执行
fn exampleBasicSQLGeneration(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== 示例 1: 基础 SQL 生成 ===\n", .{});

    // 使用反射模块直接生成 CREATE TABLE SQL
    const reflection = @import("zorm").reflection;

    const sql = try reflection.generateCreateTableSQL(User, .postgresql, allocator);
    defer allocator.free(sql);

    std.debug.print("生成的 SQL:\n{s}\n", .{sql});
}

/// 示例 2: IF NOT EXISTS 子句
///
/// 演示如何添加 IF NOT EXISTS，避免表已存在时的错误
fn exampleIfNotExists(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== 示例 2: IF NOT EXISTS 子句 ===\n", .{});

    const table_mod = @import("zorm").schema;
    var table = try table_mod.Table.init(allocator, "products");
    defer table.deinit();

    // 添加列
    var id_col = table_mod.Column.init("id", .bigint);
    _ = id_col.setPrimaryKey();
    _ = try table.addColumn(id_col);

    var title_col = table_mod.Column.init("title", .text);
    _ = title_col.setNotNull();
    _ = try table.addColumn(title_col);

    var price_col = table_mod.Column.init("price", .double);
    _ = price_col.setNotNull();
    _ = try table.addColumn(price_col);

    const sql = try table.toSQL(.postgresql);
    defer allocator.free(sql);

    // 手动添加 IF NOT EXISTS (实际使用时通过 CreateTableQuery.ifNotExists())
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "CREATE TABLE IF NOT EXISTS ");
    try buf.appendSlice(allocator, sql[13..]); // 跳过 "CREATE TABLE "

    const final_sql = try buf.toOwnedSlice(allocator);
    defer allocator.free(final_sql);

    std.debug.print("带 IF NOT EXISTS 的 SQL:\n{s}\n", .{final_sql});
}

/// 示例 3: 类型映射演示
///
/// 展示 Zig 类型到 PostgreSQL 类型的完整映射
fn exampleTypeMapping() !void {
    std.debug.print("\n=== 示例 3: 类型映射 ===\n", .{});

    const types_mod = @import("zorm").types;

    std.debug.print("Zig 类型 → PostgreSQL 类型:\n", .{});
    std.debug.print("  i8, i16      → {s}\n", .{comptime types_mod.zigToSQLType(i8)});
    std.debug.print("  i32          → {s}\n", .{comptime types_mod.zigToSQLType(i32)});
    std.debug.print("  i64          → {s}\n", .{comptime types_mod.zigToSQLType(i64)});
    std.debug.print("  u8, u16, u32 → {s}\n", .{comptime types_mod.zigToSQLType(u32)});
    std.debug.print("  u64          → {s}\n", .{comptime types_mod.zigToSQLType(u64)});
    std.debug.print("  f32          → {s}\n", .{comptime types_mod.zigToSQLType(f32)});
    std.debug.print("  f64          → {s}\n", .{comptime types_mod.zigToSQLType(f64)});
    std.debug.print("  bool         → {s}\n", .{comptime types_mod.zigToSQLType(bool)});
    std.debug.print("  []const u8   → {s}\n", .{comptime types_mod.zigToSQLType([]const u8)});
    std.debug.print("  ?T           → 对应类型 + 可空\n", .{});
}

/// 示例 4: 列定义生成
///
/// 演示字段反射和列定义自动生成
fn exampleColumnGeneration(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== 示例 4: 列定义生成 ===\n", .{});

    const reflection = @import("zorm").reflection;

    const columns = try reflection.generateColumns(User, allocator);
    defer allocator.free(columns);

    std.debug.print("从 User struct 生成的列定义:\n", .{});
    for (columns) |col| {
        std.debug.print("  {s}: {s}", .{ col.name, @tagName(col.column_type) });
        if (col.primary_key) std.debug.print(" PRIMARY KEY", .{});
        if (!col.nullable) std.debug.print(" NOT NULL", .{});
        if (col.nullable) std.debug.print(" (NULLABLE)", .{});
        std.debug.print("\n", .{});
    }
}

/// 示例 5: 多种数据类型
///
/// 展示各种数据类型的表定义
fn exampleComplexTypes(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== 示例 5: 复杂类型示例 ===\n", .{});

    const ComplexModel = struct {
        id: i64,
        uuid: []const u8,
        count: i32,
        price: f64,
        discount: ?f32,
        active: bool,
        description: ?[]const u8,
        created_at: i64,

        pub const table_name = "complex_models";
    };

    const reflection = @import("zorm").reflection;
    const sql = try reflection.generateCreateTableSQL(ComplexModel, .postgresql, allocator);
    defer allocator.free(sql);

    std.debug.print("复杂模型 SQL:\n{s}\n", .{sql});
}

/// 示例 6: 手动列定义
///
/// 演示如何手动构建列定义（用于需要精确控制的场景）
fn exampleManualColumns(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== 示例 6: 手动列定义 ===\n", .{});

    const table_mod = @import("zorm").schema;

    var table = try table_mod.Table.init(allocator, "custom_table");
    defer table.deinit();

    // 主键列，带自增
    var id_col = table_mod.Column.init("id", .bigint);
    _ = id_col.setPrimaryKey();
    _ = try table.addColumn(id_col);

    // 唯一约束列
    var email_col = table_mod.Column.init("email", .varchar);
    _ = email_col.setUnique().setNotNull();
    _ = try table.addColumn(email_col);

    // 带默认值的列
    var status_col = table_mod.Column.init("status", .varchar);
    _ = status_col.setDefault("'active'").setNotNull();
    _ = try table.addColumn(status_col);

    // 带检查约束的列
    var age_col = table_mod.Column.init("age", .int);
    _ = age_col.setCheck("age >= 0 AND age <= 150").setNotNull();
    _ = try table.addColumn(age_col);

    const sql = try table.toSQL(.postgresql);
    defer allocator.free(sql);

    std.debug.print("手动定义的表 SQL:\n{s}\n", .{sql});
}

// ============================================================================
// 主函数
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n" ++ "=" ** 70 ++ "\n", .{});
    std.debug.print("  ZORM CREATE TABLE 查询构建器示例\n", .{});
    std.debug.print("=" ** 70 ++ "\n", .{});

    // 运行所有示例
    try exampleBasicSQLGeneration(allocator);
    try exampleIfNotExists(allocator);
    try exampleTypeMapping();
    try exampleColumnGeneration(allocator);
    try exampleComplexTypes(allocator);
    try exampleManualColumns(allocator);

    std.debug.print("\n" ++ "=" ** 70 ++ "\n", .{});
    std.debug.print("  所有示例运行完成\n", .{});
    std.debug.print("=" ** 70 ++ "\n\n", .{});

    std.debug.print("注意:\n", .{});
    std.debug.print("  1. 以上示例仅生成 SQL，不连接真实数据库\n", .{});
    std.debug.print("  2. 实际使用时，通过 db.newCreateTable(User) 创建查询构建器\n", .{});
    std.debug.print("  3. 调用 .ifNotExists().exec() 执行 DDL 语句\n", .{});
    std.debug.print("  4. 示例代码位于 examples/create_table_basic.zig\n", .{});
}
