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
