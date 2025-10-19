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

    // 示例 3: INSERT 查询构建器
    try demoInsertQuery(allocator);

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

    // 演示 SelectQuery 实际用法
    try demoSelectQuery(allocator);

    std.debug.print("   完整用法示例:\n\n", .{});

    const example_code =
        \\   var db = try zorm.DB(.postgresql).init(allocator, conn, .{});
        \\   defer db.deinit();
        \\
        \\   // SELECT 查询
        \\   var query = try db.newSelect(User);
        \\   defer query.deinit();
        \\
        \\   _ = try query
        \\       .column("id")
        \\       .column("name")
        \\       .column("email")
        \\       .where("email LIKE $1", .{"%@example.com"})
        \\       .orderBy("created_at", .desc)
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

/// 示例 2.1: 演示 SelectQuery API
fn demoSelectQuery(allocator: std.mem.Allocator) !void {
    std.debug.print("   SelectQuery API 演示:\n\n", .{});

    // Mock DB 用于演示
    const MockDB = struct {
        allocator: std.mem.Allocator,
    };
    var mock_db = MockDB{ .allocator = allocator };

    // 创建 SELECT 查询构建器
    var query = try zorm.SelectQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db), "users");
    defer query.deinit();

    // 链式构建查询
    _ = try query.column("id");
    _ = try query.column("name");
    _ = try query.column("email");
    _ = try query.where("created_at > $1", .{1704067200}); // 2024-01-01
    _ = try query.orderBy("created_at", .desc);
    _ = try query.limit(5);

    const sql = try query.build();
    defer allocator.free(sql);

    std.debug.print("     生成的 SQL:\n", .{});
    std.debug.print("     {s}\n\n", .{sql});

    // 演示更复杂的查询
    var query2 = try zorm.SelectQuery(Post, .postgresql).init(allocator, @ptrCast(&mock_db), "posts");
    defer query2.deinit();

    _ = try query2.where("user_id = $1", .{1});
    _ = try query2.where("title LIKE $2", .{"%Zig%"});
    _ = try query2.orderBy("created_at", .desc);
    _ = try query2.limit(10);
    _ = try query2.offset(0);

    const sql2 = try query2.build();
    defer allocator.free(sql2);

    std.debug.print("     复杂查询 SQL:\n", .{});
    std.debug.print("     {s}\n\n", .{sql2});

    // Story 1.3: 演示列选择和 DISTINCT
    try demoColumnDistinct(allocator);
}

