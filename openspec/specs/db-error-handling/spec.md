# db-error-handling Specification

## Purpose
TBD - created by archiving change implement-db-instance-management. Update Purpose after archive.
## Requirements
### Requirement: 错误类型定义

DB 模块 MUST定义完整的错误集，覆盖所有可能的错误场景。

#### Scenario: 定义 ZORM 错误集

**Given** ZORM 核心模块
**When** 定义错误类型
**Then** 包含所有功能规格要求的错误类型

**错误定义**:
```zig
pub const Error = error{
    // 连接错误
    ConnectionFailed,
    ConnectionClosed,
    ConnectionTimeout,

    // 查询错误
    QueryFailed,
    QueryTimeout,
    InvalidSQL,

    // Schema 错误
    ModelNotFound,
    ColumnNotFound,
    InvalidType,

    // 事务错误
    TransactionAlreadyStarted,
    NoActiveTransaction,
    TransactionFailed,
    CommitFailed,
    RollbackFailed,

    // 数据错误
    NoRows,
    TooManyRows,
    ScanError,

    // 内存错误
    OutOfMemory,

    // 配置错误
    InvalidConfig,
    UnsupportedDialect,
};
```

#### Scenario: 错误类型在编译时已知

**Given** 函数返回 `!T` 类型
**When** 编译时
**Then** 编译器可以推断所有可能的错误类型
**And** 强制调用者处理或传播错误

---

### Requirement: 错误传播

所有可能失败的操作 MUST返回错误联合类型 `!T`，调用者必须处理或传播错误。

#### Scenario: 使用 try 传播错误

**Given** 函数调用可能失败的操作
**When** 使用 `try` 关键字
**Then** 错误自动传播给调用者

**示例代码**:
```zig
pub fn findUser(db: *DB, id: i64) !User {
    var query = try db.newSelect(User); // 传播错误
    defer query.deinit();

    try query.where("id = ?", .{id}); // 传播错误
    return try query.scanOne(); // 传播错误
}

// 调用者必须处理错误
const user = try findUser(db, 123); // 继续传播
// 或
const user = findUser(db, 123) catch |err| {
    // 处理错误
    std.log.err("Failed: {}", .{err});
    return err;
};
```

#### Scenario: 错误未处理导致编译错误

**Given** 函数返回 `!T`
**When** 调用者忘记处理错误
**Then** 编译器报错，强制处理

**示例代码**:
```zig
// ❌ 编译错误：必须处理错误
const user = findUser(db, 123);
// error: value with error set '!User' ignored

// ✅ 正确：使用 try 传播
const user = try findUser(db, 123);

// ✅ 正确：使用 catch 处理
const user = findUser(db, 123) catch |err| {
    std.log.err("Error: {}", .{err});
    return err;
};
```

---

### Requirement: 错误捕获和处理

调用者 MUST 能够使用 `catch` 捕获和处理错误，提供恢复机制。

#### Scenario: 使用 catch 处理错误

**Given** 函数可能返回错误
**When** 使用 `catch` 捕获错误
**Then** 可以提供默认值或恢复逻辑

**示例代码**:
```zig
pub fn findUserSafe(db: *DB, id: i64) ?User {
    return findUser(db, id) catch |err| {
        std.log.warn("User {} not found: {}", .{ id, err });
        return null; // 返回 null 而非错误
    };
}
```

#### Scenario: 错误恢复提供默认值

**Given** 查询可能失败
**When** 捕获错误并提供默认值
**Then** 函数总是返回有效值

**示例代码**:
```zig
pub fn findUserWithDefault(db: *DB, id: i64) User {
    return findUser(db, id) catch {
        std.log.warn("User {} not found, using default", .{id});
        return User{
            .id = -1,
            .name = "Unknown",
            .email = "",
            .created_at = 0,
            .updated_at = 0,
        };
    };
}
```

---

### Requirement: 错误类型判断

调用者 MUST 能够根据错误类型执行不同的处理逻辑。

#### Scenario: 使用 switch 判断错误类型

**Given** 捕获的错误
**When** 使用 `switch` 语句
**Then** 可以针对不同错误执行不同逻辑

