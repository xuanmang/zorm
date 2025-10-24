# create-index-query-api Specification

## Purpose
TBD - created by archiving change implement-create-index-query-api. Update Purpose after archive.
## Requirements
### Requirement: 提供类型安全的 CREATE INDEX 查询构建器

系统 SHALL 提供 `db.newCreateIndex(T)` API 用于创建类型安全的 CREATE INDEX 查询构建器，其中 T 是目标表的 Zig 结构体类型。构建器 SHALL 自动从结构体推断表名。

#### Scenario: 创建基本索引

- **GIVEN** 用户有一个 User 结构体类型
- **WHEN** 用户调用 `db.newCreateIndex(User)`
- **THEN** 返回一个绑定到 users 表的 CreateIndexQuery 实例

#### Scenario: 自动推断表名

- **GIVEN** User 结构体定义了 `pub const table_name = "users"`
- **WHEN** 用户创建 CreateIndexQuery
- **THEN** 查询构建器使用 "users" 作为表名

---

### Requirement: 支持索引名称设置

系统 SHALL 提供 `.index(name)` 方法用于指定索引名称，该方法 SHALL 返回 self 指针以支持链式调用。

#### Scenario: 设置索引名称

- **GIVEN** 用户创建了 CreateIndexQuery 实例
- **WHEN** 用户调用 `.index("idx_users_email")`
- **THEN** 索引名称设置为 "idx_users_email"
- **AND** 方法返回 self 指针

#### Scenario: 未设置索引名称时构建失败

- **GIVEN** 用户创建了 CreateIndexQuery 但未调用 `.index()`
- **WHEN** 用户调用 `.build()` 或 `.exec()`
- **THEN** 返回 `error.IndexNameRequired` 错误

---

### Requirement: 支持添加索引列

系统 SHALL 提供 `.column(col)` 方法用于添加索引列，SHALL 支持多次调用以创建复合索引。方法 SHALL 接受列名字符串或表达式字符串。

#### Scenario: 添加单列索引

- **GIVEN** 用户创建了 CreateIndexQuery 实例
- **WHEN** 用户调用 `.column("email")`
- **THEN** "email" 列被添加到索引列列表
- **AND** 方法返回 self 指针

#### Scenario: 创建复合索引

- **GIVEN** 用户创建了 CreateIndexQuery 实例
- **WHEN** 用户依次调用 `.column("status")` 和 `.column("created_at")`
- **THEN** 索引包含两列：status 和 created_at（顺序保持）

#### Scenario: 支持表达式索引

- **GIVEN** 用户需要创建基于表达式的索引
- **WHEN** 用户调用 `.column("LOWER(email)")`
- **THEN** 索引使用表达式 "LOWER(email)"
- **AND** 生成的 SQL 为 `CREATE INDEX ... ON ... (LOWER(email))`

#### Scenario: 未添加列时构建失败

- **GIVEN** 用户创建了 CreateIndexQuery 但未调用 `.column()`
- **WHEN** 用户调用 `.build()` 或 `.exec()`
- **THEN** 返回 `error.ColumnsRequired` 错误

---

### Requirement: 支持唯一索引创建

系统 SHALL 提供 `.unique()` 方法用于标记索引为唯一索引，SHALL 生成 `CREATE UNIQUE INDEX` SQL 语句。

#### Scenario: 创建唯一索引

- **GIVEN** 用户创建了 CreateIndexQuery 实例
- **WHEN** 用户调用 `.unique()`
- **THEN** 索引标记为唯一索引
- **AND** 生成的 SQL 包含 "UNIQUE" 关键字

#### Scenario: 默认为非唯一索引

- **GIVEN** 用户创建了 CreateIndexQuery 但未调用 `.unique()`
- **WHEN** 用户构建 SQL
- **THEN** 生成的 SQL 不包含 "UNIQUE" 关键字

---

### Requirement: 支持 IF NOT EXISTS 子句

系统 SHALL 提供 `.ifNotExists()` 方法用于添加 `IF NOT EXISTS` 子句，避免索引已存在时报错。

#### Scenario: 添加 IF NOT EXISTS 子句

- **GIVEN** 用户创建了 CreateIndexQuery 实例
- **WHEN** 用户调用 `.ifNotExists()`
- **THEN** 生成的 SQL 包含 "IF NOT EXISTS" 子句
- **AND** 索引已存在时不会报错

#### Scenario: PostgreSQL 方言支持

- **GIVEN** 使用 PostgreSQL 方言
- **WHEN** 用户调用 `.ifNotExists()`
- **THEN** 生成的 SQL 为 `CREATE INDEX IF NOT EXISTS ...`

---

### Requirement: 支持部分索引（WHERE 条件）

