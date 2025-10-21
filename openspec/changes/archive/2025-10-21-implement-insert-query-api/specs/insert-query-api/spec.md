# insert-query-api Specification

## Purpose

定义 ZORM INSERT 查询构建器的 API 规范，实现类型安全的单行和批量插入功能，支持 PostgreSQL RETURNING 子句，确保性能优化和内存安全。

## ADDED Requirements

### Requirement: newInsert() 工厂方法

DB 实例 MUST 提供 `newInsert(T)` 方法创建 INSERT 查询构建器，T 为目标 Zig 结构体类型。

#### Scenario: 创建 INSERT 查询构建器

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

const User = struct {
    name: []const u8,
    email: []const u8,
    age: u32,
    pub const table_name = "users";
};

var query = try db.newInsert(User);
defer query.deinit();

try std.testing.expect(query.allocator.ptr == allocator.ptr);
try std.testing.expectEqualStrings("users", query.table_name);
```

#### Scenario: 自动提取表名

```zig
const User = struct {
    id: i64,
    name: []const u8,
    pub const table_name = "users";
};

var query = try db.newInsert(User);
defer query.deinit();

try std.testing.expectEqualStrings("users", query.table_name);
```

---

### Requirement: value() 单行插入

INSERT 查询构建器 MUST 提供 `value(item)` 方法插入单行数据，接受包含列名和值的匿名结构体。

#### Scenario: 插入单行数据

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newInsert(User);
defer query.deinit();

_ = try query.value(.{
    .name = "Alice",
    .email = "alice@example.com",
    .age = 25,
});

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expectEqualStrings(
    "INSERT INTO users (name, email, age) VALUES ($1, $2, $3)",
    sql
);
```

#### Scenario: 自动初始化列名

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newInsert(User);
defer query.deinit();

// 第一次调用 value() 初始化列名
_ = try query.value(.{
    .name = "Alice",
    .email = "alice@example.com",
});

try std.testing.expectEqual(@as(usize, 2), query.columns.items.len);
try std.testing.expectEqualStrings("name", query.columns.items[0]);
try std.testing.expectEqualStrings("email", query.columns.items[1]);
```

#### Scenario: 链式调用支持

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newInsert(User);
defer query.deinit();

_ = try query
    .value(.{ .name = "Alice", .email = "alice@example.com" })
    .returning(&.{"id"});

try std.testing.expect(query.returning_columns != null);
```

---

### Requirement: values() 批量插入

INSERT 查询构建器 MUST 提供 `values(items)` 方法批量插入多行数据，接受结构体切片或数组指针。

#### Scenario: 批量插入多行

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

const users = [_]struct { name: []const u8, email: []const u8, age: u32 }{
    .{ .name = "Alice", .email = "alice@example.com", .age = 25 },
    .{ .name = "Bob", .email = "bob@example.com", .age = 30 },
    .{ .name = "Carol", .email = "carol@example.com", .age = 28 },
};

var query = try db.newInsert(User);
defer query.deinit();

_ = try query.values(&users);

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expectEqualStrings(
    "INSERT INTO users (name, email, age) VALUES ($1, $2, $3), ($4, $5, $6), ($7, $8, $9)",
    sql
);
```

#### Scenario: 批量大小限制

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

// 创建超过限制的批量数据
var large_batch = std.ArrayList(User).init(allocator);
defer large_batch.deinit();

var i: usize = 0;
while (i < 1001) : (i += 1) {
    try large_batch.append(.{
        .name = "User",
        .email = "user@example.com",
        .age = 25,
    });
}

var query = try db.newInsert(User);
defer query.deinit();

// 超过 1000 行限制应返回错误
try std.testing.expectError(error.BatchSizeTooLarge, query.values(large_batch.items));
```

#### Scenario: PostgreSQL 参数限制检查

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

// 创建会超过 PostgreSQL 参数限制的批量数据
// 假设每行 100 列，656 行 = 65600 个参数
const LargeRow = struct {
    field1: i64,
    field2: i64,
    // ... 98 more fields
    field100: i64,
};

var batch = std.ArrayList(LargeRow).init(allocator);
defer batch.deinit();

var i: usize = 0;
while (i < 656) : (i += 1) {
    try batch.append(.{ /* ... */ });
}

var query = try db.newInsert(LargeRow);
defer query.deinit();

// 超过 65535 参数限制应返回错误
try std.testing.expectError(error.ExceedsPostgreSQLParamLimit, query.values(batch.items));
```

---

### Requirement: returning() RETURNING 子句

INSERT 查询构建器 MUST 提供 `returning(cols)` 方法添加 RETURNING 子句（仅 PostgreSQL 支持），接受列名数组。

#### Scenario: 添加 RETURNING 子句

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newInsert(User);
defer query.deinit();

_ = try query
    .value(.{ .name = "Alice", .email = "alice@example.com" })
    .returning(&.{"id", "created_at"});

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expectEqualStrings(
    "INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id, created_at",
    sql
);
```

