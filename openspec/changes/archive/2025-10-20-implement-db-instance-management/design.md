# DB 实例管理设计文档

## 概述

本文档详细描述 ZORM DB 实例管理功能的设计决策、架构模式和实现细节，确保实现严格符合功能规格说明书 2.1.1 节的要求。

## 架构决策

### ADR-001: 使用 comptime 参数化方言

**决策**：DB 使用 comptime 参数化数据库方言，而非运行时枚举

**理由**：
- 零运行时开销：方言分派在编译时完成
- 类型安全：不同方言的 DB 是不同类型
- 性能优化：编译器可以内联和优化特定方言的代码路径

**权衡**：
- ✅ 优势：性能最优，类型安全
- ❌ 劣势：需要为每个方言实例化类型

**示例**：
```zig
const PostgresDB = DB(.postgresql);
const MySQLDB = DB(.mysql);

// 编译时类型检查
var pg_db: *PostgresDB = try PostgresDB.init(...);
// var mysql_db: *PostgresDB = ...; // 编译错误！类型不匹配
```

### ADR-002: 显式 Allocator 传递

**决策**：所有需要分配内存的操作都显式接受 Allocator 参数

**理由**：
- 符合 Zig 语言惯例
- 调用者完全控制内存分配策略
- 支持多种分配器（GPA, Arena, FixedBuffer 等）
- 便于测试（使用 testing.allocator 检测泄漏）

**模式**：
```zig
pub fn init(allocator: Allocator, conn: Conn, options: DBOptions) !*Self {
    const self = try allocator.create(Self);
    errdefer allocator.destroy(self); // 错误时自动清理

    self.* = .{
        .allocator = allocator,
        .query_hooks = std.ArrayList(QueryHook).init(allocator),
        // ...
    };

    return self;
}

pub fn deinit(self: *Self) void {
    self.query_hooks.deinit(); // 清理子资源
    self.allocator.destroy(self); // 释放自身
}
```

### ADR-003: 查询钩子管理机制

**决策**：使用 `ArrayList(QueryHook)` 而非 `ArrayList(*QueryHook)`

**理由**：
- 简化所有权管理：钩子的生命周期由调用者管理
- 避免悬垂指针：钩子实例由调用者持有
- 符合 Zig 惯例：值语义优于指针语义

**实现**：
```zig
pub fn addHook(self: *Self, hook: QueryHook) !void {
    try self.query_hooks.append(hook);
}

// 使用示例
var logging = LoggingHook.init(true, 1000);
try db.addHook(logging.hook()); // 返回 QueryHook 值
```

**替代方案**（已拒绝）：
- 使用 `ArrayList(*QueryHook)` - 需要管理钩子生命周期，容易出现悬垂指针
- 使用单个钩子 - 不支持钩子链，限制了扩展性

### ADR-004: 连接接口抽象

**决策**：使用 Conn 接口抽象数据库连接，而非直接接受 `anytype`

**理由**：
- 类型安全：编译时验证连接是否实现了必需的方法
- 统一接口：不同数据库驱动实现相同的接口
- 便于测试：可以实现 Mock 连接

**接口定义**：
```zig
pub const Conn = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        exec: *const fn (ptr: *anyopaque, query: []const u8, args: []const QueryArg) anyerror!void,
        query: *const fn (ptr: *anyopaque, query: []const u8, args: []const QueryArg) anyerror!*Result,
        begin: *const fn (ptr: *anyopaque) anyerror!*Tx,
        close: *const fn (ptr: *anyopaque) void,
    };
};
```

**与规格说明书的差异**：
- 规格要求 `conn: anytype`，现实实现使用 `Conn` 接口
- **理由**：Zig 的 `anytype` 在运行时无法提供类型安全保证，接口模式更可靠

## 核心组件设计

### 组件 1: DB 实例

**职责**：
- 管理数据库连接的生命周期
- 提供查询构建器工厂方法
- 管理查询钩子链
- 维护连接统计信息
- 支持事务管理

