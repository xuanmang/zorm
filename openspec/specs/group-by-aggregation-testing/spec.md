# group-by-aggregation-testing Specification

## Purpose
TBD - created by archiving change enhance-group-by-aggregation-testing. Update Purpose after archive.
## Requirements
### Requirement: 基础聚合函数测试(COUNT, SUM, AVG, MAX, MIN)

SELECT 查询构建器 MUST 支持所有标准 SQL 聚合函数,并通过测试验证 SQL 生成和实际查询结果的正确性。

#### Scenario: COUNT 聚合函数测试

```zig
test "SelectQuery: COUNT aggregation" {
    const allocator = std.testing.allocator;
    const db = try createTestDB(allocator);
    defer db.deinit();

    var query = try db.newSelect(User);
    defer query.deinit();

    try query
        .column("department")
        .column("COUNT(*) as user_count")
        .groupBy("department");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try std.testing.expectEqualStrings(
        "SELECT department, COUNT(*) as user_count FROM users GROUP BY department",
        sql
    );
}
```

#### Scenario: SUM 聚合函数测试

```zig
test "SelectQuery: SUM aggregation" {
    const allocator = std.testing.allocator;
    const db = try createTestDB(allocator);
    defer db.deinit();

    var query = try db.newSelect(Order);
    defer query.deinit();

    try query
        .column("user_id")
        .column("SUM(amount) as total_amount")
        .groupBy("user_id")
        .having("SUM(amount) > $1", .{1000});

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "SUM(amount) as total_amount") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "GROUP BY user_id") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "HAVING SUM(amount) > $1") != null);
}
```

#### Scenario: AVG 聚合函数测试

```zig
test "SelectQuery: AVG aggregation" {
    const allocator = std.testing.allocator;
    const db = try createTestDB(allocator);
    defer db.deinit();

    var query = try db.newSelect(Post);
    defer query.deinit();

    try query
        .column("user_id")
        .column("AVG(view_count) as avg_views")
        .groupBy("user_id");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "AVG(view_count) as avg_views") != null);
}
```

#### Scenario: MAX 和 MIN 聚合函数测试

```zig
test "SelectQuery: MAX and MIN aggregation" {
    const allocator = std.testing.allocator;
    const db = try createTestDB(allocator);
    defer db.deinit();

    var query = try db.newSelect(Product);
    defer query.deinit();

    try query
        .column("category")
        .column("MAX(price) as max_price")
        .column("MIN(price) as min_price")
        .groupBy("category");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "MAX(price) as max_price") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "MIN(price) as min_price") != null);
}
```

---

### Requirement: DISTINCT 聚合测试

聚合函数 MUST 支持 DISTINCT 关键字,用于去重统计,如 `COUNT(DISTINCT column)`。

#### Scenario: COUNT(DISTINCT column) 测试

```zig
test "SelectQuery: COUNT DISTINCT aggregation" {
    const allocator = std.testing.allocator;
    const db = try createTestDB(allocator);
    defer db.deinit();

    var query = try db.newSelect(Order);
    defer query.deinit();

    try query
        .column("DATE(created_at) as order_date")
        .column("COUNT(DISTINCT user_id) as unique_users")
        .groupBy("DATE(created_at)");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "COUNT(DISTINCT user_id) as unique_users") != null);
}
```

#### Scenario: 多个 DISTINCT 聚合

```zig
test "SelectQuery: multiple DISTINCT aggregations" {
    const allocator = std.testing.allocator;
    const db = try createTestDB(allocator);
    defer db.deinit();

    var query = try db.newSelect(Order);
    defer query.deinit();

    try query
        .column("category")
        .column("COUNT(DISTINCT user_id) as unique_users")
        .column("COUNT(DISTINCT product_id) as unique_products")
        .groupBy("category");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "COUNT(DISTINCT user_id)") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "COUNT(DISTINCT product_id)") != null);
}
```

---

### Requirement: 多列 GROUP BY 测试

GROUP BY 子句 MUST 支持两种多列分组方式:单次调用传入逗号分隔的列,或多次调用链式添加列。

#### Scenario: 单次调用多列 GROUP BY

```zig
test "SelectQuery: multi-column GROUP BY (single call)" {
    const allocator = std.testing.allocator;
    const db = try createTestDB(allocator);
    defer db.deinit();

    var query = try db.newSelect(Order);
    defer query.deinit();

    try query
        .column("user_id")
        .column("product_id")
        .column("COUNT(*) as order_count")
        .groupBy("user_id, product_id");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try std.testing.expectEqualStrings(
        "SELECT user_id, product_id, COUNT(*) as order_count FROM orders GROUP BY user_id, product_id",
        sql
    );
}
```

