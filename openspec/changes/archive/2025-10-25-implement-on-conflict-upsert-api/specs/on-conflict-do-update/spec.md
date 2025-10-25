# on-conflict-do-update Specification

## Purpose
支持 PostgreSQL ON CONFLICT DO UPDATE 语法,在插入冲突时更新指定列,实现 UPSERT 操作。

## ADDED Requirements

### Requirement: doUpdate() 方法设置更新表达式

InsertQuery MUST 提供 `doUpdate(assignments)` 方法指定冲突时的更新操作。

#### Scenario: 设置 DO UPDATE 动作

**Given** 已调用 `onConflict()` 的 InsertQuery
**When** 调用 `doUpdate("name = EXCLUDED.name")`
**Then** MUST 设置 `conflict_action = .do_update`
**And** MUST 存储更新表达式
**And** MUST 返回 `*Self` 支持链式调用

```zig
const allocator = std.testing.allocator;
var query = try InsertQuery(User, .postgresql).init(allocator, mock_db, "users");
defer query.deinit();

_ = try query.onConflict(&.{"email"});
_ = try query.doUpdate("name = EXCLUDED.name");

try std.testing.expect(query.conflict_action != null);
try std.testing.expectEqual(ConflictAction.do_update, query.conflict_action.?);
try std.testing.expect(query.conflict_updates != null);
try std.testing.expectEqualStrings("name = EXCLUDED.name", query.conflict_updates.?);
```

#### Scenario: 多列更新表达式

**Given** 已调用 `onConflict()` 的 InsertQuery
**When** 调用 `doUpdate("name = EXCLUDED.name, age = EXCLUDED.age")`
**Then** MUST 存储完整的更新表达式

```zig
_ = try query.onConflict(&.{"email"});
_ = try query.doUpdate("name = EXCLUDED.name, age = EXCLUDED.age, updated_at = CURRENT_TIMESTAMP");

try std.testing.expectEqualStrings(
    "name = EXCLUDED.name, age = EXCLUDED.age, updated_at = CURRENT_TIMESTAMP",
    query.conflict_updates.?
);
```

#### Scenario: 未设置冲突目标错误

**Given** 未调用 `onConflict()` 的 InsertQuery
**When** 调用 `doUpdate()`
**Then** MUST 返回 `error.ConflictTargetNotSet`

```zig
var query2 = try InsertQuery(User, .postgresql).init(allocator, mock_db, "users");
defer query2.deinit();

const result = query2.doUpdate("name = EXCLUDED.name");
try std.testing.expectError(error.ConflictTargetNotSet, result);
```

#### Scenario: 空更新表达式错误

**Given** 已调用 `onConflict()` 的 InsertQuery
**When** 调用 `doUpdate("")`
**Then** MUST 返回 `error.EmptyUpdateAssignments`

```zig
_ = try query.onConflict(&.{"email"});
const result = query.doUpdate("");
try std.testing.expectError(error.EmptyUpdateAssignments, result);
```

---

### Requirement: 生成 ON CONFLICT DO UPDATE SQL

InsertQuery.build() MUST 生成正确的 ON CONFLICT DO UPDATE SET SQL 语句。

#### Scenario: 单列更新

**Given** 配置了冲突和更新的 InsertQuery
**When** 调用 `build()`
**Then** MUST 生成包含 `ON CONFLICT (...) DO UPDATE SET ...` 的 SQL

```zig
_ = try query.value(.{
    .name = "Alice",
    .email = "alice@example.com",
    .age = 25,
});
_ = try query.onConflict(&.{"email"});
_ = try query.doUpdate("name = EXCLUDED.name");

const sql = try query.build(null);
defer allocator.free(sql);

const expected = "INSERT INTO users (name, email, age) VALUES ($1, $2, $3) " ++
                 "ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name";
try std.testing.expectEqualStrings(expected, sql);
```

#### Scenario: 多列更新

**Given** 配置了多列更新的 InsertQuery
**When** 调用 `build()`
**Then** MUST 生成包含多个 SET 赋值的 SQL

```zig
_ = try query.value(.{
    .name = "Bob",
    .email = "bob@example.com",
    .age = 30,
});
_ = try query.onConflict(&.{"email"});
_ = try query.doUpdate("name = EXCLUDED.name, age = EXCLUDED.age");

const sql = try query.build(null);
defer allocator.free(sql);

const expected = "INSERT INTO users (name, email, age) VALUES ($1, $2, $3) " ++
                 "ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name, age = EXCLUDED.age";
try std.testing.expectEqualStrings(expected, sql);
```

---

### Requirement: 支持 SQL 函数和表达式

doUpdate() MUST 支持任意有效的 PostgreSQL SET 表达式。

#### Scenario: 使用 CURRENT_TIMESTAMP

**Given** InsertQuery 配置了冲突
**When** `doUpdate("updated_at = CURRENT_TIMESTAMP")`
**Then** MUST 在 SQL 中原样保留函数调用

```zig
_ = try query.onConflict(&.{"id"});
_ = try query.doUpdate("updated_at = CURRENT_TIMESTAMP");

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "updated_at = CURRENT_TIMESTAMP") != null);
```

#### Scenario: 使用算术表达式

**Given** InsertQuery 配置了冲突
**When** `doUpdate("view_count = view_count + 1")`
**Then** MUST 在 SQL 中保留表达式

```zig
_ = try query.onConflict(&.{"id"});
_ = try query.doUpdate("view_count = view_count + 1");

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "view_count = view_count + 1") != null);
```

---

### Requirement: 批量插入支持

ON CONFLICT DO UPDATE MUST 支持批量插入场景。

#### Scenario: 批量 UPSERT

**Given** InsertQuery 配置了多行数据和冲突更新
**When** 调用 `build()`
**Then** MUST 生成批量 VALUES 和 ON CONFLICT 子句

```zig
const users = [_]struct { name: []const u8, email: []const u8, age: u32 }{
    .{ .name = "Alice", .email = "alice@example.com", .age = 25 },
    .{ .name = "Bob", .email = "bob@example.com", .age = 30 },
};

_ = try query.values(&users);
_ = try query.onConflict(&.{"email"});
_ = try query.doUpdate("name = EXCLUDED.name");

const sql = try query.build(null);
defer allocator.free(sql);

const expected = "INSERT INTO users (name, email, age) VALUES ($1, $2, $3), ($4, $5, $6) " ++
                 "ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name";
try std.testing.expectEqualStrings(expected, sql);
```

---

### Requirement: 链式调用支持

InsertQuery MUST 支持流畅的链式调用风格。

#### Scenario: 完整链式调用

**Given** PostgreSQL 方言的 InsertQuery
**When** 链式调用 `value().onConflict().doUpdate()`
**Then** MUST 正确执行所有方法

```zig
const sql = try query
    .value(.{
        .name = "Carol",
        .email = "carol@example.com",
        .age = 28,
    })
    .onConflict(&.{"email"})
    .doUpdate("age = EXCLUDED.age")
    .build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "ON CONFLICT (email) DO UPDATE SET age = EXCLUDED.age") != null);
```
