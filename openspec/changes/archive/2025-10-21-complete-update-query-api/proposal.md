# Proposal: Complete UPDATE Query Builder API

## Change ID
`complete-update-query-api`

## Problem Statement

根据 PRD Epic 2 (Complete CRUD & Transaction Support) 的要求，ZORM 需要提供完整的 UPDATE 查询构建器实现，以支持 Story 2.1 (Type-Safe UPDATE Query Builder) 和 Story 2.2 (Bulk UPDATE Support)。

**当前状态**:
- ✅ UpdateQuery 基本框架已实现 (src/query/query.zig:1195)
- ✅ set() 方法已实现
- ✅ where() 方法已实现
- ✅ setReturning() 和 exec/execReturning 方法已实现

**缺失功能**:
- ❌ whereIn() 方法 - 批量匹配支持 (AC2.2.2)
- ❌ 子查询支持 (AC2.2.3)
- ❌ 完整的测试覆盖和文档
- ❌ 正式的 OpenSpec 规范定义

## Proposed Solution

通过创建两个规范来正式化 UPDATE Query Builder API:

1. **update-query-api**: 定义核心 UPDATE 查询构建器需求 (Story 2.1)
   - newUpdate() 工厂方法
   - set() 方法 - 设置列值
   - where() 方法 - 添加条件
   - exec() 方法 - 执行更新
   - setReturning() + execReturning() - RETURNING 子句支持
   - 链式调用支持

2. **bulk-update-api**: 定义批量更新需求 (Story 2.2)
   - whereIn() 方法 - 批量匹配
   - whereNotIn() 方法
   - 子查询支持 (whereIn 接受 SelectQuery)
   - 批量 RETURNING 支持

## Impact Analysis

### Affected Systems
- **Query Builder** (src/query/query.zig): 添加 whereIn/whereNotIn 方法
- **Tests**: 添加完整的单元测试和集成测试
- **Documentation**: 补充 API 文档和使用示例

### Breaking Changes
- 无破坏性变更 - 仅添加新功能

### Dependencies
- 依赖现有的 SelectQuery 实现 (用于子查询支持)
- 依赖现有的 whereIn 实现模式 (参考 DELETE Query Builder)

## Success Criteria

根据 PRD 定义的验收标准:

**Story 2.1 验收标准**:
- ✅ AC2.1.1: db.newUpdate(T) API 已实现
- ✅ AC2.1.2: set(assignments) 方法已实现
- ✅ AC2.1.3: where(condition, args) 方法已实现
- ✅ AC2.1.4: exec() 方法返回 UpdateResult 已实现
- ✅ AC2.1.5: setReturning(cols) 方法已实现
- ✅ AC2.1.6: execReturning(dest) 方法已实现
- ✅ AC2.1.7: 链式调用支持已实现

**Story 2.2 验收标准**:
- ✅ AC2.2.1: 复杂 WHERE 条件已支持
- ❌ AC2.2.2: whereIn(column, values) 方法需要实现
- ❌ AC2.2.3: 子查询支持需要实现
- ✅ AC2.2.4: RETURNING 批量返回已支持

**OpenSpec 要求**:
- 所有需求必须有至少一个 Scenario
- 通过 `openspec validate --strict` 验证
- 所有测试通过（单元测试 + 集成测试）

## Timeline Estimate

- Spec 编写: 1 小时
- whereIn/whereNotIn 实现: 2 小时
- 子查询支持实现: 2 小时
- 测试编写: 3 小时
- 文档完善: 1 小时

**总计**: 约 1 个工作日

## Related Changes

- **前置依赖**: select-query-api (已完成) - 子查询需要 SelectQuery
- **后续依赖**: transaction-api (Epic 2 Story 2.4) - UPDATE 在事务中执行
- **相关规范**: delete-query-api - whereIn 实现模式参考
