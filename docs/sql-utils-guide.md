# ZORM SQL 生成工具使用指南

## 概述

ZORM 提供了一套完整的 SQL 生成工具函数，帮助开发者安全、高效地构建 SQL 语句，防止 SQL 注入攻击。

所有函数都支持多种数据库方言（PostgreSQL, MySQL, SQLite），并在编译时进行类型安全检查。

## API 参考

### 1. escapeIdentifier - 标识符转义

将 SQL 标识符（表名、列名等）转义为安全的格式。

**函数签名：**
```zig
pub fn escapeIdentifier(
    allocator: Allocator,
    comptime dialect: Dialect,
    identifier: []const u8,
) ![]const u8
```

**参数说明：**
- `allocator`: 内存分配器
- `dialect`: 数据库方言（`.postgresql`, `.mysql`, `.sqlite`）
- `identifier`: 需要转义的标识符

**返回值：**
- 转义后的标识符字符串（需要调用者释放内存）

**方言差异：**
- PostgreSQL/SQLite: 使用双引号 `"identifier"`
- MySQL: 使用反引号 `` `identifier` ``

**示例代码：**
```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // PostgreSQL
    const pg_escaped = try zorm.sql.escapeIdentifier(allocator, .postgresql, "user_table");
    defer allocator.free(pg_escaped);
    std.debug.print("PostgreSQL: {s}\n", .{pg_escaped}); // 输出: "user_table"

    // 包含特殊字符的标识符
    const special_escaped = try zorm.sql.escapeIdentifier(allocator, .postgresql, "user\"table");
    defer allocator.free(special_escaped);
    std.debug.print("With quotes: {s}\n", .{special_escaped}); // 输出: "user""table"

    // MySQL
    const mysql_escaped = try zorm.sql.escapeIdentifier(allocator, .mysql, "user_table");
    defer allocator.free(mysql_escaped);
    std.debug.print("MySQL: {s}\n", .{mysql_escaped}); // 输出: `user_table`
}
```

**最佳实践：**
- 总是转义用户输入的标识符
- 特别注意动态表名和列名的转义
- 使用 `defer` 确保内存被正确释放

---

### 2. escapeString - 字符串转义

将字符串转义为安全的 SQL 字符串字面量。

**函数签名：**
```zig
pub fn escapeString(
    allocator: Allocator,
    comptime dialect: Dialect,
    str: []const u8,
) ![]const u8
```

**参数说明：**
- `allocator`: 内存分配器
- `dialect`: 数据库方言
- `str`: 需要转义的字符串

**返回值：**
- 转义后的字符串字面量（包含单引号，需要调用者释放内存）

**转义规则：**
- 单引号 `'` → `''`
- 反斜杠 `\` → `\\` (MySQL 需要)
- NULL 字节 → `\0`
- 换行符 `\n` → `\n`
- 回车符 `\r` → `\r`
- 制表符 `\t` → `\t`

**示例代码：**
```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 简单字符串
    const simple = try zorm.sql.escapeString(allocator, .postgresql, "hello world");
    defer allocator.free(simple);
    std.debug.print("Simple: {s}\n", .{simple}); // 输出: 'hello world'

    // 包含单引号的字符串
    const with_quote = try zorm.sql.escapeString(allocator, .postgresql, "it's");
    defer allocator.free(with_quote);
    std.debug.print("With quote: {s}\n", .{with_quote}); // 输出: 'it''s'

    // 包含特殊字符的字符串
    const special = try zorm.sql.escapeString(allocator, .postgresql, "line1\nline2\ttab");
    defer allocator.free(special);
    std.debug.print("Special: {s}\n", .{special}); // 输出: 'line1\nline2\ttab'

    // MySQL 反斜杠转义
    const mysql_bs = try zorm.sql.escapeString(allocator, .mysql, "path\\to\\file");
    defer allocator.free(mysql_bs);
    std.debug.print("MySQL: {s}\n", .{mysql_bs}); // 输出: 'path\\\\to\\\\file'
}
```

**最佳实践：**
- 总是转义用户输入的字符串
- 注意 MySQL 的反斜杠转义规则
- 避免在 SQL 中直接拼接未转义的用户输入

---

### 3. generatePlaceholders - 占位符生成

生成指定数量的占位符数组。

**函数签名：**
```zig
pub fn generatePlaceholders(
    allocator: Allocator,
    comptime dialect: Dialect,
    count: usize,
    start_index: usize,
) ![]const []const u8

