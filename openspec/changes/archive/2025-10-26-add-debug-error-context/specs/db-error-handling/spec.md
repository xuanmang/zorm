## ADDED Requirements

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
