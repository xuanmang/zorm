# Story 007: 实现方言系统和特性检测

## Status
Approved

## Story
**As a** ZORM 开发者,
**I want** 完整的数据库方言系统,
**so that** 能够在编译时检测和使用数据库特定特性,实现零运行时开销

## Acceptance Criteria
1. 定义 Dialect 枚举 (postgres, mysql, sqlite)
2. 实现编译时特性检测函数 (supportsReturning, supportsOnConflict 等)
3. 实现占位符生成函数 (PostgreSQL: $1, MySQL: ?)
4. 实现标识符引号函数 (PostgreSQL: ", MySQL: `)
5. 所有方言相关函数都是 comptime,零运行时开销
6. 编写完整单元测试验证所有方言特性

## Tasks / Subtasks
- [ ] 创建 src/dialect/dialect.zig
  - [ ] 定义 Dialect enum (postgres, mysql, sqlite)
  - [ ] 实现 supportsReturning(comptime dialect)
  - [ ] 实现 supportsOnConflict(comptime dialect)
  - [ ] 实现 supportsCTE(comptime dialect)
  - [ ] 实现 supportsJSONB(comptime dialect)
  - [ ] 实现 placeholder(comptime dialect, index)
  - [ ] 实现 quoteIdentifier(comptime dialect, identifier)
- [ ] 编写测试验证编译时计算
- [ ] 编写文档说明方言差异

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md
### 架构参考
- [docs/architecture.md#方言系统设计](architecture.md#方言系统设计) (行 1553-1754)

### 关键实现
```zig
pub const Dialect = enum {
    postgres,
    mysql,
    sqlite,

    pub fn supportsReturning(comptime dialect: Dialect) bool {
        return comptime switch (dialect) {
            .postgres, .sqlite => true,
            .mysql => false,
        };
    }

    pub fn placeholder(comptime dialect: Dialect, index: usize) []const u8 {
        return comptime switch (dialect) {
            .postgres => std.fmt.comptimePrint("${d}", .{index}),
            .mysql, .sqlite => "?",
        };
    }
};
```

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |

## Dev Agent Record
_待填写_

## QA Results
_待填写_
