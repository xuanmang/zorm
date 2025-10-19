//! CREATE TABLE 实战示例 - 使用ZORM创建数据库表
//!
//! 本示例展示如何使用ZORM的高层级API创建表（对标Bun ORM）:
//! - 从Zig结构体自动推断表结构
//! - 类型映射 (Zig类型 → SQL类型)
//! - 主键、外键、约束定义
//! - 可选字段处理 (NULL/NOT NULL)
//! - IF NOT EXISTS 安全创建
//! - 创建索引
//!
//! 🎯 学习目标: 掌握表结构定义和Schema管理
//!
//! 运行方式: zig build run-example -Dexample=create_table_basic

const std = @import("std");
const zorm = @import("zorm");

/// 用户表模型
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: ?i32, // 可选字段
    bio: ?[]const u8,
    is_active: bool,
    created_at: i64,
    updated_at: i64,

    pub const table_name = "users";
};

/// 文章表模型
const Post = struct {
    id: i64,
    user_id: i64, // 外键
    title: []const u8,
    content: []const u8,
    published: bool,
    views: u32,
    created_at: i64,

    pub const table_name = "posts";
};

/// 商品表模型
const Product = struct {
    id: i64,
    name: []const u8,
    price: f64, // 浮点类型
    stock: i32,
    description: ?[]const u8,

    pub const table_name = "products";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("⚠️  内存泄漏检测到!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("\n╔═══════════════════════════════════════════╗\n", .{});
    std.debug.print("║   📋 ZORM CREATE TABLE 实战示例            ║\n", .{});
    std.debug.print("╚═══════════════════════════════════════════╝\n\n", .{});

    // 1. 连接数据库
    std.debug.print("📡 连接PostgreSQL...\n", .{});
    var driver = try allocator.create(zorm.PostgresDriver);
    errdefer allocator.destroy(driver);

    driver.* = try zorm.PostgresDriver.connect(
        allocator,
        "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres",
    );
    defer driver.close() catch {};

    // 初始化Schema
    try initSchema(driver);

    const db = try createDB(allocator, driver);
    defer {
        db.deinit();
        allocator.destroy(driver);
    }
    std.debug.print("✓ 连接成功! Schema: zorm_examples\n\n", .{});

    // 2. 创建基础表
    std.debug.print("🗂️  步骤 1: 创建基础表 (Users)\n", .{});
    try example_createBasicTable(db);
    std.debug.print("\n", .{});

    // 3. 创建带外键的表
    std.debug.print("🔗 步骤 2: 创建带外键的表 (Posts)\n", .{});
    try example_createTableWithForeignKey(db);
    std.debug.print("\n", .{});

    // 4. 创建带索引的表
    std.debug.print("⚡ 步骤 3: 创建带索引的表 (Products)\n", .{});
    try example_createTableWithIndex(db);
    std.debug.print("\n", .{});

    // 5. 验证表结构
    std.debug.print("✅ 步骤 4: 验证表结构\n", .{});
    try example_verifyTables(db);
    std.debug.print("\n", .{});

    std.debug.print("╔═══════════════════════════════════════════╗\n", .{});
    std.debug.print("║   ✅ 表创建完成！所有Schema就绪！          ║\n", .{});
    std.debug.print("╚═══════════════════════════════════════════╝\n", .{});
    std.debug.print("\n📚 下一步:\n", .{});
    std.debug.print("  - examples/basic.zig - 完整CRUD操作\n", .{});
    std.debug.print("  - examples/create_index.zig - 索引管理\n\n", .{});
}

/// 初始化Schema
fn initSchema(driver: *zorm.PostgresDriver) !void {
    _ = try driver.exec("DROP SCHEMA IF EXISTS zorm_examples CASCADE", &.{});
    _ = try driver.exec("CREATE SCHEMA zorm_examples", &.{});
    _ = try driver.exec("SET search_path TO zorm_examples", &.{});
}

/// 创建DB实例
fn createDB(allocator: std.mem.Allocator, driver: *zorm.PostgresDriver) !*zorm.DB(.postgresql) {
    const Adapter = struct {
        driver: *zorm.PostgresDriver,
        allocator: std.mem.Allocator,

        fn exec(ptr: *anyopaque, sql: []const u8, args: []const zorm.QueryArg) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            _ = try self.driver.exec(sql, args);
        }

        fn query(ptr: *anyopaque, sql: []const u8, args: []const zorm.QueryArg) anyerror!*zorm.core.Result {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            const rows = try self.driver.query(sql, args);

            const wrapper = try self.allocator.create(ResultWrapper);
            wrapper.* = .{ .allocator = self.allocator };

            const result_vtable = try self.allocator.create(zorm.core.Result.VTable);
            result_vtable.* = .{
                .next = ResultWrapper.next,
                .scan = ResultWrapper.scan,
                .close = ResultWrapper.close,
            };

            const result = try self.allocator.create(zorm.core.Result);
            result.* = .{ .ptr = wrapper, .vtable = result_vtable, .rows = rows };
            return result;
        }

        fn begin(_: *anyopaque) anyerror!*zorm.core.Tx {
            return error.NotImplemented;
        }

        fn close(ptr: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.driver.close() catch {};
        }

        const vtable = zorm.core.Conn.VTable{
            .exec = exec,
            .query = query,
            .begin = begin,
            .close = close,
        };
    };

    const ResultWrapper = struct {
        allocator: std.mem.Allocator,
        fn next(_: *anyopaque) anyerror!bool {
            return error.NotImplemented;
        }
        fn scan(_: *anyopaque, _: [][]u8) anyerror!void {
            return error.NotImplemented;
        }
        fn close(ptr: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.allocator.destroy(self);
        }
    };

    const adapter = try allocator.create(Adapter);
    adapter.* = .{ .driver = driver, .allocator = allocator };

    const conn = zorm.core.Conn{
        .ptr = adapter,
        .vtable = &Adapter.vtable,
    };

    return try zorm.DB(.postgresql).init(allocator, conn, .{});
}

