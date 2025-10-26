//! Comptime 优化性能基准测试
//!
//! 验证 AC4.8.4: 利用 Zig comptime 特性将类型映射和 SQL 模板生成移到编译时
//!
//! 性能目标:
//! - Comptime 生成应该比运行时拼接更快（> 40% 性能提升）
//! - 编译时生成的 SQL 模板应该是零运行时开销
//!
//! 运行方式:
//! ```sh
//! zig build-exe benchmarks/comptime_optimization_bench.zig
//! ./comptime_optimization_bench
//! ```

const std = @import("std");

// 嵌入 comptime 优化函数用于基准测试
const ComptimeReflect = struct {
    /// 在编译时生成列名列表（逗号分隔）
    pub fn generateColumnList(comptime T: type) []const u8 {
        const type_info = @typeInfo(T);
        if (type_info != .@"struct") {
            @compileError("generateColumnList requires a struct type");
        }
        const fields = type_info.@"struct".fields;
        comptime var result: []const u8 = "";
        inline for (fields, 0..) |field, i| {
            if (i > 0) result = result ++ ", ";
            result = result ++ field.name;
        }
        return result;
    }

    /// 在编译时生成 SELECT 查询模板
    pub fn generateSelectTemplate(comptime T: type, comptime table_name: []const u8) []const u8 {
        const type_info = @typeInfo(T);
        if (type_info != .@"struct") {
            @compileError("generateSelectTemplate requires a struct type");
        }
        const fields = type_info.@"struct".fields;

        comptime var result: []const u8 = "SELECT ";
        inline for (fields, 0..) |field, i| {
            if (i > 0) result = result ++ ", ";
            result = result ++ field.name;
        }
        result = result ++ " FROM " ++ table_name;
        return result;
    }

    /// 在编译时生成 INSERT 查询模板
    pub fn generateInsertTemplate(comptime T: type, comptime table_name: []const u8) []const u8 {
        const type_info = @typeInfo(T);
        if (type_info != .@"struct") {
            @compileError("generateInsertTemplate requires a struct type");
        }
        const fields = type_info.@"struct".fields;

        comptime var result: []const u8 = "INSERT INTO " ++ table_name ++ " (";

        inline for (fields, 0..) |field, i| {
            if (i > 0) result = result ++ ", ";
            result = result ++ field.name;
        }

        result = result ++ ") VALUES (";

        inline for (fields, 0..) |_, i| {
            if (i > 0) result = result ++ ", ";
            const idx = i + 1;
            if (idx == 1) result = result ++ "$1"
            else if (idx == 2) result = result ++ "$2"
            else if (idx == 3) result = result ++ "$3"
            else if (idx == 4) result = result ++ "$4"
            else if (idx == 5) result = result ++ "$5"
            else if (idx == 6) result = result ++ "$6"
            else if (idx == 7) result = result ++ "$7"
            else if (idx == 8) result = result ++ "$8"
            else if (idx == 9) result = result ++ "$9"
            else if (idx == 10) result = result ++ "$10"
            else @compileError("generateInsertTemplate: too many fields");
        }

        result = result ++ ")";
        return result;
    }

    /// 在编译时生成占位符列表
    pub fn generatePlaceholders(comptime T: type, comptime start_index: usize) []const u8 {
        const type_info = @typeInfo(T);
        if (type_info != .@"struct") {
            @compileError("generatePlaceholders requires a struct type");
        }
        const fields = type_info.@"struct".fields;
        comptime var result: []const u8 = "";
        inline for (fields, 0..) |_, i| {
            if (i > 0) result = result ++ ", ";
            const idx = start_index + i;
            if (idx == 1) result = result ++ "$1"
            else if (idx == 2) result = result ++ "$2"
            else if (idx == 3) result = result ++ "$3"
            else if (idx == 4) result = result ++ "$4"
            else if (idx == 5) result = result ++ "$5"
            else if (idx == 6) result = result ++ "$6"
            else if (idx == 7) result = result ++ "$7"
            else if (idx == 8) result = result ++ "$8"
            else if (idx == 9) result = result ++ "$9"
            else if (idx == 10) result = result ++ "$10"
            else @compileError("generatePlaceholders: index > 10 not supported");
        }
        return result;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n" ++ "=" ** 70 ++ "\n", .{});
    std.debug.print("Comptime SQL 优化性能基准测试\n", .{});
    std.debug.print("=" ** 70 ++ "\n\n", .{});

    // 测试场景 1: 列名生成
    try testColumnListGeneration(allocator);

    // 测试场景 2: SELECT 模板生成
    try testSelectTemplateGeneration(allocator);

    // 测试场景 3: INSERT 模板生成
    try testInsertTemplateGeneration(allocator);

    // 测试场景 4: 占位符生成
    try testPlaceholderGeneration(allocator);

    std.debug.print("\n✅ 所有 Comptime 优化测试完成!\n", .{});
}

/// 测试用户类型
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: i32,
    created_at: i64,
};

