# error-type-aliases Specification

## Purpose
定义错误处理系统的类型别名，提供语义化的查询结果类型，使 API 签名更清晰、更易理解。

## Context
ZORM 使用 Zig 的错误联合类型 `!T` 作为所有可能失败操作的返回类型。为了提升代码可读性和语义清晰性，功能规格说明书 2.1.3 定义了两个类型别名：
- `QueryResult(T)`: 泛型查询结果类型，等价于 `Error!T`
- `VoidResult`: 空结果类型，等价于 `Error!void`

这些类型别名提供零运行时开销，符合 Zig 的零成本抽象原则。

## ADDED Requirements

### Requirement: QueryResult 泛型类型别名定义

错误处理模块 MUST 提供 `QueryResult(T)` 泛型类型别名，作为 `Error!T` 的语义化替代。

#### Scenario: 定义 QueryResult 泛型类型别名

**Given** 错误处理模块 `src/error.zig`
**When** 定义 `QueryResult(T)` 类型别名
**Then** 返回 `Error!T` 类型
**And** 类型别名可用于任意类型 T

**实现代码**:
```zig
/// 查询结果类型
///
/// 所有查询操作返回此类型，明确表达操作可能成功返回 T 或失败返回错误。
/// 这是 `Error!T` 的语义化别名，提供零运行时开销。
///
/// ## 使用场景
/// - 数据库查询操作（SELECT）
/// - 数据获取操作（GET, FIND）
/// - 任何返回数据的可能失败操作
///
/// ## 示例
/// ```zig
/// // 函数签名
/// pub fn findUser(db: *DB, id: i64) QueryResult(User) {
///     var query = try db.newSelect(User);
///     defer query.deinit();
///     try query.where("id = ?", .{id});
///     return query.scanOne();
/// }
///
/// // 使用
/// const user = try findUser(db, 123);
/// ```
pub fn QueryResult(comptime T: type) type {
    return Error!T;
}
```

**验证**:
- 编译时类型检查通过
- `QueryResult(User)` 与 `Error!User` 完全等价
- 可用于任意类型参数

---

#### Scenario: QueryResult 在函数签名中使用

**Given** 定义了返回用户数据的查询函数
**When** 使用 `QueryResult(User)` 作为返回类型
**Then** 函数签名清晰表达返回查询结果
**And** 调用者必须处理可能的错误

**示例代码**:
```zig
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
};

/// 根据 ID 查找用户
pub fn findUserById(db: *DB, id: i64) QueryResult(User) {
    var query = try db.newSelect(User);
    defer query.deinit();

    try query.where("id = ?", .{id});
    return query.scanOne();
}

/// 调用示例
pub fn example(db: *DB) !void {
    // 使用 try 传播错误
    const user = try findUserById(db, 123);
    std.debug.print("User: {s}\n", .{user.name});

    // 使用 catch 处理错误
    const user_or_null = findUserById(db, 456) catch |err| {
        std.log.warn("User not found: {}", .{err});
        return;
    };
}
```

**验证**:
- 函数签名使用 `QueryResult(User)` 代替 `Error!User`
- 编译器强制错误处理
- 语义清晰，易于理解

---

#### Scenario: QueryResult 与 Error!T 完全兼容

**Given** 已有使用 `Error!T` 的代码
**When** 引入 `QueryResult(T)` 类型别名
**Then** 两种写法完全兼容，可以互换使用
**And** 不破坏现有代码

**兼容性示例**:
```zig
// 旧代码：使用 Error!User
pub fn oldFunction() Error!User {
    return User{ .id = 1, .name = "Alice", .email = "alice@example.com" };
}

// 新代码：使用 QueryResult(User)
pub fn newFunction() QueryResult(User) {
    return User{ .id = 2, .name = "Bob", .email = "bob@example.com" };
}

