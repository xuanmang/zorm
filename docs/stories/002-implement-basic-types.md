# Story 002: 实现基础类型定义

## Status
Draft

## Story
**As a** ZORM 开发者,
**I want** 完整的基础类型定义系统,
**so that** 查询构建、参数绑定和数据映射都能使用统一的类型系统，确保类型安全

## Acceptance Criteria
1. 定义 QueryArg 联合类型，支持所有常见 SQL 参数类型
2. 定义 WHERE/JOIN/ORDER BY/HAVING 等 SQL 子句的结构体
3. 定义列类型枚举 (ColumnType)，映射到数据库类型
4. 提供类型转换函数 (fromValue)
5. 所有类型定义符合 Zig 0.15.2+ 规范并支持 comptime 使用

## Tasks / Subtasks
- [ ] 创建 src/types.zig 文件 (AC: 1)
  - [ ] 定义 QueryArg 联合类型 (支持 int/uint/float/bool/string/bytes/null)
  - [ ] 实现 QueryArg.fromValue() 函数进行类型转换
  - [ ] 添加 comptime 类型检查支持
- [ ] 定义 SQL 子句结构体 (AC: 2)
  - [ ] WhereClause (condition, args, operator)
  - [ ] WhereOperator enum (and_op, or_op)
  - [ ] JoinClause (join_type, table, condition)
  - [ ] JoinType enum (inner, left, right, full, cross)
  - [ ] OrderByClause (column, direction)
  - [ ] OrderDirection enum (asc, desc)
  - [ ] HavingClause (condition, args)
- [ ] 定义列类型枚举 (AC: 3)
  - [ ] ColumnType enum (integer, bigint, text, varchar, timestamp, jsonb 等)
  - [ ] 映射 Zig 类型到 SQL 类型
  - [ ] 映射 SQL 类型到 Zig 类型
- [ ] 编写类型转换测试 (AC: 4)
  - [ ] 测试 QueryArg.fromValue() 对所有支持类型的转换
  - [ ] 测试可选类型 (Optional) 的处理
  - [ ] 测试错误类型的处理
- [ ] 编写类型安全验证测试 (AC: 5)
  - [ ] 验证 comptime 类型检查
  - [ ] 验证不支持类型的编译时错误

## Dev Notes

