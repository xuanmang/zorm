# on-conflict-where-clause Specification

## Purpose
支持 PostgreSQL ON CONFLICT WHERE 子句,实现部分唯一索引冲突检测。

## ADDED Requirements

### Requirement: whereConflict() 方法设置 WHERE 条件

InsertQuery MUST 提供 `whereConflict(condition)` 方法指定部分唯一索引的 WHERE 条件。

#### Scenario: 设置 WHERE 条件

**Given** 已调用 `onConflict()` 的 InsertQuery
**When** 调用 `whereConflict("active = true")`
**Then** MUST 存储 WHERE 条件
**And** MUST 返回 `*Self` 支持链式调用

```zig
const allocator = std.testing.allocator;
var query = try InsertQuery(User, .postgresql).init(allocator, mock_db, "users");
defer query.deinit();

_ = try query.onConflict(&.{"email"});
_ = try query.whereConflict("active = true");

try std.testing.expect(query.conflict_where != null);
try std.testing.expectEqualStrings("active = true", query.conflict_where.?);
```

#### Scenario: 复杂 WHERE 条件

**Given** 已调用 `onConflict()` 的 InsertQuery
**When** 调用 `whereConflict("deleted_at IS NULL AND active = true")`
**Then** MUST 存储完整的 WHERE 条件表达式

```zig
_ = try query.onConflict(&.{"email"});
_ = try query.whereConflict("deleted_at IS NULL AND active = true");

try std.testing.expectEqualStrings(
    "deleted_at IS NULL AND active = true",
    query.conflict_where.?
);
```

#### Scenario: 未设置冲突目标错误

**Given** 未调用 `onConflict()` 的 InsertQuery
**When** 调用 `whereConflict()`
**Then** MUST 返回 `error.ConflictTargetNotSet`

```zig
var query2 = try InsertQuery(User, .postgresql).init(allocator, mock_db, "users");
defer query2.deinit();

const result = query2.whereConflict("active = true");
try std.testing.expectError(error.ConflictTargetNotSet, result);
```

#### Scenario: 空 WHERE 条件错误

**Given** 已调用 `onConflict()` 的 InsertQuery
**When** 调用 `whereConflict("")`
**Then** MUST 返回 `error.EmptyWhereCondition`

```zig
_ = try query.onConflict(&.{"email"});
const result = query.whereConflict("");
try std.testing.expectError(error.EmptyWhereCondition, result);
```

---

### Requirement: 生成 ON CONFLICT WHERE SQL

InsertQuery.build() MUST 在 ON CONFLICT 子句中正确生成 WHERE 条件。

#### Scenario: WHERE 条件在冲突列之后

**Given** 配置了冲突列和 WHERE 条件的 InsertQuery
**When** 调用 `build()`
**Then** MUST 生成 `ON CONFLICT (...) WHERE ... DO NOTHING` 格式

```zig
_ = try query.value(.{
    .name = "Alice",
    .email = "alice@example.com",
    .active = true,
});
_ = try query.onConflict(&.{"email"});
_ = try query.whereConflict("active = true");
_ = try query.doNothing();

const sql = try query.build(null);
defer allocator.free(sql);

const expected = "INSERT INTO users (name, email, active) VALUES ($1, $2, $3) " ++
                 "ON CONFLICT (email) WHERE active = true DO NOTHING";
try std.testing.expectEqualStrings(expected, sql);
```

#### Scenario: WHERE 条件与 DO UPDATE

**Given** 配置了 WHERE 条件和 DO UPDATE 的 InsertQuery
**When** 调用 `build()`
**Then** MUST 生成 `ON CONFLICT (...) WHERE ... DO UPDATE SET ...` 格式

```zig
_ = try query.value(.{
    .name = "Bob",
    .email = "bob@example.com",
    .deleted_at = null,
});
_ = try query.onConflict(&.{"email"});
_ = try query.whereConflict("deleted_at IS NULL");
_ = try query.doUpdate("name = EXCLUDED.name");

const sql = try query.build(null);
defer allocator.free(sql);

const expected = "INSERT INTO users (name, email, deleted_at) VALUES ($1, $2, $3) " ++
                 "ON CONFLICT (email) WHERE deleted_at IS NULL " ++
                 "DO UPDATE SET name = EXCLUDED.name";
try std.testing.expectEqualStrings(expected, sql);
```

---

### Requirement: WHERE 条件支持任意表达式

whereConflict() MUST 支持任意有效的 PostgreSQL WHERE 表达式。

#### Scenario: IS NULL 判断

