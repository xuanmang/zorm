const std = @import("std");
const pg = @import("pg");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== 测试 pg.zig 的 Stmt 参数绑定 ===\n", .{});

    // 创建连接池
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

    std.debug.print("1. 清理并创建测试表...\n", .{});
    _ = try pool.exec("DROP TABLE IF EXISTS test_stmt", .{});
    _ = try pool.exec("CREATE TABLE test_stmt (id SERIAL PRIMARY KEY, name TEXT, age INTEGER)", .{});

    std.debug.print("2. 测试使用 Stmt.bind() 进行参数化插入...\n", .{});

    // 获取连接
    const conn = try pool.acquire();
    defer pool.release(conn);

    // 创建 statement (release_conn = false,因为我们手动管理)
    var stmt = try pg.Stmt.init(conn, .{ .release_conn = false });
    errdefer stmt.deinit();

    // Prepare
    try stmt.prepare("INSERT INTO test_stmt (name, age) VALUES ($1, $2)", null);

    // Bind
    try stmt.bind("Alice");
    try stmt.bind(@as(i64, 25));

    // Execute
    const result = try stmt.execute();
    defer result.deinit();

    std.debug.print("   ✓ 插入成功!\n", .{});

    std.debug.print("\n=== 测试通过! ===\n", .{});
}
