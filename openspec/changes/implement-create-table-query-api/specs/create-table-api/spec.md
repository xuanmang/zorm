# Spec: CREATE TABLE Query Builder API

## ADDED Requirements

### Requirement: API 提供 db.newCreateTable(T) 方法创建查询构建器

系统 MUST 提供 `db.newCreateTable(T)` 方法，接受 Zig 结构体类型 T 作为参数，返回 CREATE TABLE 查询构建器实例。

**依据**: PRD AC3.1.1

#### Scenario: 使用 newCreateTable 创建查询构建器

**Given** 数据库实例 `db` 已初始化
**And** 定义了 Zig 结构体 `User`:
```zig
const User = struct {
    id: i64,
    name: []const u8,
    pub const table_name = "users";
};
```

**When** 调用 `var query = try db.newCreateTable(User);`

**Then** 返回 `CreateTableQuery(User, .postgresql)` 类型的指针
**And** 查询构建器的表名为 "users"
**And** 可以调用 `defer query.deinit();` 释放资源

---

### Requirement: 自动从 Zig 结构体字段生成列定义

系统 MUST 自动从 Zig 结构体的字段生成对应的 PostgreSQL 列定义，包括列名和列类型。

**依据**: PRD AC3.1.2

#### Scenario: 自动生成基础类型列定义

**Given** 定义了包含基础类型字段的结构体:
```zig
const Product = struct {
    id: i64,
    name: []const u8,
    price: f64,
    in_stock: bool,
    pub const table_name = "products";
};
```

**When** 创建 `CreateTableQuery(Product)` 并调用 `build()`

**Then** 生成的 SQL 包含:
- `id BIGINT` 列定义
- `name TEXT` 列定义
- `price DOUBLE PRECISION` 列定义
- `in_stock BOOLEAN` 列定义

#### Scenario: 自动生成可选类型列定义

**Given** 定义了包含可选类型字段的结构体:
```zig
const User = struct {
    id: i64,
    name: []const u8,
    bio: ?[]const u8,
    pub const table_name = "users";
};
```

**When** 创建 `CreateTableQuery(User)` 并调用 `build()`

**Then** 生成的 SQL 中:
- `id BIGINT` 包含 `NOT NULL` 或 `PRIMARY KEY`
- `name TEXT` 包含 `NOT NULL`
- `bio TEXT` 不包含 `NOT NULL`（允许 NULL）

---

### Requirement: 支持 Zig 类型到 PostgreSQL 类型的完整映射

系统 MUST 支持 PRD AC3.1.3 中定义的所有 Zig 原生类型到 PostgreSQL 类型的映射。

**依据**: PRD AC3.1.3

#### Scenario: 整数类型映射

**Given** 定义了包含不同整数类型的结构体:
```zig
const Numbers = struct {
    tiny: i8,
    small: i16,
    medium: i32,
    large: i64,
    utiny: u8,
    usmall: u16,
    umedium: u32,
    ularge: u64,
    pub const table_name = "numbers";
};
```

**When** 创建 `CreateTableQuery(Numbers)` 并调用 `build()`

**Then** 生成的 SQL 包含:
- `tiny SMALLINT NOT NULL`
- `small SMALLINT NOT NULL`
- `medium SMALLINT NOT NULL`
- `large BIGINT NOT NULL`
- `utiny INTEGER NOT NULL`
- `usmall INTEGER NOT NULL`
- `umedium INTEGER NOT NULL`
- `ularge BIGINT NOT NULL`

#### Scenario: 浮点类型映射

**Given** 定义了包含浮点类型的结构体:
```zig
const Floats = struct {
    single: f32,
    double: f64,
    pub const table_name = "floats";
};
```

**When** 创建 `CreateTableQuery(Floats)` 并调用 `build()`

**Then** 生成的 SQL 包含:
- `single REAL NOT NULL`
- `double DOUBLE PRECISION NOT NULL`

#### Scenario: 布尔和文本类型映射

**Given** 定义了包含布尔和文本类型的结构体:
```zig
const Misc = struct {
    active: bool,
    description: []const u8,
    pub const table_name = "misc";
};
```

**When** 创建 `CreateTableQuery(Misc)` 并调用 `build()`

**Then** 生成的 SQL 包含:
- `active BOOLEAN NOT NULL`
- `description TEXT NOT NULL`

---

### Requirement: 自动检测主键字段

系统 MUST 自动检测主键字段，当字段名为 `id` 时，自动设置为主键并添加 PRIMARY KEY 约束。

**依据**: PRD AC3.1.4

#### Scenario: 字段名为 id 自动设置为主键

**Given** 定义了包含 `id` 字段的结构体:
```zig
const User = struct {
    id: i64,
    name: []const u8,
    pub const table_name = "users";
};
```

**When** 创建 `CreateTableQuery(User)` 并调用 `build()`

**Then** 生成的 SQL 包含 `id BIGINT PRIMARY KEY` 或 `id BIGSERIAL PRIMARY KEY`
**And** `id` 字段隐含 `NOT NULL` 约束（主键必须非空）

#### Scenario: 非 id 字段不自动设置为主键

**Given** 定义了不包含 `id` 字段的结构体:
```zig
const Config = struct {
    key: []const u8,
    value: []const u8,
    pub const table_name = "config";
};
```

**When** 创建 `CreateTableQuery(Config)` 并调用 `build()`

**Then** 生成的 SQL 不包含 `PRIMARY KEY` 约束
**And** 所有字段都包含 `NOT NULL` 约束

---

### Requirement: 可选类型自动省略 NOT NULL 约束

系统 MUST 确保当字段类型为可选类型（`?T`）时，生成的列定义允许 NULL，不添加 NOT NULL 约束。