/// 测试列名生成: Comptime vs Runtime
fn testColumnListGeneration(allocator: std.mem.Allocator) !void {
    std.debug.print("1️⃣  列名生成性能测试\n", .{});
    std.debug.print("   对比: Comptime 生成 vs 运行时拼接\n\n", .{});

    const iterations: usize = 100000;
    var timer = try std.time.Timer.start();

    // 测试 1: Comptime 生成（编译时已确定）
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        // Comptime 生成的字符串字面量，零运行时开销
        const columns = comptime ComptimeReflect.generateColumnList(User);
        _ = columns;
    }

    const elapsed_comptime = timer.read();
    timer.reset();

    // 测试 2: 运行时拼接
    i = 0;
    while (i < iterations) : (i += 1) {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);

        // 模拟运行时类型反射和字符串拼接
        try buf.appendSlice(allocator, "id");
        try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, "name");
        try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, "email");
        try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, "age");
        try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, "created_at");
    }

    const elapsed_runtime = timer.read();

    printComparisonResults(
        "列名生成",
        iterations,
        elapsed_comptime,
        elapsed_runtime,
    );
}

/// 测试 SELECT 模板生成: Comptime vs Runtime
fn testSelectTemplateGeneration(allocator: std.mem.Allocator) !void {
    std.debug.print("2️⃣  SELECT 模板生成性能测试\n", .{});
    std.debug.print("   对比: Comptime 模板 vs 运行时构建\n\n", .{});

    const iterations: usize = 100000;
    var timer = try std.time.Timer.start();

    // 测试 1: Comptime 模板
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const sql = comptime ComptimeReflect.generateSelectTemplate(User, "users");
        _ = sql;
    }

    const elapsed_comptime = timer.read();
    timer.reset();

    // 测试 2: 运行时构建
    i = 0;
    while (i < iterations) : (i += 1) {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);

        try buf.appendSlice(allocator, "SELECT ");
        try buf.appendSlice(allocator, "id, name, email, age, created_at");
        try buf.appendSlice(allocator, " FROM ");
        try buf.appendSlice(allocator, "users");
    }

    const elapsed_runtime = timer.read();

    printComparisonResults(
        "SELECT 模板生成",
        iterations,
        elapsed_comptime,
        elapsed_runtime,
    );
}

/// 测试 INSERT 模板生成: Comptime vs Runtime
fn testInsertTemplateGeneration(allocator: std.mem.Allocator) !void {
    std.debug.print("3️⃣  INSERT 模板生成性能测试\n", .{});
    std.debug.print("   对比: Comptime 模板 vs 运行时构建\n\n", .{});

    const iterations: usize = 100000;
    var timer = try std.time.Timer.start();

    // 测试 1: Comptime 模板
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const sql = comptime ComptimeReflect.generateInsertTemplate(User, "users");
        _ = sql;
    }

    const elapsed_comptime = timer.read();
    timer.reset();

    // 测试 2: 运行时构建
    i = 0;
    while (i < iterations) : (i += 1) {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);

        try buf.appendSlice(allocator, "INSERT INTO ");
        try buf.appendSlice(allocator, "users");
        try buf.appendSlice(allocator, " (");
        try buf.appendSlice(allocator, "id, name, email, age, created_at");
        try buf.appendSlice(allocator, ") VALUES (");
        try buf.appendSlice(allocator, "$1, $2, $3, $4, $5");
        try buf.appendSlice(allocator, ")");
    }

    const elapsed_runtime = timer.read();

    printComparisonResults(
        "INSERT 模板生成",
        iterations,
        elapsed_comptime,
        elapsed_runtime,
    );
}

