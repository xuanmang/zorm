//! Schema Field Customization 示例
//!
//! 演示如何使用 comptime schema 配置自定义表字段属性
//!
//! ## 运行方式
//! ```bash
//! zig build-exe examples/schema_field_customization.zig -fno-emit-bin --mod zorm::src/zorm.zig
//! ```
//!
//! ## 功能演示
//! - 自定义列名映射
//! - 显式指定 SQL 类型
//! - UNIQUE 约束
//! - DEFAULT 值设置
//! - CHECK 约束
//! - AUTO_INCREMENT (SERIAL/BIGSERIAL)
//! - PRIMARY KEY 定义
//! - 综合使用各种约束

const std = @import("std");
const schema_mod = @import("zorm").schema;

// ============================================================================
// 示例 1: 完整的用户表定义 (来自 Story 3.2 AC)
// ============================================================================

/// 用户模型 - 展示所有 Schema 配置功能
const User = struct {
    id: i64,
    username: []const u8,
    email: []const u8,
    age: i32,
    status: []const u8,
    created_at: i64,

    pub const table_name = "users";

    pub const schema = .{
        .id = .{ .primary_key = true, .auto_increment = true },
        .username = .{ .unique = true, .sql_type = "VARCHAR(50)" },
        .email = .{ .unique = true },
        .age = .{ .check = "age >= 0 AND age <= 150" },
        .status = .{ .default = "'active'" },
        .created_at = .{ .default = "CURRENT_TIMESTAMP" },
    };
};

// ============================================================================
// 示例 2: 自定义列名映射
// ============================================================================

/// 产品模型 - 演示列名映射
const Product = struct {
    id: i64,
    product_title: []const u8, // Zig 字段名
    unit_price: f64,
    stock_quantity: i32,

    pub const table_name = "products";

    pub const schema = .{
        .id = .{ .primary_key = true, .auto_increment = true },
        .product_title = .{ .column_name = "title" }, // SQL 列名为 "title"
        .unit_price = .{ .column_name = "price" }, // SQL 列名为 "price"
        .stock_quantity = .{ .column_name = "stock" }, // SQL 列名为 "stock"
    };
};

// ============================================================================
// 示例 3: 复杂约束组合
// ============================================================================

/// 订单模型 - 演示复杂约束
const Order = struct {
    id: i32, // 使用 i32 展示 SERIAL (非 BIGSERIAL)
    order_number: []const u8,
    total_amount: f64,
    discount_percent: f32,
    order_status: []const u8,
    notes: ?[]const u8, // 可选字段

    pub const table_name = "orders";

    pub const schema = .{
        .id = .{ .primary_key = true, .auto_increment = true },
        .order_number = .{
            .column_name = "number",
            .sql_type = "VARCHAR(20)",
            .unique = true,
            .check = "LENGTH(number) = 20",
        },
        .total_amount = .{
            .check = "total_amount >= 0",
            .default = "0.0",
        },
        .discount_percent = .{
            .check = "discount_percent >= 0 AND discount_percent <= 100",
            .default = "0.0",
        },
        .order_status = .{
            .column_name = "status",
            .sql_type = "VARCHAR(20)",
            .default = "'pending'",
            .check = "status IN ('pending', 'processing', 'completed', 'cancelled')",
        },
        // notes 字段没有配置,使用默认行为 (TEXT, NULLABLE)
    };
};

// ============================================================================
// 示例函数
// ============================================================================

/// 示例 1: 用户表 SQL 生成
fn exampleUserTable(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== 示例 1: 用户表 (完整功能展示) ===\n", .{});

    const columns_sql = try schema_mod.generateColumnDefinitions(allocator, User);
    defer allocator.free(columns_sql);

    std.debug.print("生成的列定义:\n", .{});
    std.debug.print("    {s}\n", .{columns_sql});

    std.debug.print("\n完整 CREATE TABLE 语句:\n", .{});
    std.debug.print("CREATE TABLE IF NOT EXISTS users (\n", .{});
    std.debug.print("    {s}\n", .{columns_sql});
    std.debug.print(")\n", .{});

    std.debug.print("\n预期结果:\n", .{});
    std.debug.print("  - id: BIGSERIAL PRIMARY KEY\n", .{});
    std.debug.print("  - username: VARCHAR(50) UNIQUE NOT NULL\n", .{});
    std.debug.print("  - email: TEXT UNIQUE NOT NULL\n", .{});
    std.debug.print("  - age: INTEGER NOT NULL CHECK (age >= 0 AND age <= 150)\n", .{});
    std.debug.print("  - status: TEXT NOT NULL DEFAULT 'active'\n", .{});
    std.debug.print("  - created_at: BIGINT NOT NULL DEFAULT CURRENT_TIMESTAMP\n", .{});
}

/// 示例 2: 产品表 SQL 生成 (列名映射)
fn exampleProductTable(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== 示例 2: 产品表 (列名映射) ===\n", .{});

    const columns_sql = try schema_mod.generateColumnDefinitions(allocator, Product);
    defer allocator.free(columns_sql);

    std.debug.print("生成的列定义:\n", .{});
    std.debug.print("    {s}\n", .{columns_sql});

    std.debug.print("\n完整 CREATE TABLE 语句:\n", .{});
    std.debug.print("CREATE TABLE IF NOT EXISTS products (\n", .{});
    std.debug.print("    {s}\n", .{columns_sql});
    std.debug.print(")\n", .{});

    std.debug.print("\n说明:\n", .{});
    std.debug.print("  - Zig 字段 'product_title' → SQL 列 'title'\n", .{});
    std.debug.print("  - Zig 字段 'unit_price' → SQL 列 'price'\n", .{});
    std.debug.print("  - Zig 字段 'stock_quantity' → SQL 列 'stock'\n", .{});
}

