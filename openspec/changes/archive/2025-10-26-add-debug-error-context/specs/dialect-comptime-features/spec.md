## ADDED Requirements

### Requirement: 查询构建器 explain() 方法

所有查询构建器 MUST 提供 `explain()` 方法，用于返回生成的 SQL 语句而不执行查询。

#### Scenario: SelectQuery 提供 explain() 方法

**Given** SelectQuery 实例
**When** 调用 `explain()` 方法
**Then** 返回生成的 SELECT SQL 语句
**And** 不执行查询
**And** 返回的 SQL 字符串由调用者负责释放

**使用示例**:
```zig
var query = try db.newSelect(User);
defer query.deinit();

_ = try query.where("age > $1", .{18});
const sql = try query.explain();
defer db.allocator.free(sql);

std.debug.print("Generated SQL:\n{s}\n", .{sql});
// 输出: SELECT * FROM users WHERE age > $1
```

**验证**:
- `explain()` 返回完整的 SQL 语句
- SQL 字符串格式正确
- 不执行数据库查询

---

#### Scenario: InsertQuery 提供 explain() 方法

**Given** InsertQuery 实例
**When** 调用 `explain()` 方法
**Then** 返回生成的 INSERT SQL 语句
**And** 包含 VALUES 子句和参数占位符

**使用示例**:
```zig
const user = User{
    .id = 1,
    .name = "Alice",
    .email = "alice@example.com",
    .created_at = 1234567890,
    .updated_at = 1234567890,
};

var query = try db.newInsert(User);
defer query.deinit();

_ = try query.value(user);
const sql = try query.explain();
defer db.allocator.free(sql);

std.debug.print("{s}\n", .{sql});
// 输出: INSERT INTO users (id, name, email, created_at, updated_at) VALUES ($1, $2, $3, $4, $5)
```

**验证**:
- SQL 包含 INSERT 语句
- VALUES 子句正确
- 参数占位符正确

---

#### Scenario: UpdateQuery 提供 explain() 方法

**Given** UpdateQuery 实例
**When** 调用 `explain()` 方法
**Then** 返回生成的 UPDATE SQL 语句
**And** 包含 SET 和 WHERE 子句

**使用示例**:
```zig
var query = try db.newUpdate(User);
defer query.deinit();

_ = try (try query.set("name = $1", .{"Bob"})).where("id = $2", .{123});
const sql = try query.explain();
defer db.allocator.free(sql);

std.debug.print("{s}\n", .{sql});
// 输出: UPDATE users SET name = $1 WHERE id = $2
```

**验证**:
- SQL 包含 UPDATE 语句
- SET 子句正确
- WHERE 子句正确

---

#### Scenario: DeleteQuery 提供 explain() 方法

**Given** DeleteQuery 实例
**When** 调用 `explain()` 方法
**Then** 返回生成的 DELETE SQL 语句
**And** 包含 WHERE 子句

**使用示例**:
```zig
var query = try db.newDelete(User);
defer query.deinit();

_ = try query.where("id = $1", .{123});
const sql = try query.explain();
defer db.allocator.free(sql);

std.debug.print("{s}\n", .{sql});
// 输出: DELETE FROM users WHERE id = $1
```

**验证**:
- SQL 包含 DELETE 语句
- WHERE 子句正确

---

### Requirement: Schema 构建器 explain() 方法

所有 Schema DDL 构建器 MUST 提供 `explain()` 方法，用于返回生成的 DDL 语句。

#### Scenario: CreateTableQuery 提供 explain() 方法

**Given** CreateTableQuery 实例
**When** 调用 `explain()` 方法
**Then** 返回生成的 CREATE TABLE SQL 语句
**And** 包含表名、列定义和约束

**使用示例**:
```zig
var query = try db.newCreateTable(User);
defer query.deinit();

_ = try query.ifNotExists();
const sql = try query.explain();
defer db.allocator.free(sql);

std.debug.print("{s}\n", .{sql});
// 输出: CREATE TABLE IF NOT EXISTS users (id BIGINT PRIMARY KEY, name TEXT NOT NULL, ...)
```

**验证**:
- SQL 包含 CREATE TABLE 语句
- 列定义正确
- 约束正确（如 PRIMARY KEY）

---

#### Scenario: DropTableQuery 提供 explain() 方法

**Given** DropTableQuery 实例
**When** 调用 `explain()` 方法
**Then** 返回生成的 DROP TABLE SQL 语句

**使用示例**:
```zig
var query = try db.newDropTable(User);
defer query.deinit();

_ = try query.ifExists().cascade();
const sql = try query.explain();
defer db.allocator.free(sql);

std.debug.print("{s}\n", .{sql});
// 输出: DROP TABLE IF EXISTS users CASCADE
```

**验证**:
- SQL 包含 DROP TABLE 语句
- IF EXISTS 子句正确
- CASCADE 选项正确

---

#### Scenario: CreateIndexQuery 提供 explain() 方法