**示例代码**:
```zig
pub fn handleQueryError(db: *DB, id: i64) !User {
    return findUser(db, id) catch |err| switch (err) {
        error.NoRows => {
            std.log.warn("User {} not found", .{id});
            return error.NoRows; // 重新抛出
        },
        error.ConnectionFailed => {
            std.log.err("Database connection failed", .{});
            // 可能重试连接
            return error.ConnectionFailed;
        },
        error.QueryTimeout => {
            std.log.warn("Query timeout, retrying...", .{});
            // 重试逻辑
            return error.QueryTimeout;
        },
        else => {
            std.log.err("Unexpected error: {}", .{err});
            return err;
        },
    };
}
```

#### Scenario: 针对特定错误的恢复

**Given** 查询可能返回 NoRows 错误
**When** 捕获 NoRows 错误
**Then** 返回空列表而非错误

**示例代码**:
```zig
pub fn findAllUsers(db: *DB) !std.ArrayList(User) {
    var users = std.ArrayList(User).init(db.allocator);
    errdefer users.deinit();

    var query = try db.newSelect(User);
    defer query.deinit();

    query.scan(&users) catch |err| switch (err) {
        error.NoRows => {
            // 没有数据不是错误，返回空列表
            std.log.debug("No users found", .{});
            return users;
        },
        else => return err,
    };

    return users;
}
```

---

### Requirement: errdefer 错误清理

错误发生时 MUST使用 errdefer 清理已分配的资源。

#### Scenario: 使用 errdefer 清理资源

**Given** 函数中分配多个资源
**When** 任何操作失败
**Then** errdefer 自动清理已分配的资源

**示例代码**:
```zig
pub fn loadUsersFromFile(allocator: Allocator, path: []const u8) !std.ArrayList(User) {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close(); // 正常退出时关闭

    var users = std.ArrayList(User).init(allocator);
    errdefer users.deinit(); // 错误时清理

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);
    errdefer allocator.free(content); // 错误时释放

    // 解析用户...
    // 如果失败，users 和 content 会自动清理

    return users;
}
```

#### Scenario: 嵌套 errdefer

**Given** 创建嵌套的资源
**When** 初始化失败
**Then** 按照反向顺序清理资源

**示例代码**:
```zig
pub fn createComplexQuery(allocator: Allocator) !*Query {
    const query = try allocator.create(Query);
    errdefer allocator.destroy(query);

    query.where_clauses = std.ArrayList(WhereClause).init(allocator);
    errdefer query.where_clauses.deinit();

    query.joins = std.ArrayList(JoinClause).init(allocator);
    errdefer query.joins.deinit();

    query.order_by = std.ArrayList(OrderClause).init(allocator);
    errdefer query.order_by.deinit();

    // 任何失败都会按照 LIFO 顺序清理
    return query;
}
```

---

### Requirement: 错误上下文

关键操作 MUST 记录错误上下文，便于调试。

#### Scenario: 记录错误日志

**Given** 操作失败
**When** 捕获错误
**Then** 记录详细的错误上下文

**示例代码**:
```zig
pub fn exec(self: *DB, query: []const u8, args: []const QueryArg) !void {
    const result = self.conn.exec(query, args);

    if (result) |_| {
        // 成功
    } else |err| {
        // 记录详细的错误上下文
        std.log.err(
            "Query execution failed: {s}\nQuery: {s}\nError: {}",
            .{ @errorName(err), query, err },
        );

        self.stats.recordError();

        // 执行错误钩子
        for (self.query_hooks.items) |hook| {
            hook.onError(query, args, err) catch |hook_err| {
                std.log.warn("Hook onError failed: {}", .{hook_err});
            };
        }

        return err;
    }
}
```

#### Scenario: 错误栈追踪

**Given** 调试模式
**When** 错误发生
**Then** 提供栈追踪信息

**示例代码**:
```zig
pub fn debugQuery(db: *DB, query: []const u8, args: []const QueryArg) !void {
    if (std.debug.runtime_safety) {
        const result = db.exec(query, args);
        if (result) |_| {
            // 成功
        } else |err| {
            std.debug.print("Query failed at:\n", .{});
            std.debug.dumpCurrentStackTrace(@returnAddress());
            return err;
        }
    } else {
        return db.exec(query, args);
    }
}
```

---

### Requirement: 错误传播链

错误 MUST 保留原始类型，避免丢失信息。

#### Scenario: 保留原始错误

