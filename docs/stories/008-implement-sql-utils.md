# Story 008: 实现 SQL 生成工具

## Status
Approved

## Story
**As a** ZORM 开发者,
**I want** SQL 生成工具函数集合,
**so that** 能够安全高效地构建 SQL 语句,避免 SQL 注入

## Acceptance Criteria
1. 实现 SQL 标识符转义函数
2. 实现 SQL 字符串转义函数
3. 实现占位符数组生成函数
4. 实现 IN 子句生成函数
5. 所有函数都考虑不同方言的差异
6. 编写单元测试覆盖所有边界情况

## Tasks / Subtasks
- [ ] 创建 src/dialect/sql.zig
  - [ ] escapeIdentifier() 函数
  - [ ] escapeString() 函数
  - [ ] generatePlaceholders() 函数
  - [ ] buildInClause() 函数
- [ ] 编写单元测试
- [ ] 编写使用文档和示例

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md
### 架构参考
- [docs/architecture.md#方言系统设计](architecture.md#方言系统设计)

### 依赖项
- `src/dialect/dialect.zig`

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
