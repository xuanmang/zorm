# ZORM Product Requirements Document (PRD)

**Version**: v1.0
**Date**: 2025-10-19
**Author**: John (PM)
**Project**: ZORM - SQL-first Zig ORM (PostgreSQL High-Level API)

---

## Goals and Background Context

### Goals

- 为 Zig 开发者提供简单、直观的 PostgreSQL ORM API，隐藏底层数据库驱动复杂性
- 实现类型安全的查询构建器，利用 Zig 的 comptime 特性实现零运行时开销
- 提供清晰的错误处理机制和显式内存管理模式
- 确保 API 易于理解和使用，降低 Zig PostgreSQL ORM 学习曲线
- 充分利用 PostgreSQL 特性（RETURNING、JSONB、数组类型等）

### Background Context

ZORM 是一个参照 Bun ORM 设计的 SQL-first Zig ORM 库，专门针对 **PostgreSQL 数据库**。当前市场缺乏专为 Zig 语言设计的成熟 PostgreSQL ORM 解决方案，现有开发者需要直接使用底层 PostgreSQL 协议或 C API，开发效率低且容易出错。

本 PRD 专注于定义 **高层级 API**（面向最终用户的便捷接口），这些 API 将构建在底层 PostgreSQL 驱动（如 pg.zig）之上，为开发者提供类型安全、符合 Zig 语言惯例的 ORM 体验。通过精心设计的 API，我们将充分利用 Zig 的 comptime、显式内存管理和强制错误处理等特性，同时最大化发挥 PostgreSQL 的强大功能（如 RETURNING、ON CONFLICT、CTE、JSONB 等），提供接近 C 性能的同时保持良好的开发体验。

**重要设计约束**: 所有 API 设计必须与 **Golang Bun ORM** 的使用方式保持一致，确保熟悉 Bun 的开发者能够快速上手 ZORM。

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-10-19 | v1.0 | Initial PRD for ZORM High-Level API (PostgreSQL only) | John (PM) |

---

## Requirements

### Functional Requirements

**FR1**: 提供 DB 实例初始化 API，支持从 PostgreSQL 连接创建 DB 对象，配置连接池参数（最大连接数、空闲连接数、连接生命周期）

**FR2**: 提供类型安全的 SELECT 查询构建器，支持链式调用方法（where、orderBy、limit、offset、join、groupBy、having、distinct）

**FR3**: 提供类型安全的 INSERT 查询构建器，支持单行和批量插入，支持 PostgreSQL RETURNING 子句返回插入的数据

**FR4**: 提供类型安全的 UPDATE 查询构建器，支持条件更新和批量更新，支持 RETURNING 子句

**FR5**: 提供类型安全的 DELETE 查询构建器，支持条件删除，支持 RETURNING 子句

**FR6**: 提供 Raw SQL 查询 API，允许执行任意 SQL 语句并将结果扫描到 Zig 结构体

**FR7**: 支持 PostgreSQL 特有功能：ON CONFLICT DO NOTHING/UPDATE（upsert）、JSONB 类型、数组类型

**FR8**: 提供事务管理 API（beginTx、commit、rollback），支持 errdefer 自动回滚模式

**FR9**: 提供 Schema DDL 构建器（CREATE TABLE、DROP TABLE、CREATE INDEX、DROP INDEX），基于 Zig 结构体自动生成表定义

**FR10**: 支持查询钩子系统，允许注册全局钩子（BeforeQuery、AfterQuery）用于日志记录、性能追踪等

**FR11**: 提供结果扫描 API，自动将查询结果映射到 Zig 结构体，支持 comptime 类型反射

**FR12**: 支持 JOIN 操作（INNER JOIN、LEFT JOIN、RIGHT JOIN），返回组合结构体结果

### Non-Functional Requirements

**NFR1**: 所有 API 必须使用 Zig Allocator 模式进行显式内存管理，无垃圾回收

**NFR2**: 所有可能失败的操作必须返回错误联合类型（!T），强制调用者处理错误

**NFR3**: 利用 comptime 特性实现零运行时开销的类型映射和 SQL 生成

**NFR4**: 查询构建器必须在编译时验证类型安全性，防止 SQL 注入

**NFR5**: API 文档覆盖率达到 100%，每个公共函数必须包含示例代码

**NFR6**: 单元测试覆盖率达到 80% 以上，使用 std.testing.allocator 检测内存泄漏

**NFR7**: 查询执行性能应接近直接使用原生 PostgreSQL 协议，开销不超过 5%

**NFR8**: 支持 Zig 0.15.2+ 版本，遵循 Zig 语言最佳实践和惯例

**NFR9**: 所有资源（DB、Query、Transaction）必须提供 deinit() 方法，支持 defer 清理模式

**NFR10**: 错误消息必须清晰明确，包含足够的上下文信息帮助调试

---

## Technical Assumptions

### Repository Structure: Monorepo

ZORM 采用单一代码库结构，所有核心模块、测试、示例和文档集中管理。

### Service Architecture

**单体库架构 (Library Monolith)**
- ZORM 是一个独立的 Zig 库包，不涉及微服务或服务器架构
- 所有功能模块作为库的内部模块组织
- 用户通过 `@import("zorm")` 导入并使用

### Testing Requirements

**全面测试金字塔**
- **单元测试**: 每个 API 函数必须有对应的单元测试（目标覆盖率 80%+）
- **集成测试**: 针对 PostgreSQL 数据库的真实集成测试，验证完整查询流程
- **内存泄漏测试**: 使用 `std.testing.allocator` 自动检测所有测试中的内存泄漏
- **示例验证**: 文档中的所有代码示例必须可编译并通过测试
- **性能基准测试**: 关键路径（查询构建、结果扫描）需要 benchmark 验证性能目标

### Additional Technical Assumptions and Requests

**核心技术栈**:
- **目标 Zig 版本**: 0.15.2+（确保稳定性和语言特性支持）
- **PostgreSQL 驱动**: 使用 pg.zig 纯 Zig 实现作为底层驱动（避免 C 依赖）
- **构建系统**: Zig 标准构建系统（build.zig）

**用户便利性优先的设计原则**:
- **链式 API**: 所有查询构建器支持链式调用（流畅接口模式），提升代码可读性
  ```zig
  try db.newSelect(User)
      .where("age > ?", .{18})
      .orderBy("created_at", .desc)
      .limit(10)
      .scan(&users);
  ```

- **自动类型推断**: 利用 `comptime` 从 Zig 结构体自动推断表结构、列类型和 SQL 映射
  ```zig
  const User = struct {
      id: i64,
      name: []const u8,
      email: []const u8,
  };
  // ZORM 自动生成 CREATE TABLE、INSERT、SELECT 等语句
  ```

- **零配置启动**: 提供开箱即用的默认配置，高级功能可选配置
  ```zig
  const db = try DB.init(allocator, conn, .postgresql, .{});
  // 使用合理默认值，无需复杂配置
  ```

- **清晰的错误信息**: 所有错误必须包含上下文（SQL 语句、参数、行号等），便于快速调试

- **内存管理简化**:
  - 提供 Arena 分配器模式用于临时查询，简化内存管理
  - 所有 API 返回值所有权清晰，配合 `defer` 实现自动清理

- **文档与示例优先**:
  - 每个 API 必须包含完整的 inline 文档和可运行示例
  - 提供 examples/ 目录，包含常见场景的完整示例程序

