# Story 009: 实现 DB 实例管理

## Status
Approved

## Story
**As a** ZORM 开发者,
**I want** 核心 DB 实例管理功能,
**so that** 能够创建数据库实例、管理连接、执行查询

## Acceptance Criteria
1. 实现 DB(comptime dialect: Dialect) 泛型结构体
2. 提供 init() 和 deinit() 方法
3. 实现 newSelect/newInsert/newUpdate/newDelete 查询构建器工厂方法
4. 支持数据库配置选项 (DBOptions)
5. 实现统计信息收集 (DBStats)
6. 编写完整单元测试

## Tasks / Subtasks
- [ ] 创建 src/core/db.zig
- [ ] 定义 DB 泛型结构体
- [ ] 实现查询构建器工厂方法
- [ ] 实现配置和统计

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md
参考 [docs/architecture.md#DB实例管理](architecture.md) (行 1876-1918)

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
