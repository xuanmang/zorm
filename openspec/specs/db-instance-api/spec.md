# db-instance-api Specification

## Purpose
TBD - created by archiving change implement-db-instance-management. Update Purpose after archive.
## Requirements
### Requirement: DB 实例创建和销毁

DB 实例 MUST支持显式的创建和销毁，确保资源正确管理。

#### Scenario: 创建 DB 实例

**Given** 有效的 Allocator、数据库连接和配置选项
**When** 调用 `DB.init(allocator, conn, options)`
**Then** 返回新创建的 DB 实例指针
**And** DB 实例正确初始化所有字段
**And** 查询钩子列表为空

**示例代码**:
```zig
const allocator = std.heap.page_allocator;
const conn = try openConnection("postgres://localhost/testdb");
const options = DBOptions{ .max_open_conns = 20 };

var db = try DB(.postgresql).init(allocator, conn, options);
defer db.deinit();

try std.testing.expect(db.allocator == allocator);
try std.testing.expect(db.options.max_open_conns == 20);
try std.testing.expectEqual(@as(usize, 0), db.query_hooks.items.len);
```

#### Scenario: 销毁 DB 实例

**Given** 已创建的 DB 实例
**When** 调用 `db.deinit()`
**Then** 回滚所有活动事务（如果有）
**And** 清理查询钩子列表
**And** 关闭数据库连接
**And** 释放分配的内存

**示例代码**:
```zig
var db = try DB(.postgresql).init(allocator, conn, .{});
db.deinit();
// 所有资源已释放，不会泄漏
```

#### Scenario: 创建失败时的资源清理

**Given** Allocator 或连接初始化失败
**When** `DB.init()` 返回错误
**Then** 不会发生内存泄漏
**And** 已分配的资源通过 errdefer 自动清理

**示例代码**:
```zig
const allocator = std.testing.allocator;

// 模拟内存不足
var limited_allocator = std.testing.FailingAllocator.init(allocator, 1);

const result = DB(.postgresql).init(limited_allocator.allocator(), conn, .{});
try std.testing.expectError(error.OutOfMemory, result);

// 不会有内存泄漏
```

---

### Requirement: DB 实例克隆

DB 实例 MUST支持克隆，创建共享连接但独立状态的新实例。

#### Scenario: 克隆 DB 实例

**Given** 已创建的 DB 实例
**When** 调用 `db.clone()`
**Then** 返回新的 DB 实例
**And** 新实例共享相同的连接
**And** 新实例有独立的查询钩子列表
**And** 新实例有独立的统计信息
**And** 新实例的事务状态为 null

**示例代码**:
```zig
var db = try DB(.postgresql).init(allocator, conn, .{});
defer db.deinit();

var hook = LoggingHook.init(true, 1000);
try db.addHook(hook.hook());

var cloned = try db.clone();
defer cloned.deinit();

// 共享连接
try std.testing.expect(db.conn.ptr == cloned.conn.ptr);

// 独立的钩子列表
try std.testing.expectEqual(@as(usize, 1), db.query_hooks.items.len);
try std.testing.expectEqual(@as(usize, 1), cloned.query_hooks.items.len);

// 独立的统计信息
db.stats.recordQuery();
try std.testing.expectEqual(@as(u64, 1), db.getStats().getQueryCount());
try std.testing.expectEqual(@as(u64, 0), cloned.getStats().getQueryCount());
```

#### Scenario: 克隆并添加钩子

**Given** 已创建的 DB 实例
**When** 调用 `db.withQueryHook(hook)`
**Then** 返回添加了钩子的新实例
**And** 原实例的钩子列表不变

**示例代码**:
```zig
var db = try DB(.postgresql).init(allocator, conn, .{});
defer db.deinit();

var logging = LoggingHook.init(true, 1000);
var logged_db = try db.withQueryHook(logging.hook());
defer logged_db.deinit();

try std.testing.expectEqual(@as(usize, 0), db.query_hooks.items.len);
try std.testing.expectEqual(@as(usize, 1), logged_db.query_hooks.items.len);
```

---

### Requirement: 查询执行

DB 实例 MUST支持执行 SQL 查询，返回结果或错误。

#### Scenario: 执行 exec 查询

**Given** 已创建的 DB 实例
**When** 调用 `db.exec(query_str, args)`
**Then** 执行 SQL 语句
**And** 记录查询统计
**And** 调用所有钩子的 beforeQuery
**And** 调用所有钩子的 afterQuery

**示例代码**:
```zig
var db = try DB(.postgresql).init(allocator, conn, .{});
defer db.deinit();

var logging = LoggingHook.init(true, 1000);
try db.addHook(logging.hook());

try db.exec("INSERT INTO users (name) VALUES ($1)", &[_]QueryArg{.{ .string = "Alice" }});

const stats = db.getStats();
try std.testing.expectEqual(@as(u64, 1), stats.getQueryCount());
```

#### Scenario: 执行 query 查询

