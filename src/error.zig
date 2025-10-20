// src/error.zig
// ZORM 错误定义系统
// 提供类型安全、语义清晰的错误类型,确保编译时强制错误处理

const std = @import("std");

/// ZORM 错误集
///
/// 该错误集涵盖了 ZORM 所有可能的错误场景，包括：
/// - 连接错误: 数据库连接相关的失败
/// - 查询错误: SQL 查询执行过程中的错误
/// - 结果错误: 查询结果处理中的错误
/// - 事务错误: 事务管理相关的错误
/// - 内存错误: 内存分配失败
/// - 方言错误: 数据库方言不支持的特性
///
/// 所有 ZORM 操作都返回 !T 类型(错误联合类型),编译器强制错误处理
pub const Error = error{
    // ========== 连接错误 (Connection Errors) ==========

    /// 数据库连接失败
    /// 触发条件: 网络问题、认证失败、服务器不可达、端口被占用等
    /// 使用场景: DB.connect(), DB.open() 等连接操作失败时
    ConnectionFailed,

    /// 连接已关闭
    /// 触发条件: 尝试在已关闭的连接上执行操作
    /// 使用场景: 连接被 close() 后再次调用 query/exec 等方法
    ConnectionClosed,

    /// 连接池耗尽
    /// 触发条件: 连接池中所有连接都在使用,无法获取新连接
    /// 使用场景: DB.acquire() 在超时时间内无法获取可用连接
    ConnectionPoolExhausted,

    /// 连接超时
    /// 触发条件: 连接操作超过指定的超时时间
    /// 使用场景: 网络延迟过高或服务器无响应导致连接超时
    ConnectionTimeout,

    // ========== 查询错误 (Query Errors) ==========

    /// 查询执行失败
    /// 触发条件: SQL 语句执行时数据库返回错误
    /// 使用场景: 数据库约束违反、权限不足、表不存在等
    QueryFailed,

    /// 无效的 SQL 语句
    /// 触发条件: SQL 语法错误或不符合目标数据库方言
    /// 使用场景: 手写 SQL 或查询构建器生成的 SQL 不合法
    InvalidSQL,

    /// 无效的参数
    /// 触发条件: 参数类型不匹配或参数值不符合约束
    /// 使用场景: 绑定参数时类型转换失败或值超出范围
    InvalidParameter,

    /// 参数数量不匹配
    /// 触发条件: SQL 占位符数量与提供的参数数量不一致
    /// 使用场景: query.bind() 提供的参数数量与 SQL 中 $1, $2... 不匹配
    ParameterCountMismatch,

    // ========== 结果错误 (Result Errors) ==========

    /// 查询结果为空
    /// 触发条件: 期望至少一行结果,但查询返回 0 行
    /// 使用场景: scanOne() 要求至少一行,但 SELECT 结果为空
    NoRows,

    /// 查询返回过多行
    /// 触发条件: 期望单行结果,但查询返回多行
    /// 使用场景: scanOne() 要求最多一行,但 SELECT 返回多行
    TooManyRows,

    /// 列不存在
    /// 触发条件: 尝试访问查询结果中不存在的列
    /// 使用场景: result.get("column_name") 时列名拼写错误或不存在
    ColumnNotFound,

    /// 无效的列索引
    /// 触发条件: 列索引超出结果集的列数范围
    /// 使用场景: rows.columnName(999) 时索引越界
    InvalidColumnIndex,

    /// 类型不匹配
    /// 触发条件: 数据库列类型与目标 Zig 类型不兼容
    /// 使用场景: 尝试将 VARCHAR 扫描到 i32,或 JSON 扫描到非结构体
    TypeMismatch,

    /// 意外的 NULL 值
    /// 触发条件: 尝试将数据库 NULL 值扫描到非可选类型
    /// 使用场景: result.get(i32) 但数据库返回 NULL
    NullValue,

    // ========== 事务错误 (Transaction Errors) ==========

    /// 事务已经开始
    /// 触发条件: 在已有活动事务的连接上尝试开启新事务
    /// 使用场景: 嵌套事务未正确使用 SAVEPOINT,或忘记 commit/rollback
    TransactionAlreadyStarted,

    /// 嵌套事务不支持 (Story 2.4)
    /// 触发条件: 尝试在已有活动事务时调用 beginTx()
    /// 使用场景: PostgreSQL 不支持真正的嵌套事务,使用 SAVEPOINT 在 v2.0
    /// 注意: 这是 TransactionAlreadyStarted 的更明确版本
    NestedTransaction,

    /// 没有活动事务
    /// 触发条件: 尝试 commit/rollback 但当前无活动事务
    /// 使用场景: 重复调用 commit() 或未调用 begin()
    NoActiveTransaction,

    /// 事务未激活 (Story 2.4)
    /// 触发条件: 尝试在非活动事务上执行操作
    /// 使用场景: commit/rollback 后再次调用事务方法
    TransactionNotActive,

    /// 事务已提交 (Story 2.4)
    /// 触发条件: 尝试对已提交的事务执行 commit/rollback
    /// 使用场景: 重复提交或提交后尝试回滚
    AlreadyCommitted,

    /// 事务已回滚 (Story 2.4)
    /// 触发条件: 尝试对已回滚的事务执行 commit
    /// 使用场景: 回滚后尝试提交
    AlreadyRolledBack,

    /// 事务回滚失败
    /// 触发条件: ROLLBACK 命令执行失败
    /// 使用场景: 数据库内部错误或连接已断开
    TransactionRollbackFailed,

    /// 事务提交失败
    /// 触发条件: COMMIT 命令执行失败
    /// 使用场景: 约束违反、死锁、序列化失败等
    TransactionCommitFailed,

    // ========== 内存错误 (Memory Errors) ==========

    /// 内存不足
    /// 触发条件: Allocator.alloc() 或 Allocator.create() 失败
    /// 使用场景: 系统内存耗尽或达到分配器限制
    OutOfMemory,

    // ========== 方言错误 (Dialect Errors) ==========

    /// 不支持的数据库方言
    /// 触发条件: 尝试使用非 PostgreSQL 数据库
    /// 使用场景: ZORM 仅支持 PostgreSQL
    UnsupportedDialect,

    /// 不支持的特性
    /// 触发条件: 使用不支持的数据库特性
    /// 使用场景: 尝试使用超出 PostgreSQL 能力范围的功能
    UnsupportedFeature,

    // ========== Schema 错误 (Schema Errors) ==========

    /// 未指定列
    /// 触发条件: 创建索引时未指定任何列
    /// 使用场景: Index.toSQL() 时 columns 列表为空
    NoColumnsSpecified,
};

