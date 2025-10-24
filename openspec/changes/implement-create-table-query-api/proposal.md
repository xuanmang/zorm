# Proposal: Implement CREATE TABLE Query Builder API

## Why

完成 PRD Epic 3 Story 3.1，为 ZORM 提供类型安全的 Schema 管理能力。当前用户必须手写 DDL 或使用底层 Table API，缺乏从 Zig 结构体自动生成 CREATE TABLE 的便捷方式。本提案通过 Query Builder API 简化 Schema 管理，利用 Zig 的 comptime 特性实现零运行时开销的类型映射，显著提升开发效率。

## Overview

完成 PRD Epic 3 Story 3.1 中定义的 CREATE TABLE Query Builder 基础功能。该功能允许开发者通过简洁的 API 从 Zig 结构体自动生成 PostgreSQL CREATE TABLE 语句，无需手写 DDL。

## Context

当前 ZORM 已实现完整的 CRUD Query Builder（SELECT、INSERT、UPDATE、DELETE）以及事务管理 API。现在需要进入 Epic 3: Schema Management & Type System 阶段，首先实现 CREATE TABLE Query Builder 的基础功能。

### 现有实现

项目中已存在以下相关代码：

1. **src/schema/table.zig**: 提供底层 Table 和 Column 结构，支持手动构建表定义并生成 SQL
2. **src/schema/reflection.zig**: 提供 comptime 类型反射功能，可从 Zig 结构体推断表名和列定义
3. **src/query/query.zig**: 已实现 `CreateTableQuery` 类型，包含：
   - `init()`: 自动从结构体生成列
   - `initEmpty()`: 手动添加列
   - `ifNotExists()`: 添加 IF NOT EXISTS 子句
   - `column()`: 手动添加列
   - `exec()`: 执行 DDL

### 差距分析

根据 PRD Story 3.1 的 8 个 Acceptance Criteria（AC3.1.1 ~ AC3.1.8）：

**已实现的功能**：
- ✅ AC3.1.1: 提供 `db.newCreateTable(T)` API
- ✅ AC3.1.6: 提供 `.ifNotExists()` 方法
- ✅ AC3.1.7: 提供 `.exec()` 方法

**需要补充/验证的功能**：
- ⚠️ AC3.1.2: 自动从 Zig 结构体生成列定义（已实现但需验证完整性）
- ⚠️ AC3.1.3: 支持完整的 Zig 类型到 PostgreSQL 类型映射（需验证所有类型）
- ⚠️ AC3.1.4: 自动检测主键字段（需验证检测逻辑）
- ⚠️ AC3.1.5: 可选类型（`?T`）自动省略 NOT NULL 约束（需验证）
- ❌ AC3.1.8: 缺少完整的测试覆盖（当前只有 4 个基础测试）

## Goals

1. **验证现有实现**：确保所有类型映射、主键检测、可选类型处理符合 PRD 规范
2. **补充测试覆盖**：为所有 AC 编写完整的单元测试和集成测试
3. **文档完善**：确保 API 文档清晰、示例代码可运行
4. **示例程序**：提供 `examples/schema.zig` 演示完整使用场景

## Scope

### In Scope

- 验证和测试 Zig 类型到 PostgreSQL 类型的映射（AC3.1.3 中列出的所有类型）
- 验证和测试主键自动检测（字段名为 `id` 或带有 schema 配置）
- 验证和测试可选类型（`?T`）的 NULL 约束处理
- 编写覆盖所有 AC 的单元测试
- 编写集成测试验证完整的 CREATE TABLE 工作流
- 完善 API 文档和代码注释
- 创建 `examples/schema.zig` 示例程序

### Out of Scope

- Story 3.2（Schema Field Customization with Struct Tags）- 将在后续提案中实现
- Story 3.3（DROP TABLE）- 已实现，不在本提案范围
- Story 3.4/3.5（CREATE INDEX / DROP INDEX）- 已实现，不在本提案范围
- Story 3.6（PostgreSQL Specific Types）- 将在后续提案中实现

## Design Overview

### 类型映射验证

需要验证以下 Zig 类型到 PostgreSQL 类型的映射（AC3.1.3）：

| Zig Type | PostgreSQL Type | 说明 |
|----------|----------------|------|
| `i8, i16, i32` | SMALLINT | 小整数 |
| `i64` | BIGINT | 大整数 |
| `u8, u16, u32` | INTEGER | 无符号整数 |
| `u64` | BIGINT | 大无符号整数 |
| `f32` | REAL | 单精度浮点 |
| `f64` | DOUBLE PRECISION | 双精度浮点 |
| `bool` | BOOLEAN | 布尔值 |
| `[]const u8` | TEXT | 文本字符串 |
| `?T` | 对应类型 + NULL 允许 | 可选类型 |

### 主键检测逻辑

验证以下主键检测逻辑（AC3.1.4）：
- 字段名为 `id` 自动设置为主键
- 支持通过 `pub const schema` 配置显式指定主键
- 主键字段自动添加 `NOT NULL` 约束

### 测试策略

1. **类型映射测试**：为每种 Zig 类型编写测试，验证生成的 SQL 类型正确
2. **主键检测测试**：测试 `id` 字段自动检测和手动配置
3. **可选类型测试**：测试 `?T` 字段生成的 SQL 省略 NOT NULL
4. **完整工作流测试**：端到端测试从结构体到 CREATE TABLE SQL
5. **示例代码测试**：确保 PRD 中的所有示例代码可编译并通过测试

## Capabilities

### create-table-api

完整实现 CREATE TABLE Query Builder API，包括：
- 自动类型映射
- 主键检测
- 可选类型处理
- IF NOT EXISTS 支持
- 完整测试覆盖

## Tasks

详见 `tasks.md`

## Dependencies

无外部依赖。本提案基于现有代码进行验证和测试补充。

## Success Criteria

1. ✅ 所有 Zig 类型映射测试通过
2. ✅ 主键检测逻辑测试通过
3. ✅ 可选类型处理测试通过
4. ✅ PRD 中所有示例代码可编译并通过测试
5. ✅ `examples/schema.zig` 示例程序可运行
6. ✅ 单元测试覆盖率达到 80%+
7. ✅ `openspec validate --strict` 通过

## Timeline

预计 1-2 天完成：
- Day 1: 编写测试、验证实现、补充文档
- Day 2: 创建示例程序、修复问题、通过验证

## Risks

1. **类型映射不完整**：可能存在某些 Zig 类型未正确映射
   - 缓解措施：编写覆盖所有类型的测试
2. **主键检测逻辑不符合预期**：可能需要调整检测规则
   - 缓解措施：编写详细的测试用例验证各种场景

## References

- PRD: docs/prd.md - Epic 3, Story 3.1
- 现有实现: src/query/query.zig (`CreateTableQuery`)
- 类型反射: src/schema/reflection.zig
- 底层表定义: src/schema/table.zig
