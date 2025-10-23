# Transaction Management API - Design Document

## Architecture Overview

### Component Hierarchy
```
DB(.postgresql)
  └── beginTx(opts: TxOptions) -> *TxManager(.postgresql)
        ├── commit()
        ├── rollback()
        ├── deinit()  // Auto-rollback if not committed
        └── Query Builders
              ├── newSelect(T)
              ├── newInsert(T)
              ├── newUpdate(T)
              ├── newDelete(T)
              └── newRaw(sql, args)
```

## Design Principles

### 1. Compile-Time Dialect Parameterization
事务管理器使用 comptime 泛型参数化方言，实现零运行时开销：

```zig
pub fn TxManager(comptime dialect: Dialect) type {
    const DBType = db_mod.DB(dialect);
    // ...
}
```

**优势**：
- 类型安全：不同方言的 TxManager 是不同的类型
- 零运行时开销：方言选择在编译时确定
- 查询构建器泛型复用：TxManager 可以调用同一方言的查询构建器

### 2. Resource Management Pattern
ZORM 采用 Zig 的 RAII 模式（defer/errdefer）确保资源清理：

```zig
var tx = try db.beginTx(.{});
defer tx.deinit();  // 确保未提交的事务自动回滚
errdefer tx.rollback() catch {};  // 错误时显式回滚
```

**关键实现**：
- `deinit()` 方法：检查 `is_active` 标志，如果事务仍活动则自动回滚
- `commit()/rollback()` 方法：幂等性设计，多次调用不会崩溃
- `is_committed/is_rolled_back` 状态：防止重复操作

### 3. Nested Transaction Detection
PostgreSQL 不支持真正的嵌套事务（必须使用 Savepoint），因此 ZORM 在 `beginTx()` 时检测活动事务：

```zig
pub fn init(allocator: Allocator, db: *DBType, opts: TxOptions) !*Self {
    if (db.active_tx != null) {
        return Error.NestedTransaction;  // 立即返回错误
    }
    // ...
}
```

**设计选择**：
- **严格禁止嵌套**：避免用户误用导致数据不一致
- **DB 级别标记**：`db.active_tx` 指针追踪活动事务
- **清理机制**：commit/rollback 后置 `db.active_tx = null`

**未来扩展**：
如果需要嵌套事务，可以：
1. 使用 `transaction.zig` 中的 Savepoint 机制
2. 或者自动转换为 Savepoint（类似 Ruby on Rails）

### 4. Isolation Level Configuration
隔离级别通过 `TxOptions` 传递，在事务开始时设置：

```zig
if (opts.isolation_level) |level| {
    const sql = try std.fmt.allocPrint(
        allocator,
        "SET TRANSACTION ISOLATION LEVEL {s}",
        .{level.toSQL()},
    );
    defer allocator.free(sql);
    try tx.exec(sql, &[_]QueryArg{});
}
```

**关键细节**：
- **PostgreSQL 要求**：`SET TRANSACTION ISOLATION LEVEL` 必须在事务内的第一个语句
- **可选配置**：`?IsolationLevel` 允许 null，默认使用 PostgreSQL 默认级别（READ COMMITTED）
- **SQL 安全**：`toSQL()` 方法生成固定的 SQL 字符串，无 SQL 注入风险

## Key Design Decisions

### Decision 1: TxManager vs Transaction
**选择**：使用 `TxManager(dialect)` 而非 `Transaction(dialect)`

**理由**：
- 避免与底层 `Tx` 接口命名冲突
- "Manager" 语义更清晰：管理事务的生命周期，不仅仅是"一个事务"
- 与 `DB` 实例平级：`DB` 管理连接，`TxManager` 管理事务

### Decision 2: Pointer-Based API
**选择**：`beginTx()` 返回 `*TxManager` 指针，而非值类型

**理由**：
- **内存管理清晰**：用户显式调用 `deinit()` 释放
- **状态追踪**：事务状态（is_active, is_committed）需要在整个生命周期中维护
- **defer 模式**：`defer tx.deinit()` 语义自然

**权衡**：
- 优势：资源管理明确，符合 Zig 惯例
- 劣势：用户必须记得调用 `deinit()`（但 defer 强制执行）

### Decision 3: State Tracking
**选择**：维护 `is_active`, `is_committed`, `is_rolled_back` 三个布尔标志

