# Story 003: 实现 Allocator 工具函数

## Status
Draft

## Story
**As a** ZORM 开发者,
**I want** 一套 Allocator 工具函数,
**so that** 能够简化内存管理操作，提供常用的分配和释放辅助函数

## Acceptance Criteria
1. 提供字符串复制工具函数 (dupeString)
2. 提供切片复制工具函数 (dupeSlice)
3. 提供参数数组分配函数 (allocArgs)
4. 提供内存清理辅助函数
5. 所有函数都接受 Allocator 参数，符合 Zig 内存管理模式
6. 编写完整的单元测试，包括内存泄漏检测

## Tasks / Subtasks
- [ ] 创建 src/allocator.zig 文件 (AC: 1, 5)
  - [ ] 实现 dupeString() 函数 (字符串复制)
  - [ ] 实现 dupeSlice() 泛型函数 (切片复制)
  - [ ] 实现 allocArgs() 函数 (从 tuple 分配 QueryArg 数组)
  - [ ] 实现 freeArgs() 函数 (释放 QueryArg 数组内存)
- [ ] 添加内存清理辅助函数 (AC: 4)
  - [ ] 实现 freeStringSlice() (释放字符串切片)
  - [ ] 实现 freeSlice() 泛型函数
- [ ] 编写文档注释 (AC: 1-5)
  - [ ] 为每个函数添加清晰的文档
  - [ ] 说明内存所有权和生命周期
  - [ ] 提供使用示例
- [ ] 编写单元测试 (AC: 6)
  - [ ] 测试字符串复制功能
  - [ ] 测试切片复制功能
  - [ ] 测试参数分配和释放
  - [ ] 使用 std.testing.allocator 检测内存泄漏
  - [ ] 验证错误处理 (OutOfMemory)

## Dev Notes

