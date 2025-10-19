//! 🎯 ZORM 核心价值演示 - 查询构建器的强大功能
//!
//! **为什么使用 ZORM 而不是原始 pg.zig?**
//! ========================================
//! ✅ 类型安全: 编译时检查字段类型，消除运行时错误
//! ✅ 自动映射: 查询结果自动映射到结构体，无需手动解析
//! ✅ 链式 API: 优雅的查询构建方式，代码更易读易维护
//! ✅ SQL 注入防护: 自动参数化查询，杜绝 SQL 注入攻击
//! ✅ 跨数据库: 方言系统支持 PostgreSQL
//!
//! 本示例对标 Golang Bun ORM，展示:
//! ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//! 1. ✨ SelectQuery - 类型安全的查询
//! 2. ✨ InsertQuery - 结构体直接插入
//! 3. ✨ UpdateQuery - 链式更新 API
//! 4. ✨ DeleteQuery - 安全删除操作
//! 5. ✨ 自动结果映射 - 无需手动解析
//!
//! 运行环境:
//!   PostgreSQL 127.0.0.1:5432 (user: pguser, db: postgres)
//!
//! 编译运行:
//!   zig build run-basic

const std = @import("std");
const zorm = @import("zorm");

// ═══════════════════════════════════════════════════════
// 📦 模型定义 (对标 Bun ORM 的 Model)
// ═══════════════════════════════════════════════════════

/// 用户模型 - ZORM 自动推断表结构
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: ?i32, // ?i32 → NULLABLE 列
    created_at: i64,
    updated_at: i64,

    pub const table_name = "users";
};

/// 文章模型
const Post = struct {
    id: i64,
    user_id: i64,
    title: []const u8,
    content: []const u8,
    published: bool,
    created_at: i64,

    pub const table_name = "posts";
};

// ═══════════════════════════════════════════════════════
// 🔧 数据库连接辅助 (简化示例代码)
// ═══════════════════════════════════════════════════════

const DSN = "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres";
const SCHEMA = "zorm_examples";

fn initSchema(driver: *zorm.PostgresDriver) !void {
    _ = try driver.exec("DROP SCHEMA IF EXISTS " ++ SCHEMA ++ " CASCADE", &.{});
    _ = try driver.exec("CREATE SCHEMA " ++ SCHEMA, &.{});
    _ = try driver.exec("SET search_path TO " ++ SCHEMA, &.{});
}

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
            const ResultWrapper = struct {
                allocator: std.mem.Allocator,
                result_vtable_ptr: *zorm.core.Result.VTable,
                result_ptr: *zorm.core.Result,
                fn next(_: *anyopaque) anyerror!bool {
                    return error.NotImplemented;
                }
                fn scan(_: *anyopaque, _: [][]u8) anyerror!void {
                    return error.NotImplemented;
                }
                fn close(ptr2: *anyopaque) void {
                    const wrapper: *@This() = @ptrCast(@alignCast(ptr2));
                    const alloc = wrapper.allocator;
                    const vtbl = wrapper.result_vtable_ptr;
                    const res = wrapper.result_ptr;
                    // 释放所有分配的对象
                    alloc.destroy(wrapper);
                    alloc.destroy(vtbl);
                    alloc.destroy(res);
                }
            };
            const wrapper = try self.allocator.create(ResultWrapper);
            const result_vtable = try self.allocator.create(zorm.core.Result.VTable);
            result_vtable.* = .{ .next = ResultWrapper.next, .scan = ResultWrapper.scan, .close = ResultWrapper.close };
            const result = try self.allocator.create(zorm.core.Result);
            wrapper.* = .{
                .allocator = self.allocator,
                .result_vtable_ptr = result_vtable,
                .result_ptr = result,
            };
            result.* = .{ .ptr = wrapper, .vtable = result_vtable, .rows = rows };
            return result;
        }
        fn begin(_: *anyopaque) anyerror!*zorm.core.Tx {
            return error.NotImplemented;
        }
        fn close(ptr: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.driver.close() catch {};
            self.allocator.destroy(self); // 释放 Adapter 自身
        }
        const vtable = zorm.core.Conn.VTable{ .exec = exec, .query = query, .begin = begin, .close = close };
    };
    const adapter = try allocator.create(Adapter);
    adapter.* = .{ .driver = driver, .allocator = allocator };
    const conn = zorm.core.Conn{ .ptr = adapter, .vtable = &Adapter.vtable };
    return try zorm.DB(.postgresql).init(allocator, conn, .{});
}

