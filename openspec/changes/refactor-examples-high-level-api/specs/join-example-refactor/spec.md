# Spec: JOIN 查询示例重构

## MODIFIED Requirements

### Requirement: 使用 JOIN 构建器替代原始 JOIN SQL

**优先级**: P0
**依赖**: select-query-join-api

`join.zig` 示例 **MUST** 使用 `db.newSelect()` 查询构建器的 `join()` 方法替代手写 JOIN SQL。

#### Scenario: INNER JOIN 查询用户及其文章

**Given**: users 表有 3 个用户, posts 表有 2 篇已发布文章
**When**: 查询所有用户及其已发布的文章
**Then**:
- 使用 `var query = try db.newSelect(User)`
- 调用 `try query.column("users.name").column("users.email").column("posts.title")`
- 调用 `try query.join("posts", "posts.user_id = users.id")`
- 调用 `try query.where("posts.published", .eq, .{ .bool = true })`
- 调用 `try query.orderBy("users.id", .asc).orderBy("posts.id", .asc)`
- 返回 2 条记录

```zig
var query = try db.newSelect(User);
defer query.deinit();

try query.column("users.name");
try query.column("users.email");
try query.column("posts.title");

try query.join("posts", "posts.user_id = users.id");
try query.where("posts.published", .eq, .{ .bool = true });
try query.orderBy("users.id", .asc);
try query.orderBy("posts.id", .asc);

var rows = try query.exec();
defer rows.deinit();

var count: u32 = 0;
while (try rows.next()) |row| {
    const name = try row.getString(0);
    const email = try row.getString(1);
    const title = try row.getString(2);
    count += 1;
    std.debug.print("   [{d}] {s} <{s}> - 「{s}」\n", .{ count, name, email, title });
}
```

---

### Requirement: 使用 LEFT JOIN 构建器

**优先级**: P0
**依赖**: select-query-join-api

`join.zig` 示例 **MUST** 使用 `db.newSelect()` 查询构建器的 `leftJoin()` 方法执行 LEFT JOIN 查询。

#### Scenario: LEFT JOIN 查询所有用户及其文章数

**Given**: users 表有 3 个用户 (Alice 2篇, Bob 1篇未发布, Charlie 0篇)
**When**: 查询所有用户及其文章数,包括无文章的用户
**Then**:
- 使用 `var query = try db.newSelect(User)`
- 调用 `try query.column("users.name")`
- 调用 `try query.column("COUNT(posts.id) as post_count")`
- 调用 `try query.leftJoin("posts", "posts.user_id = users.id")`
- 调用 `try query.groupBy("users.id").groupBy("users.name")`
- 调用 `try query.orderBy("users.id", .asc)`
- 返回 3 条记录 (Alice: 2, Bob: 1, Charlie: 0)

```zig
var query = try db.newSelect(User);
defer query.deinit();

try query.column("users.name");
try query.column("COUNT(posts.id) as post_count");

try query.leftJoin("posts", "posts.user_id = users.id");

try query.groupBy("users.id");
try query.groupBy("users.name");
try query.orderBy("users.id", .asc);

var rows = try query.exec();
defer rows.deinit();

while (try rows.next()) |row| {
    const name = try row.getString(0);
    const post_count = try row.getInt(i64, 1);
    std.debug.print("   {s}: {d} 篇文章\n", .{ name, post_count });
}
```

---

### Requirement: 使用多表 JOIN 构建器

**优先级**: P0
**依赖**: select-query-join-api

`join.zig` 示例 **MUST** 链式调用多个 `join()` 方法执行多表关联查询。

#### Scenario: 三表 JOIN 查询文章、作者和评论

**Given**: users, posts, comments 三表关联
**When**: 查询所有文章及其作者和评论
**Then**:
- 使用 `var query = try db.newSelect(Post)`
- 调用 `try query.column("users.name as author")`
- 调用 `try query.column("posts.title")`
- 调用 `try query.column("comments.content")`
- 调用 `try query.join("users", "users.id = posts.user_id")`
- 调用 `try query.join("comments", "comments.post_id = posts.id")`
- 调用 `try query.orderBy("posts.id", .asc).orderBy("comments.id", .asc)`
- 返回所有评论记录

