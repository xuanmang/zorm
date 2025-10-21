# bulk-update-api Specification

## Purpose
TBD - created by archiving change complete-update-query-api. Update Purpose after archive.
## Requirements
### Requirement: whereIn() 方法批量匹配

UPDATE 查询构建器 MUST 提供 `whereIn(column, values)` 方法支持批量匹配 (WHERE column IN (...))。

#### Scenario: 使用 whereIn 批量更新

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

// 准备测试数据
var insert = try db.newInsert(User);
defer insert.deinit();
const users = [_]User{
    .{ .name = "Alice", .email = "alice@example.com", .age = 25 },
    .{ .name = "Bob", .email = "bob@example.com", .age = 30 },
    .{ .name = "Carol", .email = "carol@example.com", .age = 28 },
};
_ = try insert.values(&users).exec();

// 批量更新
var update = try db.newUpdate(User);
defer update.deinit();

const user_ids = [_]i64{ 1, 2, 3 };
const result = try update
    .set("status = $1", .{"verified"})
    .whereIn("id", &user_ids)
    .exec();

try std.testing.expect(result.rows_affected == 3);
```

#### Scenario: whereIn 生成正确的 SQL

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newUpdate(User);
defer query.deinit();

const user_ids = [_]i64{ 1, 2, 3, 5, 8 };
const sql = try query
    .set("status = $1", .{"verified"})
    .whereIn("id", &user_ids)
    .build(null);
defer allocator.free(sql);

// 验证生成的 SQL 包含 IN 子句
try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE id IN ($2, $3, $4, $5, $6)") != null);
```

#### Scenario: whereIn 与其他 WHERE 条件组合

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newUpdate(User);
defer query.deinit();

const user_ids = [_]i64{ 1, 2, 3 };
const sql = try query
    .set("status = $1", .{"verified"})
    .where("age > $1", .{18})
    .whereIn("id", &user_ids)
    .build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE age > $2 AND id IN ($3, $4, $5)") != null);
```

---

### Requirement: whereNotIn() 方法排除匹配

UPDATE 查询构建器 MUST 提供 `whereNotIn(column, values)` 方法支持排除匹配 (WHERE column NOT IN (...))。

#### Scenario: 使用 whereNotIn 排除特定记录

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newUpdate(User);
defer query.deinit();

const excluded_ids = [_]i64{ 1, 2, 3 };
const sql = try query
    .set("status = $1", .{"inactive"})
    .whereNotIn("id", &excluded_ids)
    .build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE id NOT IN ($2, $3, $4)") != null);
```

#### Scenario: whereNotIn 与 whereIn 组合使用

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newUpdate(User);
defer query.deinit();

const allowed_ids = [_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
const excluded_ids = [_]i64{ 3, 5, 7 };

const sql = try query
    .set("status = $1", .{"active"})
    .whereIn("id", &allowed_ids)
    .whereNotIn("id", &excluded_ids)
    .build(null);
defer allocator.free(sql);

// 验证同时包含 IN 和 NOT IN
try std.testing.expect(std.mem.indexOf(u8, sql, "id IN (") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "id NOT IN (") != null);
```

---

### Requirement: 子查询支持

UPDATE 查询构建器 MUST 支持将 SelectQuery 作为子查询用于 whereIn/whereNotIn 条件。

#### Scenario: 使用子查询更新相关数据

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

// 创建子查询：查找活跃用户
var subquery = try db.newSelect(User);
defer subquery.deinit();

try subquery
    .column("id")
    .where("is_active = $1", .{true})
    .where("last_login > $1", .{cutoff_timestamp});

// 使用子查询更新
var update = try db.newUpdate(Post);
defer update.deinit();

const sql = try update
    .set("visibility = $1", .{"public"})
    .whereInSubquery("user_id", subquery)
    .build(null);
defer allocator.free(sql);

// 验证包含子查询
try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE user_id IN (SELECT id FROM users") != null);
```

#### Scenario: 子查询参数自动合并

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

