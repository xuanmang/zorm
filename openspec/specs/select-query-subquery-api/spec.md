# select-query-subquery-api Specification

## Purpose
TBD - created by archiving change implement-subquery-support. Update Purpose after archive.
## Requirements
### Requirement: WHERE IN 子查询支持

SELECT 查询构建器 MUST 提供 `whereIn(column, subquery)` 方法,支持在 WHERE 子句中使用 IN 子查询。

#### Scenario: 使用 whereIn() 查询满足子查询条件的记录

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

// 创建子查询
var subquery = try db.newSelect(Post);
defer subquery.deinit();

try subquery
    .column("DISTINCT user_id")
    .where("published = $1", .{true});

// 主查询使用子查询
var users = std.ArrayList(User).init(allocator);
defer users.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .whereIn("id", subquery)
    .scan(&users);

// 验证生成的 SQL
const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE id IN (SELECT DISTINCT user_id FROM posts WHERE published = $1)") != null);
```

#### Scenario: WHERE IN 子查询参数正确绑定

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var subquery = try db.newSelect(Post);
defer subquery.deinit();

try subquery
    .column("user_id")
    .where("status = $1", .{"active"})
    .where("views > $2", .{100});

var query = try db.newSelect(User);
defer query.deinit();

try query
    .whereIn("id", subquery)
    .where("age > $3", .{18});

const args = try query.collectAllArgs();
defer allocator.free(args);

// 验证参数顺序: active, 100, 18
try std.testing.expectEqual(@as(usize, 3), args.len);
try std.testing.expectEqualStrings("active", args[0].string_val);
try std.testing.expectEqual(@as(i64, 100), args[1].int_val);
try std.testing.expectEqual(@as(i64, 18), args[2].int_val);
```

#### Scenario: WHERE IN 子查询与其他 WHERE 条件组合

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var subquery = try db.newSelect(Post);
defer subquery.deinit();

try subquery
    .column("DISTINCT user_id")
    .where("published = $1", .{true});

var query = try db.newSelect(User);
defer query.deinit();

try query
    .where("age > $2", .{18})
    .whereIn("id", subquery)
    .where("is_active = $3", .{true});

const sql = try query.buildSQL();
defer allocator.free(sql);

// 验证 SQL 包含所有条件
try std.testing.expect(std.mem.indexOf(u8, sql, "age > $2") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "id IN") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "is_active = $3") != null);
```

---

### Requirement: WHERE NOT IN 子查询支持

SELECT 查询构建器 MUST 提供 `whereNotIn(column, subquery)` 方法,支持在 WHERE 子句中使用 NOT IN 子查询。

#### Scenario: 使用 whereNotIn() 排除满足子查询条件的记录

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var subquery = try db.newSelect(Post);
defer subquery.deinit();

try subquery
    .column("user_id")
    .where("status = $1", .{"banned"});

var users = std.ArrayList(User).init(allocator);
defer users.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .whereNotIn("id", subquery)
    .scan(&users);

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE id NOT IN (SELECT user_id FROM posts WHERE status = $1)") != null);
```

#### Scenario: WHERE NOT IN 子查询集成测试

```zig
test "WHERE NOT IN subquery integration" {
    const allocator = std.testing.allocator;
    const db = try createRealDB(allocator);
    defer db.deinit();

    // 准备测试数据
    try db.exec("CREATE TABLE IF NOT EXISTS users (id BIGSERIAL PRIMARY KEY, name TEXT)", .{});
    try db.exec("CREATE TABLE IF NOT EXISTS banned_users (user_id BIGINT)", .{});
    try db.exec("INSERT INTO users (name) VALUES ('Alice'), ('Bob'), ('Charlie')", .{});
    try db.exec("INSERT INTO banned_users (user_id) VALUES (2)", .{}); // Bob is banned

    var subquery = try db.newSelect(struct { user_id: i64 });
    defer subquery.deinit();

    try subquery
        .column("user_id")
        .from("banned_users");

    var users = std.ArrayList(User).init(allocator);
    defer users.deinit();

    var query = try db.newSelect(User);
    defer query.deinit();

    try query
        .whereNotIn("id", subquery)
        .scan(&users);

    // 应该只返回 Alice 和 Charlie
    try std.testing.expectEqual(@as(usize, 2), users.items.len);
}
```