// ═══════════════════════════════════════════════════════
// 🎓 主教程 - 展示 ZORM 查询构建器的核心价值
// ═══════════════════════════════════════════════════════

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) std.debug.print("\n⚠️  Memory leak detected!\n", .{});
    }
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("╔══════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║  🚀 ZORM 查询构建器教程 - 对标 Golang Bun ORM            ║\n", .{});
    std.debug.print("║                                                          ║\n", .{});
    std.debug.print("║  展示类型安全查询、自动映射、链式 API 的强大功能          ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Step 1: 连接数据库
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    std.debug.print("📌 Step 1: 连接到 PostgreSQL\n", .{});
    std.debug.print("────────────────────────────────────────────────────────\n", .{});

    var driver = try zorm.PostgresDriver.connect(allocator, DSN);
    // 注意: driver.close() 由 db.deinit() 通过 Adapter.close() 自动调用
    // 不要在这里使用 defer driver.close(),否则会导致双重释放
    try initSchema(&driver);
    const db = try createDB(allocator, &driver);
    defer db.deinit();

    std.debug.print("✅ 已连接: 127.0.0.1:5432\n", .{});
    std.debug.print("✅ Schema: {s}\n\n", .{SCHEMA});

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Step 2: 使用 CreateTableQuery 构建器创建表
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    std.debug.print("📌 Step 2: 使用 CreateTableQuery 创建表\n", .{});
    std.debug.print("────────────────────────────────────────────────────────\n", .{});
    std.debug.print("💡 ZORM 自动从结构体推断列类型和约束\n\n", .{});

    var create_users = try db.newCreateTable(User);
    defer create_users.deinit();
    try create_users.ifNotExists().exec();
    std.debug.print("✅ users 表 (id, name, email, age, created_at, updated_at)\n", .{});

    var create_posts = try db.newCreateTable(Post);
    defer create_posts.deinit();
    try create_posts.ifNotExists().exec();
    std.debug.print("✅ posts 表 (id, user_id, title, content, published, created_at)\n\n", .{});

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Step 3: 使用 InsertQuery 插入数据 (对标 Bun ORM)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    std.debug.print("📌 Step 3: 使用 InsertQuery 插入数据\n", .{});
    std.debug.print("────────────────────────────────────────────────────────\n", .{});
    std.debug.print("💡 对比 Bun ORM: db.NewInsert().Model(&user).Exec(ctx)\n\n", .{});

    const now = std.time.timestamp();

    // 示例: 插入单个用户 (展示 ZORM 的类型安全)
    {
        std.debug.print("🔹 插入用户 Alice (展示结构体字段映射)\n", .{});
        var insert = try db.newInsert(User);
        defer insert.deinit();

        _ = try insert.value(.{
            .name = "Alice",
            .email = "alice@example.com",
            .age = 25,
            .created_at = now,
            .updated_at = now,
        });

        _ = try insert.exec();
        std.debug.print("   ✓ INSERT成功 - 字段自动映射到SQL\n", .{});
    }

    // 示例: 批量插入 (展示 ORM 的便利性)
    {
        std.debug.print("🔹 批量插入 Bob, Charlie, Diana\n", .{});
        const users_data = [_]struct { name: []const u8, email: []const u8, age: ?i32 }{
            .{ .name = "Bob", .email = "bob@example.com", .age = 30 },
            .{ .name = "Charlie", .email = "charlie@example.com", .age = null }, // NULL值处理
            .{ .name = "Diana", .email = "diana@example.com", .age = 35 },
        };

        for (users_data) |user_data| {
            var insert = try db.newInsert(User);
            defer insert.deinit();
            _ = try insert.value(.{
                .name = user_data.name,
                .email = user_data.email,
                .age = user_data.age,
                .created_at = now,
                .updated_at = now,
            });
            _ = try insert.exec();
        }
        std.debug.print("   ✓ 批量INSERT成功 - ?i32自动处理NULL\n\n", .{});
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Step 4: 使用 SelectQuery 查询数据 (展示核心价值!)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    std.debug.print("📌 Step 4: 使用 SelectQuery 查询数据\n", .{});
    std.debug.print("────────────────────────────────────────────────────────\n", .{});
    std.debug.print("💡 类型安全 + 自动映射 = ZORM 的核心价值!\n\n", .{});

    // 示例 4.1: 查询所有用户 (自动映射到结构体切片)
    {
        std.debug.print("🔍 示例 4.1: 查询所有用户 - 结果自动映射\n", .{});
        var query = try db.newSelect(User);
        defer query.deinit();

        _ = try query.orderBy("id", .asc);
        const users = try query.scan();
        defer allocator.free(users);

        std.debug.print("   查询到 {d} 个用户:\n", .{users.len});
        for (users) |user| {
            if (user.age) |age| {
                std.debug.print("     • {s} ({s}) - Age: {d}\n", .{ user.name, user.email, age });
            } else {
                std.debug.print("     • {s} ({s}) - Age: NULL\n", .{ user.name, user.email });
            }
        }
        std.debug.print("\n", .{});
    }

    // 示例 4.2: WHERE 条件查询 (链式 API)
    {
        std.debug.print("🔍 示例 4.2: WHERE 条件查询 - 链式 API\n", .{});
        var query = try db.newSelect(User);
        defer query.deinit();

        _ = try query.where("age > $1", .{@as(i32, 25)});
        _ = try query.orderBy("age", .desc);

        const users = try query.scan();
        defer allocator.free(users);

        std.debug.print("   年龄 > 25 的用户 ({d} 人):\n", .{users.len});
        for (users) |user| {
            if (user.age) |age| {
                std.debug.print("     • {s} - Age: {d}\n", .{ user.name, age });
            }
        }
        std.debug.print("\n", .{});
    }

    // 示例 4.3: 分页查询 (LIMIT + OFFSET)
    {
        std.debug.print("🔍 示例 4.3: 分页查询 - LIMIT + OFFSET\n", .{});
        var query = try db.newSelect(User);
        defer query.deinit();

        _ = try query.orderBy("id", .asc);
        _ = try query.limit(2);
        _ = try query.offset(1);

        const users = try query.scan();
        defer allocator.free(users);

        std.debug.print("   第2页 (每页2条, 跳过1条):\n", .{});
        for (users) |user| {
            std.debug.print("     • {s}\n", .{user.name});
        }
        std.debug.print("\n", .{});
    }

    // 示例 4.4: 查询单条记录
    {
        std.debug.print("🔍 示例 4.4: 查询单条记录 - scanOne()\n", .{});
        var query = try db.newSelect(User);
        defer query.deinit();

        _ = try query.where("email = $1", .{"alice@example.com"});
        const user = try query.scanOne();

        std.debug.print("   查询到用户:\n", .{});
        std.debug.print("     ID: {d}\n", .{user.id});
        std.debug.print("     Name: {s}\n", .{user.name});
        std.debug.print("     Email: {s}\n", .{user.email});
        if (user.age) |age| {
            std.debug.print("     Age: {d}\n", .{age});
        }
        std.debug.print("\n", .{});
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Step 5: 使用 UpdateQuery 更新数据
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    std.debug.print("📌 Step 5: 使用 UpdateQuery 更新数据\n", .{});
    std.debug.print("────────────────────────────────────────────────────────\n", .{});
    std.debug.print("💡 对比 Bun ORM: db.NewUpdate().Model(&user).Set(...).Exec(ctx)\n\n", .{});

    // 示例 5.1: 更新单个字段
    {
        std.debug.print("✏️  示例 5.1: 更新单个字段 - Alice的年龄\n", .{});
        var update = try db.newUpdate(User);
        defer update.deinit();

        _ = try update.set("age = $1", .{@as(i32, 26)});
        _ = try update.where("name = $1", .{"Alice"});

        _ = try update.exec();
        std.debug.print("   ✓ 已更新 Alice 年龄: 25 → 26\n\n", .{});
    }

    // 示例 5.2: 批量更新 (多个 SET 子句)
    {
        std.debug.print("✏️  示例 5.2: 批量更新 - 更新年龄和时间戳\n", .{});
        var update = try db.newUpdate(User);
        defer update.deinit();

        _ = try update.set("age = age + $1", .{@as(i32, 1)});
        _ = try update.set("updated_at = $1", .{now + 100});
        _ = try update.where("age IS NOT NULL", .{});

        _ = try update.exec();
        std.debug.print("   ✓ 所有非NULL年龄用户 +1 岁\n\n", .{});
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Step 6: 使用 DeleteQuery 删除数据
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    std.debug.print("📌 Step 6: 使用 DeleteQuery 删除数据\n", .{});
    std.debug.print("────────────────────────────────────────────────────────\n", .{});
    std.debug.print("💡 对比 Bun ORM: db.NewDelete().Model(&user).Where(...).Exec(ctx)\n\n", .{});

    // 示例 6.1: 条件删除
    {
        std.debug.print("🗑️  示例 6.1: 删除特定用户 - Charlie\n", .{});
        var delete = try db.newDelete(User);
        defer delete.deinit();

        _ = try delete.where("name = $1", .{"Charlie"});
        _ = try delete.exec();
        std.debug.print("   ✓ 已删除用户 Charlie\n\n", .{});
    }

    // 验证删除结果
    {
        std.debug.print("🔍 验证: 查询剩余用户数量\n", .{});
        var query = try db.newSelect(User);
        defer query.deinit();

        const users = try query.scan();
        defer allocator.free(users);

        std.debug.print("   剩余用户数: {d}\n", .{users.len});
        std.debug.print("   剩余用户: ", .{});
        for (users, 0..) |user, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{user.name});
        }
        std.debug.print("\n\n", .{});
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 总结: ZORM vs 原始 pg.zig
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    std.debug.print("╔══════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║  ✅ 教程完成! ZORM vs 原始 pg.zig 的核心区别             ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("📊 ZORM 查询构建器的核心价值:\n", .{});
    std.debug.print("───────────────────────────────────────────────────────────\n", .{});
    std.debug.print("  1. ✨ 类型安全的查询构建\n", .{});
    std.debug.print("     • SelectQuery: .where() + .orderBy() + .limit()\n", .{});
    std.debug.print("     • InsertQuery: .value() 自动字段映射\n", .{});
    std.debug.print("     • UpdateQuery: .set() + .where() 链式 API\n", .{});
    std.debug.print("     • DeleteQuery: .where() 安全删除\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  2. ✨ 自动结果映射\n", .{});
    std.debug.print("     • .scan() → []User (自动解析到结构体切片)\n", .{});
    std.debug.print("     • .scanOne() → User (单条记录)\n", .{});
    std.debug.print("     • 无需手动 row.getString()/row.getInt()\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  3. ✨ SQL 注入防护\n", .{});
    std.debug.print("     • 自动参数化查询 ($1, $2, $3...)\n", .{});
    std.debug.print("     • 无需担心字符串拼接漏洞\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  4. ✨ 跨数据库支持\n", .{});
    std.debug.print("     • 方言系统: PostgreSQL\n", .{});
    std.debug.print("     • 同一代码适配多种数据库\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("🚫 原始 pg.zig 的局限:\n", .{});
    std.debug.print("───────────────────────────────────────────────────────────\n", .{});
    std.debug.print("  ✗ 手动拼接 SQL 字符串\n", .{});
    std.debug.print("  ✗ 手动解析查询结果\n", .{});
    std.debug.print("  ✗ 手动管理参数化查询\n", .{});
    std.debug.print("  ✗ 容易出现 SQL 注入漏洞\n", .{});
    std.debug.print("  ✗ 无法跨数据库移植\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("🎯 这就是 ZORM 的价值所在!\n\n", .{});

    std.debug.print("📚 下一步学习:\n", .{});
    std.debug.print("───────────────────────────────────────────────────────────\n", .{});
    std.debug.print("  • transaction.zig - 学习事务管理\n", .{});
    std.debug.print("  • 02_simple_select.zig - 深入查询构建器\n", .{});
    std.debug.print("  • relations.zig - 学习关系映射\n\n", .{});
}
