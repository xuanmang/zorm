# Raw SQL Query API

## ADDED Requirements

### Requirement: RawQuery Initialization
**ID**: `RSQ-001`
**Priority**: P0
**Status**: Implemented

The system MUST provide `DB.newRaw()` and `Tx.newRaw()` methods to create Raw SQL queries, accepting SQL statements and parameter tuples, and returning RawQuery instances.

**Rationale**: 提供统一的 Raw SQL 查询创建接口，确保参数绑定的类型安全性。

#### Scenario: Create Raw SQL query from DB instance
**Given** 一个已初始化的 DB 实例
**When** 调用 `db.newRaw(sql, args)` 其中 sql 包含 `$1, $2, ...` 占位符
**Then** 返回一个有效的 RawQuery 实例
**And** 参数元组被正确转换为 QueryArg 数组
**And** 占位符数量与参数数量匹配

#### Scenario: Create Raw SQL query from transaction
**Given** 一个活跃的事务实例
**When** 调用 `tx.newRaw(sql, args)` 创建 Raw SQL 查询
**Then** 返回的 RawQuery 使用事务的数据库连接
**And** 查询执行在事务上下文中

#### Scenario: Parameter binding with PostgreSQL placeholders
**Given** SQL 语句 `"SELECT * FROM users WHERE age > $1 AND status = $2"`
**When** 调用 `db.newRaw(sql, .{18, "active"})` 创建查询
**Then** 参数 18 和 "active" 正确绑定到 $1 和 $2 占位符
**And** 防止 SQL 注入攻击

---

### Requirement: Execute DML Statements
**ID**: `RSQ-002`
**Priority**: P0
**Status**: Implemented

RawQuery MUST provide an `exec()` method to execute DML statements (INSERT/UPDATE/DELETE), returning a RawResult containing the number of affected rows.

**Rationale**: 支持执行修改数据的 SQL 语句并返回执行结果。

#### Scenario: Execute UPDATE statement
**Given** 一个 RawQuery 实例包含 UPDATE SQL
**When** 调用 `query.exec()` 执行查询
**Then** 返回 RawResult 包含正确的 rows_affected 数量
**And** 数据库中的数据被成功更新

#### Scenario: Execute DELETE statement
**Given** 一个 RawQuery 实例包含 DELETE SQL
**When** 调用 `query.exec()` 执行删除
**Then** 返回 RawResult 包含被删除的行数
**And** 数据从数据库中被正确删除

#### Scenario: Execute INSERT statement
**Given** 一个 RawQuery 实例包含 INSERT SQL
**When** 调用 `query.exec()` 执行插入
**Then** 返回 RawResult 包含插入的行数
**And** 新数据被成功添加到数据库

---

### Requirement: Scan Query Results to ArrayList
**ID**: `RSQ-003`
**Priority**: P0
**Status**: Implemented

RawQuery MUST provide a `scan()` method to execute SELECT queries and scan results into an ArrayList, supporting arbitrary Zig struct types.

**Rationale**: 提供类型安全的查询结果扫描机制，将数据库行映射到 Zig 结构体。

#### Scenario: Scan multiple rows to ArrayList
**Given** 一个 RawQuery 实例包含 SELECT SQL
**And** 一个空的 `std.ArrayList(T)` 结果容器
**When** 调用 `query.scan(T, &dest)` 扫描结果
**Then** 所有查询结果行被正确映射到结构体 T
**And** dest ArrayList 包含所有结果行
**And** 字段类型自动转换（数据库类型 → Zig 类型）

#### Scenario: Scan complex query with JOINs
**Given** 一个包含 JOIN 的复杂 SELECT 查询
**And** 一个包含多表字段的自定义结构体类型
**When** 调用 `scan()` 扫描结果
**Then** JOIN 结果正确映射到自定义结构体的各个字段
**And** NULL 值正确处理（可选字段）

#### Scenario: Scan query with window functions
**Given** 一个使用窗口函数（如 RANK(), ROW_NUMBER()）的 SQL 查询
**When** 调用 `scan()` 扫描结果
**Then** 窗口函数计算结果正确映射到结构体字段
**And** 支持复杂聚合和排名场景

---