---

### Requirement: WHERE EXISTS 子查询支持

SELECT 查询构建器 MUST 提供 `whereExists(subquery)` 方法,支持在 WHERE 子句中使用 EXISTS 子查询。

#### Scenario: 使用 whereExists() 筛选存在关联记录的行

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var subquery = try db.newSelect(Post);
defer subquery.deinit();

try subquery
    .column("1")
    .where("posts.user_id = users.id", .{})
    .where("published = $1", .{true});

var users = std.ArrayList(User).init(allocator);
defer users.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .from("users")
    .whereExists(subquery)
    .scan(&users);

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE EXISTS (SELECT 1 FROM posts WHERE posts.user_id = users.id AND published = $1)") != null);
```

#### Scenario: WHERE EXISTS 子查询关联主查询表

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var subquery = try db.newSelect(Post);
defer subquery.deinit();

// 子查询引用主查询的表
try subquery
    .column("1")
    .from("posts")
    .where("posts.user_id = users.id", .{})
    .where("posts.status = $1", .{"published"});

var query = try db.newSelect(User);
defer query.deinit();

try query
    .column("*")
    .from("users")
    .whereExists(subquery);

const sql = try query.buildSQL();
defer allocator.free(sql);

// EXISTS 子查询应该包含关联条件
try std.testing.expect(std.mem.indexOf(u8, sql, "posts.user_id = users.id") != null);
```

#### Scenario: WHERE EXISTS 子查询集成测试

```zig
test "WHERE EXISTS subquery integration" {
    const allocator = std.testing.allocator;
    const db = try createRealDB(allocator);
    defer db.deinit();

    // 准备测试数据
    try db.exec("CREATE TABLE IF NOT EXISTS users (id BIGSERIAL PRIMARY KEY, name TEXT)", .{});
    try db.exec("CREATE TABLE IF NOT EXISTS posts (id BIGSERIAL PRIMARY KEY, user_id BIGINT, published BOOLEAN)", .{});
    try db.exec("INSERT INTO users (name) VALUES ('Alice'), ('Bob')", .{});
    try db.exec("INSERT INTO posts (user_id, published) VALUES (1, true)", .{}); // Alice has a published post

    var subquery = try db.newSelect(struct { id: i64 });
    defer subquery.deinit();

    try subquery
        .column("1")
        .from("posts")
        .where("posts.user_id = users.id", .{})
        .where("published = $1", .{true});

    var users = std.ArrayList(User).init(allocator);
    defer users.deinit();

    var query = try db.newSelect(User);
    defer query.deinit();

    try query
        .from("users")
        .whereExists(subquery)
        .scan(&users);

    // 应该只返回 Alice
    try std.testing.expectEqual(@as(usize, 1), users.items.len);
    try std.testing.expectEqualStrings("Alice", users.items[0].name);
}
```

---

### Requirement: WHERE NOT EXISTS 子查询支持

SELECT 查询构建器 MUST 提供 `whereNotExists(subquery)` 方法,支持在 WHERE 子句中使用 NOT EXISTS 子查询。

#### Scenario: 使用 whereNotExists() 筛选不存在关联记录的行

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var subquery = try db.newSelect(Post);
defer subquery.deinit();

try subquery
    .column("1")
    .where("posts.user_id = users.id", .{});

