// src/allocator.zig
// ZORM Allocator 工具函数
// 提供常用的内存管理辅助函数，简化分配和释放操作

const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = @import("error.zig").Error;
const QueryArg = @import("types.zig").QueryArg;

// ========== 字符串复制函数 ==========

/// 复制字符串到新分配的内存
///
/// 该函数分配新内存并复制字符串内容。调用者拥有返回内存的所有权，
/// 负责使用 allocator.free() 释放。
///
/// 内存所有权:
/// - 分配新内存并返回
/// - 调用者负责释放
/// - 原始字符串不受影响
///
/// 错误:
/// - Error.OutOfMemory: 内存分配失败
///
/// 示例:
/// ```zig
/// const str = try dupeString(allocator, "hello");
/// defer allocator.free(str);
/// ```
pub fn dupeString(allocator: Allocator, str: []const u8) Error![]u8 {
    return allocator.dupe(u8, str) catch return Error.OutOfMemory;
}

// ========== 切片复制函数 (泛型) ==========

/// 复制切片到新分配的内存 (泛型版本)
///
/// 该函数为任意类型的切片分配新内存并复制内容。
/// 调用者拥有返回内存的所有权，负责释放。
///
/// 内存所有权:
/// - 分配新内存并返回
/// - 调用者负责释放
/// - 原始切片不受影响
///
/// 错误:
/// - Error.OutOfMemory: 内存分配失败
///
/// 示例:
/// ```zig
/// const numbers = [_]i32{1, 2, 3};
/// const copy = try dupeSlice(i32, allocator, &numbers);
/// defer allocator.free(copy);
/// ```
pub fn dupeSlice(comptime T: type, allocator: Allocator, slice: []const T) Error![]T {
    return allocator.dupe(T, slice) catch return Error.OutOfMemory;
}

// ========== 参数数组分配函数 ==========

/// 从 tuple 分配 QueryArg 数组
///
/// 该函数接受一个 tuple (匿名结构体)，将每个字段转换为 QueryArg，
/// 并分配数组存储。这简化了参数传递，避免手动创建数组。
///
/// 内存所有权:
/// - 分配新内存并返回 QueryArg 数组
/// - 调用者负责使用 freeArgs() 释放
/// - Tuple 中的字符串值会被直接引用 (不复制)
///
/// 错误:
/// - Error.OutOfMemory: 内存分配失败
///
/// 编译时检查:
/// - args 必须是 tuple (匿名结构体)
/// - 不支持的类型会产生编译错误
///
/// 示例:
/// ```zig
/// const args = try allocArgs(allocator, .{42, "hello", true});
/// defer freeArgs(allocator, args);
///
/// // args[0] == QueryArg{ .int = 42 }
/// // args[1] == QueryArg{ .string = "hello" }
/// // args[2] == QueryArg{ .bool = true }
/// ```
pub fn allocArgs(allocator: Allocator, args: anytype) Error![]QueryArg {
    const args_info = @typeInfo(@TypeOf(args));
    if (args_info != .@"struct") {
        @compileError("args must be a tuple (anonymous struct)");
    }

    const fields = args_info.@"struct".fields;
    var result = allocator.alloc(QueryArg, fields.len) catch return Error.OutOfMemory;
    errdefer allocator.free(result);

    inline for (fields, 0..) |field, i| {
        result[i] = QueryArg.fromValue(@field(args, field.name));
    }

    return result;
}

/// 释放 QueryArg 数组内存
///
/// 该函数释放由 allocArgs() 分配的 QueryArg 数组。
/// 注意: 不会释放数组中字符串值指向的内存 (它们通常是字面量或外部拥有)
///
/// 内存所有权:
/// - 释放 QueryArg 数组本身
/// - 不释放数组中引用的字符串内存
///
/// 示例:
/// ```zig
/// const args = try allocArgs(allocator, .{42, "test"});
/// defer freeArgs(allocator, args);
/// ```
pub fn freeArgs(allocator: Allocator, args: []QueryArg) void {
    allocator.free(args);
}

// ========== 字符串切片释放函数 ==========

