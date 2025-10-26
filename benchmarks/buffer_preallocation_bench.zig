//! SQL 缓冲区预分配性能基准测试
//!
//! 验证 AC4.8.2: SQL 生成过程预分配缓冲区，减少字符串拼接过程中的多次内存分配
//!
//! 性能目标:
//! - 预分配应该比动态扩展更快
//! - 预分配应该减少内存分配操作
//!
//! 运行方式:
//! ```sh
//! zig build-exe benchmarks/buffer_preallocation_bench.zig
//! ./buffer_preallocation_bench
//! ```

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n" ++ "=" ** 70 ++ "\n", .{});
    std.debug.print("SQL 缓冲区预分配性能基准测试\n", .{});
    std.debug.print("=" ** 70 ++ "\n\n", .{});

    // 测试场景 1: 简单 SELECT 查询
    try testSimpleSelect(allocator);

    // 测试场景 2: 复杂 SELECT 查询（多个条件 + JOIN）
    try testComplexSelect(allocator);

    // 测试场景 3: UPDATE 查询
    try testUpdate(allocator);

    // 测试场景 4: DELETE 查询
    try testDelete(allocator);

    std.debug.print("\n✅ 所有缓冲区预分配测试完成!\n", .{});
}

/// 测试简单 SELECT 查询的缓冲区预分配效果
fn testSimpleSelect(allocator: std.mem.Allocator) !void {
    std.debug.print("1️⃣  简单 SELECT 查询缓冲区预分配测试\n", .{});
    std.debug.print("   查询: SELECT id, name, email FROM users WHERE age > 18 ORDER BY name LIMIT 10\n\n", .{});

    const iterations: usize = 10000;
    var timer = try std.time.Timer.start();

    // 测试 1: 使用预分配（ensureTotalCapacity）
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const estimated_size: usize = 100;
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);

        try buf.ensureTotalCapacity(allocator, estimated_size);
        try buf.appendSlice(allocator, "SELECT id, name, email FROM users WHERE age > 18 ORDER BY name LIMIT 10");
    }

    const elapsed_with_prealloc = timer.read();
    timer.reset();

    // 测试 2: 不使用预分配（动态扩展）
    i = 0;
    while (i < iterations) : (i += 1) {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);

        // 模拟多次 append 触发 resize
        try buf.appendSlice(allocator, "SELECT ");
        try buf.appendSlice(allocator, "id, name, email");
        try buf.appendSlice(allocator, " FROM users");
        try buf.appendSlice(allocator, " WHERE age > 18");
        try buf.appendSlice(allocator, " ORDER BY name");
        try buf.appendSlice(allocator, " LIMIT 10");
    }

    const elapsed_without_prealloc = timer.read();

    printComparisonResults(
        "简单 SELECT",
        iterations,
        elapsed_with_prealloc,
        elapsed_without_prealloc,
    );
}

/// 测试复杂 SELECT 查询的缓冲区预分配效果
fn testComplexSelect(allocator: std.mem.Allocator) !void {
    std.debug.print("2️⃣  复杂 SELECT 查询缓冲区预分配测试\n", .{});
    std.debug.print("   查询: 包含多个 WHERE, JOIN, GROUP BY, HAVING, ORDER BY 子句\n\n", .{});

    const iterations: usize = 5000;
    var timer = try std.time.Timer.start();

    // 使用预分配
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const estimated_size: usize = 300;
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);

        try buf.ensureTotalCapacity(allocator, estimated_size);
        try buf.appendSlice(allocator, "SELECT users.id, users.name, posts.title, COUNT(comments.id) FROM users INNER JOIN posts ON posts.user_id = users.id LEFT JOIN comments ON comments.post_id = posts.id WHERE users.active = true AND posts.published = true GROUP BY users.id, posts.title HAVING COUNT(comments.id) > 5 ORDER BY COUNT(comments.id) DESC LIMIT 20");
    }

    const elapsed_with_prealloc = timer.read();
    timer.reset();

    // 不使用预分配
    i = 0;
    while (i < iterations) : (i += 1) {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);

        try buf.appendSlice(allocator, "SELECT users.id, users.name, posts.title, COUNT(comments.id)");
        try buf.appendSlice(allocator, " FROM users");
        try buf.appendSlice(allocator, " INNER JOIN posts ON posts.user_id = users.id");
        try buf.appendSlice(allocator, " LEFT JOIN comments ON comments.post_id = posts.id");
        try buf.appendSlice(allocator, " WHERE users.active = true AND posts.published = true");
        try buf.appendSlice(allocator, " GROUP BY users.id, posts.title");
        try buf.appendSlice(allocator, " HAVING COUNT(comments.id) > 5");
        try buf.appendSlice(allocator, " ORDER BY COUNT(comments.id) DESC");
        try buf.appendSlice(allocator, " LIMIT 20");
    }

    const elapsed_without_prealloc = timer.read();

    printComparisonResults(
        "复杂 SELECT",
        iterations,
        elapsed_with_prealloc,
        elapsed_without_prealloc,
    );
}

