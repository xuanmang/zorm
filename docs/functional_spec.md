# ZORM 功能需求规格说明书
## 基于 Bun ORM 功能对等实现 (Zig 语言版)

**版本**: v2.0
**日期**: 2025-10-16
**作者**: Mary (Business Analyst)
**项目**: ZORM - SQL-first Zig ORM
**目标语言**: Zig 0.15.2+

---

## 文档概述

本文档详细定义了 ZORM (参照 Bun ORM，使用 Zig 语言实现) 需要实现的全部功能需求。每个功能点明确了其核心行为、API 接口以及所有相关的配置选项。本规格说明书基于对 Bun ORM 源代码和官方文档的全面分析，并适配 Zig 语言的特性和惯例构建。

### 目标读者
- 架构师和技术负责人
- Zig 语言工程师
- 数据库工程师
- QA 测试工程师

### Zig 语言关键特性
- **显式内存管理** - 使用 Allocator 模式，无垃圾回收
- **编译时计算** - `comptime` 关键字支持泛型和元编程
- **强制错误处理** - 错误联合类型 `!T`，必须处理或传播
- **零开销抽象** - 接近 C 的性能，无运行时开销
- **跨平台** - 支持交叉编译，单一工具链

### 文档结构
本文档按以下维度组织功能需求:
1. **核心架构** - DB 实例、连接管理、方言系统
2. **查询构建器** - SELECT/INSERT/UPDATE/DELETE 等 DML
3. **Schema 管理** - 模型定义、表关系、迁移
4. **高级特性** - 事务、钩子、批量操作
5. **可观测性** - 日志、追踪、性能监控
6. **数据库支持** - 多数据库方言适配

---

## 第一部分: 功能对等矩阵

### 1.1 核心功能矩阵

| 功能类别 | Bun ORM 功能 | ZORM 实现优先级 | 复杂度 | Zig 特有考虑 |
|---------|-------------|----------------|--------|-------------|
| **核心DB** | DB 实例管理 | P0 - 必需 | 中 | Allocator 传递 |
| | 连接池配置 | P0 - 必需 | 低 | 使用 std.heap |
| | 方言系统 | P0 - 必需 | 高 | comptime dispatch |
| | 命名参数绑定 | P1 - 重要 | 中 | HashMap 管理 |
| | 查询钩子系统 | P1 - 重要 | 中 | 函数指针 |
| | 连接解析器 | P2 - 可选 | 高 | 接口模式 |
| **查询构建** | SELECT 查询 | P0 - 必需 | 高 | 链式 API |
| | INSERT 查询 | P0 - 必需 | 中 | 批量优化 |
| | UPDATE 查询 | P0 - 必需 | 中 | 批量更新 |
| | DELETE 查询 | P0 - 必需 | 中 | 软删除支持 |
| | Raw SQL 查询 | P0 - 必需 | 低 | 直接传递 |
| | CTE (WITH) 子句 | P1 - 重要 | 高 | 递归 CTE |
| | 子查询支持 | P1 - 重要 | 高 | 嵌套构建器 |
| | JOIN 操作 | P0 - 必需 | 高 | 多表关联 |
| | UNION 操作 | P1 - 重要 | 中 | 结果合并 |
| **Schema** | 模型定义 | P0 - 必需 | 中 | comptime 反射 |
| | 表定义 | P0 - 必需 | 高 | struct 元数据 |
| | 关系映射 | P1 - 重要 | 高 | comptime 关联 |
| | 类型映射 | P0 - 必需 | 中 | SQL<->Zig 类型 |
| | 迁移系统 | P1 - 重要 | 高 | 版本管理 |
| **内存管理** | Allocator 集成 | P0 - 必需 | 高 | 显式传递 |
| | Arena 分配器 | P1 - 重要 | 中 | 临时分配 |
| | 内存泄漏检测 | P1 - 重要 | 低 | test allocator |
| **错误处理** | 错误联合类型 | P0 - 必需 | 低 | `!T` 语法 |
| | 自定义错误集 | P1 - 重要 | 中 | error enum |
| | 错误追踪 | P2 - 可选 | 中 | stack trace |

### 1.2 数据库方言支持矩阵

| 数据库 | Bun 支持 | ZORM 优先级 | Zig 实现考虑 |
|-------|---------|------------|-------------|
| PostgreSQL | ✅ | P0 - 必需 | pq.zig  |

### 1.3 Zig 特性利用矩阵

| Zig 特性 | ZORM 应用场景 | 优势 |
|---------|-------------|------|
| comptime | 泛型查询构建、类型反射 | 零运行时开销 |
| Allocator | 内存管理、连接池 | 显式控制 |
| 错误联合 | 查询错误处理 | 编译时强制 |
| defer | 资源清理、事务回滚 | 自动管理 |
| inline | 热路径优化 | 性能优化 |
| @TypeOf | 动态类型推断 | 类型安全 |
| @fieldParentPtr | 结构体偏移计算 | 零成本抽象 |

---

## 第二部分: 详细功能需求（Zig 实现）

### 2.1 核心架构

#### 2.1.1 DB 实例管理

**功能描述**
DB 是 ZORM 的核心类型，封装数据库连接并提供类型安全的查询构建能力。

**核心行为**
- 显式 Allocator 管理所有内存分配
- 支持多数据库方言切换（comptime）
- 提供查询构建器工厂方法
- 管理连接生命周期
- 支持克隆和派生实例

**API 接口**

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

/// DB 实例配置选项
pub const DBOptions = struct {
    /// 是否丢弃未知列（默认 false）
    discard_unknown_columns: bool = false,
    /// 连接解析器（用于读写分离）
    conn_resolver: ?*ConnResolver = null,
    /// 最大打开连接数
    max_open_conns: u32 = 25,
    /// 最大空闲连接数
    max_idle_conns: u32 = 25,
    /// 连接最大生命周期（秒）
    conn_max_lifetime: u64 = 300,
};

/// DB 统计信息
pub const DBStats = struct {
    queries: u32,
    errors: u32,
};