#### Scenario: RETURNING 所有列

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newInsert(User);
defer query.deinit();

_ = try query
    .value(.{ .name = "Alice", .email = "alice@example.com" })
    .returning(&.{"*"});

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expect(std.mem.indexOf(u8, sql, "RETURNING *") != null);
```

#### Scenario: 批量插入支持 RETURNING

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

const users = [_]struct { name: []const u8, email: []const u8 }{
    .{ .name = "Alice", .email = "alice@example.com" },
    .{ .name = "Bob", .email = "bob@example.com" },
};

var query = try db.newInsert(User);
defer query.deinit();

_ = try query
    .values(&users)
    .returning(&.{"id"});

const sql = try query.build(null);
defer allocator.free(sql);

// 批量插入的 RETURNING 应返回所有插入行的数据
try std.testing.expect(std.mem.indexOf(u8, sql, "VALUES") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "RETURNING id") != null);
```

---

### Requirement: exec() 执行插入

INSERT 查询构建器 MUST 提供 `exec()` 方法执行插入，返回 InsertResult 包含 rows_affected 和 last_insert_id。

#### Scenario: 执行单行插入

```zig
const allocator = std.testing.allocator;
const db = try createRealDB(allocator);
defer db.deinit();

var query = try db.newInsert(User);
defer query.deinit();

const result = try query
    .value(.{ .name = "Alice", .email = "alice@example.com", .age = 25 })
    .exec();

try std.testing.expectEqual(@as(usize, 1), result.rows_affected);
```

#### Scenario: 执行批量插入

```zig
const allocator = std.testing.allocator;
const db = try createRealDB(allocator);
defer db.deinit();

const users = [_]struct { name: []const u8, email: []const u8, age: u32 }{
    .{ .name = "Alice", .email = "alice@example.com", .age = 25 },
    .{ .name = "Bob", .email = "bob@example.com", .age = 30 },
    .{ .name = "Carol", .email = "carol@example.com", .age = 28 },
};

var query = try db.newInsert(User);
defer query.deinit();

const result = try query.values(&users).exec();

try std.testing.expectEqual(@as(usize, 3), result.rows_affected);
```

---

### Requirement: execReturning() 执行并返回数据

INSERT 查询构建器 MUST 提供 `execReturning(dest)` 方法执行插入并将 RETURNING 结果扫描到 ArrayList（仅 PostgreSQL 支持）。

#### Scenario: 单行插入并返回数据

```zig
const allocator = std.testing.allocator;
const db = try createRealDB(allocator);
defer db.deinit();

const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    created_at: i64,
};

var inserted_users = std.ArrayList(User).init(allocator);
defer inserted_users.deinit();

var query = try db.newInsert(User);
defer query.deinit();

try query
    .value(.{ .name = "Alice", .email = "alice@example.com" })
    .returning(&.{"*"})
    .execReturning(&inserted_users);

try std.testing.expectEqual(@as(usize, 1), inserted_users.items.len);
try std.testing.expectEqualStrings("Alice", inserted_users.items[0].name);
try std.testing.expect(inserted_users.items[0].id > 0);
```

#### Scenario: 批量插入并返回数据

```zig
const allocator = std.testing.allocator;
const db = try createRealDB(allocator);
defer db.deinit();

const users = [_]struct { name: []const u8, email: []const u8 }{
    .{ .name = "Alice", .email = "alice@example.com" },
    .{ .name = "Bob", .email = "bob@example.com" },
    .{ .name = "Carol", .email = "carol@example.com" },
};

var inserted_users = std.ArrayList(User).init(allocator);
defer inserted_users.deinit();

var query = try db.newInsert(User);
defer query.deinit();

try query
    .values(&users)
    .returning(&.{"*"})
    .execReturning(&inserted_users);

try std.testing.expectEqual(@as(usize, 3), inserted_users.items.len);
try std.testing.expectEqualStrings("Alice", inserted_users.items[0].name);
try std.testing.expectEqualStrings("Bob", inserted_users.items[1].name);
try std.testing.expectEqualStrings("Carol", inserted_users.items[2].name);
```

#### Scenario: 未设置 RETURNING 时返回错误

```zig
const allocator = std.testing.allocator;
const db = try createRealDB(allocator);
defer db.deinit();

var inserted_users = std.ArrayList(User).init(allocator);
defer inserted_users.deinit();

var query = try db.newInsert(User);
defer query.deinit();

_ = try query.value(.{ .name = "Alice", .email = "alice@example.com" });

// 未调用 returning() 应返回错误
try std.testing.expectError(
    error.NoReturningColumns,
    query.execReturning(&inserted_users)
);
```

---

### Requirement: 内存优化

