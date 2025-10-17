# Story 013: 实现 INSERT 查询构建器

## Status
Approved

## Story
**As a** ZORM 开发者,
**I want** 功能完整的 INSERT 查询构建器,
**so that** 能够插入单行或多行数据,支持 RETURNING 等特性

## Acceptance Criteria
1. 实现 InsertQuery(comptime T, comptime dialect) 泛型结构体
2. 支持 value() 单行插入
3. 支持 values() 批量插入
4. 支持 returning() (PostgreSQL/SQLite)
5. 支持 onConflict() (PostgreSQL/SQLite)
6. 支持 onDuplicateKeyUpdate() (MySQL)
7. 实现 buildSQL() 和 exec()
8. 编写测试

## Tasks / Subtasks
- [ ] 创建 src/query/insert.zig
- [ ] 实现插入逻辑
- [ ] 实现方言特定特性
- [ ] 编写测试

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md
参考 [docs/architecture.md#InsertQuery](architecture.md) (行 1661-1721)

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
