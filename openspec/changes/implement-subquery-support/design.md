# Design: Subquery Support

## Overview

本设计文档描述了在 ZORM SELECT 查询构建器中实现子查询支持的技术方案。子查询功能允许开发者在 WHERE、FROM 等子句中嵌套使用 SELECT 查询,实现复杂的数据过滤和组合逻辑。

## Architecture

### 核心组件

```
┌─────────────────────────────────────────────────────────┐
│                    SelectQuery(T, dialect)                │
├─────────────────────────────────────────────────────────┤
│  字段:                                                     │
│  - subquery_clauses: ArrayList(SubqueryClause)           │
│  - derived_table: ?DerivedTable                          │
│                                                           │
│  方法:                                                     │
│  - whereIn(column, subquery) -> *Self                    │
│  - whereNotIn(column, subquery) -> *Self                 │
│  - whereExists(subquery) -> *Self                        │
│  - whereNotExists(subquery) -> *Self                     │
│  - fromSubquery(subquery, alias) -> *Self                │
│  - buildSQL() -> []const u8 (包含子查询生成逻辑)         │
│  - collectAllArgs() -> []QueryArg (合并主查询和子查询参数)│
└─────────────────────────────────────────────────────────┘
                           │
                           │ 使用
                           ▼
┌─────────────────────────────────────────────────────────┐
│                     SubqueryClause                        │
├─────────────────────────────────────────────────────────┤
│  字段:                                                     │
│  - type: SubqueryType (.where_in | .where_not_in |       │
│                        .exists | .not_exists)            │
│  - column: ?[]const u8 (用于 WHERE IN,可选)               │
│  - sql: []const u8 (子查询生成的完整 SQL)                 │
│  - args: []const QueryArg (子查询的绑定参数)              │
│                                                           │
│  方法:                                                     │
│  - toSQL() -> []const u8                                 │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                     DerivedTable                          │
├─────────────────────────────────────────────────────────┤
│  字段:                                                     │
│  - sql: []const u8 (派生表子查询的 SQL)                   │
│  - alias: []const u8 (派生表别名)                         │
│  - args: []const QueryArg (派生表查询的参数)              │
└─────────────────────────────────────────────────────────┘
```

### 类型定义

#### SubqueryType 枚举
```zig
pub const SubqueryType = enum {
    where_in,      // WHERE column IN (SELECT ...)
    where_not_in,  // WHERE column NOT IN (SELECT ...)
    exists,        // WHERE EXISTS (SELECT ...)
    not_exists,    // WHERE NOT EXISTS (SELECT ...)
};
```

#### SubqueryClause 结构体
```zig
pub const SubqueryClause = struct {
    type: SubqueryType,
    column: ?[]const u8,        // 仅用于 WHERE IN/NOT IN
    sql: []const u8,            // 子查询的完整 SQL
    args: []const QueryArg,     // 子查询的绑定参数

    pub fn toSQL(self: SubqueryClause, allocator: Allocator) ![]const u8 {
        return switch (self.type) {
            .where_in => try std.fmt.allocPrint(
                allocator,
                "{s} IN ({s})",
                .{ self.column.?, self.sql }
            ),
            .where_not_in => try std.fmt.allocPrint(
                allocator,
                "{s} NOT IN ({s})",
                .{ self.column.?, self.sql }
            ),
            .exists => try std.fmt.allocPrint(
                allocator,
                "EXISTS ({s})",
                .{self.sql}
            ),
            .not_exists => try std.fmt.allocPrint(
                allocator,
                "NOT EXISTS ({s})",
                .{self.sql}
            ),
        };
    }
};
```

#### DerivedTable 结构体
```zig
pub const DerivedTable = struct {
    sql: []const u8,
    alias: []const u8,
    args: []const QueryArg,
};
```

## Parameter Management

### 参数重新编号策略

子查询的参数占位符需要重新编号,以避免与主查询的占位符冲突。

#### 策略:顺序合并
1. 主查询使用占位符 `$1, $2, ..., $N`
2. 收集所有子查询的参数
3. 重新编号子查询占位符为 `$N+1, $N+2, ...`

