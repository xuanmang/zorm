# on-conflict-excluded-keyword Specification

## Purpose
TBD - created by archiving change implement-on-conflict-upsert-api. Update Purpose after archive.
## Requirements
### Requirement: EXCLUDED 关键字支持

doUpdate() MUST 支持 PostgreSQL EXCLUDED 关键字引用被排除的插入值。

#### Scenario: 单列 EXCLUDED 引用

**Given** InsertQuery 配置了 DO UPDATE
**When** `doUpdate("name = EXCLUDED.name")`
**Then** MUST 在生成的 SQL 中保留 EXCLUDED 关键字

```zig
const allocator = std.testing.allocator;
var query = try InsertQuery(User, .postgresql).init(allocator, mock_db, "users");
defer query.deinit();

_ = try query.value(.{
    .name = "Alice Updated",
    .email = "alice@example.com",
    .age = 26,
});
_ = try query.onConflict(&.{"email"});
_ = try query.doUpdate("name = EXCLUDED.name");

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "name = EXCLUDED.name") != null);
```

#### Scenario: 多列 EXCLUDED 引用

**Given** InsertQuery 配置了 DO UPDATE
**When** `doUpdate("name = EXCLUDED.name, age = EXCLUDED.age")`
**Then** MUST 在 SQL 中保留所有 EXCLUDED 引用

```zig
_ = try query.value(.{
    .name = "Bob Updated",
    .email = "bob@example.com",
    .age = 31,
});
_ = try query.onConflict(&.{"email"});
_ = try query.doUpdate("name = EXCLUDED.name, age = EXCLUDED.age");

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "name = EXCLUDED.name") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "age = EXCLUDED.age") != null);
```

---

### Requirement: EXCLUDED 与常量混合

doUpdate() MUST 支持 EXCLUDED 关键字与常量值混合使用。

#### Scenario: EXCLUDED 与函数调用

**Given** InsertQuery 配置了 DO UPDATE
**When** `doUpdate("name = EXCLUDED.name, updated_at = CURRENT_TIMESTAMP")`
**Then** MUST 同时支持 EXCLUDED 和函数调用

```zig
_ = try query.value(.{
    .name = "Carol",
    .email = "carol@example.com",
    .age = 28,
});
_ = try query.onConflict(&.{"email"});
_ = try query.doUpdate("name = EXCLUDED.name, updated_at = CURRENT_TIMESTAMP");

const sql = try query.build(null);
defer allocator.free(sql);

const expected = "INSERT INTO users (name, email, age) VALUES ($1, $2, $3) " ++
                 "ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name, updated_at = CURRENT_TIMESTAMP";
try std.testing.expectEqualStrings(expected, sql);
```

#### Scenario: EXCLUDED 与字面量

**Given** InsertQuery 配置了 DO UPDATE
**When** `doUpdate("name = EXCLUDED.name, status = 'updated'")`
**Then** MUST 同时支持 EXCLUDED 和字面量

```zig
_ = try query.onConflict(&.{"id"});
_ = try query.doUpdate("name = EXCLUDED.name, status = 'updated'");

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "name = EXCLUDED.name") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "status = 'updated'") != null);
```

---

### Requirement: EXCLUDED 在复杂表达式中

doUpdate() MUST 支持 EXCLUDED 在复杂 SQL 表达式中使用。

#### Scenario: EXCLUDED 在算术表达式中

**Given** InsertQuery 配置了 DO UPDATE
**When** `doUpdate("score = EXCLUDED.score + 10")`
**Then** MUST 在 SQL 中保留完整表达式

```zig
_ = try query.onConflict(&.{"id"});
_ = try query.doUpdate("score = EXCLUDED.score + 10");

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "score = EXCLUDED.score + 10") != null);
```

#### Scenario: EXCLUDED 在 COALESCE 函数中

**Given** InsertQuery 配置了 DO UPDATE
**When** `doUpdate("bio = COALESCE(EXCLUDED.bio, bio)")`
**Then** MUST 在 SQL 中保留函数调用和 EXCLUDED

```zig
_ = try query.onConflict(&.{"id"});
_ = try query.doUpdate("bio = COALESCE(EXCLUDED.bio, bio)");

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "bio = COALESCE(EXCLUDED.bio, bio)") != null);
```

---

### Requirement: EXCLUDED 与 RETURNING 集成

EXCLUDED 关键字 MUST 与 RETURNING 子句正确协作。

#### Scenario: DO UPDATE 使用 EXCLUDED 并返回更新后的值

**Given** InsertQuery 配置了 DO UPDATE 和 RETURNING
**When** 同时使用 EXCLUDED 和 RETURNING
**Then** MUST 生成包含两者的正确 SQL

```zig
_ = try query.value(.{
    .name = "Dave",
    .email = "dave@example.com",
    .age = 35,
});
_ = try query.onConflict(&.{"email"});
_ = try query.doUpdate("name = EXCLUDED.name, age = EXCLUDED.age");
_ = try query.returning(&.{"id", "name", "age"});

const sql = try query.build(null);
defer allocator.free(sql);

const expected = "INSERT INTO users (name, email, age) VALUES ($1, $2, $3) " ++
                 "ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name, age = EXCLUDED.age " ++
                 "RETURNING id, name, age";
try std.testing.expectEqualStrings(expected, sql);
```

---

### Requirement: 文档和示例

EXCLUDED 关键字用法 MUST 在代码文档中明确说明。

#### Scenario: 文档注释包含 EXCLUDED 示例

**Given** doUpdate() 方法的文档注释
**Then** MUST 包含 EXCLUDED 关键字的使用示例

```zig
/// 冲突时更新指定列 (DO UPDATE SET ...)
///
/// 参数:
/// - assignments: SQL SET 表达式字符串,支持 EXCLUDED 关键字
///   示例: "name = EXCLUDED.name, age = EXCLUDED.age"
///
/// EXCLUDED 关键字引用被冲突排除的插入值,可在表达式中使用:
/// - "column = EXCLUDED.column" - 使用新值
/// - "column = EXCLUDED.column + 10" - 基于新值计算
/// - "column = COALESCE(EXCLUDED.column, column)" - 条件更新
pub fn doUpdate(self: *Self, assignments: []const u8) !*Self {
    // ...
}
```

