# Implement Raw SQL Query API

## Why
查询构建器 API (SELECT/INSERT/UPDATE/DELETE Query) 虽然提供了类型安全的查询构建,但无法覆盖 PostgreSQL 的所有高级功能,如:
- 窗口函数 (RANK, ROW_NUMBER, LAG, LEAD等)
- 公共表表达式 (CTE) 和递归 CTE
- 全文搜索 (to_tsvector, to_tsquery)
- JSONB 复杂查询
- 多表复杂 JOIN
- 自定义聚合函数

为了支持这些场景同时保持参数绑定的安全性和类型安全的结果映射,ZORM 需要提供 Raw SQL Query API。

## What Changes
本变更将 Story 2.6 (Raw SQL Query Support) 的现有实现正式化为 OpenSpec 规格,并补充完整的单元测试:

1. **规格化 RawQuery API**
   - `DB.newRaw()` 和 `Tx.newRaw()` 创建方法
   - `exec()` 执行 DML 语句
   - `scan()` 扫描查询结果到 ArrayList
   - `scanOne()` 查询单行结果
   - `deinit()` 资源释放

2. **单元测试补充**
   - RawQuery 基本功能测试 (初始化、参数转换、资源管理)
   - 参数绑定安全性测试 (SQL 注入防护)
   - 边界和错误场景测试 (空SQL、NULL值、Unicode等)

3. **集成测试规划**
   - 需要真实数据库环境的测试建议在 `tests/integration/` 中实现

## Overview
完成 ZORM Raw SQL Query API 的正式化规格说明，支持执行任意 SQL 语句并提供类型安全的结果扫描。

## Motivation
根据 PRD Epic 2 (Complete CRUD & Transaction Support) 的要求，ZORM 需要提供 Raw SQL Query API 以处理查询构建器无法覆盖的复杂场景（如窗口函数、CTE、全文搜索等）。本提案将 Story 2.6 (Raw SQL Query Support) 的现有实现正式化为 OpenSpec 规格说明。

## Goals
1. 正式化 Raw SQL Query API (Story 2.6)，包括 `db.newRaw()` 和 `tx.newRaw()` 方法
2. 确保参数绑定安全性（使用 PostgreSQL `$1, $2, ...` 占位符）
3. 支持 DML 执行（exec）和查询结果扫描（scan/scanOne）
4. 为所有功能添加完整的单元测试和集成测试
5. 确保所有 AC (Acceptance Criteria) 都有对应的测试用例

## Scope
### In Scope
- ✅ Raw SQL Query API（newRaw, exec, scan, scanOne, deinit）
- ✅ 参数绑定机制（`$1, $2, ...` 占位符自动处理）
- ✅ DML 执行（INSERT/UPDATE/DELETE）返回 RawResult
- ✅ 查询结果扫描到 ArrayList（scan）
- ✅ 单行结果查询（scanOne）
- ✅ 事务中执行 Raw SQL（tx.newRaw）
- ⏳ 单元测试（RawQuery 各方法的独立测试）
- ⏳ 集成测试（复杂 SQL 场景验证）

### Out of Scope
- ❌ 编译时 SQL 语法验证
- ❌ SQL 查询优化和性能分析
- ❌ SQL 查询构建器（已在其他 specs 中定义）
- ❌ 查询钩子系统（属于 Epic 4）

## Dependencies
### Depends On
- [x] `db-instance-api` - DB 实例初始化和连接管理
- [x] `query-context-api` - 查询执行上下文
- [x] `error-type-aliases` - 错误类型定义
- [x] `db-error-handling` - 数据库错误处理

### Enables
- [ ] Epic 4: Query Hook System（Raw SQL 钩子支持）
- [ ] Future: SQL 查询性能分析工具

## Implementation Status
当前实现已完成：
- ✅ `src/query/query.zig` - 完整的 RawQuery 实现
  - ✅ init() - 初始化 Raw SQL 查询
  - ✅ deinit() - 释放资源
  - ✅ exec() - 执行 DML 语句返回 RawResult
  - ✅ scan() - 扫描查询结果到 ArrayList
  - ✅ scanOne() - 查询单行结果
- ✅ `src/core/db.zig` - DB.newRaw() 方法
- ✅ `src/core/tx_manager.zig` - Tx.newRaw() 方法

待完成任务：
- ⏳ 添加 RawQuery 单元测试（测试各方法的基本功能）
- ⏳ 添加参数绑定测试（验证 $1, $2, ... 占位符处理）
- ⏳ 添加复杂 SQL 场景集成测试（窗口函数、CTE、JOIN 等）
- ⏳ 添加错误场景测试（SQL 语法错误、类型不匹配等）
- ⏳ 添加事务中执行 Raw SQL 测试

## Related Documents
- PRD: Story 2.6 (Raw SQL Query Support)
- 代码: `src/query/query.zig` (RawQuery 实现)
- 代码: `src/core/db.zig` (DB.newRaw 方法)
- 代码: `src/core/tx_manager.zig` (Tx.newRaw 方法)