/// 数据库实例
pub const DB = struct {
    allocator: Allocator,
    conn: *anyopaque, // 实际数据库连接
    dialect: Dialect,
    options: DBOptions,
    query_hooks: std.ArrayList(*QueryHook),
    stats: std.atomic.Value(DBStats),

    /// 创建新的 DB 实例
    pub fn init(
        allocator: Allocator,
        conn: anytype,
        dialect: Dialect,
        options: DBOptions,
    ) !*DB {
        const self = try allocator.create(DB);
        self.* = .{
            .allocator = allocator,
            .conn = @ptrCast(conn),
            .dialect = dialect,
            .options = options,
            .query_hooks = std.ArrayList(*QueryHook).init(allocator),
            .stats = std.atomic.Value(DBStats).init(.{ .queries = 0, .errors = 0 }),
        };
        return self;
    }

    /// 释放 DB 实例
    pub fn deinit(self: *DB) void {
        self.query_hooks.deinit();
        self.allocator.destroy(self);
    }

    /// 关闭数据库连接
    pub fn close(self: *DB) !void {
        // 关闭底层连接
        // 实现依赖于具体的数据库驱动
    }

    /// 获取统计信息
    pub fn getStats(self: *const DB) DBStats {
        return self.stats.load(.monotonic);
    }

    /// 查询构建器工厂方法
    pub fn newSelect(self: *DB, comptime T: type) !*SelectQuery(T) {
        return SelectQuery(T).init(self.allocator, self);
    }

    pub fn newInsert(self: *DB, comptime T: type) !*InsertQuery(T) {
        return InsertQuery(T).init(self.allocator, self);
    }

    pub fn newUpdate(self: *DB, comptime T: type) !*UpdateQuery(T) {
        return UpdateQuery(T).init(self.allocator, self);
    }

    pub fn newDelete(self: *DB, comptime T: type) !*DeleteQuery(T) {
        return DeleteQuery(T).init(self.allocator, self);
    }

    pub fn newRaw(self: *DB, query: []const u8, args: anytype) !*RawQuery {
        return RawQuery.init(self.allocator, self, query, args);
    }

    /// DDL 构建器工厂
    pub fn newCreateTable(self: *DB, comptime T: type) !*CreateTableQuery(T) {
        return CreateTableQuery(T).init(self.allocator, self);
    }

    pub fn newDropTable(self: *DB, comptime T: type) !*DropTableQuery(T) {
        return DropTableQuery(T).init(self.allocator, self);
    }

    pub fn newCreateIndex(self: *DB, comptime T: type) !*CreateIndexQuery(T) {
        return CreateIndexQuery(T).init(self.allocator, self);
    }

    pub fn newDropIndex(self: *DB, comptime T: type) !*DropIndexQuery(T) {
        return DropIndexQuery(T).init(self.allocator, self);
    }

    /// 扫描行
    pub fn scanRows(
        self: *DB,
        comptime T: type,
        rows: *Rows,
        dest: *std.ArrayList(T),
    ) !void {
        // 实现行扫描逻辑
    }

    /// 添加查询钩子
    pub fn withQueryHook(self: *DB, hook: *QueryHook) !*DB {
        const cloned = try self.clone();
        try cloned.query_hooks.append(hook);
        return cloned;
    }

    /// 克隆 DB 实例（浅拷贝，共享连接）
    pub fn clone(self: *const DB) !*DB {
        const new_db = try self.allocator.create(DB);
        new_db.* = self.*;
        new_db.query_hooks = try self.query_hooks.clone();
        return new_db;
    }
};
```

**使用示例**

```zig
const std = @import("std");
const zorm = @import("zorm");

// 定义模型
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    created_at: i64,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 打开数据库连接
    const conn = try openPostgresConnection(allocator, "postgres://localhost/test");
    defer conn.close();

    // 创建 DB 实例
    const db = try zorm.DB.init(
        allocator,
        conn,
        .postgresql,
        .{
            .max_open_conns = 20,
            .discard_unknown_columns = false,
        },
    );
    defer db.deinit();

    // 使用查询构建器
    var users = std.ArrayList(User).init(allocator);
    defer users.deinit();

    var query = try db.newSelect(User);
    defer query.deinit();

    try query.where("age > ?", .{18});
    try query.orderBy("created_at", .desc);
    try query.limit(10);
    try query.scan(&users);

    std.debug.print("Found {} users\n", .{users.items.len});
}
```

---

#### 2.1.2 内存管理策略

**功能描述**
Zig 要求显式内存管理，ZORM 使用 Allocator 模式管理所有内存分配。

**核心原则**
1. **Allocator 传递** - 所有需要分配的函数接受 Allocator 参数
2. **谁分配谁释放** - 清晰的所有权语义
3. **defer 清理** - 使用 defer 确保资源释放
4. **Arena 优化** - 临时分配使用 ArenaAllocator

**内存分配策略**

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

/// 查询上下文，使用 Arena 管理临时分配
pub const QueryContext = struct {
    arena: std.heap.ArenaAllocator,
    base_allocator: Allocator,

    pub fn init(base_allocator: Allocator) QueryContext {
        return .{
            .arena = std.heap.ArenaAllocator.init(base_allocator),
            .base_allocator = base_allocator,
        };
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

/// 使用示例
pub fn executeQuery(db: *DB, sql: []const u8) !void {
    var ctx = QueryContext.init(db.allocator);
    defer ctx.deinit();

    // 所有临时分配使用 ctx.allocator()
    const params = try ctx.allocator().alloc(Param, 10);
    // params 会在 ctx.deinit() 时自动释放
}
```

**内存泄漏检测**

```zig
const std = @import("std");

test "detect memory leaks" {
    // 使用 testing allocator 自动检测泄漏
    const allocator = std.testing.allocator;

    var db = try DB.init(allocator, conn, .postgresql, .{});
    defer db.deinit();

    var users = std.ArrayList(User).init(allocator);
    defer users.deinit();

    var query = try db.newSelect(User);
    defer query.deinit(); // 忘记这行会导致测试失败

    try query.scan(&users);
}
```

---

#### 2.1.3 错误处理系统

**功能描述**
Zig 的错误处理使用错误联合类型，编译器强制处理所有错误。

**错误定义**

```zig
/// ZORM 错误集
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

/// 查询结果类型
pub fn QueryResult(comptime T: type) type {
    return Error!T;
}

/// 空结果类型
pub const VoidResult = Error!void;
```

**错误处理模式**

```zig
const std = @import("std");

// 1. 传播错误（使用 try）
pub fn findUser(db: *DB, id: i64) !User {
    var query = try db.newSelect(User); // 传播错误
    defer query.deinit();

    try query.where("id = ?", .{id});
    return try query.scanOne(); // 传播错误
}

// 2. 捕获错误（使用 catch）
pub fn findUserSafe(db: *DB, id: i64) ?User {
    return findUser(db, id) catch |err| {
        std.log.err("Failed to find user: {}", .{err});
        return null;
    };
}

// 3. 错误恢复
pub fn findUserWithDefault(db: *DB, id: i64) User {
    return findUser(db, id) catch |err| {
        std.log.warn("User not found, using default: {}", .{err});
        return User{
            .id = -1,
            .name = "Unknown",
            .email = "",
            .created_at = 0,
        };
    };
}

// 4. 错误类型判断
pub fn handleQueryError(db: *DB, id: i64) !User {
    return findUser(db, id) catch |err| switch (err) {
        error.NoRows => {
            std.log.warn("User {} not found", .{id});
            return error.NoRows;
        },
        error.ConnectionFailed => {
            std.log.err("Database connection failed", .{});
            // 可能重试连接
            return error.ConnectionFailed;
        },
        else => {
            std.log.err("Unexpected error: {}", .{err});
            return err;
        },
    };
}
```

---

#### 2.1.4 方言系统（Comptime 实现）

**功能描述**
使用 Zig 的 `comptime` 特性在编译时选择数据库方言，实现零运行时开销。

**方言定义**