**性能与安全**:
- **编译时 SQL 验证**: 尽可能在 comptime 检测 SQL 错误（如类型不匹配）
- **参数化查询**: 强制使用参数绑定，防止 SQL 注入
- **连接池管理**: 内置高效连接池，自动处理连接生命周期
- **零拷贝优化**: 结果扫描时尽量减少数据拷贝

**开发体验**:
- **友好的编译错误**: 利用 `@compileError` 提供清晰的编译时错误提示
- **调试支持**: 提供 debug 模式，自动打印生成的 SQL 语句
- **渐进式学习曲线**: 简单场景使用简单 API，高级功能按需引入

---

## Epic List

### Epic 1: Foundation & Query Builder Core
**目标**: 建立项目基础设施（构建系统、测试框架、PostgreSQL 连接），并实现类型安全的 SELECT 和 INSERT 查询构建器，让用户能够执行基本的数据读取和插入操作。

### Epic 2: Complete CRUD & Transaction Support
**目标**: 实现 UPDATE 和 DELETE 查询构建器，提供完整的 CRUD 能力，并添加事务管理 API（begin/commit/rollback），确保数据一致性和原子性操作支持。

### Epic 3: Schema Management & Type System
**目标**: 提供 Schema DDL 构建器（CREATE/DROP TABLE、CREATE/DROP INDEX），实现 Zig 结构体到 PostgreSQL 类型的自动映射系统，简化数据库表结构管理和迁移。

### Epic 4: PostgreSQL Power Features & Developer Experience
**目标**: 充分利用 PostgreSQL 特有功能（RETURNING、ON CONFLICT、JSONB、数组类型），添加查询钩子系统用于可观测性，优化错误处理和文档，提升整体开发体验。

---

## MVP Validation Plan

### Success Criteria

**Core Functionality Validation**:
- ✅ 成功连接到 PostgreSQL 数据库（使用真实 PostgreSQL 实例）
- ✅ 执行基本 CRUD 操作（SELECT、INSERT、UPDATE、DELETE）无错误
- ✅ 事务管理正常工作（commit/rollback 符合预期）
- ✅ 内存泄漏检测通过（所有测试使用 `std.testing.allocator` 无泄漏）
- ✅ 编译时类型安全验证（不支持的类型触发 `@compileError`）

**Performance Benchmarks**:
- ✅ 批量插入性能：1000 行数据插入时间 < pg.zig 原生操作的 1.05 倍
- ✅ 复杂查询构建：生成带 JOIN 和 WHERE 的 SQL < 1ms
- ✅ 结果扫描：扫描 1000 行结果到 ArrayList < pg.zig 原生操作的 1.05 倍

**API Usability Validation**:
- ✅ 完成至少 3 个真实场景的示例程序（CRUD、事务、JOIN）
- ✅ 所有示例代码可编译并通过集成测试
- ✅ API 与 Bun ORM 使用方式对齐（熟悉 Bun 的开发者能快速理解）

### Beta Testing Plan

**Internal Testing (Week 1-2)**:
1. 项目团队成员使用 ZORM 构建一个简单的博客系统后端
2. 收集反馈：API 易用性、错误消息清晰度、性能表现
3. 识别高频使用场景和痛点

**Community Alpha (Week 3-4)**:
1. 邀请 5-10 位 Zig 社区开发者参与早期测试
2. 提供详细的 Getting Started 文档和示例
3. 通过 GitHub Issues 收集 bug 报告和功能建议
4. 每周进行一次 bug 修复和 API 调整迭代

**Public Beta (Week 5-6)**:
1. 发布到 Zig 包管理器（如 Gyro 或 zigmod）
2. 撰写博客文章介绍 ZORM 特性和设计理念
3. 监控 GitHub Issues 和社区反馈
4. 准备 v1.0 发布的最终调整

### Iteration Criteria

**何时进入下一阶段**:
- Internal Testing → Community Alpha:
  - 所有 Epic 1 和 Epic 2 的 AC 通过
  - 单元测试覆盖率 > 80%
  - 无已知 P0/P1 级别 bug
- Community Alpha → Public Beta:
  - Epic 3 和 Epic 4 核心功能完成
  - 至少 3 位 alpha 测试者反馈正面
  - 性能基准测试达标
  - 文档完整度 > 90%
- Public Beta → v1.0:
  - 连续 2 周无新 P0/P1 bug 报告
  - API 稳定（无 breaking changes）
  - 至少 10 个真实项目使用 ZORM
  - 性能和内存安全验证通过

---

## Known Areas of High Complexity

### Technical Risk Assessment

| Risk Area | Severity | Likelihood | Impact | Mitigation Strategy | Owner |
|-----------|----------|------------|--------|---------------------|-------|
| **Zig 版本兼容性问题** | High | Medium | 新版本 Zig 可能破坏 API（如 0.15.x → 0.16.x） | 固定支持 0.15.2+ 并在 CI 中测试多版本；使用保守的语言特性；提供版本迁移指南 | Core Team |
| **PostgreSQL 驱动集成复杂性** | Medium | Low | pg.zig 纯 Zig 实现避免 C FFI 问题，但需验证协议完整性 | 充分测试 PostgreSQL 协议覆盖；验证特殊类型支持；提供 mock 驱动用于单元测试 | Backend Lead |
| **Comptime 类型反射限制** | Medium | Medium | Zig 的 comptime 可能无法处理某些复杂类型（如嵌套泛型、函数指针） | 明确文档说明支持的类型；提供 escape hatch（Raw SQL）；comptime 错误消息清晰 | Type System Lead |
| **性能开销超出预期** | Medium | Low | 查询构建器和类型映射可能引入 > 5% 性能损失 | 早期进行性能基准测试；使用 Arena 分配器优化临时分配；profiling 识别热点路径 | Performance Engineer |
| **内存泄漏** | High | Low | 复杂的内存管理（特别是错误路径）可能导致泄漏 | 强制使用 `std.testing.allocator`；所有测试检测泄漏；代码审查关注 errdefer | QA Lead |
| **SQL 注入防护不足** | Critical | Low | 参数绑定实现错误可能导致 SQL 注入漏洞 | 强制使用占位符；禁止字符串拼接 SQL；安全审计和模糊测试 | Security Lead |
| **文档滞后于代码** | Medium | High | 快速迭代可能导致文档过时 | 每个 PR 要求更新相关文档；CI 检查示例代码可编译；文档版本化 | Tech Writer |
| **跨平台兼容性** | Low | Low | macOS/Linux/Windows 上的 PostgreSQL 连接差异 | CI 矩阵测试三大平台；明确平台特定的依赖和配置 | DevOps Lead |

### High-Risk Stories (需优先验证)

**Epic 1**:
- **Story 1.6 (Comptime Type Reflection)**: Zig 的类型反射能力是核心基础，需要早期验证复杂类型的支持情况
  - **验证方式**: 创建测试覆盖 20+ 种 Zig 类型，确认 comptime 错误消息清晰

**Epic 2**:
- **Story 2.4 (Transaction Management)**: 事务的错误处理和资源管理复杂，容易出现死锁或连接泄漏
  - **验证方式**: 压力测试并发事务；模拟各种错误场景（网络断开、超时）

**Epic 3**:
- **Story 3.6 (PostgreSQL Specific Types)**: JSONB、数组等特殊类型的序列化/反序列化容易出错
  - **验证方式**: 端到端测试覆盖所有 PostgreSQL 特有类型；验证边界情况（空数组、嵌套 JSON）