/// 示例 2.2: 演示列选择、DISTINCT 和 COUNT (Story 1.3)
fn demoColumnDistinct(allocator: std.mem.Allocator) !void {
    std.debug.print("   Story 1.3 - 列选择、DISTINCT 和 COUNT:\n\n", .{});

    // Mock DB 用于演示
    const MockDB = struct {
        allocator: std.mem.Allocator,
    };
    var mock_db = MockDB{ .allocator = allocator };

    // 示例 1: 列选择
    {
        std.debug.print("     1. 列选择 (指定查询列):\n", .{});
        var query = try zorm.SelectQuery(User, .postgresql).init(
            allocator,
            @ptrCast(&mock_db),
            "users",
        );
        defer query.deinit();

        _ = try query.column("id");
        _ = try query.column("email");
        _ = try query.where("age > $1", .{18});

        const sql = try query.build();
        defer allocator.free(sql);

        std.debug.print("        SQL: {s}\n\n", .{sql});
    }

    // 示例 2: DISTINCT 去重
    {
        std.debug.print("     2. DISTINCT (去重):\n", .{});
        var query = try zorm.SelectQuery(User, .postgresql).init(
            allocator,
            @ptrCast(&mock_db),
            "users",
        );
        defer query.deinit();

        _ = try query.distinct();
        _ = try query.column("email");

        const sql = try query.build();
        defer allocator.free(sql);

        std.debug.print("        SQL: {s}\n\n", .{sql});
    }

    // 示例 3: DISTINCT + 多列
    {
        std.debug.print("     3. DISTINCT + 多列:\n", .{});
        var query = try zorm.SelectQuery(User, .postgresql).init(
            allocator,
            @ptrCast(&mock_db),
            "users",
        );
        defer query.deinit();

        _ = try query.distinct();
        _ = try query.column("name");
        _ = try query.column("age");
        _ = try query.orderBy("name", .asc);

        const sql = try query.build();
        defer allocator.free(sql);

        std.debug.print("        SQL: {s}\n\n", .{sql});
    }

    // 示例 4: 完整组合 (列选择 + DISTINCT + WHERE + ORDER BY + LIMIT)
    {
        std.debug.print("     4. 完整组合:\n", .{});
        var query = try zorm.SelectQuery(User, .postgresql).init(
            allocator,
            @ptrCast(&mock_db),
            "users",
        );
        defer query.deinit();

        _ = try query.distinct();
        _ = try query.column("name");
        _ = try query.column("email");
        _ = try query.where("age > $1", .{18});
        _ = try query.where("email IS NOT NULL", .{});
        _ = try query.orderBy("name", .asc);
        _ = try query.limit(10);

        const sql = try query.build();
        defer allocator.free(sql);

        std.debug.print("        SQL: {s}\n\n", .{sql});
    }

    std.debug.print("     注意: count() 方法需要实际数据库连接才能执行\n", .{});
    std.debug.print("          它会返回查询结果的行数 (usize 类型)\n\n", .{});
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

/// 示例 3: 演示 INSERT 查询构建器
fn demoInsertQuery(allocator: std.mem.Allocator) !void {
    std.debug.print("\n3. INSERT 查询构建器\n", .{});
    std.debug.print("   - 类型安全的数据插入\n", .{});
    std.debug.print("   - 支持 RETURNING 子句 (PostgreSQL)\n", .{});
    std.debug.print("   - 批量插入支持\n\n", .{});

    // 创建一个 Mock DB (仅用于演示 SQL 生成)
    const MockDB = struct {
        allocator: std.mem.Allocator,
    };
    var mock_db = MockDB{ .allocator = allocator };

    // 演示单行插入
    {
        std.debug.print("   单行插入:\n", .{});

        var query = try zorm.InsertQuery(User, .postgresql).init(
            allocator,
            @ptrCast(&mock_db),
            "users",
        );
        defer query.deinit();

        _ = try query.value(.{
            .id = 1,
            .name = "Alice",
            .email = "alice@example.com",
            .created_at = std.time.timestamp(),
        });

        const sql = try query.build();
        defer allocator.free(sql);

        std.debug.print("   SQL: {s}\n\n", .{sql});
    }

    // 演示 RETURNING 子句
    {
        std.debug.print("   INSERT with RETURNING:\n", .{});

        var query = try zorm.InsertQuery(User, .postgresql).init(
            allocator,
            @ptrCast(&mock_db),
            "users",
        );
        defer query.deinit();

        _ = try query.value(.{
            .id = 2,
            .name = "Bob",
            .email = "bob@example.com",
            .created_at = std.time.timestamp(),
        });

        _ = try query.returning(&.{ "id", "created_at" });

        const sql = try query.build();
        defer allocator.free(sql);

        std.debug.print("   SQL: {s}\n\n", .{sql});
    }

    // 演示批量插入
    {
        std.debug.print("   批量插入:\n", .{});

        var query = try zorm.InsertQuery(User, .postgresql).init(
            allocator,
            @ptrCast(&mock_db),
            "users",
        );
        defer query.deinit();

        const users = [_]@TypeOf(.{
            .id = @as(i64, 0),
            .name = @as([]const u8, ""),
            .email = @as([]const u8, ""),
            .created_at = @as(i64, 0),
        }){
            .{ .id = 3, .name = "Charlie", .email = "charlie@example.com", .created_at = std.time.timestamp() },
            .{ .id = 4, .name = "David", .email = "david@example.com", .created_at = std.time.timestamp() },
        };

        _ = try query.values(&users);

        const sql = try query.build();
        defer allocator.free(sql);

        std.debug.print("   SQL: {s}\n\n", .{sql});
    }

    // 演示 ON CONFLICT (PostgreSQL)
    {
        std.debug.print("   INSERT with ON CONFLICT (UPSERT):\n", .{});

        var query = try zorm.InsertQuery(User, .postgresql).init(
            allocator,
            @ptrCast(&mock_db),
            "users",
        );
        defer query.deinit();

        _ = try query.value(.{
            .id = 1,
            .name = "Alice Updated",
            .email = "alice@example.com",
            .created_at = std.time.timestamp(),
        });

        _ = try query.onConflict(.{
            .columns = &.{"email"},
            .action = .do_update,
            .update_columns = &.{"name"},
        });

        const sql = try query.build();
        defer allocator.free(sql);

        std.debug.print("   SQL: {s}\n\n", .{sql});
    }

    std.debug.print("   完整 INSERT 用法示例:\n\n", .{});

    const example_code =
        \\   var db = try zorm.DB(.postgresql).init(allocator, conn, .{});
        \\   defer db.deinit();
        \\
        \\   // 基本插入
        \\   var insert = try db.newInsert(User);
        \\   defer insert.deinit();
        \\
        \\   const result = try insert
        \\       .value(.{
        \\           .id = 1,
        \\           .name = "Alice",
        \\           .email = "alice@example.com",
        \\           .created_at = std.time.timestamp(),
        \\       })
        \\       .exec();
        \\
        \\   std.debug.print("插入了 {} 行\n", .{result.rows_affected});
        \\
        \\   // INSERT with RETURNING
        \\   var users = std.ArrayList(User){};
        \\   defer users.deinit(allocator);
        \\
        \\   var insert2 = try db.newInsert(User);
        \\   defer insert2.deinit();
        \\
        \\   try insert2
        \\       .value(.{ .id = 2, .name = "Bob", ... })
        \\       .returning(&.{"*"})
        \\       .execReturning(&users);
        \\
        \\   std.debug.print("插入的用户: {}\n", .{users.items[0]});
    ;

    std.debug.print("{s}\n", .{example_code});
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
