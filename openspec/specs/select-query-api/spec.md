# select-query-api Specification

## Purpose
TBD - created by archiving change complete-select-query-builder. Update Purpose after archive.
## Requirements
### Requirement: buildSQL() 方法别名

SELECT 查询构建器 MUST 提供 `buildSQL()` 方法作为 `build(null)` 的别名，以符合功能规格 2.2.1 的定义。

#### Scenario: 使用 buildSQL() 构建 SQL

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query.where("age > $1", .{18});

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expectEqualStrings("SELECT * FROM users WHERE age > $1", sql);
```

#### Scenario: buildSQL() 与 build(null) 等价

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query.where("age > $1", .{18}).orderBy("id", .asc);

const sql1 = try query.build(null);
defer allocator.free(sql1);

const sql2 = try query.buildSQL();
defer allocator.free(sql2);

try std.testing.expectEqualStrings(sql1, sql2);
```

#### Scenario: 向后兼容 build() 方法

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var ctx = QueryContext.init(allocator);
defer ctx.deinit();

var query = try db.newSelect(User);
defer query.deinit();

// 使用自定义 allocator（现有功能保持不变）
const sql = try query.build(ctx.allocator());
defer ctx.allocator().free(sql);

try std.testing.expect(sql.len > 0);
```

---

### Requirement: allColumns() Comptime 反射

SELECT 查询构建器 MUST 提供 `allColumns()` 方法，使用 comptime 反射自动获取模型类型的所有字段名并添加到列列表。

#### Scenario: 自动选择所有列

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: u32,
};

var query = try db.newSelect(User);
defer query.deinit();

try query.allColumns();

const sql = try query.buildSQL();
defer allocator.free(sql);

try std.testing.expectEqualStrings(
    "SELECT id, name, email, age FROM User",
    sql
);
```

#### Scenario: allColumns() 追加到现有列

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

const User = struct {
    id: i64,
    name: []const u8,
};

var query = try db.newSelect(User);
defer query.deinit();

try query.column("COUNT(*) as count")
    .allColumns()
    .column("created_at");

try std.testing.expectEqual(@as(usize, 4), query.columns.items.len);
try std.testing.expectEqualStrings("COUNT(*) as count", query.columns.items[0]);
try std.testing.expectEqualStrings("id", query.columns.items[1]);
try std.testing.expectEqualStrings("name", query.columns.items[2]);
try std.testing.expectEqualStrings("created_at", query.columns.items[3]);
```

#### Scenario: allColumns() 编译时展开

```zig
// allColumns() 使用 inline for 在编译时展开
// 生成的代码等价于：
// try query.column("id");
// try query.column("name");
// try query.column("email");
// try query.column("age");

// 验证：编译后的二进制不包含运行时反射代码
const User = struct {
    id: i64,
    name: []const u8,
};

var query = try db.newSelect(User);
defer query.deinit();

// 这行代码在编译时完全展开，无运行时开销
try query.allColumns();
```

---

### Requirement: collectArgs() 参数收集

SELECT 查询构建器 MUST 实现内部方法 `collectArgs()`，用于收集 WHERE 和 HAVING 子句中的所有查询参数。

#### Scenario: 收集 WHERE 子句参数

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query.where("age > $1", .{18});
try query.where("status = $2", .{"active"});

// collectArgs() 是内部方法，在 scan/scanOne/count 中调用
const args = try query.collectArgs();
defer allocator.free(args);

try std.testing.expectEqual(@as(usize, 2), args.len);
try std.testing.expectEqual(@as(i64, 18), args[0].int);
try std.testing.expectEqualStrings("active", args[1].string);
```

#### Scenario: 收集 WHERE 和 HAVING 参数

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query.where("age > $1", .{18});
try query.groupBy("role");
try query.having("COUNT(*) > $2", .{5});

const args = try query.collectArgs();
defer allocator.free(args);

try std.testing.expectEqual(@as(usize, 2), args.len);
try std.testing.expectEqual(@as(i64, 18), args[0].int);
try std.testing.expectEqual(@as(i64, 5), args[1].int);
```

#### Scenario: 参数顺序保持一致

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

// 参数按添加顺序收集
try query.where("a = $1", .{1});
try query.whereOr("b = $2", .{2});
try query.where("c = $3", .{3});
try query.having("d > $4", .{4});

const args = try query.collectArgs();
defer allocator.free(args);

try std.testing.expectEqual(@as(usize, 4), args.len);
try std.testing.expectEqual(@as(i64, 1), args[0].int);
try std.testing.expectEqual(@as(i64, 2), args[1].int);
try std.testing.expectEqual(@as(i64, 3), args[2].int);
try std.testing.expectEqual(@as(i64, 4), args[3].int);
```

