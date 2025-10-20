# DB 错误处理规范

## 能力标识
`db-error-handling`

## 概述

定义 ZORM DB 实例的错误处理策略和模式，使用 Zig 错误联合类型实现编译时强制错误处理。符合功能规格说明书 2.1.3 节要求。

## ADDED Requirements

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

## MODIFIED Requirements

无

---

## REMOVED Requirements

无

---

## 依赖关系

### 依赖于
- `std.log` - 日志记录
- `std.debug` - 调试工具

### 被依赖于
- 所有使用 DB 的模块
- 查询构建器
- 事务管理

---

## 验证标准

- [ ] 所有错误类型都已定义
- [ ] 所有可能失败的操作返回 `!T`
- [ ] 测试覆盖所有错误分支
- [ ] 错误处理示例完整
- [ ] 错误日志有足够上下文
- [ ] 文档说明错误处理最佳实践
