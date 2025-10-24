# drop-index-query-api Specification

## Purpose
TBD - created by archiving change complete-drop-index-query-api. Update Purpose after archive.
## Requirements
### Requirement: newDropIndex() 工厂方法

DB 实例 SHALL 提供 `newDropIndex(T)` 方法创建 DROP INDEX 查询构建器,T 为目标表的 Zig 结构体类型。该方法 SHALL 返回已初始化的 DropIndexQuery 指针。

#### Scenario: 创建 DROP INDEX 查询构建器

**GIVEN** 用户有一个 User 结构体类型
**WHEN** 用户调用 `db.newDropIndex(User)`
**THEN** 返回一个 DropIndexQuery 实例
**AND** 查询构建器已正确初始化,allocator 和 db 指针已设置

```zig
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    pub const table_name = "users";
};

var query = try db.newDropIndex(User);
defer query.deinit();

try std.testing.expect(query.allocator.ptr == allocator.ptr);
try std.testing.expect(query.db == db);
```

#### Scenario: 类型参数用于 API 一致性

**GIVEN** DROP INDEX 不需要表名(PostgreSQL 索引是全局的)
**WHEN** 用户调用 `db.newDropIndex(T)`
**THEN** 类型参数 T 仅用于保持 API 与其他查询构建器一致
**AND** 实际生成的 SQL 不包含表名

---

### Requirement: index() 方法指定索引名称

DropIndexQuery SHALL 提供 `index(name)` 方法用于指定要删除的索引名称。该方法 SHALL 返回 self 指针以支持链式调用。

#### Scenario: 设置索引名称

**GIVEN** 用户创建了 DropIndexQuery 实例
**WHEN** 用户调用 `.index("idx_users_email")`
**THEN** 索引名称设置为 "idx_users_email"
**AND** 方法返回 self 指针支持链式调用

```zig
var query = try db.newDropIndex(User);
defer query.deinit();

const self = query.index("idx_users_email");
try std.testing.expect(self == query);
try std.testing.expectEqualStrings("idx_users_email", query.index_name.?);
```

#### Scenario: 未设置索引名称时构建失败

**GIVEN** 用户创建了 DropIndexQuery 但未调用 `.index()`
**WHEN** 用户调用 `.build()` 或 `.exec()`
**THEN** 返回 `error.IndexNameRequired` 错误

```zig
var query = try db.newDropIndex(User);
defer query.deinit();

try std.testing.expectError(error.IndexNameRequired, query.build());
try std.testing.expectError(error.IndexNameRequired, query.exec());
```

---

### Requirement: ifExists() 方法添加 IF EXISTS 子句

DropIndexQuery SHALL 提供 `ifExists()` 方法添加 IF EXISTS 子句,避免索引不存在时报错。该方法 SHALL 返回 self 指针以支持链式调用。

#### Scenario: 添加 IF EXISTS 子句

**GIVEN** 用户创建了 DropIndexQuery 实例
**WHEN** 用户调用 `.ifExists()`
**THEN** if_exists_flag 设置为 true
**AND** 生成的 SQL 包含 "IF EXISTS" 关键字

```zig
var query = try db.newDropIndex(User);
defer query.deinit();

_ = query.index("idx_users_email").ifExists();

const sql = try query.build();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "DROP INDEX IF EXISTS") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "idx_users_email") != null);
```

#### Scenario: 默认不包含 IF EXISTS

**GIVEN** 用户创建了 DropIndexQuery 但未调用 `.ifExists()`
**WHEN** 用户构建 SQL
**THEN** 生成的 SQL 不包含 "IF EXISTS" 关键字

```zig
var query = try db.newDropIndex(User);
defer query.deinit();

_ = query.index("idx_users_email");

const sql = try query.build();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "IF EXISTS") == null);
try std.testing.expectEqualStrings("DROP INDEX idx_users_email", sql);
```

---

### Requirement: cascade() 方法添加 CASCADE 选项

DropIndexQuery SHALL 提供 `cascade()` 方法添加 CASCADE 选项,自动删除依赖于该索引的对象。该方法 SHALL 返回 self 指针以支持链式调用。

#### Scenario: 添加 CASCADE 选项

**GIVEN** 用户创建了 DropIndexQuery 实例
**WHEN** 用户调用 `.cascade()`
**THEN** cascade_flag 设置为 true
**AND** 生成的 SQL 包含 "CASCADE" 关键字

```zig
var query = try db.newDropIndex(User);
defer query.deinit();

_ = query.index("idx_users_email").cascade();

const sql = try query.build();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "DROP INDEX idx_users_email CASCADE") != null);
```