#### Scenario: 多次调用链式 GROUP BY

```zig
test "SelectQuery: multi-column GROUP BY (chained calls)" {
    const allocator = std.testing.allocator;
    const db = try createTestDB(allocator);
    defer db.deinit();

    var query = try db.newSelect(Order);
    defer query.deinit();

    try query
        .column("user_id")
        .column("product_id")
        .column("COUNT(*) as order_count")
        .groupBy("user_id")
        .groupBy("product_id");

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try std.testing.expectEqualStrings(
        "SELECT user_id, product_id, COUNT(*) as order_count FROM orders GROUP BY user_id, product_id",
        sql
    );
}
```

---

### Requirement: 聚合结果映射到自定义结构体(集成测试)

聚合查询结果 MUST 能够正确扫描到包含聚合字段的自定义 Zig 结构体,并通过集成测试验证实际数据库行为。

#### Scenario: 基础聚合结果映射

```zig
test "Integration: aggregate result mapping to struct" {
    const allocator = std.testing.allocator;
    const db = try createRealDB(allocator);
    defer db.deinit();

    // 定义聚合结果结构体
    const UserStats = struct {
        user_id: i64,
        post_count: i64,
        total_views: i64,
        avg_views: f64,
    };

    // 准备测试数据
    try db.exec(
        \\CREATE TABLE IF NOT EXISTS users (
        \\  id BIGSERIAL PRIMARY KEY,
        \\  name TEXT NOT NULL
        \\)
    , .{});

    try db.exec(
        \\CREATE TABLE IF NOT EXISTS posts (
        \\  id BIGSERIAL PRIMARY KEY,
        \\  user_id BIGINT NOT NULL,
        \\  view_count INTEGER NOT NULL
        \\)
    , .{});

    try db.exec("INSERT INTO users (id, name) VALUES (1, 'Alice'), (2, 'Bob')", .{});
    try db.exec(
        "INSERT INTO posts (user_id, view_count) VALUES (1, 100), (1, 200), (2, 150)",
        .{}
    );

    // 执行聚合查询
    var stats = std.ArrayList(UserStats).init(allocator);
    defer stats.deinit();

    var query = try db.newSelect(UserStats);
    defer query.deinit();

    try query
        .column("user_id")
        .column("COUNT(*) as post_count")
        .column("SUM(view_count) as total_views")
        .column("AVG(view_count) as avg_views")
        .from("posts")
        .groupBy("user_id")
        .orderBy("user_id", .asc)
        .scan(&stats);

    // 验证结果
    try std.testing.expectEqual(@as(usize, 2), stats.items.len);

    // Alice: 2 篇文章,总浏览量 300,平均 150
    try std.testing.expectEqual(@as(i64, 1), stats.items[0].user_id);
    try std.testing.expectEqual(@as(i64, 2), stats.items[0].post_count);
    try std.testing.expectEqual(@as(i64, 300), stats.items[0].total_views);
    try std.testing.expectApproxEqAbs(@as(f64, 150.0), stats.items[0].avg_views, 0.01);

    // Bob: 1 篇文章,总浏览量 150,平均 150
    try std.testing.expectEqual(@as(i64, 2), stats.items[1].user_id);
    try std.testing.expectEqual(@as(i64, 1), stats.items[1].post_count);
    try std.testing.expectEqual(@as(i64, 150), stats.items[1].total_views);
    try std.testing.expectApproxEqAbs(@as(f64, 150.0), stats.items[1].avg_views, 0.01);
}
```

#### Scenario: 复杂聚合结果映射(包含 NULL 值)

