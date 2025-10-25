# select-query-join-api Specification

## Purpose
定义 SELECT 查询构建器的 JOIN 功能，支持多种 JOIN 类型（INNER、LEFT、RIGHT、FULL、CROSS），多表连接，表别名，以及 JOIN 条件中的参数绑定。

## ADDED Requirements

### Requirement: JOIN 方法基础 API

SELECT 查询构建器 MUST 提供 `join(join_type, table, condition)` 方法支持各种 JOIN 类型。

#### Scenario: 使用 join() 方法添加 INNER JOIN

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .column("u.id")
    .column("p.bio")
    .from("users AS u")
    .join(.inner, "profiles AS p", "p.user_id = u.id");

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expectEqualStrings(
    "SELECT u.id, p.bio FROM users AS u INNER JOIN profiles AS p ON p.user_id = u.id",
    sql
);
```

#### Scenario: 使用 join() 方法添加 LEFT JOIN

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .from("users AS u")
    .join(.left, "orders AS o", "o.user_id = u.id");

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "LEFT JOIN orders AS o ON o.user_id = u.id") != null);
```

#### Scenario: 支持所有 JOIN 类型

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

// INNER JOIN
var q1 = try db.newSelect(User);
defer q1.deinit();
try q1.join(.inner, "profiles", "profiles.user_id = users.id");
try std.testing.expect(std.mem.indexOf(u8, try q1.buildSQL(), "INNER JOIN") != null);

// LEFT JOIN
var q2 = try db.newSelect(User);
defer q2.deinit();
try q2.join(.left, "profiles", "profiles.user_id = users.id");
try std.testing.expect(std.mem.indexOf(u8, try q2.buildSQL(), "LEFT JOIN") != null);

// RIGHT JOIN
var q3 = try db.newSelect(User);
defer q3.deinit();
try q3.join(.right, "profiles", "profiles.user_id = users.id");
try std.testing.expect(std.mem.indexOf(u8, try q3.buildSQL(), "RIGHT JOIN") != null);

// FULL OUTER JOIN
var q4 = try db.newSelect(User);
defer q4.deinit();
try q4.join(.full, "profiles", "profiles.user_id = users.id");
try std.testing.expect(std.mem.indexOf(u8, try q4.buildSQL(), "FULL OUTER JOIN") != null);

// CROSS JOIN
var q5 = try db.newSelect(User);
defer q5.deinit();
try q5.join(.cross, "profiles", "");
try std.testing.expect(std.mem.indexOf(u8, try q5.buildSQL(), "CROSS JOIN") != null);
```

---

### Requirement: 便捷 JOIN 方法

SELECT 查询构建器 MUST 提供便捷方法 `innerJoin()`, `leftJoin()`, `rightJoin()`, `fullJoin()`, `crossJoin()` 简化常用 JOIN 操作。

#### Scenario: 使用 innerJoin() 便捷方法

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .from("users AS u")
    .innerJoin("profiles AS p", "p.user_id = u.id");

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "INNER JOIN profiles AS p ON p.user_id = u.id") != null);
```

#### Scenario: 使用 leftJoin() 便捷方法

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .from("users AS u")
    .leftJoin("orders AS o", "o.user_id = u.id");

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "LEFT JOIN orders AS o ON o.user_id = u.id") != null);
```

#### Scenario: crossJoin() 不需要条件参数

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .from("users")
    .crossJoin("categories");

const sql = try query.buildSQL();
defer allocator.free(sql);

// CROSS JOIN 不应该有 ON 子句
try std.testing.expect(std.mem.indexOf(u8, sql, "CROSS JOIN categories") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, " ON ") == null or
                        std.mem.indexOf(u8, sql, "CROSS JOIN categories ON") == null);
```

---

### Requirement: 多个 JOIN 链式调用

SELECT 查询构建器 MUST 支持多次调用 JOIN 方法，实现多表连接。