```zig
const std = @import("std");

/// 数据库方言枚举
pub const Dialect = enum {
    postgresql,
    mysql,
    sqlite,
    mssql,
    oracle,

    /// 获取占位符格式
    pub fn placeholder(comptime self: Dialect, index: usize) []const u8 {
        return comptime switch (self) {
            .postgresql => std.fmt.comptimePrint("${d}", .{index}),
            .mysql, .sqlite => "?",
            .mssql => std.fmt.comptimePrint("@p{d}", .{index}),
            .oracle => std.fmt.comptimePrint(":{d}", .{index}),
        };
    }

    /// 检查是否支持特性
    pub fn supports(comptime self: Dialect, comptime feature: Feature) bool {
        return comptime switch (self) {
            .postgresql => switch (feature) {
                .returning => true,
                .cte => true,
                .arrays => true,
                .jsonb => true,
                .on_conflict => true,
                else => false,
            },
            .mysql => switch (feature) {
                .cte => true,
                .on_duplicate_key => true,
                .insert_ignore => true,
                else => false,
            },
            .sqlite => switch (feature) {
                .returning => true,
                .cte => true,
                .on_conflict => true,
                else => false,
            },
            .mssql => switch (feature) {
                .cte => true,
                .output_clause => true,
                .merge => true,
                else => false,
            },
            .oracle => switch (feature) {
                .cte => true,
                .merge => true,
                else => false,
            },
        };
    }

    /// 获取标识符引用符号
    pub fn quoteIdentifier(comptime self: Dialect) [2]u8 {
        return comptime switch (self) {
            .postgresql, .oracle => .{ '"', '"' },
            .mysql => .{ '`', '`' },
            .mssql => .{ '[', ']' },
            .sqlite => .{ '"', '"' },
        };
    }
};

/// 特性标志
pub const Feature = enum {
    returning,
    output_clause,
    cte,
    window_functions,
    arrays,
    jsonb,
    on_conflict,
    on_duplicate_key,
    insert_ignore,
    merge,
    full_text_search,
};

/// 编译时方言分派
pub fn dialectDispatch(
    comptime dialect: Dialect,
    comptime feature: Feature,
    args: anytype,
) !void {
    if (comptime dialect.supports(feature)) {
        // 编译时已知，生成特定代码
        return implementFeature(dialect, feature, args);
    } else {
        // 编译时错误
        @compileError(std.fmt.comptimePrint(
            "Dialect {s} does not support feature {s}",
            .{ @tagName(dialect), @tagName(feature) },
        ));
    }
}
```

**使用示例**

```zig
const std = @import("std");

// 编译时选择方言
pub fn buildQuery(comptime dialect: Dialect, id: i64) []const u8 {
    const ph = dialect.placeholder(1);
    const quote = dialect.quoteIdentifier();

    return comptime std.fmt.comptimePrint(
        "SELECT * FROM {c}users{c} WHERE id = {s}",
        .{ quote[0], quote[1], ph },
    );
}

// 生成的代码：
// PostgreSQL: SELECT * FROM "users" WHERE id = $1
// MySQL: SELECT * FROM `users` WHERE id = ?
// MSSQL: SELECT * FROM [users] WHERE id = @p1

test "comptime dialect dispatch" {
    const pg_query = buildQuery(.postgresql, 123);
    const my_query = buildQuery(.mysql, 123);

    try std.testing.expectEqualStrings(
        "SELECT * FROM \"users\" WHERE id = $1",
        pg_query,
    );
    try std.testing.expectEqualStrings(
        "SELECT * FROM `users` WHERE id = ?",
        my_query,
    );
}
```

---

### 2.2 查询构建器（Zig 实现）

#### 2.2.1 SELECT 查询

**功能描述**
类型安全的 SELECT 查询构建器，使用泛型和 comptime 反射。

**API 接口**

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

/// SELECT 查询构建器
pub fn SelectQuery(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        db: *DB,
        columns: std.ArrayList([]const u8),
        table_name: []const u8,
        where_clauses: std.ArrayList(WhereClause),
        joins: std.ArrayList(JoinClause),
        order_by: std.ArrayList(OrderClause),
        group_by: std.ArrayList([]const u8),
        having: std.ArrayList(WhereClause),
        limit_value: ?usize,
        offset_value: ?usize,
        distinct: bool,

        pub fn init(allocator: Allocator, db: *DB) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .allocator = allocator,
                .db = db,
                .columns = std.ArrayList([]const u8).init(allocator),
                .table_name = comptime getTableName(T),
                .where_clauses = std.ArrayList(WhereClause).init(allocator),
                .joins = std.ArrayList(JoinClause).init(allocator),
                .order_by = std.ArrayList(OrderClause).init(allocator),
                .group_by = std.ArrayList([]const u8).init(allocator),
                .having = std.ArrayList(WhereClause).init(allocator),
                .limit_value = null,
                .offset_value = null,
                .distinct = false,
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.columns.deinit();
            self.where_clauses.deinit();
            self.joins.deinit();
            self.order_by.deinit();
            self.group_by.deinit();
            self.having.deinit();
            self.allocator.destroy(self);
        }

        /// 选择列
        pub fn column(self: *Self, col: []const u8) !*Self {
            try self.columns.append(col);
            return self;
        }

        /// 选择所有列
        pub fn allColumns(self: *Self) !*Self {
            comptime {
                const fields = @typeInfo(T).Struct.fields;
                inline for (fields) |field| {
                    try self.columns.append(field.name);
                }
            }
            return self;
        }

        /// WHERE 条件
        pub fn where(self: *Self, condition: []const u8, args: anytype) !*Self {
            const clause = WhereClause{
                .condition = condition,
                .args = try allocArgs(self.allocator, args),
                .operator = .and_op,
            };
            try self.where_clauses.append(clause);
            return self;
        }

        /// WHERE OR 条件
        pub fn whereOr(self: *Self, condition: []const u8, args: anytype) !*Self {
            const clause = WhereClause{
                .condition = condition,
                .args = try allocArgs(self.allocator, args),
                .operator = .or_op,
            };
            try self.where_clauses.append(clause);
            return self;
        }

        /// JOIN
        pub fn join(
            self: *Self,
            join_type: JoinType,
            table: []const u8,
            condition: []const u8,
        ) !*Self {
            try self.joins.append(.{
                .join_type = join_type,
                .table = table,
                .condition = condition,
            });
            return self;
        }

        pub fn leftJoin(self: *Self, table: []const u8, condition: []const u8) !*Self {
            return self.join(.left, table, condition);
        }

        pub fn innerJoin(self: *Self, table: []const u8, condition: []const u8) !*Self {
            return self.join(.inner, table, condition);
        }

        /// ORDER BY
        pub fn orderBy(self: *Self, col: []const u8, direction: OrderDirection) !*Self {
            try self.order_by.append(.{ .column = col, .direction = direction });
            return self;
        }

        /// GROUP BY
        pub fn groupBy(self: *Self, col: []const u8) !*Self {
            try self.group_by.append(col);
            return self;
        }

        /// LIMIT
        pub fn limit(self: *Self, n: usize) *Self {
            self.limit_value = n;
            return self;
        }

        /// OFFSET
        pub fn offset(self: *Self, n: usize) *Self {
            self.offset_value = n;
            return self;
        }

        /// DISTINCT
        pub fn setDistinct(self: *Self) *Self {
            self.distinct = true;
            return self;
        }

        /// 构建 SQL
        pub fn buildSQL(self: *Self) ![]const u8 {
            var buf = std.ArrayList(u8).init(self.allocator);
            defer buf.deinit();

            const writer = buf.writer();

            // SELECT
            try writer.writeAll("SELECT ");
            if (self.distinct) {
                try writer.writeAll("DISTINCT ");
            }

            // 列
            if (self.columns.items.len == 0) {
                try writer.writeAll("*");
            } else {
                for (self.columns.items, 0..) |col, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll(col);
                }
            }

            // FROM
            try writer.print(" FROM {s}", .{self.table_name});

            // JOIN
            for (self.joins.items) |j| {
                try writer.print(" {s} JOIN {s} ON {s}", .{
                    @tagName(j.join_type),
                    j.table,
                    j.condition,
                });
            }

            // WHERE
            if (self.where_clauses.items.len > 0) {
                try writer.writeAll(" WHERE ");
                for (self.where_clauses.items, 0..) |clause, i| {
                    if (i > 0) {
                        const op = if (clause.operator == .and_op) " AND " else " OR ";
                        try writer.writeAll(op);
                    }
                    try writer.writeAll(clause.condition);
                }
            }

            // GROUP BY
            if (self.group_by.items.len > 0) {
                try writer.writeAll(" GROUP BY ");
                for (self.group_by.items, 0..) |col, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll(col);
                }
            }

            // HAVING
            if (self.having.items.len > 0) {
                try writer.writeAll(" HAVING ");
                for (self.having.items, 0..) |clause, i| {
                    if (i > 0) try writer.writeAll(" AND ");
                    try writer.writeAll(clause.condition);
                }
            }

            // ORDER BY
            if (self.order_by.items.len > 0) {
                try writer.writeAll(" ORDER BY ");
                for (self.order_by.items, 0..) |order, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("{s} {s}", .{
                        order.column,
                        if (order.direction == .asc) "ASC" else "DESC",
                    });
                }
            }

            // LIMIT
            if (self.limit_value) |lim| {
                try writer.print(" LIMIT {d}", .{lim});
            }

            // OFFSET
            if (self.offset_value) |off| {
                try writer.print(" OFFSET {d}", .{off});
            }

            return try buf.toOwnedSlice();
        }

        /// 执行查询并扫描结果
        pub fn scan(self: *Self, dest: *std.ArrayList(T)) !void {
            const sql = try self.buildSQL();
            defer self.allocator.free(sql);

            // 执行查询
            const rows = try self.db.query(sql, self.collectArgs());
            defer rows.deinit();

            // 扫描每一行
            while (try rows.next()) |row| {
                const item = try scanRow(T, row, self.allocator);
                try dest.append(item);
            }
        }

        /// 扫描单行
        pub fn scanOne(self: *Self) !T {
            _ = self.limit(1);

            var list = std.ArrayList(T).init(self.allocator);
            defer list.deinit();

            try self.scan(&list);

            if (list.items.len == 0) {
                return error.NoRows;
            }

            return list.items[0];
        }

        /// 计数
        pub fn count(self: *Self) !usize {
            const original_cols = self.columns;
            defer self.columns = original_cols;

            self.columns = std.ArrayList([]const u8).init(self.allocator);
            try self.columns.append("COUNT(*)");

            var result: usize = 0;
            // 执行并扫描结果
            return result;
        }
    };
}

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