**状态**：
```zig
pub fn DB(comptime dialect: Dialect) type {
    return struct {
        allocator: Allocator,      // 内存分配器
        conn: Conn,                 // 数据库连接接口
        options: DBOptions,         // 配置选项
        stats: DBStats,             // 统计信息（原子操作）
        active_tx: ?*Tx,            // 活动事务（可选）
        query_hooks: std.ArrayList(QueryHook), // 查询钩子列表
    };
}
```

**生命周期**：
```
创建 (init) → 使用 (query/exec) → 销毁 (deinit)
                   ↓
             可选：开启事务 (beginTx)
```

### 组件 2: DBStats 统计信息

**职责**：
- 记录查询次数
- 记录错误次数
- 跟踪连接状态

**线程安全**：
使用原子操作确保多线程访问安全

```zig
pub const DBStats = struct {
    total_queries: std.atomic.Value(u64),
    total_errors: std.atomic.Value(u64),
    open_connections: std.atomic.Value(u32),
    idle_connections: std.atomic.Value(u32),

    pub fn recordQuery(self: *DBStats) void {
        _ = self.total_queries.fetchAdd(1, .monotonic);
    }
};
```

### 组件 3: 查询执行流程

**流程**：
```
1. 记录统计 (recordQuery)
     ↓
2. 执行钩子 - beforeQuery
     ↓
3. 记录开始时间
     ↓
4. 执行查询 (conn.query 或 tx.query)
     ↓
5. 计算执行时间
     ↓
6. 成功？
   ├─ Yes → 执行钩子 - afterQuery → 返回结果
   └─ No  → 记录错误 + 执行钩子 - onError → 返回错误
```

**实现**：
```zig
pub fn query(self: *Self, query_str: []const u8, args: []const QueryArg) !*Result {
    self.stats.recordQuery();

    // 钩子: beforeQuery
    for (self.query_hooks.items) |hook| {
        hook.beforeQuery(query_str, args) catch |err| {
            std.log.warn("Hook beforeQuery failed: {}", .{err});
        };
    }

    const start_time = std.time.nanoTimestamp();

    // 执行查询
    const result = if (self.active_tx) |tx|
        tx.query(query_str, args)
    else
        self.conn.query(query_str, args);

    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));

    if (result) |res| {
        // 钩子: afterQuery
        for (self.query_hooks.items) |hook| {
            hook.afterQuery(query_str, args, duration_ns) catch |err| {
                std.log.warn("Hook afterQuery failed: {}", .{err});
            };
        }
        return res;
    } else |err| {
        self.stats.recordError();

        // 钩子: onError
        for (self.query_hooks.items) |hook| {
            hook.onError(query_str, args, err) catch |hook_err| {
                std.log.warn("Hook onError failed: {}", .{hook_err});
            };
        }

        return err;
    }
}
```

## 内存管理策略

### 策略 1: 清晰的所有权语义

**原则**：
- DB 实例拥有其内部资源（query_hooks 列表）
- 调用者拥有 DB 实例本身
- 查询构建器拥有其内部缓冲区
- 调用者拥有查询结果

**模式**：
```zig
// 调用者负责 deinit
var db = try DB.init(allocator, conn, .{});
defer db.deinit();

// 调用者负责 deinit
var query = try db.newSelect(User);
defer query.deinit();

// 调用者负责释放结果
var users = std.ArrayList(User).init(allocator);
defer users.deinit();
```

### 策略 2: errdefer 自动清理

**模式**：
```zig
pub fn init(allocator: Allocator, conn: Conn, options: DBOptions) !*Self {
    const self = try allocator.create(Self);
    errdefer allocator.destroy(self); // 错误时自动清理

    self.query_hooks = std.ArrayList(QueryHook).init(allocator);
    errdefer self.query_hooks.deinit(); // 嵌套清理

    // 更多初始化...

    return self;
}
```

### 策略 3: Arena 优化临时分配

**使用场景**：
- SQL 字符串构建
- 参数列表构建
- 临时缓冲区