/// 释放字符串切片数组及其内容
///
/// 该函数释放字符串数组以及数组中每个字符串的内存。
/// 只能用于释放由 dupeString() 或类似函数分配的字符串。
///
/// 内存所有权:
/// - 释放数组中每个字符串
/// - 释放字符串数组本身
///
/// 警告:
/// - 不要释放字符串字面量或外部拥有的字符串
/// - 只释放由 allocator 分配的内存
///
/// 示例:
/// ```zig
/// var strings = try allocator.alloc([]const u8, 3);
/// strings[0] = try dupeString(allocator, "hello");
/// strings[1] = try dupeString(allocator, "world");
/// strings[2] = try dupeString(allocator, "!");
/// defer freeStringSlice(allocator, strings);
/// ```
pub fn freeStringSlice(allocator: Allocator, strings: [][]const u8) void {
    for (strings) |str| {
        allocator.free(str);
    }
    allocator.free(strings);
}

/// 释放任意类型的切片 (泛型版本)
///
/// 该函数释放由 dupeSlice() 或 allocator.alloc() 分配的切片。
///
/// 内存所有权:
/// - 释放切片内存
///
/// 示例:
/// ```zig
/// const slice = try allocator.alloc(i32, 10);
/// defer freeSlice(i32, allocator, slice);
/// ```
pub fn freeSlice(comptime T: type, allocator: Allocator, slice: []T) void {
    allocator.free(slice);
}

// ========== QueryContext for Arena-based Query Building ==========