**Given** 已创建的 DB 实例
**When** 调用 `db.query(query_str, args)`
**Then** 执行 SQL 查询
**And** 返回 Result 指针
**And** 调用者负责调用 result.close() 释放资源

**示例代码**:
```zig
var db = try DB(.postgresql).init(allocator, conn, .{});
defer db.deinit();

const result = try db.query("SELECT * FROM users WHERE id = $1", &[_]QueryArg{.{ .int = 123 }});
defer result.close();

// 使用结果...
```

#### Scenario: 查询失败时记录错误

**Given** 已创建的 DB 实例
**When** 查询执行失败
**Then** 记录错误统计
**And** 调用所有钩子的 onError
**And** 返回错误

**示例代码**:
```zig
var db = try DB(.postgresql).init(allocator, conn, .{});
defer db.deinit();

var logging = LoggingHook.init(true, 1000);
try db.addHook(logging.hook());

const result = db.query("INVALID SQL", &[_]QueryArg{});
try std.testing.expectError(error.QueryFailed, result);

const stats = db.getStats();
try std.testing.expectEqual(@as(u64, 1), stats.getErrorCount());
```

---

### Requirement: 查询构建器工厂方法

DB 实例 MUST提供工厂方法创建各种查询构建器。

#### Scenario: 创建 SELECT 查询构建器

**Given** 已创建的 DB 实例和模型类型
**When** 调用 `db.newSelect(User)`
**Then** 返回 SelectQuery 实例
**And** 查询构建器使用模型的 table_name 常量（如果有）
**And** 调用者负责调用 query.deinit() 释放资源

**示例代码**:
```zig
const User = struct {
    id: i64,
    name: []const u8,
    pub const table_name = "users";
};

var db = try DB(.postgresql).init(allocator, conn, .{});
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try std.testing.expectEqualStrings("users", query.table_name);
```

#### Scenario: 创建 INSERT 查询构建器

**Given** 已创建的 DB 实例
**When** 调用 `db.newInsert(User)`
**Then** 返回 InsertQuery 实例

**示例代码**:
```zig
var db = try DB(.postgresql).init(allocator, conn, .{});
defer db.deinit();

var insert = try db.newInsert(User);
defer insert.deinit();
```

#### Scenario: 创建 UPDATE 查询构建器

**Given** 已创建的 DB 实例
**When** 调用 `db.newUpdate(User)`
**Then** 返回 UpdateQuery 实例

#### Scenario: 创建 DELETE 查询构建器

**Given** 已创建的 DB 实例
**When** 调用 `db.newDelete(User)`
**Then** 返回 DeleteQuery 实例

#### Scenario: 创建 Raw SQL 查询

**Given** 已创建的 DB 实例
**When** 调用 `db.newRaw(sql, args)`
**Then** 返回 RawQuery 实例
**And** 支持窗口函数、CTE 等复杂查询

**示例代码**:
```zig
const sql =
    \\SELECT
    \\  u.id,
    \\  u.name,
    \\  RANK() OVER (ORDER BY COUNT(p.id) DESC) as rank
    \\FROM users u
    \\LEFT JOIN posts p ON p.user_id = u.id
    \\GROUP BY u.id, u.name
;

var query = try db.newRaw(sql, .{});
defer query.deinit();
```

---

### Requirement: 统计信息

DB 实例 MUST提供线程安全的统计信息访问。

#### Scenario: 记录和获取查询统计

**Given** 已创建的 DB 实例
**When** 执行多次查询
**Then** 统计信息正确累加
**And** 统计操作是原子的，线程安全

**示例代码**:
```zig
var db = try DB(.postgresql).init(allocator, conn, .{});
defer db.deinit();

try db.exec("SELECT 1", &[_]QueryArg{});
try db.exec("SELECT 2", &[_]QueryArg{});

const stats = db.getStats();
try std.testing.expectEqual(@as(u64, 2), stats.getQueryCount());
try std.testing.expectEqual(@as(u64, 0), stats.getErrorCount());
```

#### Scenario: 记录错误统计

**Given** 已创建的 DB 实例
**When** 查询执行失败
**Then** 错误计数器递增

**示例代码**:
```zig
var db = try DB(.postgresql).init(allocator, conn, .{});
defer db.deinit();

_ = db.query("INVALID SQL", &[_]QueryArg{}) catch {};

const stats = db.getStats();
try std.testing.expectEqual(@as(u64, 1), stats.getErrorCount());
```

---

### Requirement: 编译时方言获取

DB 实例 MUST提供编译时方言类型查询。

#### Scenario: 获取 DB 方言

**Given** DB 类型
**When** 调用 `DB(.postgresql).getDialect()`
**Then** 返回 `.postgresql`
**And** 此操作在编译时求值，零运行时开销

**示例代码**:
```zig
const PostgresDB = DB(.postgresql);
const MySQLDB = DB(.mysql);

try std.testing.expectEqual(Dialect.postgresql, PostgresDB.getDialect());
try std.testing.expectEqual(Dialect.mysql, MySQLDB.getDialect());
```

---