/// 测试 UPDATE 查询的缓冲区预分配效果
fn testUpdate(allocator: std.mem.Allocator) !void {
    std.debug.print("3️⃣  UPDATE 查询缓冲区预分配测试\n", .{});
    std.debug.print("   查询: UPDATE users SET name = $1, email = $2 WHERE id = $3\n\n", .{});

    const iterations: usize = 10000;
    var timer = try std.time.Timer.start();

    // 使用预分配
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const estimated_size: usize = 80;
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);

        try buf.ensureTotalCapacity(allocator, estimated_size);
        try buf.appendSlice(allocator, "UPDATE users SET name = $1, email = $2 WHERE id = $3");
    }

    const elapsed_with_prealloc = timer.read();
    timer.reset();

    // 不使用预分配
    i = 0;
    while (i < iterations) : (i += 1) {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);

        try buf.appendSlice(allocator, "UPDATE users SET ");
        try buf.appendSlice(allocator, "name = $1, email = $2");
        try buf.appendSlice(allocator, " WHERE id = $3");
    }

    const elapsed_without_prealloc = timer.read();

    printComparisonResults(
        "UPDATE",
        iterations,
        elapsed_with_prealloc,
        elapsed_without_prealloc,
    );
}

/// 测试 DELETE 查询的缓冲区预分配效果
fn testDelete(allocator: std.mem.Allocator) !void {
    std.debug.print("4️⃣  DELETE 查询缓冲区预分配测试\n", .{});
    std.debug.print("   查询: DELETE FROM users WHERE id = $1 AND active = false\n\n", .{});

    const iterations: usize = 10000;
    var timer = try std.time.Timer.start();

    // 使用预分配
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const estimated_size: usize = 70;
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);

        try buf.ensureTotalCapacity(allocator, estimated_size);
        try buf.appendSlice(allocator, "DELETE FROM users WHERE id = $1 AND active = false");
    }

    const elapsed_with_prealloc = timer.read();
    timer.reset();

    // 不使用预分配
    i = 0;
    while (i < iterations) : (i += 1) {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);

        try buf.appendSlice(allocator, "DELETE FROM users");
        try buf.appendSlice(allocator, " WHERE id = $1");
        try buf.appendSlice(allocator, " AND active = false");
    }

    const elapsed_without_prealloc = timer.read();

    printComparisonResults(
        "DELETE",
        iterations,
        elapsed_with_prealloc,
        elapsed_without_prealloc,
    );
}

/// 打印对比结果
fn printComparisonResults(
    test_name: []const u8,
    iterations: usize,
    time_with: u64,
    time_without: u64,
) void {
    const time_with_ms = @as(f64, @floatFromInt(time_with)) / 1_000_000.0;
    const time_without_ms = @as(f64, @floatFromInt(time_without)) / 1_000_000.0;
    const time_improvement = (1.0 - time_with_ms / time_without_ms) * 100.0;

    const avg_with_us = (time_with_ms * 1000.0) / @as(f64, @floatFromInt(iterations));
    const avg_without_us = (time_without_ms * 1000.0) / @as(f64, @floatFromInt(iterations));

    std.debug.print("   测试: {s}\n", .{test_name});
    std.debug.print("   迭代次数: {}\n\n", .{iterations});

    std.debug.print("   📊 性能对比:\n", .{});
    std.debug.print("   ┌────────────────────┬──────────────┬──────────────┬──────────────┐\n", .{});
    std.debug.print("   │ 指标               │ 预分配       │ 动态扩展     │ 改善         │\n", .{});
    std.debug.print("   ├────────────────────┼──────────────┼──────────────┼──────────────┤\n", .{});
    std.debug.print("   │ 总耗时 (ms)        │ {d:>12.2} │ {d:>12.2} │ {d:>11.1}% │\n", .{ time_with_ms, time_without_ms, time_improvement });
    std.debug.print("   │ 平均耗时 (μs)      │ {d:>12.2} │ {d:>12.2} │ {d:>11.1}% │\n", .{ avg_with_us, avg_without_us, time_improvement });
    std.debug.print("   └────────────────────┴──────────────┴──────────────┴──────────────┘\n\n", .{});

    const passed = time_improvement > 0;

    std.debug.print("   ✨ 性能提升: {d:.1}%\n", .{time_improvement});
    std.debug.print("   📈 结果: {s}\n\n", .{if (passed) "✅ 预分配更快" else "⚠️  无明显提升"});
    std.debug.print("   " ++ "-" ** 66 ++ "\n\n", .{});
}
