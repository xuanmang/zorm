# db-memory-management Specification

## Purpose
TBD - created by archiving change implement-db-instance-management. Update Purpose after archive.
## Requirements
### Requirement: Allocator 传递模式

所有需要分配内存的 API MUST显式接受 Allocator 参数。

#### Scenario: DB 实例接受 Allocator

**Given** 调用者提供 Allocator
**When** 创建 DB 实例
**Then** DB 使用传入的 Allocator 分配内存
**And** DB 存储 Allocator 引用供后续使用

**示例代码**:
```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

var db = try DB(.postgresql).init(allocator, conn, .{});
defer db.deinit();

try std.testing.expect(db.allocator == allocator);
```

#### Scenario: 查询构建器使用 DB 的 Allocator

**Given** 已创建的 DB 实例
**When** 创建查询构建器
**Then** 查询构建器使用 DB 的 Allocator

**示例代码**:
```zig
var query = try db.newSelect(User);
defer query.deinit();

try std.testing.expect(query.allocator == db.allocator);
```

---

### Requirement: errdefer 自动清理

初始化失败时 MUST自动清理已分配的资源，防止内存泄漏。

#### Scenario: init 失败时自动清理

**Given** 初始化过程中发生错误
**When** 返回错误前
**Then** 通过 errdefer 释放所有已分配的资源

**示例代码**:
```zig
pub fn init(allocator: Allocator, conn: Conn, options: DBOptions) !*Self {
    const self = try allocator.create(Self);
    errdefer allocator.destroy(self); // 创建失败时清理

    self.* = .{
        .allocator = allocator,
        .query_hooks = std.ArrayList(QueryHook).init(allocator),
        // ...
    };

    // 如果下面的初始化失败，self 会被自动销毁
    return self;
}
```

#### Scenario: 嵌套资源的清理

**Given** 初始化多层嵌套资源
**When** 任何一层初始化失败
**Then** 所有已初始化的资源通过嵌套 errdefer 自动清理

**示例代码**:
```zig
pub fn complex_init(allocator: Allocator) !*Complex {
    const self = try allocator.create(Complex);
    errdefer allocator.destroy(self);

    self.list1 = std.ArrayList(i32).init(allocator);
    errdefer self.list1.deinit();

    self.list2 = std.ArrayList(i32).init(allocator);
    errdefer self.list2.deinit();

    // 任何错误都会触发正确的清理顺序
    return self;
}
```

---

### Requirement: defer 资源释放

调用者 MUST使用 defer 确保资源正确释放。

#### Scenario: DB 实例使用 defer 清理

**Given** 创建 DB 实例
**When** 函数退出前
**Then** 通过 defer 调用 deinit() 释放资源

**示例代码**:
```zig
pub fn queryUsers(allocator: Allocator) !void {
    var db = try DB(.postgresql).init(allocator, conn, .{});
    defer db.deinit(); // 确保函数退出时清理

    var query = try db.newSelect(User);
    defer query.deinit(); // 确保查询构建器清理

    var users = std.ArrayList(User).init(allocator);
    defer users.deinit(); // 确保结果列表清理

    try query.scan(&users);
    // 所有资源会按照 LIFO 顺序清理
}
```

#### Scenario: 查询结果使用 defer 关闭

**Given** 执行查询返回 Result
**When** 使用完结果后
**Then** 通过 defer 调用 result.close() 释放资源

**示例代码**:
```zig
const result = try db.query("SELECT * FROM users", &[_]QueryArg{});
defer result.close(); // 确保结果集关闭

while (try result.next()) {
    // 处理行...
}
// result 自动关闭
```

---

### Requirement: Arena 优化临时分配

临时分配（如 SQL 构建）MUST 使用 Arena 分配器优化性能。

#### Scenario: 使用 Arena 构建 SQL

**Given** 需要构建复杂 SQL 字符串
**When** 使用 Arena 分配器
**Then** 所有临时分配通过一次 deinit 释放

**示例代码**:
```zig
pub fn buildComplexQuery(base_allocator: Allocator) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit(); // 一次性释放所有临时分配

    const temp_allocator = arena.allocator();

    // 所有临时分配使用 temp_allocator
    const sql_parts = try temp_allocator.alloc([]const u8, 10);
    const params = try temp_allocator.alloc(QueryArg, 5);

    // 构建 SQL...
    const sql = try std.mem.join(temp_allocator, " ", sql_parts);

    // 复制到持久内存
    return try base_allocator.dupe(u8, sql);
    // arena.deinit() 释放所有临时内存
}
```

#### Scenario: QueryContext 封装 Arena

**Given** 定义 QueryContext 包装 Arena
**When** 执行查询
**Then** 简化临时内存管理