**Given** 底层操作返回错误
**When** 包装函数捕获错误
**Then** 重新抛出原始错误类型

**示例代码**:
```zig
pub fn queryWrapper(db: *DB, sql: []const u8) !*Result {
    const result = db.query(sql, &[_]QueryArg{}) catch |err| {
        // 记录日志但保留原始错误
        std.log.debug("Query failed: {}", .{err});
        return err; // 原始错误类型
    };

    return result;
}
```

#### Scenario: 错误转换（谨慎使用）

**Given** 需要转换错误类型
**When** 确实需要隐藏实现细节
**Then** 明确文档说明转换原因

**示例代码**:
```zig
pub const APIError = error{
    UserNotFound,
    DatabaseError,
};

pub fn getUser(db: *DB, id: i64) APIError!User {
    return findUser(db, id) catch |err| switch (err) {
        error.NoRows => error.UserNotFound, // 转换为 API 错误
        else => {
            std.log.err("Database error: {}", .{err});
            return error.DatabaseError; // 转换为通用错误
        },
    };
}
```

---

### Requirement: Debug 模式配置

DB 模块 MUST 提供 debug 配置选项，用于启用调试模式下的 SQL 和参数打印。

#### Scenario: 配置 debug 选项为 true

**Given** 初始化 DB 实例
**When** 在 DBOptions 中设置 `debug: true`
**Then** 所有查询执行前自动打印 SQL 语句和参数
**And** 使用 `std.log.debug` 输出日志

**配置示例**:
```zig
const db = try DB(.postgresql).init(allocator, conn, .{
    .debug = true,
});
defer db.deinit();

// 执行查询时自动打印 SQL 和参数
var query = try db.newSelect(User);
defer query.deinit();

try query.where("age > $1", .{18}).scan(&users);
// Debug 输出:
// [ZORM Debug] Executing Query
// SQL: SELECT * FROM users WHERE age > $1
// Args: { 18 }
```

**验证**:
- debug 选项默认为 `false`
- debug = true 时，所有查询执行打印日志
- debug = false 时，不打印日志

---

#### Scenario: Debug 模式对性能的影响

**Given** debug 模式关闭 (`debug: false`)
**When** 执行查询操作
**Then** 不应有日志输出
**And** 性能开销 <1%（编译器优化掉未使用分支）

**Given** debug 模式开启 (`debug: true`)
**When** 执行查询操作
**Then** 日志输出不应显著影响性能
**And** 性能开销 <5%（PRD 要求）

**验证**:
- Benchmark 测试对比 debug = true 和 debug = false 的性能
- 使用 std.testing.allocator 验证无内存泄漏

---

### Requirement: 错误上下文增强

DB 模块 MUST 在错误发生时记录完整的错误上下文，包括 SQL 语句、参数和错误类型。

#### Scenario: 查询失败时记录错误上下文

**Given** 执行一个会失败的查询
**When** 查询执行失败
**Then** 使用 `std.log.err` 输出错误上下文
**And** 错误日志包含 SQL 语句、参数、错误类型

**错误日志格式**:
```
[ZORM Error] QueryFailed
SQL: SELECT * FROM nonexistent_table
Args: {}
Cause: relation "nonexistent_table" does not exist
```

**实现示例**:
```zig
pub fn exec(self: *Self, sql: []const u8, args: anytype) !void {
    const result = self.conn.exec(sql, args) catch |err| {
        std.log.err("[ZORM Error] {s}", .{@errorName(err)});
        std.log.err("SQL: {s}", .{sql});
        std.log.err("Args: {any}", .{args});
        return err;
    };
    _ = result;
}
```

**验证**:
- 错误日志包含所有必要的上下文信息
- 错误类型名称通过 `@errorName(err)` 正确获取
- 参数格式化为可读形式

---

#### Scenario: 连接失败时记录错误上下文

**Given** 数据库连接失败
**When** 尝试执行查询
**Then** 错误日志记录连接失败的详细信息
**And** 包含 SQL 语句和参数（如果有）

**错误日志示例**:
```
[ZORM Error] ConnectionFailed
SQL: SELECT * FROM users
Args: {}
Cause: connection to server failed
```

**验证**:
- 连接错误被正确记录
- 错误类型为 `ConnectionFailed`
- 上下文信息完整

---

### Requirement: Debug 日志格式