/// JOIN 类型
pub const JoinType = enum {
    inner,
    left,
    right,
    full,
    cross,
};

/// JOIN 子句
pub const JoinClause = struct {
    join_type: JoinType,
    table: []const u8,
    condition: []const u8,
};

/// ORDER BY 方向
pub const OrderDirection = enum {
    asc,
    desc,
};

/// ORDER BY 子句
pub const OrderClause = struct {
    column: []const u8,
    direction: OrderDirection,
};

/// 查询参数
pub const QueryArg = union(enum) {
    int: i64,
    uint: u64,
    float: f64,
    bool: bool,
    string: []const u8,
    null_val: void,
};

/// 从元组分配参数
fn allocArgs(allocator: Allocator, args: anytype) ![]const QueryArg {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);

    if (args_type_info != .Struct) {
        @compileError("args must be a tuple");
    }

    const fields = args_type_info.Struct.fields;
    var result = try allocator.alloc(QueryArg, fields.len);

    inline for (fields, 0..) |field, i| {
        const value = @field(args, field.name);
        result[i] = try argFromValue(value);
    }

    return result;
}

/// 从值创建参数
fn argFromValue(value: anytype) !QueryArg {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    return switch (type_info) {
        .Int => .{ .int = @intCast(value) },
        .Float => .{ .float = @floatCast(value) },
        .Bool => .{ .bool = value },
        .Pointer => |ptr| {
            if (ptr.child == u8) {
                return .{ .string = value };
            }
            @compileError("Unsupported pointer type");
        },
        else => @compileError("Unsupported argument type"),
    };
}

/// 获取表名（comptime）
fn getTableName(comptime T: type) []const u8 {
    // 查找 @"table" 字段或使用类型名
    if (@hasDecl(T, "table_name")) {
        return T.table_name;
    }
    return @typeName(T);
}

/// 从行扫描到结构体
fn scanRow(comptime T: type, row: *Row, allocator: Allocator) !T {
    var result: T = undefined;

    comptime {
        const fields = @typeInfo(T).Struct.fields;
        inline for (fields, 0..) |field, i| {
            const value = try row.getValue(field.type, i);
            @field(result, field.name) = value;
        }
    }

    return result;
}
```

**使用示例**

```zig
const std = @import("std");
const zorm = @import("zorm");

