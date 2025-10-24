# Complete Transaction Management API

## Overview
完成 ZORM 事务管理 API 的实现和正式化，包括事务生命周期管理（BEGIN/COMMIT/ROLLBACK）和事务隔离级别配置功能。

## Motivation
根据 PRD Epic 2 (Complete CRUD & Transaction Support) 的要求，ZORM 需要提供完整的事务管理能力以支持复杂业务逻辑的原子性操作和数据一致性保证。本提案将 Story 2.4 (Transaction Management API) 和 Story 2.5 (Transaction Isolation Levels) 的现有实现正式化为 OpenSpec 规格说明。

## Goals
1. 正式化事务管理 API (Story 2.4)，包括 `beginTx()`, `commit()`, `rollback()` 和自动回滚机制
2. 正式化事务隔离级别 API (Story 2.5)，支持 PostgreSQL 四个标准隔离级别
3. 确保嵌套事务检测和禁止
4. 为事务管理器提供完整的查询构建器方法支持
5. 确保所有 AC (Acceptance Criteria) 都有对应的测试用例

## Scope
### In Scope
- ✅ 事务生命周期管理 API（beginTx, commit, rollback, deinit）
- ✅ 事务隔离级别配置（read_uncommitted, read_committed, repeatable_read, serializable）
- ✅ 嵌套事务检测和错误处理
- ✅ 事务管理器查询构建器方法（newSelect, newInsert, newUpdate, newDelete, newRaw）
- ✅ 自动回滚机制（deinit 和 errdefer 模式）
- ✅ 事务状态跟踪（is_active, is_committed, is_rolled_back）

### Out of Scope
- ❌ 保存点（Savepoint）支持（已在 transaction.zig 中实现，但不是本次提案的重点）
- ❌ 分布式事务（Two-Phase Commit）
- ❌ 事务钩子系统
- ❌ 事务性能监控和调优

## Dependencies
### Depends On
- [x] `db-instance-api` - DB 实例初始化和连接管理
- [x] `query-context-api` - 查询执行上下文
- [x] `error-type-aliases` - 错误类型定义
- [x] `insert-query-api` - INSERT 查询构建器
- [x] `update-query-api` - UPDATE 查询构建器
- [x] `select-query-api` - SELECT 查询构建器

### Enables
- [ ] Story 2.6: Raw SQL Query Support（事务中执行 Raw SQL）
- [ ] Epic 4: Query Hook System（事务钩子）
- [ ] Future: Savepoint 嵌套事务支持

## Implementation Status
当前实现已完成：
- ✅ `src/core/tx_manager.zig` - 完整的 TxManager 实现
- ✅ `src/core/types.zig` - IsolationLevel 枚举定义
- ✅ `src/core/db.zig` - DB.beginTx() 方法

待完成任务：
- ⏳ 增强集成测试覆盖（事务提交/回滚场景）
- ⏳ 添加隔离级别测试用例
- ⏳ 完善错误处理测试（嵌套事务、重复提交等）

## Related Documents
- PRD: Story 2.4 (Transaction Management API)
- PRD: Story 2.5 (Transaction Isolation Levels)
- 代码: `src/core/tx_manager.zig`
- 代码: `src/core/types.zig` (IsolationLevel 定义)
- 代码: `src/core/db.zig` (DB.beginTx 方法)
