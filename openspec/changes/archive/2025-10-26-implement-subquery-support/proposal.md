# Implement Subquery Support

## Why

当前 ZORM SELECT 查询构建器缺乏子查询支持,无法构建复杂的嵌套查询逻辑(如 WHERE IN 子查询、EXISTS 子查询、FROM 派生表等)。这限制了开发者执行高级查询模式的能力,特别是在需要基于其他查询结果进行过滤时。

根据 PRD Story 4.4,子查询支持是 Epic 4 的重要功能之一,对于提供完整的 PostgreSQL 查询能力至关重要。

## What Changes

- **NEW**: 在 `types.zig` 中添加 `SubqueryClause` 类型,表示子查询及其参数
- **NEW**: 为 `SelectQuery` 添加 `whereIn(column, subquery)` 方法,支持 WHERE IN 子查询
- **NEW**: 为 `SelectQuery` 添加 `whereNotIn(column, subquery)` 方法,支持 WHERE NOT IN 子查询
- **NEW**: 为 `SelectQuery` 添加 `whereExists(subquery)` 方法,支持 EXISTS 子查询
- **NEW**: 为 `SelectQuery` 添加 `whereNotExists(subquery)` 方法,支持 NOT EXISTS 子查询
- **NEW**: 为 `SelectQuery` 添加 `fromSubquery(subquery, alias)` 方法,支持 FROM 派生表
- **NEW**: 子查询参数自动合并到主查询参数列表的机制
- **NEW**: 为所有子查询方法添加完整的文档注释和使用示例
- **NEW**: 添加全面的单元测试和集成测试覆盖

## Impact

### Affected Specs
- **select-query-api**: 需要扩展以支持子查询相关方法
- **NEW**: **select-query-subquery-api**: 新建 spec 专门定义子查询功能

### Affected Code
- `src/types.zig`: 添加 `SubqueryClause` 类型定义
- `src/query/query.zig`: 在 `SelectQuery` 中添加子查询方法和 SQL 生成逻辑
- `src/query/builder.zig`: 更新查询构建器以支持子查询的 SQL 生成
- `tests/query/subquery_tests.zig`: 新建测试文件覆盖所有子查询功能

### Breaking Changes
无破坏性变更。所有新功能都是向后兼容的扩展。

### Migration Path
不需要迁移。现有代码无需修改即可继续工作。

### Dependencies
- 依赖现有的 `SelectQuery` 实现
- 依赖 `QueryArg` 参数绑定机制
- 需要参数合并逻辑来组合主查询和子查询的参数

## Success Criteria

1. ✅ 所有子查询方法都能生成正确的 SQL 语句
2. ✅ 子查询参数正确合并到主查询参数列表
3. ✅ 子查询支持嵌套(子查询中包含子查询)
4. ✅ 所有测试通过,包括单元测试和 PostgreSQL 集成测试
5. ✅ 代码覆盖率达到 80% 以上
6. ✅ 所有公共 API 包含完整文档注释和使用示例
7. ✅ `openspec validate --strict` 通过验证

## Example Usage

```zig
// WHERE IN 子查询
var subquery = try db.newSelect(Post);
defer subquery.deinit();

try subquery
    .column("DISTINCT user_id")
    .where("published = $1", .{true});

var users = std.ArrayList(User).init(allocator);
defer users.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .whereIn("id", subquery)
    .scan(&users);

// WHERE EXISTS 子查询
var exists_query = try db.newSelect(Post);
defer exists_query.deinit();

try exists_query
    .column("1")
    .where("posts.user_id = users.id", .{})
    .where("published = $1", .{true});

var active_users = std.ArrayList(User).init(allocator);
defer active_users.deinit();

var main_query = try db.newSelect(User);
defer main_query.deinit();

try main_query
    .whereExists(exists_query)
    .scan(&active_users);

// FROM 派生表
var derived = try db.newSelect(User);
defer derived.deinit();

try derived
    .column("id")
    .column("COUNT(*) AS post_count")
    .from("users")
    .join(.left, "posts", "posts.user_id = users.id")
    .groupBy("id");

var results = std.ArrayList(UserStats).init(allocator);
defer results.deinit();

var outer_query = try db.newSelect(UserStats);
defer outer_query.deinit();

try outer_query
    .column("*")
    .fromSubquery(derived, "user_stats")
    .where("post_count > $1", .{5})
    .scan(&results);
```