**Epic 4**:
- **Story 4.1 (ON CONFLICT Upsert)**: PostgreSQL ON CONFLICT 语法复杂，容易生成错误 SQL
  - **验证方式**: 对照 PostgreSQL 官方文档验证生成的 SQL；集成测试覆盖多种冲突场景

---

## Epic 1: Foundation & Query Builder Core

**Epic Goal**: 建立 ZORM 项目基础设施（Git、构建系统、CI/CD、PostgreSQL 连接管理），并实现类型安全的 SELECT 和 INSERT 查询构建器。用户能够通过简洁的链式 API 执行基本的数据查询和插入操作，体验与 Bun ORM 一致的开发模式。完成后，用户可以在真实 PostgreSQL 数据库上执行查询并获取类型安全的结果。

### Story 1.1: Project Setup and PostgreSQL Connection

**As a** Zig developer,
**I want** 初始化 ZORM 项目并建立 PostgreSQL 数据库连接，
**so that** 我能够开始使用 ZORM 进行数据库操作。

#### Acceptance Criteria

1. **AC1.1.1**: 项目包含完整的 `build.zig` 配置，支持编译库、运行测试、生成文档
2. **AC1.1.2**: 提供 `DB.init()` API，接受 Allocator、PostgreSQL 连接对象和配置选项，返回 DB 实例
3. **AC1.1.3**: DB 配置支持连接池参数（max_open_conns、max_idle_conns、conn_max_lifetime），提供合理默认值
4. **AC1.1.4**: 提供 `DB.close()` 方法关闭数据库连接，支持 `defer db.deinit()` 资源清理模式
5. **AC1.1.5**: 包含完整的示例程序（`examples/basic.zig`）演示连接创建和关闭
6. **AC1.1.6**: 所有内存分配使用 testing allocator 测试，确保无内存泄漏
7. **AC1.1.7**: 设置 CI/CD（GitHub Actions）自动运行测试和检查代码格式

---

### Story 1.2: Type-Safe SELECT Query Builder (Basic)

**As a** Zig developer,
**I want** 使用类型安全的 SELECT 查询构建器检索数据，
**so that** 我能够以编译时验证的方式查询 PostgreSQL 数据库，避免运行时错误。

#### Acceptance Criteria

1. **AC1.2.1**: 提供 `db.newSelect(T)` API 创建 SELECT 查询构建器，T 为目标 Zig 结构体类型
2. **AC1.2.2**: 支持 `.where(condition, args)` 方法添加 WHERE 条件，参数使用元组自动绑定（防止 SQL 注入）
3. **AC1.2.3**: 支持 `.orderBy(column, direction)` 方法指定排序，direction 为枚举 `.asc` 或 `.desc`
4. **AC1.2.4**: 支持 `.limit(n)` 和 `.offset(n)` 方法实现分页
5. **AC1.2.5**: 提供 `.scan(dest)` 方法执行查询并将结果扫描到 `std.ArrayList(T)` 中
6. **AC1.2.6**: 提供 `.scanOne()` 方法查询单行，返回 `!T` 类型（无结果返回 error.NoRows）
7. **AC1.2.7**: 查询构建器支持链式调用（fluent interface），提升代码可读性
8. **AC1.2.8**: 使用示例：
   ```zig
   var users: std.ArrayList(User) = .{};
   defer users.deinit(allocator);

   var query = try db.newSelect(User);
   defer query.deinit();

   try query
       .where("age > ?", .{18})
       .orderBy("created_at", .desc)
       .limit(10)
       .scan(&users);
   ```

---

### Story 1.3: SELECT Query Builder with Column Selection and Distinct

**As a** Zig developer,
**I want** 选择特定列和使用 DISTINCT 去重，
**so that** 我能够优化查询性能并精确控制返回的数据。

#### Acceptance Criteria

1. **AC1.3.1**: 支持 `.column(name)` 方法指定要查询的列（可多次调用选择多列）
2. **AC1.3.2**: 默认查询所有列（SELECT *），用户可选择性指定列子集
3. **AC1.3.3**: 支持 `.setDistinct()` 方法启用 DISTINCT 去重
4. **AC1.3.4**: 支持 `.count()` 方法返回查询结果数量（返回 `!usize`）
5. **AC1.3.5**: 使用示例：
   ```zig
   // 选择特定列
   var query = try db.newSelect(User);
   defer query.deinit();

   try query
       .column("id")
       .column("name")
       .column("email")
       .where("active = ?", .{true})
       .scan(&users);

   // DISTINCT 去重
   const count = try db.newSelect(User)
       .setDistinct()
       .column("email")
       .count();
   ```

---

### Story 1.4: Type-Safe INSERT Query Builder (Single Row)

**As a** Zig developer,
**I want** 使用类型安全的 INSERT 构建器插入单行数据，
**so that** 我能够以类型安全的方式向数据库添加数据，并利用 PostgreSQL RETURNING 获取插入结果。

#### Acceptance Criteria

1. **AC1.4.1**: 提供 `db.newInsert(T)` API 创建 INSERT 查询构建器
2. **AC1.4.2**: 提供 `.value(item)` 方法指定要插入的单行数据（T 类型实例）
3. **AC1.4.3**: 提供 `.exec()` 方法执行插入，返回 `InsertResult`（包含 rows_affected 和 last_insert_id）
4. **AC1.4.4**: 支持 `.setReturning(cols)` 方法启用 PostgreSQL RETURNING 子句
5. **AC1.4.5**: 提供 `.execReturning(dest)` 方法执行插入并将 RETURNING 结果扫描到 ArrayList 中
6. **AC1.4.6**: 自动从 Zig 结构体字段生成 INSERT 语句的列名和占位符
7. **AC1.4.7**: 使用示例：
   ```zig
   const user = User{
       .name = "John Doe",
       .email = "john@example.com",
       .age = 30,
       .created_at = std.time.timestamp(),
   };

   // 基本插入
   var insert = try db.newInsert(User);
   defer insert.deinit();

   const result = try insert.value(user).exec();
   std.debug.print("Inserted {} rows\n", .{result.rows_affected});

   // 使用 RETURNING 获取插入的数据
   var inserted_users: std.ArrayList(User) = .{};
   defer inserted_users.deinit(allocator);

   try insert
       .value(user)
       .setReturning("*")
       .execReturning(&inserted_users);

   std.debug.print("Inserted user ID: {}\n", .{inserted_users.items[0].id});
   ```

---

### Story 1.5: Batch INSERT Support

**As a** Zig developer,
**I want** 批量插入多行数据以提升性能，
**so that** 我能够高效地向数据库添加大量数据。

#### Acceptance Criteria

1. **AC1.5.1**: 提供 `.values(items)` 方法接受 `[]const T` 切片进行批量插入
2. **AC1.5.2**: 批量插入生成单条 SQL 语句（`INSERT INTO ... VALUES (...), (...), ...`）
3. **AC1.5.3**: 批量插入支持 RETURNING 子句，返回所有插入行的数据
4. **AC1.5.4**: 性能测试验证批量插入比循环单行插入快至少 10 倍
5. **AC1.5.5**: 使用示例：
   ```zig
   const users = [_]User{
       .{ .name = "Alice", .email = "alice@example.com", .age = 25, .created_at = std.time.timestamp() },
       .{ .name = "Bob", .email = "bob@example.com", .age = 35, .created_at = std.time.timestamp() },
       .{ .name = "Carol", .email = "carol@example.com", .age = 28, .created_at = std.time.timestamp() },
   };

   var insert = try db.newInsert(User);
   defer insert.deinit();

   const result = try insert.values(&users).exec();
   std.debug.print("Inserted {} rows\n", .{result.rows_affected});
   ```