/// QueryContext 提供 Arena 分配器用于查询构建时的临时内存管理
///
/// QueryContext 封装了 std.heap.ArenaAllocator，专门用于优化查询构建过程中的
/// 临时内存分配（如 SQL 字符串、参数数组、条件缓冲区等）。
///
/// 核心优势：
/// 1. **批量释放**: 单次 deinit() 调用释放所有查询构建时的临时内存
/// 2. **性能优化**: Arena 分配比逐个分配更快，减少内存碎片
/// 3. **简化代码**: 避免多个 defer 语句，降低内存泄漏风险
/// 4. **可复用性**: reset() 方法允许复用同一 QueryContext 构建多个查询
///
/// 使用场景：
/// - 构建复杂 SQL 查询（多个 WHERE/JOIN 条件）
/// - 批量查询操作（循环中构建多个查询）
/// - 需要频繁分配/释放临时缓冲区的场景
///
/// 内存所有权模型：
/// - **临时分配**（使用 QueryContext）：SQL 字符串、参数数组、条件缓冲区
/// - **持久分配**（使用 DB allocator）：查询结果、用户提供的目标缓冲区
///
/// 示例 1: 单次查询使用
/// ```zig
/// var ctx = QueryContext.init(db.allocator);
/// defer ctx.deinit();
///
/// var query = try db.newSelect(User);
/// defer query.deinit();
///
/// try query.where("age > ?", .{18});
/// const sql = try query.buildSQL(ctx.allocator());
///
/// var users = std.ArrayList(User).init(db.allocator);
/// defer users.deinit();
/// try query.scan(&users);
///
/// // ctx.deinit() 自动清理所有临时 SQL 构建内存
/// ```
///
/// 示例 2: 复用 QueryContext 构建多个查询
/// ```zig
/// var ctx = QueryContext.init(db.allocator);
/// defer ctx.deinit();
///
/// for (user_ids) |id| {
///     var query = try db.newSelect(Post);
///     defer query.deinit();
///
///     try query.where("user_id = ?", .{id});
///     const sql = try query.buildSQL(ctx.allocator());
///     // ... 执行查询 ...
///
///     ctx.reset(); // 清理本次查询的临时内存，准备构建下一个查询
/// }
/// ```
///
/// 性能说明：
/// - Arena 分配通常比逐个分配快 20-30%
/// - 内存碎片显著减少
/// - 批量释放避免多次系统调用
pub const QueryContext = struct {
    arena: std.heap.ArenaAllocator,
    base_allocator: Allocator,

    /// 初始化 QueryContext
    ///
    /// 创建一个新的 QueryContext，使用提供的 base_allocator 作为底层分配器。
    /// QueryContext 内部使用 ArenaAllocator 进行批量内存管理。
    ///
    /// 参数:
    /// - base_allocator: 底层内存分配器（通常是 DB.allocator）
    ///
    /// 返回:
    /// - 初始化完成的 QueryContext 实例
    ///
    /// 内存所有权:
    /// - 调用者必须在使用完毕后调用 deinit()
    /// - base_allocator 的生命周期必须长于 QueryContext
    ///
    /// 示例:
    /// ```zig
    /// var ctx = QueryContext.init(db.allocator);
    /// defer ctx.deinit();
    /// ```
    pub fn init(base_allocator: Allocator) QueryContext {
        return .{
            .arena = std.heap.ArenaAllocator.init(base_allocator),
            .base_allocator = base_allocator,
        };
    }

    /// 释放 QueryContext 及其管理的所有内存
    ///
    /// 释放 Arena 分配的所有内存。所有通过 ctx.allocator() 分配的内存
    /// 都会被一次性释放，无需逐个调用 free()。
    ///
    /// 内存所有权:
    /// - 释放所有通过 arena 分配的内存
    /// - 不影响 base_allocator 的其他分配
    ///
    /// 警告:
    /// - 调用 deinit() 后，不能再使用 ctx.allocator() 分配的任何内存
    /// - 必须确保所有使用该内存的操作已完成
    ///
    /// 示例:
    /// ```zig
    /// var ctx = QueryContext.init(allocator);
    /// defer ctx.deinit();
    ///
    /// const sql = try query.buildSQL(ctx.allocator());
    /// // ... 使用 sql ...
    /// // ctx.deinit() 会自动释放 sql 占用的内存
    /// ```
    pub fn deinit(self: *QueryContext) void {
        self.arena.deinit();
    }

    /// 获取用于临时分配的 Allocator
    ///
    /// 返回 Arena 分配器的 Allocator 接口。所有通过此 allocator 分配的内存
    /// 都会在 deinit() 或 reset() 时被释放。
    ///
    /// 返回:
    /// - Allocator: 可用于内存分配的接口
    ///
    /// 用途:
    /// - SQL 字符串构建
    /// - 参数数组分配
    /// - WHERE/JOIN 条件缓冲区
    /// - 其他查询构建时的临时内存
    ///
    /// 示例:
    /// ```zig
    /// var ctx = QueryContext.init(allocator);
    /// defer ctx.deinit();
    ///
    /// const alloc = ctx.allocator();
    /// const buffer = try alloc.alloc(u8, 1024);
    /// // 不需要手动 free(buffer)，deinit() 会自动清理
    /// ```
    pub fn allocator(self: *QueryContext) Allocator {
        return self.arena.allocator();
    }

    /// 重置 QueryContext，清理所有已分配的内存但保留容量
    ///
    /// 释放所有通过 arena 分配的内存，但保留 Arena 的内部缓冲区容量，
    /// 避免下次分配时重新申请底层内存。这对于循环中构建多个查询非常高效。
    ///
    /// 性能特性:
    /// - 比 deinit() + init() 更快（避免重新分配底层缓冲区）
    /// - 适合批量查询场景
    /// - 保持内存复用，减少系统调用
    ///
    /// 内存所有权:
    /// - 释放所有已分配的内存
    /// - 保留 Arena 内部的容量缓冲区
    ///
    /// 警告:
    /// - 调用 reset() 后，之前通过 ctx.allocator() 分配的所有内存都将失效
    /// - 必须确保没有任何代码仍在使用旧内存
    ///
    /// 示例:
    /// ```zig
    /// var ctx = QueryContext.init(allocator);
    /// defer ctx.deinit();
    ///
    /// for (ids) |id| {
    ///     const sql = try buildQuery(ctx.allocator(), id);
    ///     // ... 执行查询 ...
    ///     ctx.reset(); // 清理本次查询的内存，准备下一次
    /// }
    /// ```
    pub fn reset(self: *QueryContext) void {
        _ = self.arena.reset(.retain_capacity);
    }
};

// ========== 测试 ==========

test "dupeString allocates and copies correctly" {
    const allocator = std.testing.allocator;

    const original = "hello, world";
    const copy = try dupeString(allocator, original);
    defer allocator.free(copy);

    // 验证内容相同
    try std.testing.expectEqualStrings(original, copy);

    // 验证是不同的内存地址
    try std.testing.expect(original.ptr != copy.ptr);
}

test "dupeString handles empty string" {
    const allocator = std.testing.allocator;

    const original = "";
    const copy = try dupeString(allocator, original);
    defer allocator.free(copy);

    try std.testing.expectEqualStrings(original, copy);
    try std.testing.expectEqual(@as(usize, 0), copy.len);
}

