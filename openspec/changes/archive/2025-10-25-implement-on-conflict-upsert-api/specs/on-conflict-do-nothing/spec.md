# on-conflict-do-nothing Specification

## Purpose
支持 PostgreSQL ON CONFLICT DO NOTHING 语法,在插入冲突时忽略该行,不执行任何操作。

## ADDED Requirements

### Requirement: onConflict() 方法指定冲突目标

InsertQuery MUST 提供 `onConflict(columns)` 方法指定冲突检测的列。

#### Scenario: 单列冲突目标

**Given** PostgreSQL 方言的 InsertQuery
**When** 调用 `onConflict(&.{"email"})`
**Then** MUST 存储冲突列数组
**And** MUST 返回 `*Self` 支持链式调用

```zig
const allocator = std.testing.allocator;
var query = try InsertQuery(User, .postgresql).init(allocator, mock_db, "users");
defer query.deinit();

_ = try query.onConflict(&.{"email"});

try std.testing.expect(query.conflict_target != null);
try std.testing.expectEqual(@as(usize, 1), query.conflict_target.?.len);
try std.testing.expectEqualStrings("email", query.conflict_target.?[0]);
```

#### Scenario: 多列冲突目标

**Given** PostgreSQL 方言的 InsertQuery
**When** 调用 `onConflict(&.{"user_id", "project_id"})`
**Then** MUST 存储所有冲突列

```zig
_ = try query.onConflict(&.{"user_id", "project_id"});

try std.testing.expectEqual(@as(usize, 2), query.conflict_target.?.len);
try std.testing.expectEqualStrings("user_id", query.conflict_target.?[0]);
try std.testing.expectEqualStrings("project_id", query.conflict_target.?[1]);
```

#### Scenario: 空列数组错误

**Given** PostgreSQL 方言的 InsertQuery
**When** 调用 `onConflict(&.{})`
**Then** MUST 返回 `error.EmptyConflictTarget`

```zig
const result = query.onConflict(&.{});
try std.testing.expectError(error.EmptyConflictTarget, result);
```

---

### Requirement: doNothing() 方法设置冲突动作

InsertQuery MUST 提供 `doNothing()` 方法指定冲突时不执行任何操作。

#### Scenario: 设置 DO NOTHING 动作

**Given** 已调用 `onConflict()` 的 InsertQuery
**When** 调用 `doNothing()`
**Then** MUST 设置 `conflict_action = .do_nothing`
**And** MUST 返回 `*Self` 支持链式调用

```zig
_ = try query.onConflict(&.{"email"});
_ = try query.doNothing();

try std.testing.expect(query.conflict_action != null);
try std.testing.expectEqual(ConflictAction.do_nothing, query.conflict_action.?);
```

#### Scenario: 未设置冲突目标错误

**Given** 未调用 `onConflict()` 的 InsertQuery
**When** 调用 `doNothing()`
**Then** MUST 返回 `error.ConflictTargetNotSet`

```zig
var query2 = try InsertQuery(User, .postgresql).init(allocator, mock_db, "users");
defer query2.deinit();

const result = query2.doNothing();
try std.testing.expectError(error.ConflictTargetNotSet, result);
```

---

### Requirement: 生成 ON CONFLICT DO NOTHING SQL

InsertQuery.build() MUST 生成正确的 ON CONFLICT DO NOTHING SQL 语句。

#### Scenario: 单列冲突 DO NOTHING

**Given** 配置了单列冲突和 DO NOTHING 的 InsertQuery
**When** 调用 `build()`
**Then** MUST 生成包含 `ON CONFLICT (column) DO NOTHING` 的 SQL

```zig
_ = try query.value(.{
    .name = "Alice",
    .email = "alice@example.com",
    .age = 25,
});
_ = try query.onConflict(&.{"email"});
_ = try query.doNothing();

const sql = try query.build(null);
defer allocator.free(sql);

const expected = "INSERT INTO users (name, email, age) VALUES ($1, $2, $3) " ++
                 "ON CONFLICT (email) DO NOTHING";
try std.testing.expectEqualStrings(expected, sql);
```

#### Scenario: 多列冲突 DO NOTHING

**Given** 配置了多列冲突和 DO NOTHING 的 InsertQuery
**When** 调用 `build()`
**Then** MUST 生成包含 `ON CONFLICT (col1, col2) DO NOTHING` 的 SQL

```zig
_ = try query.value(.{
    .user_id = 1,
    .project_id = 100,
    .role = "admin",
});
_ = try query.onConflict(&.{"user_id", "project_id"});
_ = try query.doNothing();

const sql = try query.build(null);
defer allocator.free(sql);

const expected = "INSERT INTO users (user_id, project_id, role) VALUES ($1, $2, $3) " ++
                 "ON CONFLICT (user_id, project_id) DO NOTHING";
try std.testing.expectEqualStrings(expected, sql);
```

---

### Requirement: 链式调用支持

InsertQuery MUST 支持流畅的链式调用风格。

#### Scenario: 完整链式调用

**Given** PostgreSQL 方言的 InsertQuery
**When** 链式调用 `value().onConflict().doNothing()`
**Then** MUST 正确执行所有方法

```zig
const sql = try (try (try (try query.value(.{
    .name = "Bob",
    .email = "bob@example.com",
    .age = 30,
})).onConflict(&.{"email"})).doNothing()).build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "ON CONFLICT (email) DO NOTHING") != null);
```

---

### Requirement: 编译时方言检查

非 PostgreSQL 方言 MUST 在编译时拒绝 ON CONFLICT 调用。

#### Scenario: MySQL 方言编译失败

**Given** MySQL 方言的 InsertQuery
**When** 调用 `onConflict()`
**Then** MUST 触发编译错误

```zig
// 此代码应无法编译
// var query = try InsertQuery(User, .mysql).init(allocator, mock_db, "users");
// _ = try query.onConflict(&.{"email"});
// @compileError("ON CONFLICT is not supported by mysql")
```
