# Complete DROP INDEX Query Builder API

## Why

PRD Story 3.5 要求提供一个类型安全的 DROP INDEX 查询构建器,使开发者能够安全地删除数据库索引。当前 DropIndexQuery 已有基础实现,但存在以下问题:

1. **API 不一致**: `src/schema/schema.zig` 和 `src/query/query.zig` 中的实现不一致
2. **缺少 CASCADE/RESTRICT 支持**: `src/query/query.zig` 版本缺少 `cascade()` 和 `restrict()` 方法
3. **缺少测试覆盖**: 没有专门的 DROP INDEX 单元测试和集成测试
4. **文档不完整**: API 文档和使用示例不足

根据 PostgreSQL 文档,DROP INDEX 完整语法为:
```sql
DROP INDEX [ CONCURRENTLY ] [ IF EXISTS ] name [, ...] [ CASCADE | RESTRICT ]
```

## What Changes

- **统一 API 实现**: 确保所有 DropIndexQuery 实现遵循相同的 API 设计
- **添加 CASCADE/RESTRICT 支持**: 补充缺失的 `cascade()` 和 `restrict()` 方法
- **实现互斥逻辑**: CASCADE 和 RESTRICT 不能同时存在,后调用的覆盖前面的
- **完善单元测试**: 为所有 API 方法添加单元测试,确保覆盖率达到 80%+
- **添加集成测试**: 针对真实 PostgreSQL 数据库验证 DROP INDEX 功能
- **完善文档**: 补充 API 文档和使用示例,说明 CASCADE/RESTRICT 的应用场景

## Impact

- **Affected specs**:
  - `drop-index-query-api` (新增 spec)
- **Affected code**:
  - `src/query/query.zig` (DropIndexQuery 结构体,添加 cascade/restrict 方法)
  - `src/schema/schema.zig` (统一 API 设计)
  - `src/core/db.zig` (newDropIndex 方法)
  - `tests/` (新增 drop_index_test.zig)
- **Related specs**:
  - `create-index-query-api` (对称 API)
  - `drop-table-query-api` (相似的 CASCADE/RESTRICT 模式)

## Implementation Status

**Current State** (基于代码分析):
- ✅ 基本 API 结构 (AC3.5.1)
- ✅ `.index(name)` 方法 (AC3.5.2) - 仅 `src/schema/schema.zig` 版本
- ✅ `.ifExists()` 方法 (AC3.5.3)
- ⚠️  `.cascade()` 方法 (AC3.5.4) - 仅 `src/schema/schema.zig` 版本有实现
- ❌ `.restrict()` 方法 - **缺失**
- ❌ CASCADE 和 RESTRICT 互斥逻辑 - **缺失**
- ✅ `.exec()` 和 `.build()` 方法 (AC3.5.5)
- ❌ 完整的单元测试覆盖 - **缺失**
- ❌ 集成测试覆盖 - **缺失**

**What Needs to be Done**:
1. 统一 `src/query/query.zig` 和 `src/schema/schema.zig` 中的 DropIndexQuery 实现
2. 添加 `restrict()` 方法到所有版本
3. 实现 CASCADE 和 RESTRICT 互斥逻辑(参考 DROP TABLE 实现)
4. 添加完整的单元测试(覆盖所有方法和场景)
5. 添加集成测试(真实 PostgreSQL 验证)
6. 完善文档和示例(包括 CASCADE/RESTRICT 使用场景说明)