// 兼容性验证
test "QueryResult and Error!T compatibility" {
    const testing = std.testing;

    // 可以将 QueryResult 赋值给 Error!T
    const result1: Error!User = try newFunction();

    // 可以将 Error!T 赋值给 QueryResult
    const result2: QueryResult(User) = try oldFunction();

    // 两者完全等价
    try testing.expectEqual(@TypeOf(result1), @TypeOf(result2));
}
```

**验证**:
- 编译通过
- 类型检查无错误
- 运行时行为一致

---

### Requirement: VoidResult 常量类型别名定义

错误处理模块 MUST 提供 `VoidResult` 常量类型别名，作为 `Error!void` 的语义化替代。

#### Scenario: 定义 VoidResult 常量类型别名

**Given** 错误处理模块 `src/error.zig`
**When** 定义 `VoidResult` 类型别名
**Then** 等价于 `Error!void` 类型
**And** 类型别名可用于不返回数据的操作

**实现代码**:
```zig
/// 空结果类型
///
/// 用于不返回数据的操作（如 INSERT/UPDATE/DELETE），明确表达操作可能成功或失败。
/// 这是 `Error!void` 的语义化别名，提供零运行时开销。
///
/// ## 使用场景
/// - 数据库修改操作（INSERT, UPDATE, DELETE）
/// - 副作用操作（CONNECT, CLOSE）
/// - 任何不返回数据的可能失败操作
///
/// ## 示例
/// ```zig
/// // 函数签名
/// pub fn deleteUser(db: *DB, id: i64) VoidResult {
///     var query = try db.newDelete(User);
///     defer query.deinit();
///     try query.where("id = ?", .{id});
///     return query.exec();
/// }
///
/// // 使用
/// try deleteUser(db, 123);
/// ```
pub const VoidResult = Error!void;
```

**验证**:
- 编译时类型检查通过
- `VoidResult` 与 `Error!void` 完全等价

---

#### Scenario: VoidResult 在函数签名中使用

**Given** 定义了删除用户的操作函数
**When** 使用 `VoidResult` 作为返回类型
**Then** 函数签名清晰表达不返回数据但可能失败
**And** 调用者必须处理可能的错误

**示例代码**:
```zig
/// 删除指定 ID 的用户
pub fn deleteUser(db: *DB, id: i64) VoidResult {
    var query = try db.newDelete(User);
    defer query.deinit();

    try query.where("id = ?", .{id});
    try query.exec();
}

/// 关闭数据库连接
pub fn closeConnection(db: *DB) VoidResult {
    return db.close();
}

/// 调用示例
pub fn example(db: *DB) !void {
    // 使用 try 传播错误
    try deleteUser(db, 123);

    // 使用 catch 处理错误
    deleteUser(db, 456) catch |err| {
        std.log.err("Failed to delete user: {}", .{err});
        return err;
    };

    // 关闭连接
    try closeConnection(db);
}
```

**验证**:
- 函数签名使用 `VoidResult` 代替 `Error!void`
- 编译器强制错误处理
- 语义清晰，易于理解

---

#### Scenario: VoidResult 与 Error!void 完全兼容

**Given** 已有使用 `Error!void` 的代码
**When** 引入 `VoidResult` 类型别名
**Then** 两种写法完全兼容，可以互换使用
**And** 不破坏现有代码

**兼容性示例**:
```zig
// 旧代码：使用 Error!void
pub fn oldOperation() Error!void {
    std.log.info("Old operation executed", .{});
}

// 新代码：使用 VoidResult
pub fn newOperation() VoidResult {
    std.log.info("New operation executed", .{});
}

// 兼容性验证
test "VoidResult and Error!void compatibility" {
    const testing = std.testing;

    // 可以将 VoidResult 赋值给 Error!void
    const result1: Error!void = try newOperation();
    _ = result1;

    // 可以将 Error!void 赋值给 VoidResult
    const result2: VoidResult = try oldOperation();
    _ = result2;

    // 两者完全等价
    try testing.expectEqual(@TypeOf(result1), @TypeOf(result2));
}
```

**验证**:
- 编译通过
- 类型检查无错误
- 运行时行为一致

---

### Requirement: 类型别名导出和可用性

类型别名 MUST 正确导出，使其在整个 ZORM 项目中可用。

#### Scenario: 类型别名从错误模块导出

**Given** 在 `src/error.zig` 定义的类型别名
**When** 其他模块导入错误模块
**Then** 可以访问 `QueryResult` 和 `VoidResult`
**And** 类型别名可用于类型注解和函数签名

**导出验证**:
```zig
// src/error.zig 已定义类型别名