```zig
test "Integration: aggregate with NULL values" {
    const allocator = std.testing.allocator;
    const db = try createRealDB(allocator);
    defer db.deinit();

    const CategoryStats = struct {
        category: []const u8,
        product_count: i64,
        max_price: ?f64,  // 可能为 NULL
        min_price: ?f64,
        avg_price: ?f64,
    };

    // 准备测试数据
    try db.exec(
        \\CREATE TABLE IF NOT EXISTS products (
        \\  id BIGSERIAL PRIMARY KEY,
        \\  category TEXT NOT NULL,
        \\  price DECIMAL(10, 2)
        \\)
    , .{});

    try db.exec(
        "INSERT INTO products (category, price) VALUES ('Electronics', 99.99), ('Electronics', 199.99), ('Books', NULL)",
        .{}
    );

    var stats = std.ArrayList(CategoryStats).init(allocator);
    defer stats.deinit();

    var query = try db.newSelect(CategoryStats);
    defer query.deinit();

    try query
        .column("category")
        .column("COUNT(*) as product_count")
        .column("MAX(price) as max_price")
        .column("MIN(price) as min_price")
        .column("AVG(price) as avg_price")
        .from("products")
        .groupBy("category")
        .orderBy("category", .asc)
        .scan(&stats);

    try std.testing.expectEqual(@as(usize, 2), stats.items.len);

    // Books: 1 个产品,价格都是 NULL
    const books = stats.items[0];
    try std.testing.expectEqualStrings("Books", books.category);
    try std.testing.expectEqual(@as(i64, 1), books.product_count);
    try std.testing.expectEqual(@as(?f64, null), books.max_price);
    try std.testing.expectEqual(@as(?f64, null), books.min_price);
    try std.testing.expectEqual(@as(?f64, null), books.avg_price);

    // Electronics: 2 个产品,有有效价格
    const electronics = stats.items[1];
    try std.testing.expectEqualStrings("Electronics", electronics.category);
    try std.testing.expectEqual(@as(i64, 2), electronics.product_count);
    try std.testing.expectApproxEqAbs(@as(f64, 199.99), electronics.max_price.?, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 99.99), electronics.min_price.?, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 149.99), electronics.avg_price.?, 0.01);
}
```

---

### Requirement: JOIN + GROUP BY + HAVING 组合场景测试

聚合查询 MUST 支持与 JOIN 和 HAVING 子句的组合使用,并通过集成测试验证复杂查询场景。

#### Scenario: JOIN 与 GROUP BY 组合(SQL 生成)

```zig
test "SelectQuery: JOIN with GROUP BY" {
    const allocator = std.testing.allocator;
    const db = try createTestDB(allocator);
    defer db.deinit();

    var query = try db.newSelect(User);
    defer query.deinit();

    try query
        .column("u.id")
        .column("u.name")
        .column("COUNT(p.id) as post_count")
        .from("users AS u")
        .leftJoin("posts AS p", "p.user_id = u.id")
        .groupBy("u.id, u.name")
        .orderBy("post_count", .desc);

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "LEFT JOIN posts AS p ON p.user_id = u.id") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "GROUP BY u.id, u.name") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "COUNT(p.id) as post_count") != null);
}
```

#### Scenario: JOIN + GROUP BY + HAVING 完整组合(集成测试)

```zig
test "Integration: JOIN with GROUP BY and HAVING" {
    const allocator = std.testing.allocator;
    const db = try createRealDB(allocator);
    defer db.deinit();

    const UserWithStats = struct {
        user_id: i64,
        user_name: []const u8,
        post_count: i64,
        total_views: i64,
        avg_views: f64,
    };

    // 准备测试数据
    try db.exec("TRUNCATE TABLE users CASCADE", .{});
    try db.exec("TRUNCATE TABLE posts CASCADE", .{});

    try db.exec(
        "INSERT INTO users (id, name) VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Carol')",
        .{}
    );

    try db.exec(
        \\INSERT INTO posts (user_id, view_count) VALUES
        \\  (1, 100), (1, 200), (1, 300),
        \\  (2, 50), (2, 60),
        \\  (3, 1000), (3, 2000), (3, 3000), (3, 4000), (3, 5000)
    , .{});

    var stats = std.ArrayList(UserWithStats).init(allocator);
    defer stats.deinit();

    var query = try db.newSelect(UserWithStats);
    defer query.deinit();

    try query
        .column("u.id AS user_id")
        .column("u.name AS user_name")
        .column("COUNT(p.id) AS post_count")
        .column("SUM(p.view_count) AS total_views")
        .column("AVG(p.view_count) AS avg_views")
        .from("users AS u")
        .leftJoin("posts AS p", "p.user_id = u.id")
        .groupBy("u.id, u.name")
        .having("COUNT(p.id) > $1", .{2})
        .orderBy("total_views", .desc)
        .scan(&stats);

    // 只有 Alice 和 Carol 有超过 2 篇文章
    try std.testing.expectEqual(@as(usize, 2), stats.items.len);

    // Carol: 5 篇文章,总浏览量最高
    try std.testing.expectEqualStrings("Carol", stats.items[0].user_name);
    try std.testing.expectEqual(@as(i64, 5), stats.items[0].post_count);
    try std.testing.expectEqual(@as(i64, 15000), stats.items[0].total_views);

    // Alice: 3 篇文章
    try std.testing.expectEqualStrings("Alice", stats.items[1].user_name);
    try std.testing.expectEqual(@as(i64, 3), stats.items[1].post_count);
    try std.testing.expectEqual(@as(i64, 600), stats.items[1].total_views);
}
```