**示例代码**:
```zig
pub const QueryContext = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(base_allocator: Allocator) QueryContext {
        return .{ .arena = std.heap.ArenaAllocator.init(base_allocator) };
    }

    pub fn deinit(self: *QueryContext) void {
        self.arena.deinit();
    }

    pub fn allocator(self: *QueryContext) Allocator {
        return self.arena.allocator();
    }

    pub fn reset(self: *QueryContext) void {
        _ = self.arena.reset(.retain_capacity);
    }
};

// 使用示例
pub fn executeQuery(db: *DB, sql: []const u8) !void {
    var ctx = QueryContext.init(db.allocator);
    defer ctx.deinit();

    const params = try ctx.allocator().alloc(QueryArg, 10);
    // params 会在 ctx.deinit() 时自动释放
}
```

---

### Requirement: 内存泄漏检测

测试 MUST使用 testing.allocator 检测内存泄漏。

#### Scenario: 单元测试检测泄漏

**Given** 使用 testing.allocator
**When** 测试结束
**Then** 自动检测是否有内存泄漏

**示例代码**:
```zig
test "detect memory leaks" {
    const allocator = std.testing.allocator;

    var db = try DB(.postgresql).init(allocator, mock_conn, .{});
    defer db.deinit();

    var query = try db.newSelect(User);
    defer query.deinit(); // 忘记这行会导致测试失败

    // 测试逻辑...
}
// testing.allocator 会在测试结束时验证所有内存都已释放
```

#### Scenario: 检测查询构建器泄漏

**Given** 创建多个查询构建器
**When** 忘记调用 deinit()
**Then** testing.allocator 报告泄漏

**示例代码**:
```zig
test "query builder must be freed" {
    const allocator = std.testing.allocator;

    var db = try DB(.postgresql).init(allocator, mock_conn, .{});
    defer db.deinit();

    var query1 = try db.newSelect(User);
    defer query1.deinit();

    var query2 = try db.newInsert(User);
    // defer query2.deinit(); // 忘记这行会失败

    // 测试会失败并报告泄漏
}
```

---

### Requirement: 所有权语义

资源所有权 MUST清晰，避免悬垂指针和双重释放。

#### Scenario: DB 拥有查询钩子列表

**Given** DB 实例包含查询钩子列表
**When** DB.deinit() 被调用
**Then** DB 负责释放钩子列表
**And** 钩子实例由调用者管理

**示例代码**:
```zig
pub fn deinit(self: *Self) void {
    // DB 拥有 query_hooks 列表
    self.query_hooks.deinit();

    // 但不拥有钩子实例本身
    // 钩子实例由调用者管理生命周期

    self.conn.close();
    self.allocator.destroy(self);
}

// 使用示例
pub fn example() !void {
    var db = try DB(.postgresql).init(allocator, conn, .{});
    defer db.deinit();

    // 调用者拥有钩子实例
    var logging = LoggingHook.init(true, 1000);
    try db.addHook(logging.hook()); // 传递钩子值，不是指针

    // db.deinit() 会清理列表，但不会销毁 logging
}
```

#### Scenario: 查询结果由调用者拥有

**Given** 查询返回 Result
**When** 调用者使用完毕
**Then** 调用者负责调用 result.close()

**示例代码**:
```zig
pub fn queryData() !void {
    const result = try db.query("SELECT ...", &[_]QueryArg{});
    defer result.close(); // 调用者负责关闭

    // 使用结果...
}
```

---

### Requirement: 内存分配优化

频繁使用的缓冲区 MUST 复用，减少分配次数。

#### Scenario: QueryBuilder 复用缓冲区

**Given** QueryBuilder 包含 ArrayList(u8) 缓冲区
**When** 重置构建器
**Then** 保留缓冲区容量，避免重新分配

**示例代码**:
```zig
pub const QueryBuilder = struct {
    buf: std.ArrayList(u8),

    pub fn reset(self: *QueryBuilder) void {
        self.buf.clearRetainingCapacity(); // 保留容量
    }
};

// 使用示例
var builder = QueryBuilder{ .buf = std.ArrayList(u8).init(allocator) };
defer builder.buf.deinit();

for (0..100) |_| {
    builder.reset(); // 不重新分配
    try builder.buf.appendSlice("SELECT ...");
    const sql = builder.buf.items;
    // 使用 sql...
}
```

#### Scenario: 预分配容量

**Given** 已知需要的容量
**When** 创建 ArrayList
**Then** 预分配容量减少重新分配

**示例代码**:
```zig
pub fn allocWithCapacity(allocator: Allocator, expected_size: usize) !std.ArrayList(u8) {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.ensureTotalCapacity(expected_size);
    return buf;
}

// 使用示例
var buf = try allocWithCapacity(allocator, 1024);
defer buf.deinit();

// 前 1024 字节不会触发重新分配
try buf.appendSlice("long sql query...");
```

---