#### 实现示例
```zig
fn collectAllArgs(self: *Self, allocator: Allocator) ![]QueryArg {
    var all_args = std.ArrayList(QueryArg).init(allocator);
    errdefer all_args.deinit();

    var param_offset: usize = 1;

    // 1. 收集主查询 WHERE 子句参数
    for (self.where_clauses.items) |clause| {
        for (clause.args) |arg| {
            try all_args.append(arg);
            param_offset += 1;
        }
    }

    // 2. 收集所有子查询参数
    for (self.subquery_clauses.items) |sub_clause| {
        for (sub_clause.args) |arg| {
            try all_args.append(arg);
        }
    }

    // 3. 收集 FROM 派生表参数
    if (self.derived_table) |dt| {
        for (dt.args) |arg| {
            try all_args.append(arg);
        }
    }

    return try all_args.toOwnedSlice();
}
```

### 占位符重新编号
```zig
fn renumberPlaceholders(
    sql: []const u8,
    allocator: Allocator,
    offset: usize
) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < sql.len) {
        if (sql[i] == '$') {
            // 解析占位符编号
            i += 1;
            var num: usize = 0;
            while (i < sql.len and std.ascii.isDigit(sql[i])) {
                num = num * 10 + (sql[i] - '0');
                i += 1;
            }

            // 重新编号
            const new_num = num + offset;
            try result.writer().print("${d}", .{new_num});
        } else {
            try result.append(sql[i]);
            i += 1;
        }
    }

    return try result.toOwnedSlice();
}
```

## SQL Generation

### WHERE IN 子查询
```sql
SELECT * FROM users
WHERE id IN (
    SELECT DISTINCT user_id
    FROM posts
    WHERE published = $1
)
```

生成逻辑:
```zig
pub fn whereIn(
    self: *Self,
    column: []const u8,
    subquery: anytype  // 另一个 SelectQuery
) !*Self {
    // 1. 生成子查询 SQL
    const sub_sql = try subquery.buildSQL();
    defer self.allocator.free(sub_sql);

    // 2. 收集子查询参数
    const sub_args = try subquery.collectArgs();

    // 3. 创建 SubqueryClause
    const clause = SubqueryClause{
        .type = .where_in,
        .column = try self.allocator.dupe(u8, column),
        .sql = try self.allocator.dupe(u8, sub_sql),
        .args = sub_args,
    };

    try self.subquery_clauses.append(self.allocator, clause);
    return self;
}
```

### WHERE EXISTS 子查询
```sql
SELECT * FROM users
WHERE EXISTS (
    SELECT 1
    FROM posts
    WHERE posts.user_id = users.id
    AND published = $1
)
```

生成逻辑:
```zig
pub fn whereExists(
    self: *Self,
    subquery: anytype
) !*Self {
    const sub_sql = try subquery.buildSQL();
    defer self.allocator.free(sub_sql);

    const sub_args = try subquery.collectArgs();

    const clause = SubqueryClause{
        .type = .exists,
        .column = null,
        .sql = try self.allocator.dupe(u8, sub_sql),
        .args = sub_args,
    };

    try self.subquery_clauses.append(self.allocator, clause);
    return self;
}
```

### FROM 派生表
```sql
SELECT * FROM (
    SELECT id, COUNT(*) AS post_count
    FROM users
    LEFT JOIN posts ON posts.user_id = users.id
    GROUP BY id
) AS user_stats
WHERE post_count > $1
```

生成逻辑:
```zig
pub fn fromSubquery(
    self: *Self,
    subquery: anytype,
    alias: []const u8
) !*Self {
    const sub_sql = try subquery.buildSQL();
    const sub_args = try subquery.collectArgs();

    self.derived_table = DerivedTable{
        .sql = try self.allocator.dupe(u8, sub_sql),
        .alias = try self.allocator.dupe(u8, alias),
        .args = sub_args,
    };

    return self;
}
```

### 更新 buildSQL() 方法
```zig
pub fn buildSQL(self: *Self) ![]const u8 {
    var sql = std.ArrayList(u8).init(self.allocator);
    defer sql.deinit();

    // SELECT clause
    try sql.appendSlice("SELECT ");
    // ... 列生成逻辑 ...

    // FROM clause
    try sql.appendSlice(" FROM ");
    if (self.derived_table) |dt| {
        // 使用派生表
        try sql.writer().print("({s}) AS {s}", .{ dt.sql, dt.alias });
    } else {
        // 使用普通表名
        try sql.appendSlice(self.table_name);
    }

    // JOIN clauses
    for (self.join_clauses.items) |join| {
        // ... JOIN 生成逻辑 ...
    }

    // WHERE clause
    if (self.where_clauses.items.len > 0 or
        self.subquery_clauses.items.len > 0) {
        try sql.appendSlice(" WHERE ");

        var first = true;

        // 常规 WHERE 条件
        for (self.where_clauses.items) |clause| {
            if (!first) {
                try sql.writer().print(" {s} ", .{clause.operator.toSQL()});
            }
            try sql.appendSlice(clause.condition);
            first = false;
        }

        // 子查询条件
        for (self.subquery_clauses.items) |sub_clause| {
            if (!first) {
                try sql.appendSlice(" AND ");
            }
            const sub_sql = try sub_clause.toSQL(self.allocator);
            defer self.allocator.free(sub_sql);
            try sql.appendSlice(sub_sql);
            first = false;
        }
    }

    // ... 其他子句 ...

    return try sql.toOwnedSlice();
}
```