#### Scenario: CASCADE 与 IF EXISTS 组合

**GIVEN** 用户需要同时使用 IF EXISTS 和 CASCADE
**WHEN** 用户链式调用 `.ifExists().cascade()`
**THEN** 生成的 SQL 同时包含两个关键字
**AND** 关键字顺序正确

```zig
var query = try db.newDropIndex(User);
defer query.deinit();

const sql = try query
    .index("idx_users_email")
    .ifExists()
    .cascade()
    .build();
defer allocator.free(sql);

try std.testing.expectEqualStrings("DROP INDEX IF EXISTS idx_users_email CASCADE", sql);
```

---

### Requirement: restrict() 方法添加 RESTRICT 选项

DropIndexQuery SHALL 提供 `restrict()` 方法添加 RESTRICT 选项,如果有依赖对象则拒绝删除。该方法 SHALL 返回 self 指针以支持链式调用。

#### Scenario: 添加 RESTRICT 选项

**GIVEN** 用户创建了 DropIndexQuery 实例
**WHEN** 用户调用 `.restrict()`
**THEN** restrict_flag 设置为 true
**AND** 生成的 SQL 包含 "RESTRICT" 关键字

```zig
var query = try db.newDropIndex(User);
defer query.deinit();

_ = query.index("idx_users_email").restrict();

const sql = try query.build();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "DROP INDEX idx_users_email RESTRICT") != null);
```

#### Scenario: RESTRICT 与 IF EXISTS 组合

**GIVEN** 用户需要同时使用 IF EXISTS 和 RESTRICT
**WHEN** 用户链式调用 `.ifExists().restrict()`
**THEN** 生成的 SQL 同时包含两个关键字
**AND** 关键字顺序正确

```zig
var query = try db.newDropIndex(User);
defer query.deinit();

const sql = try query
    .index("idx_users_email")
    .ifExists()
    .restrict()
    .build();
defer allocator.free(sql);

try std.testing.expectEqualStrings("DROP INDEX IF EXISTS idx_users_email RESTRICT", sql);
```

---

### Requirement: CASCADE 和 RESTRICT 互斥行为

`cascade()` 和 `restrict()` 方法 SHALL 是互斥的。调用其中一个方法 SHALL 自动清除另一个选项的标志。

#### Scenario: CASCADE 覆盖 RESTRICT

**GIVEN** 用户先调用了 `.restrict()`
**WHEN** 用户再调用 `.cascade()`
**THEN** cascade_flag 为 true,restrict_flag 为 false
**AND** 生成的 SQL 仅包含 "CASCADE",不包含 "RESTRICT"

```zig
var query = try db.newDropIndex(User);
defer query.deinit();

const sql = try query
    .index("idx_users_email")
    .restrict()
    .cascade()
    .build();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "CASCADE") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "RESTRICT") == null);
try std.testing.expectEqualStrings("DROP INDEX idx_users_email CASCADE", sql);
```

#### Scenario: RESTRICT 覆盖 CASCADE

**GIVEN** 用户先调用了 `.cascade()`
**WHEN** 用户再调用 `.restrict()`
**THEN** restrict_flag 为 true,cascade_flag 为 false
**AND** 生成的 SQL 仅包含 "RESTRICT",不包含 "CASCADE"

```zig
var query = try db.newDropIndex(User);
defer query.deinit();

const sql = try query
    .index("idx_users_email")
    .cascade()
    .restrict()
    .build();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "RESTRICT") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "CASCADE") == null);
try std.testing.expectEqualStrings("DROP INDEX idx_users_email RESTRICT", sql);
```

#### Scenario: 默认不包含 CASCADE 或 RESTRICT

**GIVEN** 用户未调用 `.cascade()` 或 `.restrict()`
**WHEN** 用户构建 SQL
**THEN** 生成的 SQL 不包含 "CASCADE" 或 "RESTRICT" 关键字
**AND** PostgreSQL 使用默认的 RESTRICT 行为

```zig
var query = try db.newDropIndex(User);
defer query.deinit();

const sql = try query
    .index("idx_users_email")
    .build();
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "CASCADE") == null);
try std.testing.expect(std.mem.indexOf(u8, sql, "RESTRICT") == null);
try std.testing.expectEqualStrings("DROP INDEX idx_users_email", sql);
```

---

### Requirement: build() 方法生成 SQL 语句

DropIndexQuery SHALL 提供 `build()` 方法生成最终的 DROP INDEX SQL 语句。该方法 SHALL 返回分配的 SQL 字符串,调用者负责释放内存。

#### Scenario: 生成基本 DROP INDEX SQL

