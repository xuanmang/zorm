# Story 016: 实现查询构建器基础功能

## Status
Approved

## Story
**As a** ZORM 开发者,
**I want** 查询构建器共享的基础功能,
**so that** 减少代码重复,提高可维护性

## Acceptance Criteria
1. 提取 WHERE 子句构建逻辑
2. 提取参数收集逻辑
3. 提供共享的辅助函数
4. 编写测试

## Tasks / Subtasks
- [ ] 创建 src/query/builder_base.zig
- [ ] 实现共享逻辑
- [ ] 重构现有查询构建器使用共享逻辑

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md


## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