var users = std.ArrayList(User).init(allocator);
defer users.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .from("users")
    .whereNotExists(subquery)
    .scan(&users);

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE NOT EXISTS (SELECT 1 FROM posts WHERE posts.user_id = users.id)") != null);
```

#### Scenario: WHERE NOT EXISTS 子查询集成测试

```zig
test "WHERE NOT EXISTS subquery integration" {
    const allocator = std.testing.allocator;
    const db = try createRealDB(allocator);
    defer db.deinit();

    // 准备测试数据
    try db.exec("INSERT INTO users (name) VALUES ('Alice'), ('Bob')", .{});
    try db.exec("INSERT INTO posts (user_id, published) VALUES (1, true)", .{}); // Alice has a post, Bob doesn't

    var subquery = try db.newSelect(struct { id: i64 });
    defer subquery.deinit();

    try subquery
        .column("1")
        .from("posts")
        .where("posts.user_id = users.id", .{});

    var users = std.ArrayList(User).init(allocator);
    defer users.deinit();

    var query = try db.newSelect(User);
    defer query.deinit();

    try query
        .from("users")
        .whereNotExists(subquery)
        .scan(&users);

    // 应该只返回 Bob (没有 posts)
    try std.testing.expectEqual(@as(usize, 1), users.items.len);
    try std.testing.expectEqualStrings("Bob", users.items[0].name);
}
```

---

### Requirement: FROM 派生表支持

SELECT 查询构建器 MUST 提供 `fromSubquery(subquery, alias)` 方法,支持在 FROM 子句中使用子查询作为派生表。

#### Scenario: 使用 fromSubquery() 从派生表查询

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

const UserStats = struct {
    id: i64,
    post_count: i64,
};

// 创建派生表子查询
var derived = try db.newSelect(UserStats);
defer derived.deinit();

try derived
    .column("users.id")
    .column("COUNT(posts.id) AS post_count")
    .from("users")
    .leftJoin("posts", "posts.user_id = users.id")
    .groupBy("users.id");

// 主查询使用派生表
var results = std.ArrayList(UserStats).init(allocator);
defer results.deinit();

var query = try db.newSelect(UserStats);
defer query.deinit();

try query
    .column("*")
    .fromSubquery(derived, "user_stats")
    .where("post_count > $1", .{5})
    .scan(&results);

const sql = try query.buildSQL();
defer allocator.free(sql);

// 验证 SQL 包含派生表
try std.testing.expect(std.mem.indexOf(u8, sql, "FROM (SELECT") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, ") AS user_stats") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE post_count > $1") != null);
```

#### Scenario: 派生表别名在 WHERE 和 ORDER BY 中使用

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var derived = try db.newSelect(User);
defer derived.deinit();

try derived
    .column("*")
    .from("users")
    .where("age > $1", .{18});

var query = try db.newSelect(User);
defer query.deinit();

try query
    .column("adult_users.name")
    .column("adult_users.age")
    .fromSubquery(derived, "adult_users")
    .where("adult_users.age < $2", .{65})
    .orderBy("adult_users.age", .desc);

const sql = try query.buildSQL();
defer allocator.free(sql);

// 验证别名正确使用
try std.testing.expect(std.mem.indexOf(u8, sql, "adult_users.name") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "adult_users.age") != null);
```

#### Scenario: FROM 派生表集成测试

```zig
test "FROM derived table integration" {
    const allocator = std.testing.allocator;
    const db = try createRealDB(allocator);
    defer db.deinit();

    // 准备测试数据
    try db.exec("CREATE TABLE IF NOT EXISTS users (id BIGSERIAL PRIMARY KEY, name TEXT, age INT)", .{});
    try db.exec("INSERT INTO users (name, age) VALUES ('Alice', 25), ('Bob', 35), ('Charlie', 45)", .{});

    const AgeGroup = struct {
        age_group: []const u8,
        user_count: i64,
    };

    // 创建派生表:年龄分组统计
    var derived = try db.newSelect(AgeGroup);
    defer derived.deinit();

    try derived
        .column("CASE WHEN age < 30 THEN 'young' ELSE 'senior' END AS age_group")
        .column("COUNT(*) AS user_count")
        .from("users")
        .groupBy("age_group");

    var results = std.ArrayList(AgeGroup).init(allocator);
    defer results.deinit();

    var query = try db.newSelect(AgeGroup);
    defer query.deinit();

    try query
        .column("*")
        .fromSubquery(derived, "age_groups")
        .where("user_count > $1", .{0})
        .scan(&results);

    // 验证结果
    try std.testing.expectEqual(@as(usize, 2), results.items.len); // young and senior groups
}
```

---

### Requirement: 嵌套子查询支持

子查询 MUST 能够包含其他子查询,实现多层嵌套查询逻辑。

#### Scenario: 嵌套 WHERE IN 子查询

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

// 第三层子查询
var sub_sub_query = try db.newSelect(Comment);
defer sub_sub_query.deinit();

try sub_sub_query
    .column("DISTINCT post_id")
    .where("status = $1", .{"approved"});

// 第二层子查询
var subquery = try db.newSelect(Post);
defer subquery.deinit();

try subquery
    .column("user_id")
    .whereIn("id", sub_sub_query);

// 主查询
var users = std.ArrayList(User).init(allocator);
defer users.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .whereIn("id", subquery)
    .scan(&users);

const sql = try query.buildSQL();
defer allocator.free(sql);

// 验证嵌套子查询 SQL
try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE id IN (SELECT user_id") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE id IN (SELECT DISTINCT post_id") != null);
```