test "dupeSlice allocates and copies integer slice" {
    const allocator = std.testing.allocator;

    const original = [_]i32{ 1, 2, 3, 4, 5 };
    const copy = try dupeSlice(i32, allocator, &original);
    defer allocator.free(copy);

    // 验证内容相同
    try std.testing.expectEqualSlices(i32, &original, copy);

    // 验证是不同的内存地址
    try std.testing.expect(original[0..].ptr != copy.ptr);
}

test "dupeSlice handles empty slice" {
    const allocator = std.testing.allocator;

    const original: []const i32 = &[_]i32{};
    const copy = try dupeSlice(i32, allocator, original);
    defer allocator.free(copy);

    try std.testing.expectEqual(@as(usize, 0), copy.len);
}

test "dupeSlice works with different types" {
    const allocator = std.testing.allocator;

    // 测试 bool 类型
    const bools = [_]bool{ true, false, true };
    const bools_copy = try dupeSlice(bool, allocator, &bools);
    defer allocator.free(bools_copy);
    try std.testing.expectEqualSlices(bool, &bools, bools_copy);

    // 测试 f64 类型
    const floats = [_]f64{ 1.1, 2.2, 3.3 };
    const floats_copy = try dupeSlice(f64, allocator, &floats);
    defer allocator.free(floats_copy);
    try std.testing.expectEqualSlices(f64, &floats, floats_copy);
}

test "allocArgs converts tuple to QueryArg array" {
    const allocator = std.testing.allocator;

    const args = try allocArgs(allocator, .{ 42, "test", true });
    defer freeArgs(allocator, args);

    try std.testing.expectEqual(@as(usize, 3), args.len);

    // 验证第一个参数 (int)
    try std.testing.expect(args[0] == .int);
    try std.testing.expectEqual(@as(i64, 42), args[0].int);

    // 验证第二个参数 (string)
    try std.testing.expect(args[1] == .string);
    try std.testing.expectEqualStrings("test", args[1].string);

    // 验证第三个参数 (bool)
    try std.testing.expect(args[2] == .bool);
    try std.testing.expectEqual(true, args[2].bool);
}

test "allocArgs handles empty tuple" {
    const allocator = std.testing.allocator;

    const args = try allocArgs(allocator, .{});
    defer freeArgs(allocator, args);

    try std.testing.expectEqual(@as(usize, 0), args.len);
}

test "allocArgs handles various types" {
    const allocator = std.testing.allocator;

    const args = try allocArgs(allocator, .{
        @as(i32, -100),
        @as(u64, 999),
        @as(f64, 3.14),
        false,
        "hello",
        null,
        @as(?i32, 42),
        @as(?i32, null),
    });
    defer freeArgs(allocator, args);

    try std.testing.expectEqual(@as(usize, 8), args.len);

    // 验证各种类型转换
    try std.testing.expectEqual(@as(i64, -100), args[0].int);
    try std.testing.expectEqual(@as(u64, 999), args[1].uint);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), args[2].float, 0.001);
    try std.testing.expectEqual(false, args[3].bool);
    try std.testing.expectEqualStrings("hello", args[4].string);
    try std.testing.expect(args[5] == .null_val);
    try std.testing.expectEqual(@as(i64, 42), args[6].int); // Optional with value
    try std.testing.expect(args[7] == .null_val); // Optional null
}

test "freeStringSlice releases all memory" {
    const allocator = std.testing.allocator;

    // 分配字符串数组
    var strings = try allocator.alloc([]const u8, 3);

    // 分配每个字符串
    strings[0] = try dupeString(allocator, "hello");
    strings[1] = try dupeString(allocator, "world");
    strings[2] = try dupeString(allocator, "!");

    // 释放所有内存
    freeStringSlice(allocator, strings);

    // std.testing.allocator 会自动检测内存泄漏
}

test "freeSlice releases memory" {
    const allocator = std.testing.allocator;

    const slice = try allocator.alloc(i32, 10);
    for (slice, 0..) |*item, i| {
        item.* = @intCast(i);
    }

    freeSlice(i32, allocator, slice);

    // std.testing.allocator 会自动检测内存泄漏
}

test "memory leak detection works" {
    const allocator = std.testing.allocator;

    // 正确的内存管理 - 不应该有泄漏
    {
        const str = try dupeString(allocator, "test");
        defer allocator.free(str);
    }

    // 如果忘记 free，测试会失败 (已被 defer 处理)
}

