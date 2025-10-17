# Story 010: 实现事务管理

## Status
Approved

## Story
**As a** ZORM 开发者,
**I want** 完整的事务管理功能,
**so that** 能够安全执行数据库事务,支持保存点和自动回滚

## Acceptance Criteria
1. 实现 Transaction(comptime dialect) 泛型结构体
2. 实现 begin/commit/rollback 方法
3. 支持保存点 (savepoint/rollbackTo/releaseSavepoint)
4. 实现 withTransaction 自动管理辅助函数
5. 使用 defer/errdefer 确保事务清理
6. 编写集成测试验证事务 ACID 特性

## Tasks / Subtasks
- [ ] 创建 src/core/transaction.zig
- [ ] 实现事务生命周期管理
- [ ] 实现保存点支持
- [ ] 编写事务测试

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md
参考 [docs/architecture.md#TransactionManager](architecture.md) (行 790-917)

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