### 架构参考
- **文档位置**: [docs/architecture.md#接口定义](architecture.md#接口定义) (行 1757-1872)
- **关键设计原则**:
  - 使用 Zig 联合类型 (union) 表示多种参数类型
  - 利用 comptime 进行类型检查和转换
  - 支持可选类型 (Optional) 的自动处理
  - 所有类型转换在编译时验证

### 文件位置
- **目标文件**: `src/types.zig`
- **依赖文件**: `src/error.zig` (用于类型转换错误)

### 类型定义详解

#### 1. QueryArg - 查询参数类型
```zig
pub const QueryArg = union(enum) {
    int: i64,
    uint: u64,
    float: f64,
    bool: bool,
    string: []const u8,
    bytes: []const u8,
    null_val: void,

    /// 从任意类型值创建 QueryArg
    pub fn fromValue(value: anytype) QueryArg {
        // comptime 类型分析和转换
    }
};
```

#### 2. WHERE 子句相关类型
```zig
pub const WhereClause = struct {
    condition: []const u8,      // WHERE 条件字符串
    args: []const QueryArg,     // 绑定参数
    operator: WhereOperator,    // AND/OR 运算符
};

pub const WhereOperator = enum {
    and_op,
    or_op,
};
```

#### 3. JOIN 子句相关类型
```zig
pub const JoinClause = struct {
    join_type: JoinType,
    table: []const u8,
    condition: []const u8,
};

pub const JoinType = enum {
    inner,
    left,
    right,
    full,
    cross,
};
```

#### 4. ORDER BY 子句相关类型
```zig
pub const OrderByClause = struct {
    column: []const u8,
    direction: OrderDirection,
};

pub const OrderDirection = enum {
    asc,
    desc,
};
```

#### 5. HAVING 子句相关类型
```zig
pub const HavingClause = struct {
    condition: []const u8,
    args: []const QueryArg,
};
```

#### 6. 列类型枚举
```zig
pub const ColumnType = enum {
    // 整数类型
    integer,
    bigint,
    smallint,

    // 布尔类型
    boolean,

    // 文本类型
    text,
    varchar,
    char,

    // 浮点类型
    real,
    double_precision,
    numeric,

    // 日期时间类型
    date,
    time,
    timestamp,
    timestamptz,

    // JSON 类型
    json,
    jsonb,

    // 其他类型
    uuid,
    bytea,
};
```

### 实现指南

1. **QueryArg.fromValue() 实现**
   ```zig
   pub fn fromValue(value: anytype) QueryArg {
       const T = @TypeOf(value);
       const type_info = @typeInfo(T);

       return switch (type_info) {
           .Int => |int_info| {
               if (int_info.signedness == .signed) {
                   return .{ .int = @intCast(value) };
               } else {
                   return .{ .uint = @intCast(value) };
               }
           },
           .Float => .{ .float = @floatCast(value) },
           .Bool => .{ .bool = value },
           .Pointer => |ptr_info| {
               if (ptr_info.size == .Slice and ptr_info.child == u8) {
                   return .{ .string = value };
               }
               @compileError("Unsupported pointer type");
           },
           .Null => .{ .null_val = {} },
           .Optional => {
               if (value) |v| {
                   return fromValue(v);
               } else {
                   return .{ .null_val = {} };
               }
           },
           else => @compileError("Unsupported type: " ++ @typeName(T)),
       };
   }
   ```

2. **类型安全使用示例**
   ```zig
   const arg1 = QueryArg.fromValue(42);        // int
   const arg2 = QueryArg.fromValue(3.14);      // float
   const arg3 = QueryArg.fromValue("hello");   // string
   const arg4 = QueryArg.fromValue(true);      // bool
   const arg5 = QueryArg.fromValue(null);      // null

   const maybe_value: ?i32 = null;
   const arg6 = QueryArg.fromValue(maybe_value); // 自动处理 Optional
   ```

### Testing
- **测试文件位置**: `tests/unit/types_test.zig`
- **测试框架**: Zig 内置测试框架
- **测试策略**:
  - 测试所有支持类型的转换
  - 测试可选类型的处理
  - 测试编译时类型检查
  - 验证不支持类型会产生编译错误

### 技术约束
- **Zig 版本**: 0.15.2+
- **内存管理**: QueryArg 本身不分配内存，字符串类型存储指针
- **类型安全**: 使用 comptime 在编译时检查类型
- **性能要求**: 类型转换应为零开销抽象 (编译时完成)

### 依赖项
- `src/error.zig`: 用于类型转换错误定义

## Code Examples

### 类型定义骨架
```zig
// src/types.zig
const std = @import("std");
const Error = @import("error.zig").Error;

/// 查询参数联合类型
///
/// 支持所有常见的 SQL 参数类型，包括：
/// - 整数 (i64, u64)
/// - 浮点数 (f64)
/// - 布尔值 (bool)
/// - 字符串 ([]const u8)
/// - 字节数组 ([]const u8)
/// - NULL 值
pub const QueryArg = union(enum) {
    int: i64,
    uint: u64,
    float: f64,
    bool: bool,
    string: []const u8,
    bytes: []const u8,
    null_val: void,

    /// 从任意类型值创建 QueryArg (编译时类型检查)
    pub fn fromValue(value: anytype) QueryArg {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        return switch (type_info) {
            .Int => |int_info| {
                if (int_info.signedness == .signed) {
                    return .{ .int = @intCast(value) };
                } else {
                    return .{ .uint = @intCast(value) };
                }
            },
            // TODO: 实现其他类型转换...
            else => @compileError("Unsupported type: " ++ @typeName(T)),
        };
    }
};

/// WHERE 子句
pub const WhereClause = struct {
    condition: []const u8,
    args: []const QueryArg,
    operator: WhereOperator,
};

/// WHERE 运算符
pub const WhereOperator = enum {
    and_op,
    or_op,
};

// TODO: 实现其他类型定义...

test "QueryArg.fromValue with different types" {
    const arg_int = QueryArg.fromValue(42);
    try std.testing.expect(arg_int == .int);
    try std.testing.expectEqual(@as(i64, 42), arg_int.int);

    // TODO: 添加更多测试...
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