INSERT 查询构建器 MUST 实现内存预分配优化，预估 SQL 语句大小并预分配缓冲区，减少多次分配开销。

#### Scenario: SQL 缓冲区预分配

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newInsert(User);
defer query.deinit();

// 添加 100 行数据
var i: usize = 0;
while (i < 100) : (i += 1) {
    _ = try query.value(.{
        .name = "User",
        .email = "user@example.com",
        .age = 25,
    });
}

// build() 应该使用预分配优化
const estimated_size = query.estimateSQLSize();
try std.testing.expect(estimated_size > 0);

const sql = try query.build(null);
defer allocator.free(sql);

try std.testing.expect(sql.len > 0);
```

#### Scenario: 批量容量预分配

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

const users = [_]struct { name: []const u8, email: []const u8 }{
    .{ .name = "Alice", .email = "alice@example.com" },
    .{ .name = "Bob", .email = "bob@example.com" },
    .{ .name = "Carol", .email = "carol@example.com" },
};

var query = try db.newInsert(User);
defer query.deinit();

// values() 应该预分配 values_list 容量
const initial_capacity = query.values_list.capacity;
_ = try query.values(&users);

try std.testing.expect(query.values_list.capacity >= initial_capacity + users.len);
```

---

### Requirement: 性能验证

批量插入性能 MUST 比循环单行插入快至少 10 倍，验证批量 SQL 生成的性能优势。

#### Scenario: 批量插入性能基准测试

```zig
test "批量插入性能优于单行插入" {
    const allocator = std.testing.allocator;
    const db = try createRealDB(allocator);
    defer db.deinit();

    const BATCH_SIZE = 1000;
    var users = std.ArrayList(User).init(allocator);
    defer users.deinit();

    var i: usize = 0;
    while (i < BATCH_SIZE) : (i += 1) {
        try users.append(.{
            .name = "User",
            .email = "user@example.com",
            .age = 25,
        });
    }

    // 测试批量插入
    var timer = try std.time.Timer.start();
    const batch_start = timer.read();

    var batch_query = try db.newInsert(User);
    defer batch_query.deinit();
    _ = try batch_query.values(users.items).exec();

    const batch_end = timer.read();
    const batch_time = batch_end - batch_start;

    // 测试单行插入
    const single_start = timer.read();

    for (users.items) |user| {
        var single_query = try db.newInsert(User);
        defer single_query.deinit();
        _ = try single_query.value(user).exec();
    }

    const single_end = timer.read();
    const single_time = single_end - single_start;

    // 批量插入应该至少快 10 倍
    const speedup = @as(f64, @floatFromInt(single_time)) / @as(f64, @floatFromInt(batch_time));
    try std.testing.expect(speedup >= 10.0);

    std.debug.print("\n批量插入加速比: {d:.2}x\n", .{speedup});
}
```

---

### Requirement: 类型安全

INSERT 查询构建器 MUST 在编译时验证类型安全性，仅接受结构体类型，拒绝其他类型。

#### Scenario: 编译时类型检查

```zig
// 以下代码应该编译失败
var query = try db.newInsert(User);
defer query.deinit();

// 传入非结构体类型应该触发 @compileError
_ = try query.value(42); // 编译错误: value() requires a struct
_ = try query.value("string"); // 编译错误: value() requires a struct
_ = try query.value(&[_]i32{1, 2, 3}); // 编译错误: value() requires a struct
```

#### Scenario: 自动参数绑定

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newInsert(User);
defer query.deinit();

_ = try query.value(.{
    .name = "Alice'; DROP TABLE users; --",
    .email = "alice@example.com",
});

const sql = try query.build(null);
defer allocator.free(sql);

// SQL 应该使用参数化查询，防止 SQL 注入
try std.testing.expect(std.mem.indexOf(u8, sql, "$1") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "DROP TABLE") == null);
```

---

### Requirement: 错误处理

INSERT 查询构建器 MUST 提供清晰的错误处理，包括 NoValuesToInsert、BatchSizeTooLarge、ExceedsPostgreSQLParamLimit 等错误。

#### Scenario: 空值列表错误

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var query = try db.newInsert(User);
defer query.deinit();

// 未添加任何值时 build() 应返回错误
try std.testing.expectError(error.NoValuesToInsert, query.build(null));
```

#### Scenario: 批量大小超限错误

```zig
const allocator = std.testing.allocator;
const db = try createTestDB(allocator);
defer db.deinit();

var large_batch = std.ArrayList(User).init(allocator);
defer large_batch.deinit();

// 创建 1001 行数据
var i: usize = 0;
while (i < 1001) : (i += 1) {
    try large_batch.append(.{ .name = "User", .email = "user@example.com", .age = 25 });
}

var query = try db.newInsert(User);
defer query.deinit();

try std.testing.expectError(error.BatchSizeTooLarge, query.values(large_batch.items));
```