const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: u32,
    created_at: i64,

    pub const table_name = "users";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const db = try initDB(allocator);
    defer db.deinit();

    // 基础查询
    var users = std.ArrayList(User).init(allocator);
    defer users.deinit();

    var query = try db.newSelect(User);
    defer query.deinit();

    try query
        .where("age > ?", .{18})
        .orderBy("created_at", .desc)
        .limit(10)
        .scan(&users);

    std.debug.print("Found {} users\n", .{users.items.len});

    // 复杂查询
    var adult_users = std.ArrayList(User).init(allocator);
    defer adult_users.deinit();

    var complex_query = try db.newSelect(User);
    defer complex_query.deinit();

    try complex_query
        .where("age >= ?", .{18})
        .whereOr("role = ?", .{"admin"})
        .leftJoin("profiles", "profiles.user_id = users.id")
        .groupBy("users.id")
        .having("COUNT(posts.id) > ?", .{5})
        .orderBy("created_at", .desc)
        .limit(20)
        .offset(10)
        .scan(&adult_users);

    // 单行查询
    const user = try db.newSelect(User)
        .where("id = ?", .{123})
        .scanOne();

    std.debug.print("User: {s}\n", .{user.name});

    // 计数查询
    const count = try db.newSelect(User)
        .where("active = ?", .{true})
        .count();

    std.debug.print("Active users: {d}\n", .{count});
}
```

---

#### 2.2.2 INSERT 查询

**功能描述**
类型安全的 INSERT 查询构建器，支持批量插入和 RETURNING。

**API 接口**

```zig
/// INSERT 查询构建器
pub fn InsertQuery(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        db: *DB,
        table_name: []const u8,
        values: std.ArrayList(T),
        columns: std.ArrayList([]const u8),
        ignore: bool,
        replace: bool,
        returning: ?[]const u8,
        on_conflict: ?[]const u8,
        on_duplicate_key: ?[]const u8,

        pub fn init(allocator: Allocator, db: *DB) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .allocator = allocator,
                .db = db,
                .table_name = comptime getTableName(T),
                .values = std.ArrayList(T).init(allocator),
                .columns = std.ArrayList([]const u8).init(allocator),
                .ignore = false,
                .replace = false,
                .returning = null,
                .on_conflict = null,
                .on_duplicate_key = null,
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.values.deinit();
            self.columns.deinit();
            self.allocator.destroy(self);
        }

        /// 设置要插入的值（单个）
        pub fn value(self: *Self, val: T) !*Self {
            try self.values.append(val);
            return self;
        }

        /// 设置要插入的值（批量）
        pub fn values(self: *Self, vals: []const T) !*Self {
            try self.values.appendSlice(vals);
            return self;
        }

        /// 指定列（可选）
        pub fn column(self: *Self, col: []const u8) !*Self {
            try self.columns.append(col);
            return self;
        }

        /// INSERT IGNORE (MySQL)
        pub fn setIgnore(self: *Self) *Self {
            if (comptime !self.db.dialect.supports(.insert_ignore)) {
                @compileError("Current dialect does not support INSERT IGNORE");
            }
            self.ignore = true;
            return self;
        }

        /// REPLACE INTO (MySQL/SQLite)
        pub fn setReplace(self: *Self) *Self {
            self.replace = true;
            return self;
        }

        /// RETURNING (PostgreSQL/SQLite)
        pub fn setReturning(self: *Self, cols: []const u8) !*Self {
            if (comptime !self.db.dialect.supports(.returning)) {
                @compileError("Current dialect does not support RETURNING");
            }
            self.returning = cols;
            return self;
        }

        /// ON CONFLICT (PostgreSQL/SQLite)
        pub fn onConflict(self: *Self, clause: []const u8) !*Self {
            if (comptime !self.db.dialect.supports(.on_conflict)) {
                @compileError("Current dialect does not support ON CONFLICT");
            }
            self.on_conflict = clause;
            return self;
        }

        /// ON DUPLICATE KEY UPDATE (MySQL)
        pub fn onDuplicateKeyUpdate(self: *Self, clause: []const u8) !*Self {
            if (comptime !self.db.dialect.supports(.on_duplicate_key)) {
                @compileError("Current dialect does not support ON DUPLICATE KEY");
            }
            self.on_duplicate_key = clause;
            return self;
        }

        /// 构建 SQL
        pub fn buildSQL(self: *Self) ![]const u8 {
            var buf = std.ArrayList(u8).init(self.allocator);
            const writer = buf.writer();

            // INSERT/REPLACE
            if (self.replace) {
                try writer.writeAll("REPLACE");
            } else {
                try writer.writeAll("INSERT");
                if (self.ignore) {
                    try writer.writeAll(" IGNORE");
                }
            }

            // INTO
            try writer.print(" INTO {s} ", .{self.table_name});

            // 列名
            if (self.columns.items.len > 0) {
                try writer.writeAll("(");
                for (self.columns.items, 0..) |col, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll(col);
                }
                try writer.writeAll(") ");
            }

            // VALUES
            try writer.writeAll("VALUES ");
            for (self.values.items, 0..) |_, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll("(");

                // 生成占位符
                const field_count = @typeInfo(T).Struct.fields.len;
                for (0..field_count) |j| {
                    if (j > 0) try writer.writeAll(", ");
                    try writer.print("{s}", .{
                        self.db.dialect.placeholder(i * field_count + j + 1),
                    });
                }
                try writer.writeAll(")");
            }

            // ON CONFLICT
            if (self.on_conflict) |clause| {
                try writer.print(" ON CONFLICT {s}", .{clause});
            }

            // ON DUPLICATE KEY UPDATE
            if (self.on_duplicate_key) |clause| {
                try writer.print(" ON DUPLICATE KEY UPDATE {s}", .{clause});
            }

            // RETURNING
            if (self.returning) |cols| {
                try writer.print(" RETURNING {s}", .{cols});
            }

            return try buf.toOwnedSlice();
        }

        /// 执行插入
        pub fn exec(self: *Self) !InsertResult {
            const sql = try self.buildSQL();
            defer self.allocator.free(sql);

            const result = try self.db.exec(sql, self.collectArgs());
            return result;
        }

        /// 执行并返回生成的 ID
        pub fn execReturning(self: *Self, dest: *std.ArrayList(T)) !void {
            if (self.returning == null) {
                self.returning = "*";
            }

            const sql = try self.buildSQL();
            defer self.allocator.free(sql);

            const rows = try self.db.query(sql, self.collectArgs());
            defer rows.deinit();

            while (try rows.next()) |row| {
                const item = try scanRow(T, row, self.allocator);
                try dest.append(item);
            }
        }
    };
}

/// 插入结果
pub const InsertResult = struct {
    rows_affected: u64,
    last_insert_id: ?i64,
};
```

**使用示例**

```zig
const std = @import("std");
const zorm = @import("zorm");

const User = struct {
    id: i64 = 0,
    name: []const u8,
    email: []const u8,
    age: u32,
    created_at: i64,
};

pub fn insertExamples(db: *zorm.DB, allocator: Allocator) !void {
    // 1. 单行插入
    const user = User{
        .name = "John Doe",
        .email = "john@example.com",
        .age = 30,
        .created_at = std.time.timestamp(),
    };

    var insert1 = try db.newInsert(User);
    defer insert1.deinit();

    const result = try insert1.value(user).exec();
    std.debug.print("Inserted {} rows, last ID: {?}\n", .{
        result.rows_affected,
        result.last_insert_id,
    });

    // 2. 批量插入
    const users = [_]User{
        .{ .name = "Alice", .email = "alice@example.com", .age = 25, .created_at = std.time.timestamp() },
        .{ .name = "Bob", .email = "bob@example.com", .age = 35, .created_at = std.time.timestamp() },
        .{ .name = "Carol", .email = "carol@example.com", .age = 28, .created_at = std.time.timestamp() },
    };

    var insert2 = try db.newInsert(User);
    defer insert2.deinit();

    _ = try insert2.values(&users).exec();

    // 3. RETURNING (PostgreSQL)
    var inserted_users = std.ArrayList(User).init(allocator);
    defer inserted_users.deinit();

    var insert3 = try db.newInsert(User);
    defer insert3.deinit();

    try insert3
        .value(user)
        .setReturning("*")
        .execReturning(&inserted_users);

    std.debug.print("Inserted user ID: {}\n", .{inserted_users.items[0].id});

    // 4. ON CONFLICT DO NOTHING (PostgreSQL)
    var insert4 = try db.newInsert(User);
    defer insert4.deinit();

    _ = try insert4
        .value(user)
        .onConflict("(email) DO NOTHING")
        .exec();

    // 5. ON CONFLICT DO UPDATE (PostgreSQL)
    var insert5 = try db.newInsert(User);
    defer insert5.deinit();

    _ = try insert5
        .value(user)
        .onConflict("(email) DO UPDATE SET name = EXCLUDED.name, age = EXCLUDED.age")
        .exec();

    // 6. INSERT IGNORE (MySQL)
    var insert6 = try db.newInsert(User);
    defer insert6.deinit();

    _ = try insert6
        .value(user)
        .setIgnore()
        .exec();

    // 7. ON DUPLICATE KEY UPDATE (MySQL)
    var insert7 = try db.newInsert(User);
    defer insert7.deinit();

    _ = try insert7
        .value(user)
        .onDuplicateKeyUpdate("name = VALUES(name), age = VALUES(age)")
        .exec();
}
```

---

### 2.3 编译时反射和类型映射

**功能描述**
使用 Zig 的 `comptime` 和 `@typeInfo` 实现零运行时开销的类型映射。

```zig
const std = @import("std");

/// SQL 类型
pub const SQLType = enum {
    integer,
    big_integer,
    small_integer,
    float,
    double,
    boolean,
    text,
    varchar,
    timestamp,
    date,
    time,
    json,
    jsonb,
    blob,
    uuid,
};