---

### Story 1.6: Comptime Type Reflection and SQL Type Mapping

**As a** Zig developer,
**I want** ZORM 自动从 Zig 结构体推断 SQL 类型和表结构，
**so that** 我无需手动配置列映射，减少重复代码并避免类型不匹配错误。

#### Acceptance Criteria

1. **AC1.6.1**: 使用 `@typeInfo()` 在 comptime 反射 Zig 结构体字段
2. **AC1.6.2**: 实现 Zig 类型到 PostgreSQL 类型的映射（i64→BIGINT、[]const u8→TEXT、bool→BOOLEAN 等）
3. **AC1.6.3**: 支持可选类型（`?T`）自动映射为 NULL 允许的列
4. **AC1.6.4**: 支持自定义表名（结构体可定义 `pub const table_name = "custom_name"`）
5. **AC1.6.5**: 提供 `getTableName(T)` 和 `zigToSQLType(T)` 等 comptime 辅助函数
6. **AC1.6.6**: 编译时验证不支持的类型，使用 `@compileError` 提供清晰错误消息
7. **AC1.6.7**: 使用示例：
   ```zig
   const User = struct {
       id: i64,              // 自动映射为 BIGINT
       name: []const u8,     // 自动映射为 TEXT
       email: ?[]const u8,   // 自动映射为 TEXT (NULL 允许)
       age: u32,             // 自动映射为 INTEGER
       is_active: bool,      // 自动映射为 BOOLEAN
       created_at: i64,      // 自动映射为 BIGINT (Unix timestamp)

       pub const table_name = "users"; // 自定义表名
   };
   ```

---

## Epic 2: Complete CRUD & Transaction Support

**Epic Goal**: 实现 UPDATE 和 DELETE 查询构建器，提供完整的 CRUD 操作能力。添加事务管理 API（beginTx、commit、rollback）以支持复杂业务逻辑的原子性操作，并提供 Raw SQL 执行能力应对特殊场景。完成后，用户能够执行所有标准数据库操作，并通过事务确保数据一致性，API 使用体验与 Bun ORM 完全对齐。

### Story 2.1: Type-Safe UPDATE Query Builder

**As a** Zig developer,
**I want** 使用类型安全的 UPDATE 构建器修改数据库记录，
**so that** 我能够以声明式方式更新数据，避免手写 SQL 错误。

#### Acceptance Criteria

1. **AC2.1.1**: 提供 `db.newUpdate(T)` API 创建 UPDATE 查询构建器
2. **AC2.1.2**: 提供 `.set(assignments)` 方法指定要更新的列和值（支持字符串表达式或结构体）
3. **AC2.1.3**: 支持 `.where(condition, args)` 方法添加 WHERE 条件（防止误更新所有行）
4. **AC2.1.4**: 提供 `.exec()` 方法执行更新，返回 `UpdateResult`（包含 rows_affected）
5. **AC2.1.5**: 支持 `.setReturning(cols)` 方法启用 PostgreSQL RETURNING 子句
6. **AC2.1.6**: 提供 `.execReturning(dest)` 方法执行更新并获取更新后的数据
7. **AC2.1.7**: 支持链式调用和多个 WHERE 条件组合
8. **AC2.1.8**: 使用示例：
   ```zig
   // 基本更新
   var update = try db.newUpdate(User);
   defer update.deinit();

   const result = try update
       .set("age = age + 1, updated_at = ?", .{std.time.timestamp()})
       .where("email = ?", .{"alice@example.com"})
       .exec();

   std.debug.print("Updated {} rows\n", .{result.rows_affected});

   // 使用 RETURNING 获取更新后的数据
   var updated_users: std.ArrayList(User) = .{};
   defer updated_users.deinit(allocator);

   try update
       .set("is_active = ?", .{false})
       .where("last_login < ?", .{cutoff_timestamp})
       .setReturning("*")
       .execReturning(&updated_users);
   ```

---

### Story 2.2: Bulk UPDATE Support

**As a** Zig developer,
**I want** 批量更新多行数据，
**so that** 我能够高效地修改大量记录而不需要循环执行单个更新。

#### Acceptance Criteria

1. **AC2.2.1**: UPDATE 构建器支持复杂 WHERE 条件匹配多行
2. **AC2.2.2**: 支持 `.whereIn(column, values)` 方法批量匹配（如 `WHERE id IN (1,2,3)`）
3. **AC2.2.3**: 支持使用子查询作为 WHERE 条件
4. **AC2.2.4**: 批量更新的 RETURNING 子句返回所有更新行的数据
5. **AC2.2.5**: 使用示例：
   ```zig
   var update = try db.newUpdate(User);
   defer update.deinit();

   // 批量更新多个用户
   const user_ids = [_]i64{ 1, 2, 3, 5, 8 };
   const result = try update
       .set("status = ?", .{"verified"})
       .whereIn("id", &user_ids)
       .exec();

   std.debug.print("Updated {} users\n", .{result.rows_affected});
   ```

---

### Story 2.3: Type-Safe DELETE Query Builder

**As a** Zig developer,
**I want** 使用类型安全的 DELETE 构建器删除数据库记录，
**so that** 我能够安全地删除数据，并通过 WHERE 条件防止误删。

#### Acceptance Criteria

1. **AC2.3.1**: 提供 `db.newDelete(T)` API 创建 DELETE 查询构建器
2. **AC2.3.2**: 强制要求 WHERE 条件（防止意外删除所有行），无 WHERE 时编译错误或返回错误
3. **AC2.3.3**: 支持 `.where(condition, args)` 方法指定删除条件
4. **AC2.3.4**: 提供 `.exec()` 方法执行删除，返回 `DeleteResult`（包含 rows_affected）
5. **AC2.3.5**: 支持 `.setReturning(cols)` 方法启用 RETURNING 子句，返回被删除的数据
6. **AC2.3.6**: 提供 `.execReturning(dest)` 方法执行删除并获取被删除的数据
7. **AC2.3.7**: 支持 `.whereIn()` 批量删除
8. **AC2.3.8**: 使用示例：
   ```zig
   // 基本删除
   var delete = try db.newDelete(User);
   defer delete.deinit();

   const result = try delete
       .where("id = ?", .{123})
       .exec();

   std.debug.print("Deleted {} rows\n", .{result.rows_affected});

   // 删除并获取被删除的数据（审计日志）
   var deleted_users: std.ArrayList(User) = .{};
   defer deleted_users.deinit(allocator);

   try delete
       .where("status = ?", .{"inactive"})
       .where("last_login < ?", .{cutoff_timestamp})
       .setReturning("*")
       .execReturning(&deleted_users);

   // 记录被删除的用户
   for (deleted_users.items) |user| {
       std.debug.print("Deleted user: {s}\n", .{user.email});
   }
   ```

---

### Story 2.4: Transaction Management API

**As a** Zig developer,
**I want** 使用事务管理 API 确保多个数据库操作的原子性，
**so that** 我能够实现复杂业务逻辑并保证数据一致性。

#### Acceptance Criteria

