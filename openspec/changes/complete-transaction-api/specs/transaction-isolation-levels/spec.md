# Specification: Transaction Isolation Levels

**Capability**: transaction-isolation-levels
**Status**: Implemented
**Related**: PRD Story 2.5

## ADDED Requirements

### Requirement: IsolationLevel 枚举定义
**ID**: TXI-001
**Priority**: P0
**Source**: PRD AC2.5.1

ZORM MUST 定义 `IsolationLevel` 枚举,包含四个标准 SQL 隔离级别。

#### Scenario: 枚举值定义正确
```zig
const level1 = IsolationLevel.read_uncommitted;
const level2 = IsolationLevel.read_committed;
const level3 = IsolationLevel.repeatable_read;
const level4 = IsolationLevel.serializable;

try std.testing.expect(level1 != level2);
try std.testing.expect(level2 != level3);
try std.testing.expect(level3 != level4);
```

#### Scenario: toSQL() 转换正确
```zig
try std.testing.expectEqualStrings("READ UNCOMMITTED", IsolationLevel.read_uncommitted.toSQL());
try std.testing.expectEqualStrings("READ COMMITTED", IsolationLevel.read_committed.toSQL());
try std.testing.expectEqualStrings("REPEATABLE READ", IsolationLevel.repeatable_read.toSQL());
try std.testing.expectEqualStrings("SERIALIZABLE", IsolationLevel.serializable.toSQL());
```

---

### Requirement: TxOptions 包含 isolation_level
**ID**: TXI-002
**Priority**: P0
**Source**: PRD AC2.5.2

`db.beginTx()` MUST 接受可选的 `TxOptions` 参数,包含 `isolation_level` 字段。

#### Scenario: TxOptions 默认值
```zig
const opts = TxOptions{};

try std.testing.expectEqual(@as(?IsolationLevel, null), opts.isolation_level);
try std.testing.expectEqual(false, opts.read_only);
try std.testing.expectEqual(@as(u64, 0), opts.timeout);
```

#### Scenario: 指定隔离级别
```zig
const opts = TxOptions{
    .isolation_level = .serializable,
};

var tx = try db.beginTx(opts);
defer tx.deinit();

try std.testing.expectEqual(IsolationLevel.serializable, tx.isolation_level.?);
```

---

### Requirement: 默认隔离级别
**ID**: TXI-003
**Priority**: P1
**Source**: PRD AC2.5.3

ZORM SHALL 默认使用 PostgreSQL 的默认隔离级别（read_committed）。

#### Scenario: 未指定隔离级别时使用默认值
```zig
var tx = try db.beginTx(.{});
defer tx.deinit();

// isolation_level 应为 null,表示使用数据库默认
try std.testing.expectEqual(@as(?IsolationLevel, null), tx.isolation_level);
```

#### Scenario: 验证数据库默认隔离级别
```zig
var tx = try db.beginTx(.{});
defer tx.deinit();

// 查询当前事务隔离级别
const sql = "SHOW transaction_isolation";
var query = try tx.newRaw(sql, .{});
defer query.deinit();

// 应为 "read committed" (PostgreSQL 默认)
```

---

### Requirement: 事务开始时设置隔离级别
**ID**: TXI-004
**Priority**: P0
**Source**: PRD AC2.5.4

ZORM MUST 在事务开始时执行 `SET TRANSACTION ISOLATION LEVEL` 语句。

#### Scenario: 执行 SET TRANSACTION ISOLATION LEVEL
```zig
const opts = TxOptions{
    .isolation_level = .serializable,
};

var tx = try db.beginTx(opts);
defer tx.deinit();

// 验证 SQL 已执行（通过日志或数据库状态）
// 预期执行: SET TRANSACTION ISOLATION LEVEL SERIALIZABLE
```

#### Scenario: 隔离级别在事务内生效
```zig
const opts = TxOptions{
    .isolation_level = .repeatable_read,
};

var tx = try db.beginTx(opts);
defer tx.deinit();

// 查询当前隔离级别
const sql = "SHOW transaction_isolation";
var query = try tx.newRaw(sql, .{});
defer query.deinit();

var results = std.ArrayList(struct { level: []const u8 }).init(allocator);
defer results.deinit();

try query.scan(&results);
try std.testing.expectEqualStrings("repeatable read", results.items[0].level);
```

---

### Requirement: 完整隔离级别示例
**ID**: TXI-005
**Priority**: P0
**Source**: PRD AC2.5.5

ZORM SHALL 支持符合 PRD 示例的完整隔离级别配置场景。

#### Scenario: serializable 隔离级别事务
```zig
const tx = try db.beginTx(.{
    .isolation_level = .serializable,
});
defer tx.deinit();
errdefer tx.rollback() catch {};

// 执行需要 serializable 级别的操作
var query = try tx.newSelect(User);
defer query.deinit();

var users = std.ArrayList(User).init(allocator);
defer users.deinit();

try query.where("balance > ?", .{1000}).scan(&users);

// 执行转账等关键操作
for (users.items) |user| {
    var update = try tx.newUpdate(User);
    defer update.deinit();

    try update
        .set("balance = balance - ?", .{100})
        .where("id = ?", .{user.id})
        .exec();
}

try tx.commit();
```

#### Scenario: read_committed 隔离级别事务
```zig
const tx = try db.beginTx(.{
    .isolation_level = .read_committed,
});
defer tx.deinit();

// 执行一般查询
var query = try tx.newSelect(User);
defer query.deinit();

var users = std.ArrayList(User).init(allocator);
defer users.deinit();

try query.scan(&users);
try tx.commit();
```

---

### Requirement: 隔离级别文档说明
**ID**: TXI-006
**Priority**: P1
**Source**: PRD Story 2.5 补充

IsolationLevel 枚举 MUST 提供详细的文档注释,说明每个级别的特性和适用场景。

#### Scenario: 文档注释包含关键信息
```zig
// 验证 IsolationLevel 类型存在文档注释
// 包含以下内容:
// - READ UNCOMMITTED: PostgreSQL 实际等同于 READ COMMITTED
// - READ COMMITTED: 默认级别,适用大多数 OLTP 应用
// - REPEATABLE READ: 避免 Non-repeatable Read,适用报表分析
// - SERIALIZABLE: 最高隔离级别,适用金融系统
```
