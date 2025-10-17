# Story 012: 实现 SELECT 查询构建器

## Status
Approved

## Story
**As a** ZORM 开发者,
**I want** 功能完整的 SELECT 查询构建器,
**so that** 能够使用链式 API 构建类型安全的 SELECT 查询

## Acceptance Criteria
1. 实现 SelectQuery(comptime T, comptime dialect) 泛型结构体
2. 支持 column/allColumns 选择列
3. 支持 where/whereOr 条件
4. 支持 join (inner/left/right/full/cross)
5. 支持 orderBy/groupBy/having
6. 支持 limit/offset/distinct
7. 实现 buildSQL() 生成 SQL 字符串
8. 实现 scan()/scanOne() 执行查询并映射结果
9. 编写完整单元测试和集成测试

## Tasks / Subtasks
- [ ] 创建 src/query/select.zig
- [ ] 实现 SelectQuery 结构体和所有方法
- [ ] 实现 SQL 生成逻辑
- [ ] 集成结果映射
- [ ] 编写测试

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md
参考 [docs/architecture.md#SelectQuery](architecture.md) (行 368-684)

### 关键实现
```zig
pub fn SelectQuery(comptime T: type, comptime dialect: Dialect) type {
    return struct {
        const Self = @This();
        const table_name = comptime getTableName(T);
        const field_names = comptime getFieldNames(T);

        arena: std.heap.ArenaAllocator,
        base_allocator: Allocator,
        db: *DB(dialect),
        where_clauses: std.ArrayList(WhereClause),
        // ...

        pub fn where(self: *Self, condition: []const u8, args: anytype) !*Self {
            // 实现
        }

        pub fn buildSQL(self: *Self) ![]const u8 {
            // 实现
        }

        pub fn scan(self: *Self, dest: *std.ArrayList(T)) !void {
            // 实现
        }
    };
}
```

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
