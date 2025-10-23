# select-query-scan-api Specification

## Purpose
TBD - created by archiving change align-select-query-story-1-2. Update Purpose after archive.
## Requirements
### Requirement: SELECT Query scan() Method Signature

SELECT 查询的 `scan()` 方法 MUST 接受一个 `*std.ArrayList(T)` 参数，并将查询结果追加到该列表中，而非返回切片。

#### Scenario: Scan query results into ArrayList

**Given** 一个初始化的 SelectQuery 对象
**And** 一个空的 `std.ArrayList(User)`
**When** 调用 `query.scan(&users)`
**Then** 查询被执行
**And** 所有结果行被解析为 User 类型
**And** 结果被追加到 users ArrayList 中
**And** 方法返回 void（或错误）

**Code Example**:
```zig
const User = struct {
    id: i64,
    name: []const u8,
    age: u32,
};

var db = try DB(.postgresql).init(allocator, conn, .{});
defer db.deinit();

var users = std.ArrayList(User){};
defer users.deinit(allocator);

var query = try db.newSelect(User);
defer query.deinit();

try query
    .where("age > ?", .{18})
    .orderBy("created_at", .desc)
    .limit(10)
    .scan(&users);

try std.testing.expect(users.items.len <= 10);
for (users.items) |user| {
    try std.testing.expect(user.age > 18);
}
```

#### Scenario: Scan appends to existing ArrayList

**Given** 一个 SelectQuery 对象
**And** 一个已包含 5 个元素的 `std.ArrayList(User)`
**When** 调用 `query.scan(&users)`
**And** 查询返回 3 行结果
**Then** ArrayList 包含 8 个元素（5 + 3）
**And** 原有的 5 个元素保持不变
**And** 新的 3 个元素追加在末尾

**Code Example**:
```zig
var users = std.ArrayList(User){};
defer users.deinit(allocator);

// 第一次查询：活跃用户
try active_query.where("status = ?", .{"active"}).scan(&users);
const active_count = users.items.len;

// 第二次查询：追加待审核用户
try pending_query.where("status = ?", .{"pending"}).scan(&users);

try std.testing.expect(users.items.len >= active_count);
// users 现在包含 active + pending 用户
```

#### Scenario: Scan empty result set

**Given** 一个 SelectQuery 对象
**And** 一个空的 `std.ArrayList(User)`
**When** 调用 `query.scan(&users)`
**And** 查询返回 0 行
**Then** ArrayList 仍然为空
**And** 方法成功返回（无错误）

**Code Example**:
```zig
var users = std.ArrayList(User){};
defer users.deinit(allocator);

var query = try db.newSelect(User);
defer query.deinit();

// 查询不存在的记录
try query.where("id = ?", .{-9999}).scan(&users);

try std.testing.expectEqual(@as(usize, 0), users.items.len);
```

#### Scenario: Scan with pre-allocated capacity

**Given** 一个 SelectQuery 对象
**And** 一个预分配了容量的 `std.ArrayList(User)`
**When** 调用 `query.scan(&users)`
**Then** 如果结果数量不超过预分配容量，不会发生额外的内存分配
**And** 所有结果正确填充到 ArrayList

**Code Example**:
```zig
var users = std.ArrayList(User){};
defer users.deinit(allocator);

// 预分配容量，优化性能
try users.ensureTotalCapacity(100);

var query = try db.newSelect(User);
defer query.deinit();

try query.limit(50).scan(&users);

try std.testing.expect(users.items.len <= 50);
try std.testing.expect(users.capacity >= 100);
```

---

### Requirement: SELECT Query scan() Error Handling

`scan()` 方法 MUST 在遇到错误时正确传播错误，并在部分扫描失败时保持 ArrayList 的一致性。

#### Scenario: Scan propagates database errors

**Given** 一个 SelectQuery 对象
**And** 数据库连接已断开
**When** 调用 `query.scan(&users)`
**Then** 方法返回 DatabaseError
**And** ArrayList 保持未修改（或仅包含部分数据）

**Code Example**:
```zig
var users = std.ArrayList(User){};
defer users.deinit(allocator);

var query = try db.newSelect(User);
defer query.deinit();

// 模拟数据库错误
query.scan(&users) catch |err| {
    try std.testing.expectEqual(error.DatabaseError, err);
    // users 可能为空或包含部分数据
    return;
};
```

#### Scenario: Scan propagates type conversion errors

**Given** 一个 SelectQuery 对象
**And** 数据库列类型与 Zig 类型不匹配
**When** 调用 `query.scan(&users)`
**Then** 方法返回 ScanError.TypeMismatch
**And** 错误信息包含列名和类型信息