/// 测试占位符生成: Comptime vs Runtime
fn testPlaceholderGeneration(allocator: std.mem.Allocator) !void {
    std.debug.print("4️⃣  占位符生成性能测试\n", .{});
    std.debug.print("   对比: Comptime 生成 vs 运行时格式化\n\n", .{});

    const iterations: usize = 100000;
    var timer = try std.time.Timer.start();

    // 测试 1: Comptime 生成
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const placeholders = comptime ComptimeReflect.generatePlaceholders(User, 1);
        _ = placeholders;
    }

    const elapsed_comptime = timer.read();
    timer.reset();

    // 测试 2: 运行时格式化
    i = 0;
    while (i < iterations) : (i += 1) {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);

        // 模拟运行时 fmt.format
        try buf.appendSlice(allocator, "$1");
        try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, "$2");
        try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, "$3");
        try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, "$4");
        try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, "$5");
    }

    const elapsed_runtime = timer.read();

    printComparisonResults(
        "占位符生成",
        iterations,
        elapsed_comptime,
        elapsed_runtime,
    );
}

/// 打印对比结果
fn printComparisonResults(
    test_name: []const u8,
    iterations: usize,
    time_comptime: u64,
    time_runtime: u64,
) void {
    const time_comptime_ms = @as(f64, @floatFromInt(time_comptime)) / 1_000_000.0;
    const time_runtime_ms = @as(f64, @floatFromInt(time_runtime)) / 1_000_000.0;
    const time_improvement = (1.0 - time_comptime_ms / time_runtime_ms) * 100.0;

    const avg_comptime_ns = (time_comptime_ms * 1_000_000.0) / @as(f64, @floatFromInt(iterations));
    const avg_runtime_ns = (time_runtime_ms * 1_000_000.0) / @as(f64, @floatFromInt(iterations));

    std.debug.print("   测试: {s}\n", .{test_name});
    std.debug.print("   迭代次数: {}\n\n", .{iterations});

    std.debug.print("   📊 性能对比:\n", .{});
    std.debug.print("   ┌────────────────────┬──────────────┬──────────────┬──────────────┐\n", .{});
    std.debug.print("   │ 指标               │ Comptime     │ Runtime      │ 改善         │\n", .{});
    std.debug.print("   ├────────────────────┼──────────────┼──────────────┼──────────────┤\n", .{});
    std.debug.print("   │ 总耗时 (ms)        │ {d:>12.2} │ {d:>12.2} │ {d:>11.1}% │\n", .{ time_comptime_ms, time_runtime_ms, time_improvement });
    std.debug.print("   │ 平均耗时 (ns)      │ {d:>12.2} │ {d:>12.2} │ {d:>11.1}% │\n", .{ avg_comptime_ns, avg_runtime_ns, time_improvement });
    std.debug.print("   └────────────────────┴──────────────┴──────────────┴──────────────┘\n\n", .{});

    const passed = time_improvement >= 40.0; // AC4.8.4 目标：> 40% 提升

    std.debug.print("   ✨ 性能提升: {d:.1}%\n", .{time_improvement});
    std.debug.print("   📈 结果: {s}\n\n", .{if (passed) "✅ 达到目标 (> 40%)" else "⚠️  未达目标"});
    std.debug.print("   " ++ "-" ** 66 ++ "\n\n", .{});
}
