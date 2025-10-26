# Spec: API Documentation

## ADDED Requirements

### Requirement: Complete API Documentation Coverage

All public APIs MUST include complete documentation comments using Zig's `///` doc comment syntax.

#### Scenario: 核心模块文档完整性

**Given** ZORM 的核心模块（DB, Query Builder, Schema, Transaction）
**When** 开发者查看这些模块的公共 API
**Then** 每个公共函数、结构体、枚举都应有完整的文档注释
**And** 文档注释包含：功能说明、参数描述、返回值说明、可能的错误类型、使用示例

**Verification**:
```bash
# 运行文档生成
zig build docs
# 检查生成的 HTML 文档包含所有公共 API
```

---

### Requirement: Documentation Comment Format Standard

Documentation comments MUST follow a consistent format specification for readability and maintainability.

#### Scenario: 标准文档格式

**Given** 任意公共 API 函数
**When** 查看其文档注释
**Then** 注释应包含以下结构：
- 功能简介（一句话）
- 详细说明（可选，复杂功能需要）
- 参数列表（每个参数单独说明）
- 返回值说明
- 错误类型列表
- 至少一个代码示例

**Example**:
```zig
/// 创建一个新的 SELECT 查询构建器
///
/// 该函数初始化一个类型安全的查询构建器，用于构建 SELECT 语句。
/// 查询构建器支持链式调用，可以添加 WHERE、ORDER BY、LIMIT 等子句。
///
/// ## Parameters
/// - `allocator`: 用于内存分配的 Allocator
/// - `T`: 目标结构体类型，查询结果将映射到此类型
///
/// ## Returns
/// 返回初始化的 SelectQuery 实例
///
/// ## Errors
/// - `error.OutOfMemory`: 内存分配失败
///
/// ## Example
/// ```zig
/// var query = try db.newSelect(User);
/// defer query.deinit();
/// try query.where("age > ?", .{18}).scan(&users);
/// ```
pub fn newSelect(allocator: Allocator, comptime T: type) !SelectQuery(T) {
    // ...
}
```

---

### Requirement: Error Type Documentation

All possible error return types MUST be explicitly documented.

#### Scenario: 错误类型说明

**Given** 一个返回 `!T` 的公共函数
**When** 开发者查看函数文档
**Then** 文档应列出所有可能的错误类型
**And** 每个错误类型都应说明触发条件

**Example**:
```zig
/// ## Errors
/// - `error.OutOfMemory`: 内存分配失败
/// - `error.InvalidQuery`: SQL 语法错误
/// - `error.ConnectionClosed`: 数据库连接已关闭
/// - `error.Timeout`: 查询执行超时
```

---

### Requirement: Code Example Completeness

Code examples in documentation MUST be complete and runnable code snippets.

#### Scenario: 可运行的示例代码

**Given** 文档注释中的代码示例
**When** 开发者复制示例代码
**Then** 示例应包含必要的导入、变量声明、资源清理
**And** 示例代码应能够直接编译运行（或仅需最小修改）

**Example**:
```zig
/// ## Example
/// ```zig
/// const std = @import("std");
/// const zorm = @import("zorm");
///
/// var gpa = std.heap.GeneralPurposeAllocator(.{}){};
/// defer _ = gpa.deinit();
/// const allocator = gpa.allocator();
///
/// var db = try zorm.DB.open(allocator, .{
///     .dialect = .postgresql,
///     .dsn = "postgres://localhost/test",
/// });
/// defer db.close();
///
/// var query = try db.newSelect(User);
/// defer query.deinit();
/// const users = try query.scan();
/// defer allocator.free(users);
/// ```
```

---

### Requirement: Comptime Feature Documentation

Comptime parameters and functionality MUST clearly explain their purpose and constraints.

#### Scenario: Comptime 参数说明

**Given** 使用 `comptime` 参数的函数
**When** 开发者查看文档
**Then** 文档应说明 comptime 参数的用途
**And** 说明编译时的类型要求和约束

**Example**:
```zig
/// ## Parameters
/// - `comptime T`: 目标结构体类型。必须满足以下条件：
///   - 所有字段类型必须可映射到 SQL 类型
///   - 可选包含 `pub const table_name` 指定表名
///   - 字段名将自动转换为 snake_case 作为列名
```

---

### Requirement: Type Mapping Documentation

Schema type mapping relationships MUST be clearly explained in documentation.

#### Scenario: Zig 到 SQL 类型映射

**Given** 使用 ZORM Schema 功能
**When** 开发者需要了解类型映射规则
**Then** 文档应提供完整的类型映射表
**And** 说明每种 Zig 类型对应的 SQL 类型

**Example**:
```zig
/// ## 类型映射
///
/// | Zig Type | PostgreSQL Type | MySQL Type | SQLite Type |
/// |----------|----------------|------------|-------------|
/// | i8, i16, i32 | SMALLINT | SMALLINT | INTEGER |
/// | i64 | BIGINT | BIGINT | INTEGER |
/// | bool | BOOLEAN | TINYINT(1) | INTEGER |
/// | []const u8 | TEXT | TEXT | TEXT |
/// | ?T | T (NULL allowed) | T (NULL allowed) | T (NULL allowed) |
```

---

### Requirement: Documentation Generation Configuration

build.zig MUST be correctly configured for documentation generation to ensure all modules are included.

#### Scenario: 文档生成测试

**Given** 完整的 ZORM 代码库
**When** 运行 `zig build docs`
**Then** 应成功生成 HTML 文档到 `zig-out/docs/`
**And** 文档包含所有公共模块和 API
**And** 文档链接正确，无死链

**Verification**:
```bash
zig build docs
# 检查生成的文档
ls zig-out/docs/
# 验证核心模块文档存在
grep -r "newSelect" zig-out/docs/
```
