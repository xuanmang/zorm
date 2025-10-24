# drop-table-query-api Specification

## Purpose

提供类型安全的 DROP TABLE Query Builder API，允许开发者通过简洁的链式调用从 Zig 结构体生成 PostgreSQL DROP TABLE 语句。支持 IF EXISTS、CASCADE 和 RESTRICT 选项，确保安全删除表结构。

## ADDED Requirements

### Requirement: newDropTable() 工厂方法

DB 实例 MUST 提供 `newDropTable(T)` 方法创建 DROP TABLE 查询构建器，T 为目标 Zig 结构体类型。

#### Scenario: 创建 DROP TABLE 查询构建器

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    pub const table_name = "users";
};

var query = try db.newDropTable(User);
defer query.deinit();

try std.testing.expect(query.allocator.ptr == allocator.ptr);
try std.testing.expectEqualStrings("users", query.table_name);
```

#### Scenario: 自动提取表名

```zig
const User = struct {
    id: i64,
    name: []const u8,
    pub const table_name = "custom_users";
};

var query = try db.newDropTable(User);
defer query.deinit();

try std.testing.expectEqualStrings("custom_users", query.table_name);
```

#### Scenario: 表名未定义时使用类型名

```zig
const Product = struct {
    id: i64,
    name: []const u8,
    // 未定义 table_name,应使用类型名
};

var query = try db.newDropTable(Product);
defer query.deinit();

// @typeName 返回完整的类型名,包括模块路径,所以检查是否包含 "Product"
try std.testing.expect(std.mem.indexOf(u8, query.table_name, "Product") != null);
```

---

### Requirement: ifExists() 方法添加 IF EXISTS 子句

DROP TABLE 查询构建器 MUST 提供 `ifExists()` 方法添加 IF EXISTS 子句，避免表不存在时报错。

#### Scenario: 添加 IF EXISTS 子句

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newDropTable(User);
defer query.deinit();

_ = query.ifExists();

const sql = try query.build();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "DROP TABLE IF EXISTS users") != null);
```

#### Scenario: 链式调用支持

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newDropTable(User);
defer query.deinit();

const sql = try query
    .ifExists()
    .build();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "IF EXISTS") != null);
```

---

### Requirement: cascade() 方法添加 CASCADE 选项

DROP TABLE 查询构建器 MUST 提供 `cascade()` 方法添加 CASCADE 选项，自动删除依赖此表的对象（如外键约束）。

#### Scenario: 添加 CASCADE 选项

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newDropTable(User);
defer query.deinit();

_ = query.cascade();

const sql = try query.build();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "DROP TABLE users CASCADE") != null);
```

#### Scenario: CASCADE 与 IF EXISTS 组合

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newDropTable(User);
defer query.deinit();

const sql = try query
    .ifExists()
    .cascade()
    .build();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "DROP TABLE IF EXISTS users CASCADE") != null);
```

---

### Requirement: restrict() 方法添加 RESTRICT 选项

DROP TABLE 查询构建器 MUST 提供 `restrict()` 方法添加 RESTRICT 选项，如果有依赖对象则拒绝删除并返回错误。这是 PostgreSQL 的默认行为，此方法用于显式声明。

#### Scenario: 添加 RESTRICT 选项

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newDropTable(User);
defer query.deinit();

_ = query.restrict();

const sql = try query.build();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "DROP TABLE users RESTRICT") != null);
```

#### Scenario: RESTRICT 与 IF EXISTS 组合

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newDropTable(User);
defer query.deinit();

const sql = try query
    .ifExists()
    .restrict()
    .build();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "DROP TABLE IF EXISTS users RESTRICT") != null);
```

---

### Requirement: CASCADE 和 RESTRICT 互斥行为

`cascade()` 和 `restrict()` 方法 MUST 是互斥的。调用其中一个方法应自动清除另一个选项的标志。

#### Scenario: CASCADE 覆盖 RESTRICT

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newDropTable(User);
defer query.deinit();

_ = query.restrict();
_ = query.cascade(); // 应覆盖 restrict

const sql = try query.build();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "CASCADE") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "RESTRICT") == null);
```

#### Scenario: RESTRICT 覆盖 CASCADE

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newDropTable(User);
defer query.deinit();