#### Scenario: 嵌套子查询参数正确合并

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var sub_sub_query = try db.newSelect(Comment);
defer sub_sub_query.deinit();

try sub_sub_query
    .column("post_id")
    .where("rating > $1", .{4});

var subquery = try db.newSelect(Post);
defer subquery.deinit();

try subquery
    .column("user_id")
    .whereIn("id", sub_sub_query)
    .where("views > $2", .{100});

var query = try db.newSelect(User);
defer query.deinit();

try query
    .whereIn("id", subquery)
    .where("age > $3", .{18});

const args = try query.collectAllArgs();
defer allocator.free(args);

// 验证参数顺序: 4, 100, 18
try std.testing.expectEqual(@as(usize, 3), args.len);
try std.testing.expectEqual(@as(i64, 4), args[0].int_val);
try std.testing.expectEqual(@as(i64, 100), args[1].int_val);
try std.testing.expectEqual(@as(i64, 18), args[2].int_val);
```

---

### Requirement: 子查询参数自动合并

主查询和子查询的参数 MUST 自动合并,占位符自动重新编号,避免参数冲突。

#### Scenario: 主查询和子查询参数合并

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var subquery = try db.newSelect(Post);
defer subquery.deinit();

try subquery
    .column("user_id")
    .where("published = $1", .{true})
    .where("views > $2", .{100});

var query = try db.newSelect(User);
defer query.deinit();

try query
    .where("age > $1", .{18})
    .whereIn("id", subquery)
    .where("is_active = $2", .{true});

// 参数应该按顺序合并: 18, true (is_active), true (published), 100
const args = try query.collectAllArgs();
defer allocator.free(args);

try std.testing.expectEqual(@as(usize, 4), args.len);
```

#### Scenario: 多个子查询参数合并

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var subquery1 = try db.newSelect(Post);
defer subquery1.deinit();

try subquery1
    .column("user_id")
    .where("status = $1", .{"published"});

var subquery2 = try db.newSelect(Comment);
defer subquery2.deinit();

try subquery2
    .column("user_id")
    .where("approved = $1", .{true});

var query = try db.newSelect(User);
defer query.deinit();

try query
    .whereIn("id", subquery1)
    .whereExists(subquery2);

const args = try query.collectAllArgs();
defer allocator.free(args);

// 验证参数收集自两个子查询
try std.testing.expectEqual(@as(usize, 2), args.len);
try std.testing.expectEqualStrings("published", args[0].string_val);
try std.testing.expectEqual(true, args[1].bool_val);
```

---

### Requirement: 子查询与其他查询子句兼容

子查询 MUST 与 JOIN、GROUP BY、HAVING、ORDER BY、LIMIT、OFFSET 等子句正确组合。

#### Scenario: 子查询与 JOIN 组合

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var subquery = try db.newSelect(Post);
defer subquery.deinit();

try subquery
    .column("DISTINCT user_id")
    .where("published = $1", .{true});

var query = try db.newSelect(User);
defer query.deinit();

try query
    .from("users AS u")
    .leftJoin("profiles AS p", "p.user_id = u.id")
    .whereIn("u.id", subquery)
    .where("p.verified = $2", .{true});

const sql = try query.buildSQL();
defer allocator.free(sql);

// 验证 JOIN 和子查询都存在
try std.testing.expect(std.mem.indexOf(u8, sql, "LEFT JOIN profiles AS p") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "u.id IN (SELECT") != null);
```

#### Scenario: 子查询与 GROUP BY、HAVING 组合

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var subquery = try db.newSelect(Post);
defer subquery.deinit();

try subquery
    .column("user_id")
    .where("views > $1", .{1000});

var query = try db.newSelect(User);
defer query.deinit();