**理由**：
- **幂等性**：`commit()` 和 `rollback()` 可以安全地多次调用
- **错误检测**：防止 "已提交的事务被回滚" 等逻辑错误
- **调试友好**：明确的状态标志便于日志记录和错误消息

**状态转换图**：
```
[Init] -> is_active=true, is_committed=false, is_rolled_back=false
  ├─> [commit()] -> is_active=false, is_committed=true
  ├─> [rollback()] -> is_active=false, is_rolled_back=true
  └─> [deinit()] -> 如果 is_active=true，调用 rollback()
```

### Decision 4: Query Builder Integration
**选择**：TxManager 直接提供查询构建器工厂方法

**理由**：
- **API 一致性**：`db.newSelect(User)` 和 `tx.newSelect(User)` 语义相同
- **上下文自动绑定**：查询构建器自动使用事务连接，无需用户手动传递
- **类型安全**：comptime 方言参数确保查询构建器与事务方言匹配

**实现细节**：
```zig
pub fn newSelect(self: *Self, comptime T: type) !*SelectQuery(T, dialect) {
    // 复用 DB 的查询构建器，但使用事务的 DB 实例
    return SelectQuery(T, dialect).init(self.allocator, self.db, table_name);
}
```

注意：虽然传递的是 `self.db`，但 `db.active_tx` 已设置，查询会自动路由到事务。

## Error Handling Strategy

### 错误类型层次
```zig
Error.NestedTransaction         // 嵌套事务检测
Error.TransactionNotActive       // 事务未激活
Error.AlreadyCommitted           // 已提交
Error.AlreadyRolledBack          // 已回滚
Error.OutOfMemory                // 内存分配失败
```

### 错误传播
- `commit()` 失败：设置 `is_active=false`，清理 `db.active_tx`，向上传播错误
- `rollback()` 失败：设置 `is_active=false`，清理 `db.active_tx`，向上传播错误
- `deinit()` 自动回滚失败：仅记录警告日志（`std.log.warn`），不崩溃

### 幂等性保证
```zig
pub fn rollback(self: *Self) !void {
    if (!self.is_active or self.is_rolled_back) {
        return;  // 幂等：已回滚或未激活，直接返回
    }
    // ...
}
```

## Performance Considerations

### 1. Zero Runtime Overhead for Dialect Selection
方言选择在 comptime 完成，生成的机器码针对特定方言优化。

### 2. Minimal Memory Allocations
- TxManager 实例：单次 `allocator.create(Self)` 分配
- 隔离级别 SQL：临时分配，立即释放（`defer allocator.free(sql)`）
- 状态标志：栈内存，无堆分配

### 3. Connection Reuse
事务复用 DB 的连接池连接，避免重复建立连接的开销。

## Testing Strategy

### Unit Tests
- TxOptions 默认值
- TxManager 类型实例化
- 状态标志正确性

### Integration Tests
- ✅ 事务提交场景（插入数据并提交）
- ✅ 事务回滚场景（插入数据后回滚）
- ✅ errdefer 自动回滚
- ✅ 嵌套事务检测
- ⏳ 隔离级别设置（验证 SET TRANSACTION ISOLATION LEVEL 执行）
- ⏳ 幂等性测试（重复 commit/rollback）
- ⏳ 查询构建器在事务中的使用

### Memory Leak Tests
所有测试使用 `std.testing.allocator`，确保无内存泄漏。

## Future Enhancements

### 1. Savepoint Support (Epic 3+)
自动将嵌套 `beginTx()` 转换为 Savepoint：
```zig
var tx1 = try db.beginTx(.{});
defer tx1.deinit();

var tx2 = try tx1.beginSavepoint("sp1");  // 新方法
defer tx2.deinit();
```

### 2. Transaction Hooks
在事务生命周期中触发钩子：
```zig
hook.onBeginTx(tx);
hook.onCommit(tx, duration_ns);
hook.onRollback(tx, err);
```

### 3. Read-Only Transactions
```zig
var tx = try db.beginTx(.{ .read_only = true });
```

PostgreSQL: `SET TRANSACTION READ ONLY`

### 4. Connection Pool Integration
为长事务提供连接池优化，避免阻塞其他查询。

## References
- PostgreSQL Documentation: [Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
- Zig Language Reference: [defer and errdefer](https://ziglang.org/documentation/master/#defer)
- Bun ORM: [Transaction API](https://bun.sh/docs/api/orm#transactions)