**Given** CreateIndexQuery 实例
**When** 调用 `explain()` 方法
**Then** 返回生成的 CREATE INDEX SQL 语句

**使用示例**:
```zig
var query = try db.newCreateIndex(User);
defer query.deinit();

_ = try (try (try query.index("idx_users_email")).column("email")).unique();
const sql = try query.explain();
defer db.allocator.free(sql);

std.debug.print("{s}\n", .{sql});
// 输出: CREATE UNIQUE INDEX idx_users_email ON users (email)
```

**验证**:
- SQL 包含 CREATE INDEX 语句
- UNIQUE 选项正确
- 索引名和列名正确

---

#### Scenario: DropIndexQuery 提供 explain() 方法

**Given** DropIndexQuery 实例
**When** 调用 `explain()` 方法
**Then** 返回生成的 DROP INDEX SQL 语句

**使用示例**:
```zig
var query = try db.newDropIndex(User);
defer query.deinit();

_ = try query.index("idx_users_email").ifExists();
const sql = try query.explain();
defer db.allocator.free(sql);

std.debug.print("{s}\n", .{sql});
// 输出: DROP INDEX IF EXISTS idx_users_email
```

**验证**:
- SQL 包含 DROP INDEX 语句
- IF EXISTS 子句正确

---

### Requirement: explain() 与 buildSQL() 的等价性

`explain()` 方法 MUST 与 `buildSQL()` 方法完全等价，仅提供更清晰的语义。

#### Scenario: explain() 和 buildSQL() 返回相同的 SQL

**Given** 任意查询构建器实例
**When** 分别调用 `explain()` 和 `buildSQL()`
**Then** 两者返回的 SQL 字符串完全相同
**And** 字符串内容逐字节相等

**测试代码**:
```zig
test "explain() equals buildSQL()" {
    var query = try SelectQuery(User, .postgresql).init(std.testing.allocator, undefined, "users");
    defer query.deinit();

    _ = try (try query.where("age > $1", .{18})).orderBy("created_at", .desc);

    const sql1 = try query.buildSQL();
    defer std.testing.allocator.free(sql1);

    const sql2 = try query.explain();
    defer std.testing.allocator.free(sql2);

    try std.testing.expectEqualStrings(sql1, sql2);
}
```

**验证**:
- `explain()` 和 `buildSQL()` 返回值相同
- 内存分配行为一致
- 调用者都需要释放返回的字符串

---

#### Scenario: explain() 的实现调用 buildSQL()

**Given** 查询构建器的 `explain()` 方法实现
**When** 查看源码
**Then** `explain()` 内部直接调用 `buildSQL()`
**And** 无额外逻辑或开销

**实现示例**:
```zig
/// 返回生成的 SQL 语句（不执行）
///
/// 用于调试和验证 SQL 生成逻辑。等价于 `buildSQL()`。
pub fn explain(self: *Self) ![]const u8 {
    return self.buildSQL();
}
```

**验证**:
- `explain()` 实现简洁
- 直接调用 `buildSQL()`
- 零运行时开销

---

### Requirement: explain() 方法的文档和示例

所有 `explain()` 方法 MUST 包含完整的文档注释和使用示例。

#### Scenario: explain() 文档说明用途

**Given** 查询构建器的 `explain()` 方法
**When** 查看文档注释
**Then** 文档说明 `explain()` 用于返回 SQL 而不执行
**And** 说明与 `buildSQL()` 的关系
**And** 包含使用示例

**文档模板**:
```zig
/// 返回生成的 SQL 语句（不执行）
///
/// 用于调试和验证 SQL 生成逻辑。返回的 SQL 字符串由调用者负责释放。
///
/// ## 示例
/// ```zig
/// var query = try db.newSelect(User);
/// defer query.deinit();
///
/// const sql = try query.where("age > $1", .{18}).explain();
/// defer db.allocator.free(sql);
/// std.debug.print("Generated SQL:\n{s}\n", .{sql});
/// ```
///
/// ## 等价于
/// `explain()` 与 `buildSQL()` 完全等价，选择语义更清晰的命名。
pub fn explain(self: *Self) ![]const u8 {
    return self.buildSQL();
}
```

**验证**:
- 文档注释完整
- 包含使用示例
- 说明内存管理责任

---

#### Scenario: explain() 示例展示调试用法

**Given** 查询构建器的文档
**When** 查看示例代码
**Then** 示例展示如何使用 `explain()` 进行调试
**And** 示例包含 SQL 打印和验证

**示例代码**:
```zig
// 调试示例：验证生成的 SQL
var query = try db.newSelect(User);
defer query.deinit();

_ = try (try (try query.where("age > $1", .{18})).where("active = $2", .{true})).orderBy("created_at", .desc);

const sql = try query.explain();
defer db.allocator.free(sql);

std.debug.print("Generated SQL:\n{s}\n", .{sql});
// 验证 SQL 是否符合预期
try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "age > $1") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "active = $2") != null);
```

**验证**:
- 示例代码可运行
- 展示调试场景
- 说明如何验证生成的 SQL
