# update-query-api Specification

## Purpose
TBD - created by archiving change complete-update-query-api. Update Purpose after archive.
## Requirements
### Requirement: newUpdate() 工厂方法

DB 实例 MUST 提供 `newUpdate(T)` 方法创建 UPDATE 查询构建器，T 为目标 Zig 结构体类型。

#### Scenario: 创建 UPDATE 查询构建器

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: u32,
    pub const table_name = "users";
};

var query = try db.newUpdate(User);
defer query.deinit();

try std.testing.expect(query.allocator.ptr == allocator.ptr);
try std.testing.expectEqualStrings("users", query.table_name);
```

#### Scenario: 自动提取表名

```zig
const User = struct {
    id: i64,
    name: []const u8,
    pub const table_name = "users";
};

var query = try db.newUpdate(User);
defer query.deinit();

try std.testing.expectEqualStrings("users", query.table_name);
```

---

### Requirement: set() 方法设置更新值

UPDATE 查询构建器 MUST 提供 `set(assignments, args)` 方法指定要更新的列和值，支持 SQL 表达式。

#### Scenario: 设置单列更新

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newUpdate(User);
defer query.deinit();

_ = try query.set("name = $1", .{"Alice"});

const sql = try query.set("email = $1", .{"alice@example.com"})
    .where("id = $1", .{123})
    .build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "SET name = $1, email = $2") != null);
```

#### Scenario: 支持表达式更新

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newUpdate(User);
defer query.deinit();

_ = try query.set("age = age + 1", .{});
_ = try query.set("updated_at = $1", .{std.time.timestamp()});
_ = try query.where("id = $1", .{123});

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "SET age = age + 1, updated_at = $2") != null);
```

#### Scenario: 链式调用支持

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newUpdate(User);
defer query.deinit();

const sql = try query
    .set("name = $1", .{"Bob"})
    .set("age = $1", .{30})
    .where("id = $1", .{456})
    .build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "UPDATE users") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "SET") != null);
```

---

### Requirement: where() 方法添加条件

UPDATE 查询构建器 MUST 提供 `where(condition, args)` 方法添加 WHERE 条件，防止误更新所有行。

#### Scenario: 添加单个 WHERE 条件

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newUpdate(User);
defer query.deinit();

const sql = try query
    .set("name = $1", .{"Alice"})
    .where("id = $1", .{123})
    .build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE id = $2") != null);
```

#### Scenario: 添加多个 WHERE 条件 (AND)

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newUpdate(User);
defer query.deinit();

const sql = try query
    .set("status = $1", .{"active"})
    .where("email = $1", .{"alice@example.com"})
    .where("age > $1", .{18})
    .build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE email = $2 AND age > $3") != null);
```

---

### Requirement: exec() 方法执行更新

UPDATE 查询构建器 MUST 提供 `exec()` 方法执行更新操作，返回 UpdateResult (包含 rows_affected)。

#### Scenario: 执行基本更新

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

// 插入测试数据
var insert = try db.newInsert(User);
defer insert.deinit();
_ = try insert.value(.{
    .name = "Alice",
    .email = "alice@example.com",
    .age = 25,
}).exec();

// 执行更新
var update = try db.newUpdate(User);
defer update.deinit();

const result = try update
    .set("age = $1", .{26})
    .where("email = $1", .{"alice@example.com"})
    .exec();

try std.testing.expect(result.rows_affected > 0);
```

#### Scenario: 没有 SET 子句时返回错误

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var update = try db.newUpdate(User);
defer update.deinit();

_ = try update.where("id = $1", .{123});

const result = update.exec();
try std.testing.expectError(error.NoColumnsToUpdate, result);
```

---

### Requirement: setReturning() 方法启用 RETURNING 子句

UPDATE 查询构建器 MUST 提供 `setReturning(cols)` 方法启用 PostgreSQL RETURNING 子句。

#### Scenario: 设置 RETURNING 所有列

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newUpdate(User);
defer query.deinit();

_ = query.setReturning(&[_][]const u8{"*"});

const sql = try query
    .set("age = $1", .{30})
    .where("id = $1", .{123})
    .build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "RETURNING *") != null);
```

#### Scenario: 设置 RETURNING 特定列

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newUpdate(User);
defer query.deinit();

_ = query.setReturning(&[_][]const u8{ "id", "name", "email" });

const sql = try query
    .set("age = $1", .{30})
    .where("id = $1", .{123})
    .build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "RETURNING id, name, email") != null);
```

---

### Requirement: execReturning() 方法执行并获取更新后数据

UPDATE 查询构建器 MUST 提供 `execReturning(dest)` 方法执行更新并将 RETURNING 结果扫描到 ArrayList 中。

#### Scenario: 执行更新并获取更新后的数据

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

// 插入测试数据
var insert = try db.newInsert(User);
defer insert.deinit();
_ = try insert.value(.{
    .name = "Alice",
    .email = "alice@example.com",
    .age = 25,
}).exec();

// 执行更新并获取结果
var updated_users = std.ArrayList(User){};
defer updated_users.deinit(allocator);

var update = try db.newUpdate(User);
defer update.deinit();

try update
    .set("age = $1", .{26})
    .where("email = $1", .{"alice@example.com"})
    .setReturning(&[_][]const u8{"*"})
    .execReturning(&updated_users);

try std.testing.expect(updated_users.items.len > 0);
try std.testing.expectEqual(@as(u32, 26), updated_users.items[0].age);
```

#### Scenario: 未设置 RETURNING 时返回错误

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var updated_users = std.ArrayList(User){};
defer updated_users.deinit(allocator);

var update = try db.newUpdate(User);
defer update.deinit();

_ = try update
    .set("age = $1", .{26})
    .where("id = $1", .{123});

const result = update.execReturning(&updated_users);
try std.testing.expectError(error.NoReturningColumns, result);
```

---

### Requirement: 参数占位符自动编号

UPDATE 查询构建器 MUST 自动为 SET 和 WHERE 子句的参数生成正确的占位符编号 ($1, $2, ...)。

#### Scenario: SET 和 WHERE 参数正确编号

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newUpdate(User);
defer query.deinit();

const sql = try query
    .set("name = $1", .{"Alice"})
    .set("age = $1", .{30})
    .where("email = $1", .{"alice@example.com"})
    .where("id = $1", .{123})
    .build(null);
defer allocator.free(sql);

// SET 参数: $1, $2
// WHERE 参数: $3, $4
try std.testing.expect(std.mem.indexOf(u8, sql, "name = $1") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "age = $2") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "email = $3") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "id = $4") != null);
```

