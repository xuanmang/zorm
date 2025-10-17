# 数据库方言差异说明

本文档详细说明 ZORM 支持的各个数据库方言之间的差异。所有方言特性检测都在编译时完成，实现零运行时开销。

## 支持的数据库方言

ZORM 当前支持以下数据库方言:

- **PostgreSQL** (`.postgresql`)
- **MySQL** (`.mysql`)
- **SQLite** (`.sqlite`)

## 特性支持对比表

| 特性 | PostgreSQL | MySQL | SQLite |
|------|-----------|-------|--------|
| **RETURNING** | ✅ | ❌ | ✅ (3.35.0+) |
| **CTE** | ✅ | ✅ (8.0+) | ✅ |
| **Arrays** | ✅ | ❌ | ❌ |
| **JSON/JSONB** | ✅ | ✅ (JSON) | ✅ |
| **ON CONFLICT** | ✅ | ❌ | ✅ |
| **Window Functions** | ✅ | ✅ (8.0+) | ✅ (3.25.0+) |
| **LATERAL JOIN** | ✅ | ❌ | ❌ |
| **UPSERT** | ✅ | ✅ (ON DUPLICATE) | ✅ |
| **generate_series** | ✅ | ❌ | ✅ |
| **LISTEN/NOTIFY** | ✅ | ❌ | ❌ |

## 占位符语法

不同数据库使用不同的参数占位符语法:

| 方言 | 占位符语法 | 示例 |
|------|----------|------|
| PostgreSQL | `$1`, `$2`, `$3`, ... | `SELECT * FROM users WHERE id = $1` |
| MySQL | `?`, `?`, `?`, ... | `SELECT * FROM users WHERE id = ?` |
| SQLite | `?`, `?`, `?`, ... | `SELECT * FROM users WHERE id = ?` |

### 代码示例

```zig
const std = @import("std");
const Dialect = @import("zorm").Dialect;

// 编译时占位符生成
comptime {
    const pg_ph1 = Dialect.postgresql.placeholder(1);  // "$1"
    const pg_ph2 = Dialect.postgresql.placeholder(2);  // "$2"

    const mysql_ph = Dialect.mysql.placeholder(1);     // "?"
    const sqlite_ph = Dialect.sqlite.placeholder(1);   // "?"
}
```

## 标识符引用语法

不同数据库使用不同的标识符引号字符:

| 方言 | 左引号 | 右引号 | 示例 |
|------|-------|-------|------|
| PostgreSQL | `"` | `"` | `"users"`, `"first_name"` |
| MySQL | `` ` `` | `` ` `` | `` `users` ``, `` `first_name` `` |
| SQLite | `"` | `"` | `"users"`, `"first_name"` |

### 代码示例

```zig
const Dialect = @import("zorm").Dialect;

// 编译时标识符引用
comptime {
    const pg_quoted = Dialect.postgresql.quoteIdentifier("users");
    // 结果: "users"

    const mysql_quoted = Dialect.mysql.quoteIdentifier("users");
    // 结果: `users`
}
```

## UPSERT 语法差异

不同数据库的 UPSERT 操作使用不同的语法:

### PostgreSQL - ON CONFLICT

```sql
INSERT INTO users (id, name, email)
VALUES (1, 'Alice', 'alice@example.com')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    email = EXCLUDED.email;
```

### MySQL - ON DUPLICATE KEY UPDATE

```sql
INSERT INTO users (id, name, email)
VALUES (1, 'Alice', 'alice@example.com')
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    email = VALUES(email);
```

### SQLite - ON CONFLICT

```sql
INSERT INTO users (id, name, email)
VALUES (1, 'Alice', 'alice@example.com')
ON CONFLICT (id) DO UPDATE SET
    name = excluded.name,
    email = excluded.email;
```


### 代码示例

```zig
const Dialect = @import("zorm").Dialect;

// 编译时获取 UPSERT 子句
comptime {
    const pg_upsert = Dialect.postgresql.upsertClause();
    // 结果: "ON CONFLICT"

    const mysql_upsert = Dialect.mysql.upsertClause();
    // 结果: "ON DUPLICATE KEY UPDATE"
}
```

## LIMIT/OFFSET 语法差异

### PostgreSQL/MySQL/SQLite

```sql
SELECT * FROM users LIMIT 10 OFFSET 20;
```


## 自动递增列语法

| 方言 | 语法 | 示例 |
|------|------|------|
| PostgreSQL | `SERIAL` | `id SERIAL PRIMARY KEY` |
| MySQL | `AUTO_INCREMENT` | `id INT AUTO_INCREMENT PRIMARY KEY` |
| SQLite | `AUTOINCREMENT` | `id INTEGER PRIMARY KEY AUTOINCREMENT` |

### 代码示例

```zig
const Dialect = @import("zorm").Dialect;

// 编译时获取自动递增语法
comptime {
    const pg_auto = Dialect.postgresql.autoIncrementClause();
    // 结果: "SERIAL"

    const mysql_auto = Dialect.mysql.autoIncrementClause();
    // 结果: "AUTO_INCREMENT"
}
```