/// Zig 类型到 SQL 类型的映射
pub fn zigToSQLType(comptime T: type) SQLType {
    const type_info = @typeInfo(T);

    return switch (type_info) {
        .Int => |int_info| {
            if (int_info.bits <= 16) return .small_integer;
            if (int_info.bits <= 32) return .integer;
            return .big_integer;
        },
        .Float => |float_info| {
            if (float_info.bits <= 32) return .float;
            return .double;
        },
        .Bool => .boolean,
        .Pointer => |ptr_info| {
            if (ptr_info.child == u8) return .text;
            @compileError("Unsupported pointer type for SQL");
        },
        .Optional => |opt_info| {
            return zigToSQLType(opt_info.child);
        },
        .Struct => {
            // 检查是否是特殊类型
            if (T == std.time.Timestamp) return .timestamp;
            if (hasField(T, "json")) return .json;
            @compileError("Unsupported struct type for SQL");
        },
        else => @compileError("Unsupported type for SQL: " ++ @typeName(T)),
    };
}

/// 生成 CREATE TABLE SQL
pub fn generateCreateTableSQL(comptime T: type, allocator: Allocator) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const writer = buf.writer();

    const table_name = getTableName(T);
    try writer.print("CREATE TABLE {s} (\n", .{table_name});

    const fields = @typeInfo(T).Struct.fields;
    inline for (fields, 0..) |field, i| {
        if (i > 0) try writer.writeAll(",\n");

        const sql_type = zigToSQLType(field.type);
        const is_optional = @typeInfo(field.type) == .Optional;

        try writer.print("    {s} {s}", .{
            field.name,
            sqlTypeToString(sql_type),
        });

        // 主键检测
        if (std.mem.eql(u8, field.name, "id")) {
            try writer.writeAll(" PRIMARY KEY");
        }

        // NOT NULL
        if (!is_optional) {
            try writer.writeAll(" NOT NULL");
        }
    }

    try writer.writeAll("\n)");
    return try buf.toOwnedSlice();
}

/// SQL 类型转字符串
fn sqlTypeToString(sql_type: SQLType) []const u8 {
    return switch (sql_type) {
        .integer => "INTEGER",
        .big_integer => "BIGINT",
        .small_integer => "SMALLINT",
        .float => "REAL",
        .double => "DOUBLE PRECISION",
        .boolean => "BOOLEAN",
        .text => "TEXT",
        .varchar => "VARCHAR(255)",
        .timestamp => "TIMESTAMP",
        .date => "DATE",
        .time => "TIME",
        .json => "JSON",
        .jsonb => "JSONB",
        .blob => "BLOB",
        .uuid => "UUID",
    };
}

/// 检测结构体是否有某个字段
fn hasField(comptime T: type, comptime field_name: []const u8) bool {
    const fields = @typeInfo(T).Struct.fields;
    inline for (fields) |field| {
        if (std.mem.eql(u8, field.name, field_name)) {
            return true;
        }
    }
    return false;
}

test "comptime type reflection" {
    const User = struct {
        id: i64,
        name: []const u8,
        email: ?[]const u8,
        age: u32,
        is_active: bool,
        created_at: i64,
    };

    const sql = try generateCreateTableSQL(User, std.testing.allocator);
    defer std.testing.allocator.free(sql);

    std.debug.print("\n{s}\n", .{sql});

    // 预期输出:
    // CREATE TABLE User (
    //     id BIGINT PRIMARY KEY NOT NULL,
    //     name TEXT NOT NULL,
    //     email TEXT,
    //     age INTEGER NOT NULL,
    //     is_active BOOLEAN NOT NULL,
    //     created_at BIGINT NOT NULL
    // )
}
```

---

## 第三部分: 构建和测试

### 3.1 项目结构

```
zorm/
├── build.zig              # 构建配置
├── build.zig.zon          # 依赖配置
├── src/
│   ├── main.zig           # 主入口
│   ├── db.zig             # DB 核心
│   ├── query/
│   │   ├── select.zig     # SELECT 查询
│   │   ├── insert.zig     # INSERT 查询
│   │   ├── update.zig     # UPDATE 查询
│   │   ├── delete.zig     # DELETE 查询
│   │   └── raw.zig        # Raw SQL
│   ├── dialect/
│   │   ├── postgres.zig   # PostgreSQL 方言
│   ├── schema/
│   │   ├── table.zig      # 表定义
│   │   ├── field.zig      # 字段定义
│   │   └── relation.zig   # 关系定义
│   ├── migrate/
│   │   └── migrator.zig   # 迁移系统
│   └── extra/
│       ├── debug.zig      # 调试工具
│       └── otel.zig       # OpenTelemetry
├── tests/
│   ├── query_test.zig     # 查询测试
│   ├── dialect_test.zig   # 方言测试
│   └── integration_test.zig # 集成测试
└── docs/
    └── functional_spec.md # 本文档
```

### 3.2 构建配置

**build.zig**

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 库模块
    const zorm = b.addModule("zorm", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 单元测试
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 添加数据库驱动依赖
    unit_tests.linkSystemLibrary("pq");        // PostgreSQL
    unit_tests.linkSystemLibrary("mysqlclient"); // MySQL
    unit_tests.linkSystemLibrary("sqlite3");   // SQLite

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // 示例程序
    const example = b.addExecutable(.{
        .name = "zorm-example",
        .root_source_file = b.path("examples/basic.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("zorm", zorm);
    example.linkSystemLibrary("pq");

    b.installArtifact(example);

    const run_cmd = b.addRunArtifact(example);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);

    // 文档生成
    const docs = b.addInstallDirectory(.{
        .source_dir = unit_tests.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&docs.step);
}
```

### 3.3 测试策略

**单元测试示例**

```zig
const std = @import("std");
const zorm = @import("zorm");
const testing = std.testing;

test "SELECT query building" {
    const allocator = testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,
        email: []const u8,
    };

    const db = try zorm.DB.initMock(allocator, .postgresql);
    defer db.deinit();

    var query = try db.newSelect(User);
    defer query.deinit();

    try query.where("age > ?", .{18});
    try query.orderBy("created_at", .desc);
    try query.limit(10);

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    try testing.expectEqualStrings(
        "SELECT * FROM User WHERE age > $1 ORDER BY created_at DESC LIMIT 10",
        sql,
    );
}

test "INSERT with RETURNING" {
    const allocator = testing.allocator;

    const User = struct {
        id: i64 = 0,
        name: []const u8,
        email: []const u8,
    };

    const db = try zorm.DB.initMock(allocator, .postgresql);
    defer db.deinit();

    var insert = try db.newInsert(User);
    defer insert.deinit();

    const user = User{
        .name = "John Doe",
        .email = "john@example.com",
    };

    try insert.value(user);
    try insert.setReturning("id");

    const sql = try insert.buildSQL();
    defer allocator.free(sql);

    try testing.expectEqualStrings(
        "INSERT INTO User (name, email) VALUES ($1, $2) RETURNING id",
        sql,
    );
}

test "memory leak detection" {
    const allocator = testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,
    };

    const db = try zorm.DB.initMock(allocator, .postgresql);
    defer db.deinit();

    var query = try db.newSelect(User);
    // 忘记 defer query.deinit(); 会导致测试失败
    defer query.deinit();

    _ = try query.buildSQL();
    // SQL 自动释放
}

test "comptime dialect dispatch" {
    const allocator = testing.allocator;

    // PostgreSQL
    {
        const db_pg = try zorm.DB.initMock(allocator, .postgresql);
        defer db_pg.deinit();

        const ph1 = db_pg.dialect.placeholder(1);
        try testing.expectEqualStrings("$1", ph1);

        const supports_returning = db_pg.dialect.supports(.returning);
        try testing.expect(supports_returning);
    }

    // MySQL
    {
        const db_my = try zorm.DB.initMock(allocator, .mysql);
        defer db_my.deinit();

        const ph1 = db_my.dialect.placeholder(1);
        try testing.expectEqualStrings("?", ph1);

        const supports_returning = db_my.dialect.supports(.returning);
        try testing.expect(!supports_returning);
    }
}
```