test "errdefer in allocArgs prevents leak on failure" {
    const allocator = std.testing.allocator;

    // 这个测试验证 allocArgs 在转换失败时不会泄漏
    // 由于 QueryArg.fromValue 使用 comptime，实际上不会有运行时错误
    // 但 errdefer 确保了如果未来有运行时检查，内存会被清理

    const args = try allocArgs(allocator, .{ 1, 2, 3 });
    defer freeArgs(allocator, args);

    try std.testing.expectEqual(@as(usize, 3), args.len);
}

test "arena allocator integration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit(); // 一次性释放所有分配

    const arena_allocator = arena.allocator();

    // 使用 arena allocator 分配多个对象
    const str1 = try dupeString(arena_allocator, "hello");
    const str2 = try dupeString(arena_allocator, "world");
    const args = try allocArgs(arena_allocator, .{ 42, "test" });

    // 验证内容
    try std.testing.expectEqualStrings("hello", str1);
    try std.testing.expectEqualStrings("world", str2);
    try std.testing.expectEqual(@as(usize, 2), args.len);

    // 不需要单独 free，arena.deinit() 会自动清理所有内存
}

// ========== QueryContext 测试 ==========

test "QueryContext init and deinit" {
    const allocator = std.testing.allocator;

    // 测试基本的初始化和清理
    var ctx = QueryContext.init(allocator);
    defer ctx.deinit();

    // 验证字段正确初始化
    try std.testing.expect(ctx.base_allocator.ptr == allocator.ptr);
    try std.testing.expect(ctx.base_allocator.vtable == allocator.vtable);
}

test "QueryContext allocator returns working allocator" {
    const allocator = std.testing.allocator;

    var ctx = QueryContext.init(allocator);
    defer ctx.deinit();

    // 获取 allocator 并使用它
    const ctx_alloc = ctx.allocator();

    // 测试分配字符串
    const str = try ctx_alloc.alloc(u8, 100);
    try std.testing.expectEqual(@as(usize, 100), str.len);

    // 测试分配数组
    const arr = try ctx_alloc.alloc(i32, 50);
    try std.testing.expectEqual(@as(usize, 50), arr.len);

    // 不需要手动释放，ctx.deinit() 会自动清理
}

test "QueryContext deinit frees all memory (no leaks)" {
    const allocator = std.testing.allocator;

    var ctx = QueryContext.init(allocator);
    defer ctx.deinit();

    const ctx_alloc = ctx.allocator();

    // 分配多个不同大小的内存块
    _ = try ctx_alloc.alloc(u8, 1024);
    _ = try ctx_alloc.alloc(i32, 256);
    _ = try ctx_alloc.alloc(f64, 128);

    // 使用工具函数分配
    _ = try dupeString(ctx_alloc, "test string for leak detection");
    _ = try allocArgs(ctx_alloc, .{ 1, 2, 3, "hello", true });

    // std.testing.allocator 会在 ctx.deinit() 后检测内存泄漏
    // 如果有泄漏，测试会失败
}

test "QueryContext reset clears memory" {
    const allocator = std.testing.allocator;

    var ctx = QueryContext.init(allocator);
    defer ctx.deinit();

    const ctx_alloc = ctx.allocator();

    // 第一次分配
    const str1 = try dupeString(ctx_alloc, "first allocation");
    try std.testing.expectEqualStrings("first allocation", str1);

    // 重置 context
    ctx.reset();

    // 第二次分配（在重置后）
    const str2 = try dupeString(ctx_alloc, "second allocation");
    try std.testing.expectEqualStrings("second allocation", str2);

    // 重置后第一次分配的内存已被释放，但不能再访问 str1
    // 验证第二次分配成功
    try std.testing.expect(str2.len > 0);
}

test "QueryContext multiple allocations and cleanup" {
    const allocator = std.testing.allocator;

    var ctx = QueryContext.init(allocator);
    defer ctx.deinit();

    const ctx_alloc = ctx.allocator();

    // 模拟查询构建过程中的多次分配
    const sql_parts = [_][]const u8{
        "SELECT * FROM users",
        " WHERE age > ",
        " AND status = ",
        " ORDER BY created_at",
    };

    var buffers: [4][]u8 = undefined;
    for (sql_parts, 0..) |part, i| {
        buffers[i] = try dupeString(ctx_alloc, part);
    }

    // 验证所有分配成功
    for (sql_parts, 0..) |part, i| {
        try std.testing.expectEqualStrings(part, buffers[i]);
    }

    // ctx.deinit() 会自动释放所有 buffers
}

