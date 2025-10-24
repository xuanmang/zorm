# Specification: Transaction Management API

**Capability**: transaction-management-api
**Status**: Implemented
**Related**: PRD Story 2.4

## ADDED Requirements

### Requirement: DB.beginTx() API
**ID**: TXM-001
**Priority**: P0
**Source**: PRD AC2.4.1

ZORM MUST 提供 `db.beginTx()` 方法开启事务,返回 `*TxManager` 事务管理器对象。

#### Scenario: 成功开启事务
```zig
var tx = try db.beginTx(.{});
defer tx.deinit();

try std.testing.expect(tx.is_active == true);
try std.testing.expect(tx.is_committed == false);
try std.testing.expect(tx.is_rolled_back == false);
```

#### Scenario: 嵌套事务被拒绝
```zig
var tx1 = try db.beginTx(.{});
defer tx1.deinit();

const tx2 = db.beginTx(.{});
try std.testing.expectError(error.NestedTransaction, tx2);
```

---

### Requirement: TxManager 查询构建器方法
**ID**: TXM-002
**Priority**: P0
**Source**: PRD AC2.4.2

TxManager MUST 提供与 DB 相同的查询构建器方法（newSelect、newInsert、newUpdate、newDelete、newRaw）。

#### Scenario: 事务中执行 INSERT
```zig
var tx = try db.beginTx(.{});
defer tx.deinit();
errdefer tx.rollback() catch {};

const user = User{ .id = 1, .name = "Alice", .email = "alice@example.com" };

var insert = try tx.newInsert(User);
defer insert.deinit();

try insert.value(user).exec();
try tx.commit();
```

#### Scenario: 事务中执行 SELECT
```zig
var tx = try db.beginTx(.{});
defer tx.deinit();

var users = std.ArrayList(User).init(allocator);
defer users.deinit();

var query = try tx.newSelect(User);
defer query.deinit();

try query.where("age > ?", .{18}).scan(&users);
try tx.commit();
```

---

### Requirement: tx.commit() 提交事务
**ID**: TXM-003
**Priority**: P0
**Source**: PRD AC2.4.3

TxManager MUST 提供 `tx.commit()` 方法提交事务,将所有更改持久化到数据库。

#### Scenario: 提交成功后状态更新
```zig
var tx = try db.beginTx(.{});
defer tx.deinit();

try tx.commit();

try std.testing.expect(tx.is_active == false);
try std.testing.expect(tx.is_committed == true);
try std.testing.expect(tx.is_rolled_back == false);
```

#### Scenario: 重复提交返回错误
```zig
var tx = try db.beginTx(.{});
defer tx.deinit();

try tx.commit();
const result = tx.commit();

try std.testing.expectError(error.AlreadyCommitted, result);
```

---

### Requirement: tx.rollback() 回滚事务
**ID**: TXM-004
**Priority**: P0
**Source**: PRD AC2.4.4

TxManager MUST 提供 `tx.rollback()` 方法回滚事务,撤销所有未提交的更改。

#### Scenario: 回滚成功后状态更新
```zig
var tx = try db.beginTx(.{});
defer tx.deinit();

try tx.rollback();

try std.testing.expect(tx.is_active == false);
try std.testing.expect(tx.is_committed == false);
try std.testing.expect(tx.is_rolled_back == true);
```

#### Scenario: rollback 幂等性
```zig
var tx = try db.beginTx(.{});
defer tx.deinit();

try tx.rollback();
try tx.rollback(); // 不应报错

try std.testing.expect(tx.is_rolled_back == true);
```

---

### Requirement: errdefer 自动回滚模式
**ID**: TXM-005
**Priority**: P0
**Source**: PRD AC2.4.5

TxManager MUST 支持 `errdefer tx.rollback()` 模式,错误发生时自动回滚事务。

