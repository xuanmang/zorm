# Story 001: 实现错误定义系统

## Status
Draft

## Story
**As a** ZORM 开发者,
**I want** 一个完整的错误定义系统,
**so that** 所有 ORM 操作都能返回类型安全、语义清晰的错误类型，确保编译时强制错误处理

## Acceptance Criteria
1. 定义完整的 ZORM 错误集 (Error Set)
2. 错误类型覆盖连接、查询、结果、事务、内存等所有场景
3. 错误定义符合 Zig 0.15.2+ 的错误联合类型 (!T) 规范
4. 提供清晰的错误文档和使用示例
5. 所有错误类型都有明确的语义和使用场景

## Tasks / Subtasks
- [ ] 创建 src/error.zig 文件 (AC: 1)
  - [ ] 定义连接相关错误 (ConnectionFailed, ConnectionClosed, ConnectionPoolExhausted, ConnectionTimeout)
  - [ ] 定义查询相关错误 (QueryFailed, InvalidSQL, InvalidParameter, ParameterCountMismatch)
  - [ ] 定义结果相关错误 (NoRows, TooManyRows, ColumnNotFound, TypeMismatch, NullValue)
  - [ ] 定义事务相关错误 (TransactionAlreadyStarted, NoActiveTransaction, TransactionRollbackFailed, TransactionCommitFailed)
  - [ ] 定义内存相关错误 (OutOfMemory)
  - [ ] 定义方言相关错误 (UnsupportedDialect, UnsupportedFeature)
- [ ] 编写错误类型使用文档 (AC: 4)
  - [ ] 为每个错误类型添加文档注释
  - [ ] 说明错误的触发条件和使用场景
- [ ] 编写错误处理示例代码 (AC: 4, 5)
  - [ ] 演示错误传播 (try)
  - [ ] 演示错误捕获 (catch)
  - [ ] 演示错误恢复模式
- [ ] 编写单元测试 (AC: 3, 5)
  - [ ] 测试错误定义的有效性
  - [ ] 测试错误与 !T 联合类型的兼容性
  - [ ] 验证编译器强制错误处理

## Dev Notes

### 架构参考
- **文档位置**: [docs/architecture.md#错误处理策略](architecture.md#错误处理策略) (行 1252-1370)
- **关键设计原则**:
  - 使用 Zig 的错误联合类型 (!T) 实现强制错误处理
  - 所有可能失败的操作必须返回 !T
  - 错误集应涵盖所有可能的失败场景
  - 错误类型应具有清晰的语义

### 文件位置
- **目标文件**: `src/error.zig`
- **依赖文件**: 无（Foundation Layer 基础模块）

### 错误分类与定义

根据架构文档，错误集应包含以下类别：

#### 1. 连接错误 (Connection Errors)
```zig
ConnectionFailed,        // 连接数据库失败
ConnectionClosed,        // 连接已关闭
ConnectionPoolExhausted, // 连接池耗尽
ConnectionTimeout,       // 连接超时
```

#### 2. 查询错误 (Query Errors)
```zig
QueryFailed,            // 查询执行失败
InvalidSQL,             // 无效的 SQL 语句
InvalidParameter,       // 无效的参数
ParameterCountMismatch, // 参数数量不匹配
```

#### 3. 结果错误 (Result Errors)
```zig
NoRows,          // 查询结果为空
TooManyRows,     // 查询返回过多行
ColumnNotFound,  // 列不存在
TypeMismatch,    // 类型不匹配
NullValue,       // 意外的 NULL 值
```

#### 4. 事务错误 (Transaction Errors)
```zig
TransactionAlreadyStarted, // 事务已经开始
NoActiveTransaction,       // 没有活动事务
TransactionRollbackFailed, // 事务回滚失败
TransactionCommitFailed,   // 事务提交失败
```

#### 5. 内存错误 (Memory Errors)
```zig
OutOfMemory, // 内存不足
```

#### 6. 方言错误 (Dialect Errors)
```zig
UnsupportedDialect, // 不支持的数据库方言
UnsupportedFeature, // 不支持的特性
```

### 实现指南

1. **定义错误集**
   ```zig
   pub const Error = error{
       // 连接错误
       ConnectionFailed,
       ConnectionClosed,
       // ... 其他错误
   };
   ```

2. **错误使用示例**
   ```zig
   // 函数返回错误联合类型
   pub fn connect(dsn: []const u8) !Connection {
       return Connection{} catch return error.ConnectionFailed;
   }

   // 错误传播
   const conn = try connect(dsn);

   // 错误捕获和处理
   const conn = connect(dsn) catch |err| {
       std.log.err("Failed to connect: {}", .{err});
       return err;
   };
   ```

3. **错误恢复模式**
   ```zig
   pub fn scanOneOptional(self: *SelectQuery) !?T {
       return self.scanOne() catch |err| switch (err) {
           error.NoRows => return null,
           else => return err,
       };
   }
   ```

### Testing
- **测试文件位置**: `tests/unit/error_test.zig`
- **测试框架**: Zig 内置测试框架 (`zig test`)
- **测试策略**:
  - 验证所有错误类型都能正确定义
  - 测试错误类型与 !T 的兼容性
  - 验证编译器强制错误处理机制
  - 测试错误传播和恢复模式

### 技术约束
- **Zig 版本**: 0.15.2+
- **错误处理模式**: 必须使用 !T 错误联合类型
- **文档要求**: 每个错误类型必须有清晰的文档注释

### 数据库环境
- PostgreSQL 测试环境:
  - Host: 127.0.0.1
  - Port: 5432
  - Username: pguser
  - Password: Pg#123!
  - Database: postgres

## Code Examples

### 错误定义骨架
```zig
// src/error.zig
const std = @import("std");

/// ZORM 错误集
///
/// 该错误集涵盖了 ZORM 所有可能的错误场景，包括：
/// - 连接错误: 数据库连接相关的失败
/// - 查询错误: SQL 查询执行过程中的错误
/// - 结果错误: 查询结果处理中的错误
/// - 事务错误: 事务管理相关的错误
/// - 内存错误: 内存分配失败
/// - 方言错误: 数据库方言不支持的特性
pub const Error = error{
    // ========== 连接错误 ==========

    /// 数据库连接失败
    /// 原因: 网络问题、认证失败、服务器不可达等
    ConnectionFailed,

    /// 连接已关闭
    /// 原因: 尝试在已关闭的连接上执行操作
    ConnectionClosed,

    // TODO: 实现其他错误类型...
};

test "error definition is valid" {
    // 测试错误定义
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
