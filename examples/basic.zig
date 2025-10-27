//! 基础 CRUD 操作示例 - 可运行版本
//!
//! 本示例演示使用 ZORM 高层级 API 进行真实的数据库操作:
//! 1. 使用简化的 zorm.connect() 连接数据库
//! 2. 使用查询构建器进行所有 CRUD 操作
//! 3. 展示 ZORM 的类型安全和链式调用特性
//!
//! 运行方式:
//! ```sh
//! zig build run-example-basic
//! ```

const std = @import("std");
const zorm = @import("zorm");

// 定义用户模型
const User = struct {
    id: i64 = 0,
    name: []const u8,
    email: []const u8,
    age: i32,
    active: bool = true,

    pub const table_name = "users";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("ZORM 基础 CRUD 操作示例\n", .{});
    std.debug.print("==" ** 60 ++ "\n\n", .{});

    // 1. 连接数据库 - 使用新的简化 API ✨
    std.debug.print("📦 连接数据库: pguser@127.0.0.1:5432/postgres\n\n", .{});
    const dsn = "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres";

    const db = try zorm.connect(allocator, dsn);
    defer db.deinit();

    std.debug.print("✓ 数据库连接成功\n\n", .{});

    // 2. 执行 CRUD 操作
    try runCRUDOperations(db, allocator);

    std.debug.print("\n✅ 示例执行完成!\n", .{});
}

fn runCRUDOperations(db: *zorm.DB(.postgresql), allocator: std.mem.Allocator) !void {
    // ========================================
    // 1. DROP TABLE IF EXISTS (清理环境)
    // ========================================
    std.debug.print("🧹 清理旧表...\n", .{});
    {
        const drop_sql = "DROP TABLE IF EXISTS users CASCADE";
        db.exec(drop_sql, &[_]zorm.QueryArg{}) catch |err| {
            std.debug.print("   警告: 删除表失败: {any}\n", .{err});
        };
        std.debug.print("   完成\n\n", .{});
    }

    // ========================================
    // 2. CREATE TABLE - 使用 newCreateTable() ✨
    // ========================================
    std.debug.print("1️⃣  创建表 (使用 newCreateTable)\n", .{});
    {
        var create = try db.newCreateTable(User);
        defer create.deinit();

        // 查看生成的 SQL（可选）
        const sql = try create.explain();
        defer create.allocator.free(sql);
        std.debug.print("   SQL: {s}\n", .{sql});

        // 直接执行
        try create.exec();
        std.debug.print("   ✓ 表创建成功\n\n", .{});
    }

    // ========================================
    // 3. INSERT - 使用 newInsert()
    // ========================================
    std.debug.print("2️⃣  插入数据 (使用 newInsert)\n", .{});
    {
        // 插入第一条
        {
            var insert = try db.newInsert(User);
            defer insert.deinit();

            _ = try insert.value(.{
                .name = "张三",
                .email = "zhangsan@example.com",
                .age = 28,
                .active = true,
            });

            const result = try insert.exec();
            std.debug.print("   ✓ 插入 {} 行记录 (张三)\n", .{result.rows_affected});
        }

        // 插入第二条
        {
            var insert = try db.newInsert(User);
            defer insert.deinit();

            _ = try insert.value(.{
                .name = "李四",
                .email = "lisi@example.com",
                .age = 32,
                .active = true,
            });

            const result = try insert.exec();
            std.debug.print("   ✓ 插入 {} 行记录 (李四)\n", .{result.rows_affected});
        }

        // 插入第三条
        {
            var insert = try db.newInsert(User);
            defer insert.deinit();

            _ = try insert.value(.{
                .name = "王五",
                .email = "wangwu@example.com",
                .age = 25,
                .active = false,
            });

            const result = try insert.exec();
            std.debug.print("   ✓ 插入 {} 行记录 (王五)\n\n", .{result.rows_affected});
        }
    }

    // ========================================
    // 4. SELECT - 使用 newSelect() ✨
    // ========================================
    std.debug.print("3️⃣  查询数据 (使用 newSelect)\n", .{});
    {
        var query = try db.newSelect(User);
        defer query.deinit();

        // 添加条件和排序
        _ = try query.where("age >= $1", .{25});
        _ = try query.orderBy("age", .desc);

        // 执行查询并获取结果
        var users: std.ArrayList(User) = .{};
        defer users.deinit(allocator);

        try query.scan(&users);

        std.debug.print("   ✓ 共查询到 {} 行记录\n", .{users.items.len});
        std.debug.print("   查询结果:\n", .{});

        for (users.items, 1..) |user, i| {
            std.debug.print("   [{d}] ID={d}, Name={s}, Email={s}, Age={d}, Active={}\n", .{
                i,
                user.id,
                user.name,
                user.email,
                user.age,
                user.active,
            });
        }
        std.debug.print("\n", .{});
    }

    // ========================================
    // 5. UPDATE - 使用 newUpdate()
    // ========================================
    std.debug.print("4️⃣  更新数据 (使用 newUpdate)\n", .{});
    {
        var update = try db.newUpdate(User);
        defer update.deinit();

        _ = try update.set("age = $1", .{29});
        _ = try update.where("name = $2", .{"张三"});

        // 查看生成的 SQL（可选）
        const sql = try update.explain();
        defer update.allocator.free(sql);
        std.debug.print("   SQL: {s}\n", .{sql});

        // 直接执行
        const result = try update.exec();
        std.debug.print("   ✓ 更新 {} 行记录\n\n", .{result.rows_affected});
    }

    // ========================================
    // 6. 验证更新结果 - 使用 newSelect() + scanOne()
    // ========================================
    std.debug.print("5️⃣  验证更新结果 (使用 scanOne)\n", .{});
    {
        var query = try db.newSelect(User);
        defer query.deinit();

        _ = try query.where("name = $1", .{"张三"});

        const user = try query.scanOne();

        std.debug.print("   Name={s}, Age={d}\n", .{ user.name, user.age });
        if (user.age == 29) {
            std.debug.print("   ✓ 年龄更新验证成功 (28 → 29)\n\n", .{});
        } else {
            std.debug.print("   ✗ 年龄更新验证失败 (期望 29, 实际 {d})\n\n", .{user.age});
        }
    }

    // ========================================
    // 7. DELETE - 使用 newDelete()
    // ========================================
    std.debug.print("6️⃣  删除数据 (使用 newDelete)\n", .{});
    {
        var delete = try db.newDelete(User);
        defer delete.deinit();

        _ = try delete.where("active = $1", .{false});

        // 查看生成的 SQL（可选）
        const sql = try delete.explain();
        defer delete.allocator.free(sql);
        std.debug.print("   SQL: {s}\n", .{sql});

        // 直接执行
        const result = try delete.exec();
        std.debug.print("   ✓ 删除 {} 行记录\n\n", .{result.rows_affected});
    }

    // ========================================
    // 8. 最终统计 - 使用 newSelect() + count()
    // ========================================
    std.debug.print("7️⃣  最终统计 (使用 count)\n", .{});
    {
        var query = try db.newSelect(User);
        defer query.deinit();

        const count = try query.count();
        std.debug.print("   剩余用户数: {d}\n", .{count});
        std.debug.print("   ✓ 最终验证完成 (应为 2 条记录)\n", .{});
    }
}