**依据**: PRD AC3.1.5

#### Scenario: 可选类型字段允许 NULL

**Given** 定义了包含多个可选字段的结构体:
```zig
const User = struct {
    id: i64,
    name: []const u8,
    email: ?[]const u8,
    bio: ?[]const u8,
    age: ?u32,
    pub const table_name = "users";
};
```

**When** 创建 `CreateTableQuery(User)` 并调用 `build()`

**Then** 生成的 SQL 中:
- `id` 和 `name` 包含 `NOT NULL` 约束
- `email`, `bio`, `age` 不包含 `NOT NULL` 约束
**And** 可选字段的 SQL 类型与对应的非可选类型相同（如 `email TEXT`, `age INTEGER`）

#### Scenario: 非可选类型字段强制 NOT NULL

**Given** 定义了所有非可选字段的结构体:
```zig
const Product = struct {
    id: i64,
    name: []const u8,
    price: f64,
    pub const table_name = "products";
};
```

**When** 创建 `CreateTableQuery(Product)` 并调用 `build()`

**Then** 所有非主键字段的 SQL 定义都包含 `NOT NULL` 约束

---

### Requirement: 提供 ifNotExists 方法添加 IF NOT EXISTS 子句

系统 MUST 提供 `ifNotExists()` 方法，用于在 CREATE TABLE 语句中添加 IF NOT EXISTS 子句，防止表已存在时报错。

**依据**: PRD AC3.1.6

#### Scenario: 调用 ifNotExists 添加 IF NOT EXISTS

**Given** 创建了查询构建器 `query = db.newCreateTable(User)`

**When** 调用 `query.ifNotExists()`

**Then** 返回 `*CreateTableQuery` 指针（支持链式调用）
**And** 后续调用 `build()` 生成的 SQL 包含 `CREATE TABLE IF NOT EXISTS users`

#### Scenario: 不调用 ifNotExists 则不包含 IF NOT EXISTS

**Given** 创建了查询构建器 `query = db.newCreateTable(User)`

**When** 直接调用 `build()` 而不调用 `ifNotExists()`

**Then** 生成的 SQL 为 `CREATE TABLE users (...)`
**And** 不包含 `IF NOT EXISTS` 子句

---

### Requirement: 提供 exec 方法执行 DDL 语句

系统 MUST 提供 `exec()` 方法，用于执行生成的 CREATE TABLE DDL 语句。

**依据**: PRD AC3.1.7

#### Scenario: 调用 exec 执行 CREATE TABLE

**Given** 创建了查询构建器并配置完成:
```zig
var query = try db.newCreateTable(User);
defer query.deinit();
_ = query.ifNotExists();
```

**When** 调用 `try query.exec()`

**Then** 在数据库中创建 `users` 表
**And** 如果表已存在，不抛出错误（因为使用了 IF NOT EXISTS）
**And** 方法返回 `void` 或成功完成

#### Scenario: exec 执行失败时返回错误

**Given** 创建了查询构建器但未使用 IF NOT EXISTS:
```zig
var query = try db.newCreateTable(User);
defer query.deinit();
```
**And** 数据库中已存在 `users` 表

**When** 调用 `try query.exec()`

**Then** 抛出 `error.TableAlreadyExists` 或相关数据库错误
**And** 表不会被重复创建

---

### Requirement: 支持完整的使用示例

系统 MUST 支持 PRD AC3.1.8 中定义的完整使用示例，包括所有类型映射和 DDL 执行。

**依据**: PRD AC3.1.8

#### Scenario: PRD 示例代码可编译并执行

**Given** PRD 中的示例代码:
```zig
const User = struct {
    id: i64,              // PRIMARY KEY, BIGINT NOT NULL
    name: []const u8,     // TEXT NOT NULL
    email: []const u8,    // TEXT NOT NULL
    age: u32,             // INTEGER NOT NULL
    bio: ?[]const u8,     // TEXT (NULL 允许)
    is_active: bool,      // BOOLEAN NOT NULL
    created_at: i64,      // BIGINT NOT NULL

    pub const table_name = "users";
};

var create = try db.newCreateTable(User);
defer create.deinit();

try create
    .ifNotExists()
    .exec();
```

**When** 编译并执行上述代码

**Then** 代码成功编译
**And** 执行后在数据库中创建 `users` 表
**And** 生成的 SQL 为:
```sql
CREATE TABLE IF NOT EXISTS users (
    id BIGINT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    age INTEGER NOT NULL,
    bio TEXT,
    is_active BOOLEAN NOT NULL,
    created_at BIGINT NOT NULL
)
```

#### Scenario: 测试覆盖所有 AC 场景

**Given** 编写了覆盖所有 AC 的单元测试

**When** 运行 `zig build test`

**Then** 所有测试通过
**And** 测试覆盖率达到 80%+
**And** 无内存泄漏（使用 `std.testing.allocator` 验证）

---

### Requirement: 提供清晰的 API 文档和示例程序

系统 MUST 提供完整的 API 文档和可运行的示例程序，帮助用户快速上手。

**依据**: PRD NFR5（API 文档覆盖率 100%）

#### Scenario: API 文档完整且准确

**Given** 查看 `src/query/query.zig` 中的 `CreateTableQuery` 文档

**Then** 每个公共方法都包含文档注释
**And** 文档包含方法说明、参数说明、返回值说明
**And** 文档包含可运行的示例代码

#### Scenario: 示例程序可运行

**Given** 示例程序 `examples/schema.zig` 存在

**When** 运行 `zig build run-example-schema`

**Then** 程序成功执行
**And** 输出演示了 CREATE TABLE 的完整使用场景
**And** 示例代码包含详细注释说明