**GIVEN** 用户配置了索引名称
**WHEN** 用户调用 `.build()`
**THEN** 返回格式正确的 DROP INDEX SQL 字符串
**AND** SQL 格式为 "DROP INDEX index_name"

```zig
var query = try db.newDropIndex(User);
defer query.deinit();

const sql = try query
    .index("idx_users_email")
    .build();
defer allocator.free(sql);

try std.testing.expectEqualStrings("DROP INDEX idx_users_email", sql);
```

#### Scenario: 生成带所有选项的 SQL

**GIVEN** 用户配置了所有支持的选项
**WHEN** 用户调用 `.build()`
**THEN** 返回包含所有选项的完整 SQL 语句
**AND** 关键字顺序正确

```zig
var query = try db.newDropIndex(User);
defer query.deinit();

const sql = try query
    .index("idx_users_email")
    .ifExists()
    .cascade()
    .build();
defer allocator.free(sql);

try std.testing.expectEqualStrings("DROP INDEX IF EXISTS idx_users_email CASCADE", sql);
```

#### Scenario: 调用者负责释放内存

**GIVEN** 用户调用了 `.build()` 获取 SQL 字符串
**WHEN** 用户使用完 SQL 字符串后
**THEN** 必须使用 allocator.free() 释放内存
**AND** 使用 defer 模式确保正确清理

---

### Requirement: exec() 方法执行 DROP INDEX

DropIndexQuery SHALL 提供 `exec()` 方法执行 DROP INDEX DDL 语句。该方法 SHALL 在数据库连接上执行生成的 SQL,并返回执行结果。

#### Scenario: 执行基本 DROP INDEX

**GIVEN** 用户创建了一个索引
**AND** 用户配置了 DropIndexQuery
**WHEN** 用户调用 `.exec()`
**THEN** DROP INDEX SQL 在数据库中执行
**AND** 索引被成功删除

```zig
// 先创建索引
var create_idx = try db.newCreateIndex(User);
defer create_idx.deinit();
try create_idx
    .index("idx_users_email")
    .column("email")
    .exec();

// 删除索引
var drop_idx = try db.newDropIndex(User);
defer drop_idx.deinit();
try drop_idx
    .index("idx_users_email")
    .exec();

// 验证索引已删除(再次删除应失败)
var drop_idx2 = try db.newDropIndex(User);
defer drop_idx2.deinit();
try std.testing.expectError(error.DatabaseError, drop_idx2.index("idx_users_email").exec());
```

#### Scenario: 执行 DROP INDEX IF EXISTS(索引不存在)

**GIVEN** 索引不存在于数据库中
**WHEN** 用户调用 `.ifExists().exec()`
**THEN** 执行成功,不抛出错误
**AND** 操作幂等,可重复执行

```zig
var drop_idx = try db.newDropIndex(User);
defer drop_idx.deinit();

// 第一次删除(索引可能不存在)
try drop_idx.index("idx_nonexistent").ifExists().exec();

// 第二次删除(索引肯定不存在),应仍然成功
try drop_idx.index("idx_nonexistent").ifExists().exec();
```

#### Scenario: 执行 DROP INDEX CASCADE

**GIVEN** 用户需要级联删除依赖对象
**WHEN** 用户调用 `.cascade().exec()`
**THEN** PostgreSQL 删除索引及其所有依赖对象
**AND** 不会因为依赖对象存在而失败

---

### Requirement: 链式调用支持(Fluent Interface)

所有配置方法 SHALL 返回 `*Self` 指针,SHALL 支持链式调用以提升代码可读性。

#### Scenario: 链式调用配置

**GIVEN** 用户创建了 DropIndexQuery 实例
**WHEN** 用户使用链式调用配置查询
**THEN** 所有配置方法正确应用
**AND** 代码简洁易读

```zig
var drop_idx = try db.newDropIndex(User);
defer drop_idx.deinit();

try drop_idx
    .index("idx_users_email")
    .ifExists()
    .cascade()
    .exec();
```

#### Scenario: 方法调用顺序不影响结果

**GIVEN** 用户以不同顺序调用配置方法
**WHEN** 用户构建 SQL
**THEN** 生成的 SQL 格式一致
**AND** 仅最后调用的互斥选项生效

```zig
// 顺序 1
var query1 = try db.newDropIndex(User);
defer query1.deinit();
const sql1 = try query1.index("idx").ifExists().cascade().build();
defer allocator.free(sql1);

// 顺序 2
var query2 = try db.newDropIndex(User);
defer query2.deinit();
const sql2 = try query2.ifExists().cascade().index("idx").build();
defer allocator.free(sql2);

try std.testing.expectEqualStrings(sql1, sql2);
```