pub fn freePlaceholders(allocator: Allocator, placeholders: []const []const u8) void
```

**参数说明：**
- `allocator`: 内存分配器
- `dialect`: 数据库方言
- `count`: 占位符数量
- `start_index`: 起始索引（默认为 1）

**返回值：**
- 占位符字符串数组（需要使用 `freePlaceholders` 释放）

**方言差异：**
- PostgreSQL: `$1`, `$2`, `$3`, ...
- MySQL/SQLite: `?`, `?`, `?`, ...

**示例代码：**
```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // PostgreSQL 占位符
    const pg_phs = try zorm.sql.generatePlaceholders(allocator, .postgresql, 3, 1);
    defer zorm.sql.freePlaceholders(allocator, pg_phs);

    std.debug.print("PostgreSQL placeholders:\n", .{});
    for (pg_phs) |ph| {
        std.debug.print("  {s}\n", .{ph});
    }
    // 输出:
    //   $1
    //   $2
    //   $3

    // MySQL 占位符
    const mysql_phs = try zorm.sql.generatePlaceholders(allocator, .mysql, 3, 1);
    defer zorm.sql.freePlaceholders(allocator, mysql_phs);

    std.debug.print("MySQL placeholders:\n", .{});
    for (mysql_phs) |ph| {
        std.debug.print("  {s}\n", .{ph});
    }
    // 输出:
    //   ?
    //   ?
    //   ?

    // 使用偏移量
    const offset_phs = try zorm.sql.generatePlaceholders(allocator, .postgresql, 3, 5);
    defer zorm.sql.freePlaceholders(allocator, offset_phs);

    std.debug.print("With offset:\n", .{});
    for (offset_phs) |ph| {
        std.debug.print("  {s}\n", .{ph});
    }
    // 输出:
    //   $5
    //   $6
    //   $7
}
```

**最佳实践：**
- 使用占位符而非字符串拼接
- 记得使用 `freePlaceholders` 释放内存
- 当需要多个查询参数时使用 `start_index` 偏移

---

### 4. buildInClause - IN 子句构建

构建 SQL IN 子句。

**函数签名：**
```zig
pub fn buildInClause(
    allocator: Allocator,
    comptime dialect: Dialect,
    count: usize,
    start_index: usize,
) ![]const u8
```

**参数说明：**
- `allocator`: 内存分配器
- `dialect`: 数据库方言
- `count`: IN 子句中的值数量
- `start_index`: 起始占位符索引

**返回值：**
- IN 子句字符串（例如 `"IN ($1, $2, $3)"`）

**示例代码：**
```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // PostgreSQL IN 子句
    const pg_in = try zorm.sql.buildInClause(allocator, .postgresql, 3, 1);
    defer allocator.free(pg_in);
    std.debug.print("PostgreSQL: {s}\n", .{pg_in}); // 输出: IN ($1, $2, $3)

    // MySQL IN 子句
    const mysql_in = try zorm.sql.buildInClause(allocator, .mysql, 3, 1);
    defer allocator.free(mysql_in);
    std.debug.print("MySQL: {s}\n", .{mysql_in}); // 输出: IN (?, ?, ?)

    // 使用偏移量
    const offset_in = try zorm.sql.buildInClause(allocator, .postgresql, 3, 5);
    defer allocator.free(offset_in);
    std.debug.print("With offset: {s}\n", .{offset_in}); // 输出: IN ($5, $6, $7)

    // 单个值
    const single_in = try zorm.sql.buildInClause(allocator, .postgresql, 1, 1);
    defer allocator.free(single_in);
    std.debug.print("Single value: {s}\n", .{single_in}); // 输出: IN ($1)

    // 空 IN 子句
    const empty_in = try zorm.sql.buildInClause(allocator, .postgresql, 0, 1);
    defer allocator.free(empty_in);
    std.debug.print("Empty: {s}\n", .{empty_in}); // 输出: IN ()
}
```

**完整查询示例：**
```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn findUsersByIds(allocator: Allocator, db: *zorm.DB, ids: []const i64) !void {
    // 构建 IN 子句
    const in_clause = try zorm.sql.buildInClause(allocator, .postgresql, ids.len, 1);
    defer allocator.free(in_clause);

    // 构建完整 SQL
    const sql = try std.fmt.allocPrint(
        allocator,
        "SELECT * FROM users WHERE id {s}",
        .{in_clause}
    );
    defer allocator.free(sql);

    std.debug.print("SQL: {s}\n", .{sql});
    // 输出: SELECT * FROM users WHERE id IN ($1, $2, $3)

    // 执行查询（伪代码）
    // const result = try db.query(sql, ids);
    // ...
}
```

---

## 综合示例

### 动态查询构建

```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn buildDynamicQuery(allocator: Allocator) ![]const u8 {
    // 转义表名
    const table = try zorm.sql.escapeIdentifier(allocator, .postgresql, "users");
    defer allocator.free(table);

    // 转义列名
    const col_name = try zorm.sql.escapeIdentifier(allocator, .postgresql, "name");
    defer allocator.free(col_name);

    const col_age = try zorm.sql.escapeIdentifier(allocator, .postgresql, "age");
    defer allocator.free(col_age);

    // 转义字符串值
    const name_value = try zorm.sql.escapeString(allocator, .postgresql, "John's");
    defer allocator.free(name_value);

    // 构建 IN 子句
    const in_clause = try zorm.sql.buildInClause(allocator, .postgresql, 3, 2);
    defer allocator.free(in_clause);

    // 组装最终 SQL
    const sql = try std.fmt.allocPrint(
        allocator,
        "SELECT * FROM {s} WHERE {s} = {s} AND {s} {s}",
        .{ table, col_name, name_value, col_age, in_clause }
    );

    return sql;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sql = try buildDynamicQuery(allocator);
    defer allocator.free(sql);

    std.debug.print("Generated SQL:\n{s}\n", .{sql});
    // 输出: SELECT * FROM "users" WHERE "name" = 'John''s' AND "age" IN ($2, $3, $4)
}
```

### 批量插入

```zig
const std = @import("std");
const zorm = @import("zorm");