try query
    .column("users.id")
    .column("COUNT(posts.id) AS post_count")
    .from("users")
    .leftJoin("posts", "posts.user_id = users.id")
    .whereIn("users.id", subquery)
    .groupBy("users.id")
    .having("COUNT(posts.id) > $2", .{5});

const sql = try query.buildSQL();
defer allocator.free(sql);

// 验证 SQL 结构正确
try std.testing.expect(std.mem.indexOf(u8, sql, "GROUP BY users.id") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "HAVING COUNT(posts.id) > $2") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.id IN (SELECT") != null);
```

#### Scenario: 子查询与 ORDER BY、LIMIT 组合

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var subquery = try db.newSelect(Post);
defer subquery.deinit();

try subquery
    .column("user_id")
    .where("published = $1", .{true});

var query = try db.newSelect(User);
defer query.deinit();

try query
    .whereIn("id", subquery)
    .orderBy("created_at", .desc)
    .limit(10)
    .offset(0);

const sql = try query.buildSQL();
defer allocator.free(sql);

// 验证 ORDER BY 和 LIMIT 在子查询之后
try std.testing.expect(std.mem.indexOf(u8, sql, "ORDER BY created_at DESC") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "LIMIT 10") != null);
```

---

### Requirement: 文档和示例

所有子查询 API 方法 MUST 在模块文档中提供清晰的注释和使用示例。

#### Scenario: whereIn() 方法文档示例

```zig
/// 添加 WHERE IN 子查询条件
///
/// 使用子查询结果作为 IN 操作符的值列表。
/// 子查询的参数会自动合并到主查询的参数列表中。
///
/// ## 参数
/// - `column`: 要匹配的列名
/// - `subquery`: 返回值列表的 SELECT 子查询
///
/// ## 示例
/// ```zig
/// // 查询有已发布文章的用户
/// var subquery = try db.newSelect(Post);
/// defer subquery.deinit();
///
/// try subquery
///     .column("DISTINCT user_id")
///     .where("published = $1", .{true});
///
/// var users = std.ArrayList(User).init(allocator);
/// defer users.deinit();
///
/// var query = try db.newSelect(User);
/// defer query.deinit();
///
/// try query
///     .whereIn("id", subquery)
///     .scan(&users);
/// ```
///
/// ## 注意
/// - 子查询应该返回单列值
/// - 子查询参数会自动重新编号
/// - 可以与其他 WHERE 条件组合使用
///
/// ## 参见
/// - `whereNotIn()` - WHERE NOT IN 子查询
/// - `whereExists()` - WHERE EXISTS 子查询
pub fn whereIn(
    self: *Self,
    column: []const u8,
    subquery: anytype
) !*Self {
    // Implementation...
}
```

#### Scenario: fromSubquery() 方法文档示例

```zig
/// 使用子查询作为 FROM 派生表
///
/// 将子查询的结果作为虚拟表使用,可在主查询中引用。
/// 派生表必须指定别名,用于在主查询中引用。
///
/// ## 参数
/// - `subquery`: 生成派生表的 SELECT 子查询
/// - `alias`: 派生表的别名
///
/// ## 示例
/// ```zig
/// // 从用户文章统计派生表查询
/// const UserStats = struct {
///     id: i64,
///     post_count: i64,
/// };
///
/// var derived = try db.newSelect(UserStats);
/// defer derived.deinit();
///
/// try derived
///     .column("users.id")
///     .column("COUNT(posts.id) AS post_count")
///     .from("users")
///     .leftJoin("posts", "posts.user_id = users.id")
///     .groupBy("users.id");
///
/// var results = std.ArrayList(UserStats).init(allocator);
/// defer results.deinit();
///
/// var query = try db.newSelect(UserStats);
/// defer query.deinit();
///
/// try query
///     .column("*")
///     .fromSubquery(derived, "user_stats")
///     .where("post_count > $1", .{5})
///     .scan(&results);
/// ```
///
/// ## 注意
/// - 别名必须提供且唯一
/// - 派生表的列可在主查询中通过 `alias.column` 引用
/// - 派生表与 JOIN、WHERE 等子句兼容
///
/// ## 参见
/// - `whereIn()` - WHERE IN 子查询
/// - `join()` - 表连接操作
pub fn fromSubquery(
    self: *Self,
    subquery: anytype,
    alias: []const u8
) !*Self {
    // Implementation...
}
```

