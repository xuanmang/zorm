# on-conflict-returning-integration Specification

## Purpose
确保 ON CONFLICT 子句与 RETURNING 子句正确集成,支持返回插入或更新后的数据。

## ADDED Requirements

### Requirement: ON CONFLICT 与 RETURNING 兼容性

ON CONFLICT 子句 MUST 与 RETURNING 子句完全兼容,支持返回插入或更新后的行。

#### Scenario: DO NOTHING 与 RETURNING

**Given** 配置了 DO NOTHING 和 RETURNING 的 InsertQuery
**When** 调用 `build()`
**Then** MUST 生成包含两个子句的正确 SQL

```zig
const allocator = std.testing.allocator;
var query = try InsertQuery(User, .postgresql).init(allocator, mock_db, "users");
defer query.deinit();

_ = try query.value(.{
    .name = "Alice",
    .email = "alice@example.com",
    .age = 25,
});
_ = try query.onConflict(&.{"email"});
_ = try query.doNothing();
_ = try query.returning(&.{"id", "name"});

const sql = try query.build(null);
defer allocator.free(sql);

const expected = "INSERT INTO users (name, email, age) VALUES ($1, $2, $3) " ++
                 "ON CONFLICT (email) DO NOTHING " ++
                 "RETURNING id, name";
try std.testing.expectEqualStrings(expected, sql);
```

#### Scenario: DO UPDATE 与 RETURNING

**Given** 配置了 DO UPDATE 和 RETURNING 的 InsertQuery
**When** 调用 `build()`
**Then** MUST 生成包含两个子句的正确 SQL

```zig
_ = try query.value(.{
    .name = "Bob",
    .email = "bob@example.com",
    .age = 30,
});
_ = try query.onConflict(&.{"email"});
_ = try query.doUpdate("name = EXCLUDED.name, age = EXCLUDED.age");
_ = try query.returning(&.{"*"});

const sql = try query.build(null);
defer allocator.free(sql);

const expected = "INSERT INTO users (name, email, age) VALUES ($1, $2, $3) " ++
                 "ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name, age = EXCLUDED.age " ++
                 "RETURNING *";
try std.testing.expectEqualStrings(expected, sql);
```

---

### Requirement: execReturning() 方法支持

execReturning() MUST 支持 ON CONFLICT 场景,返回插入或更新的行。

#### Scenario: DO NOTHING execReturning

**Given** 配置了 DO NOTHING 和 RETURNING 的 InsertQuery
**When** 调用 `execReturning(dest)`
**Then** MUST 执行查询并填充目标 ArrayList

```zig
var results = std.ArrayList(User).init(allocator);
defer results.deinit();

_ = try query.value(.{
    .name = "Carol",
    .email = "carol@example.com",
    .age = 28,
});
_ = try query.onConflict(&.{"email"});
_ = try query.doNothing();
_ = try query.returning(&.{"*"});

// 如果没有冲突,应返回插入的行
// 如果有冲突且 DO NOTHING,返回空结果
try query.execReturning(&results);

// 验证结果 (具体行为取决于数据库状态)
try std.testing.expect(results.items.len <= 1);
```

#### Scenario: DO UPDATE execReturning

**Given** 配置了 DO UPDATE 和 RETURNING 的 InsertQuery
**When** 调用 `execReturning(dest)`
**Then** MUST 返回更新后的行

```zig
var results2 = std.ArrayList(User).init(allocator);
defer results2.deinit();

_ = try query.value(.{
    .name = "Dave Updated",
    .email = "dave@example.com",
    .age = 35,
});
_ = try query.onConflict(&.{"email"});
_ = try query.doUpdate("name = EXCLUDED.name, age = EXCLUDED.age");
_ = try query.returning(&.{"id", "name", "age"});

try query.execReturning(&results2);

// 应返回一行 (插入或更新后的数据)
try std.testing.expectEqual(@as(usize, 1), results2.items.len);
try std.testing.expectEqualStrings("Dave Updated", results2.items[0].name);
try std.testing.expectEqual(@as(u32, 35), results2.items[0].age);
```

---

### Requirement: RETURNING 所有列支持

RETURNING * MUST 支持返回 ON CONFLICT 操作的所有列。

#### Scenario: RETURNING * 与 DO UPDATE

**Given** 配置了 DO UPDATE 和 `RETURNING *` 的 InsertQuery
**When** 调用 `build()`
**Then** MUST 生成 `RETURNING *` 子句

```zig
_ = try query.value(.{
    .name = "Eve",
    .email = "eve@example.com",
    .age = 22,
});
_ = try query.onConflict(&.{"email"});
_ = try query.doUpdate("age = EXCLUDED.age + 1");
_ = try query.returning(&.{"*"});

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "RETURNING *") != null);
```