**模式**：
```zig
pub const QueryContext = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(base_allocator: Allocator) QueryContext {
        return .{ .arena = std.heap.ArenaAllocator.init(base_allocator) };
    }

    pub fn deinit(self: *QueryContext) void {
        self.arena.deinit(); // 一次性释放所有
    }

    pub fn allocator(self: *QueryContext) Allocator {
        return self.arena.allocator();
    }
};
```

## 错误处理设计

### 错误类型定义

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
};
```

### 错误处理模式

**模式 1：传播错误**
```zig
pub fn findUser(db: *DB, id: i64) !User {
    var query = try db.newSelect(User);
    defer query.deinit();

    try query.where("id = ?", .{id});
    return try query.scanOne(); // 传播错误
}
```

**模式 2：捕获和转换**
```zig
pub fn findUserSafe(db: *DB, id: i64) ?User {
    return findUser(db, id) catch |err| {
        std.log.err("Failed to find user: {}", .{err});
        return null;
    };
}
```

**模式 3：错误恢复**
```zig
pub fn findUserWithDefault(db: *DB, id: i64) User {
    return findUser(db, id) catch {
        return User{ .id = -1, .name = "Unknown", .email = "" };
    };
}
```

## 性能优化策略

### 优化 1: comptime SQL 生成

```zig
pub fn simpleSelect(comptime T: type, comptime where_clause: []const u8) []const u8 {
    return comptime blk: {
        const table_name = getTableName(T);
        break :blk std.fmt.comptimePrint(
            "SELECT * FROM {s} WHERE {s}",
            .{ table_name, where_clause },
        );
    };
}
```

### 优化 2: inline 热路径

```zig
pub inline fn scanField(comptime T: type, row: *Row, index: usize) !T {
    return switch (T) {
        i32, i64 => try row.getInt(T, index),
        f32, f64 => try row.getFloat(T, index),
        bool => try row.getBool(index),
        []const u8 => try row.getString(index),
        else => @compileError("Unsupported type"),
    };
}
```

### 优化 3: Buffer 复用

```zig
pub const QueryBuilder = struct {
    buf: std.ArrayList(u8),

    pub fn reset(self: *QueryBuilder) void {
        self.buf.clearRetainingCapacity(); // 保留容量
    }
};
```

## 测试策略

### 单元测试覆盖

1. **DBStats 测试**：
   - 记录查询和错误
   - 原子操作正确性
   - 并发访问安全性

2. **DB 生命周期测试**：
   - init/deinit 正确性
   - 内存泄漏检测
   - clone 和 withQueryHook

3. **查询执行测试**：
   - exec 和 query 方法
   - 钩子调用顺序
   - 错误处理

4. **事务管理测试**：
   - begin/commit/rollback
   - 嵌套事务检测
   - 事务回滚

### 集成测试场景

1. **完整查询流程**：
   - 连接 → 查询 → 扫描结果 → 关闭

2. **事务场景**：
   - 成功提交
   - 回滚
   - 错误处理

3. **钩子集成**：
   - 日志钩子
   - 性能监控
   - 错误追踪

### 性能基准测试

1. **批量插入**
2. **复杂查询**
3. **事务吞吐量**
4. **内存分配开销**

## 兼容性考虑

### 向后兼容性

- 保留旧版 `begin()/commit()/rollback()` API
- 添加 `@deprecated` 标记引导用户迁移到新 API
- 提供迁移指南

### 前向兼容性

- 使用 comptime 参数化设计，便于添加新方言
- 预留扩展点（钩子系统）
- 保持 API 稳定性

## 安全考虑

### SQL 注入防护

- 所有查询使用参数绑定
- 禁止字符串拼接
- 提供安全的 Raw SQL 接口

### 内存安全

- 使用 Zig 的内存安全保证
- testing.allocator 检测泄漏
- errdefer 确保清理

### 并发安全

- DBStats 使用原子操作
- 连接池线程安全
- 事务隔离

## 参考资料

1. Zig Language Reference - Memory Management
2. Zig Standard Library - Allocator Patterns
3. Bun ORM Documentation
4. PostgreSQL Wire Protocol
5. ZORM 功能规格说明书 2.1.1 节