// 子查询有 2 个参数
var subquery = try db.newSelect(User);
defer subquery.deinit();
try subquery
    .column("id")
    .where("status = $1", .{"verified"})
    .where("age > $1", .{18});

// UPDATE 有 1 个 SET 参数
var update = try db.newUpdate(Post);
defer update.deinit();

const sql = try update
    .set("featured = $1", .{true})
    .whereInSubquery("user_id", subquery)
    .build(null);
defer allocator.free(sql);

// 验证参数编号：SET 用 $1，子查询用 $2, $3
try std.testing.expect(std.mem.indexOf(u8, sql, "SET featured = $1") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "status = $2") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "age > $3") != null);
```

---

### Requirement: 批量 RETURNING 支持

批量更新操作 MUST 支持 RETURNING 子句，返回所有更新行的数据。

#### Scenario: 批量更新并返回所有更新的数据

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

// 准备测试数据
var insert = try db.newInsert(User);
defer insert.deinit();
const users = [_]User{
    .{ .name = "Alice", .email = "alice@example.com", .age = 25 },
    .{ .name = "Bob", .email = "bob@example.com", .age = 30 },
    .{ .name = "Carol", .email = "carol@example.com", .age = 28 },
};
_ = try insert.values(&users).exec();

// 批量更新并返回
var updated_users = std.ArrayList(User){};
defer updated_users.deinit(allocator);

var update = try db.newUpdate(User);
defer update.deinit();

const user_ids = [_]i64{ 1, 2, 3 };
try update
    .set("status = $1", .{"verified"})
    .whereIn("id", &user_ids)
    .setReturning(&[_][]const u8{"*"})
    .execReturning(&updated_users);

try std.testing.expectEqual(@as(usize, 3), updated_users.items.len);
for (updated_users.items) |user| {
    try std.testing.expectEqualStrings("verified", user.status);
}
```

#### Scenario: RETURNING 特定列减少数据传输

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

const UpdatedUser = struct {
    id: i64,
    name: []const u8,
    status: []const u8,
};

var updated_users = std.ArrayList(UpdatedUser){};
defer updated_users.deinit(allocator);

var update = try db.newUpdate(User);
defer update.deinit();

const user_ids = [_]i64{ 1, 2, 3 };
try update
    .set("status = $1", .{"verified"})
    .whereIn("id", &user_ids)
    .setReturning(&[_][]const u8{ "id", "name", "status" })
    .execReturning(&updated_users);

try std.testing.expect(updated_users.items.len > 0);
```

---

### Requirement: 空值列表检查

whereIn/whereNotIn 方法 MUST 在值列表为空时返回错误，防止生成无效 SQL。

#### Scenario: whereIn 空列表返回错误

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newUpdate(User);
defer query.deinit();

const empty_ids: []const i64 = &[_]i64{};
const result = query.whereIn("id", empty_ids);

try std.testing.expectError(error.EmptyValuesList, result);
```

#### Scenario: whereNotIn 空列表返回错误

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newUpdate(User);
defer query.deinit();

const empty_ids: []const i64 = &[_]i64{};
const result = query.whereNotIn("id", empty_ids);

try std.testing.expectError(error.EmptyValuesList, result);
```

---

### Requirement: 性能优化 - 批量参数绑定

批量更新 MUST 使用参数绑定而非字符串拼接，确保 SQL 注入防护和查询计划缓存优化。

#### Scenario: 验证使用参数绑定

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newUpdate(User);
defer query.deinit();

const user_ids = [_]i64{ 1, 2, 3, 4, 5 };
const sql = try query
    .set("status = $1", .{"verified"})
    .whereIn("id", &user_ids)
    .build(null);
defer allocator.free(sql);

// 验证使用占位符 $1, $2, $3, $4, $5, $6
try std.testing.expect(std.mem.indexOf(u8, sql, "$1") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "$2") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "$6") != null);

// 验证不包含直接拼接的数字
try std.testing.expect(std.mem.indexOf(u8, sql, "IN (1, 2, 3, 4, 5)") == null);
```

