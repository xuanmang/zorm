# Story 003: 实现 Allocator 工具函数

## Status
Ready for Review

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
- [x] 创建 src/allocator.zig 文件 (AC: 1, 5)
  - [x] 实现 dupeString() 函数 (字符串复制)
  - [x] 实现 dupeSlice() 泛型函数 (切片复制)
  - [x] 实现 allocArgs() 函数 (从 tuple 分配 QueryArg 数组)
  - [x] 实现 freeArgs() 函数 (释放 QueryArg 数组内存)
- [x] 添加内存清理辅助函数 (AC: 4)
  - [x] 实现 freeStringSlice() (释放字符串切片)
  - [x] 实现 freeSlice() 泛型函数
- [x] 编写文档注释 (AC: 1-5)
  - [x] 为每个函数添加清晰的文档
  - [x] 说明内存所有权和生命周期
  - [x] 提供使用示例
- [x] 编写单元测试 (AC: 6)
  - [x] 测试字符串复制功能
  - [x] 测试切片复制功能
  - [x] 测试参数分配和释放
  - [x] 使用 std.testing.allocator 检测内存泄漏
  - [x] 验证错误处理 (OutOfMemory)

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md

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
| 2025-01-17 | 2.0 | 实现完成 - 创建 src/allocator.zig,实现 6 个工具函数,13 个单元测试全部通过,无内存泄漏 | James (Developer Agent) |

## Dev Agent Record

### Agent Model Used
- Primary: Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)
- Role: Full Stack Developer (James)

### Debug Log References
- 解决 Zig 0.15.2 编译问题:
  - 移除 freeSlice() 中不必要的 `_ = T` (pointless discard)
  - T 已在函数签名 slice: []T 中使用，无需额外 discard

### Completion Notes
- ✅ 成功实现完整的 ZORM Allocator 工具函数系统
- ✅ 实现 6 个核心工具函数:
  1. **dupeString()** - 字符串复制，分配新内存
  2. **dupeSlice()** - 泛型切片复制，支持任意类型
  3. **allocArgs()** - 从 tuple 分配 QueryArg 数组，编译时类型转换
  4. **freeArgs()** - 释放 QueryArg 数组
  5. **freeStringSlice()** - 释放字符串切片数组及其内容
  6. **freeSlice()** - 泛型切片释放
- ✅ 所有函数都遵循 Zig Allocator 模式:
  - 接受 Allocator 参数
  - 返回 Error!T 或 void
  - 清晰的内存所有权语义
- ✅ 完整的文档注释:
  - 每个函数都有详细说明
  - 明确内存所有权和生命周期
  - 提供使用示例和代码片段
  - 错误处理说明
- ✅ 实现 13 个单元测试,全部通过:
  1. dupeString allocates and copies correctly
  2. dupeString handles empty string
  3. dupeSlice allocates and copies integer slice
  4. dupeSlice handles empty slice
  5. dupeSlice works with different types
  6. allocArgs converts tuple to QueryArg array
  7. allocArgs handles empty tuple
  8. allocArgs handles various types
  9. freeStringSlice releases all memory
  10. freeSlice releases memory
  11. memory leak detection works
  12. errdefer in allocArgs prevents leak on failure
  13. arena allocator integration
- ✅ 内存泄漏检测:
  - 所有测试使用 std.testing.allocator
  - 自动检测内存泄漏
  - 验证 defer/errdefer 正确工作
  - 测试 Arena Allocator 集成
- ✅ 错误处理:
  - 所有分配函数返回 Error.OutOfMemory
  - errdefer 确保分配失败时清理
- ✅ 代码符合 Zig 0.15.2+ 规范
- ✅ 通过 zig fmt 格式检查
- ✅ 项目构建成功

**实现亮点**:
- 完整的 Allocator 模式实现，符合 Zig 最佳实践
- allocArgs() 使用 comptime 泛型，支持任意 tuple
- 自动内存泄漏检测，确保内存安全
- 支持 Arena Allocator，简化批量内存管理
- errdefer 确保异常安全
- 清晰的内存所有权文档

