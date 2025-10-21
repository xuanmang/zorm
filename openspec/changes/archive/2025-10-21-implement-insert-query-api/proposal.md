# Proposal: implement-insert-query-api

## Why

实现 PRD Story 1.4 和 1.5 的类型安全 INSERT 查询构建器功能。当前 ZORM 已有 SELECT 查询能力，但缺少正式化的 INSERT API 规范，需要提供单行和批量插入功能，支持 PostgreSQL RETURNING 子句，确保类型安全和性能优化。

## What Changes

- **新增功能**：INSERT 查询构建器 API
  - `db.newInsert(T)` - 创建 INSERT 查询构建器
  - `.value(item)` - 单行插入（Story 1.4）
  - `.values(items)` - 批量插入（Story 1.5）
  - `.returning(cols)` - RETURNING 子句支持
  - `.exec()` - 执行插入并返回 InsertResult
  - `.execReturning(dest)` - 执行插入并获取返回数据

- **性能优化**：
  - 批量插入生成单条 SQL 语句（VALUES (...), (...), ...）
  - 内存预分配优化（预估 SQL 大小）
  - 批量大小限制（最大 1000 行，PostgreSQL 参数限制 65535）

- **类型安全**：
  - 编译时从 Zig 结构体自动推断列名
  - 自动生成参数化查询（防止 SQL 注入）
  - comptime 类型检查（仅接受结构体）

## Impact

- **新增规范**：`insert-query-api` - 定义 INSERT 查询构建器的需求和场景
- **受影响代码**：
  - `src/query/query.zig` - InsertQuery 实现（已存在，需正式化）
  - `src/core/db.zig` - DB.newInsert() 工厂方法（已存在）
  - `src/types.zig` - InsertResult 类型定义（已存在）
- **测试覆盖**：需补充性能测试（AC1.5.4 - 批量插入性能验证）

## Dependencies

- 依赖现有的 `query-context-api` 规范（内存管理）
- 依赖现有的 `db-instance-api` 规范（DB 工厂方法）
- 依赖现有的 `dialect-comptime-features` 规范（RETURNING 子句支持检查）

## Migration

无需迁移 - 这是新增功能，不影响现有 API。

## Related PRD

- PRD Story 1.4: Type-Safe INSERT Query Builder (Single Row)
- PRD Story 1.5: Batch INSERT Support