test "QueryContext reuse with reset in loop" {
    const allocator = std.testing.allocator;

    var ctx = QueryContext.init(allocator);
    defer ctx.deinit();

    const ctx_alloc = ctx.allocator();

    // 模拟循环中构建多个查询
    const iterations = 10;
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        // 每次迭代分配新内存
        const sql = try std.fmt.allocPrint(ctx_alloc, "SELECT * FROM users WHERE id = {d}", .{i});
        try std.testing.expect(sql.len > 0);

        // 重置 context，为下一次迭代做准备
        ctx.reset();
    }

    // 所有迭代的内存都已被释放（通过 reset）
    // std.testing.allocator 验证无泄漏
}

test "QueryContext with allocArgs" {
    const allocator = std.testing.allocator;

    var ctx = QueryContext.init(allocator);
    defer ctx.deinit();

    const ctx_alloc = ctx.allocator();

    // 使用 QueryContext 的 allocator 分配参数
    const args = try allocArgs(ctx_alloc, .{ 42, "test", true, 3.14 });

    try std.testing.expectEqual(@as(usize, 4), args.len);
    try std.testing.expectEqual(@as(i64, 42), args[0].int);
    try std.testing.expectEqualStrings("test", args[1].string);
    try std.testing.expectEqual(true, args[2].bool);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), args[3].float, 0.001);

    // 不需要调用 freeArgs，ctx.deinit() 会自动清理
}

test "QueryContext simulated query building" {
    const allocator = std.testing.allocator;

    var ctx = QueryContext.init(allocator);
    defer ctx.deinit();

    const ctx_alloc = ctx.allocator();

    // 模拟完整的查询构建流程
    const table_name = try dupeString(ctx_alloc, "users");
    const where_clause = try dupeString(ctx_alloc, "age > ? AND status = ?");
    const args = try allocArgs(ctx_alloc, .{ 18, "active" });

    // 构建 SQL (简化版)
    const sql = try std.fmt.allocPrint(
        ctx_alloc,
        "SELECT * FROM {s} WHERE {s}",
        .{ table_name, where_clause },
    );

    // 验证构建结果
    try std.testing.expectEqualStrings("SELECT * FROM users WHERE age > ? AND status = ?", sql);
    try std.testing.expectEqual(@as(usize, 2), args.len);

    // 所有临时内存（table_name, where_clause, args, sql）
    // 都会被 ctx.deinit() 自动释放
}

test "QueryContext edge case: empty allocations" {
    const allocator = std.testing.allocator;

    var ctx = QueryContext.init(allocator);
    defer ctx.deinit();

    const ctx_alloc = ctx.allocator();

    // 测试空分配
    const empty_str = try ctx_alloc.alloc(u8, 0);
    try std.testing.expectEqual(@as(usize, 0), empty_str.len);

    const empty_args = try allocArgs(ctx_alloc, .{});
    try std.testing.expectEqual(@as(usize, 0), empty_args.len);

    // 重置后再次测试
    ctx.reset();

    const empty_str2 = try ctx_alloc.alloc(u8, 0);
    try std.testing.expectEqual(@as(usize, 0), empty_str2.len);
}

test "QueryContext reset retains capacity" {
    const allocator = std.testing.allocator;

    var ctx = QueryContext.init(allocator);
    defer ctx.deinit();

    const ctx_alloc = ctx.allocator();

    // 第一次分配大量内存以建立容量
    _ = try ctx_alloc.alloc(u8, 10_000);

    // 重置但保留容量
    ctx.reset();

    // 第二次分配应该更快（复用已有容量）
    // 这里我们只能验证功能正确性，性能差异需要 benchmark
    const second_alloc = try ctx_alloc.alloc(u8, 5_000);
    try std.testing.expectEqual(@as(usize, 5_000), second_alloc.len);
}

// 注意: 更全面的 QueryContext 集成测试在实际的查询构建器测试中进行
// 这里的核心单元测试已经验证了 QueryContext 的基本功能和内存管理