Debug 模式的日志输出 MUST 使用统一的格式，便于阅读和解析。

#### Scenario: Debug 日志的标准格式

**Given** debug 模式启用
**When** 执行任何查询操作
**Then** 日志输出使用以下格式：
```
[ZORM Debug] Executing Query
SQL: <SQL 语句>
Args: <参数列表>
```

**格式要求**:
- 第一行：`[ZORM Debug] Executing Query`
- 第二行：`SQL: <完整 SQL 语句>`
- 第三行：`Args: <参数格式化为 {any}>`

**示例**:
```
[ZORM Debug] Executing Query
SQL: INSERT INTO users (name, email) VALUES ($1, $2)
Args: { "Alice", "alice@example.com" }
```

**验证**:
- 日志格式符合标准
- SQL 语句完整显示（不截断）
- 参数格式化清晰可读

---

#### Scenario: 无参数查询的 Debug 日志

**Given** debug 模式启用
**When** 执行无参数的查询
**Then** Args 行显示空元组 `{}`

**示例**:
```
[ZORM Debug] Executing Query
SQL: SELECT * FROM users
Args: {}
```

**验证**:
- 无参数时 Args 显示为 `{}`
- 不省略 Args 行

---

### Requirement: 错误消息格式

错误日志 MUST 使用统一的格式，提供足够的上下文帮助调试。

#### Scenario: 错误消息的标准格式

**Given** 查询执行失败
**When** 记录错误日志
**Then** 使用以下格式：
```
[ZORM Error] <错误类型>
SQL: <SQL 语句>
Args: <参数列表>
Cause: <底层错误消息>
```

**格式要求**:
- 第一行：`[ZORM Error] <错误类型名称>`（通过 `@errorName(err)` 获取）
- 第二行：`SQL: <完整 SQL 语句>`
- 第三行：`Args: <参数格式化为 {any}>`
- 第四行（可选）：`Cause: <底层数据库错误消息>`

**示例**:
```
[ZORM Error] QueryFailed
SQL: UPDATE users SET name = $1 WHERE id = $2
Args: { "Bob", 999 }
Cause: no rows affected
```

**验证**:
- 错误类型名称正确（如 `QueryFailed`, `ConnectionFailed`）
- SQL 和 Args 完整显示
- Cause 信息来自底层驱动（如 pg.zig）

---

#### Scenario: 参数绑定错误的错误消息

**Given** 参数绑定失败（类型不匹配等）
**When** 记录错误
**Then** 错误消息包含参数信息，便于定位问题

**示例**:
```
[ZORM Error] InvalidType
SQL: SELECT * FROM users WHERE id = $1
Args: { "not_a_number" }
Cause: invalid input syntax for type bigint
```

**验证**:
- 错误类型为 `InvalidType`
- 参数值清晰显示（便于发现类型问题）
- Cause 说明具体的类型错误

---

### Requirement: Debug 模式的向后兼容性

Debug 模式的引入 MUST 保持向后兼容，不破坏现有代码。

#### Scenario: debug 选项的默认值

**Given** 现有代码未指定 debug 选项
**When** 初始化 DB 实例
**Then** debug 默认为 `false`
**And** 行为与之前版本完全一致（不打印 debug 日志）

**代码示例**:
```zig
// 旧代码：不指定 debug
const db = try DB(.postgresql).init(allocator, conn, .{});
defer db.deinit();

// 行为与之前版本一致（不打印 debug 日志）
```

**验证**:
- debug 默认值为 `false`
- 现有代码无需修改即可正常运行
- 不打印 debug 日志

---

#### Scenario: 启用 debug 不影响错误处理

**Given** debug 模式启用
**When** 查询失败
**Then** 错误传播机制不变
**And** 错误类型和错误处理逻辑与之前版本一致

**代码示例**:
```zig
const db = try DB(.postgresql).init(allocator, conn, .{
    .debug = true,
});
defer db.deinit();

// 错误处理与之前版本一致
const result = db.query("SELECT * FROM nonexistent_table", .{}) catch |err| {
    // err 类型为 Error.QueryFailed
    try std.testing.expectEqual(error.QueryFailed, err);
    return err;
};
```

**验证**:
- debug 模式不改变错误类型
- 错误传播机制不变
- 错误处理代码无需修改