const User = struct {
    name: []const u8,
    email: []const u8,
};

pub fn buildBatchInsert(allocator: Allocator, users: []const User) ![]const u8 {
    var sql = std.ArrayList(u8).init(allocator);
    defer sql.deinit();

    const writer = sql.writer();

    // 表名
    const table = try zorm.sql.escapeIdentifier(allocator, .postgresql, "users");
    defer allocator.free(table);

    // 列名
    const col_name = try zorm.sql.escapeIdentifier(allocator, .postgresql, "name");
    defer allocator.free(col_name);

    const col_email = try zorm.sql.escapeIdentifier(allocator, .postgresql, "email");
    defer allocator.free(col_email);

    // 开始构建 SQL
    try writer.print("INSERT INTO {s} ({s}, {s}) VALUES ", .{ table, col_name, col_email });

    // 生成每行的占位符
    for (users, 0..) |_, i| {
        if (i > 0) try writer.writeAll(", ");

        const start_idx = i * 2 + 1;
        try writer.print("(${d}, ${d})", .{ start_idx, start_idx + 1 });
    }

    return sql.toOwnedSlice();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const users = [_]User{
        .{ .name = "Alice", .email = "alice@example.com" },
        .{ .name = "Bob", .email = "bob@example.com" },
        .{ .name = "Charlie", .email = "charlie@example.com" },
    };

    const sql = try buildBatchInsert(allocator, &users);
    defer allocator.free(sql);

    std.debug.print("Batch Insert SQL:\n{s}\n", .{sql});
    // 输出: INSERT INTO "users" ("name", "email") VALUES ($1, $2), ($3, $4), ($5, $6)
}
```

---

## 性能考虑

1. **内存管理**: 所有函数都返回新分配的字符串，调用者负责释放内存
2. **编译时优化**: 方言相关的逻辑在编译时确定，零运行时开销
3. **快速路径**: 不需要转义时使用优化的快速路径
4. **批量操作**: 对于大量数据，使用批量操作可以减少内存分配

## 安全最佳实践

1. **总是使用占位符**: 避免直接拼接用户输入到 SQL
2. **转义标识符**: 动态表名和列名必须转义
3. **验证输入**: 在转义之前验证用户输入的合法性
4. **使用参数绑定**: 配合数据库驱动的参数绑定功能使用

---

## 错误处理

所有函数都可能返回以下错误：
- `error.OutOfMemory`: 内存分配失败

示例错误处理：
```zig
const escaped = zorm.sql.escapeIdentifier(allocator, .postgresql, "users") catch |err| {
    std.log.err("Failed to escape identifier: {}", .{err});
    return err;
};
defer allocator.free(escaped);
```

---

## 进一步阅读

- [ZORM 架构文档](architecture.md)
- [方言系统文档](dialect-system.md)
- [查询构建器指南](query-builder-guide.md)