---

### Requirement: 显式内存管理

系统 SHALL 使用 Zig Allocator 模式进行显式内存管理,SHALL 提供 `deinit()` 方法释放资源,SHALL 支持 `defer` 清理模式。

#### Scenario: 资源释放

**GIVEN** 用户创建了 DropIndexQuery 实例
**WHEN** 用户调用 `query.deinit()`
**THEN** 所有分配的内存被释放
**AND** 查询对象本身被销毁

```zig
var query = try db.newDropIndex(User);
query.deinit(); // 显式释放

// query 指针不再有效,不应再使用
```

#### Scenario: defer 模式

**GIVEN** 用户使用 defer 管理资源
**WHEN** 作用域结束时
**THEN** defer 自动调用 deinit()
**AND** 错误路径也正确清理资源

```zig
{
    var query = try db.newDropIndex(User);
    defer query.deinit();

    // 使用 query
    _ = query.index("idx_users_email");

    // 可能的错误路径
    if (some_condition) return error.SomeError;

    // defer 确保所有路径都清理资源
}
```

#### Scenario: 无内存泄漏

**GIVEN** 使用 std.testing.allocator 运行测试
**WHEN** 执行所有测试
**THEN** 无内存泄漏报告
**AND** 所有资源正确释放

---

### Requirement: 完整的错误处理

系统 SHALL 对所有可能失败的操作返回错误联合类型(`!T`),强制调用者处理错误。错误消息 SHALL 清晰明确,包含足够的上下文信息。

#### Scenario: 必需参数缺失错误

**GIVEN** 用户未提供索引名称
**WHEN** 用户调用 `.build()` 或 `.exec()`
**THEN** 返回 `error.IndexNameRequired` 错误
**AND** 错误消息明确指出缺少索引名称

```zig
var query = try db.newDropIndex(User);
defer query.deinit();

try std.testing.expectError(error.IndexNameRequired, query.build());
try std.testing.expectError(error.IndexNameRequired, query.exec());
```

#### Scenario: 数据库执行错误

**GIVEN** 索引不存在且未使用 IF EXISTS
**WHEN** 用户调用 `.exec()`
**THEN** 返回数据库错误
**AND** 错误消息包含索引名称信息

```zig
var query = try db.newDropIndex(User);
defer query.deinit();

// 删除不存在的索引应失败
try std.testing.expectError(error.DatabaseError,
    query.index("idx_nonexistent").exec()
);
```

---

### Requirement: PRD 示例代码验证

PRD AC3.5.6 中的示例代码 SHALL 可编译并正确运行。

#### Scenario: PRD 示例代码

**GIVEN** PRD Story 3.5 中的示例代码
**WHEN** 示例代码编译并执行
**THEN** 所有操作成功完成
**AND** 生成的 SQL 与 PRD 注释一致

```zig
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    pub const table_name = "users";
};

// 先创建索引
var create_idx = try db.newCreateIndex(User);
defer create_idx.deinit();
try create_idx
    .index("idx_users_email")
    .column("email")
    .exec();

// PRD 示例代码
var drop_idx = try db.newDropIndex(User);
defer drop_idx.deinit();

try drop_idx
    .index("idx_users_email")
    .ifExists()
    .exec();

// 验证生成的 SQL
const sql = try db.newDropIndex(User)
    .index("idx_users_email")
    .ifExists()
    .build();
defer allocator.free(sql);

// 生成的 SQL: DROP INDEX IF EXISTS idx_users_email
try std.testing.expectEqualStrings("DROP INDEX IF EXISTS idx_users_email", sql);
```

---

### Requirement: 完整的测试覆盖

系统 SHALL 提供完整的单元测试和集成测试,覆盖所有 API 方法和错误场景。

#### Scenario: 单元测试覆盖所有方法

**GIVEN** DropIndexQuery 实现完成
**WHEN** 运行单元测试
**THEN** 所有公共方法都有对应的单元测试
**AND** 覆盖率达到 80% 以上

#### Scenario: 集成测试验证真实场景

**GIVEN** 真实的 PostgreSQL 数据库连接
**WHEN** 执行集成测试
**THEN** 所有 DROP INDEX 操作在真实数据库中成功执行
**AND** IF EXISTS、CASCADE、RESTRICT 选项正确生效

#### Scenario: 内存泄漏检测

**GIVEN** 使用 `std.testing.allocator` 运行测试
**WHEN** 执行所有测试
**THEN** 无内存泄漏报告
**AND** 所有资源正确释放

