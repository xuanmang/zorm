const std = @import("std");
const pg = @import("pg");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== 简单 PostgreSQL 连接测试 ===\n", .{});

    // 创建连接池
    std.debug.print("1. 正在连接 PostgreSQL...\n", .{});
    const pool = try pg.Pool.init(allocator, .{
        .size = 2,
        .connect = .{
            .host = "127.0.0.1",
            .port = 5432,
        },
        .auth = .{
            .username = "pguser",
            .password = "Pg#123!",
            .database = "postgres",
            .timeout = 10_000,
        },
    });
    defer pool.deinit();
    std.debug.print("   ✓ 连接成功!\n", .{});

    // 测试简单查询
    std.debug.print("2. 执行简单查询 (SELECT 1)...\n", .{});
    const result = try pool.exec("SELECT 1", .{});
    std.debug.print("   ✓ 查询成功! 结果: {?}\n", .{result});

    // 测试创建表
    std.debug.print("3. 测试创建表...\n", .{});
    _ = try pool.exec("DROP TABLE IF EXISTS simple_test", .{});
    _ = try pool.exec("CREATE TABLE simple_test (id SERIAL PRIMARY KEY, name TEXT)", .{});
    std.debug.print("   ✓ 创建表成功!\n", .{});

    // 测试插入
    std.debug.print("4. 测试插入数据...\n", .{});
    _ = try pool.exec("INSERT INTO simple_test (name) VALUES ('test1')", .{});
    std.debug.print("   ✓ 插入成功!\n", .{});

    // 测试查询
    std.debug.print("5. 测试查询数据...\n", .{});
    var query_result = try pool.query("SELECT * FROM simple_test", .{});
    defer query_result.deinit();

    var count: usize = 0;
    while (try query_result.next()) |row| {
        const id = row.get(i32, 0);
        const name = row.get([]const u8, 1);
        std.debug.print("   行 {}: id={}, name={s}\n", .{count + 1, id, name});
        count += 1;
    }
    std.debug.print("   ✓ 查询成功! 共 {} 行\n", .{count});

    // 清理
    std.debug.print("6. 清理测试表...\n", .{});
    _ = try pool.exec("DROP TABLE simple_test", .{});
    std.debug.print("   ✓ 清理完成!\n", .{});

    std.debug.print("\n=== 所有测试通过! ===\n", .{});
}