1. **AC2.4.1**: 提供 `db.beginTx()` 方法开启事务，返回 `*Tx` 事务对象
2. **AC2.4.2**: Tx 对象提供与 DB 相同的查询构建器方法（newSelect、newInsert、newUpdate、newDelete）
3. **AC2.4.3**: 提供 `tx.commit()` 方法提交事务
4. **AC2.4.4**: 提供 `tx.rollback()` 方法回滚事务
5. **AC2.4.5**: 支持 `errdefer tx.rollback()` 模式，错误时自动回滚
6. **AC2.4.6**: 事务内的所有操作共享同一个数据库连接
7. **AC2.4.7**: 嵌套事务检测并返回错误（PostgreSQL 不支持真正的嵌套事务）
8. **AC2.4.8**: 使用示例：
   ```zig
   // 开启事务
   const tx = try db.beginTx();
   errdefer tx.rollback() catch {}; // 错误时自动回滚

   // 在事务中插入用户
   var insert_user = try tx.newInsert(User);
   defer insert_user.deinit();

   var inserted: std.ArrayList(User) = .{};
   defer inserted.deinit(allocator);

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
       .created_at = std.time.timestamp(),
   };

   var insert_post = try tx.newInsert(Post);
   defer insert_post.deinit();

   _ = try insert_post.value(post).exec();

   // 提交事务
   try tx.commit();

   std.debug.print("Transaction completed successfully\n", .{});
   ```

---

### Story 2.5: Transaction Isolation Levels

**As a** Zig developer,
**I want** 配置事务隔离级别，
**so that** 我能够根据业务需求平衡并发性能和数据一致性。

#### Acceptance Criteria

1. **AC2.5.1**: 定义 `IsolationLevel` 枚举（read_uncommitted、read_committed、repeatable_read、serializable）
2. **AC2.5.2**: `db.beginTx()` 接受可选的 `TxOptions` 参数，包含 isolation_level 字段
3. **AC2.5.3**: 默认使用 PostgreSQL 的默认隔离级别（read_committed）
4. **AC2.5.4**: 在事务开始时执行 `SET TRANSACTION ISOLATION LEVEL` 语句
5. **AC2.5.5**: 使用示例：
   ```zig
   const tx = try db.beginTx(.{
       .isolation_level = .serializable,
   });
   errdefer tx.rollback() catch {};

   // 执行需要 serializable 级别的操作
   // ...

   try tx.commit();
   ```

---

### Story 2.6: Raw SQL Query Support

**As a** Zig developer,
**I want** 执行任意 Raw SQL 语句，
**so that** 我能够处理查询构建器无法覆盖的复杂场景（如窗口函数、CTE、全文搜索等）。

#### Acceptance Criteria

1. **AC2.6.1**: 提供 `db.newRaw(sql, args)` API 创建 Raw SQL 查询
2. **AC2.6.2**: 支持参数绑定（使用 PostgreSQL `$1, $2, ...` 占位符）
3. **AC2.6.3**: 提供 `.exec()` 方法执行 DML 语句（INSERT/UPDATE/DELETE），返回 rows_affected
4. **AC2.6.4**: 提供 `.scan(dest)` 方法执行查询并将结果扫描到 ArrayList 中
5. **AC2.6.5**: 提供 `.scanOne()` 方法查询单行结果
6. **AC2.6.6**: Raw SQL 也支持在事务中执行（`tx.newRaw()`）
7. **AC2.6.7**: 使用示例：
   ```zig
   // 执行复杂查询（窗口函数）
   const UserWithRank = struct {
       user_id: i64,
       user_name: []const u8,
       post_count: i64,
       rank: i64,
   };

   const sql =
       \\SELECT
       \\  u.id as user_id,
       \\  u.name as user_name,
       \\  COUNT(p.id) as post_count,
       \\  RANK() OVER (ORDER BY COUNT(p.id) DESC) as rank
       \\FROM users u
       \\LEFT JOIN posts p ON p.user_id = u.id
       \\GROUP BY u.id, u.name
       \\HAVING COUNT(p.id) > $1
       \\ORDER BY rank
       \\LIMIT $2
   ;

   var results: std.ArrayList(UserWithRank) = .{};
   defer results.deinit(allocator);

   var query = try db.newRaw(sql, .{ 5, 10 });
   defer query.deinit();

   try query.scan(&results);

   for (results.items) |result| {
       std.debug.print("#{d} {s}: {d} posts\n", .{
           result.rank,
           result.user_name,
           result.post_count,
       });
   }
   ```

---

## Epic 3: Schema Management & Type System

**Epic Goal**: 提供 Schema DDL 构建器（CREATE/DROP TABLE、CREATE/DROP INDEX），实现从 Zig 结构体到 PostgreSQL 表结构的自动映射系统，简化数据库 Schema 管理和表结构创建。用户能够通过定义 Zig 结构体自动生成数据库表，无需手写 DDL 语句，并支持自定义约束、索引和默认值配置，API 设计与 Bun ORM 的 Schema 管理保持一致。

### Story 3.1: CREATE TABLE Query Builder (Basic)

**As a** Zig developer,
**I want** 使用 CREATE TABLE 构建器从 Zig 结构体自动创建数据库表，
**so that** 我无需手写 DDL 语句，减少重复代码并确保类型一致性。

#### Acceptance Criteria

1. **AC3.1.1**: 提供 `db.newCreateTable(T)` API 创建 CREATE TABLE 查询构建器
2. **AC3.1.2**: 自动从 Zig 结构体字段生成列定义（字段名 → 列名，字段类型 → SQL 类型）
3. **AC3.1.3**: 支持 Zig 类型到 PostgreSQL 类型的完整映射：
   - `i8, i16, i32` → SMALLINT
   - `i64` → BIGINT
   - `u8, u16, u32` → INTEGER
   - `u64` → BIGINT
   - `f32` → REAL
   - `f64` → DOUBLE PRECISION
   - `bool` → BOOLEAN
   - `[]const u8` → TEXT
   - `?T` → 对应 SQL 类型 + NULL 允许