**技术决策**:
- 所有 dupe* 函数封装 allocator.dupe()，统一错误处理
- allocArgs() 使用 inline for 编译时展开，零运行时开销
- 不复制 QueryArg 中的字符串值，调用者管理生命周期
- freeStringSlice() 假设字符串由同一 allocator 分配
- 泛型函数支持任意类型，最大化代码复用

**Arena Allocator 集成**:
- 测试验证 Arena Allocator 正常工作
- 适用场景: 批量分配临时对象
- 优势: 一次性释放所有内存，简化管理

### File List
#### 新增文件:
- `src/allocator.zig` - ZORM Allocator 工具函数 (329 行)

#### 修改文件:
无

## QA Results

### Review Date: 2025-10-17

### Reviewed By: Quinn (Test Architect)

### Code Quality Assessment

**Overall Score: 97/100 - 优秀** ✅

实现质量非常高,完全满足所有验收标准:
- ✅ 实现 dupeString() 字符串复制工具,分配新内存
- ✅ 实现 dupeSlice() 泛型切片复制,支持任意类型
- ✅ 实现 allocArgs() 从 tuple 分配 QueryArg 数组,comptime 类型转换
- ✅ 实现 freeArgs/freeStringSlice/freeSlice 内存清理函数
- ✅ 所有函数遵循 Zig Allocator 模式,接受 Allocator 参数
- ✅ 13 个单元测试,全部通过,使用 std.testing.allocator 自动检测内存泄漏

**技术亮点**:
1. 内存管理规范,所有函数遵循 Zig Allocator 模式,清晰的所有权语义
2. 错误处理完善,使用 errdefer 确保异常安全
3. allocArgs() 使用 comptime 检查和 inline for 编译时展开,零运行时开销
4. 泛型设计优秀,dupeSlice/freeSlice 支持任意类型,最大化代码复用
5. 完整的内存泄漏检测,所有测试使用 std.testing.allocator
6. Arena Allocator 集成测试,验证批量内存管理场景

### Refactoring Performed

无需重构 - 代码质量已经很高 ✅

### Compliance Check

- Coding Standards: ✅ 符合 Zig 编码标准
- Project Structure: ✅ 文件位置正确 (src/allocator.zig, Foundation Layer)
- Testing Strategy: ✅ 13 个单元测试,覆盖全面,包含泄漏检测
- All ACs Met: ✅ 6/6 验收标准全部满足

### Improvements Checklist

**全部完成,无待办项** ✅

Future improvements (非阻塞,可选):
- [ ] 考虑在注释中明确说明为何使用 .@"struct" 转义关键字 (行 89)

### Security Review

✅ **PASS** - 无安全问题
- 所有函数清晰说明内存所有权,避免双重释放
- errdefer 确保异常安全,分配失败时自动清理
- 文档明确警告不要释放字面量或外部拥有的内存
- allocArgs 不复制字符串值,避免生命周期混淆

### Performance Considerations

✅ **PASS** - 性能优秀
- 工具函数为轻量级封装,最小化开销
- allocArgs 使用 inline for 编译时展开,零运行时开销
- comptime 类型检查,无运行时类型判断
- 直接封装 allocator.dupe/alloc/free,无额外抽象层

### Files Modified During Review

无 - 代码质量已达标,无需修改

### Gate Status

Gate: **PASS** → docs/qa/gates/003-implement-allocator-utils.yml
Quality Score: **97/100**
All NFRs: **PASS**

### Requirements Traceability

| AC | 需求 | 测试覆盖 | 状态 |
|----|------|---------|------|
| AC1 | 提供字符串复制工具 (dupeString) | test "dupeString *" (2个) | ✅ |
| AC2 | 提供切片复制工具 (dupeSlice) | test "dupeSlice *" (3个) | ✅ |
| AC3 | 提供参数数组分配函数 (allocArgs) | test "allocArgs *" (3个) | ✅ |
| AC4 | 提供内存清理辅助函数 | test "free* *" (2个) | ✅ |
| AC5 | 所有函数接受 Allocator 参数 | 所有测试验证 | ✅ |
| AC6 | 完整单元测试+内存泄漏检测 | 13个测试+std.testing.allocator | ✅ |

**Coverage: 6/6 (100%)** ✅

### Recommended Status

**✅ Ready for Done**

Story 003 已完全满足所有验收标准,代码质量优秀,无阻塞问题。建议标记为 Done。