---

### Requirement: 文档和示例完善

所有聚合功能 MUST 在模块文档中提供清晰的注释和完整的使用示例,对齐 PRD Story 4.3 的示例代码。

#### Scenario: groupBy() 方法文档更新

```zig
/// 添加 GROUP BY 子句到查询
///
/// 支持两种多列分组方式:
/// 1. 单次调用传入逗号分隔的列: `groupBy("col1, col2")`
/// 2. 多次调用链式添加: `groupBy("col1").groupBy("col2")`
///
/// ## 参数
/// - `column`: 列名或逗号分隔的多列名
///
/// ## 示例
///
/// ### 基础分组
/// ```zig
/// var query = try db.newSelect(User);
/// defer query.deinit();
///
/// try query
///     .column("department")
///     .column("COUNT(*) as user_count")
///     .groupBy("department");
/// ```
///
/// ### 多列分组(单次调用)
/// ```zig
/// try query
///     .column("department")
///     .column("role")
///     .column("COUNT(*) as count")
///     .groupBy("department, role");
/// ```
///
/// ### 多列分组(链式调用)
/// ```zig
/// try query
///     .groupBy("department")
///     .groupBy("role");
/// // 等价于: groupBy("department, role")
/// ```
///
/// ### 与聚合函数配合
/// ```zig
/// const UserStats = struct {
///     user_id: i64,
///     post_count: i64,
///     total_views: i64,
///     avg_views: f64,
/// };
///
/// var stats = std.ArrayList(UserStats).init(allocator);
/// defer stats.deinit();
///
/// var query = try db.newSelect(UserStats);
/// defer query.deinit();
///
/// try query
///     .column("user_id")
///     .column("COUNT(*) as post_count")
///     .column("SUM(view_count) as total_views")
///     .column("AVG(view_count) as avg_views")
///     .from("posts")
///     .groupBy("user_id")
///     .having("COUNT(*) > $1", .{5})
///     .scan(&stats);
/// ```
///
/// ## 注意
/// - 非聚合列必须出现在 GROUP BY 子句中
/// - 聚合函数(COUNT, SUM, AVG, MAX, MIN)不能出现在 GROUP BY 中
/// - 支持表达式分组,如 `DATE(created_at)`
///
/// ## 参见
/// - `having()` - 添加 HAVING 条件过滤分组结果
/// - `column()` - 添加聚合函数表达式
pub fn groupBy(self: *Self, col: []const u8) !*Self {
    try self.group_by_columns.append(self.allocator, col);
    return self;
}
```

#### Scenario: 聚合查询完整示例

```zig
/// 聚合查询完整示例
///
/// 本示例演示如何使用 ZORM 进行复杂的聚合统计查询,
/// 包括 JOIN、GROUP BY、HAVING 和多种聚合函数的组合使用。
///
test "Example: comprehensive aggregation query" {
    const allocator = std.testing.allocator;
    const db = try createRealDB(allocator);
    defer db.deinit();

    // 定义聚合结果结构体
    const UserStats = struct {
        user_id: i64,
        user_name: []const u8,
        post_count: i64,
        total_views: i64,
        avg_views: f64,
        max_views: i64,
        min_views: i64,
    };

    var stats = std.ArrayList(UserStats).init(allocator);
    defer stats.deinit();

    // 构建聚合查询
    var query = try db.newSelect(UserStats);
    defer query.deinit();

    try query
        .column("u.id AS user_id")
        .column("u.name AS user_name")
        .column("COUNT(p.id) AS post_count")
        .column("SUM(p.view_count) AS total_views")
        .column("AVG(p.view_count) AS avg_views")
        .column("MAX(p.view_count) AS max_views")
        .column("MIN(p.view_count) AS min_views")
        .from("users AS u")
        .leftJoin("posts AS p", "p.user_id = u.id")
        .groupBy("u.id, u.name")
        .having("COUNT(p.id) > $1", .{5})
        .orderBy("total_views", .desc)
        .scan(&stats);

    // 处理结果
    for (stats.items) |stat| {
        std.debug.print("User: {s}\n", .{stat.user_name});
        std.debug.print("  Posts: {d}\n", .{stat.post_count});
        std.debug.print("  Total Views: {d}\n", .{stat.total_views});
        std.debug.print("  Avg Views: {d:.2}\n", .{stat.avg_views});
        std.debug.print("  Max Views: {d}\n", .{stat.max_views});
        std.debug.print("  Min Views: {d}\n", .{stat.min_views});
    }
}
```

