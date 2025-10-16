//! ZORM 基础使用示例
//!
//! 此示例展示了 ZORM 的基本功能:
//! - 数据库连接
//! - 查询构建器
//! - 类型安全的 SQL 操作
//!
//! 运行方式:
//!   zig build run-example

const std = @import("std");
const zorm = @import("zorm");

/// 用户模型
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    created_at: i64,
};

/// 文章模型
const Post = struct {
    id: i64,
    user_id: i64,
    title: []const u8,
    content: []const u8,
    created_at: i64,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 基础示例 ===\n\n", .{});

    // 示例 1: 方言系统 (编译时)
    demoDialect();

    // 示例 2: 查询构建器
    try demoQueryBuilder(allocator);

    std.debug.print("\n示例完成!\n", .{});
}

/// 示例 1: 演示方言系统的编译时特性
fn demoDialect() void {
    std.debug.print("1. 方言系统 (Dialect System)\n", .{});
    std.debug.print("   - 所有方言差异在编译时解决,零运行时开销\n\n", .{});

    // PostgreSQL
    {
        const pg = comptime zorm.Dialect.postgresql;
        std.debug.print("   PostgreSQL:\n", .{});
        std.debug.print("     占位符: {s}\n", .{comptime pg.placeholder(1)});
        std.debug.print("     支持 RETURNING: {any}\n", .{comptime pg.supports(.returning)});
        std.debug.print("     支持 JSONB: {any}\n", .{comptime pg.supports(.jsonb)});
        const quote = comptime pg.identQuote();
        std.debug.print("     标识符引用: {c}table{c}\n", .{ quote.left, quote.right });
    }

    std.debug.print("\n", .{});

    // MySQL
    {
        const mysql = comptime zorm.Dialect.mysql;
        std.debug.print("   MySQL:\n", .{});
        std.debug.print("     占位符: {s}\n", .{comptime mysql.placeholder(1)});
        std.debug.print("     支持 RETURNING: {any}\n", .{comptime mysql.supports(.returning)});
        std.debug.print("     UPSERT 语法: {s}\n", .{comptime mysql.upsertClause()});
        const quote = comptime mysql.identQuote();
        std.debug.print("     标识符引用: {c}table{c}\n", .{ quote.left, quote.right });
    }

    std.debug.print("\n", .{});
}

/// 示例 2: 演示查询构建器
fn demoQueryBuilder(allocator: std.mem.Allocator) !void {
    std.debug.print("2. 查询构建器 (Query Builder)\n", .{});
    std.debug.print("   - 类型安全的 SQL 构建\n", .{});
    std.debug.print("   - 链式调用\n", .{});
    std.debug.print("   - 自动参数绑定\n\n", .{});

    // 注意: 这里是演示用代码,实际使用需要真实的数据库连接
    // 以下代码展示了 API 的使用方式

    std.debug.print("   示例查询 (代码展示):\n\n", .{});

    const example_code =
        \\   var db = try zorm.DB.open(allocator, .{
        \\       .dialect = .postgresql,
        \\       .dsn = "postgres://user:pass@localhost/mydb",
        \\   });
        \\   defer db.close();
        \\
        \\   // SELECT 查询
        \\   var query = try db.newSelect(User);
        \\   defer query.deinit();
        \\
        \\   _ = try query
        \\       .column("id")
        \\       .column("name")
        \\       .column("email")
        \\       .where("email LIKE ?", .{"%@example.com"})
        \\       .orderBy("created_at DESC")
        \\       .limit(10);
        \\
        \\   const sql = try query.build();
        \\   defer allocator.free(sql);
        \\
        \\   // 生成的 SQL:
        \\   // SELECT id, name, email FROM users
        \\   // WHERE email LIKE $1
        \\   // ORDER BY created_at DESC LIMIT 10
    ;

    std.debug.print("{s}\n\n", .{example_code});

    // 演示 SQL 构建 (不连接数据库)
    try demoSQLBuilding(allocator);
}

/// 示例 3: 演示 SQL 构建过程
fn demoSQLBuilding(allocator: std.mem.Allocator) !void {
    std.debug.print("3. SQL 构建演示\n\n", .{});

    // 创建模拟的 DB 实例来构建 SQL
    // 注意: 这只是为了演示 API,不会实际执行查询

    std.debug.print("   当前版本: v{any}\n", .{zorm.version});
    std.debug.print("   支持的方言: PostgreSQL, MySQL, SQLite, MSSQL, Oracle\n", .{});
    std.debug.print("   特性: comptime 泛型, 零开销抽象, 显式内存管理\n", .{});

    _ = allocator; // 避免未使用警告
}

/// 示例 4: 演示错误处理
fn demoErrorHandling() void {
    std.debug.print("\n4. 错误处理\n", .{});
    std.debug.print("   - 所有可能失败的操作返回 error union\n", .{});
    std.debug.print("   - 使用 try/catch 显式处理错误\n", .{});
    std.debug.print("   - defer/errdefer 确保资源清理\n\n", .{});

    const example_error_code =
        \\   const user = db.findUser(id) catch |err| switch (err) {
        \\       error.NoRows => {
        \\           std.debug.print("用户不存在\n", .{});
        \\           return;
        \\       },
        \\       error.ConnectionClosed => {
        \\           std.debug.print("数据库连接已关闭\n", .{});
        \\           return err;
        \\       },
        \\       else => return err,
        \\   };
    ;

    std.debug.print("   {s}\n", .{example_error_code});
}

test "basic example" {
    const allocator = std.testing.allocator;

    // 测试方言系统
    comptime {
        const pg = zorm.Dialect.postgresql;
        try std.testing.expect(pg.supports(.returning));
        try std.testing.expect(pg.supports(.jsonb));
    }

    // 测试版本
    try std.testing.expectEqual(0, zorm.version.major);
    try std.testing.expectEqual(1, zorm.version.minor);

    _ = allocator;
}