#### Scenario: 链式调用多个 JOIN

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .column("u.id")
    .column("p.bio")
    .column("o.total")
    .from("users AS u")
    .leftJoin("profiles AS p", "p.user_id = u.id")
    .leftJoin("orders AS o", "o.user_id = u.id")
    .where("u.is_active = $1", .{true});

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "LEFT JOIN profiles AS p ON p.user_id = u.id") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "LEFT JOIN orders AS o ON o.user_id = u.id") != null);
```

#### Scenario: 混合不同 JOIN 类型

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .from("users AS u")
    .innerJoin("profiles AS p", "p.user_id = u.id")
    .leftJoin("orders AS o", "o.user_id = u.id")
    .rightJoin("payments AS pay", "pay.order_id = o.id");

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "INNER JOIN profiles") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "LEFT JOIN orders") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "RIGHT JOIN payments") != null);
```

---

### Requirement: 表别名支持

SELECT 查询构建器 MUST 支持在 FROM 和 JOIN 子句中使用表别名（如 `users AS u`）。

#### Scenario: 使用表别名简化列引用

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .column("u.id AS user_id")
    .column("u.name AS user_name")
    .column("p.bio AS profile_bio")
    .from("users AS u")
    .leftJoin("profiles AS p", "p.user_id = u.id");

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expectEqualStrings(
    "SELECT u.id AS user_id, u.name AS user_name, p.bio AS profile_bio FROM users AS u LEFT JOIN profiles AS p ON p.user_id = u.id",
    sql
);
```

#### Scenario: 表别名在 WHERE 子句中使用

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .from("users AS u")
    .leftJoin("profiles AS p", "p.user_id = u.id")
    .where("u.age > $1", .{18})
    .where("p.bio IS NOT NULL", .{});

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE u.age > $1 AND p.bio IS NOT NULL") != null);
```

---

### Requirement: JOIN 条件中的参数绑定

JOIN 条件 MUST 支持参数绑定占位符（如 `$1`, `$2`），参数通过 WHERE 子句的 args 收集。

#### Scenario: JOIN 条件中使用参数绑定

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

// JOIN 条件中的参数需要在 WHERE 中提供
try query
    .from("users AS u")
    .innerJoin("orders AS o", "o.user_id = u.id AND o.status = $1")
    .where("u.age > $2", .{"completed", 18});

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "o.status = $1") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "u.age > $2") != null);
```

#### Scenario: 多个 JOIN 条件参数绑定

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .from("users AS u")
    .innerJoin("orders AS o", "o.user_id = u.id AND o.status = $1")
    .leftJoin("payments AS p", "p.order_id = o.id AND p.method = $2")
    .where("u.created_at > $3", .{"completed", "credit_card", @as(i64, 1609459200)});

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "o.status = $1") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "p.method = $2") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "u.created_at > $3") != null);
```

---

### Requirement: JOIN 结果扫描到自定义结构体

JOIN 查询结果 MUST 能够扫描到包含多表字段的自定义 Zig 结构体。

#### Scenario: JOIN 结果映射到自定义结构体

```zig
const allocator = std.testing.allocator;
const db = try createRealDB(allocator);
defer db.deinit();

const UserWithProfile = struct {
    user_id: i64,
    user_name: []const u8,
    user_email: []const u8,
    profile_bio: ?[]const u8,
    profile_avatar: ?[]const u8,
};

// 准备测试数据
try db.exec("CREATE TABLE IF NOT EXISTS users (id BIGSERIAL PRIMARY KEY, name TEXT, email TEXT, is_active BOOLEAN)", .{});
try db.exec("CREATE TABLE IF NOT EXISTS profiles (id BIGSERIAL PRIMARY KEY, user_id BIGINT, bio TEXT, avatar TEXT)", .{});
try db.exec("INSERT INTO users (name, email, is_active) VALUES ($1, $2, $3)", .{"Alice", "alice@example.com", true});
try db.exec("INSERT INTO profiles (user_id, bio, avatar) VALUES ($1, $2, $3)", .{1, "Software Engineer", "avatar.png"});

var results = std.ArrayList(UserWithProfile).init(allocator);
defer results.deinit();

var query = try db.newSelect(UserWithProfile);
defer query.deinit();

try query
    .column("u.id AS user_id")
    .column("u.name AS user_name")
    .column("u.email AS user_email")
    .column("p.bio AS profile_bio")
    .column("p.avatar AS profile_avatar")
    .from("users AS u")
    .leftJoin("profiles AS p", "p.user_id = u.id")
    .where("u.is_active = $1", .{true})
    .scan(&results);

try std.testing.expectEqual(@as(usize, 1), results.items.len);
try std.testing.expectEqual(@as(i64, 1), results.items[0].user_id);
try std.testing.expectEqualStrings("Alice", results.items[0].user_name);
try std.testing.expectEqualStrings("Software Engineer", results.items[0].profile_bio.?);
```