4. **AC3.1.4**: 自动检测主键字段（字段名为 `id` 或带有特殊标记）并添加 PRIMARY KEY 约束
5. **AC3.1.5**: 可选类型（`?T`）自动省略 NOT NULL 约束
6. **AC3.1.6**: 提供 `.ifNotExists()` 方法添加 IF NOT EXISTS 子句
7. **AC3.1.7**: 提供 `.exec()` 方法执行 DDL 语句
8. **AC3.1.8**: 使用示例：
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

   // 生成的 SQL:
   // CREATE TABLE IF NOT EXISTS users (
   //     id BIGINT PRIMARY KEY NOT NULL,
   //     name TEXT NOT NULL,
   //     email TEXT NOT NULL,
   //     age INTEGER NOT NULL,
   //     bio TEXT,
   //     is_active BOOLEAN NOT NULL,
   //     created_at BIGINT NOT NULL
   // )
   ```

---

### Story 3.2: Schema Field Customization with Struct Tags

**As a** Zig developer,
**I want** 自定义表字段的属性（如列名、类型、约束、默认值），
**so that** 我能够精确控制生成的 Schema 而不受 Zig 结构体字段命名限制。

#### Acceptance Criteria

1. **AC3.2.1**: 支持通过结构体字段上的 comptime 元数据定义列属性
2. **AC3.2.2**: 支持自定义列名（如 Zig 字段 `user_name` 映射到 SQL 列 `username`）
3. **AC3.2.3**: 支持显式指定 SQL 类型（覆盖自动推断）
4. **AC3.2.4**: 支持 UNIQUE 约束标记
5. **AC3.2.5**: 支持 DEFAULT 值设置
6. **AC3.2.6**: 支持 CHECK 约束
7. **AC3.2.7**: 使用 Zig comptime 结构定义 Schema 配置（参考 Bun 的 struct tags）
8. **AC3.2.8**: 使用示例：
   ```zig
   const User = struct {
       id: i64,
       username: []const u8,
       email: []const u8,
       age: u32,
       status: []const u8,
       created_at: i64,

       pub const table_name = "users";

       // Schema 配置（comptime）
       pub const schema = .{
           .id = .{ .primary_key = true, .auto_increment = true },
           .username = .{ .unique = true, .sql_type = "VARCHAR(50)" },
           .email = .{ .unique = true },
           .age = .{ .check = "age >= 0 AND age <= 150" },
           .status = .{ .default = "'active'" },
           .created_at = .{ .default = "CURRENT_TIMESTAMP" },
       };
   };

   var create = try db.newCreateTable(User);
   defer create.deinit();

   try create.ifNotExists().exec();

   // 生成的 SQL:
   // CREATE TABLE IF NOT EXISTS users (
   //     id BIGSERIAL PRIMARY KEY,
   //     username VARCHAR(50) UNIQUE NOT NULL,
   //     email TEXT UNIQUE NOT NULL,
   //     age INTEGER NOT NULL CHECK (age >= 0 AND age <= 150),
   //     status TEXT NOT NULL DEFAULT 'active',
   //     created_at BIGINT NOT NULL DEFAULT CURRENT_TIMESTAMP
   // )
   ```

---

### Story 3.3: DROP TABLE Query Builder

**As a** Zig developer,
**I want** 使用 DROP TABLE 构建器删除数据库表，
**so that** 我能够在测试或清理场景中安全地删除表结构。

#### Acceptance Criteria

1. **AC3.3.1**: 提供 `db.newDropTable(T)` API 创建 DROP TABLE 查询构建器
2. **AC3.3.2**: 自动从 Zig 结构体获取表名
3. **AC3.3.3**: 提供 `.ifExists()` 方法添加 IF EXISTS 子句（避免表不存在时报错）
4. **AC3.3.4**: 提供 `.cascade()` 方法添加 CASCADE 选项（级联删除依赖对象）
5. **AC3.3.5**: 提供 `.restrict()` 方法添加 RESTRICT 选项（有依赖时拒绝删除，默认行为）
6. **AC3.3.6**: 提供 `.exec()` 方法执行 DDL 语句
7. **AC3.3.7**: 使用示例：
   ```zig
   var drop = try db.newDropTable(User);
   defer drop.deinit();

   try drop
       .ifExists()
       .cascade()
       .exec();

   // 生成的 SQL:
   // DROP TABLE IF EXISTS users CASCADE
   ```

---

### Story 3.4: CREATE INDEX Query Builder

**As a** Zig developer,
**I want** 使用 CREATE INDEX 构建器为表创建索引，
**so that** 我能够优化查询性能，特别是对频繁查询的列。

#### Acceptance Criteria

1. **AC3.4.1**: 提供 `db.newCreateIndex(T)` API 创建 CREATE INDEX 查询构建器
2. **AC3.4.2**: 提供 `.index(name)` 方法指定索引名称
3. **AC3.4.3**: 提供 `.column(col)` 方法添加索引列（支持多次调用创建复合索引）
4. **AC3.4.4**: 提供 `.unique()` 方法创建唯一索引
5. **AC3.4.5**: 提供 `.ifNotExists()` 方法添加 IF NOT EXISTS 子句
6. **AC3.4.6**: 支持表达式索引（如 `LOWER(email)`）
7. **AC3.4.7**: 支持部分索引（WHERE 条件）通过 `.where()` 方法
8. **AC3.4.8**: 提供 `.exec()` 方法执行 DDL 语句
9. **AC3.4.9**: 使用示例：
   ```zig
   // 简单索引
   var idx1 = try db.newCreateIndex(User);
   defer idx1.deinit();

   try idx1
       .index("idx_users_email")
       .column("email")
       .ifNotExists()
       .exec();

   // 复合索引
   var idx2 = try db.newCreateIndex(User);
   defer idx2.deinit();

   try idx2
       .index("idx_users_status_created")
       .column("status")
       .column("created_at")
       .exec();

   // 唯一索引
   var idx3 = try db.newCreateIndex(User);
   defer idx3.deinit();

   try idx3
       .index("idx_users_username_unique")
       .column("username")
       .unique()
       .exec();

   // 部分索引
   var idx4 = try db.newCreateIndex(User);
   defer idx4.deinit();

   try idx4
       .index("idx_users_active_email")
       .column("email")
       .where("is_active = true")
       .exec();
   ```

---

### Story 3.5: DROP INDEX Query Builder

**As a** Zig developer,
**I want** 使用 DROP INDEX 构建器删除数据库索引，
**so that** 我能够在索引不再需要时清理数据库。

#### Acceptance Criteria

1. **AC3.5.1**: 提供 `db.newDropIndex(T)` API 创建 DROP INDEX 查询构建器
2. **AC3.5.2**: 提供 `.index(name)` 方法指定要删除的索引名称
3. **AC3.5.3**: 提供 `.ifExists()` 方法添加 IF EXISTS 子句
4. **AC3.5.4**: 提供 `.cascade()` 方法添加 CASCADE 选项
5. **AC3.5.5**: 提供 `.exec()` 方法执行 DDL 语句
6. **AC3.5.6**: 使用示例：
   ```zig
   var drop_idx = try db.newDropIndex(User);
   defer drop_idx.deinit();

   try drop_idx
       .index("idx_users_email")
       .ifExists()
       .exec();

   // 生成的 SQL:
   // DROP INDEX IF EXISTS idx_users_email
   ```

---

### Story 3.6: Complete Type Mapping System with PostgreSQL Specific Types

**As a** Zig developer,
**I want** 支持 PostgreSQL 特有的数据类型（JSONB、数组、UUID 等），
**so that** 我能够充分利用 PostgreSQL 的强大功能。

#### Acceptance Criteria

1. **AC3.6.1**: 支持 JSONB 类型映射（Zig 侧可用 `[]const u8` 存储 JSON 字符串）
2. **AC3.6.2**: 支持数组类型（如 `[]i64` → `BIGINT[]`，`[][]const u8` → `TEXT[]`）
3. **AC3.6.3**: 支持 UUID 类型（通过自定义类型或 `[16]u8`）
4. **AC3.6.4**: 支持 TIMESTAMP WITH TIME ZONE 和 TIMESTAMP WITHOUT TIME ZONE
5. **AC3.6.5**: 提供显式类型覆盖机制（通过 schema 配置）
6. **AC3.6.6**: 在 CREATE TABLE 中正确生成 PostgreSQL 特有类型的列定义
7. **AC3.6.7**: 在 INSERT/SELECT 中正确处理 PostgreSQL 特有类型的序列化和反序列化
8. **AC3.6.8**: 使用示例：
   ```zig
   const Article = struct {
       id: i64,
       title: []const u8,
       tags: [][]const u8,         // TEXT[] 数组
       metadata: []const u8,        // JSONB (存储 JSON 字符串)
       view_counts: []i32,          // INTEGER[] 数组
       created_at: i64,

       pub const table_name = "articles";

       pub const schema = .{
           .id = .{ .primary_key = true },
           .metadata = .{ .sql_type = "JSONB" },
           .tags = .{ .sql_type = "TEXT[]" },
           .view_counts = .{ .sql_type = "INTEGER[]" },
       };
   };

   var create = try db.newCreateTable(Article);
   defer create.deinit();

   try create.ifNotExists().exec();

   // 插入示例
   const article = Article{
       .id = 1,
       .title = "Introduction to ZORM",
       .tags = &[_][]const u8{ "zig", "orm", "postgresql" },
       .metadata = "{\"author\": \"John\", \"draft\": false}",
       .view_counts = &[_]i32{ 100, 200, 150 },
       .created_at = std.time.timestamp(),
   };

   var insert = try db.newInsert(Article);
   defer insert.deinit();

   _ = try insert.value(article).exec();
   ```

---

## Epic 4: PostgreSQL Power Features & Developer Experience

**Epic Goal**: 充分利用 PostgreSQL 特有功能（ON CONFLICT、JOIN、聚合函数、子查询），添加查询钩子系统用于日志记录和性能追踪，优化错误处理和调试体验，完善文档和示例。完成后，ZORM 提供完整的 PostgreSQL ORM 能力，开发者能够高效构建复杂查询，并通过钩子和调试工具快速排查问题，整体开发体验达到生产就绪水平。

### Story 4.1: PostgreSQL ON CONFLICT (Upsert) Support

**As a** Zig developer,
**I want** 使用 ON CONFLICT 子句实现 upsert 操作（存在则更新，不存在则插入），
**so that** 我能够优雅地处理唯一约束冲突，避免手动检查和多次查询。

#### Acceptance Criteria

1. **AC4.1.1**: INSERT 查询构建器提供 `.onConflict(target)` 方法指定冲突目标（列名或约束名）
2. **AC4.1.2**: 提供 `.doNothing()` 方法指定冲突时不执行任何操作
3. **AC4.1.3**: 提供 `.doUpdate(assignments)` 方法指定冲突时执行更新操作
4. **AC4.1.4**: 支持 `EXCLUDED` 关键字引用被排除的值（如 `SET name = EXCLUDED.name`）
5. **AC4.1.5**: ON CONFLICT 与 RETURNING 子句兼容，返回插入或更新的数据
6. **AC4.1.6**: 支持部分唯一约束冲突（WHERE 条件）
7. **AC4.1.7**: 使用示例：
   ```zig
   const user = User{
       .name = "John Doe",
       .email = "john@example.com",
       .age = 30,
       .created_at = std.time.timestamp(),
   };

   // ON CONFLICT DO NOTHING
   var insert1 = try db.newInsert(User);
   defer insert1.deinit();

   _ = try insert1
       .value(user)
       .onConflict("email")
       .doNothing()
       .exec();

   // ON CONFLICT DO UPDATE
   var insert2 = try db.newInsert(User);
   defer insert2.deinit();

   var upserted: std.ArrayList(User) = .{};
   defer upserted.deinit(allocator);

   try insert2
       .value(user)
       .onConflict("email")
       .doUpdate("name = EXCLUDED.name, age = EXCLUDED.age, updated_at = EXCLUDED.updated_at")
       .setReturning("*")
       .execReturning(&upserted);
   ```

---

### Story 4.2: JOIN Query Support

**As a** Zig developer,
**I want** 在 SELECT 查询中使用 JOIN 连接多个表，
**so that** 我能够在单次查询中获取关联数据，避免 N+1 查询问题。

#### Acceptance Criteria

1. **AC4.2.1**: SELECT 查询构建器提供 `.join(type, table, condition)` 方法
2. **AC4.2.2**: 支持 JOIN 类型：INNER、LEFT、RIGHT、FULL、CROSS
3. **AC4.2.3**: 提供便捷方法：`.innerJoin(table, condition)`、`.leftJoin(table, condition)` 等
4. **AC4.2.4**: 支持多个 JOIN（可多次调用 join 方法）
5. **AC4.2.5**: 支持表别名（`users AS u`）
6. **AC4.2.6**: JOIN 查询结果扫描到自定义结构体（包含多表字段）
7. **AC4.2.7**: 支持在 JOIN 条件中使用参数绑定
8. **AC4.2.8**: 使用示例：
   ```zig
   const UserWithProfile = struct {
       user_id: i64,
       user_name: []const u8,
       user_email: []const u8,
       profile_bio: ?[]const u8,
       profile_avatar: ?[]const u8,
   };

   var results: std.ArrayList(UserWithProfile) = .{};
   defer results.deinit(allocator);

   var query = try db.newSelect(UserWithProfile);
   defer query.deinit();

   try query
       .column("u.id AS user_id")
       .column("u.name AS user_name")
       .column("u.email AS user_email")
       .column("p.bio AS profile_bio")
       .column("p.avatar AS profile_avatar")
       .from("users AS u")
       .leftJoin("profiles AS p", "p.user_id = u.id")
       .where("u.is_active = ?", .{true})
       .orderBy("u.created_at", .desc)
       .scan(&results);
   ```

---

### Story 4.3: GROUP BY and Aggregation Functions

**As a** Zig developer,
**I want** 使用 GROUP BY 和聚合函数（COUNT、SUM、AVG、MAX、MIN）进行数据分组和统计，
**so that** 我能够执行复杂的数据分析查询。

#### Acceptance Criteria

1. **AC4.3.1**: SELECT 查询构建器提供 `.groupBy(columns)` 方法（支持单列或多列）
2. **AC4.3.2**: 提供 `.having(condition, args)` 方法添加 HAVING 条件
3. **AC4.3.3**: 支持在 SELECT 中使用聚合函数（COUNT、SUM、AVG、MAX、MIN）
4. **AC4.3.4**: 聚合查询结果扫描到自定义结构体
5. **AC4.3.5**: 支持 DISTINCT 聚合（如 `COUNT(DISTINCT column)`）
6. **AC4.3.6**: 使用示例：
   ```zig
   const UserStats = struct {
       user_id: i64,
       user_name: []const u8,
       post_count: i64,
       total_views: i64,
       avg_views: f64,
   };

   var stats: std.ArrayList(UserStats) = .{};
   defer stats.deinit(allocator);

   var query = try db.newSelect(UserStats);
   defer query.deinit();

   try query
       .column("u.id AS user_id")
       .column("u.name AS user_name")
       .column("COUNT(p.id) AS post_count")
       .column("SUM(p.view_count) AS total_views")
       .column("AVG(p.view_count) AS avg_views")
       .from("users AS u")
       .leftJoin("posts AS p", "p.user_id = u.id")
       .groupBy("u.id, u.name")
       .having("COUNT(p.id) > ?", .{5})
       .orderBy("total_views", .desc)
       .scan(&stats);
   ```

---

### Story 4.4: Subquery Support

**As a** Zig developer,
**I want** 在查询中使用子查询（WHERE IN、FROM 子查询等），
**so that** 我能够构建复杂的嵌套查询逻辑。

#### Acceptance Criteria

1. **AC4.4.1**: 支持在 WHERE 条件中使用子查询（如 `WHERE id IN (SELECT ...)`）
2. **AC4.4.2**: 提供 `.whereIn(column, subquery)` 方法接受另一个查询构建器作为子查询
3. **AC4.4.3**: 提供 `.whereNotIn(column, subquery)` 方法
4. **AC4.4.4**: 支持 EXISTS 和 NOT EXISTS 子查询
5. **AC4.4.5**: 支持在 FROM 中使用子查询（派生表）
6. **AC4.4.6**: 子查询参数自动合并到主查询的参数列表中
7. **AC4.4.7**: 使用示例：
   ```zig
   // 子查询：查找有文章的用户
   var subquery = try db.newSelect(Post);
   defer subquery.deinit();

   try subquery
       .column("DISTINCT user_id")
       .where("published = ?", .{true});

   var users: std.ArrayList(User) = .{};
   defer users.deinit(allocator);

   var query = try db.newSelect(User);
   defer query.deinit();

   try query
       .whereIn("id", subquery)
       .scan(&users);
   ```

---

### Story 4.5: Query Hook System for Observability

**As a** Zig developer,
**I want** 注册查询钩子以记录 SQL 语句、测量执行时间、追踪性能瓶颈，
**so that** 我能够监控和优化应用的数据库交互。

#### Acceptance Criteria

1. **AC4.5.1**: 定义 `QueryHook` 接口，包含 `beforeQuery` 和 `afterQuery` 回调
2. **AC4.5.2**: DB 提供 `.addQueryHook(hook)` 方法注册全局钩子
3. **AC4.5.3**: beforeQuery 接收 SQL 语句和参数，可用于日志记录或修改
4. **AC4.5.4**: afterQuery 接收执行结果（成功或错误）和执行时长
5. **AC4.5.5**: 提供内置的 `LoggingHook` 实现，自动打印所有查询
6. **AC4.5.6**: 提供内置的 `PerformanceHook` 实现，追踪慢查询
7. **AC4.5.7**: 钩子支持链式调用（多个钩子按注册顺序执行）
8. **AC4.5.8**: 使用示例：
   ```zig
   const QueryHook = struct {
       const Self = @This();

       pub fn beforeQuery(self: *Self, sql: []const u8, args: []const QueryArg) !void {
           _ = self;
           std.debug.print("[SQL] {s}\n", .{sql});
           std.debug.print("[ARGS] {any}\n", .{args});
       }

       pub fn afterQuery(
           self: *Self,
           sql: []const u8,
           duration_ns: i64,
           err: ?anyerror,
       ) !void {
           _ = self;
           _ = sql;
           const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

           if (err) |e| {
               std.debug.print("[ERROR] Query failed: {}\n", .{e});
           } else {
               std.debug.print("[TIMING] Query completed in {d:.2}ms\n", .{duration_ms});
           }
       }
   };

   // 注册钩子
   var logging_hook = QueryHook{};
   try db.addQueryHook(&logging_hook);

   // 所有查询自动触发钩子
   var users: std.ArrayList(User) = .{};
   defer users.deinit(allocator);

   try db.newSelect(User)
       .where("age > ?", .{18})
       .scan(&users);
   ```

---

### Story 4.6: Enhanced Error Handling and Debug Mode

**As a** Zig developer,
**I want** 清晰的错误消息和 debug 模式，
**so that** 我能够快速定位和修复数据库相关问题。

#### Acceptance Criteria

1. **AC4.6.1**: 所有错误类型包含详细的上下文信息（SQL、参数、错误位置）
2. **AC4.6.2**: 提供 `DBOptions.debug = true` 选项启用 debug 模式
3. **AC4.6.3**: Debug 模式自动打印生成的 SQL 语句和参数
4. **AC4.6.4**: 查询构建器提供 `.explain()` 方法返回生成的 SQL（不执行）
5. **AC4.6.5**: 连接错误、查询错误、类型转换错误返回明确的错误类型
6. **AC4.6.6**: 错误消息包含足够信息帮助调试（不需要额外日志）
7. **AC4.6.7**: 使用示例：
   ```zig
   // 启用 debug 模式
   const db = try DB.init(allocator, conn, .postgresql, .{
       .debug = true,
   });
   defer db.deinit();

   // 查看生成的 SQL（不执行）
   var query = try db.newSelect(User);
   defer query.deinit();

   const sql = try query
       .where("age > ?", .{18})
       .orderBy("created_at", .desc)
       .explain(); // 返回 SQL 字符串

   defer allocator.free(sql);
   std.debug.print("Generated SQL:\n{s}\n", .{sql});
   ```

---

### Story 4.7: Comprehensive Documentation and Examples

**As a** Zig developer,
**I want** 完整的 API 文档和实用示例，
**so that** 我能够快速学习 ZORM 并应用到项目中。

#### Acceptance Criteria

1. **AC4.7.1**: 所有公共 API 函数包含完整的文档注释（使用 Zig `///` 语法）
2. **AC4.7.2**: 文档包含：功能说明、参数描述、返回值、错误类型、使用示例
3. **AC4.7.3**: 提供 `examples/` 目录，包含常见场景的完整示例程序：
   - `basic.zig` - 基础 CRUD 操作
   - `transaction.zig` - 事务管理
   - `schema.zig` - Schema 管理和迁移
   - `join.zig` - JOIN 查询
   - `upsert.zig` - ON CONFLICT upsert
   - `hooks.zig` - 查询钩子和日志