#### Scenario: 错误时自动回滚
```zig
const result = blk: {
    var tx = try db.beginTx(.{});
    defer tx.deinit();
    errdefer tx.rollback() catch {};

    var insert = try tx.newInsert(User);
    defer insert.deinit();

    // 模拟错误
    if (should_fail) {
        break :blk error.TestError;
    }

    try tx.commit();
    break :blk {};
};

try std.testing.expectError(error.TestError, result);
// 验证事务已回滚（数据未插入）
```

---

### Requirement: 事务内操作共享连接
**ID**: TXM-006
**Priority**: P0
**Source**: PRD AC2.4.6

事务内的所有操作 MUST 共享同一个数据库连接,确保原子性。

#### Scenario: 验证连接复用
```zig
var tx = try db.beginTx(.{});
defer tx.deinit();

// 执行多个操作
var insert1 = try tx.newInsert(User);
defer insert1.deinit();
try insert1.value(user1).exec();

var insert2 = try tx.newInsert(Post);
defer insert2.deinit();
try insert2.value(post1).exec();

try tx.commit();
// 验证所有操作都在同一事务中（通过数据库日志或查询验证）
```

---

### Requirement: 嵌套事务检测
**ID**: TXM-007
**Priority**: P1
**Source**: PRD AC2.4.7

ZORM MUST 检测嵌套事务并返回错误（PostgreSQL 不支持真正的嵌套事务）。

#### Scenario: 检测并拒绝嵌套事务
```zig
var tx1 = try db.beginTx(.{});
defer tx1.deinit();

// 尝试开启第二个事务
const tx2 = db.beginTx(.{});

try std.testing.expectError(error.NestedTransaction, tx2);
```

#### Scenario: 提交后可以开启新事务
```zig
var tx1 = try db.beginTx(.{});
try tx1.commit();
tx1.deinit();

// 第一个事务已提交,可以开启新事务
var tx2 = try db.beginTx(.{});
defer tx2.deinit();

try std.testing.expect(tx2.is_active == true);
```

---

### Requirement: deinit() 自动回滚
**ID**: TXM-008
**Priority**: P0
**Source**: PRD AC2.4.5 (补充)

如果事务仍处于活动状态（未 commit 或 rollback）,`deinit()` MUST 自动回滚事务。

#### Scenario: deinit 自动回滚未提交事务
```zig
{
    var tx = try db.beginTx(.{});
    defer tx.deinit();

    var insert = try tx.newInsert(User);
    defer insert.deinit();
    try insert.value(user).exec();

    // 忘记调用 commit(),离开作用域
}

// 验证事务已自动回滚（数据未插入）
var users = std.ArrayList(User).init(allocator);
defer users.deinit();

var query = try db.newSelect(User);
defer query.deinit();
try query.scan(&users);

try std.testing.expect(users.items.len == 0);
```

---

### Requirement: 完整事务示例
**ID**: TXM-009
**Priority**: P0
**Source**: PRD AC2.4.8

ZORM MUST 支持符合 PRD 示例的完整事务使用场景。

#### Scenario: 用户和文章关联插入
```zig
const tx = try db.beginTx(.{});
defer tx.deinit();
errdefer tx.rollback() catch {};

// 插入用户
var insert_user = try tx.newInsert(User);
defer insert_user.deinit();

var inserted_users = std.ArrayList(User).init(allocator);
defer inserted_users.deinit();

try insert_user
    .value(user)
    .setReturning("*")
    .execReturning(&inserted_users);

if (inserted_users.items.len == 0) {
    try tx.rollback();
    return error.InsertFailed;
}

// 插入关联的文章
const post = Post{
    .user_id = inserted_users.items[0].id,
    .title = "My First Post",
    .content = "Hello, World!",
    .created_at = std.time.timestamp(),
};

var insert_post = try tx.newInsert(Post);
defer insert_post.deinit();

_ = try insert_post.value(post).exec();

// 提交事务
try tx.commit();
```