---

### Requirement: RETURNING 特定列支持

RETURNING MUST 支持返回指定的列子集。

#### Scenario: RETURNING 指定列

**Given** 配置了 DO UPDATE 和指定列 RETURNING 的 InsertQuery
**When** 调用 `build()`
**Then** MUST 生成包含指定列的 RETURNING 子句

```zig
_ = try query.value(.{
    .name = "Frank",
    .email = "frank@example.com",
    .age = 40,
});
_ = try query.onConflict(&.{"email"});
_ = try query.doUpdate("name = EXCLUDED.name");
_ = try query.returning(&.{"id", "updated_at"});

const sql = try query.build(null);
defer allocator.free(sql);

const expected = "INSERT INTO users (name, email, age) VALUES ($1, $2, $3) " ++
                 "ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name " ++
                 "RETURNING id, updated_at";
try std.testing.expectEqualStrings(expected, sql);
```

---

### Requirement: 批量插入与 RETURNING

ON CONFLICT 与 RETURNING MUST 支持批量插入场景。

#### Scenario: 批量 UPSERT 返回所有行

**Given** 配置了批量插入、DO UPDATE 和 RETURNING 的 InsertQuery
**When** 调用 `execReturning()`
**Then** MUST 返回所有插入或更新的行

```zig
const users = [_]struct { name: []const u8, email: []const u8, age: u32 }{
    .{ .name = "Alice", .email = "alice@example.com", .age = 25 },
    .{ .name = "Bob", .email = "bob@example.com", .age = 30 },
    .{ .name = "Carol", .email = "carol@example.com", .age = 28 },
};

var results = std.ArrayList(User).init(allocator);
defer results.deinit();

_ = try query.values(&users);
_ = try query.onConflict(&.{"email"});
_ = try query.doUpdate("age = EXCLUDED.age");
_ = try query.returning(&.{"*"});

try query.execReturning(&results);

// 应返回 3 行 (所有插入或更新的行)
try std.testing.expectEqual(@as(usize, 3), results.items.len);
```

---

### Requirement: WHERE 条件与 RETURNING 集成

whereConflict() 与 RETURNING MUST 正确协作。

#### Scenario: 部分唯一索引 + RETURNING

**Given** 配置了 WHERE 条件、DO UPDATE 和 RETURNING 的 InsertQuery
**When** 调用 `build()`
**Then** MUST 生成包含所有三个子句的正确 SQL

```zig
_ = try query.value(.{
    .email = "grace@example.com",
    .name = "Grace",
    .deleted_at = null,
});
_ = try query.onConflict(&.{"email"});
_ = try query.whereConflict("deleted_at IS NULL");
_ = try query.doUpdate("name = EXCLUDED.name");
_ = try query.returning(&.{"id", "name"});

const sql = try query.build(null);
defer allocator.free(sql);

const expected = "INSERT INTO users (email, name, deleted_at) VALUES ($1, $2, $3) " ++
                 "ON CONFLICT (email) WHERE deleted_at IS NULL " ++
                 "DO UPDATE SET name = EXCLUDED.name " ++
                 "RETURNING id, name";
try std.testing.expectEqualStrings(expected, sql);
```

---

### Requirement: 链式调用支持

RETURNING MUST 支持与 ON CONFLICT 相关方法的流畅链式调用。

#### Scenario: 完整链式调用

**Given** PostgreSQL 方言的 InsertQuery
**When** 链式调用 `value().onConflict().doUpdate().returning()`
**Then** MUST 正确执行所有方法

```zig
const sql = try query
    .value(.{
        .name = "Helen",
        .email = "helen@example.com",
        .age = 32,
    })
    .onConflict(&.{"email"})
    .doUpdate("name = EXCLUDED.name, age = EXCLUDED.age")
    .returning(&.{"id", "name", "age", "updated_at"})
    .build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "ON CONFLICT") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "DO UPDATE SET") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "RETURNING id, name, age, updated_at") != null);
```

---

### Requirement: 错误处理一致性

execReturning() 在 ON CONFLICT 场景下 MUST 保持与普通插入一致的错误处理。

#### Scenario: 连接错误传播

**Given** 数据库连接失败
**When** 调用 `execReturning()` 使用 ON CONFLICT
**Then** MUST 返回连接错误

```zig
// 模拟连接错误场景
// 错误处理逻辑应与普通 INSERT 一致
```

#### Scenario: 类型转换错误

**Given** RETURNING 列与目标结构体类型不匹配
**When** 调用 `execReturning()`
**Then** MUST 返回类型转换错误

```zig
// 模拟类型不匹配场景
// 错误处理逻辑应与普通 INSERT RETURNING 一致
```