// ========== 类型别名 (Type Aliases) ==========

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

// ========== 辅助函数 (Helper Functions) ==========

/// 错误处理辅助函数示例
/// 将特定错误转换为可选值(用于可恢复的场景)
pub fn toOptional(comptime T: type, result: Error!T) ?T {
    return result catch |err| switch (err) {
        error.NoRows => return null,
        else => return null, // 或者重新抛出: return err
    };
}

/// 错误日志辅助函数示例
/// 记录错误信息并重新抛出
pub fn logAndReturn(comptime T: type, result: Error!T, context: []const u8) Error!T {
    return result catch |err| {
        std.log.err("{s}: {}", .{ context, err });
        return err;
    };
}

// ========== 测试 ==========

test "error definition is valid" {
    const testing = std.testing;

    // 验证错误可以正确创建
    const err: Error = error.ConnectionFailed;
    try testing.expect(err == error.ConnectionFailed);
}

test "error union type compatibility" {
    const testing = std.testing;

    // 验证错误联合类型 (!T) 兼容性
    const result: Error!i32 = error.QueryFailed;
    try testing.expectError(error.QueryFailed, result);
}

test "error propagation with try" {
    const testing = std.testing;

    const Helper = struct {
        fn failingFunction() Error!void {
            return error.ConnectionClosed;
        }

        fn callingFunction() Error!void {
            // 错误传播: try 会自动向上传播错误
            try failingFunction();
        }
    };

    try testing.expectError(error.ConnectionClosed, Helper.callingFunction());
}

test "error recovery with catch" {
    const testing = std.testing;

    const Helper = struct {
        fn failingFunction() Error!i32 {
            return error.NoRows;
        }

        fn recoveringFunction() i32 {
            // 错误恢复: catch 捕获错误并提供默认值
            return failingFunction() catch 0;
        }
    };

    try testing.expectEqual(@as(i32, 0), Helper.recoveringFunction());
}

test "error recovery with switch" {
    const testing = std.testing;

    const Helper = struct {
        fn failingFunction(should_fail: bool) Error!i32 {
            if (should_fail) return error.NoRows;
            return 42;
        }

        fn recoveringFunction(should_fail: bool) Error!?i32 {
            return failingFunction(should_fail) catch |err| switch (err) {
                error.NoRows => return null, // NoRows 转为 null
                else => return err, // 其他错误重新抛出
            };
        }
    };

    // NoRows 情况返回 null
    const result_null = try Helper.recoveringFunction(true);
    try testing.expect(result_null == null);

    // 成功情况返回值
    const result_ok = try Helper.recoveringFunction(false);
    try testing.expectEqual(@as(?i32, 42), result_ok);
}

test "toOptional helper function" {
    const testing = std.testing;

    const Helper = struct {
        fn failingFunction() Error!i32 {
            return error.NoRows;
        }

        fn successFunction() Error!i32 {
            return 42;
        }
    };

    // NoRows 转为 null
    const result_null = toOptional(i32, Helper.failingFunction());
    try testing.expect(result_null == null);

    // 成功情况返回值
    const result_ok = toOptional(i32, Helper.successFunction());
    try testing.expectEqual(@as(?i32, 42), result_ok);
}

