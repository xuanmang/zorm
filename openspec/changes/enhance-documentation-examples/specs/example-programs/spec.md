# Spec: Example Programs

## ADDED Requirements

### Requirement: Basic CRUD Operations Example

A complete basic CRUD operations example MUST be provided, demonstrating basic usage of SELECT, INSERT, UPDATE, and DELETE.

#### Scenario: basic.zig 示例程序

**Given** 开发者需要快速了解 ZORM 的基本用法
**When** 查看 `examples/basic.zig`
**Then** 示例应包含以下操作：
- 数据库连接创建和关闭
- INSERT 单行数据
- SELECT 查询多行数据
- UPDATE 更新数据
- DELETE 删除数据
- 基本的错误处理

**And** 示例应使用清晰的注释说明每个步骤
**And** 可以通过 `zig build run-example-basic` 运行

**Verification**:
```bash
zig build run-example-basic
# 应成功执行所有 CRUD 操作
```

---

### Requirement: Transaction Management Example

An example demonstrating transaction begin, commit, rollback, and errdefer automatic rollback MUST be provided.

#### Scenario: transaction.zig 示例程序

**Given** 开发者需要实现原子性操作
**When** 查看 `examples/transaction.zig`
**Then** 示例应包含：
- 事务的创建（beginTx）
- 在事务中执行多个操作
- 事务提交（commit）
- 错误时自动回滚（errdefer）
- 手动回滚（rollback）
- 不同隔离级别的设置

**Verification**:
```bash
zig build run-example-transaction
# 验证事务的原子性
```

---

### Requirement: Schema Management Example

An example demonstrating table creation, modification, deletion, and index management MUST be provided.

#### Scenario: schema.zig 示例程序（增强现有）

**Given** 开发者需要管理数据库 Schema
**When** 查看 `examples/schema.zig`
**Then** 示例应包含：
- CREATE TABLE（基本和高级特性）
- DROP TABLE
- CREATE INDEX（普通索引、唯一索引、复合索引、部分索引）
- DROP INDEX
- Schema 字段自定义（约束、默认值、CHECK）
- 从 Zig 结构体自动生成表

**Verification**:
```bash
zig build run-example-schema
# 验证表和索引的创建和删除
```

---

### Requirement: JOIN Query Example

An example demonstrating multi-table join queries MUST be provided.

#### Scenario: join.zig 示例程序

**Given** 开发者需要执行关联查询
**When** 查看 `examples/join.zig`
**Then** 示例应包含：
- INNER JOIN
- LEFT JOIN
- RIGHT JOIN
- 多个 JOIN 的组合
- 带条件的 JOIN
- JOIN 结果映射到自定义结构体

**Verification**:
```bash
zig build run-example-join
# 验证关联查询结果的正确性
```

---

### Requirement: UPSERT Operation Example

An example demonstrating PostgreSQL ON CONFLICT usage MUST be provided.

#### Scenario: upsert.zig 示例程序

**Given** 开发者需要处理唯一约束冲突
**When** 查看 `examples/upsert.zig`
**Then** 示例应包含：
- ON CONFLICT DO NOTHING
- ON CONFLICT DO UPDATE
- 使用 EXCLUDED 关键字
- 部分唯一约束冲突（WHERE 条件）
- 与 RETURNING 结合使用

**Verification**:
```bash
zig build run-example-upsert
# 验证 upsert 行为的正确性
```

---

### Requirement: Query Hook Example

An example demonstrating query hook system usage, including logging and performance tracking, MUST be provided.

#### Scenario: hooks.zig 示例程序

**Given** 开发者需要实现查询监控
**When** 查看 `examples/hooks.zig`
**Then** 示例应包含：
- 注册内置的 LoggingHook
- 注册内置的 PerformanceHook
- 自定义钩子的实现
- 钩子链的使用
- 获取性能统计信息

**Verification**:
```bash
zig build run-example-hooks
# 验证钩子被正确触发，日志输出
```

---

### Requirement: Example Code Quality Standards

All example code MUST follow the project's coding standards and best practices.

#### Scenario: 代码质量检查

**Given** 任意示例程序
**When** 进行代码审查
**Then** 示例应满足：
- 使用 `std.testing.allocator` 或明确的内存管理
- 所有资源使用 `defer` 进行清理
- 适当的错误处理（不使用 `catch unreachable` 除非绝对安全）
- 清晰的注释和说明
- 符合 `zig fmt` 格式规范

**Verification**:
```bash
zig fmt --check examples/*.zig
# 所有示例应通过格式检查
```

---

### Requirement: Example Test Validation

All example programs MUST be compilable and validated through automated tests.

#### Scenario: 示例编译测试

**Given** 所有示例程序
**When** 运行构建系统
**Then** 每个示例都应能够成功编译
**And** build.zig 应提供运行每个示例的步骤

**Verification**:
```bash
# 编译所有示例
zig build examples
# 运行所有示例测试
zig build test-examples
```

---

### Requirement: Example Documentation Description

Each example program MUST include clear documentation at the top.

#### Scenario: 示例头部注释

**Given** 任意示例程序
**When** 打开文件查看
**Then** 文件顶部应包含：
- 示例的目的和适用场景
- 前置条件（如是否需要数据库）
- 运行方法
- 预期输出

**Example**:
```zig
//! # Basic CRUD Operations Example
//!
//! 本示例展示 ZORM 的基础 CRUD 操作用法。
//!
//! ## 前置条件
//! - PostgreSQL 数据库运行在 localhost:5432
//! - 数据库名称：test
//!
//! ## 运行方法
//! ```bash
//! zig build run-example-basic
//! ```
//!
//! ## 预期输出
//! - 成功插入、查询、更新、删除用户数据
//! - 打印操作结果和统计信息
```

---

### Requirement: Example Database Configuration

Examples MUST support flexible database configuration to avoid hardcoding.

#### Scenario: 环境变量配置

**Given** 示例程序需要连接数据库
**When** 运行示例
**Then** 应支持通过环境变量配置数据库连接
**And** 提供合理的默认值
**And** 文档说明配置方法

**Example**:
```zig
const dsn = std.process.getEnvVarOwned(
    allocator,
    "DATABASE_URL"
) catch "postgres://localhost/test";
defer allocator.free(dsn);
```