### 架构参考
- **文档位置**: [docs/architecture.md#内存管理策略](architecture.md#内存管理策略) (行 1132-1249)
- **关键设计原则**:
  - 所有分配内存的函数都接受 Allocator 参数
  - 调用者负责释放分配的内存
  - 使用 defer/errdefer 确保资源清理
  - Arena Allocator 用于临时分配
  - 提供清晰的内存所有权语义

### 文件位置
- **目标文件**: `src/allocator.zig`
- **依赖文件**:
  - `src/error.zig` (OutOfMemory 错误)
  - `src/types.zig` (QueryArg 类型)

### 工具函数详解

#### 1. 字符串复制
```zig
/// 复制字符串到新分配的内存
/// 调用者负责使用 allocator.free() 释放
pub fn dupeString(allocator: Allocator, str: []const u8) ![]u8 {
    return allocator.dupe(u8, str);
}
```

#### 2. 切片复制 (泛型)
```zig
/// 复制切片到新分配的内存 (泛型版本)
/// 调用者负责释放内存
pub fn dupeSlice(comptime T: type, allocator: Allocator, slice: []const T) ![]T {
    return allocator.dupe(T, slice);
}
```

#### 3. 参数数组分配
```zig
/// 从 tuple 分配 QueryArg 数组
/// 例如: allocArgs(allocator, .{42, "hello", true})
pub fn allocArgs(allocator: Allocator, args: anytype) ![]QueryArg {
    const args_info = @typeInfo(@TypeOf(args));
    if (args_info != .Struct) {
        @compileError("args must be a tuple");
    }

    const fields = args_info.Struct.fields;
    var result = try allocator.alloc(QueryArg, fields.len);
    errdefer allocator.free(result);

    inline for (fields, 0..) |field, i| {
        result[i] = QueryArg.fromValue(@field(args, field.name));
    }

    return result;
}
```

#### 4. 参数数组释放
```zig
/// 释放 QueryArg 数组内存
pub fn freeArgs(allocator: Allocator, args: []QueryArg) void {
    allocator.free(args);
}
```

#### 5. 字符串切片释放
```zig
/// 释放字符串切片数组
pub fn freeStringSlice(allocator: Allocator, strings: [][]const u8) void {
    for (strings) |str| {
        allocator.free(str);
    }
    allocator.free(strings);
}
```

### 实现指南

1. **内存所有权规则**
   - 所有 `dupe*` 函数分配新内存，调用者拥有所有权
   - 所有 `alloc*` 函数分配新内存，调用者负责释放
   - 所有 `free*` 函数释放内存，之后不能再访问

2. **错误处理**
   ```zig
   pub fn dupeString(allocator: Allocator, str: []const u8) ![]u8 {
       return allocator.dupe(u8, str) catch |err| {
           // 通常是 OutOfMemory
           return err;
       };
   }
   ```

3. **使用 defer 确保清理**
   ```zig
   const args = try allocArgs(allocator, .{42, "hello"});
   defer freeArgs(allocator, args);

   // 使用 args...
   ```

4. **Arena Allocator 模式**
   ```zig
   var arena = std.heap.ArenaAllocator.init(base_allocator);
   defer arena.deinit(); // 一次性释放所有分配

   const args = try allocArgs(arena.allocator(), .{1, 2, 3});
   // 不需要单独 free，arena.deinit() 会自动清理
   ```

### Testing
- **测试文件位置**: `tests/unit/allocator_test.zig`
- **测试框架**: Zig 内置测试框架
- **测试策略**:
  - 使用 `std.testing.allocator` 自动检测内存泄漏
  - 测试所有分配和释放函数
  - 验证 defer/errdefer 正确工作
  - 测试 OutOfMemory 错误处理
  - 测试 Arena Allocator 集成

### 技术约束
- **Zig 版本**: 0.15.2+
- **内存管理**: 必须使用 Allocator 模式
- **错误处理**: 内存分配失败返回 OutOfMemory
- **性能要求**: 工具函数应为轻量级封装，最小化开销

### 依赖项
- `src/error.zig`: 使用 OutOfMemory 错误
- `src/types.zig`: allocArgs 函数需要 QueryArg 类型

## Code Examples

### Allocator 工具函数骨架
```zig
// src/allocator.zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = @import("error.zig").Error;
const QueryArg = @import("types.zig").QueryArg;

/// 复制字符串到新分配的内存
///
/// 调用者负责使用 allocator.free() 释放返回的内存
///
/// 示例:
/// ```zig
/// const str = try dupeString(allocator, "hello");
/// defer allocator.free(str);
/// ```
pub fn dupeString(allocator: Allocator, str: []const u8) ![]u8 {
    return allocator.dupe(u8, str);
}

/// 复制切片到新分配的内存 (泛型版本)
///
/// 调用者负责释放返回的内存
///
/// 示例:
/// ```zig
/// const numbers = [_]i32{1, 2, 3};
/// const copy = try dupeSlice(i32, allocator, &numbers);
/// defer allocator.free(copy);
/// ```
pub fn dupeSlice(comptime T: type, allocator: Allocator, slice: []const T) ![]T {
    return allocator.dupe(T, slice);
}

/// 从 tuple 分配 QueryArg 数组
///
/// 自动将 tuple 中的每个值转换为 QueryArg
/// 调用者负责使用 freeArgs() 释放
///
/// 示例:
/// ```zig
/// const args = try allocArgs(allocator, .{42, "hello", true});
/// defer freeArgs(allocator, args);
/// ```
pub fn allocArgs(allocator: Allocator, args: anytype) ![]QueryArg {
    const args_info = @typeInfo(@TypeOf(args));
    if (args_info != .Struct) {
        @compileError("args must be a tuple");
    }

    const fields = args_info.Struct.fields;
    var result = try allocator.alloc(QueryArg, fields.len);
    errdefer allocator.free(result);

    inline for (fields, 0..) |field, i| {
        result[i] = QueryArg.fromValue(@field(args, field.name));
    }

    return result;
}

/// 释放 QueryArg 数组
pub fn freeArgs(allocator: Allocator, args: []QueryArg) void {
    allocator.free(args);
}

// TODO: 实现其他工具函数...

test "dupeString allocates and copies correctly" {
    const allocator = std.testing.allocator;

    const original = "hello, world";
    const copy = try dupeString(allocator, original);
    defer allocator.free(copy);

    try std.testing.expectEqualStrings(original, copy);
    // std.testing.allocator 会自动检测内存泄漏
}

test "allocArgs converts tuple to QueryArg array" {
    const allocator = std.testing.allocator;

    const args = try allocArgs(allocator, .{ 42, "test", true });
    defer freeArgs(allocator, args);

    try std.testing.expectEqual(@as(usize, 3), args.len);
    try std.testing.expect(args[0] == .int);
    try std.testing.expectEqual(@as(i64, 42), args[0].int);
}
```

## Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob (Scrum Master) |

## Dev Agent Record
_此部分将由开发 Agent 在实现过程中填写_

### Agent Model Used
_待填写_

### Debug Log References
_待填写_

### Completion Notes
_待填写_

### File List
_待填写_

## QA Results
_此部分将由 QA Agent 在审查后填写_