test "all error types are defined" {
    const testing = std.testing;

    // 验证所有错误类型都能正确实例化
    const errors = [_]Error{
        // 连接错误
        error.ConnectionFailed,
        error.ConnectionClosed,
        error.ConnectionPoolExhausted,
        error.ConnectionTimeout,
        // 查询错误
        error.QueryFailed,
        error.InvalidSQL,
        error.InvalidParameter,
        error.ParameterCountMismatch,
        // 结果错误
        error.NoRows,
        error.TooManyRows,
        error.ColumnNotFound,
        error.InvalidColumnIndex,
        error.TypeMismatch,
        error.NullValue,
        // 事务错误 (Story 2.4 新增)
        error.TransactionAlreadyStarted,
        error.NestedTransaction,
        error.NoActiveTransaction,
        error.TransactionNotActive,
        error.AlreadyCommitted,
        error.AlreadyRolledBack,
        error.TransactionRollbackFailed,
        error.TransactionCommitFailed,
        // 内存错误
        error.OutOfMemory,
        // 方言错误
        error.UnsupportedDialect,
        error.UnsupportedFeature,
        // Schema 错误
        error.NoColumnsSpecified,
    };

    // 验证数组长度符合预期(26个错误,Story 2.4 新增 4个)
    try testing.expectEqual(@as(usize, 26), errors.len);
}

// ========== 类型别名测试 (Type Alias Tests) ==========

test "QueryResult type alias equivalence" {
    const testing = std.testing;

    // 验证 QueryResult(T) 与 Error!T 等价
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

test "VoidResult type alias equivalence" {
    const testing = std.testing;

    // 验证 VoidResult 与 Error!void 等价
    // 成功情况
    const result1: VoidResult = {};
    const result2: Error!void = {};

    // 错误情况
    const result3: VoidResult = error.ConnectionClosed;
    try testing.expectError(error.ConnectionClosed, result3);

    // 类型检查 - 使用 void 值来比较类型
    try result1;
    try result2;
    try testing.expectEqual(@TypeOf(result1), @TypeOf(result2));
}

test "QueryResult in function signatures" {
    const testing = std.testing;

    const Helper = struct {
        fn getUserId() QueryResult(i64) {
            return 123;
        }

        fn failingQuery() QueryResult(i64) {
            return error.QueryFailed;
        }
    };

    // 成功情况
    const id = try Helper.getUserId();
    try testing.expectEqual(@as(i64, 123), id);

    // 错误情况
    try testing.expectError(error.QueryFailed, Helper.failingQuery());
}

test "VoidResult in function signatures" {
    const testing = std.testing;

    const Helper = struct {
        fn saveUser() VoidResult {
            return {};
        }

        fn failingOperation() VoidResult {
            return error.ConnectionClosed;
        }
    };

    // 成功情况
    try Helper.saveUser();

    // 错误情况
    try testing.expectError(error.ConnectionClosed, Helper.failingOperation());
}

test "QueryResult and Error!T compatibility" {
    const testing = std.testing;

    const User = struct {
        id: i64,
        name: []const u8,
    };

    const Helper = struct {
        // 使用 Error!T
        fn oldFunction() Error!User {
            return User{ .id = 1, .name = "Alice" };
        }

        // 使用 QueryResult
        fn newFunction() QueryResult(User) {
            return User{ .id = 2, .name = "Bob" };
        }
    };

    // 可以将 QueryResult 赋值给 Error!T
    const user1 = try Helper.newFunction();
    try testing.expectEqual(@as(i64, 2), user1.id);

    // 可以将 Error!T 赋值给 QueryResult
    const user2 = try Helper.oldFunction();
    try testing.expectEqual(@as(i64, 1), user2.id);

    // 类型完全等价
    const result1: Error!User = User{ .id = 3, .name = "Charlie" };
    const result2: QueryResult(User) = User{ .id = 4, .name = "David" };
    try testing.expectEqual(@TypeOf(result1), @TypeOf(result2));
}

test "VoidResult and Error!void compatibility" {
    const testing = std.testing;

    const Helper = struct {
        // 使用 Error!void
        fn oldOperation() Error!void {
            // 无操作
        }

        // 使用 VoidResult
        fn newOperation() VoidResult {
            // 无操作
        }
    };

    // 可以将 VoidResult 赋值给 Error!void
    try Helper.newOperation();

    // 可以将 Error!void 赋值给 VoidResult
    try Helper.oldOperation();

    // 类型完全等价
    const result1: Error!void = {};
    const result2: VoidResult = {};
    try testing.expectEqual(@TypeOf(result1), @TypeOf(result2));
}

test "nested QueryResult types" {
    const testing = std.testing;

    // 验证嵌套使用 QueryResult
    const result: QueryResult(QueryResult(i32)) = @as(QueryResult(i32), 42);
    const inner = try result;
    const value = try inner;
    try testing.expectEqual(@as(i32, 42), value);
}

test "QueryResult with optional types" {
    const testing = std.testing;

    const Helper = struct {
        fn findUser(should_exist: bool) QueryResult(?i64) {
            if (should_exist) {
                return 123; // Some(123)
            } else {
                return null; // None
            }
        }
    };

    // 找到用户
    const user1 = try Helper.findUser(true);
    try testing.expectEqual(@as(?i64, 123), user1);

    // 未找到用户（返回 null 而非错误）
    const user2 = try Helper.findUser(false);
    try testing.expectEqual(@as(?i64, null), user2);
}
