# Story 008: 实现 SQL 生成工具

## Status
Ready for Review

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
- [x] 创建 src/dialect/sql.zig
  - [x] escapeIdentifier() 函数
  - [x] escapeString() 函数
  - [x] generatePlaceholders() 函数
  - [x] buildInClause() 函数
- [x] 编写单元测试
- [x] 编写使用文档和示例

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md
### 架构参考
- [docs/architecture.md#方言系统设计](architecture.md#方言系统设计)

### 依赖项
- `src/dialect/dialect.zig`

## Dev Agent Record

### Agent Model Used
Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)

### File List
- src/dialect/sql.zig (新建)
- src/zorm.zig (修改 - 添加 sql 模块导出)
- docs/sql-utils-guide.md (新建 - 使用文档)

### Completion Notes
1. ✅ 成功实现所有四个核心 SQL 工具函数
2. ✅ 支持 PostgreSQL, MySQL, SQLite 三种方言
3. ✅ 实现快速路径优化,不需转义时使用优化代码
4. ✅ 完整的内存管理,所有分配都正确释放
5. ✅ 编写详细的函数文档和使用示例
6. ✅ 创建 60+ 页的使用指南文档
7. ✅ 所有测试通过,功能验证完成

### Debug Log References
无

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
| 2025-10-17 | 2.0 | 完成实现 | James (Dev Agent) |