**Given** InsertQuery 配置了冲突
**When** `whereConflict("deleted_at IS NULL")`
**Then** MUST 在 SQL 中保留 IS NULL 表达式

```zig
_ = try query.onConflict(&.{"email"});
_ = try query.whereConflict("deleted_at IS NULL");
_ = try query.doNothing();

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE deleted_at IS NULL") != null);
```

#### Scenario: 布尔字段判断

**Given** InsertQuery 配置了冲突
**When** `whereConflict("active = true")`
**Then** MUST 在 SQL 中保留布尔比较

```zig
_ = try query.onConflict(&.{"email"});
_ = try query.whereConflict("active = true");
_ = try query.doUpdate("updated_at = CURRENT_TIMESTAMP");

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE active = true") != null);
```

#### Scenario: 复合条件 (AND/OR)

**Given** InsertQuery 配置了冲突
**When** `whereConflict("deleted_at IS NULL AND status != 'archived'")`
**Then** MUST 在 SQL 中保留完整的逻辑表达式

```zig
_ = try query.onConflict(&.{"email"});
_ = try query.whereConflict("deleted_at IS NULL AND status != 'archived'");
_ = try query.doNothing();

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE deleted_at IS NULL AND status != 'archived'") != null);
```

---

### Requirement: 部分唯一索引场景

whereConflict() MUST 支持 PostgreSQL 部分唯一索引的典型使用场景。

#### Scenario: 软删除数据唯一性

**Given** 表包含 deleted_at 列的软删除设计
**When** 使用 WHERE deleted_at IS NULL 的部分唯一索引
**Then** MUST 只对未删除记录检测冲突

```zig
// 假设数据库有以下部分唯一索引:
// CREATE UNIQUE INDEX users_email_active_idx
// ON users (email) WHERE deleted_at IS NULL;

_ = try query.value(.{
    .email = "alice@example.com",
    .name = "Alice",
    .deleted_at = null,
});
_ = try query.onConflict(&.{"email"});
_ = try query.whereConflict("deleted_at IS NULL");
_ = try query.doUpdate("name = EXCLUDED.name, updated_at = CURRENT_TIMESTAMP");

const sql = try query.build(null);
defer allocator.free(sql);

const expected = "INSERT INTO users (email, name, deleted_at) VALUES ($1, $2, $3) " ++
                 "ON CONFLICT (email) WHERE deleted_at IS NULL " ++
                 "DO UPDATE SET name = EXCLUDED.name, updated_at = CURRENT_TIMESTAMP";
try std.testing.expectEqualStrings(expected, sql);
```

#### Scenario: 激活状态唯一性

**Given** 表包含 active 布尔列
**When** 使用 WHERE active = true 的部分唯一索引
**Then** MUST 只对激活记录检测冲突

```zig
// 假设数据库有以下部分唯一索引:
// CREATE UNIQUE INDEX users_email_active_idx
// ON users (email) WHERE active = true;

_ = try query.value(.{
    .email = "bob@example.com",
    .name = "Bob",
    .active = true,
});
_ = try query.onConflict(&.{"email"});
_ = try query.whereConflict("active = true");
_ = try query.doNothing();

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE active = true") != null);
```

---

### Requirement: 链式调用支持

whereConflict() MUST 支持与其他方法的流畅链式调用。

#### Scenario: 完整链式调用

**Given** PostgreSQL 方言的 InsertQuery
**When** 链式调用 `onConflict().whereConflict().doUpdate()`
**Then** MUST 正确执行所有方法

```zig
const sql = try query
    .value(.{
        .email = "carol@example.com",
        .name = "Carol",
        .deleted_at = null,
    })
    .onConflict(&.{"email"})
    .whereConflict("deleted_at IS NULL")
    .doUpdate("name = EXCLUDED.name")
    .build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE deleted_at IS NULL") != null);
```

---

### Requirement: 可选性

whereConflict() MUST 是可选的,不影响基础 ON CONFLICT 功能。

#### Scenario: 无 WHERE 条件的冲突

**Given** InsertQuery 只配置了 onConflict() 和 doNothing()
**When** 不调用 whereConflict()
**Then** MUST 生成不包含 WHERE 的 ON CONFLICT 子句

```zig
_ = try query.value(.{ .email = "dave@example.com", .name = "Dave" });
_ = try query.onConflict(&.{"email"});
_ = try query.doNothing();

const sql = try query.build(null);
defer allocator.free(sql);

// 不应包含 WHERE
try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE") == null);
try std.testing.expect(std.mem.indexOf(u8, sql, "ON CONFLICT (email) DO NOTHING") != null);
```
