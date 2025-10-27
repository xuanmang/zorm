# Spec: Transaction 事务管理示例重构

## MODIFIED Requirements

### Requirement: 事务控制保留原始 SQL

**优先级**: P0
**依赖**: transaction-management-api

`transaction.zig` 示例 **SHALL** 继续使用 `db.exec()` 执行 BEGIN/COMMIT/ROLLBACK SQL 标准命令。

#### Scenario: 基础事务提交

**Given**: 已连接数据库,accounts 表已创建
**When**: 在事务中插入一条账户记录
**Then**:
- 使用 `_ = try db.exec("BEGIN", &[_]QueryArg{})` 开启事务
- 使用查询构建器执行插入操作
- 使用 `_ = try db.exec("COMMIT", &[_]QueryArg{})` 提交事务
- 数据持久化成功

```zig
_ = try db.exec("BEGIN", &[_]QueryArg{});

var insert = try db.newInsert(Account);
defer insert.deinit();

const account = Account{
    .id = 0,
    .username = "Alice",
    .balance = 1000.00,
};

try insert.values(&account);
_ = try insert.exec();

_ = try db.exec("COMMIT", &[_]QueryArg{});
```

#### Scenario: 事务回滚

**Given**: 已连接数据库,accounts 表中有 Alice 账户
**When**: 尝试插入重复的 Alice 账户,触发错误
**Then**:
- 使用 `BEGIN` 开启事务
- 插入操作失败时自动捕获错误
- 使用 `ROLLBACK` 回滚事务
- 数据库状态保持一致

```zig
_ = try db.exec("BEGIN", &[_]QueryArg{});

var insert = try db.newInsert(Account);
defer insert.deinit();

const account = Account{
    .id = 0,
    .username = "Alice", // 重复用户名
    .balance = 999.00,
};

try insert.values(&account);

if (insert.exec()) |_| {
    _ = try db.exec("COMMIT", &[_]QueryArg{});
} else |_| {
    _ = try db.exec("ROLLBACK", &[_]QueryArg{});
    // 事务已回滚
}
```

---

### Requirement: 事务中使用 INSERT 查询构建器

**优先级**: P0
**依赖**: insert-query-api, transaction-management-api

`transaction.zig` 示例 **MUST** 在事务内使用 `db.newInsert()` 查询构建器执行插入操作。

#### Scenario: 事务中批量插入账户

**Given**: 已开启事务
**When**: 插入 Frank 和 Grace 两个账户
**Then**:
- 使用 `db.newInsert(Account)` 创建查询
- 多次调用 `values()` 添加记录
- 在 COMMIT 前所有操作原子性执行

```zig
_ = try db.exec("BEGIN", &[_]QueryArg{});
errdefer _ = db.exec("ROLLBACK", &[_]QueryArg{}) catch {};

var insert1 = try db.newInsert(Account);
defer insert1.deinit();
try insert1.values(&Account{ .username = "Frank", .balance = 500.00 });
_ = try insert1.exec();

var insert2 = try db.newInsert(Account);
defer insert2.deinit();
try insert2.values(&Account{ .username = "Grace", .balance = 300.00 });
_ = try insert2.exec();

_ = try db.exec("COMMIT", &[_]QueryArg{});
```

---

### Requirement: 事务中使用 UPDATE 查询构建器

**优先级**: P0
**依赖**: update-query-api, transaction-management-api

`transaction.zig` 示例 **MUST** 在转账场景中使用 `db.newUpdate()` 查询构建器更新余额。

#### Scenario: 转账中的扣款操作

**Given**: 事务已开启,Frank 账户余额为 500.00
**When**: 从 Frank 账户扣款 100.00
**Then**:
- 使用 `var update = try db.newUpdate(Account)`
- 调用 `try update.set("balance", .{ .float = balance - 100.00 })`
- 调用 `try update.where("username", .eq, .{ .string = "Frank" })`
- 执行更新操作
- 影响行数为 1

```zig
// 在事务中
var update = try db.newUpdate(Account);
defer update.deinit();

try update.set("balance", .{ .float = 400.00 }); // 500 - 100
try update.where("username", .eq, .{ .string = "Frank" });

const result = try update.exec();
assert(result.rows_affected == 1);
```

#### Scenario: 转账中的加款操作

**Given**: 事务已开启,Grace 账户余额为 300.00
**When**: 向 Grace 账户加款 100.00
**Then**:
- 使用查询构建器更新余额
- 条件为 username = "Grace"
- 新余额为 400.00

---

### Requirement: 事务中使用 SELECT 查询构建器

**优先级**: P0
**依赖**: select-query-api, transaction-management-api