// src/core/db.zig
const zorm_error = @import("../error.zig");
const QueryResult = zorm_error.QueryResult;
const VoidResult = zorm_error.VoidResult;

pub fn query(self: *DB, sql: []const u8) QueryResult(*Result) {
    // 实现...
}

pub fn exec(self: *DB, sql: []const u8) VoidResult {
    // 实现...
}
```

**验证**:
- 导入成功
- 类型别名可用
- 编译通过

---

#### Scenario: 类型别名在模块命名空间中使用

**Given** ZORM 主模块 `src/zorm.zig` 重新导出类型别名
**When** 用户导入 ZORM
**Then** 可以直接使用 `zorm.QueryResult` 和 `zorm.VoidResult`
**And** 简化 API 使用

**用户使用示例**:
```zig
const zorm = @import("zorm");

// 直接使用类型别名
pub fn getUserById(db: *zorm.DB, id: i64) zorm.QueryResult(User) {
    // 实现...
}

pub fn deleteUser(db: *zorm.DB, id: i64) zorm.VoidResult {
    // 实现...
}
```

**验证**:
- 类型别名可从主模块访问
- API 简洁友好
- 用户体验良好

---

### Requirement: 类型别名文档和注释

类型别名 MUST 包含完整的文档注释，说明用途、使用场景和示例。

#### Scenario: QueryResult 包含详细文档

**Given** `QueryResult(T)` 类型别名定义
**When** 开发者查看 API 文档或代码
**Then** 可以看到详细的文档注释
**And** 包含使用示例和最佳实践

**文档要求**:
```zig
/// 查询结果类型
///
/// 所有查询操作返回此类型，明确表达操作可能成功返回 T 或失败返回错误。
/// 这是 `Error!T` 的语义化别名，提供零运行时开销。
///
/// ## 使用场景
/// - 数据库查询操作（SELECT）
/// - 数据获取操作（GET, FIND）
/// - 任何返回数据的可能失败操作
///
/// ## 示例
/// ```zig
/// pub fn findUser(db: *DB, id: i64) QueryResult(User) {
///     var query = try db.newSelect(User);
///     defer query.deinit();
///     try query.where("id = ?", .{id});
///     return query.scanOne();
/// }
///
/// const user = try findUser(db, 123);
/// ```
///
/// ## 错误处理
/// ```zig
/// // 传播错误
/// const user = try findUser(db, 123);
///
/// // 捕获错误
/// const user = findUser(db, 123) catch |err| {
///     std.log.err("Error: {}", .{err});
///     return err;
/// };
/// ```
pub fn QueryResult(comptime T: type) type {
    return Error!T;
}
```

**验证**:
- 文档注释完整
- 包含使用场景
- 包含代码示例
- 包含错误处理示例

---

#### Scenario: VoidResult 包含详细文档

**Given** `VoidResult` 类型别名定义
**When** 开发者查看 API 文档或代码
**Then** 可以看到详细的文档注释
**And** 包含使用示例和最佳实践

**文档要求**:
```zig
/// 空结果类型
///
/// 用于不返回数据的操作（如 INSERT/UPDATE/DELETE），明确表达操作可能成功或失败。
/// 这是 `Error!void` 的语义化别名，提供零运行时开销。
///
/// ## 使用场景
/// - 数据库修改操作（INSERT, UPDATE, DELETE）
/// - 副作用操作（CONNECT, CLOSE）
/// - 任何不返回数据的可能失败操作
///
/// ## 示例
/// ```zig
/// pub fn deleteUser(db: *DB, id: i64) VoidResult {
///     var query = try db.newDelete(User);
///     defer query.deinit();
///     try query.where("id = ?", .{id});
///     return query.exec();
/// }
///
/// try deleteUser(db, 123);
/// ```
///
/// ## 错误处理
/// ```zig
/// // 传播错误
/// try deleteUser(db, 123);
///
/// // 捕获错误
/// deleteUser(db, 123) catch |err| {
///     std.log.err("Error: {}", .{err});
///     return err;
/// };
/// ```
pub const VoidResult = Error!void;
```

**验证**:
- 文档注释完整
- 包含使用场景
- 包含代码示例
- 包含错误处理示例

---

### Requirement: 类型别名测试覆盖

类型别名 MUST 有完整的测试覆盖，验证其正确性和兼容性。

#### Scenario: 测试 QueryResult 类型等价性

**Given** 定义了 `QueryResult(T)` 类型别名
**When** 在测试中使用
**Then** 与 `Error!T` 完全等价
**And** 编译时和运行时行为一致

**测试代码**:
```zig
test "QueryResult type equivalence" {
    const testing = std.testing;

    // 成功情况
    const result1: QueryResult(i32) = 42;
    const result2: Error!i32 = 42;
    try testing.expectEqual(result2, result1);

    // 错误情况
    const result3: QueryResult(i32) = error.QueryFailed;
    try testing.expectError(error.QueryFailed, result3);

    // 类型检查
    try testing.expectEqual(@TypeOf(result1), @TypeOf(result2));
}
```

**验证**:
- 测试通过
- 类型等价
- 行为一致

---

#### Scenario: 测试 VoidResult 类型等价性

**Given** 定义了 `VoidResult` 类型别名
**When** 在测试中使用
**Then** 与 `Error!void` 完全等价
**And** 编译时和运行时行为一致

**测试代码**:
```zig
test "VoidResult type equivalence" {
    const testing = std.testing;

    // 成功情况
    const result1: VoidResult = {};
    const result2: Error!void = {};
    _ = result1;
    _ = result2;

    // 错误情况
    const result3: VoidResult = error.ConnectionClosed;
    try testing.expectError(error.ConnectionClosed, result3);

    // 类型检查
    try testing.expectEqual(@TypeOf(result1), @TypeOf(result2));
}
```

**验证**:
- 测试通过
- 类型等价
- 行为一致

---

#### Scenario: 测试类型别名在函数签名中使用

**Given** 使用类型别名的函数
**When** 在测试中调用
**Then** 函数正确返回结果或错误
**And** 错误处理机制正常工作

**测试代码**:
```zig
test "type aliases in function signatures" {
    const testing = std.testing;

    const Helper = struct {
        fn getUserId() QueryResult(i64) {
            return 123;
        }

        fn saveUser() VoidResult {
            return {};
        }

        fn failingQuery() QueryResult(i64) {
            return error.QueryFailed;
        }

        fn failingOperation() VoidResult {
            return error.ConnectionClosed;
        }
    };

    // 成功情况
    const id = try Helper.getUserId();
    try testing.expectEqual(@as(i64, 123), id);

    try Helper.saveUser();

    // 错误情况
    try testing.expectError(error.QueryFailed, Helper.failingQuery());
    try testing.expectError(error.ConnectionClosed, Helper.failingOperation());
}
```

**验证**:
- 所有测试通过
- 函数签名正确
- 错误处理正常

---

## Non-Requirements
- ❌ 不需要运行时类型信息（RTTI）
- ❌ 不需要额外的包装类型
- ❌ 不需要修改现有使用 `!T` 的代码
- ❌ 不需要向后不兼容的变更

## Dependencies
- ✅ `src/error.zig` 错误集已定义
- ✅ Zig 编译器支持泛型类型函数和类型别名

## Related Specs
- `db-error-handling`: 错误处理系统主规格
- `db-instance-api`: DB 实例 API（使用类型别名）
- `query-context-api`: 查询上下文 API（使用类型别名）
