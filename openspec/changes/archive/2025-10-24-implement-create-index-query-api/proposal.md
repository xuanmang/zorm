# Implement CREATE INDEX Query Builder API

## Why

PRD Story 3.4 要求提供一个类型安全的 CREATE INDEX 查询构建器，使开发者能够通过链式 API 为表创建索引，优化查询性能。当前 CreateIndexQuery 已实现了基本功能，但缺少表达式索引支持和完整的单元测试/集成测试覆盖。

## What Changes

- **完善 CreateIndexQuery API**：添加表达式索引支持（如 `LOWER(email)`）
- **完善单元测试**：为所有 API 方法添加单元测试，确保覆盖率达到 80%+
- **添加集成测试**：针对真实 PostgreSQL 数据库验证索引创建功能
- **完善文档**：补充 API 文档和使用示例

## Impact

- **Affected specs**:
  - `create-index-query-api` (新增 spec)
- **Affected code**:
  - `src/query/query.zig` (CreateIndexQuery 结构体)
  - `src/core/db.zig` (newCreateIndex 方法)
  - `tests/` (新增单元测试和集成测试)
  - `examples/` (新增示例代码)

## Implementation Status

**Current State**:
- ✅ 基本 API 结构 (AC3.4.1)
- ✅ `.index(name)` 方法 (AC3.4.2)
- ✅ `.column(col)` 方法支持复合索引 (AC3.4.3)
- ✅ `.unique()` 方法 (AC3.4.4)
- ✅ `.ifNotExists()` 方法 (AC3.4.5)
- ✅ `.where()` 方法支持部分索引 (AC3.4.7)
- ✅ `.exec()` 方法 (AC3.4.8)
- ❌ 表达式索引支持 (AC3.4.6) - **缺失**
- ❌ 完整的单元测试覆盖
- ❌ 集成测试覆盖

**What Needs to be Done**:
1. 支持表达式索引（当前 `.column()` 方法已支持传入表达式，需要验证和文档化）
2. 添加完整的单元测试（覆盖所有场景）
3. 添加集成测试（真实 PostgreSQL 验证）
4. 完善文档和示例
