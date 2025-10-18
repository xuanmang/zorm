//! SelectQuery scan/scanOne 使用示例
//!
//! 本示例演示如何使用 ZORM 的查询构建器和自动结果映射功能

const std = @import("std");
const zorm = @import("zorm");

// 定义用户模型
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: u32,
    active: bool,

    pub const table_name = "users";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM Query Scan 示例 ===\n\n", .{});

    // 连接到数据库
    std.debug.print("1. 连接到 PostgreSQL 数据库...\n", .{});
    var driver = try zorm.PostgresDriver.connect(
        allocator,
        "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres",
    );
    defer driver.close() catch {};

    var db = zorm.DB(.postgresql).init(allocator, &driver);
    defer db.deinit();

    std.debug.print("✅ 数据库连接成功\n\n", .{});

    // 示例 1: scanOne() - 查询单个用户
    std.debug.print("2. 使用 scanOne() 查询单个用户 (id = 1)...\n", .{});
    {
        var query = try db.newSelect(User);
        defer query.deinit();

        _ = try query.where("id = $1", .{1});

        const user = query.scanOne() catch |err| {
            std.debug.print("⚠️  查询失败: {}\n", .{err});
            std.debug.print("   提示: 请先运行 'zig build run-setup' 初始化数据库\n\n", .{});
            return;
        };

        std.debug.print("✅ 查询成功:\n", .{});
        std.debug.print("   ID: {d}\n", .{user.id});
        std.debug.print("   Name: {s}\n", .{user.name});
        std.debug.print("   Email: {s}\n", .{user.email});
        std.debug.print("   Age: {d}\n", .{user.age});
        std.debug.print("   Active: {}\n\n", .{user.active});
    }

    // 示例 2: scan() - 查询多个用户
    std.debug.print("3. 使用 scan() 查询所有活跃用户 (age > 18)...\n", .{});
    {
        var query = try db.newSelect(User);
        defer query.deinit();

        _ = try query.where("age > $1", .{18});
        _ = try query.where("active = $2", .{true});
        _ = try query.orderBy("id", .asc);

        const users = query.scan() catch |err| {
            std.debug.print("⚠️  查询失败: {}\n\n", .{err});
            return;
        };
        defer allocator.free(users);

        std.debug.print("✅ 查询成功，找到 {d} 个用户:\n", .{users.len});
        for (users, 0..) |user, i| {
            std.debug.print("   [{d}] {s} (id={d}, age={d}, email={s})\n", .{
                i + 1,
                user.name,
                user.id,
                user.age,
                user.email,
            });
        }
        std.debug.print("\n", .{});
    }

    // 示例 3: scan() - 使用 LIMIT 和 OFFSET
    std.debug.print("4. 使用 scan() 实现分页 (LIMIT 2 OFFSET 0)...\n", .{});
    {
        var query = try db.newSelect(User);
        defer query.deinit();

        _ = try query.orderBy("id", .asc);
        _ = try query.limit(2);
        _ = try query.offset(0);

        const users = query.scan() catch |err| {
            std.debug.print("⚠️  查询失败: {}\n\n", .{err});
            return;
        };
        defer allocator.free(users);

        std.debug.print("✅ 第一页 (前2条):\n", .{});
        for (users, 0..) |user, i| {
            std.debug.print("   [{d}] {s}\n", .{ i + 1, user.name });
        }
        std.debug.print("\n", .{});
    }

    // 示例 4: scanOne() - 处理 NoRows 错误
    std.debug.print("5. 使用 scanOne() 查询不存在的用户...\n", .{});
    {
        var query = try db.newSelect(User);
        defer query.deinit();

        _ = try query.where("id = $1", .{99999});

        if (query.scanOne()) |user| {
            std.debug.print("✅ 找到用户: {s}\n\n", .{user.name});
        } else |err| {
            if (err == error.NoRows) {
                std.debug.print("✅ 预期行为: 没有找到记录 (NoRows 错误)\n\n", .{});
            } else {
                std.debug.print("❌ 未预期的错误: {}\n\n", .{err});
            }
        }
    }

    // 示例 5: scan() - 空结果集
    std.debug.print("6. 使用 scan() 查询空结果集...\n", .{});
    {
        var query = try db.newSelect(User);
        defer query.deinit();

        _ = try query.where("age < $1", .{0}); // 不可能有 age < 0 的用户

        const users = query.scan() catch |err| {
            std.debug.print("❌ 查询失败: {}\n\n", .{err});
            return;
        };
        defer allocator.free(users);

        std.debug.print("✅ 空结果集处理正常，返回 {d} 条记录\n\n", .{users.len});
    }

    std.debug.print("=== 所有示例运行完成 ===\n", .{});
}