4. **AC4.7.4**: 提供 `README.md`，包含快速开始指南、特性介绍、构建说明
5. **AC4.7.5**: 使用 `zig build docs` 生成 HTML 文档
6. **AC4.7.6**: 所有示例代码可编译并通过测试验证
7. **AC4.7.7**: 提供性能基准测试结果和最佳实践建议

---

### Story 4.8: Performance Optimization and Benchmarks

**As a** Zig developer,
**I want** ZORM 提供接近原生 PostgreSQL 协议的性能，
**so that** 我不必为了便利性牺牲应用性能。

#### Acceptance Criteria

1. **AC4.8.1**: 查询构建器使用 Arena 分配器优化临时内存分配
2. **AC4.8.2**: SQL 生成过程预分配缓冲区，减少多次分配
3. **AC4.8.3**: 结果扫描优化，最小化数据拷贝
4. **AC4.8.4**: comptime 优化：类型映射、SQL 模板生成在编译时完成
5. **AC4.8.5**: 提供性能基准测试（`benchmarks/` 目录）：
   - 批量插入性能（与 pg.zig 原生操作对比）
   - 复杂查询构建性能
   - 结果扫描性能
6. **AC4.8.6**: 性能目标：ZORM 开销不超过 pg.zig 原生操作的 5%
7. **AC4.8.7**: 基准测试结果包含在文档中

---

## Checklist Results Report

_(此部分将在执行 PM Checklist 后填充)_

---

## Next Steps

### UX Expert Prompt

_(不适用 - ZORM 是后端库，无 UI/UX 需求)_

### Architect Prompt

Please review this PRD and create a comprehensive architecture document for ZORM. Focus on:

1. **Module Structure**: Define the internal organization of query builders, type system, connection management, and hooks
2. **API Design Patterns**: Ensure consistency with Bun ORM while leveraging Zig's comptime and type safety
3. **Performance Strategy**: Detail how to achieve <5% overhead compared to pg.zig native operations
4. **Testing Architecture**: Unit test framework, integration test setup with real PostgreSQL, benchmark infrastructure
5. **Build System**: Complete build.zig configuration for library, tests, examples, and documentation generation

Use this PRD as the single source of truth for all functional requirements and user experience expectations.