## 当前时间戳函数

| 方言 | 函数 |
|------|------|
| PostgreSQL | `CURRENT_TIMESTAMP` |
| MySQL | `CURRENT_TIMESTAMP` |
| SQLite | `CURRENT_TIMESTAMP` |

### 代码示例

```zig
const Dialect = @import("zorm").Dialect;

// 编译时获取当前时间戳函数
comptime {
    const pg_ts = Dialect.postgresql.currentTimestamp();
    // 结果: "CURRENT_TIMESTAMP"

    const mysql_ts = Dialect.mysql.currentTimestamp();
    // 结果: "CURRENT_TIMESTAMP"
}
```

## 编译时特性检测

ZORM 的所有方言特性检测都在编译时完成,确保零运行时开销:

```zig
const std = @import("std");
const Dialect = @import("zorm").Dialect;

pub fn buildQuery(comptime dialect: Dialect) []const u8 {
    var query = "INSERT INTO users (name, email) VALUES ";
    query = query ++ dialect.placeholder(1);
    query = query ++ ", ";
    query = query ++ dialect.placeholder(2);

    // 编译时检查是否支持 RETURNING
    if (comptime dialect.supportsReturning()) {
        query = query ++ " RETURNING id";
    }

    return query;
}

// 编译时生成不同的查询
comptime {
    const pg_query = buildQuery(.postgresql);
    // 结果: "INSERT INTO users (name, email) VALUES $1, $2 RETURNING id"

    const mysql_query = buildQuery(.mysql);
    // 结果: "INSERT INTO users (name, email) VALUES ?, ?"
}
```

## 特性检测 API

ZORM 提供两种方式检测数据库特性:

### 1. 通用 `supports()` 方法

```zig
pub fn supports(comptime self: Dialect, comptime feature: Feature) bool
```

**示例:**

```zig
if (comptime Dialect.postgresql.supports(.returning)) {
    // PostgreSQL 支持 RETURNING
}

if (comptime Dialect.mysql.supports(.cte)) {
    // MySQL 8.0+ 支持 CTE
}
```

### 2. 便捷的特性检测函数

```zig
pub fn supportsReturning(comptime self: Dialect) bool
pub fn supportsOnConflict(comptime self: Dialect) bool
pub fn supportsCTE(comptime self: Dialect) bool
pub fn supportsJSONB(comptime self: Dialect) bool
```

**示例:**

```zig
if (comptime Dialect.postgresql.supportsReturning()) {
    // PostgreSQL 支持 RETURNING
}

if (comptime Dialect.sqlite.supportsOnConflict()) {
    // SQLite 支持 ON CONFLICT
}
```

## 最佳实践

### 1. 优先使用 comptime 检测

```zig
// ✅ 推荐: 编译时检测
pub fn buildInsert(comptime dialect: Dialect, ...) ![]const u8 {
    var query = "INSERT INTO users ...";

    if (comptime dialect.supportsReturning()) {
        query = query ++ " RETURNING id";
    }

    return query;
}

// ❌ 不推荐: 运行时检测
pub fn buildInsert(dialect: Dialect, ...) ![]const u8 {
    // 这会产生运行时分支
    if (dialect.supportsReturning()) { ... }
}
```

### 2. 使用类型化的方言参数

```zig
// ✅ 推荐: 编译时方言
pub fn Query(comptime dialect: Dialect) type {
    return struct {
        pub fn build(self: *Self) ![]const u8 {
            // dialect 在编译时已知
            const ph = comptime dialect.placeholder(1);
            ...
        }
    };
}

// ❌ 不推荐: 运行时方言
pub const Query = struct {
    dialect: Dialect,  // 运行时值
    ...
};
```

### 3. 利用编译时字符串生成

```zig
// ✅ 推荐: 编译时生成
pub fn placeholder(comptime dialect: Dialect, index: usize) []const u8 {
    return comptime switch (dialect) {
        .postgresql => std.fmt.comptimePrint("${d}", .{index}),
        .mysql => "?",
        ...
    };
}
```

## 版本注意事项

一些特性对数据库版本有要求:

- **MySQL CTE**: 需要 MySQL 8.0+
- **MySQL Window Functions**: 需要 MySQL 8.0+
- **SQLite RETURNING**: 需要 SQLite 3.35.0+
- **SQLite Window Functions**: 需要 SQLite 3.25.0+

ZORM 的特性检测基于最新稳定版本,使用旧版本数据库时请确保版本兼容性。

**注意**: ZORM 仅支持 PostgreSQL, MySQL 和 SQLite 三种数据库，不计划支持其他数据库。

## 相关文档

- [API 文档](../zig-out/docs/index.html) - 完整的 API 文档
- [功能需求规格说明书](functional_spec.md) - 详细的功能定义
- [源代码](../src/dialect/dialect.zig) - 方言系统实现

---

**最后更新**: 2025-01-17
**ZORM 版本**: 0.1.0-alpha
