# ZORM 架构设计文档

**Version**: v1.0
**Date**: 2025-01-16
**Author**: Winston (System Architect)
**Project**: ZORM - SQL-first Zig ORM
**Target Language**: Zig 0.15.2+

---

## 目录

1. [架构概述](#架构概述)
2. [核心设计原则](#核心设计原则)
3. [模块架构](#模块架构)
4. [核心模块详细设计](#核心模块详细设计)
5. [数据流与执行模型](#数据流与执行模型)
6. [编译期 vs 运行期](#编译期-vs-运行期)
7. [内存管理策略](#内存管理策略)
8. [错误处理策略](#错误处理策略)
9. [性能优化策略](#性能优化策略)
10. [方言系统设计](#方言系统设计)
11. [接口定义](#接口定义)
12. [目录结构](#目录结构)
13. [构建系统](#构建系统)

---

## 架构概述

### 核心理念

ZORM 是一个基于 Zig 编译期元编程 (comptime) 的 SQL-first ORM 框架。其核心设计理念是:

1. **零运行时反射开销**: 所有类型内省和代码生成在编译时完成
2. **显式优于隐式**: 使用 Zig 的 Allocator 模式进行显式内存管理
3. **类型安全优先**: 利用 Zig 的类型系统在编译时捕获错误
4. **SQL 透明性**: 保持对底层 SQL 的完全控制,避免隐藏的查询开销
5. **无面向对象**: 使用函数式和泛型编程范式,而非传统 OOP

### 架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                         Application Layer                        │
│                  (用户代码使用 ZORM API)                          │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│                    Public API Layer (zorm.zig)                   │
│  - DB(comptime dialect)                                          │
│  - SelectQuery(comptime T, comptime dialect)                     │
│  - InsertQuery/UpdateQuery/DeleteQuery                           │
└──────────┬───────────────────────────────────┬───────────────────┘
           │                                   │
┌──────────▼────────────┐         ┌───────────▼──────────────────┐
│   Query Builder Layer  │         │     Mapper Layer             │
│  - query/select.zig    │         │  - mapper/type_info.zig      │
│  - query/insert.zig    │◄────────┤  - mapper/field_mapper.zig   │
│  - query/update.zig    │         │  - mapper/result_scanner.zig │
│  - query/delete.zig    │         └──────────────────────────────┘
└──────────┬────────────┘
           │
┌──────────▼──────────────────────────────────────────────────────┐
│                        Core Layer                                 │
│  - core/db.zig (DB 实例管理)                                      │
│  - core/transaction.zig (事务管理)                                │
│  - core/hooks.zig (查询钩子)                                      │
└──────────┬──────────────────────────────────┬───────────────────┘
           │                                   │
┌──────────▼────────────┐         ┌───────────▼──────────────────┐
│   Dialect Layer        │         │   Driver Layer               │
│  - dialect/dialect.zig │         │  - driver/connection.zig     │
│  - dialect/sql.zig     │         │  - driver/postgres.zig       │
│  (编译时特性检测)       │         │  - driver/mysql.zig          │
└────────────────────────┘         │  - driver/sqlite.zig         │
                                   │  - driver/pool.zig           │
                                   └──────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│                    Foundation Layer                              │
│  - error.zig (错误定义)                                          │
│  - types.zig (基础类型)                                          │
│  - allocator.zig (Allocator 工具)                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## 核心设计原则

### 1. Comptime-First 架构

**避免运行时反射**: Zig 不支持运行时反射,所有类型信息通过 `@typeInfo` 在编译时提取。

```zig
// ❌ 错误: 运行时反射 (不存在)
// const field_name = getFieldName(user, 0); // 无法在运行时获取字段名

// ✅ 正确: 编译时反射
fn getFieldNames(comptime T: type) []const []const u8 {
    const fields = @typeInfo(T).Struct.fields;
    comptime var names: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |field, i| {
        names[i] = field.name;
    }
    return &names;
}
```

**泛型特化而非多态**: 使用 comptime 参数化的泛型结构体,而非接口和虚函数表。

```zig
// ❌ 避免: 传统 OOP 多态
// pub const Connection = interface { ... }; // Zig 无接口

// ✅ 推荐: 泛型特化
pub fn Connection(comptime Driver: type) type {
    return struct {
        driver: Driver,
        pub fn exec(self: *@This(), sql: []const u8) !Result {
            return self.driver.exec(sql); // 编译时已知类型,无虚函数调用
        }
    };
}
```

### 2. 显式内存管理

**Allocator 模式**: 所有需要分配内存的函数都接受 `Allocator` 参数。

```zig
pub fn init(allocator: Allocator, conn: Connection) !*DB {
    const db = try allocator.create(DB);
    db.* = .{
        .allocator = allocator,
        .conn = conn,
        .stats = .{},
    };
    return db;
}

pub fn deinit(self: *DB) void {
    self.allocator.destroy(self);
}
```

**Arena Allocator 用于临时分配**: 查询构建过程使用 `ArenaAllocator`,查询结束后一次性释放。

```zig
pub const SelectQuery = struct {
    arena: std.heap.ArenaAllocator,
    base_allocator: Allocator,

    pub fn init(allocator: Allocator) !SelectQuery {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .base_allocator = allocator,
        };
    }

    pub fn deinit(self: *SelectQuery) void {
        self.arena.deinit(); // 一次性释放所有临时分配
    }
};
```

### 3. 强制错误处理

所有可能失败的操作返回 `!T` (错误联合类型):

```zig
pub fn scanOne(self: *SelectQuery) !User {
    const rows = try self.execute();
    if (rows.len == 0) return error.NoRows;
    if (rows.len > 1) return error.TooManyRows;
    return rows[0];
}

// 调用者必须处理错误
const user = try query.scanOne(); // 传播错误
// 或者
const user = query.scanOne() catch |err| {
    std.log.err("Failed to fetch user: {}", .{err});
    return null;
};
```

### 4. 零成本抽象

**内联热路径函数**:

```zig
inline fn setField(comptime T: type, ptr: *T, comptime field_name: []const u8, value: anytype) void {
    @field(ptr, field_name) = value;
}
```

**编译时预计算**:

```zig
const table_name = comptime getTableName(User); // 编译时计算
const field_count = comptime @typeInfo(User).Struct.fields.len; // 编译时已知
```

---

## ⚠️ Zig 0.15.2 重要 API 变化

### std.ArrayList 的正确用法

**在 Zig 0.15.2 中,`std.ArrayList` 默认返回 unmanaged 版本,API 发生了显著变化**

#### ❌ 错误用法 (Zig 0.14.x 及更早版本)

```zig
// ❌ 在 Zig 0.15.2 中不再有效!
var list = std.ArrayList(T).init(allocator);  // 错误: init() 方法不存在
defer list.deinit();                          // 错误: deinit() 缺少参数
try list.append(item);                         // 错误: append() 缺少参数
const slice = list.toOwnedSlice();            // 错误: toOwnedSlice() 缺少参数
```

#### ✅ 正确用法 (Zig 0.15.2+)

```zig
// ✅ 使用结构体字面量初始化 (unmanaged ArrayList)
var list: std.ArrayList(T) = .{};
defer list.deinit(allocator);                  // 必须传递 allocator
try list.append(allocator, item);              // 必须传递 allocator
const slice = try list.toOwnedSlice(allocator); // 必须传递 allocator
```

#### 完整示例对比

```zig
// ===== Zig 0.14.x 及更早版本 =====
// ❌ 以下代码在 Zig 0.15.2 中会编译失败
pub fn oldWay(allocator: Allocator) !void {
    var connections = std.ArrayList(*Conn).init(allocator);
    defer connections.deinit();

    try connections.append(conn1);
    try connections.append(conn2);

    const items = connections.toOwnedSlice();
    defer allocator.free(items);
}

// ===== Zig 0.15.2+ =====
// ✅ 正确的实现方式
pub fn newWay(allocator: Allocator) !void {
    var connections: std.ArrayList(*Conn) = .{};  // 结构体字面量
    defer connections.deinit(allocator);           // 传递 allocator

    try connections.append(allocator, conn1);      // 传递 allocator
    try connections.append(allocator, conn2);      // 传递 allocator

    const items = try connections.toOwnedSlice(allocator);  // 传递 allocator
    defer allocator.free(items);
}
```

#### ArrayList(u8).writer() 的用法变化

```zig
// ❌ 错误 (Zig 0.14.x 风格)
var buf = std.ArrayList(u8).init(allocator);
defer buf.deinit();
const writer = buf.writer();  // 错误: writer() 缺少参数

// ✅ 正确 (Zig 0.15.2+)
var buf: std.ArrayList(u8) = .{};
defer buf.deinit(allocator);
const writer = buf.writer(allocator);  // 必须传递 allocator
```

#### 常用方法的 Allocator 参数

所有 unmanaged ArrayList 的内存管理方法都需要显式传递 allocator:

| 方法 | Zig 0.14.x | Zig 0.15.2+ |
|------|-----------|-------------|
| 初始化 | `.init(allocator)` | `: T = .{}` |
| 释放 | `.deinit()` | `.deinit(allocator)` |
| 添加元素 | `.append(item)` | `.append(allocator, item)` |
| 批量添加 | `.appendSlice(items)` | `.appendSlice(allocator, items)` |
| 转移所有权 | `.toOwnedSlice()` | `.toOwnedSlice(allocator)` |
| 获取 writer | `.writer()` | `.writer(allocator)` |

#### 关键要点

1. **初始化**: 使用 `var list: std.ArrayList(T) = .{}` 而不是 `.init(allocator)`
2. **Allocator 参数**: 所有方法都需要显式传递 allocator
3. **结构体字面量**: `.{}` 是 Zig 的结构体默认初始化语法
4. **向后不兼容**: Zig 0.14.x 的代码在 0.15.2 中**不会编译通过**

#### 迁移检查清单

在将代码迁移到 Zig 0.15.2 时,请检查所有 ArrayList 使用:

- [ ] 将 `ArrayList(T).init(allocator)` 改为 `ArrayList(T) = .{}`
- [ ] 为 `deinit()` 添加 allocator 参数
- [ ] 为 `append()` 添加 allocator 参数
- [ ] 为 `toOwnedSlice()` 添加 allocator 参数
- [ ] 为 `writer()` 添加 allocator 参数
- [ ] 检查所有其他 ArrayList 方法调用

---

## 模块架构

### 分层架构

```
Layer 6: Schema Layer (src/schema/)
         ├── table.zig (CREATE TABLE)
         └── migration.zig (迁移系统)

Layer 5: Mapper Layer (src/mapper/)
         ├── type_info.zig (comptime 类型反射)
         ├── field_mapper.zig (字段映射)
         └── result_scanner.zig (结果扫描)

Layer 4: Query Builder Layer (src/query/)
         ├── select.zig (SELECT 查询)
         ├── insert.zig (INSERT 查询)
         ├── update.zig (UPDATE 查询)
         ├── delete.zig (DELETE 查询)
         └── builder_base.zig (共享逻辑)

Layer 3: Core Layer (src/core/)
         ├── db.zig (DB 实例)
         ├── transaction.zig (事务管理)
         └── hooks.zig (查询钩子)

Layer 2: Dialect Layer (src/dialect/)
         ├── dialect.zig (方言定义)
         └── sql.zig (SQL 生成工具)

Layer 1: Driver Layer (src/driver/)
         ├── connection.zig (连接接口)
         ├── postgres.zig (PostgreSQL 驱动)
         ├── mysql.zig (MySQL 驱动)
         ├── sqlite.zig (SQLite 驱动)
         └── pool.zig (连接池)

Layer 0: Foundation Layer (src/)
         ├── error.zig (错误定义)
         ├── types.zig (基础类型)
         └── allocator.zig (Allocator 工具)
```

**依赖规则**:
- 上层可以依赖下层,下层不能依赖上层
- 同层之间尽量减少依赖
- 所有模块都可以依赖 Layer 0

---

## 核心模块详细设计

### 1. ConnectionManager (driver/pool.zig)

**职责**:
- 管理数据库连接的生命周期
- 实现连接池(可选)
- 提供连接获取和释放接口

**设计**:

```zig
/// 连接接口 (编译时多态)
pub fn Connection(comptime Driver: type) type {
    return struct {
        const Self = @This();

        driver: Driver,
        allocator: Allocator,

        /// 执行查询
        pub fn exec(self: *Self, sql: []const u8, args: []const QueryArg) !Result {
            return self.driver.exec(sql, args);
        }

        /// 执行查询并返回结果集
        pub fn query(self: *Self, sql: []const u8, args: []const QueryArg) !Rows {
            return self.driver.query(sql, args);
        }

        /// 关闭连接
        pub fn close(self: *Self) !void {
            try self.driver.close();
        }
    };
}

/// 连接池
pub fn Pool(comptime Driver: type) type {
    return struct {
        const Self = @This();
        const Conn = Connection(Driver);

        allocator: Allocator,
        connections: std.ArrayList(*Conn),
        available: std.ArrayList(*Conn),
        mutex: std.Thread.Mutex,
        config: PoolConfig,

        pub const PoolConfig = struct {
            max_open_conns: u32 = 25,
            max_idle_conns: u32 = 25,
            conn_max_lifetime: u64 = 300, // 秒
        };

        pub fn init(allocator: Allocator, config: PoolConfig) !*Self {
            const pool = try allocator.create(Self);
            pool.* = .{
                .allocator = allocator,
                .connections = .{},  // ✅ Zig 0.15.2: 使用结构体字面量
                .available = .{},    // ✅ Zig 0.15.2: 使用结构体字面量
                .mutex = .{},
                .config = config,
            };
            return pool;
        }

        pub fn acquire(self: *Self) !*Conn {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.available.items.len > 0) {
                return self.available.pop();
            }

            if (self.connections.items.len < self.config.max_open_conns) {
                const conn = try self.createConnection();
                try self.connections.append(self.allocator, conn);  // ✅ Zig 0.15.2: 传递 allocator
                return conn;
            }

            return error.ConnectionPoolExhausted;
        }

        pub fn release(self: *Self, conn: *Conn) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            try self.available.append(self.allocator, conn);  // ✅ Zig 0.15.2: 传递 allocator
        }

        fn createConnection(self: *Self) !*Conn {
            // 创建新连接的逻辑
            // 这里会调用具体驱动的连接函数
            _ = self;
            return error.NotImplemented;
        }

        pub fn deinit(self: *Self) void {
            for (self.connections.items) |conn| {
                conn.close() catch {};
                self.allocator.destroy(conn);
            }
            self.connections.deinit(self.allocator);  // ✅ Zig 0.15.2: 传递 allocator
            self.available.deinit(self.allocator);    // ✅ Zig 0.15.2: 传递 allocator
            self.allocator.destroy(self);
        }
    };
}
```

### 2. QueryBuilder(comptime T: type) (query/select.zig)

**职责**:
- 提供类型安全的查询构建 API
- 在编译时提取模型 T 的元数据
- 在运行时组装 SQL 字符串
- 支持链式调用

**设计**:

```zig
/// SELECT 查询构建器
pub fn SelectQuery(comptime T: type, comptime dialect: Dialect) type {
    return struct {
        const Self = @This();

        // 编译时计算的元数据
        const table_name = comptime getTableName(T);
        const field_names = comptime getFieldNames(T);
        const field_types = comptime getFieldTypes(T);

        // 运行时状态
        arena: std.heap.ArenaAllocator,
        base_allocator: Allocator,
        db: *DB(dialect),

        selected_columns: ?[]const []const u8,
        where_clauses: std.ArrayList(WhereClause),
        join_clauses: std.ArrayList(JoinClause),
        order_by_clauses: std.ArrayList(OrderByClause),
        group_by_columns: std.ArrayList([]const u8),
        having_clauses: std.ArrayList(HavingClause),

        limit_value: ?usize,
        offset_value: ?usize,
        distinct: bool,

        pub fn init(allocator: Allocator, db: *DB(dialect)) !*Self {
            const query = try allocator.create(Self);
            query.* = .{
                .arena = std.heap.ArenaAllocator.init(allocator),
                .base_allocator = allocator,
                .db = db,
                .selected_columns = null,
                .where_clauses = .{},     // ✅ Zig 0.15.2: 使用结构体字面量
                .join_clauses = .{},      // ✅ Zig 0.15.2: 使用结构体字面量
                .order_by_clauses = .{},  // ✅ Zig 0.15.2: 使用结构体字面量
                .group_by_columns = .{},  // ✅ Zig 0.15.2: 使用结构体字面量
                .having_clauses = .{},    // ✅ Zig 0.15.2: 使用结构体字面量
                .limit_value = null,
                .offset_value = null,
                .distinct = false,
            };
            return query;
        }

        pub fn deinit(self: *Self) void {
            self.where_clauses.deinit(self.base_allocator);     // ✅ Zig 0.15.2: 传递 allocator
            self.join_clauses.deinit(self.base_allocator);      // ✅ Zig 0.15.2: 传递 allocator
            self.order_by_clauses.deinit(self.base_allocator);  // ✅ Zig 0.15.2: 传递 allocator
            self.group_by_columns.deinit(self.base_allocator);  // ✅ Zig 0.15.2: 传递 allocator
            self.having_clauses.deinit(self.base_allocator);    // ✅ Zig 0.15.2: 传递 allocator
            self.arena.deinit();
            self.base_allocator.destroy(self);
        }

        /// 选择特定列
        pub fn column(self: *Self, col: []const u8) !*Self {
            const allocator = self.arena.allocator();
            if (self.selected_columns == null) {
                var cols: std.ArrayList([]const u8) = .{};  // ✅ Zig 0.15.2: 使用结构体字面量
                try cols.append(allocator, try allocator.dupe(u8, col));  // ✅ 传递 allocator
                self.selected_columns = try cols.toOwnedSlice(allocator);  // ✅ 传递 allocator
            } else {
                var cols = std.ArrayList([]const u8).fromOwnedSlice(allocator, @constCast(self.selected_columns.?));
                try cols.append(allocator, try allocator.dupe(u8, col));  // ✅ 传递 allocator
                self.selected_columns = try cols.toOwnedSlice(allocator);  // ✅ 传递 allocator
            }
            return self;
        }

        /// 选择所有列 (使用编译时反射)
        pub fn allColumns(self: *Self) !*Self {
            self.selected_columns = &field_names;
            return self;
        }

        /// 添加 WHERE 条件
        pub fn where(self: *Self, condition: []const u8, args: anytype) !*Self {
            const allocator = self.arena.allocator();
            const where_clause = WhereClause{
                .condition = try allocator.dupe(u8, condition),
                .args = try allocArgs(allocator, args),
                .operator = .and_op,
            };
            try self.where_clauses.append(self.base_allocator, where_clause);  // ✅ Zig 0.15.2: 传递 allocator
            return self;
        }

        /// 添加 OR 条件
        pub fn whereOr(self: *Self, condition: []const u8, args: anytype) !*Self {
            const allocator = self.arena.allocator();
            const where_clause = WhereClause{
                .condition = try allocator.dupe(u8, condition),
                .args = try allocArgs(allocator, args),
                .operator = .or_op,
            };
            try self.where_clauses.append(self.base_allocator, where_clause);  // ✅ Zig 0.15.2: 传递 allocator
            return self;
        }

        /// 添加 JOIN
        pub fn join(self: *Self, join_type: JoinType, table: []const u8, condition: []const u8) !*Self {
            const allocator = self.arena.allocator();
            const join_clause = JoinClause{
                .join_type = join_type,
                .table = try allocator.dupe(u8, table),
                .condition = try allocator.dupe(u8, condition),
            };
            try self.join_clauses.append(self.base_allocator, join_clause);  // ✅ Zig 0.15.2: 传递 allocator
            return self;
        }

        /// 添加 ORDER BY
        pub fn orderBy(self: *Self, col: []const u8, direction: OrderDirection) !*Self {
            const allocator = self.arena.allocator();
            const order_clause = OrderByClause{
                .column = try allocator.dupe(u8, col),
                .direction = direction,
            };
            try self.order_by_clauses.append(self.base_allocator, order_clause);  // ✅ Zig 0.15.2: 传递 allocator
            return self;
        }

        /// 设置 LIMIT
        pub fn limit(self: *Self, n: usize) *Self {
            self.limit_value = n;
            return self;
        }

        /// 设置 OFFSET
        pub fn offset(self: *Self, n: usize) *Self {
            self.offset_value = n;
            return self;
        }

        /// 设置 DISTINCT
        pub fn setDistinct(self: *Self) *Self {
            self.distinct = true;
            return self;
        }

        /// 构建 SQL 字符串 (运行时)
        pub fn buildSQL(self: *Self) ![]const u8 {
            const allocator = self.arena.allocator();
            var sql: std.ArrayList(u8) = .{};  // ✅ Zig 0.15.2: 使用结构体字面量
            const writer = sql.writer(allocator);  // ✅ Zig 0.15.2: 传递 allocator

            // SELECT [DISTINCT] columns
            try writer.writeAll("SELECT ");
            if (self.distinct) {
                try writer.writeAll("DISTINCT ");
            }

            if (self.selected_columns) |cols| {
                for (cols, 0..) |col, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll(col);
                }
            } else {
                try writer.writeAll("*");
            }

            // FROM table
            try writer.print(" FROM {s}", .{table_name});

            // JOINs
            for (self.join_clauses.items) |join_clause| {
                try writer.print(" {s} JOIN {s} ON {s}", .{
                    @tagName(join_clause.join_type),
                    join_clause.table,
                    join_clause.condition,
                });
            }

            // WHERE
            if (self.where_clauses.items.len > 0) {
                try writer.writeAll(" WHERE ");
                for (self.where_clauses.items, 0..) |where_clause, i| {
                    if (i > 0) {
                        switch (where_clause.operator) {
                            .and_op => try writer.writeAll(" AND "),
                            .or_op => try writer.writeAll(" OR "),
                        }
                    }
                    try writer.writeAll(where_clause.condition);
                }
            }

            // GROUP BY
            if (self.group_by_columns.items.len > 0) {
                try writer.writeAll(" GROUP BY ");
                for (self.group_by_columns.items, 0..) |col, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll(col);
                }
            }

            // HAVING
            if (self.having_clauses.items.len > 0) {
                try writer.writeAll(" HAVING ");
                for (self.having_clauses.items, 0..) |having_clause, i| {
                    if (i > 0) try writer.writeAll(" AND ");
                    try writer.writeAll(having_clause.condition);
                }
            }

            // ORDER BY
            if (self.order_by_clauses.items.len > 0) {
                try writer.writeAll(" ORDER BY ");
                for (self.order_by_clauses.items, 0..) |order_clause, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("{s} {s}", .{
                        order_clause.column,
                        if (order_clause.direction == .asc) "ASC" else "DESC",
                    });
                }
            }

            // LIMIT
            if (self.limit_value) |limit_val| {
                try writer.print(" LIMIT {d}", .{limit_val});
            }

            // OFFSET
            if (self.offset_value) |offset_val| {
                try writer.print(" OFFSET {d}", .{offset_val});
            }

            return sql.toOwnedSlice(allocator);  // ✅ Zig 0.15.2: 传递 allocator
        }

        /// 执行查询并扫描结果到 ArrayList(T)
        pub fn scan(self: *Self, allocator: Allocator, dest: *std.ArrayList(T)) !void {
            const sql = try self.buildSQL();
            const args = try self.collectArgs();

            const rows = try self.db.conn.query(sql, args);
            defer rows.deinit();

            while (try rows.next()) |row| {
                const item = try scanRow(T, row, allocator);
                try dest.append(allocator, item);  // ✅ Zig 0.15.2: 传递 allocator
            }
        }

        /// 扫描单行
        pub fn scanOne(self: *Self) !T {
            _ = self.limit(1);
            const sql = try self.buildSQL();
            const args = try self.collectArgs();

            const rows = try self.db.conn.query(sql, args);
            defer rows.deinit();

            if (try rows.next()) |row| {
                return try scanRow(T, row, self.base_allocator);
            }

            return error.NoRows;
        }

        /// 收集所有参数
        fn collectArgs(self: *Self) ![]const QueryArg {
            const allocator = self.arena.allocator();
            var args: std.ArrayList(QueryArg) = .{};  // ✅ Zig 0.15.2: 使用结构体字面量

            for (self.where_clauses.items) |where_clause| {
                try args.appendSlice(allocator, where_clause.args);  // ✅ 传递 allocator
            }

            for (self.having_clauses.items) |having_clause| {
                try args.appendSlice(allocator, having_clause.args);  // ✅ 传递 allocator
            }

            return args.toOwnedSlice(allocator);  // ✅ 传递 allocator
        }
    };
}

/// 编译时提取表名
fn getTableName(comptime T: type) []const u8 {
    if (@hasDecl(T, "table_name")) {
        return T.table_name;
    }
    return @typeName(T);
}

/// 编译时提取字段名
fn getFieldNames(comptime T: type) []const []const u8 {
    const fields = @typeInfo(T).Struct.fields;
    comptime var names: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |field, i| {
        names[i] = field.name;
    }
    return &names;
}

/// 编译时提取字段类型
fn getFieldTypes(comptime T: type) []const type {
    const fields = @typeInfo(T).Struct.fields;
    comptime var types: [fields.len]type = undefined;
    inline for (fields, 0..) |field, i| {
        types[i] = field.type;
    }
    return &types;
}
```

### 3. ModelMapper(comptime T: type) (mapper/field_mapper.zig)

**职责**:
- 将数据库行数据映射到 Zig 结构体
- 在编译时生成字段映射逻辑
- 处理类型转换和可选字段

**设计**:

```zig
/// 将数据库行扫描到结构体 T (编译时生成映射逻辑)
pub fn scanRow(comptime T: type, row: *Row, allocator: Allocator) !T {
    var result: T = undefined;

    const fields = @typeInfo(T).Struct.fields;
    inline for (fields, 0..) |field, i| {
        const field_value = try getFieldValue(field.type, row, i, allocator);
        @field(result, field.name) = field_value;
    }

    return result;
}

/// 获取字段值 (根据类型)
fn getFieldValue(comptime FieldType: type, row: *Row, index: usize, allocator: Allocator) !FieldType {
    const type_info = @typeInfo(FieldType);

    // 处理可选类型
    if (type_info == .Optional) {
        if (row.isNull(index)) {
            return null;
        }
        const child_type = type_info.Optional.child;
        return try getFieldValue(child_type, row, index, allocator);
    }

    // 处理基础类型
    switch (type_info) {
        .Int => |int_info| {
            if (int_info.signedness == .signed) {
                return @intCast(try row.getInt(i64, index));
            } else {
                return @intCast(try row.getInt(u64, index));
            }
        },
        .Float => {
            return @floatCast(try row.getFloat(f64, index));
        },
        .Bool => {
            return try row.getBool(index);
        },
        .Pointer => |ptr_info| {
            if (ptr_info.size == .Slice and ptr_info.child == u8) {
                // []const u8 (字符串)
                const str = try row.getString(index);
                if (ptr_info.is_const) {
                    return str; // 借用 row 的内存
                } else {
                    return try allocator.dupe(u8, str); // 复制字符串
                }
            }
            return error.UnsupportedType;
        },
        else => return error.UnsupportedType,
    }
}

/// Row 接口 (由驱动实现)
pub const Row = struct {
    driver_row: *anyopaque,
    vtable: *const RowVTable,

    pub const RowVTable = struct {
        isNull: *const fn (*anyopaque, usize) bool,
        getInt: *const fn (*anyopaque, comptime type, usize) anyerror!i64,
        getFloat: *const fn (*anyopaque, comptime type, usize) anyerror!f64,
        getBool: *const fn (*anyopaque, usize) anyerror!bool,
        getString: *const fn (*anyopaque, usize) anyerror![]const u8,
    };

    pub fn isNull(self: *Row, index: usize) bool {
        return self.vtable.isNull(self.driver_row, index);
    }

    pub fn getInt(self: *Row, comptime T: type, index: usize) !T {
        const value = try self.vtable.getInt(self.driver_row, T, index);
        return @intCast(value);
    }

    pub fn getFloat(self: *Row, comptime T: type, index: usize) !T {
        const value = try self.vtable.getFloat(self.driver_row, T, index);
        return @floatCast(value);
    }

    pub fn getBool(self: *Row, index: usize) !bool {
        return self.vtable.getBool(self.driver_row, index);
    }

    pub fn getString(self: *Row, index: usize) ![]const u8 {
        return self.vtable.getString(self.driver_row, index);
    }
};
```

### 4. TransactionManager (core/transaction.zig)

**职责**:
- 管理事务生命周期
- 提供 BEGIN/COMMIT/ROLLBACK 接口
- 支持嵌套事务和保存点
- 使用 defer/errdefer 实现自动回滚

**设计**:

```zig
pub fn Transaction(comptime dialect: Dialect) type {
    return struct {
        const Self = @This();

        db: *DB(dialect),
        active: bool,
        savepoint_level: u32,

        /// 开始事务
        pub fn begin(db: *DB(dialect)) !Self {
            try db.conn.exec("BEGIN", &.{});
            return .{
                .db = db,
                .active = true,
                .savepoint_level = 0,
            };
        }

        /// 提交事务
        pub fn commit(self: *Self) !void {
            if (!self.active) return error.NoActiveTransaction;

            try self.db.conn.exec("COMMIT", &.{});
            self.active = false;
        }

        /// 回滚事务
        pub fn rollback(self: *Self) !void {
            if (!self.active) return error.NoActiveTransaction;

            try self.db.conn.exec("ROLLBACK", &.{});
            self.active = false;
        }

        /// 创建保存点 (嵌套事务)
        pub fn savepoint(self: *Self, name: []const u8) !void {
            if (!self.active) return error.NoActiveTransaction;

            const sql = try std.fmt.allocPrint(
                self.db.allocator,
                "SAVEPOINT {s}",
                .{name}
            );
            defer self.db.allocator.free(sql);

            try self.db.conn.exec(sql, &.{});
            self.savepoint_level += 1;
        }

        /// 回滚到保存点
        pub fn rollbackTo(self: *Self, name: []const u8) !void {
            if (!self.active) return error.NoActiveTransaction;

            const sql = try std.fmt.allocPrint(
                self.db.allocator,
                "ROLLBACK TO SAVEPOINT {s}",
                .{name}
            );
            defer self.db.allocator.free(sql);

            try self.db.conn.exec(sql, &.{});
        }

        /// 释放保存点
        pub fn releaseSavepoint(self: *Self, name: []const u8) !void {
            if (!self.active) return error.NoActiveTransaction;

            const sql = try std.fmt.allocPrint(
                self.db.allocator,
                "RELEASE SAVEPOINT {s}",
                .{name}
            );
            defer self.db.allocator.free(sql);

            try self.db.conn.exec(sql, &.{});
            if (self.savepoint_level > 0) {
                self.savepoint_level -= 1;
            }
        }

        /// 自动管理事务的便利函数
        pub fn withTransaction(
            db: *DB(dialect),
            comptime func: anytype,
            args: anytype
        ) !@TypeOf(func(args)) {
            var tx = try Self.begin(db);
            errdefer tx.rollback() catch {};

            const result = try @call(.auto, func, args);
            try tx.commit();

            return result;
        }
    };
}

/// 使用示例
pub fn example(db: *DB(.postgres)) !void {
    // 方式1: 手动管理
    var tx = try Transaction(.postgres).begin(db);
    defer tx.rollback() catch {}; // 确保异常时回滚

    try db.exec("INSERT INTO users (name) VALUES ($1)", .{"Alice"});
    try db.exec("INSERT INTO posts (user_id, title) VALUES ($1, $2)", .{1, "Hello"});

    try tx.commit();

    // 方式2: 自动管理
    try Transaction(.postgres).withTransaction(db, struct {
        fn execute(d: *DB(.postgres)) !void {
            try d.exec("INSERT INTO users (name) VALUES ($1)", .{"Bob"});
            try d.exec("INSERT INTO posts (user_id, title) VALUES ($1, $2)", .{2, "World"});
        }
    }.execute, .{db});
}
```

---

## 数据流与执行模型

### SELECT 查询完整数据流

```
┌────────────────────────────────────────────────────────────────┐
│                    阶段 1: 编译时类型定义                        │
│                                                                  │
│  const User = struct {                                           │
│      id: i64,                                                    │
│      name: []const u8,                                           │
│      email: ?[]const u8,                                         │
│  };                                                              │
│                                                                  │
│  [编译时生成]                                                     │
│  - table_name = "User"                                           │
│  - field_names = ["id", "name", "email"]                         │
│  - field_types = [i64, []const u8, ?[]const u8]                 │
│  - field_count = 3                                               │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│               阶段 2: 编译时查询构建器实例化                      │
│                                                                  │
│  var query = try db.newSelect(User);                             │
│                                                                  │
│  [编译时确定]                                                     │
│  - QueryBuilder 的泛型参数 T = User                              │
│  - 生成 SelectQuery(User, .postgres) 类型                        │
│  - 嵌入 User 的元数据常量                                         │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│              阶段 3: 运行时链式 API 调用                          │
│                                                                  │
│  try query.where("age > ?", .{18})                               │
│            .whereOr("role = ?", .{"admin"})                      │
│            .orderBy("created_at", .desc)                         │
│            .limit(10);                                           │
│                                                                  │
│  [运行时执行]                                                     │
│  - 将 WHERE 条件存储到 ArrayList                                 │
│  - 将 ORDER BY 子句存储到 ArrayList                              │
│  - 记录 LIMIT 值                                                 │
│  - 所有内存分配使用 Arena Allocator                               │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│                  阶段 4: 运行时 SQL 生成                          │
│                                                                  │
│  const sql = try query.buildSQL();                               │
│                                                                  │
│  [运行时组装]                                                     │
│  - 组装字符串: "SELECT id, name, email FROM User                 │
│                WHERE age > $1 OR role = $2                       │
│                ORDER BY created_at DESC LIMIT 10"                │
│                                                                  │
│  [编译时已知]                                                     │
│  - 表名 "User"                                                   │
│  - 列名 ["id", "name", "email"]                                  │
│  - 占位符格式 (PostgreSQL: $1, MySQL: ?)                         │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│                 阶段 5: 运行时数据库执行                          │
│                                                                  │
│  const rows = try db.conn.query(sql, args);                      │
│                                                                  │
│  [运行时执行]                                                     │
│  - 通过网络发送 SQL 到数据库                                      │
│  - 数据库解析并执行 SQL                                           │
│  - 接收结果集                                                     │
│  - 驱动将结果封装为 Rows 迭代器                                   │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│           阶段 6: 运行时结果映射 (使用编译时生成的映射器)          │
│                                                                  │
│  var users: std.ArrayList(User) = .{};  // ✅ Zig 0.15.2        │
│  try query.scan(allocator, &users);                              │
│                                                                  │
│  [编译时生成的映射逻辑]                                            │
│  - scanRow(User, row) 函数已在编译时生成                         │
│  - 字段映射逻辑:                                                  │
│    user.id = row.getInt(i64, 0)                                  │
│    user.name = row.getString(1)                                  │
│    user.email = row.isNull(2) ? null : row.getString(2)          │
│                                                                  │
│  [运行时执行]                                                     │
│  - 遍历 rows 迭代器                                               │
│  - 对每一行调用编译时生成的 scanRow                               │
│  - 填充 User 结构体实例                                           │
│  - 添加到 ArrayList                                               │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│                   阶段 7: 返回类型安全结果                        │
│                                                                  │
│  for (users.items) |user| {                                      │
│      std.debug.print("{s}: {s}\n", .{user.name, user.email});   │
│  }                                                               │
│                                                                  │
│  [类型安全]                                                       │
│  - user.id 是 i64 类型                                           │
│  - user.name 是 []const u8 类型                                  │
│  - user.email 是 ?[]const u8 类型 (可选)                         │
│  - 编译器在编译时检查所有类型                                     │
└────────────────────────────────────────────────────────────────┘
```

---

## 编译期 vs 运行期

### 编译期发生的事情 (comptime)

```zig
// ✅ 编译时: 类型定义
const User = struct {
    id: i64,
    name: []const u8,
    email: ?[]const u8,
};

// ✅ 编译时: 元数据提取
const table_name = comptime getTableName(User); // "User"
const field_names = comptime getFieldNames(User); // ["id", "name", "email"]
const field_count = comptime @typeInfo(User).Struct.fields.len; // 3

// ✅ 编译时: 泛型特化
const PostgresDB = DB(.postgres); // 生成 DB(.postgres) 类型
const UserSelectQuery = SelectQuery(User, .postgres); // 生成专用查询构建器类型

// ✅ 编译时: 字段映射函数生成
fn scanRow(comptime T: type, row: *Row, allocator: Allocator) !T {
    var result: T = undefined;
    // 这个循环在编译时展开,生成固定的字段赋值代码
    inline for (@typeInfo(T).Struct.fields, 0..) |field, i| {
        @field(result, field.name) = try getFieldValue(field.type, row, i, allocator);
    }
    return result;
}
// 编译后等价于:
// result.id = try getFieldValue(i64, row, 0, allocator);
// result.name = try getFieldValue([]const u8, row, 1, allocator);
// result.email = try getFieldValue(?[]const u8, row, 2, allocator);

// ✅ 编译时: 方言特定占位符生成
fn placeholder(comptime dialect: Dialect, index: usize) []const u8 {
    return comptime switch (dialect) {
        .postgres => std.fmt.comptimePrint("${d}", .{index}),
        .mysql, .sqlite => "?",
    };
}
// 对于 .postgres,编译时直接生成 "$1", "$2" 等字符串
```

### 运行期发生的事情 (runtime)

```zig
// ❌ 运行时: 创建查询构建器实例
var query = try db.newSelect(User); // 分配内存,初始化 ArrayList
defer query.deinit();

// ❌ 运行时: 添加查询条件
try query.where("age > ?", .{18}); // 将条件存储到 ArrayList
try query.orderBy("created_at", .desc); // 存储排序子句

// ❌ 运行时: 组装 SQL 字符串
const sql = try query.buildSQL(); // 拼接字符串 "SELECT ... FROM ... WHERE ..."

// ❌ 运行时: 数据库交互
const rows = try db.conn.query(sql, args); // 网络 I/O
defer rows.deinit();

// ❌ 运行时: 遍历结果集
while (try rows.next()) |row| {
    // 但是! 这里调用的是编译时生成的 scanRow 函数
    const user = try scanRow(User, row, allocator);
    try users.append(allocator, user);  // ✅ Zig 0.15.2: 传递 allocator
}
```

### 关键性能优势

**零运行时反射**:
```zig
// ❌ Go GORM (运行时反射)
// 运行时使用反射查找字段名、类型、标签
// 每次查询都要遍历结构体字段
reflect.TypeOf(user).Field(i).Name // 运行时查找

// ✅ ZORM (编译时反射)
// 所有字段信息在编译时已知,直接硬编码到二进制
const field_name = "id"; // 编译时常量
result.id = ...; // 直接赋值,无查找开销
```

**零虚函数调用**:
```zig
// ❌ 传统 OOP 多态 (虚函数表)
// 每次调用需要通过 vtable 查找函数指针
conn.exec(sql) // 运行时查找 exec 函数指针

// ✅ ZORM (编译时多态)
// 泛型特化,编译时已确定具体类型
PostgresConnection.exec(sql) // 直接调用,无虚函数开销
```

---

## 内存管理策略

### 1. Allocator 传递模式

```zig
// 所有需要分配内存的 API 都接受 Allocator 参数
pub fn init(allocator: Allocator, dsn: []const u8) !*DB {
    const db = try allocator.create(DB);
    errdefer allocator.destroy(db);

    db.* = .{
        .allocator = allocator,
        // ...
    };
    return db;
}

pub fn deinit(self: *DB) void {
    // 清理所有分配的资源
    self.allocator.destroy(self);
}
```

### 2. Arena Allocator 用于临时分配

```zig
pub const SelectQuery = struct {
    arena: std.heap.ArenaAllocator,
    base_allocator: Allocator,

    pub fn init(allocator: Allocator, db: *DB) !*SelectQuery {
        const query = try allocator.create(SelectQuery);
        query.* = .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .base_allocator = allocator,
            // ...
        };
        return query;
    }

    pub fn deinit(self: *SelectQuery) void {
        self.arena.deinit(); // 一次性释放所有临时分配
        self.base_allocator.destroy(self);
    }

    pub fn where(self: *SelectQuery, condition: []const u8, args: anytype) !*SelectQuery {
        const allocator = self.arena.allocator(); // 使用 Arena
        const cond = try allocator.dupe(u8, condition);
        // ... 所有临时分配都使用 arena.allocator()
        return self;
    }
};
```

### 3. 结果集内存由调用者管理

```zig
// 调用者创建 ArrayList 并管理其内存
var users: std.ArrayList(User) = .{};  // ✅ Zig 0.15.2: 使用结构体字面量
defer users.deinit(caller_allocator);   // ✅ Zig 0.15.2: 传递 allocator

// ZORM 将结果写入调用者提供的容器
try query.scan(caller_allocator, &users);

// 字符串内存策略
pub const ScanOptions = struct {
    copy_strings: bool = false, // 是否复制字符串
};

// 如果 copy_strings = false,字符串借用 Row 的内存 (更快,但生命周期受限)
// 如果 copy_strings = true,字符串复制到调用者的 allocator (更安全,但更慢)
```

### 4. defer/errdefer 确保资源清理

```zig
pub fn beginTransaction(self: *DB) !Transaction {
    const tx = try self.allocator.create(Transaction);
    errdefer self.allocator.destroy(tx); // 错误时自动清理

    try self.conn.exec("BEGIN", &.{});
    errdefer _ = self.conn.exec("ROLLBACK", &.{}) catch {}; // 错误时自动回滚

    tx.* = .{ .db = self, .active = true };
    return tx.*;
}

// 使用示例
pub fn example(db: *DB) !void {
    var tx = try db.beginTransaction();
    defer tx.rollback() catch {}; // 确保异常时回滚

    try db.exec("INSERT INTO users (name) VALUES ($1)", .{"Alice"});
    // 如果这里发生错误, defer 会自动调用 rollback

    try tx.commit(); // 显式提交
}
```

### 5. 内存泄漏检测

```zig
test "query builder memory safety" {
    // std.testing.allocator 会自动检测内存泄漏
    var db = try DB.init(std.testing.allocator, test_conn);
    defer db.deinit();

    var query = try db.newSelect(User);
    defer query.deinit();

    try query.where("age > ?", .{18});
    const sql = try query.buildSQL();
    _ = sql;

    // 测试结束时,如果有内存泄漏,测试会失败
}
```

---

## 错误处理策略

### 1. 错误集定义

```zig
pub const Error = error{
    // 连接错误
    ConnectionFailed,
    ConnectionClosed,
    ConnectionPoolExhausted,
    ConnectionTimeout,

    // 查询错误
    QueryFailed,
    InvalidSQL,
    InvalidParameter,
    ParameterCountMismatch,

    // 结果错误
    NoRows,
    TooManyRows,
    ColumnNotFound,
    TypeMismatch,
    NullValue,

    // 内存错误
    OutOfMemory,

    // 事务错误
    TransactionAlreadyStarted,
    NoActiveTransaction,
    TransactionRollbackFailed,
    TransactionCommitFailed,

    // 方言错误
    UnsupportedDialect,
    UnsupportedFeature,
};
```

### 2. 错误传播

```zig
// 所有可能失败的函数返回 !T
pub fn query(self: *DB, sql: []const u8, args: []const QueryArg) !Rows {
    return self.conn.exec(sql, args) catch |err| {
        // 可以添加日志或错误上下文
        std.log.err("Query failed: {s}, error: {}", .{sql, err});
        return err; // 继续传播错误
    };
}

// 调用者必须处理错误
const rows = try db.query(sql, args); // 传播错误
// 或者
const rows = db.query(sql, args) catch |err| {
    // 处理特定错误
    return switch (err) {
        error.ConnectionClosed => try db.reconnect(),
        else => err,
    };
};
```

### 3. 错误恢复

```zig
// 将错误转换为可选值
pub fn scanOneOptional(self: *SelectQuery) !?T {
    return self.scanOne() catch |err| switch (err) {
        error.NoRows => return null, // 转换为 null
        else => return err, // 其他错误继续传播
    };
}

// 使用示例
const user = try query.scanOneOptional();
if (user) |u| {
    std.debug.print("Found: {s}\n", .{u.name});
} else {
    std.debug.print("Not found\n", .{});
}
```

### 4. 错误上下文

```zig
// 为错误添加上下文信息
pub const QueryError = struct {
    err: Error,
    sql: []const u8,
    args: []const QueryArg,

    pub fn format(
        self: QueryError,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("Query error: {}\nSQL: {s}\nArgs: {any}", .{
            self.err, self.sql, self.args
        });
    }
};

pub fn queryWithContext(self: *DB, sql: []const u8, args: []const QueryArg) !Rows {
    return self.conn.query(sql, args) catch |err| {
        const ctx = QueryError{
            .err = err,
            .sql = sql,
            .args = args,
        };
        std.log.err("{}", .{ctx});
        return err;
    };
}
```

---

## 性能优化策略

### 1. 零运行时反射

```zig
// ✅ 所有类型信息在编译时提取
const field_names = comptime getFieldNames(User);
const field_types = comptime getFieldTypes(User);

// 字段访问直接硬编码,无运行时查找
inline for (@typeInfo(T).Struct.fields) |field| {
    @field(result, field.name) = value; // 编译时展开为直接赋值
}
```

### 2. 内联热路径函数

```zig
// 强制内联关键函数
inline fn setField(
    comptime T: type,
    ptr: *T,
    comptime field_name: []const u8,
    value: anytype
) void {
    @field(ptr, field_name) = value;
}

// 编译时循环展开
inline for (fields, 0..) |field, i| {
    setField(T, &result, field.name, values[i]);
}
// 编译后等价于:
// result.id = values[0];
// result.name = values[1];
// result.email = values[2];
```

### 3. Comptime 预计算

```zig
// 编译时预计算所有可以计算的值
const placeholder_prefix = comptime switch (dialect) {
    .postgres => "$",
    .mysql, .sqlite => "?",
};

// 编译时生成占位符数组
const placeholders = comptime blk: {
    var result: [max_params][]const u8 = undefined;
    for (&result, 1..) |*item, i| {
        item.* = std.fmt.comptimePrint("{s}{d}", .{placeholder_prefix, i});
    }
    break :blk result;
};
// 运行时直接使用: placeholders[0] // "$1"
```

### 4. 批量操作优化

```zig
// 批量插入优化为单个 SQL 语句
pub fn insertMany(self: *InsertQuery, values: []const T) !void {
    const allocator = self.arena.allocator();
    var sql: std.ArrayList(u8) = .{};  // ✅ Zig 0.15.2: 使用结构体字面量
    const writer = sql.writer(allocator);  // ✅ Zig 0.15.2: 传递 allocator

    try writer.print("INSERT INTO {s} ({s}) VALUES ", .{
        table_name,
        field_names_joined,
    });

    for (values, 0..) |_, i| {
        if (i > 0) try writer.writeAll(", ");
        try writer.writeAll("(");
        for (0..field_count) |j| {
            if (j > 0) try writer.writeAll(", ");
            try writer.writeAll(placeholder(dialect, i * field_count + j + 1));
        }
        try writer.writeAll(")");
    }

    // 生成: INSERT INTO users (id, name) VALUES ($1, $2), ($3, $4), ($5, $6)
    // 而不是 3 个单独的 INSERT 语句
}
```

### 5. Arena Allocator 减少分配次数

```zig
// 查询构建过程中所有临时分配使用 Arena
pub fn where(self: *SelectQuery, condition: []const u8, args: anytype) !*SelectQuery {
    const allocator = self.arena.allocator();

    // 所有临时字符串复制都使用 arena
    const cond_copy = try allocator.dupe(u8, condition);
    const args_copy = try allocArgs(allocator, args);

    try self.where_clauses.append(self.base_allocator, .{  // ✅ Zig 0.15.2: 传递 allocator
        .condition = cond_copy,
        .args = args_copy,
    });

    return self;
}

// 查询结束后,一次性释放所有临时分配
pub fn deinit(self: *SelectQuery) void {
    self.arena.deinit(); // O(1) 释放,而不是逐个 free
}
```

### 6. 字符串复用

```zig
// 编译时已知的字符串存储为常量,不分配内存
const table_name = comptime getTableName(User); // 编译时常量

// SQL 关键字也是常量
const SELECT = "SELECT";
const FROM = " FROM ";
const WHERE = " WHERE ";

// 构建 SQL 时直接引用常量
try writer.writeAll(SELECT);
try writer.writeAll(table_name); // 不需要复制
try writer.writeAll(FROM);
```

### 7. 性能基准测试

```zig
test "benchmark: simple select" {
    const iterations = 10_000;

    var timer = try std.time.Timer.start();
    for (0..iterations) |_| {
        var query = try db.newSelect(User);
        defer query.deinit();

        try query.where("id = ?", .{1});
        const sql = try query.buildSQL();
        _ = sql;
    }
    const elapsed = timer.read();

    const avg_ns = elapsed / iterations;
    std.debug.print("Average time per query: {} ns\n", .{avg_ns});

    // 目标: <500ns 每次查询构建 (不包括数据库执行)
}

test "benchmark: batch insert" {
    const batch_size = 1000;
    var users: [batch_size]User = undefined;
    for (&users, 0..) |*user, i| {
        user.* = .{
            .id = @intCast(i),
            .name = "User",
            .email = "user@example.com",
        };
    }

    var timer = try std.time.Timer.start();
    var query = try db.newInsert(User);
    defer query.deinit();

    try query.values(&users);
    const sql = try query.buildSQL();
    _ = sql;

    const elapsed = timer.read();
    std.debug.print("Time to build batch insert: {} ms\n", .{elapsed / 1_000_000});

    // 目标: <5ms 构建 1000 行的 INSERT
}
```

---

## 方言系统设计

### 1. 方言枚举和特性检测

```zig
/// 支持的数据库方言
pub const Dialect = enum {
    postgres,
    mysql,
    sqlite,

    /// 编译时特性检测
    pub fn supportsReturning(comptime dialect: Dialect) bool {
        return comptime switch (dialect) {
            .postgres, .sqlite => true,
            .mysql => false,
        };
    }

    pub fn supportsOnConflict(comptime dialect: Dialect) bool {
        return comptime switch (dialect) {
            .postgres, .sqlite => true,
            .mysql => false,
        };
    }

    pub fn supportsCTE(comptime dialect: Dialect) bool {
        return comptime switch (dialect) {
            .postgres, .mysql, .sqlite => true,
        };
    }

    pub fn supportsJSONB(comptime dialect: Dialect) bool {
        return comptime switch (dialect) {
            .postgres => true,
            .mysql, .sqlite => false,
        };
    }

    /// 获取占位符格式
    pub fn placeholder(comptime dialect: Dialect, index: usize) []const u8 {
        return comptime switch (dialect) {
            .postgres => std.fmt.comptimePrint("${d}", .{index}),
            .mysql, .sqlite => "?",
        };
    }

    /// 获取标识符引号
    pub fn quoteIdentifier(comptime dialect: Dialect, identifier: []const u8) []const u8 {
        return comptime switch (dialect) {
            .postgres => std.fmt.comptimePrint("\"{s}\"", .{identifier}),
            .mysql => std.fmt.comptimePrint("`{s}`", .{identifier}),
            .sqlite => std.fmt.comptimePrint("\"{s}\"", .{identifier}),
        };
    }
};
```

### 2. 泛型 DB 和查询构建器

```zig
/// 数据库实例 (编译时特化为特定方言)
pub fn DB(comptime dialect: Dialect) type {
    return struct {
        const Self = @This();
        const Conn = Connection(driverForDialect(dialect));

        allocator: Allocator,
        conn: Conn,
        options: DBOptions,

        pub fn init(allocator: Allocator, conn: Conn, options: DBOptions) !*Self {
            const db = try allocator.create(Self);
            db.* = .{
                .allocator = allocator,
                .conn = conn,
                .options = options,
            };
            return db;
        }

        pub fn newSelect(self: *Self, comptime T: type) !*SelectQuery(T, dialect) {
            return SelectQuery(T, dialect).init(self.allocator, self);
        }

        pub fn newInsert(self: *Self, comptime T: type) !*InsertQuery(T, dialect) {
            return InsertQuery(T, dialect).init(self.allocator, self);
        }

        pub fn deinit(self: *Self) void {
            self.allocator.destroy(self);
        }
    };
}

/// 根据方言选择驱动类型
fn driverForDialect(comptime dialect: Dialect) type {
    return switch (dialect) {
        .postgres => PostgresDriver,
        .mysql => MySQLDriver,
        .sqlite => SQLiteDriver,
    };
}
```

### 3. 方言特定特性使用

```zig
pub fn InsertQuery(comptime T: type, comptime dialect: Dialect) type {
    return struct {
        const Self = @This();

        returning_columns: ?[]const []const u8,

        /// RETURNING 子句 (仅 PostgreSQL 和 SQLite 支持)
        pub fn returning(self: *Self, columns: []const []const u8) !*Self {
            if (comptime !Dialect.supportsReturning(dialect)) {
                @compileError("RETURNING is not supported by " ++ @tagName(dialect));
            }

            self.returning_columns = columns;
            return self;
        }

        /// ON CONFLICT 子句 (仅 PostgreSQL 和 SQLite 支持)
        pub fn onConflict(self: *Self, columns: []const []const u8, action: ConflictAction) !*Self {
            if (comptime !Dialect.supportsOnConflict(dialect)) {
                @compileError("ON CONFLICT is not supported by " ++ @tagName(dialect));
            }

            // ... 实现逻辑
            _ = columns;
            _ = action;
            return self;
        }

        /// ON DUPLICATE KEY UPDATE (仅 MySQL 支持)
        pub fn onDuplicateKeyUpdate(self: *Self, updates: anytype) !*Self {
            if (comptime dialect != .mysql) {
                @compileError("ON DUPLICATE KEY UPDATE is MySQL-specific");
            }

            // ... 实现逻辑
            _ = updates;
            return self;
        }

        pub fn buildSQL(self: *Self) ![]const u8 {
            const allocator = self.arena.allocator();
            var sql: std.ArrayList(u8) = .{};  // ✅ Zig 0.15.2: 使用结构体字面量
            const writer = sql.writer(allocator);  // ✅ Zig 0.15.2: 传递 allocator

            try writer.print("INSERT INTO {s} (...) VALUES (...)", .{table_name});

            // 根据方言添加特定子句
            if (self.returning_columns) |cols| {
                if (comptime Dialect.supportsReturning(dialect)) {
                    try writer.writeAll(" RETURNING ");
                    for (cols, 0..) |col, i| {
                        if (i > 0) try writer.writeAll(", ");
                        try writer.writeAll(col);
                    }
                }
            }

            return sql.toOwnedSlice(allocator);  // ✅ Zig 0.15.2: 传递 allocator
        }
    };
}
```

### 4. 使用示例

```zig
// 编译时选择方言
const PostgresDB = DB(.postgres);
const MySQLDB = DB(.mysql);
const SQLiteDB = DB(.sqlite);

// PostgreSQL 示例
var pg_db = try PostgresDB.init(allocator, pg_conn, .{});
defer pg_db.deinit();

var pg_query = try pg_db.newInsert(User);
defer pg_query.deinit();

try pg_query.value(.{ .name = "Alice", .email = "alice@example.com" })
             .returning(&.{"id"}); // ✅ PostgreSQL 支持 RETURNING

// MySQL 示例
var mysql_db = try MySQLDB.init(allocator, mysql_conn, .{});
defer mysql_db.deinit();

var mysql_query = try mysql_db.newInsert(User);
defer mysql_query.deinit();

try mysql_query.value(.{ .name = "Bob", .email = "bob@example.com" })
               .onDuplicateKeyUpdate(.{ .email = "bob@example.com" }); // ✅ MySQL 支持

// ❌ 编译错误示例
// try mysql_query.returning(&.{"id"}); // 编译错误: RETURNING is not supported by mysql
```

---

## 接口定义

### 1. 核心类型

```zig
// src/types.zig

/// 查询参数类型
pub const QueryArg = union(enum) {
    int: i64,
    uint: u64,
    float: f64,
    bool: bool,
    string: []const u8,
    bytes: []const u8,
    null_val: void,

    pub fn fromValue(value: anytype) QueryArg {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        return switch (type_info) {
            .Int => |int_info| {
                if (int_info.signedness == .signed) {
                    return .{ .int = @intCast(value) };
                } else {
                    return .{ .uint = @intCast(value) };
                }
            },
            .Float => .{ .float = @floatCast(value) },
            .Bool => .{ .bool = value },
            .Pointer => |ptr_info| {
                if (ptr_info.size == .Slice and ptr_info.child == u8) {
                    return .{ .string = value };
                }
                @compileError("Unsupported pointer type");
            },
            .Null => .{ .null_val = {} },
            .Optional => {
                if (value) |v| {
                    return fromValue(v);
                } else {
                    return .{ .null_val = {} };
                }
            },
            else => @compileError("Unsupported type: " ++ @typeName(T)),
        };
    }
};

/// WHERE 子句
pub const WhereClause = struct {
    condition: []const u8,
    args: []const QueryArg,
    operator: WhereOperator,
};

pub const WhereOperator = enum {
    and_op,
    or_op,
};

/// JOIN 子句
pub const JoinClause = struct {
    join_type: JoinType,
    table: []const u8,
    condition: []const u8,
};

pub const JoinType = enum {
    inner,
    left,
    right,
    full,
    cross,
};

/// ORDER BY 子句
pub const OrderByClause = struct {
    column: []const u8,
    direction: OrderDirection,
};

pub const OrderDirection = enum {
    asc,
    desc,
};

/// HAVING 子句
pub const HavingClause = struct {
    condition: []const u8,
    args: []const QueryArg,
};

/// 列类型
pub const ColumnType = enum {
    integer,
    bigint,
    smallint,
    boolean,
    text,
    varchar,
    char,
    real,
    double_precision,
    numeric,
    date,
    time,
    timestamp,
    timestamptz,
    json,
    jsonb,
    uuid,
    bytea,
};
```

### 2. DB 配置

```zig
// src/core/db.zig

pub const DBOptions = struct {
    /// 忽略结果中的未知列
    discard_unknown_columns: bool = false,

    /// 最大连接数
    max_open_conns: u32 = 25,

    /// 最大空闲连接数
    max_idle_conns: u32 = 25,

    /// 连接最大生命周期 (秒)
    conn_max_lifetime: u64 = 300,

    /// 查询超时 (毫秒)
    query_timeout: u64 = 30_000,

    /// 启用查询日志
    enable_query_log: bool = false,

    /// 启用慢查询日志
    enable_slow_query_log: bool = false,

    /// 慢查询阈值 (毫秒)
    slow_query_threshold: u64 = 1000,
};

pub const DBStats = struct {
    /// 总查询数
    total_queries: std.atomic.Value(u64),

    /// 总错误数
    total_errors: std.atomic.Value(u64),

    /// 当前打开的连接数
    open_connections: std.atomic.Value(u32),

    /// 当前空闲的连接数
    idle_connections: std.atomic.Value(u32),
};
```

### 3. 查询钩子

```zig
// src/core/hooks.zig

/// 查询钩子接口
pub const QueryHook = struct {
    const Self = @This();

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        beforeQuery: *const fn (*anyopaque, []const u8, []const QueryArg) anyerror!void,
        afterQuery: *const fn (*anyopaque, []const u8, []const QueryArg, u64) anyerror!void,
        onError: *const fn (*anyopaque, []const u8, []const QueryArg, anyerror) anyerror!void,
    };

    pub fn beforeQuery(self: Self, sql: []const u8, args: []const QueryArg) !void {
        try self.vtable.beforeQuery(self.ptr, sql, args);
    }

    pub fn afterQuery(self: Self, sql: []const u8, args: []const QueryArg, duration_ns: u64) !void {
        try self.vtable.afterQuery(self.ptr, sql, args, duration_ns);
    }

    pub fn onError(self: Self, sql: []const u8, args: []const QueryArg, err: anyerror) !void {
        try self.vtable.onError(self.ptr, sql, args, err);
    }
};

/// 日志钩子示例
pub const LoggingHook = struct {
    pub fn init() QueryHook {
        const vtable = comptime &QueryHook.VTable{
            .beforeQuery = beforeQuery,
            .afterQuery = afterQuery,
            .onError = onError,
        };

        return .{
            .ptr = undefined,
            .vtable = vtable,
        };
    }

    fn beforeQuery(_: *anyopaque, sql: []const u8, args: []const QueryArg) !void {
        std.log.info("Executing query: {s}, args: {any}", .{ sql, args });
    }

    fn afterQuery(_: *anyopaque, sql: []const u8, _: []const QueryArg, duration_ns: u64) !void {
        std.log.info("Query completed: {s}, duration: {} ms", .{ sql, duration_ns / 1_000_000 });
    }

    fn onError(_: *anyopaque, sql: []const u8, _: []const QueryArg, err: anyerror) !void {
        std.log.err("Query failed: {s}, error: {}", .{ sql, err });
    }
};
```

---

## 目录结构

```
zorm/
├── build.zig                 # 构建配置
├── build.zig.zon             # 包元数据
├── README.md                 # 项目说明
├── LICENSE                   # 许可证
├── .gitignore
│
├── src/
│   ├── zorm.zig              # 主入口,导出所有公共 API
│   │
│   ├── error.zig             # 错误定义
│   ├── types.zig             # 基础类型 (QueryArg, WhereClause 等)
│   ├── allocator.zig         # Allocator 工具函数
│   │
│   ├── core/
│   │   ├── db.zig            # DB 实例管理
│   │   ├── transaction.zig   # 事务管理
│   │   └── hooks.zig         # 查询钩子系统
│   │
│   ├── driver/
│   │   ├── connection.zig    # Connection 接口
│   │   ├── postgres.zig      # PostgreSQL 驱动
│   │   ├── mysql.zig         # MySQL 驱动
│   │   ├── sqlite.zig        # SQLite 驱动
│   │   └── pool.zig          # 连接池
│   │
│   ├── dialect/
│   │   ├── dialect.zig       # Dialect 枚举和特性检测
│   │   └── sql.zig           # SQL 生成工具 (占位符、引号等)
│   │
│   ├── query/
│   │   ├── select.zig        # SelectQuery
│   │   ├── insert.zig        # InsertQuery
│   │   ├── update.zig        # UpdateQuery
│   │   ├── delete.zig        # DeleteQuery
│   │   └── builder_base.zig  # 查询构建器基础功能
│   │
│   ├── mapper/
│   │   ├── type_info.zig     # comptime 类型反射工具
│   │   ├── field_mapper.zig  # 字段映射逻辑
│   │   └── result_scanner.zig # 结果扫描
│   │
│   └── schema/
│       ├── table.zig         # CREATE TABLE
│       ├── index.zig         # CREATE INDEX
│       └── migration.zig     # 迁移系统
│
├── tests/
│   ├── unit/                 # 单元测试
│   │   ├── query_test.zig
│   │   ├── mapper_test.zig
│   │   └── dialect_test.zig
│   │
│   ├── integration/          # 集成测试
│   │   ├── postgres_test.zig
│   │   ├── mysql_test.zig
│   │   └── sqlite_test.zig
│   │
│   └── benchmark/            # 性能基准测试
│       ├── select_bench.zig
│       ├── insert_bench.zig
│       └── batch_bench.zig
│
├── examples/
│   ├── basic.zig             # 基础使用示例
│   ├── transactions.zig      # 事务示例
│   ├── relations.zig         # 关系映射示例
│   └── migrations.zig        # 迁移示例
│
└── docs/
    ├── prd.md                # 产品需求文档
    ├── architecture.md       # 本文档
    ├── api-reference.md      # API 参考
    ├── user-guide.md         # 使用指南
    └── best-practices.md     # 最佳实践
```

---

## 构建系统

### build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ========== 主模块 ==========
    const zorm_module = b.addModule("zorm", .{
        .root_source_file = b.path("src/zorm.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ========== 可选的数据库驱动 ==========
    const enable_postgres = b.option(bool, "postgres", "Enable PostgreSQL support") orelse true;
    const enable_mysql = b.option(bool, "mysql", "Enable MySQL support") orelse false;
    const enable_sqlite = b.option(bool, "sqlite", "Enable SQLite support") orelse false;

    if (enable_postgres) {
        zorm_module.linkSystemLibrary("pq", .{});
    }
    if (enable_mysql) {
        zorm_module.linkSystemLibrary("mysqlclient", .{});
    }
    if (enable_sqlite) {
        zorm_module.linkSystemLibrary("sqlite3", .{});
    }

    // ========== 静态库 ==========
    const lib = b.addStaticLibrary(.{
        .name = "zorm",
        .root_source_file = b.path("src/zorm.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (enable_postgres) lib.linkSystemLibrary("pq");
    if (enable_mysql) lib.linkSystemLibrary("mysqlclient");
    if (enable_sqlite) lib.linkSystemLibrary("sqlite3");

    b.installArtifact(lib);

    // ========== 单元测试 ==========
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("tests/unit/all_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addImport("zorm", zorm_module);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // ========== 集成测试 ==========
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("tests/integration/all_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_tests.root_module.addImport("zorm", zorm_module);
    if (enable_postgres) integration_tests.linkSystemLibrary("pq");
    if (enable_mysql) integration_tests.linkSystemLibrary("mysqlclient");
    if (enable_sqlite) integration_tests.linkSystemLibrary("sqlite3");

    const run_integration_tests = b.addRunArtifact(integration_tests);
    const integration_test_step = b.step("test-integration", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);

    // ========== 示例程序 ==========
    const examples = [_][]const u8{ "basic", "transactions", "relations", "migrations" };
    inline for (examples) |example_name| {
        const example = b.addExecutable(.{
            .name = example_name,
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example_name})),
            .target = target,
            .optimize = optimize,
        });
        example.root_module.addImport("zorm", zorm_module);
        if (enable_postgres) example.linkSystemLibrary("pq");
        if (enable_mysql) example.linkSystemLibrary("mysqlclient");
        if (enable_sqlite) example.linkSystemLibrary("sqlite3");

        const install_example = b.addInstallArtifact(example, .{});
        const example_step = b.step(
            b.fmt("example-{s}", .{example_name}),
            b.fmt("Build {s} example", .{example_name}),
        );
        example_step.dependOn(&install_example.step);

        const run_example = b.addRunArtifact(example);
        const run_example_step = b.step(
            b.fmt("run-{s}", .{example_name}),
            b.fmt("Run {s} example", .{example_name}),
        );
        run_example_step.dependOn(&run_example.step);
    }

    // ========== 文档生成 ==========
    const docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs/api",
    });
    const docs_step = b.step("docs", "Generate API documentation");
    docs_step.dependOn(&docs.step);

    // ========== 代码格式化 ==========
    const fmt_step = b.step("fmt", "Format source code");
    fmt_step.dependOn(&b.addFmt(.{
        .paths = &.{ "src", "tests", "examples" },
    }).step);
}
```

---

## 附录: 完整使用示例

```zig
const std = @import("std");
const zorm = @import("zorm");

// 1. 定义模型
const User = struct {
    id: i64,
    name: []const u8,
    email: ?[]const u8,
    age: u32,
    created_at: i64,

    pub const table_name = "users";
};

const Post = struct {
    id: i64,
    user_id: i64,
    title: []const u8,
    content: []const u8,
    published: bool,

    pub const table_name = "posts";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 2. 连接数据库 (编译时选择方言)
    const dsn = "postgresql://user:pass@localhost:5432/mydb";
    var conn = try zorm.driver.postgres.connect(allocator, dsn);
    defer conn.close() catch {};

    var db = try zorm.DB(.postgres).init(allocator, conn, .{});
    defer db.deinit();

    // 3. SELECT 查询
    std.debug.print("=== SELECT Query ===\n", .{});
    {
        var query = try db.newSelect(User);
        defer query.deinit();

        try query.column("id")
                 .column("name")
                 .column("email")
                 .where("age > ?", .{18})
                 .whereOr("role = ?", .{"admin"})
                 .orderBy("created_at", .desc)
                 .limit(10);

        const sql = try query.buildSQL();
        std.debug.print("SQL: {s}\n", .{sql});

        var users: std.ArrayList(User) = .{};  // ✅ Zig 0.15.2: 使用结构体字面量
        defer users.deinit(allocator);         // ✅ Zig 0.15.2: 传递 allocator

        try query.scan(allocator, &users);

        for (users.items) |user| {
            std.debug.print("User: id={}, name={s}, email={s}\n", .{
                user.id,
                user.name,
                user.email orelse "NULL",
            });
        }
    }

    // 4. INSERT 查询
    std.debug.print("\n=== INSERT Query ===\n", .{});
    {
        var query = try db.newInsert(User);
        defer query.deinit();

        try query.value(.{
            .name = "Alice",
            .email = "alice@example.com",
            .age = 25,
            .created_at = std.time.timestamp(),
        });

        // PostgreSQL 特定: RETURNING 子句
        try query.returning(&.{"id", "created_at"});

        const sql = try query.buildSQL();
        std.debug.print("SQL: {s}\n", .{sql});

        const result = try query.exec();
        std.debug.print("Inserted user with ID: {}\n", .{result.last_insert_id});
    }

    // 5. UPDATE 查询
    std.debug.print("\n=== UPDATE Query ===\n", .{});
    {
        var query = try db.newUpdate(User);
        defer query.deinit();

        try query.set("email", "newemail@example.com")
                 .where("id = ?", .{1});

        const sql = try query.buildSQL();
        std.debug.print("SQL: {s}\n", .{sql});

        const result = try query.exec();
        std.debug.print("Updated {} rows\n", .{result.rows_affected});
    }

    // 6. DELETE 查询
    std.debug.print("\n=== DELETE Query ===\n", .{});
    {
        var query = try db.newDelete(User);
        defer query.deinit();

        try query.where("age < ?", .{18})
                 .where("email IS NULL", .{});

        const sql = try query.buildSQL();
        std.debug.print("SQL: {s}\n", .{sql});

        const result = try query.exec();
        std.debug.print("Deleted {} rows\n", .{result.rows_affected});
    }

    // 7. 事务
    std.debug.print("\n=== Transaction ===\n", .{});
    {
        var tx = try zorm.Transaction(.postgres).begin(db);
        defer tx.rollback() catch {};

        // 插入用户
        var insert_user = try db.newInsert(User);
        defer insert_user.deinit();
        try insert_user.value(.{
            .name = "Bob",
            .email = "bob@example.com",
            .age = 30,
            .created_at = std.time.timestamp(),
        });
        const user_result = try insert_user.exec();

        // 插入文章
        var insert_post = try db.newInsert(Post);
        defer insert_post.deinit();
        try insert_post.value(.{
            .user_id = user_result.last_insert_id,
            .title = "My First Post",
            .content = "Hello, World!",
            .published = true,
        });
        _ = try insert_post.exec();

        // 提交事务
        try tx.commit();
        std.debug.print("Transaction committed successfully\n", .{});
    }

    // 8. JOIN 查询
    std.debug.print("\n=== JOIN Query ===\n", .{});
    {
        var query = try db.newSelect(User);
        defer query.deinit();

        try query.column("u.id")
                 .column("u.name")
                 .column("p.title")
                 .column("p.published")
                 .innerJoin("posts p", "p.user_id = u.id")
                 .where("p.published = ?", .{true})
                 .orderBy("p.created_at", .desc);

        const sql = try query.buildSQL();
        std.debug.print("SQL: {s}\n", .{sql});
    }

    std.debug.print("\n=== All examples completed ===\n", .{});
}
```

---

## 总结

本架构设计文档定义了 ZORM 的完整技术架构,核心要点如下:

1. **Comptime-First**: 所有类型信息在编译时提取,实现零运行时反射开销
2. **泛型多态**: 使用编译时泛型特化,避免虚函数表和动态分发
3. **显式内存管理**: Allocator 模式 + Arena Allocator + defer/errdefer
4. **强制错误处理**: 所有可能失败的操作返回 `!T`,编译器强制处理
5. **方言系统**: 编译时选择数据库方言,方言特定特性在编译时检查
6. **类型安全**: 查询结果自动映射到强类型结构体,编译时保证正确性
7. **性能优先**: 内联热路径、comptime 预计算、批量优化,目标 <5% 开销

下一步: 基于本架构文档,开发团队可以开始实现 Epic 1 的 Story,建立项目基础设施和核心 DB 管理功能。

---

**文档结束**