---

### Requirement: 集成测试覆盖

所有新增的 API 方法 MUST 通过集成测试验证，确保与数据库驱动正确协作。

#### Scenario: allColumns() 与实际数据库查询

```zig
const allocator = std.testing.allocator;
const db = try createRealDB(allocator);
defer db.deinit();

const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: u32,
};

var query = try db.newSelect(User);
defer query.deinit();

const users = try query
    .allColumns()
    .where("age > $1", .{18})
    .orderBy("id", .asc)
    .limit(5)
    .scan();
defer allocator.free(users);

try std.testing.expect(users.len <= 5);
for (users) |user| {
    try std.testing.expect(user.age > 18);
}
```

#### Scenario: buildSQL() 生成的 SQL 可执行

```zig
const allocator = std.testing.allocator;
const db = try createRealDB(allocator);
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query.where("age > $1", .{18});

const sql = try query.buildSQL();
defer allocator.free(sql);

// 验证生成的 SQL 可以被数据库执行
const result = try db.driver.exec(sql, &[_]QueryArg{.{ .int = 18 }});
defer result.deinit();

try std.testing.expect(result.rows_affected >= 0);
```

---

### Requirement: 文档和示例

所有新增的 API 方法 MUST 在模块文档中提供清晰的注释和使用示例。

#### Scenario: buildSQL() 文档示例

```zig
/// 构建 SQL 语句（使用默认 allocator）
///
/// 这是 `build(null)` 的便捷别名，符合功能规格 2.2.1 的定义。
///
/// ## 示例
/// ```zig
/// var query = try db.newSelect(User);
/// defer query.deinit();
///
/// const sql = try query.where("age > $1", .{18}).buildSQL();
/// defer db.allocator.free(sql);
///
/// std.debug.print("SQL: {s}\n", .{sql});
/// // 输出: SQL: SELECT * FROM users WHERE age > $1
/// ```
///
/// ## 参见
/// - `build()` - 支持自定义 allocator 的完整版本
pub fn buildSQL(self: *Self) ![]const u8 {
    return self.build(null);
}
```

#### Scenario: allColumns() 文档示例

```zig
/// 自动选择模型的所有字段（comptime 反射）
///
/// 使用编译时反射遍历模型类型的所有字段，并将字段名添加到列列表。
/// 此方法在编译时完全展开，无运行时反射开销。
///
/// ## 示例
/// ```zig
/// const User = struct {
///     id: i64,
///     name: []const u8,
///     email: []const u8,
/// };
///
/// var query = try db.newSelect(User);
/// defer query.deinit();
///
/// // 自动添加 id, name, email 列
/// try query.allColumns();
///
/// const sql = try query.buildSQL();
/// // 生成: SELECT id, name, email FROM users
/// ```
///
/// ## 注意
/// - 字段按结构体定义顺序添加
/// - 追加到现有列列表（不会清空）
/// - 可以与 `column()` 混合使用
///
/// ## 参见
/// - `column()` - 手动选择单个列
pub fn allColumns(self: *Self) !*Self {
    const fields = @typeInfo(T).Struct.fields;
    inline for (fields) |field| {
        try self.columns.append(self.allocator, field.name);
    }
    return self;
}
```

---

### Requirement: 性能基准测试

新增的 API 方法 MUST 通过性能基准测试验证零运行时开销的承诺。

#### Scenario: allColumns() 无运行时反射开销

```zig
test "allColumns performance benchmark" {
    const allocator = std.testing.allocator;
    const db = try createTestDB(allocator);
    defer db.deinit();

    const User = struct {
        id: i64,
        name: []const u8,
        email: []const u8,
        age: u32,
        created_at: i64,
        updated_at: i64,
    };

    var timer = try std.time.Timer.start();

    // 使用 allColumns()
    const start1 = timer.read();
    var query1 = try db.newSelect(User);
    defer query1.deinit();
    try query1.allColumns();
    const end1 = timer.read();

    // 手动调用 column()
    const start2 = timer.read();
    var query2 = try db.newSelect(User);
    defer query2.deinit();
    try query2.column("id");
    try query2.column("name");
    try query2.column("email");
    try query2.column("age");
    try query2.column("created_at");
    try query2.column("updated_at");
    const end2 = timer.read();

    // allColumns() 应该与手动调用性能相当（误差 ±10%）
    const time1 = end1 - start1;
    const time2 = end2 - start2;
    const diff = if (time1 > time2) time1 - time2 else time2 - time1;
    const ratio = @as(f64, @floatFromInt(diff)) / @as(f64, @floatFromInt(time2));

    try std.testing.expect(ratio < 0.1); // 误差小于 10%
}
```