`transaction.zig` 示例 **MUST** 在转账前使用 `db.newSelect()` 查询构建器检查余额。

#### Scenario: 转账前检查余额

**Given**: 事务已开启,需要检查 Frank 账户余额
**When**: 查询 Frank 的当前余额
**Then**:
- 使用 `var query = try db.newSelect(Account)`
- 调用 `try query.column("balance")`
- 调用 `try query.where("username", .eq, .{ .string = "Frank" })`
- 读取余额并验证是否足够

```zig
var query = try db.newSelect(Account);
defer query.deinit();

try query.column("balance");
try query.where("username", .eq, .{ .string = "Frank" });

var rows = try query.exec();
defer rows.deinit();

if (try rows.next()) |row| {
    const current_balance = try row.getFloat(f64, 0);

    if (current_balance < amount) {
        return error.InsufficientBalance;
    }
}
```

---

### Requirement: 事务隔离级别设置

**优先级**: P1
**依赖**: transaction-isolation-levels

`transaction.zig` 示例 **MUST** 演示 READ COMMITTED, REPEATABLE READ, SERIALIZABLE 三种事务隔离级别。

#### Scenario: READ COMMITTED 隔离级别

**Given**: 需要设置事务隔离级别
**When**: 开启 READ COMMITTED 事务
**Then**:
- 使用 `BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED`
- 事务正常提交

```zig
_ = try db.exec("BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED", &[_]QueryArg{});
// ... 执行操作
_ = try db.exec("COMMIT", &[_]QueryArg{});
```

#### Scenario: REPEATABLE READ 隔离级别

**Given**: 需要更高的隔离级别
**When**: 开启 REPEATABLE READ 事务
**Then**: 使用相应的 SQL 语句

#### Scenario: SERIALIZABLE 隔离级别

**Given**: 需要最高的隔离级别
**When**: 开启 SERIALIZABLE 事务
**Then**: 使用相应的 SQL 语句

---

### Requirement: 转账场景完整实现

**优先级**: P0
**依赖**: update-query-api, select-query-api, transaction-management-api

`transaction.zig` 示例 **MUST** 完整实现转账场景,演示 ACID 特性。

#### Scenario: 完整的转账流程

**Given**: Frank 余额 500.00, Grace 余额 300.00
**When**: Frank 向 Grace 转账 100.00
**Then**:
1. 开启事务
2. 使用 SELECT 查询检查 Frank 余额
3. 使用 UPDATE 从 Frank 扣款
4. 使用 UPDATE 向 Grace 加款
5. 提交事务
6. Frank 最终余额 400.00, Grace 最终余额 400.00

```zig
fn transfer(db: anytype, from: []const u8, to: []const u8, amount: f64) !void {
    _ = try db.exec("BEGIN", &[_]QueryArg{});
    errdefer _ = db.exec("ROLLBACK", &[_]QueryArg{}) catch {};

    // 1. 检查余额
    var check = try db.newSelect(Account);
    defer check.deinit();
    try check.column("balance").where("username", .eq, .{ .string = from });

    var check_rows = try check.exec();
    defer check_rows.deinit();

    if (try check_rows.next()) |row| {
        const balance = try row.getFloat(f64, 0);
        if (balance < amount) {
            return error.InsufficientBalance;
        }
    }

    // 2. 扣款
    var deduct = try db.newUpdate(Account);
    defer deduct.deinit();
    try deduct.set("balance", .{ .float = balance - amount });
    try deduct.where("username", .eq, .{ .string = from });
    _ = try deduct.exec();

    // 3. 加款
    var credit = try db.newUpdate(Account);
    defer credit.deinit();
    try credit.set("balance", .{ .float = balance + amount });
    try credit.where("username", .eq, .{ .string = to });
    _ = try credit.exec();

    // 4. 提交
    _ = try db.exec("COMMIT", &[_]QueryArg{});
}
```

---

### Requirement: 错误处理使用 errdefer

**优先级**: P1
**依赖**: transaction-management-api

`transaction.zig` 示例 **MUST** 使用 Zig 的 `errdefer` 机制处理事务错误并自动回滚。

#### Scenario: errdefer 自动回滚

**Given**: 事务中可能发生错误
**When**: 任意操作抛出错误
**Then**:
- 使用 `errdefer _ = db.exec("ROLLBACK", &[_]QueryArg{}) catch {}`
- 错误发生时自动回滚
- 无需手动 if/else 处理

```zig
_ = try db.exec("BEGIN", &[_]QueryArg{});
errdefer _ = db.exec("ROLLBACK", &[_]QueryArg{}) catch {};

// 任意操作失败都会触发 errdefer
try someOperation();

_ = try db.exec("COMMIT", &[_]QueryArg{});
```