#### Scenario: LEFT JOIN 结果包含 NULL 值

```zig
const allocator = std.testing.allocator;
const db = try createRealDB(allocator);
defer db.deinit();

const UserWithProfile = struct {
    user_id: i64,
    user_name: []const u8,
    profile_bio: ?[]const u8,
};

// 准备测试数据：用户无 profile
try db.exec("INSERT INTO users (name, email, is_active) VALUES ($1, $2, $3)", .{"Bob", "bob@example.com", true});

var results = std.ArrayList(UserWithProfile).init(allocator);
defer results.deinit();

var query = try db.newSelect(UserWithProfile);
defer query.deinit();

try query
    .column("u.id AS user_id")
    .column("u.name AS user_name")
    .column("p.bio AS profile_bio")
    .from("users AS u")
    .leftJoin("profiles AS p", "p.user_id = u.id")
    .where("u.name = $1", .{"Bob"})
    .scan(&results);

try std.testing.expectEqual(@as(usize, 1), results.items.len);
try std.testing.expectEqualStrings("Bob", results.items[0].user_name);
try std.testing.expectEqual(@as(?[]const u8, null), results.items[0].profile_bio);
```

---

### Requirement: JOIN 与其他子句兼容

JOIN 子句 MUST 与 WHERE、GROUP BY、HAVING、ORDER BY、LIMIT、OFFSET 等子句正确组合。

#### Scenario: JOIN 与 WHERE 组合

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .from("users AS u")
    .leftJoin("profiles AS p", "p.user_id = u.id")
    .where("u.is_active = $1", .{true})
    .where("p.bio IS NOT NULL", .{});

const sql = try query.buildSQL();
defer allocator.free(sql);

// JOIN 应该在 WHERE 之前
const join_pos = std.mem.indexOf(u8, sql, "LEFT JOIN");
const where_pos = std.mem.indexOf(u8, sql, "WHERE");
try std.testing.expect(join_pos.? < where_pos.?);
```

#### Scenario: JOIN 与 ORDER BY、LIMIT 组合

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .column("u.id")
    .column("p.bio")
    .from("users AS u")
    .leftJoin("profiles AS p", "p.user_id = u.id")
    .orderBy("u.created_at", .desc)
    .limit(10);

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "LEFT JOIN profiles AS p") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "ORDER BY u.created_at DESC") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "LIMIT 10") != null);
```