_ = query.cascade();
_ = query.restrict(); // 应覆盖 cascade

const sql = try query.build();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "RESTRICT") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "CASCADE") == null);
```

#### Scenario: 默认行为（无 CASCADE 或 RESTRICT）

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newDropTable(User);
defer query.deinit();

const sql = try query.build();
defer allocator.free(sql);

// 默认情况下不应包含 CASCADE 或 RESTRICT
try std.testing.expect(std.mem.indexOf(u8, sql, "CASCADE") == null);
try std.testing.expect(std.mem.indexOf(u8, sql, "RESTRICT") == null);
try std.testing.expect(std.mem.indexOf(u8, sql, "DROP TABLE users") != null);
```

---

### Requirement: build() 方法生成 SQL 语句

DROP TABLE 查询构建器 MUST 提供 `build()` 方法生成最终的 DROP TABLE SQL 语句。

#### Scenario: 生成基本 DROP TABLE SQL

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newDropTable(User);
defer query.deinit();

const sql = try query.build();
defer allocator.free(sql);

try std.testing.expectEqualStrings("DROP TABLE users", sql);
```

#### Scenario: 生成带所有选项的 SQL

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newDropTable(User);
defer query.deinit();

const sql = try query
    .ifExists()
    .cascade()
    .build();
defer allocator.free(sql);

try std.testing.expectEqualStrings("DROP TABLE IF EXISTS users CASCADE", sql);
```

---

### Requirement: exec() 方法执行 DROP TABLE

DROP TABLE 查询构建器 MUST 提供 `exec()` 方法执行 DROP TABLE 操作。

#### Scenario: 执行基本 DROP TABLE

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

// 创建测试表
var create = try db.newCreateTable(User);
defer create.deinit();
try create.ifNotExists().exec();

// 删除表
var drop = try db.newDropTable(User);
defer drop.deinit();
try drop.exec();

// 验证表已删除（再次删除应失败）
var drop2 = try db.newDropTable(User);
defer drop2.deinit();
try std.testing.expectError(error.DatabaseError, drop2.exec());
```

#### Scenario: 执行 DROP TABLE IF EXISTS（表不存在）

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

// 确保表不存在
var drop1 = try db.newDropTable(User);
defer drop1.deinit();
_ = drop1.ifExists().exec() catch {}; // 忽略错误

// 使用 IF EXISTS 删除不存在的表应成功
var drop2 = try db.newDropTable(User);
defer drop2.deinit();
try drop2.ifExists().exec(); // 应成功，不抛出错误
```

#### Scenario: 执行 DROP TABLE CASCADE

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

// 创建主表
var create_user = try db.newCreateTable(User);
defer create_user.deinit();
try create_user.ifNotExists().exec();

// 创建依赖表（有外键）
const Post = struct {
    id: i64,
    user_id: i64,
    title: []const u8,
    pub const table_name = "posts";
};

// 创建 posts 表（简化，实际需要添加外键约束）
var create_post = try db.newCreateTable(Post);
defer create_post.deinit();
try create_post.ifNotExists().exec();

// 删除主表（CASCADE 应同时删除依赖表）
var drop = try db.newDropTable(User);
defer drop.deinit();
try drop.cascade().exec();

// 验证主表和依赖表都已删除
var drop_post = try db.newDropTable(Post);
defer drop_post.deinit();
try std.testing.expectError(error.DatabaseError, drop_post.exec());
```

---

### Requirement: PRD 示例代码验证

PRD AC3.3.7 中的示例代码 MUST 可编译并运行。

#### Scenario: PRD 示例代码

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    pub const table_name = "users";
};

// 确保表存在
var create = try db.newCreateTable(User);
defer create.deinit();
try create.ifNotExists().exec();

// PRD 示例代码
var drop = try db.newDropTable(User);
defer drop.deinit();

try drop
    .ifExists()
    .cascade()
    .exec();

// 验证生成的 SQL
const sql = try db.newDropTable(User)
    .ifExists()
    .cascade()
    .build();
defer allocator.free(sql);

try std.testing.expectEqualStrings("DROP TABLE IF EXISTS users CASCADE", sql);
```
