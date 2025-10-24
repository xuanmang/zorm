# Proposal: Complete DELETE Query Builder API

## Overview

完成 PRD Story 2.3: Type-Safe DELETE Query Builder 的实现验证和测试补充。DeleteQuery 核心功能已实现，本提案专注于：

1. 补充 whereIn/whereNotIn 批量删除测试用例
2. 验证所有 AC 要求已满足
3. 确保测试覆盖率达标
4. 创建规范化的 API 文档

## Motivation

根据 PRD Story 2.3，DELETE Query Builder 需要提供：

- 类型安全的 DELETE 查询构建
- 强制 WHERE 条件（防止误删）
- 支持 whereIn/whereNotIn 批量删除
- 支持 RETURNING 子句
- 链式 API 调用
- 与 UPDATE Builder 一致的 API 风格

当前实现已完成核心功能，但缺少 whereIn/whereNotIn 的专门测试用例。

## Impact

### User Impact

- 开发者获得完整的 DELETE Query Builder 功能
- 通过测试保障功能稳定性
- 清晰的 API 文档降低学习成本

### Technical Impact

- 测试覆盖率提升
- 验证批量删除场景
- 确保与其他 Query Builder（SELECT/INSERT/UPDATE）API 一致性

## Success Criteria

1. ✅ 所有 AC（AC2.3.1 - AC2.3.8）通过验证
2. ✅ whereIn/whereNotIn 测试用例通过
3. ✅ 测试覆盖率 ≥ 80%
4. ✅ 文档完整且准确
5. ✅ 与 Bun ORM API 风格保持一致

## Related Work

- Story 2.1: Type-Safe UPDATE Query Builder（已实现）
- Story 2.2: Bulk UPDATE Support（已实现）
- Epic 2: Complete CRUD & Transaction Support

## Timeline

- 测试补充：1 小时
- 验证和修复：1 小时
- 文档完善：30 分钟