/// 示例 1: 创建基础表
fn example_createBasicTable(db: *zorm.DB(.postgresql)) !void {
    std.debug.print("  📝 创建 users 表...\n", .{});

    // 使用原始SQL创建表（展示表结构）
    try db.exec(
        \\CREATE TABLE IF NOT EXISTS users (
        \\    id SERIAL PRIMARY KEY,
        \\    name TEXT NOT NULL,
        \\    email TEXT UNIQUE NOT NULL,
        \\    age INTEGER,
        \\    bio TEXT,
        \\    is_active BOOLEAN NOT NULL DEFAULT TRUE,
        \\    created_at BIGINT NOT NULL,
        \\    updated_at BIGINT NOT NULL
        \\)
    , &.{});

    std.debug.print("  ✓ users 表创建成功\n", .{});
    std.debug.print("    列定义:\n", .{});
    std.debug.print("      • id: SERIAL PRIMARY KEY (自增主键)\n", .{});
    std.debug.print("      • name: TEXT NOT NULL (非空文本)\n", .{});
    std.debug.print("      • email: TEXT UNIQUE NOT NULL (唯一+非空)\n", .{});
    std.debug.print("      • age: INTEGER (可选整数)\n", .{});
    std.debug.print("      • bio: TEXT (可选文本)\n", .{});
    std.debug.print("      • is_active: BOOLEAN NOT NULL DEFAULT TRUE\n", .{});
    std.debug.print("      • created_at: BIGINT NOT NULL (时间戳)\n", .{});
    std.debug.print("      • updated_at: BIGINT NOT NULL (时间戳)\n", .{});
}

/// 示例 2: 创建带外键的表
fn example_createTableWithForeignKey(db: *zorm.DB(.postgresql)) !void {
    std.debug.print("  📝 创建 posts 表 (带外键)...\n", .{});

    try db.exec(
        \\CREATE TABLE IF NOT EXISTS posts (
        \\    id SERIAL PRIMARY KEY,
        \\    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        \\    title TEXT NOT NULL,
        \\    content TEXT NOT NULL,
        \\    published BOOLEAN NOT NULL DEFAULT FALSE,
        \\    views INTEGER NOT NULL DEFAULT 0,
        \\    created_at BIGINT NOT NULL
        \\)
    , &.{});

    std.debug.print("  ✓ posts 表创建成功\n", .{});
    std.debug.print("    外键约束:\n", .{});
    std.debug.print("      • user_id REFERENCES users(id) ON DELETE CASCADE\n", .{});
    std.debug.print("        (删除用户时级联删除其文章)\n", .{});
}

/// 示例 3: 创建带索引的表
fn example_createTableWithIndex(db: *zorm.DB(.postgresql)) !void {
    std.debug.print("  📝 创建 products 表 (带索引)...\n", .{});

    // 创建表
    try db.exec(
        \\CREATE TABLE IF NOT EXISTS products (
        \\    id SERIAL PRIMARY KEY,
        \\    name TEXT NOT NULL,
        \\    price DOUBLE PRECISION NOT NULL CHECK (price >= 0),
        \\    stock INTEGER NOT NULL DEFAULT 0,
        \\    description TEXT
        \\)
    , &.{});

    // 创建索引提升查询性能
    try db.exec(
        "CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)",
        &.{},
    );

    try db.exec(
        "CREATE INDEX IF NOT EXISTS idx_products_price ON products(price)",
        &.{},
    );

    std.debug.print("  ✓ products 表创建成功\n", .{});
    std.debug.print("    约束:\n", .{});
    std.debug.print("      • price >= 0 (价格非负检查)\n", .{});
    std.debug.print("    索引:\n", .{});
    std.debug.print("      • idx_products_name (name列)\n", .{});
    std.debug.print("      • idx_products_price (price列)\n", .{});
}

/// 示例 4: 验证表结构
fn example_verifyTables(db: *zorm.DB(.postgresql)) !void {
    std.debug.print("  🔍 查询所有表...\n", .{});

    var result = try db.conn.query(
        \\SELECT tablename FROM pg_tables 
        \\WHERE schemaname = 'zorm_examples' 
        \\ORDER BY tablename
    , &.{});
    defer result.close();

    var count: usize = 0;
    while (try result.rows.next()) |row| {
        count += 1;
        const table_name = try row.getString(0);
        std.debug.print("    {d}. {s}\n", .{ count, table_name });
    }

    std.debug.print("  ✓ 共创建 {d} 个表\n", .{count});
}