**Code Example**:
```zig
const User = struct {
    id: i64,
    name: []const u8,
    age: u32,  // 假设数据库中 age 是 TEXT 类型
};

var users = std.ArrayList(User){};
defer users.deinit(allocator);

var query = try db.newSelect(User);
defer query.deinit();

query.scan(&users) catch |err| {
    try std.testing.expectEqual(error.TypeMismatch, err);
    // 应该记录或处理类型不匹配错误
    return;
};
```

#### Scenario: Scan handles OutOfMemory gracefully

**Given** 一个 SelectQuery 对象
**And** 系统内存不足
**When** 调用 `query.scan(&users)`
**And** ArrayList 扩容失败
**Then** 方法返回 error.OutOfMemory
**And** ArrayList 包含已成功扫描的部分数据

**Code Example**:
```zig
var users = std.ArrayList(User){};
defer users.deinit(allocator);

var query = try db.newSelect(User);
defer query.deinit();

query.limit(1_000_000).scan(&users) catch |err| {
    if (err == error.OutOfMemory) {
        std.log.warn("Memory exhausted, scanned {} rows", .{users.items.len});
        // 可以选择清空部分数据
        users.clearRetainingCapacity();
    }
    return err;
};
```

---

### Requirement: SELECT Query scan() Memory Management

`scan()` 方法 MUST 使用查询构建器的 allocator 进行临时分配，并确保所有临时资源在方法返回前被正确释放。

#### Scenario: Scan cleans up temporary allocations

**Given** 一个 SelectQuery 对象
**When** 调用 `query.scan(&users)`
**Then** SQL 字符串在使用后被释放
**And** 参数数组在使用后被释放
**And** Result 对象在使用后被关闭
**And** 不会发生内存泄漏

**Code Example**:
```zig
test "scan does not leak memory" {
    const allocator = std.testing.allocator;

    var db = try DB(.postgresql).init(allocator, conn, .{});
    defer db.deinit();

    var users = std.ArrayList(User){};
    defer users.deinit(allocator);

    var query = try db.newSelect(User);
    defer query.deinit();

    try query.where("age > ?", .{18}).scan(&users);

    // std.testing.allocator 会自动检测内存泄漏
}
```

#### Scenario: Scan uses query allocator for internal operations

**Given** 一个使用特定 allocator 的 SelectQuery
**When** 调用 `query.scan(&users)`
**Then** SQL 构建使用 query.allocator
**And** 参数收集使用 query.allocator
**And** 结果扫描的临时操作使用 query.allocator
**And** ArrayList 的扩容使用其自己的 allocator

**Code Example**:
```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();

var db = try DB(.postgresql).init(arena.allocator(), conn, .{});
defer db.deinit();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();

var users = std.ArrayList(User).init(gpa.allocator());
defer users.deinit();

var query = try db.newSelect(User);
defer query.deinit();

// query 使用 arena allocator
// users 使用 gpa allocator
try query.scan(&users);
```

---

### Requirement: SELECT Query scan() API Consistency with PRD

所有 SelectQuery 方法 MUST 与 PRD Story 1.2 中的示例代码保持一致，确保文档示例可直接运行。

#### Scenario: PRD example code compiles and runs

**Given** PRD Story 1.2 AC1.2.8 中的示例代码
**When** 代码被编译和执行
**Then** 编译成功无错误
**And** 运行时行为符合预期
**And** 查询结果符合 WHERE 和 ORDER BY 条件

**Code Example**:
```zig
// PRD Story 1.2 AC1.2.8 示例代码
var users: std.ArrayList(User) = .{};
defer users.deinit(allocator);

var query = try db.newSelect(User);
defer query.deinit();

try query
    .where("age > ?", .{18})
    .orderBy("created_at", .desc)
    .limit(10)
    .scan(&users);

// 验证结果
try std.testing.expect(users.items.len <= 10);
for (users.items) |user| {
    try std.testing.expect(user.age > 18);
}
```

#### Scenario: Chained method calls return correct type

**Given** 一个 SelectQuery 对象
**When** 调用链式方法（where, orderBy, limit）
**Then** 每个方法返回 `!*Self` 类型
**And** 支持继续链式调用
**And** 最终调用 scan() 执行查询

**Code Example**:
```zig
var users = std.ArrayList(User){};
defer users.deinit(allocator);

var query = try db.newSelect(User);
defer query.deinit();

// 所有方法支持链式调用
const result_query = try query
    .where("status = ?", .{"active"})
    .where("age >= ?", .{21})
    .orderBy("name", .asc)
    .limit(50)
    .offset(10);

try result_query.scan(&users);
```

---

