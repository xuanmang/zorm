# Story 015: 实现 DELETE 查询构建器

## Status
Approved

## Story
**As a** ZORM 开发者,
**I want** DELETE 查询构建器,
**so that** 能够删除数据库记录

## Acceptance Criteria
1. 实现 DeleteQuery(comptime T, comptime dialect)
2. 支持 where() 条件
3. 实现 buildSQL() 和 exec()
4. 编写测试

## Tasks / Subtasks
- [ ] 创建 src/query/delete.zig
- [ ] 实现 DELETE 逻辑
- [ ] 编写测试

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md


## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