/// 示例 3: 订单表 SQL 生成 (复杂约束)
fn exampleOrderTable(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== 示例 3: 订单表 (复杂约束组合) ===\n", .{});

    const columns_sql = try schema_mod.generateColumnDefinitions(allocator, Order);
    defer allocator.free(columns_sql);

    std.debug.print("生成的列定义:\n", .{});
    std.debug.print("    {s}\n", .{columns_sql});

    std.debug.print("\n完整 CREATE TABLE 语句:\n", .{});
    std.debug.print("CREATE TABLE IF NOT EXISTS orders (\n", .{});
    std.debug.print("    {s}\n", .{});
    std.debug.print(")\n", .{});

    std.debug.print("\n特点:\n", .{});
    std.debug.print("  - id 使用 SERIAL (因为是 i32)\n", .{});
    std.debug.print("  - number 列包含 UNIQUE + CHECK + 自定义类型\n", .{});
    std.debug.print("  - total_amount 和 discount_percent 都有 CHECK + DEFAULT\n", .{});
    std.debug.print("  - status 使用 CHECK 限制可选值\n", .{});
    std.debug.print("  - notes 字段可空,没有特殊配置\n", .{});
}

/// 示例 4: Schema 配置检测
fn exampleSchemaDetection() !void {
    std.debug.print("\n=== 示例 4: Schema 配置检测 ===\n", .{});

    std.debug.print("User 结构体有 schema 配置: {}\n", .{comptime schema_mod.hasSchemaConfig(User)});
    std.debug.print("Product 结构体有 schema 配置: {}\n", .{comptime schema_mod.hasSchemaConfig(Product)});

    // 没有 schema 配置的结构体
    const SimpleModel = struct {
        id: i64,
        name: []const u8,
    };

    std.debug.print("SimpleModel 结构体有 schema 配置: {}\n", .{comptime schema_mod.hasSchemaConfig(SimpleModel)});

    std.debug.print("\n获取字段配置:\n", .{});
    const id_schema = comptime schema_mod.getFieldSchema(User, "id");
    std.debug.print("  User.id - primary_key: {}, auto_increment: {}\n", .{ id_schema.primary_key, id_schema.auto_increment });

    const username_schema = comptime schema_mod.getFieldSchema(User, "username");
    std.debug.print("  User.username - unique: {}, sql_type: {?s}\n", .{ username_schema.unique, username_schema.sql_type });

    const age_schema = comptime schema_mod.getFieldSchema(User, "age");
    std.debug.print("  User.age - check: {?s}\n", .{age_schema.check});
}

/// 示例 5: SERIAL vs BIGSERIAL
fn exampleSerialTypes(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== 示例 5: SERIAL vs BIGSERIAL ===\n", .{});

    const SmallTable = struct {
        id: i32, // SERIAL

        pub const schema = .{
            .id = .{ .primary_key = true, .auto_increment = true },
        };
    };

    const BigTable = struct {
        id: i64, // BIGSERIAL

        pub const schema = .{
            .id = .{ .primary_key = true, .auto_increment = true },
        };
    };

    const small_sql = try schema_mod.generateColumnDefinitions(allocator, SmallTable);
    defer allocator.free(small_sql);

    const big_sql = try schema_mod.generateColumnDefinitions(allocator, BigTable);
    defer allocator.free(big_sql);

    std.debug.print("i32 + auto_increment → {s}\n", .{small_sql});
    std.debug.print("i64 + auto_increment → {s}\n", .{big_sql});

    std.debug.print("\nPostgreSQL 说明:\n", .{});
    std.debug.print("  - SERIAL = INTEGER + AUTO_INCREMENT\n", .{});
    std.debug.print("  - BIGSERIAL = BIGINT + AUTO_INCREMENT\n", .{});
    std.debug.print("  - PostgreSQL 会自动创建序列 (sequence)\n", .{});
}

// ============================================================================
// 主函数
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n" ++ "=" ** 70 ++ "\n", .{});
    std.debug.print("  ZORM Schema Field Customization 示例\n", .{});
    std.debug.print("=" ** 70 ++ "\n", .{});

    try exampleUserTable(allocator);
    try exampleProductTable(allocator);
    try exampleOrderTable(allocator);
    try exampleSchemaDetection();
    try exampleSerialTypes(allocator);

    std.debug.print("\n" ++ "=" ** 70 ++ "\n", .{});
    std.debug.print("  所有示例运行完成\n", .{});
    std.debug.print("=" ** 70 ++ "\n\n", .{});

    std.debug.print("使用方式:\n", .{});
    std.debug.print("  1. 在结构体中定义 `pub const schema = .{{ ... }};`\n", .{});
    std.debug.print("  2. 为每个字段配置属性 (column_name, sql_type, unique, etc.)\n", .{});
    std.debug.print("  3. 调用 schema.generateColumnDefinitions(allocator, T)\n", .{});
    std.debug.print("  4. 生成的 SQL 包含所有约束和配置\n\n", .{});
}