## Memory Management

### 所有权规则
1. **SubqueryClause 所有权**:
   - `sql` 字段: 由 `SubqueryClause` 拥有,需要复制
   - `args` 字段: 由 `SubqueryClause` 拥有,需要复制
   - `column` 字段: 由 `SubqueryClause` 拥有,需要复制

2. **SelectQuery.deinit() 扩展**:
```zig
pub fn deinit(self: *Self) void {
    // 清理子查询
    for (self.subquery_clauses.items) |clause| {
        self.allocator.free(clause.sql);
        self.allocator.free(clause.args);
        if (clause.column) |col| {
            self.allocator.free(col);
        }
    }
    self.subquery_clauses.deinit(self.allocator);

    // 清理派生表
    if (self.derived_table) |dt| {
        self.allocator.free(dt.sql);
        self.allocator.free(dt.alias);
        self.allocator.free(dt.args);
    }

    // ... 其他清理逻辑 ...
}
```

## Performance Considerations

### 优化策略
1. **懒惰 SQL 生成**: 仅在 `buildSQL()` 调用时生成子查询 SQL
2. **参数预分配**: 预估参数总数,减少 ArrayList 重新分配
3. **字符串构建优化**: 使用 `std.ArrayList(u8)` 而非字符串拼接

### 性能目标
- 子查询开销 < 5% (相比无子查询的简单查询)
- 内存分配次数最小化
- 无内存泄漏 (通过 `std.testing.allocator` 验证)

## Error Handling

### 错误类型
```zig
pub const SubqueryError = error{
    EmptySubquery,           // 子查询为空
    InvalidSubqueryType,     // 无效的子查询类型
    ParameterMergeError,     // 参数合并失败
    CircularSubquery,        // 循环子查询引用
};
```

### 验证
- 在 `whereIn()` 等方法中验证子查询非空
- 确保派生表必须有别名
- 防止子查询自引用导致无限循环

## Testing Strategy

### 单元测试
- 每个子查询方法独立测试
- SQL 生成正确性验证
- 参数合并逻辑验证
- 内存泄漏检测

### 集成测试
- 真实 PostgreSQL 数据库测试
- 复杂嵌套子查询测试
- 与 JOIN、GROUP BY 等组合测试
- 性能基准测试

### 测试覆盖率目标
- 单元测试: 80%+
- 集成测试: 覆盖所有公开 API 场景

## Alternative Designs Considered

### 备选方案 1: 字符串模板
直接使用字符串模板生成子查询,而不是使用查询构建器。

**优点**: 实现简单,灵活
**缺点**: 失去类型安全,容易出错,无法自动参数绑定

**决策**: 不采用。与 ZORM 的类型安全原则冲突。

### 备选方案 2: 编译时子查询验证
使用 comptime 在编译时验证子查询结构。

**优点**: 更早发现错误
**缺点**: 实现复杂,限制动态查询构建

**决策**: 暂不采用,保留为未来优化方向。

## Migration and Compatibility

### 向后兼容性
✅ 完全向后兼容。所有新功能都是可选的扩展,现有代码无需修改。

### 迁移指南
不需要迁移。用户可以按需采用新的子查询功能。

## Open Questions

1. **子查询深度限制**: 是否需要限制子查询嵌套深度?
   - **决策**: 不限制,由 PostgreSQL 自身处理

2. **参数占位符风格**: 是否支持其他数据库的占位符风格 (如 MySQL 的 `?`)?
   - **决策**: 暂不支持,ZORM 当前仅针对 PostgreSQL

3. **子查询缓存**: 是否缓存子查询 SQL 以避免重复生成?
   - **决策**: 不缓存。查询构建器是一次性使用,缓存收益有限

## References

- PRD Story 4.4: Subquery Support
- PostgreSQL 子查询文档: https://www.postgresql.org/docs/current/queries-table-expressions.html
- Bun ORM 子查询示例: https://bun.uptrace.dev/guide/query-subqueries.html