#### Scenario: JOIN 与 GROUP BY、HAVING 组合

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query
    .column("u.id")
    .column("COUNT(o.id) AS order_count")
    .from("users AS u")
    .leftJoin("orders AS o", "o.user_id = u.id")
    .groupBy("u.id")
    .having("COUNT(o.id) > $1", .{5});

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "LEFT JOIN orders AS o") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "GROUP BY u.id") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "HAVING COUNT(o.id) > $1") != null);
```

---

### Requirement: 集成测试覆盖

所有 JOIN 功能 MUST 通过集成测试验证，确保在真实 PostgreSQL 数据库环境下正常工作。

#### Scenario: INNER JOIN 集成测试

```zig
test "INNER JOIN integration test" {
    const allocator = std.testing.allocator;
    const db = try createRealDB(allocator);
    defer db.deinit();

    // 准备测试数据
    try db.exec("CREATE TABLE IF NOT EXISTS users (id BIGSERIAL PRIMARY KEY, name TEXT)", .{});
    try db.exec("CREATE TABLE IF NOT EXISTS profiles (id BIGSERIAL PRIMARY KEY, user_id BIGINT, bio TEXT)", .{});
    try db.exec("INSERT INTO users (name) VALUES ('Alice'), ('Bob')", .{});
    try db.exec("INSERT INTO profiles (user_id, bio) VALUES (1, 'Engineer')", .{});

    const Result = struct {
        user_id: i64,
        user_name: []const u8,
        profile_bio: []const u8,
    };

    var results = std.ArrayList(Result).init(allocator);
    defer results.deinit();

    var query = try db.newSelect(Result);
    defer query.deinit();

    try query
        .column("u.id AS user_id")
        .column("u.name AS user_name")
        .column("p.bio AS profile_bio")
        .from("users AS u")
        .innerJoin("profiles AS p", "p.user_id = u.id")
        .scan(&results);

    // INNER JOIN 只返回有匹配的行
    try std.testing.expectEqual(@as(usize, 1), results.items.len);
    try std.testing.expectEqualStrings("Alice", results.items[0].user_name);
}
```

#### Scenario: LEFT JOIN 集成测试

```zig
test "LEFT JOIN integration test" {
    const allocator = std.testing.allocator;
    const db = try createRealDB(allocator);
    defer db.deinit();

    const Result = struct {
        user_id: i64,
        user_name: []const u8,
        profile_bio: ?[]const u8,
    };

    var results = std.ArrayList(Result).init(allocator);
    defer results.deinit();

    var query = try db.newSelect(Result);
    defer query.deinit();

    try query
        .column("u.id AS user_id")
        .column("u.name AS user_name")
        .column("p.bio AS profile_bio")
        .from("users AS u")
        .leftJoin("profiles AS p", "p.user_id = u.id")
        .scan(&results);

    // LEFT JOIN 返回所有左表行，包括无匹配的
    try std.testing.expectEqual(@as(usize, 2), results.items.len);

    // Bob 没有 profile，bio 应该是 NULL
    const bob = results.items[1];
    try std.testing.expectEqualStrings("Bob", bob.user_name);
    try std.testing.expectEqual(@as(?[]const u8, null), bob.profile_bio);
}
```

---

### Requirement: 文档和示例

所有 JOIN API 方法 MUST 在模块文档中提供清晰的注释和使用示例。

#### Scenario: join() 方法文档示例

```zig
/// 添加 JOIN 子句到查询
///
/// 支持多种 JOIN 类型：INNER、LEFT、RIGHT、FULL、CROSS。
/// 可以多次调用以实现多表连接。
///
/// ## 参数
/// - `join_type`: JOIN 类型枚举
/// - `table`: 要连接的表名（可包含别名，如 "profiles AS p"）
/// - `condition`: JOIN 条件（如 "p.user_id = u.id"）
///
/// ## 示例
/// ```zig
/// var query = try db.newSelect(User);
/// defer query.deinit();
///
/// try query
///     .from("users AS u")
///     .join(.left, "profiles AS p", "p.user_id = u.id")
///     .where("u.is_active = $1", .{true});
/// ```
///
/// ## 注意
/// - CROSS JOIN 不需要 ON 条件，condition 参数可为空字符串
/// - JOIN 条件中可使用参数绑定占位符（$1, $2, ...）
/// - 表别名有助于简化复杂查询的列引用
///
/// ## 参见
/// - `innerJoin()` - INNER JOIN 便捷方法
/// - `leftJoin()` - LEFT JOIN 便捷方法
pub fn join(self: *Self, join_type: JoinType, table: []const u8, condition: []const u8) !*Self {
    const clause = JoinClause{
        .join_type = join_type,
        .table = table,
        .condition = condition,
    };
    try self.join_clauses.append(self.allocator, clause);
    return self;
}
```