### 3.4 性能基准测试

```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const db = try initDB(allocator);
    defer db.deinit();

    // 基准测试: 批量插入
    {
        const start = std.time.nanoTimestamp();

        const User = struct {
            id: i64 = 0,
            name: []const u8,
            email: []const u8,
        };

        const batch_size = 1000;
        var users = try allocator.alloc(User, batch_size);
        defer allocator.free(users);

        for (users, 0..) |*user, i| {
            user.* = .{
                .name = try std.fmt.allocPrint(allocator, "User{d}", .{i}),
                .email = try std.fmt.allocPrint(allocator, "user{d}@test.com", .{i}),
            };
        }

        var insert = try db.newInsert(User);
        defer insert.deinit();

        _ = try insert.values(users).exec();

        const end = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
        const rows_per_sec = @as(f64, batch_size) / (duration_ms / 1000.0);

        std.debug.print("Batch insert: {d:.2}ms, {d:.0} rows/sec\n", .{
            duration_ms,
            rows_per_sec,
        });
    }
}
```

---

## 第四部分: API 设计原则（Zig 适配）

### 4.1 Zig 惯用法

1. **显式优于隐式**
   - 所有内存分配显式传递 Allocator
   - 所有错误必须处理或传播
   - 资源清理使用 defer

2. **零成本抽象**
   - 使用 comptime 消除运行时开销
   - 内联关键路径
   - 避免运行时类型检查

3. **编译时验证**
   - 方言特性在编译时检查
   - 类型映射在编译时计算
   - SQL 生成在编译时优化

4. **清晰的所有权**
   - 明确哪个模块拥有内存
   - 使用 defer 管理生命周期
   - Arena 用于临时分配

### 4.2 错误处理哲学

```zig
// ✅ 好的错误处理
pub fn findUser(db: *DB, id: i64) !User {
    var query = try db.newSelect(User);
    defer query.deinit();

    try query.where("id = ?", .{id});
    return try query.scanOne();
}

// ❌ 不好的错误处理（隐藏错误）
pub fn findUserBad(db: *DB, id: i64) ?User {
    return findUser(db, id) catch null; // 丢失错误信息
}

// ✅ 恢复错误
pub fn findUserWithFallback(db: *DB, id: i64) User {
    return findUser(db, id) catch |err| {
        std.log.err("Failed to find user: {}", .{err});
        return default_user;
    };
}
```

### 4.3 内存管理最佳实践

```zig
// ✅ 清晰的所有权
pub fn loadUsers(allocator: Allocator, db: *DB) !std.ArrayList(User) {
    var users = std.ArrayList(User).init(allocator);
    errdefer users.deinit(); // 错误时自动清理

    var query = try db.newSelect(User);
    defer query.deinit();

    try query.scan(&users);
    return users; // 调用者负责 deinit
}

// 使用
pub fn example(allocator: Allocator, db: *DB) !void {
    var users = try loadUsers(allocator, db);
    defer users.deinit(); // 清晰的清理

    // 使用 users
}

// ✅ Arena 用于临时分配
pub fn processQuery(allocator: Allocator, db: *DB) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit(); // 一次性清理所有

    const temp_allocator = arena.allocator();

    // 所有临时分配使用 temp_allocator
    const sql = try buildComplexSQL(temp_allocator);
    const params = try allocParams(temp_allocator);

    // arena.deinit() 会清理所有
}
```

---

## 第五部分: 性能优化策略

### 5.1 编译时优化

```zig
// 1. comptime SQL 生成
pub fn simpleSelect(comptime T: type, comptime where_clause: []const u8) []const u8 {
    return comptime blk: {
        const table_name = getTableName(T);
        break :blk std.fmt.comptimePrint(
            "SELECT * FROM {s} WHERE {s}",
            .{ table_name, where_clause },
        );
    };
}

// 使用
const sql = simpleSelect(User, "age > 18"); // 编译时生成

// 2. comptime 类型检查
pub fn validateModel(comptime T: type) void {
    comptime {
        const fields = @typeInfo(T).Struct.fields;
        for (fields) |field| {
            const sql_type = zigToSQLType(field.type);
            std.debug.assert(sql_type != .unsupported);
        }
    }
}

// 3. inline 热路径
pub inline fn scanField(comptime T: type, row: *Row, index: usize) !T {
    return switch (T) {
        i32, i64, u32, u64 => try row.getInt(T, index),
        f32, f64 => try row.getFloat(T, index),
        bool => try row.getBool(index),
        []const u8 => try row.getString(index),
        else => @compileError("Unsupported type"),
    };
}
```

### 5.2 运行时优化

```zig
// 1. Buffer 复用
pub const QueryBuilder = struct {
    buf: std.ArrayList(u8),

    pub fn reset(self: *QueryBuilder) void {
        self.buf.clearRetainingCapacity();
    }
};

// 2. 预分配
pub fn allocWithCapacity(allocator: Allocator, expected_size: usize) !std.ArrayList(u8) {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.ensureTotalCapacity(expected_size);
    return buf;
}

// 3. 批量操作
pub fn batchInsert(db: *DB, users: []const User, batch_size: usize) !void {
    var i: usize = 0;
    while (i < users.len) : (i += batch_size) {
        const end = @min(i + batch_size, users.len);
        const batch = users[i..end];

        var insert = try db.newInsert(User);
        defer insert.deinit();

        _ = try insert.values(batch).exec();
    }
}
```

---

## 附录 A: Zig 语言特性映射

### A.1 类型系统对比

| Go 类型 | Zig 类型 | 说明 |
|--------|---------|------|
| `int`, `int64` | `i64` | 有符号整数 |
| `uint`, `uint64` | `u64` | 无符号整数 |
| `float64` | `f64` | 浮点数 |
| `bool` | `bool` | 布尔值 |
| `string` | `[]const u8` | 字符串切片 |
| `[]T` | `[]T` | 切片 |
| `*T` | `*T` | 指针 |
| `error` | `error` | 错误类型 |
| `interface{}` | `anytype` | 任意类型 |
| `nil` | `null` | 空值 |
| `struct{}` | `struct {}` | 结构体 |

### A.2 关键字对比

| Go | Zig | 说明 |
|----|-----|------|
| `func` | `fn` | 函数 |
| `var` | `var` | 可变变量 |
| `const` | `const` | 不可变变量 |
| `type` | `type` | 类型别名 |
| `defer` | `defer` | 延迟执行 |
| `for range` | `for` | 循环 |
| `if err != nil` | `try` | 错误处理 |
| `switch` | `switch` | 分支 |
| `go` | N/A | 协程（Zig 没有） |
| N/A | `comptime` | 编译时执行 |
| N/A | `inline` | 内联 |

### A.3 内存管理对比

| Go | Zig |
|----|-----|
| 自动垃圾回收 | 手动管理 + Allocator |
| `new(T)` | `allocator.create(T)` |
| `make([]T, n)` | `allocator.alloc(T, n)` |
| 无需手动释放 | `defer allocator.free(mem)` |