```zig
var query = try db.newSelect(Post);
defer query.deinit();

try query.column("users.name as author");
try query.column("posts.title");
try query.column("comments.content");

try query.join("users", "users.id = posts.user_id");
try query.join("comments", "comments.post_id = posts.id");

try query.orderBy("posts.id", .asc);
try query.orderBy("comments.id", .asc);

var rows = try query.exec();
defer rows.deinit();

var count: u32 = 0;
while (try rows.next()) |row| {
    const author = try row.getString(0);
    const title = try row.getString(1);
    const content = try row.getString(2);

    count += 1;
    std.debug.print("   [{d}] 「{s}」 by {s}\n", .{ count, title, author });
    std.debug.print("       └─ 评论: {s}\n", .{content});
}
```

---

### Requirement: GROUP BY 和聚合函数

**优先级**: P1
**依赖**: select-query-api, select-query-join-api

`join.zig` 示例 **MUST** 使用 `groupBy()` 方法和聚合函数执行统计查询。

#### Scenario: COUNT 聚合查询

**Given**: users 和 posts 表已关联
**When**: 统计每个用户的文章数
**Then**:
- 使用 `column("COUNT(posts.id) as post_count")`
- 使用 `groupBy("users.id")`
- 结果按用户分组

```zig
try query.column("users.name");
try query.column("COUNT(posts.id) as post_count");
try query.leftJoin("posts", "posts.user_id = users.id");
try query.groupBy("users.id");
try query.groupBy("users.name");
```

---

### Requirement: 表创建和数据准备使用高层级 API

**优先级**: P1
**依赖**: insert-query-api, schema-reflection

`join.zig` 示例 **MUST** 使用 `db.newInsert()` 查询构建器和反射 API 进行表创建和数据准备。

#### Scenario: 批量插入用户数据

**Given**: users 表已创建
**When**: 插入 Alice, Bob, Charlie 三个用户
**Then**:
- 使用 `db.newInsert(User)` 创建查询
- 多次调用 `values()` 添加用户
- 执行插入

```zig
// 插入用户
var insert = try db.newInsert(User);
defer insert.deinit();

try insert.values(&User{ .name = "Alice", .email = "alice@example.com" });
try insert.values(&User{ .name = "Bob", .email = "bob@example.com" });
try insert.values(&User{ .name = "Charlie", .email = "charlie@example.com" });

_ = try insert.exec();
```

#### Scenario: 批量插入文章数据

**Given**: posts 表已创建,用户已插入
**When**: 插入 Alice 的 2 篇文章和 Bob 的 1 篇文章
**Then**:
- 使用 `db.newInsert(Post)` 创建查询
- 分别插入每篇文章

```zig
var insert = try db.newInsert(Post);
defer insert.deinit();

try insert.values(&Post{
    .user_id = 1,
    .title = "Zig Programming Guide",
    .published = true,
});
try insert.values(&Post{
    .user_id = 1,
    .title = "ZORM Tutorial",
    .published = true,
});
try insert.values(&Post{
    .user_id = 2,
    .title = "Draft Post",
    .published = false,
});

_ = try insert.exec();
```

#### Scenario: 批量插入评论数据

**Given**: comments 表已创建,用户和文章已插入
**When**: 插入 2 条评论
**Then**:
- 使用 `db.newInsert(Comment)` 创建查询
- 插入评论记录

```zig
var insert = try db.newInsert(Comment);
defer insert.deinit();

try insert.values(&Comment{
    .post_id = 1,
    .user_id = 2,
    .content = "Great tutorial!",
});
try insert.values(&Comment{
    .post_id = 2,
    .user_id = 2,
    .content = "Very helpful, thanks!",
});

_ = try insert.exec();
```

---

### Requirement: 示例输出格式保持一致

**优先级**: P2
**依赖**: 无

`join.zig` 示例重构后 **MUST** 保持输出格式与原示例一致。

#### Scenario: 输出格式一致性

**Given**: 重构后的 JOIN 示例
**When**: 运行示例程序
**Then**:
- 保持原有的分隔线和标题格式
- 保持原有的 INNER JOIN, LEFT JOIN, 多表 JOIN 三个演示
- 查询结果的展示格式一致
- 成功标记 (✓) 显示正确