系统 SHALL 提供 `.where(condition)` 方法用于添加 WHERE 子句，创建部分索引（仅索引满足条件的行）。

#### Scenario: 创建部分索引

- **GIVEN** 用户创建了 CreateIndexQuery 实例
- **WHEN** 用户调用 `.where("is_active = true")`
- **THEN** 生成的 SQL 包含 `WHERE is_active = true` 子句

#### Scenario: 部分索引性能优化

- **GIVEN** 用户需要仅为活跃用户创建索引
- **WHEN** 用户调用 `.column("email").where("is_active = true")`
- **THEN** 索引仅包含 is_active 为 true 的行
- **AND** 减少索引大小和维护开销

---

### Requirement: 支持构建和执行 SQL

系统 SHALL 提供 `.build()` 方法生成 SQL 字符串，以及 `.exec()` 方法直接执行 DDL 语句。

#### Scenario: 构建 SQL 字符串

- **GIVEN** 用户配置了完整的索引参数
- **WHEN** 用户调用 `.build()`
- **THEN** 返回格式正确的 CREATE INDEX SQL 字符串
- **AND** 调用者负责释放返回的字符串内存

#### Scenario: 执行索引创建

- **GIVEN** 用户配置了完整的索引参数
- **WHEN** 用户调用 `.exec()`
- **THEN** SQL 在数据库中执行
- **AND** 成功时不返回错误
- **AND** 失败时返回数据库错误

#### Scenario: 生成 PostgreSQL 标准 SQL

- **GIVEN** 使用 PostgreSQL 方言
- **WHEN** 用户构建简单索引 SQL
- **THEN** 生成格式为 `CREATE INDEX idx_name ON table_name (column1, column2)`

---

### Requirement: 支持链式调用（Fluent Interface）

所有配置方法 SHALL 返回 `*Self` 指针，SHALL 支持链式调用以提升代码可读性。

#### Scenario: 链式调用配置

- **GIVEN** 用户创建了 CreateIndexQuery 实例
- **WHEN** 用户编写链式调用代码：
  ```zig
  try query
      .index("idx_users_email")
      .column("email")
      .unique()
      .ifNotExists()
      .exec();
  ```
- **THEN** 所有配置方法正确应用
- **AND** 代码简洁易读

---

### Requirement: 显式内存管理

系统 SHALL 使用 Zig Allocator 模式进行显式内存管理，SHALL 提供 `deinit()` 方法释放资源，SHALL 支持 `defer` 清理模式。

#### Scenario: 资源释放

- **GIVEN** 用户创建了 CreateIndexQuery 实例
- **WHEN** 用户调用 `query.deinit()`
- **THEN** 所有分配的内存被释放
- **AND** 无内存泄漏

#### Scenario: defer 模式

- **GIVEN** 用户使用 defer 管理资源
- **WHEN** 用户编写代码：
  ```zig
  var query = try db.newCreateIndex(User);
  defer query.deinit();
  // ... 使用 query
  ```
- **THEN** 作用域结束时自动调用 deinit()
- **AND** 错误路径也正确清理资源

---

### Requirement: 完整的错误处理

系统 SHALL 对所有可能失败的操作返回错误联合类型（`!T`），强制调用者处理错误。错误消息 SHALL 清晰明确，包含足够的上下文信息。

#### Scenario: 必需参数缺失错误

- **GIVEN** 用户未提供索引名称或列
- **WHEN** 用户调用 `.build()` 或 `.exec()`
- **THEN** 返回明确的错误类型（`error.IndexNameRequired` 或 `error.ColumnsRequired`）
- **AND** 错误消息包含缺失参数的信息

#### Scenario: 数据库执行错误

- **GIVEN** 索引名称已存在且未使用 IF NOT EXISTS
- **WHEN** 用户调用 `.exec()`
- **THEN** 返回数据库错误
- **AND** 错误消息包含冲突的索引名称

---

### Requirement: 完整的测试覆盖

系统 SHALL 提供完整的单元测试和集成测试，覆盖所有 API 方法和错误场景。

#### Scenario: 单元测试覆盖所有方法

- **GIVEN** CreateIndexQuery 实现完成
- **WHEN** 运行单元测试
- **THEN** 所有公共方法都有对应的单元测试
- **AND** 覆盖率达到 80% 以上

#### Scenario: 集成测试验证真实场景

- **GIVEN** 真实的 PostgreSQL 数据库连接
- **WHEN** 执行集成测试
- **THEN** 所有索引类型（普通、唯一、复合、部分、表达式）都能成功创建
- **AND** 索引在数据库中正确生效

#### Scenario: 内存泄漏检测

- **GIVEN** 使用 `std.testing.allocator` 运行测试
- **WHEN** 执行所有测试
- **THEN** 无内存泄漏报告
- **AND** 所有资源正确释放