---

## 附录 B: 完整示例程序

```zig
const std = @import("std");
const zorm = @import("zorm");

// 模型定义
const User = struct {
    id: i64 = 0,
    name: []const u8,
    email: []const u8,
    age: u32,
    created_at: i64,
    updated_at: i64,

    pub const table_name = "users";
};

const Post = struct {
    id: i64 = 0,
    user_id: i64,
    title: []const u8,
    content: []const u8,
    published: bool,
    created_at: i64,

    pub const table_name = "posts";
};

pub fn main() !void {
    // 初始化分配器
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 连接数据库
    const conn = try openPostgresConnection(
        allocator,
        "postgres://user:pass@localhost/testdb",
    );
    defer conn.close();

    // 创建 DB 实例
    const db = try zorm.DB.init(
        allocator,
        conn,
        .postgresql,
        .{
            .max_open_conns = 20,
            .max_idle_conns = 10,
        },
    );
    defer db.deinit();

    // 示例 1: 查询用户
    std.debug.print("\n=== Example 1: Select Users ===\n", .{});
    try selectUsers(allocator, db);

    // 示例 2: 插入用户
    std.debug.print("\n=== Example 2: Insert User ===\n", .{});
    try insertUser(allocator, db);

    // 示例 3: 更新用户
    std.debug.print("\n=== Example 3: Update User ===\n", .{});
    try updateUser(allocator, db);

    // 示例 4: 事务
    std.debug.print("\n=== Example 4: Transaction ===\n", .{});
    try transactionExample(allocator, db);

    // 示例 5: JOIN 查询
    std.debug.print("\n=== Example 5: JOIN Query ===\n", .{});
    try joinExample(allocator, db);
}

fn selectUsers(allocator: std.mem.Allocator, db: *zorm.DB) !void {
    var users = std.ArrayList(User).init(allocator);
    defer users.deinit();

    var query = try db.newSelect(User);
    defer query.deinit();

    try query
        .where("age >= ?", .{18})
        .orderBy("created_at", .desc)
        .limit(10)
        .scan(&users);

    std.debug.print("Found {d} users:\n", .{users.items.len});
    for (users.items) |user| {
        std.debug.print("  - {s} ({s})\n", .{ user.name, user.email });
    }
}

fn insertUser(allocator: std.mem.Allocator, db: *zorm.DB) !void {
    const user = User{
        .name = "Alice Smith",
        .email = "alice@example.com",
        .age = 28,
        .created_at = std.time.timestamp(),
        .updated_at = std.time.timestamp(),
    };

    var insert = try db.newInsert(User);
    defer insert.deinit();

    var inserted_users = std.ArrayList(User).init(allocator);
    defer inserted_users.deinit();

    try insert
        .value(user)
        .setReturning("*")
        .execReturning(&inserted_users);

    if (inserted_users.items.len > 0) {
        const inserted = inserted_users.items[0];
        std.debug.print("Inserted user with ID: {d}\n", .{inserted.id});
    }
}

fn updateUser(allocator: std.mem.Allocator, db: *zorm.DB) !void {
    _ = allocator;

    var update = try db.newUpdate(User);
    defer update.deinit();

    const result = try update
        .set("age = age + 1")
        .where("email = ?", .{"alice@example.com"})
        .exec();

    std.debug.print("Updated {d} rows\n", .{result.rows_affected});
}

fn transactionExample(allocator: std.mem.Allocator, db: *zorm.DB) !void {
    // 开启事务
    const tx = try db.beginTx();
    errdefer tx.rollback() catch {};

    // 在事务中插入用户
    const user = User{
        .name = "Bob Jones",
        .email = "bob@example.com",
        .age = 35,
        .created_at = std.time.timestamp(),
        .updated_at = std.time.timestamp(),
    };

    var insert_user = try tx.newInsert(User);
    defer insert_user.deinit();

    var inserted = std.ArrayList(User).init(allocator);
    defer inserted.deinit();

    try insert_user
        .value(user)
        .setReturning("*")
        .execReturning(&inserted);

    if (inserted.items.len == 0) {
        try tx.rollback();
        return error.InsertFailed;
    }

    // 插入关联的文章
    const post = Post{
        .user_id = inserted.items[0].id,
        .title = "My First Post",
        .content = "Hello, World!",
        .published = true,
        .created_at = std.time.timestamp(),
    };

    var insert_post = try tx.newInsert(Post);
    defer insert_post.deinit();

    _ = try insert_post.value(post).exec();

    // 提交事务
    try tx.commit();

    std.debug.print("Transaction completed successfully\n", .{});
}

fn joinExample(allocator: std.mem.Allocator, db: *zorm.DB) !void {
    const UserWithPostCount = struct {
        user_id: i64,
        user_name: []const u8,
        post_count: i64,
    };

    var results = std.ArrayList(UserWithPostCount).init(allocator);
    defer results.deinit();

    const sql =
        \\SELECT
        \\  u.id as user_id,
        \\  u.name as user_name,
        \\  COUNT(p.id) as post_count
        \\FROM users u
        \\LEFT JOIN posts p ON p.user_id = u.id
        \\GROUP BY u.id, u.name
        \\HAVING COUNT(p.id) > 0
        \\ORDER BY post_count DESC
        \\LIMIT 10
    ;

    var query = try db.newRaw(sql, .{});
    defer query.deinit();

    try query.scan(&results);

    std.debug.print("Users with posts:\n", .{});
    for (results.items) |result| {
        std.debug.print("  - {s}: {d} posts\n", .{
            result.user_name,
            result.post_count,
        });
    }
}

// 数据库连接辅助函数（简化示例）
fn openPostgresConnection(
    allocator: std.mem.Allocator,
    dsn: []const u8,
) !*anyopaque {
    _ = allocator;
    _ = dsn;
    // 实际实现会调用 libpq
    return undefined;
}
```

---

## 结语

本功能需求规格说明书为使用 **Zig 语言**实现 ZORM（参照 Bun ORM）提供了全面的指导。

**Zig 语言的优势**:
1. **零运行时开销** - comptime 消除抽象成本
2. **显式内存管理** - 完全控制性能
3. **强制错误处理** - 编译时安全保证
4. **跨平台支持** - 单一工具链，轻松交叉编译
5. **C 互操作性** - 直接调用数据库 C API

**与 Go 实现的关键区别**:
- 使用 Allocator 而非垃圾回收
- 使用 `!T` 错误联合而非 `error` 接口
- 使用 `comptime` 实现泛型而非接口
- 使用 `defer` 管理资源而非 `defer` 语句
- 显式内存管理而非自动管理

**实施建议**:
1. 从核心 DB 和 SELECT 查询开始（P0）
2. 充分利用 comptime 优化性能
3. 使用 testing allocator 检测内存泄漏
4. 编写全面的单元测试和集成测试
5. 提供丰富的示例和文档

**下一步工作**:
1. 详细的 C API 绑定设计（libpq, libmysqlclient, sqlite3）
2. 性能基准测试框架
3. 实现原型验证设计
4. CI/CD 配置（交叉编译测试）

---

**文档版本**: v2.0 (Zig Edition)
**作者**: Mary (Business Analyst)
**审核**: 待定
**批准**: 待定
**生成日期**: 2025-10-16
**目标语言**: Zig 0.15.2+