### Requirement: Query Single Row Result
**ID**: `RSQ-004`
**Priority**: P0
**Status**: Implemented

RawQuery MUST provide a `scanOne()` method to query single-row results, returning either a struct instance or an error.

**Rationale**: 提供便捷的单行查询方法，避免手动处理 ArrayList。

#### Scenario: Query single row successfully
**Given** 一个返回单行的 SELECT 查询
**When** 调用 `query.scanOne(T)` 查询单行
**Then** 返回正确的结构体 T 实例
**And** 字段值与数据库行匹配

#### Scenario: No rows found error
**Given** 一个不返回任何行的 SELECT 查询
**When** 调用 `query.scanOne(T)` 查询
**Then** 返回 `error.NoRows` 错误
**And** 调用者可以明确知道没有找到数据

#### Scenario: Multiple rows error
**Given** 一个返回多行的 SELECT 查询
**When** 调用 `query.scanOne(T)` 期望单行
**Then** 返回 `error.MultipleRows` 错误
**And** 调用者可以识别数据不符合预期

---

### Requirement: Resource Management and Cleanup
**ID**: `RSQ-005`
**Priority**: P0
**Status**: Implemented

RawQuery MUST provide a `deinit()` method to release all allocated resources (parameter arrays, query instances).

**Rationale**: 确保显式内存管理，防止内存泄漏，遵循 Zig 语言惯例。

#### Scenario: Clean up RawQuery resources
**Given** 一个已创建的 RawQuery 实例
**When** 调用 `query.deinit()` 释放资源
**Then** 参数数组内存被正确释放
**And** RawQuery 实例内存被正确释放
**And** 使用 std.testing.allocator 检测无内存泄漏

#### Scenario: Use with defer pattern
**Given** Zig defer 清理模式
**When** 创建 RawQuery 后立即 `defer query.deinit()`
**Then** 函数退出时自动调用 deinit()
**And** 即使发生错误也正确清理资源

---

### Requirement: Support Complex SQL Scenarios
**ID**: `RSQ-006`
**Priority**: P1
**Status**: Implemented

RawQuery MUST support complex SQL scenarios that query builders cannot cover (window functions, CTEs, full-text search, recursive queries, etc.).

**Rationale**: 提供灵活性以处理 PostgreSQL 的高级功能，不受查询构建器 API 限制。

#### Scenario: Execute query with CTE (Common Table Expression)
**Given** 一个包含 WITH 子句的 CTE 查询
**When** 使用 `newRaw()` 执行 CTE 查询
**Then** CTE 正确执行并返回预期结果
**And** 支持递归 CTE

#### Scenario: Execute full-text search query
**Given** 一个使用 PostgreSQL 全文搜索功能的 SQL
**When** 执行包含 `to_tsvector()` 和 `to_tsquery()` 的查询
**Then** 全文搜索正确执行
**And** 结果按相关性排序

#### Scenario: Execute query with JSONB operations
**Given** 一个使用 JSONB 操作符（->, ->>, @>）的 SQL 查询
**When** 执行 JSONB 查询
**Then** JSONB 数据正确查询和处理
**And** 支持 JSONB 聚合和过滤

---

### Requirement: Error Handling
**ID**: `RSQ-007`
**Priority**: P0
**Status**: Implemented

RawQuery MUST correctly handle all error scenarios, returning explicit error types and context information.

**Rationale**: 确保错误处理清晰明确，便于调试和错误恢复。

#### Scenario: SQL syntax error
**Given** 一个包含语法错误的 SQL 语句
**When** 调用 `exec()` 或 `scan()` 执行查询
**Then** 返回 `error.QueryFailed` 错误
**And** 错误消息包含 SQL 语句和语法错误详情

#### Scenario: Type mismatch error
**Given** SELECT 查询返回的列类型与结构体字段类型不匹配
**When** 调用 `scan(T, &dest)` 扫描结果
**Then** 返回 `error.TypeMismatch` 错误
**And** 错误消息指出具体的字段和类型不匹配

#### Scenario: Connection closed error
**Given** 数据库连接已关闭
**When** 尝试执行 Raw SQL 查询
**Then** 返回 `error.ConnectionClosed` 错误
**And** 调用者可以识别连接问题
