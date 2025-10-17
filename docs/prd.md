# zorm Product Requirements Document (PRD)

**Version**: v1.0
**Date**: 2025-01-16
**Author**: John (Product Manager)
**Project**: ZORM - SQL-first Zig ORM
**Target Language**: Zig 0.15.2+

---

## Goals and Background Context

### Goals

如果 zorm PRD 成功执行，将实现以下成果：

- 为 Zig 开发者提供一个功能完整的 SQL-first ORM，实现 Bun ORM 的所有核心功能（查询构建、Schema 管理、关系映射、事务支持）
- 利用 Zig 的 `comptime` 特性在编译时完成类型检查和代码生成，实现零运行时反射开销和卓越性能
- 支持三大主流开源数据库（PostgreSQL、MySQL、SQLite），通过编译时方言系统确保跨数据库兼容性
- 提供符合 Zig 语言哲学的显式内存管理（Allocator 模式）和强制错误处理（`!T` 错误联合类型）
- 建立一个类型安全、易于使用、高性能的 ORM 框架，成为 Zig 生态系统中数据库交互的首选工具

### Background Context

随着 Zig 语言在系统编程和高性能应用领域的快速崛起，开发者迫切需要一个现代化的 ORM 工具来简化数据库交互。传统 ORM（如 Go 的 GORM）依赖运行时反射进行类型映射和查询构建，这不仅带来性能开销，也违背了 Zig "显式优于隐式"的核心理念。Zig 的 `comptime` 特性提供了独特的优势：可以在编译时完成所有类型检查、SQL 生成和代码优化，从而实现零运行时开销的抽象。

Bun ORM 在 TypeScript/JavaScript 生态中已经证明了 SQL-first 方法的成功——它通过类型安全的查询构建器提供便利性，同时保持对底层 SQL 的完全控制。zorm 旨在将这一成熟的设计理念引入 Zig 生态，并通过 Zig 的编译时能力将性能推向极致。我们的目标是创建一个既保持 Zig 语言哲学（显式内存管理、强制错误处理、零成本抽象），又提供现代 ORM 便利性（链式 API、关系映射、迁移系统）的工具，让 Zig 开发者能够高效、安全地构建数据驱动的应用程序。

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | v1.0 | Initial PRD draft | John (PM) |

---

## Requirements

### Functional Requirements

**FR1**: 用户必须能够创建和管理数据库连接实例，支持连接池配置（最大连接数、空闲连接数、连接生命周期）

**FR2**: 用户必须能够使用类型安全的链式 API 构建 SELECT 查询，支持列选择、WHERE 条件、JOIN、ORDER BY、GROUP BY、HAVING、LIMIT、OFFSET、DISTINCT

**FR3**: 用户必须能够执行 INSERT 操作，支持单行插入、批量插入、RETURNING 子句（PostgreSQL/SQLite）、ON CONFLICT（PostgreSQL/SQLite）、ON DUPLICATE KEY UPDATE（MySQL）

**FR4**: 用户必须能够执行 UPDATE 操作，支持条件更新、批量更新、部分字段更新

**FR5**: 用户必须能够执行 DELETE 操作，支持条件删除、批量删除、软删除支持

**FR6**: 用户必须能够定义 Zig 结构体作为数据模型，ORM 自动推断 SQL 类型映射（通过 comptime 反射）

**FR7**: 用户必须能够执行多表 JOIN 操作（INNER、LEFT、RIGHT、FULL、CROSS），支持复杂的关联查询

**FR8**: 用户必须能够使用子查询和 CTE（Common Table Expressions），包括递归 CTE

**FR9**: 用户必须能够管理数据库事务（BEGIN、COMMIT、ROLLBACK），支持嵌套事务和保存点

**FR10**: 用户必须能够定义模型之间的关系（Belongs-To、Has-One、Has-Many、Many-to-Many），ORM 自动处理关联加载

**FR11**: 用户必须能够执行 Raw SQL 查询，并将结果扫描到 Zig 结构体

**FR12**: 用户必须能够注册查询钩子（BeforeQuery、AfterQuery），用于日志记录、性能监控、查询修改

**FR13**: 用户必须能够在编译时选择数据库方言（PostgreSQL、MySQL、SQLite），ORM 自动生成方言特定的 SQL 语法

**FR14**: 用户必须能够使用命名参数绑定查询参数，防止 SQL 注入

**FR15**: 用户必须能够定义和执行数据库迁移（CREATE TABLE、ALTER TABLE、DROP TABLE、CREATE INDEX），支持版本管理和回滚

**FR16**: 用户必须能够批量执行操作（批量插入、批量更新、批量删除），ORM 自动优化为单个 SQL 语句

**FR17**: 用户必须能够扫描查询结果到 Zig 数据结构（单行、多行、流式处理），支持可选字段和类型转换

**FR18**: 用户必须能够使用 UNION、INTERSECT、EXCEPT 进行集合操作

**FR19**: 用户必须能够定义和使用自定义类型映射（例如，JSON、UUID、数组类型）

**FR20**: 用户必须能够通过编译时检查验证 SQL 语法和类型安全，错误在编译时报告

### Non-Functional Requirements

**NFR1**: ORM 必须实现零运行时反射开销，所有类型检查和代码生成在编译时完成（通过 Zig 的 `comptime` 特性）

**NFR2**: ORM 必须提供编译时类型安全保证，不正确的类型映射或 SQL 语法错误必须在编译时检测

**NFR3**: ORM 必须使用显式内存管理（Allocator 模式），所有内存分配和释放由用户控制，无垃圾回收器

**NFR4**: ORM 必须强制错误处理，所有可能失败的操作返回错误联合类型（`!T`），用户必须显式处理或传播错误

**NFR5**: ORM 的查询执行性能必须超越依赖运行时反射的 ORM（如 GORM），目标是接近手写 SQL 的性能（<5% 开销）

**NFR6**: ORM 必须确保内存安全，使用 Zig 的 `std.testing.allocator` 检测内存泄漏，测试覆盖率达到 80% 以上

**NFR7**: ORM 必须提供完整的文档，包括 API 参考、使用指南、最佳实践、性能优化建议、完整示例代码

**NFR8**: ORM 必须支持跨平台编译（Linux、macOS、Windows），使用 Zig 的交叉编译能力

**NFR9**: ORM 必须提供清晰、可操作的错误信息，包含错误类型、上下文、建议的修复方法

**NFR10**: ORM 的方言系统必须可扩展，允许用户添加自定义数据库方言而无需修改核心代码

**NFR11**: ORM 必须保持 API 的向后兼容性，遵循语义化版本控制（SemVer）

**NFR12**: ORM 必须提供性能基准测试工具，允许用户对比不同操作的性能（批量插入、复杂查询、事务吞吐量）

---

## Technical Assumptions

### Repository Structure: Monorepo

**决策**: 使用单一仓库（Monorepo）结构，所有 zorm 代码（核心库、方言实现、测试、示例）位于同一个 Git 仓库中。

**理由**:
- zorm 是一个单一的库产品，不是微服务架构
- Monorepo 简化了版本管理和跨模块重构
- Zig 的构建系统（build.zig）天然支持 Monorepo 结构
- 便于维护一致的代码风格和依赖版本

### Service Architecture: Library/Package

**决策**: zorm 是一个 Zig 库（Library），而非独立服务或应用程序。

**架构特点**:
- 编译为静态库，用户通过 `build.zig` 的 `addModule` 引入
- 无独立运行时，完全嵌入到用户应用程序中
- 无网络服务、HTTP API 或独立进程

**理由**:
- ORM 的本质是数据库访问层，应作为库而非服务
- 静态链接提供最佳性能和部署简便性
- 符合 Zig 生态的标准实践

### Testing Requirements: Comprehensive Testing Pyramid

**决策**: 实施完整的测试金字塔，包括单元测试、集成测试、内存安全测试。

**测试策略**:

1. **单元测试**（70%）:
   - 使用 Zig 内置测试框架（`zig test`）
   - 测试所有公共 API 和边界条件
   - 使用 `std.testing.allocator` 自动检测内存泄漏
   - Mock 数据库连接，测试查询构建逻辑

2. **集成测试**（25%）:
   - 测试与真实数据库的交互（PostgreSQL、MySQL、SQLite）
   - 使用 Docker 容器提供隔离的测试数据库环境
   - 验证跨数据库方言的兼容性
   - 测试事务、并发、性能场景

3. **性能基准测试**（5%）:
   - 批量插入性能（1000 行）
   - 复杂查询性能（多表 JOIN）
   - 内存使用分析
   - 与手写 SQL 和其他 ORM 的对比

**覆盖率目标**:
- 核心模块（DB、Query Builder）：90% 覆盖率
- 方言系统：80% 覆盖率
- 整体项目：80% 覆盖率（<5000 LOC）或 60%（>5000 LOC）

**理由**:
- 高覆盖率确保 comptime 代码的正确性（编译时错误难以调试）
- 内存泄漏检测是 Zig 项目的标准实践
- 集成测试验证与实际数据库的兼容性
- 性能基准测试支持 NFR5（<5% 开销目标）

### Additional Technical Assumptions and Requests

**编程语言**: Zig 0.15.2+
- **理由**: 需要最新的 `comptime` 特性和稳定的 API
- **约束**: 必须保持与 Zig 0.15.x 系列的兼容性

**数据库驱动**: C 库绑定
- **PostgreSQL**: `libpq`（通过 `@cImport`）
- **MySQL**: `libmysqlclient`（通过 `@cImport`）
- **SQLite**: `sqlite3`（通过 `@cImport`）
- **理由**:
  - 专注于三大主流开源数据库，覆盖 90%+ 的使用场景
  - 直接使用官方 C 驱动确保最佳性能和稳定性
  - 简化测试和维护负担（3 个数据库 vs 5 个）
  - SQLite 适合嵌入式场景，PostgreSQL 和 MySQL 覆盖服务器场景

**构建系统**: Zig Build System (`build.zig`)
- 使用 `std.Build` API 配置构建
- 支持可选的数据库驱动编译（通过 `-Dpostgres=true` 等标志）
- 集成单元测试（`zig build test`）
- 生成文档（`zig build docs`）
- 提供示例程序构建目标

**包管理**: Zig Package Manager
- 使用 `build.zig.zon` 定义包元数据
- 发布到 Zig 官方包索引（当 Zig 包管理器稳定后）
- 暂时支持通过 Git submodule 或 `fetchFromGitHub` 引入

**文档生成**: Zig 内置文档系统
- 使用 `///` 文档注释（Doc Comments）
- 通过 `zig build docs` 生成 HTML 文档
- 提供完整的 API 参考、使用指南、最佳实践

**开发工具**:
- **代码格式化**: `zig fmt`（强制统一代码风格）
- **静态分析**: `zig check`（编译时检查，无需额外工具）
- **调试**: GDB/LLDB 支持（Zig 生成标准调试符号）
- **CI/CD**: GitHub Actions（跨平台测试 Linux/macOS/Windows）

**跨平台支持**:
- **目标平台**: Linux（x86_64、ARM64）、macOS（x86_64、ARM64）、Windows（x86_64）
- **交叉编译**: 使用 Zig 的交叉编译能力，从任意平台构建任意目标
- **理由**: Zig 的跨平台能力是核心优势，应充分利用

**内存管理策略**:
- 所有 API 接受 `std.mem.Allocator` 参数
- 查询构建器使用 `ArenaAllocator` 管理临时分配
- 提供 `deinit()` 方法释放资源
- 使用 `defer` 和 `errdefer` 确保异常安全

**错误处理策略**:
- 所有可能失败的操作返回 `!T`（错误联合类型）
- 定义专用的 `zorm.Error` 错误集
- 提供详细的错误上下文（错误类型、SQL、参数）
- 不使用 `panic`（除非检测到不可恢复的编程错误）

**性能优化策略**:
- 使用 `inline` 关键字内联热路径函数
- 使用 `comptime` 预计算所有可编译时计算的值
- 避免不必要的内存分配（复用 buffer）
- 使用批量操作减少数据库往返次数

**版本控制策略**:
- 遵循语义化版本控制（SemVer 2.0）
- API 稳定后（v1.0.0）保证向后兼容性
- 使用 Git tags 标记发布版本
- 维护 CHANGELOG.md 记录所有变更

---

## Epic List

### Epic 1: 项目基础架构与核心 DB 管理
**目标**: 建立项目框架（构建系统、测试基础、CI/CD）、实现核心 DB 实例管理和连接池，交付一个可运行的"Hello World"查询。

### Epic 2: 类型安全的查询构建器（SELECT & Raw SQL）
**目标**: 实现 SELECT 查询构建器和 Raw SQL 支持，提供链式 API（WHERE、JOIN、ORDER BY、LIMIT 等），实现结果扫描到 Zig 结构体。

### Epic 3: 数据写入操作（INSERT、UPDATE、DELETE）
**目标**: 实现 INSERT、UPDATE、DELETE 查询构建器，支持批量操作、RETURNING 子句、ON CONFLICT 等方言特定特性。

### Epic 4: 编译时方言系统与多数据库支持
**目标**: 实现 PostgreSQL、MySQL、SQLite 的方言系统，通过 comptime 特性检测自动生成方言特定的 SQL，确保跨数据库兼容性。

### Epic 5: Schema 管理与类型映射
**目标**: 实现 comptime 类型反射，自动推断 Zig 类型到 SQL 类型的映射，提供 CREATE TABLE、DROP TABLE、CREATE INDEX 等 DDL 支持。

### Epic 6: 事务管理与查询钩子系统
**目标**: 实现事务支持（BEGIN、COMMIT、ROLLBACK、保存点），添加查询钩子系统（BeforeQuery、AfterQuery）用于日志和监控。

### Epic 7: 高级查询特性（CTE、子查询、集合操作）
**目标**: 实现 CTE（WITH 子句）、子查询、UNION/INTERSECT/EXCEPT 等高级 SQL 特性，支持递归 CTE。

### Epic 8: 关系映射与关联加载
**目标**: 实现模型关系定义（Belongs-To、Has-One、Has-Many、Many-to-Many），支持 Eager Loading 和 Lazy Loading。

---

## Epic 1: 项目基础架构与核心 DB 管理

**Epic 目标**:
建立 zorm 项目的基础架构，包括构建系统、目录结构、测试框架和 CI/CD 配置。实现核心的数据库连接管理和 DB 实例，集成 Zig 的 Allocator 和错误处理系统。交付一个可运行的 Raw SQL 查询功能，证明系统端到端可用，并为后续 Epic 奠定坚实基础。

### Story 1.1: 初始化项目结构与构建系统

**As a** Zig 开发者，
**I want** 一个完整的项目结构和可工作的构建配置，
**so that** 我可以编译库、运行测试、查看文档，并将 zorm 集成到我的项目中。

**Acceptance Criteria:**

1. 创建标准的 Zig 项目目录结构：
   ```
   zorm/
   ├── build.zig          # 构建配置
   ├── build.zig.zon      # 包元数据
   ├── src/
   │   └── zorm.zig       # 主入口
   ├── tests/             # 测试目录
   └── examples/          # 示例代码
   ```

2. `build.zig` 必须包含以下构建目标：
   - `zig build` - 构建静态库
   - `zig build test` - 运行所有测试
   - `zig build docs` - 生成文档
   - `zig build fmt` - 格式化代码
   - `zig build run-example` - 运行示例程序

3. `build.zig.zon` 必须包含项目元数据（名称、版本、作者、依赖）

4. 使用 `addModule` API 将 zorm 暴露为可导入的模块

5. 创建 `README.md`，包含项目介绍、快速开始、构建说明

6. 创建 `.gitignore`，排除 Zig 构建产物（`zig-out/`、`zig-cache/`）

7. 所有代码必须通过 `zig fmt` 格式化

### Story 1.2: 实现核心错误处理系统

**As a** zorm 库开发者，
**I want** 一个统一的错误处理系统，
**so that** 所有数据库操作都能以类型安全的方式报告错误，用户可以清晰地处理各种失败场景。

**Acceptance Criteria:**

1. 定义 `zorm.Error` 错误集，包含至少以下错误类型：
   - `ConnectionFailed` - 数据库连接失败
   - `QueryFailed` - 查询执行失败
   - `NoRows` - 查询未返回结果
   - `InvalidSQL` - SQL 语法错误
   - `OutOfMemory` - 内存分配失败

2. 所有可能失败的公共 API 必须返回 `!T`（错误联合类型）

3. 创建 `src/error.zig` 模块，集中管理所有错误定义

4. 提供错误转字符串的辅助函数（用于调试和日志）

5. 编写单元测试，验证错误可以正确传播和捕获

6. 文档必须说明每个 API 可能抛出的错误类型

### Story 1.3: 实现 Allocator 集成和内存管理基础

**As a** Zig 开发者，
**I want** zorm 的所有内存分配都通过我提供的 Allocator，
**so that** 我可以完全控制内存管理策略，并能检测内存泄漏。

**Acceptance Criteria:**

1. 所有需要分配内存的 API 必须接受 `std.mem.Allocator` 参数

2. 创建 `QueryContext` 结构体，使用 `ArenaAllocator` 管理查询临时分配：
   ```zig
   pub const QueryContext = struct {
       arena: std.heap.ArenaAllocator,
       pub fn init(base_allocator: Allocator) QueryContext;
       pub fn deinit(self: *QueryContext) void;
       pub fn allocator(self: *QueryContext) Allocator;
   };
   ```

3. 所有需要清理的资源必须提供 `deinit()` 方法

4. 编写测试使用 `std.testing.allocator`，确保所有分配都被释放

5. 在测试中故意触发内存泄漏，验证测试框架能检测到

6. 文档必须说明内存管理的所有权语义（谁分配、谁释放）

### Story 1.4: 实现数据库连接抽象和 PostgreSQL libpq 绑定

**As a** Zig 开发者，
**I want** 能够通过 zorm 连接到 PostgreSQL 数据库，
**so that** 我可以开始执行查询和管理数据。

**Acceptance Criteria:**

1. 通过 `@cImport` 绑定 `libpq` C 库

2. 创建 `Connection` 接口，定义所有数据库连接必须实现的方法：
   ```zig
   pub const Connection = struct {
       pub fn exec(self: *Connection, sql: []const u8, params: []const QueryArg) !Result;
       pub fn close(self: *Connection) !void;
   };
   ```

3. 实现 `PostgresConnection` 结构体，封装 `libpq` 的 `PGconn`

4. 提供 `openPostgres` 函数，接受 DSN 字符串并返回连接：
   ```zig
   pub fn openPostgres(allocator: Allocator, dsn: []const u8) !*PostgresConnection;
   ```

5. 支持基本的连接参数（host, port, user, password, database）

6. 连接失败必须返回清晰的错误信息（包含失败原因）

7. 在 `build.zig` 中使用 `linkSystemLibrary("pq")` 链接 libpq

8. 编写集成测试，验证能成功连接到测试数据库（使用环境变量配置）

9. 提供示例代码展示如何连接 PostgreSQL

### Story 1.5: 实现 DB 实例管理和连接池基础

**As a** Zig 开发者，
**I want** 一个 DB 实例来管理数据库连接和配置，
**so that** 我可以复用连接、配置全局选项、并通过统一的接口执行查询。

**Acceptance Criteria:**

1. 创建 `DB` 结构体，作为 zorm 的核心入口点：
   ```zig
   pub const DB = struct {
       allocator: Allocator,
       conn: *Connection,
       options: DBOptions,

       pub fn init(allocator: Allocator, conn: *Connection, options: DBOptions) !*DB;
       pub fn deinit(self: *DB) void;
       pub fn close(self: *DB) !void;
   };
   ```

2. 定义 `DBOptions` 配置结构：
   ```zig
   pub const DBOptions = struct {
       discard_unknown_columns: bool = false,
       max_open_conns: u32 = 25,
       max_idle_conns: u32 = 25,
       conn_max_lifetime: u64 = 300, // seconds
   };
   ```

3. DB 实例必须持有对底层连接的引用

4. 提供 `clone()` 方法，支持创建共享连接的 DB 实例副本

5. 实现基础的统计信息收集（查询计数、错误计数）

6. 编写单元测试，验证 DB 实例的创建、配置、销毁

7. 文档必须说明 DB 实例的生命周期管理

### Story 1.6: 实现 Raw SQL 查询执行与结果处理

**As a** Zig 开发者，
**I want** 能够执行原始 SQL 查询并处理结果，
**so that** 我可以在查询构建器尚未实现的情况下直接与数据库交互，并验证 zorm 的端到端功能。

**Acceptance Criteria:**

1. 在 `DB` 上添加 `exec` 方法执行 SQL：
   ```zig
   pub fn exec(self: *DB, sql: []const u8) !ExecResult;
   ```

2. 在 `DB` 上添加 `query` 方法执行 SELECT：
   ```zig
   pub fn query(self: *DB, sql: []const u8) !Rows;
   ```

3. 实现 `Rows` 迭代器，支持逐行读取结果：
   ```zig
   pub const Rows = struct {
       pub fn next(self: *Rows) !?Row;
       pub fn deinit(self: *Rows) void;
   };
   ```

4. 实现 `Row` 结构，支持按索引或列名获取值：
   ```zig
   pub const Row = struct {
       pub fn getInt(self: *Row, comptime T: type, index: usize) !T;
       pub fn getString(self: *Row, index: usize) ![]const u8;
       pub fn getBool(self: *Row, index: usize) !bool;
   };
   ```

5. 支持参数化查询，防止 SQL 注入

6. 编写集成测试，验证能执行简单的 CRUD 操作：
   - CREATE TABLE
   - INSERT with RETURNING
   - SELECT with WHERE
   - UPDATE
   - DELETE
   - DROP TABLE

7. 提供完整的示例程序，展示 Raw SQL 的完整使用流程

### Story 1.7: 设置测试框架和内存泄漏检测

**As a** zorm 库开发者，
**I want** 一个完善的测试基础设施，
**so that** 我可以自信地开发新功能，并确保不会引入内存泄漏或回归错误。

**Acceptance Criteria:**

1. 在 `tests/` 目录下创建测试文件结构，对应 `src/` 的模块

2. 所有测试必须使用 `std.testing.allocator`，自动检测内存泄漏

3. 创建测试辅助工具：
   - `setupTestDB()` - 创建临时测试数据库
   - `teardownTestDB()` - 清理测试数据库
   - `withTestDB()` - 自动管理测试数据库生命周期

4. 使用环境变量配置测试数据库连接：
   - `ZORM_TEST_POSTGRES_DSN`
   - 如果未设置，跳过集成测试并输出警告

5. `zig build test` 必须运行所有单元测试和集成测试

6. 编写至少 10 个测试，覆盖以前 Stories 的核心功能：
   - 错误处理测试（3 个）
   - Allocator 集成测试（2 个）
   - 连接管理测试（2 个）
   - Raw SQL 执行测试（3 个）

7. 测试覆盖率达到 70% 以上（使用 `zig build test --summary all` 检查）

8. 所有测试必须能独立运行，不依赖执行顺序

### Story 1.8: 配置 CI/CD 和跨平台构建

**As a** zorm 项目维护者，
**I want** 自动化的 CI/CD 流程，
**so that** 每次提交都能自动测试、构建，并确保跨平台兼容性。

**Acceptance Criteria:**

1. 创建 `.github/workflows/ci.yml`，配置 GitHub Actions

2. CI 必须在以下环境运行：
   - Linux (x86_64) - Ubuntu 最新版
   - macOS (x86_64, ARM64) - macOS 最新版
   - Windows (x86_64) - Windows 最新版

3. CI 必须执行以下步骤：
   - 安装 Zig 0.15.2
   - 安装 libpq（PostgreSQL 客户端库）
   - 运行 `zig build fmt --check`（检查代码格式）
   - 运行 `zig build test`（执行所有测试）
   - 运行 `zig build docs`（生成文档）

4. CI 必须设置 PostgreSQL 服务（使用 Docker 或 GitHub Actions 服务）

5. 所有测试必须在 CI 环境中通过

6. PR 必须通过 CI 检查才能合并

7. 添加 CI 状态徽章到 `README.md`

8. 配置 dependabot 或类似工具，自动更新 GitHub Actions 依赖

---

## Epic 2: 类型安全的查询构建器（SELECT）

**Epic 目标**:
实现类型安全的 SELECT 查询构建器，提供流畅的链式 API，支持 WHERE 条件、JOIN、ORDER BY、GROUP BY、LIMIT/OFFSET 等核心 SQL 特性。利用 Zig 的 `comptime` 特性在编译时完成类型检查和 SQL 生成，实现零运行时反射开销。支持将查询结果自动扫描到 Zig 结构体，提供类型安全且高性能的数据库查询体验。

### Story 2.1: 实现基础 SelectQuery 框架与简单查询

**As a** Zig 开发者，
**I want** 能够使用 `db.newSelect(Model)` 创建类型安全的 SELECT 查询，
**so that** 我可以用链式 API 构建查询，而不是手写 SQL 字符串。

**Acceptance Criteria:**

1. 创建 `SelectQuery` 泛型函数，接受模型类型参数：
   ```zig
   pub fn SelectQuery(comptime T: type) type {
       return struct {
           allocator: Allocator,
           db: *DB,
           table_name: []const u8,
           // ... 其他字段
       };
   }
   ```

2. 在 `DB` 上添加工厂方法：
   ```zig
   pub fn newSelect(self: *DB, comptime T: type) !*SelectQuery(T);
   ```

3. SelectQuery 必须提供 `deinit()` 方法释放资源

4. 实现 `buildSQL()` 方法生成 SQL 字符串

5. 实现最简单的查询：`SELECT * FROM table`

6. 使用 `comptime` 在编译时从类型 T 提取表名（优先使用 `T.table_name`，否则使用 `@typeName(T)`）

7. 编写单元测试验证 SQL 生成正确：
   ```zig
   var query = try db.newSelect(User);
   defer query.deinit();
   const sql = try query.buildSQL();
   // 期望: "SELECT * FROM users"
   ```

8. 确保内存安全：使用 `std.testing.allocator` 检测泄漏

### Story 2.2: 实现 WHERE 条件构建（AND/OR 逻辑）

**As a** Zig 开发者，
**I want** 能够添加 WHERE 条件到 SELECT 查询，支持 AND 和 OR 逻辑组合，
**so that** 我可以精确地筛选数据库记录。

**Acceptance Criteria:**

1. 添加 `where()` 方法，支持参数化条件：
   ```zig
   pub fn where(self: *Self, condition: []const u8, args: anytype) !*Self;
   ```

2. 添加 `whereOr()` 方法，支持 OR 条件：
   ```zig
   pub fn whereOr(self: *Self, condition: []const u8, args: anytype) !*Self;
   ```

3. 实现 `WhereClause` 结构存储条件：
   ```zig
   pub const WhereClause = struct {
       condition: []const u8,
       args: []const QueryArg,
       operator: WhereOperator, // .and_op 或 .or_op
   };
   ```

4. 实现 `QueryArg` 联合类型支持多种参数类型：
   ```zig
   pub const QueryArg = union(enum) {
       int: i64,
       uint: u64,
       float: f64,
       bool: bool,
       string: []const u8,
       null_val: void,
   };
   ```

5. 实现 `allocArgs()` 辅助函数，使用 `comptime` 将元组转换为 `QueryArg` 数组

6. `buildSQL()` 必须正确生成 WHERE 子句，使用 AND/OR 连接多个条件

7. 支持链式调用：
   ```zig
   try query.where("age > ?", .{18})
            .where("status = ?", .{"active"})
            .whereOr("role = ?", .{"admin"});
   // 生成: WHERE age > $1 AND status = $2 OR role = $3
   ```

8. 编写测试验证：
   - 单个 WHERE 条件
   - 多个 AND 条件
   - 混合 AND 和 OR 条件
   - 不同类型的参数（int, string, bool）

### Story 2.3: 实现列选择与 comptime 类型反射

**As a** Zig 开发者，
**I want** 能够选择特定的列或自动选择模型的所有字段，
**so that** 我可以优化查询性能并确保类型安全。

**Acceptance Criteria:**

1. 添加 `column()` 方法选择单个列：
   ```zig
   pub fn column(self: *Self, col: []const u8) !*Self;
   ```

2. 添加 `allColumns()` 方法，使用 `comptime` 自动选择类型 T 的所有字段：
   ```zig
   pub fn allColumns(self: *Self) !*Self;
   ```

3. `allColumns()` 必须使用 `@typeInfo(T).Struct.fields` 提取字段名

4. 创建辅助函数 `getTableName()` 和 `getFieldNames()`，使用 `comptime` 提取元数据

5. 如果没有调用 `column()` 或 `allColumns()`，默认行为是 `SELECT *`

6. `buildSQL()` 必须正确生成列列表：
   ```zig
   try query.column("id").column("name").column("email");
   // 生成: SELECT id, name, email FROM users
   ```

7. 编写测试验证：
   - 默认 `SELECT *`
   - 选择特定列
   - `allColumns()` 正确提取所有字段
   - 结合 WHERE 条件

8. 文档必须说明 `allColumns()` 的编译时特性和零运行时开销

### Story 2.4: 实现 ORDER BY、LIMIT 和 OFFSET

**As a** Zig 开发者，
**I want** 能够对查询结果排序、限制返回数量和跳过记录，
**so that** 我可以实现分页和排序功能。

**Acceptance Criteria:**

1. 添加 `orderBy()` 方法：
   ```zig
   pub fn orderBy(self: *Self, col: []const u8, direction: OrderDirection) !*Self;

   pub const OrderDirection = enum { asc, desc };
   ```

2. 支持多列排序（多次调用 `orderBy()`）

3. 添加 `limit()` 方法：
   ```zig
   pub fn limit(self: *Self, n: usize) *Self;
   ```

4. 添加 `offset()` 方法：
   ```zig
   pub fn offset(self: *Self, n: usize) *Self;
   ```

5. `buildSQL()` 必须按正确顺序生成 ORDER BY, LIMIT, OFFSET 子句

6. 支持链式调用：
   ```zig
   try query.where("status = ?", .{"active"})
            .orderBy("created_at", .desc)
            .orderBy("name", .asc)
            .limit(10)
            .offset(20);
   // 生成: SELECT * FROM users WHERE status = $1
   //       ORDER BY created_at DESC, name ASC LIMIT 10 OFFSET 20
   ```

7. 编写测试验证：
   - 单列排序（ASC 和 DESC）
   - 多列排序
   - LIMIT 单独使用
   - LIMIT + OFFSET 组合
   - 完整查询（WHERE + ORDER BY + LIMIT + OFFSET）

### Story 2.5: 实现 JOIN 操作（INNER、LEFT、RIGHT、FULL）

**As a** Zig 开发者，
**I want** 能够执行多表 JOIN 操作，
**so that** 我可以查询关联数据和执行复杂的数据分析。

**Acceptance Criteria:**

1. 定义 `JoinType` 枚举：
   ```zig
   pub const JoinType = enum {
       inner, left, right, full, cross
   };
   ```

2. 添加通用 `join()` 方法：
   ```zig
   pub fn join(
       self: *Self,
       join_type: JoinType,
       table: []const u8,
       condition: []const u8
   ) !*Self;
   ```

3. 添加便利方法：
   ```zig
   pub fn innerJoin(self: *Self, table: []const u8, condition: []const u8) !*Self;
   pub fn leftJoin(self: *Self, table: []const u8, condition: []const u8) !*Self;
   pub fn rightJoin(self: *Self, table: []const u8, condition: []const u8) !*Self;
   pub fn fullJoin(self: *Self, table: []const u8, condition: []const u8) !*Self;
   ```

4. 支持多个 JOIN（存储在 `ArrayList(JoinClause)` 中）

5. `buildSQL()` 必须在 FROM 和 WHERE 之间插入 JOIN 子句

6. 支持链式调用：
   ```zig
   try query.column("u.name")
            .column("p.title")
            .leftJoin("posts p", "p.user_id = u.id")
            .where("u.status = ?", .{"active"});
   // 生成: SELECT u.name, p.title FROM users u
   //       LEFT JOIN posts p ON p.user_id = u.id
   //       WHERE u.status = $1
   ```

7. 编写测试验证：
   - INNER JOIN
   - LEFT JOIN
   - 多个 JOIN
   - JOIN + WHERE 条件
   - JOIN + ORDER BY + LIMIT

8. 提供示例代码展示常见 JOIN 模式

### Story 2.6: 实现 GROUP BY 和 HAVING 子句

**As a** Zig 开发者，
**I want** 能够对查询结果分组并过滤分组结果，
**so that** 我可以执行聚合查询和统计分析。

**Acceptance Criteria:**

1. 添加 `groupBy()` 方法：
   ```zig
   pub fn groupBy(self: *Self, col: []const u8) !*Self;
   ```

2. 支持多个 GROUP BY 列（存储在 `ArrayList([]const u8)` 中）

3. 添加 `having()` 方法，语法类似 `where()`：
   ```zig
   pub fn having(self: *Self, condition: []const u8, args: anytype) !*Self;
   ```

4. `buildSQL()` 必须在正确位置生成 GROUP BY 和 HAVING 子句：
   - GROUP BY 在 WHERE 之后、HAVING 之前
   - HAVING 在 GROUP BY 之后、ORDER BY 之前

5. 支持链式调用：
   ```zig
   try query.column("user_id")
            .column("COUNT(*) as post_count")
            .groupBy("user_id")
            .having("COUNT(*) > ?", .{5})
            .orderBy("post_count", .desc);
   // 生成: SELECT user_id, COUNT(*) as post_count FROM posts
   //       GROUP BY user_id HAVING COUNT(*) > $1
   //       ORDER BY post_count DESC
   ```

6. 编写测试验证：
   - 单列 GROUP BY
   - 多列 GROUP BY
   - GROUP BY + HAVING
   - 聚合函数（COUNT, SUM, AVG, MAX, MIN）
   - 完整查询（JOIN + WHERE + GROUP BY + HAVING + ORDER BY）

### Story 2.7: 实现 DISTINCT 和聚合辅助方法

**As a** Zig 开发者，
**I want** 能够使用 DISTINCT 去重和便捷的聚合方法（如 count()），
**so that** 我可以简化常见查询模式。

**Acceptance Criteria:**

1. 添加 `setDistinct()` 方法：
   ```zig
   pub fn setDistinct(self: *Self) *Self;
   ```

2. `buildSQL()` 必须在 SELECT 后添加 DISTINCT 关键字

3. 添加 `count()` 便利方法：
   ```zig
   pub fn count(self: *Self) !usize;
   ```

4. `count()` 的实现：
   - 临时修改列为 `COUNT(*)`
   - 执行查询
   - 解析结果并返回数值
   - 不修改原始查询对象

5. 添加 `exists()` 便利方法：
   ```zig
   pub fn exists(self: *Self) !bool;
   ```

6. 支持链式调用：
   ```zig
   try query.setDistinct()
            .column("country")
            .where("active = ?", .{true});
   // 生成: SELECT DISTINCT country FROM users WHERE active = $1
   ```

7. 编写测试验证：
   - DISTINCT 查询
   - count() 返回正确数值
   - exists() 返回正确布尔值
   - DISTINCT + WHERE
   - DISTINCT + ORDER BY

8. 文档必须说明 `count()` 和 `exists()` 会执行查询，不仅仅是构建

### Story 2.8: 实现结果扫描到 Zig 结构体（comptime 类型映射）

**As a** Zig 开发者，
**I want** 能够将查询结果自动扫描到 Zig 结构体，
**so that** 我可以用类型安全的方式访问数据，而无需手动解析每个字段。

**Acceptance Criteria:**

1. 添加 `scan()` 方法，将结果扫描到 `ArrayList(T)`：
   ```zig
   pub fn scan(self: *Self, dest: *std.ArrayList(T)) !void;
   ```

2. 添加 `scanOne()` 方法，扫描单行：
   ```zig
   pub fn scanOne(self: *Self) !T;
   ```

3. 实现 `scanRow()` 辅助函数，使用 `comptime` 反射将 Row 映射到结构体：
   ```zig
   fn scanRow(comptime T: type, row: *Row, allocator: Allocator) !T;
   ```

4. `scanRow()` 必须：
   - 使用 `@typeInfo(T).Struct.fields` 遍历字段
   - 按索引或列名从 Row 获取值
   - 自动转换类型（使用 `row.getInt()`, `row.getString()` 等）
   - 处理可选字段（`?T`）

5. `scanOne()` 必须：
   - 自动添加 `LIMIT 1`
   - 如果无结果，返回 `error.NoRows`
   - 如果多行结果，只返回第一行

6. 支持使用示例：
   ```zig
   const User = struct {
       id: i64,
       name: []const u8,
       email: ?[]const u8,
       age: u32,
   };

   var users = std.ArrayList(User).init(allocator);
   defer users.deinit();

   try query.where("age > ?", .{18})
            .orderBy("created_at", .desc)
            .scan(&users);

   for (users.items) |user| {
       std.debug.print("{s}: {}\n", .{user.name, user.age});
   }
   ```

7. 编写测试验证：
   - 扫描多行到 ArrayList
   - scanOne() 返回单行
   - scanOne() 在无结果时抛出 error.NoRows
   - 处理可选字段（NULL 值）
   - 处理不同类型（int, string, bool）
   - 集成测试：完整的查询 + 扫描流程

8. 性能测试：验证 comptime 扫描的性能优于运行时反射（对比基准）

---

## Epic 3: 数据写入操作（INSERT、UPDATE、DELETE）

**Epic 目标**:
实现类型安全的 INSERT、UPDATE、DELETE 查询构建器，支持单行和批量操作。提供方言特定的高级特性，如 RETURNING 子句（PostgreSQL/SQLite）、ON CONFLICT（PostgreSQL/SQLite）、ON DUPLICATE KEY UPDATE（MySQL）。确保所有写操作都是类型安全的，并通过 comptime 优化性能。实现完整的 CRUD 能力，使 zorm 成为功能完整的数据库交互工具。

### Story 3.1: 实现基础 InsertQuery 框架与单行插入

**As a** Zig 开发者，
**I want** 能够使用 `db.newInsert(Model)` 插入单行数据，
**so that** 我可以用类型安全的方式向数据库添加记录。

**Acceptance Criteria:**

1. 创建 `InsertQuery` 泛型函数
2. 在 `DB` 上添加工厂方法 `newInsert()`
3. 添加 `value()` 方法添加单个值
4. 实现 `buildSQL()` 生成 INSERT 语句
5. 使用 comptime 提取字段并生成列列表
6. 实现 `exec()` 方法执行插入，返回 `InsertResult`
7. 支持完整的单行插入示例
8. 编写测试验证插入成功和内存安全

### Story 3.2: 实现批量 INSERT 与性能优化

**As a** Zig 开发者，
**I want** 能够批量插入多行数据，
**so that** 我可以高效地导入大量数据，减少数据库往返次数。

**Acceptance Criteria:**

1. 添加 `values()` 方法批量添加多个值
2. `buildSQL()` 为批量插入生成优化的 SQL
3. 正确生成占位符序列
4. 支持混合调用 `value()` 和 `values()`
5. 实现批量优化（单次网络往返、单个事务）
6. 支持批量插入使用示例
7. 编写测试验证批量插入（10 行、1000 行）
8. 性能基准测试：批量 vs. 循环单行插入

### Story 3.3: 实现 RETURNING 子句（PostgreSQL/SQLite）

**As a** Zig 开发者，
**I want** 能够在插入后立即获取生成的 ID 或其他列值，
**so that** 我可以在单次操作中完成插入和数据获取，避免额外查询。

**Acceptance Criteria:**

1. 添加 `setReturning()` 方法
2. 编译时检查当前方言是否支持 RETURNING
3. `buildSQL()` 添加 RETURNING 子句
4. 添加 `execReturning()` 方法执行并扫描返回的行
5. 支持返回特定列或全部列
6. 支持完整使用示例
7. 编写测试验证 RETURNING 功能
8. 文档说明方言支持情况

### Story 3.4: 实现 ON CONFLICT 与 UPSERT 支持

**As a** Zig 开发者，
**I want** 能够处理插入冲突（如唯一键冲突），
**so that** 我可以实现 UPSERT 逻辑（存在则更新，不存在则插入）。

**Acceptance Criteria:**

1. 添加 `onConflict()` 方法（PostgreSQL/SQLite）
2. 添加 `onDuplicateKeyUpdate()` 方法（MySQL）
3. 编译时检查方言支持
4. `buildSQL()` 插入冲突处理子句
5. 支持 DO NOTHING、DO UPDATE SET、ON DUPLICATE KEY UPDATE
6. 支持完整使用示例（PostgreSQL 和 MySQL）
7. 编写测试验证冲突处理
8. 提供 UPSERT 最佳实践示例

### Story 3.5: 实现 UpdateQuery 框架与条件更新

**As a** Zig 开发者，
**I want** 能够使用 `db.newUpdate(Model)` 更新数据库记录，
**so that** 我可以修改现有数据而不是重新插入。

**Acceptance Criteria:**

1. 创建 `UpdateQuery` 泛型函数
2. 在 `DB` 上添加工厂方法 `newUpdate()`
3. 添加 `set()` 方法设置更新字段
4. 复用 `where()` 方法
5. 实现 `buildSQL()` 生成 UPDATE 语句
6. 实现 `exec()` 返回 `UpdateResult`
7. 支持完整使用示例
8. 编写测试验证更新功能

### Story 3.6: 实现批量 UPDATE 与高级更新模式

**As a** Zig 开发者，
**I want** 能够高效地批量更新数据，支持计算字段更新，
**so that** 我可以执行复杂的数据转换和批量修改操作。

**Acceptance Criteria:**

1. 支持表达式更新（如 `age = age + 1`）
2. 支持子查询更新
3. 添加 `setFrom()` 方法从结构体设置值
4. 使用 comptime 自动生成 SET 子句
5. 添加无 WHERE 条件的安全检查
6. 支持批量更新使用示例
7. 编写测试验证表达式更新和 setFrom()
8. 文档强调无 WHERE 条件的危险性

### Story 3.7: 实现 DeleteQuery 框架与条件删除

**As a** Zig 开发者，
**I want** 能够使用 `db.newDelete(Model)` 删除数据库记录，
**so that** 我可以安全地移除不需要的数据。

**Acceptance Criteria:**

1. 创建 `DeleteQuery` 泛型函数
2. 在 `DB` 上添加工厂方法 `newDelete()`
3. 复用 `where()` 方法
4. 实现 `buildSQL()` 生成 DELETE 语句
5. 实现 `exec()` 返回 `DeleteResult`
6. 添加无 WHERE 条件的安全检查
7. 支持完整使用示例
8. 编写测试验证删除功能

### Story 3.8: 实现软删除支持与删除策略

**As a** Zig 开发者，
**I want** 能够实现软删除（标记删除而非物理删除），
**so that** 我可以保留历史数据并支持数据恢复。

**Acceptance Criteria:**

1. 添加软删除配置到 `DBOptions`
2. `DeleteQuery.exec()` 自动转换为 UPDATE（当配置了软删除）
3. 添加 `forceDelete()` 方法执行物理删除
4. SelectQuery 自动过滤软删除记录
5. 添加 `withTrashed()` 方法包含软删除记录
6. 添加 `onlyTrashed()` 方法只查询软删除记录
7. 支持完整使用示例
8. 编写测试验证软删除功能
9. 文档说明软删除最佳实践

---

## Epic 4: 编译时方言系统与多数据库支持

**Epic 目标**:
实现完整的数据库方言系统，支持 PostgreSQL、MySQL、SQLite 三大数据库。通过 Zig 的 `comptime` 特性在编译时选择方言并生成方言特定的 SQL 语法，实现零运行时开销的跨数据库兼容性。集成 MySQL 和 SQLite 的 C 驱动，确保所有查询构建器功能在三个数据库上都能正常工作。

### Story 4.1: 设计并实现 Dialect 枚举与特性检测系统

创建 `Dialect` 枚举，定义所有支持的数据库方言。实现 `comptime` 特性检测系统，允许在编译时查询方言是否支持特定功能（如 RETURNING、CTE、JSONB）。

### Story 4.2: 集成 MySQL libmysqlclient 驱动

通过 `@cImport` 绑定 MySQL 的 libmysqlclient C 库，实现 `MySQLConnection` 结构体，提供与 PostgreSQL 相同的连接接口。

### Story 4.3: 集成 SQLite sqlite3 驱动

通过 `@cImport` 绑定 SQLite 的 sqlite3 C 库，实现 `SQLiteConnection` 结构体，支持嵌入式数据库场景。

### Story 4.4: 在查询构建器中集成方言系统

重构 SelectQuery、InsertQuery、UpdateQuery、DeleteQuery，使其根据 DB 实例的方言生成正确的 SQL 语法。

### Story 4.5: 实现跨方言集成测试套件

创建全面的跨方言测试套件，确保所有查询构建器功能在 PostgreSQL、MySQL、SQLite 上都能正确工作。

---

## Epic 5: Schema 管理与类型映射

**Epic 目标**:
实现 comptime 类型反射系统，自动将 Zig 类型映射到 SQL 类型。提供 DDL 查询构建器（CREATE TABLE、DROP TABLE、CREATE INDEX），支持 Schema 定义和数据库迁移。利用 comptime 在编译时验证 Schema 定义的正确性。

### Story 5.1: 实现 comptime 类型到 SQL 类型的映射系统

实现 `zigToSQLType(comptime T: type)` 函数，支持基础类型映射和可选类型处理。

### Story 5.2: 实现 CreateTableQuery 构建器

创建 `CreateTableQuery(comptime T: type)` 泛型查询构建器，使用 comptime 反射提取字段并生成列定义。

### Story 5.3: 实现 DropTable、AlterTable 和 CreateIndex 构建器

实现 DDL 操作的完整支持，包括删除表、修改表结构、创建索引。

### Story 5.4: 实现基础迁移系统框架

创建 `Migration` 接口和 `Migrator` 结构，提供版本化的数据库迁移管理。

---

## Epic 6: 事务管理与查询钩子系统

**Epic 目标**:
实现完整的事务支持（BEGIN、COMMIT、ROLLBACK、保存点），提供自动事务管理和手动事务控制。实现查询钩子系统，允许用户在查询执行前后插入自定义逻辑（如日志记录、性能监控、查询修改）。

### Story 6.1: 实现基础事务 API（BEGIN、COMMIT、ROLLBACK）

在 `DB` 上添加 `beginTx()` 方法，实现 `Tx` 事务对象，支持提交、回滚和嵌套事务。

### Story 6.2: 实现自动事务管理（withTransaction 辅助方法）

提供 `db.withTransaction(callback)` 便利方法，自动管理事务生命周期。

### Story 6.3: 实现查询钩子系统（QueryHook 接口）

定义 `QueryHook` 接口，在查询执行前后调用钩子，提供示例钩子（LoggingHook、TimingHook）。

### Story 6.4: 实现统计信息收集与监控

扩展 `DBStats` 结构，使用原子操作收集查询计数、错误计数、平均耗时等指标。

---

## Epic 7: 高级查询特性（CTE、子查询、集合操作）

**Epic 目标**:
实现 CTE（Common Table Expressions）、子查询、UNION/INTERSECT/EXCEPT 等高级 SQL 特性，支持递归 CTE 和复杂的查询组合。提供类型安全的子查询构建 API，确保所有高级特性都能通过 comptime 优化。

### Story 7.1: 实现 CTE（WITH 子句）支持

在 SelectQuery 上添加 `with(name, subquery)` 方法，支持多个 CTE 定义和递归 CTE。

### Story 7.2: 实现子查询支持（WHERE、FROM、SELECT）

支持 WHERE 子查询、FROM 子查询、SELECT 子查询和 EXISTS 子查询。

### Story 7.3: 实现 UNION、INTERSECT、EXCEPT 集合操作

添加集合操作方法，验证两个查询的列类型兼容性，支持链式组合。

### Story 7.4: 实现窗口函数支持

添加 `window()` 方法，支持常见窗口函数（ROW_NUMBER, RANK, LAG, LEAD）。

---

## Epic 8: 关系映射与关联加载

**Epic 目标**:
实现模型之间的关系定义（Belongs-To、Has-One、Has-Many、Many-to-Many），提供 Eager Loading 和 Lazy Loading 支持。使用 comptime 反射自动推断关系类型和外键，简化关系定义。这是最复杂的 Epic，可能需要多次迭代。

### Story 8.1: 设计并实现关系定义系统

定义 `Relation` 接口，支持四种关系类型，使用 comptime 反射提取关系元数据。

### Story 8.2: 实现 Belongs-To 和 Has-One 关系加载

实现 `BelongsTo(T)` 和 `HasOne(T)` 泛型结构，提供 Lazy Loading 支持。

### Story 8.3: 实现 Has-Many 关系加载与 Eager Loading

实现 `HasMany(T)` 泛型结构，提供 Eager Loading 避免 N+1 问题，支持嵌套预加载。

### Story 8.4: 实现 Many-to-Many 关系（中间表支持）

实现 `ManyToMany(T)` 泛型结构，支持中间表操作（attach、detach、sync）。

---

## Checklist Results Report

**Report Generated**: 2025-01-16
**Validator**: PM Agent (Claude)
**Validation Method**: Comprehensive PM Checklist (9 Categories, 60+ Checkpoints)

---

### 执行概要 (Executive Summary)

- **整体完整度**: **78%** (良好)
- **MVP 范围适当性**: **恰到好处 (Just Right)** - 8 个 Epic 涵盖了完整 ORM 功能，从基础到高级特性有清晰的递进
- **架构阶段准备度**: **Nearly Ready** - PRD 质量高，但需要补充几个关键领域才能完全就绪
- **最关键的缺口**:
  1. 缺少明确的时间线和里程碑定义
  2. 未定义 MVP 验证计划和成功标准
  3. 缺少明确的"超出范围"部分
  4. 技术复杂度高风险区域未显式标记

---

### 分类分析表

| 类别 | 状态 | 完成度 | 关键问题 |
|-----|------|--------|----------|
| 1. Problem Definition & Context | PARTIAL | 70% | 缺少详细用户画像、具体成功指标时间线、直接用户研究证据 |
| 2. MVP Scope Definition | PARTIAL | 65% | 缺少明确的"超出范围"章节、未来增强路线图、MVP 验证计划 |
| 3. User Experience Requirements | PARTIAL | 50% | 开发者体验流程可以更详细，缺少用户反馈机制定义 |
| 4. Functional Requirements | **PASS** | **95%** | ✅ 优秀 - 20 个 FR 全面、清晰、可测试 |
| 5. Non-Functional Requirements | PARTIAL | 70% | 缺少详细的可扩展性、可用性和弹性需求 (部分合理超出库范围) |
| 6. Epic & Story Structure | **PASS** | **100%** | ✅ 卓越 - Epic 结构合理，Story 粒度恰当，Epic 1 涵盖所有基础设施 |
| 7. Technical Guidance | PARTIAL | 80% | 应显式标记高复杂度区域 (comptime 反射、关系映射)、技术债务策略 |
| 8. Cross-Functional Requirements | PARTIAL | 60% | 数据迁移策略需要更详细，运维监控需求不完整 (部分合理超出范围) |
| 9. Clarity & Communication | PARTIAL | 60% | 缺少架构图、利益相关者识别、沟通计划 |

---

### 优先级问题列表

#### 🔴 BLOCKERS (Must Fix Before Architect Proceeds)

**1. 缺少项目时间线** ⏰

- **问题**: PRD 中没有定义项目时间表、里程碑或交付预期
- **影响**: Architect 无法规划技术决策的优先级和阶段性交付
- **建议**: 添加 "Project Timeline" 章节，定义:
  - MVP 目标交付时间 (建议 3-6 个月)
  - Epic 1-3 的具体时间窗口 (关键路径)
  - Epic 4-8 的大致时间框架
  - 关键里程碑 (M1: 基础架构, M2: 查询构建器, M3: MVP)

**2. 未显式标记高复杂度/高风险技术领域** ⚠️

- **问题**: Architect 需要知道哪些领域需要深入技术调研和原型验证
- **影响**: 可能低估某些 Epic 的技术难度，导致架构设计不足
- **建议**: 在 Technical Guidance 中添加 "High Complexity Areas" 小节:
  - **comptime 类型反射系统** (Epic 2.8, 5.1): Zig 的 `@typeInfo` 和 `comptime` 边界，泛型约束
  - **关系映射系统** (Epic 8): N+1 问题避免，递归加载，类型安全的关系定义
  - **方言系统扩展性** (Epic 4): 确保第三方方言可插拔
  - **跨方言 SQL 生成一致性** (Epic 4.4): 语法差异的抽象层设计

#### 🟠 HIGH (Should Fix for Quality)

**3. 缺少明确的"超出范围"定义** 📋

- **问题**: 没有列出哪些功能不在 MVP 中，容易导致范围蔓延
- **建议**: 在 Epic List 后添加 "Out of Scope for MVP" 章节:
  - ❌ 高级连接池管理 (死连接检测、健康检查、动态扩缩容)
  - ❌ 查询缓存系统
  - ❌ 数据库读写分离支持
  - ❌ 分布式事务 (2PC/3PC)
  - ❌ ORM 插件系统
  - ❌ 可视化 Schema 迁移工具
  - ❌ 支持 NoSQL 数据库

**4. 缺少 MVP 验证计划** 🧪

- **问题**: 没有定义如何验证 MVP 是否成功，如何收集反馈
- **建议**: 添加 "MVP Validation Strategy" 章节:
  - **Alpha 测试** (Epic 1-3 完成后): 内部团队构建示例应用，验证基础功能
  - **Beta 测试** (Epic 4-6 完成后): 邀请 3-5 个 Zig 社区开发者试用，收集反馈
  - **成功标准**:
    - 能够构建完整的 CRUD 应用 (至少 3 个真实项目)
    - 性能基准测试达到 NFR5 目标 (<5% 开销)
    - 测试覆盖率达到 NFR6 目标 (80%)
    - 至少 5 个正面用户反馈
  - **反馈渠道**: GitHub Issues, Zig 社区论坛, Discord 频道

**5. 缺少详细的用户画像** 👤

- **问题**: "Zig 开发者"过于宽泛，不同技能水平和使用场景的需求不同
- **建议**: 在 Background Context 后添加 "User Personas":
  - **Persona 1: 系统程序员** (主要目标用户)
    - 构建高性能后端服务 (API 服务器、微服务)
    - 需求: 性能、内存控制、类型安全
    - 熟悉 SQL，希望保持对查询的完全控制
  - **Persona 2: 嵌入式开发者**
    - 使用 SQLite 构建嵌入式应用或命令行工具
    - 需求: 零依赖、跨平台、小体积
    - 可能不熟悉复杂 ORM，需要简单 API
  - **Persona 3: Web 后端开发者**
    - 从 Node.js/TypeScript (Bun ORM) 迁移到 Zig
    - 需求: 熟悉的 API 风格、快速上手
    - 期望类似 Bun ORM 的开发体验

#### 🟡 MEDIUM (Would Improve Clarity)

**6. 缺少架构图和可视化** 📊

- **建议**: 在 PRD 或未来的 architecture.md 中添加:
  - 模块依赖图 (core → query → dialect → schema)
  - 查询构建器工作流程图
  - 方言系统类图
  - 内存管理生命周期图

**7. 技术债务策略未定义** 🏗️

- **建议**: 在 Technical Guidance 中添加:
  - Epic 1-3 允许快速迭代，代码质量要求相对宽松
  - Epic 4+ 之前进行一次重构审查 (Refactoring Sprint)
  - 使用 TODO(DEBT) 注释标记技术债务
  - 每个 Epic 结束时预留 10% 时间偿还债务

**8. 数据迁移策略不够详细** 🗃️

- **建议**: 在 Epic 5 中细化迁移系统:
  - Story 5.4 应拆分为 3-4 个 Story
  - 定义迁移文件格式 (Zig 代码 vs SQL 文件)
  - 迁移版本管理策略 (数据库表 vs 文件系统)
  - 回滚机制 (down migrations)
  - 迁移依赖管理 (迁移之间的依赖关系)

#### 🟢 LOW (Nice to Have)

**9. 性能基准测试场景不够具体** 📈

- **建议**: 在 Technical Assumptions 中细化性能测试:
  - 具体场景: 10K 行批量插入、1K 行复杂 JOIN 查询、事务吞吐量
  - 对比基线: 手写 SQL、GORM (Go)、SQLx (Rust)
  - 测试环境: 硬件规格、数据库版本、数据集规模

**10. 文档策略可以更具体** 📖

- **建议**: 在 NFR7 中细化文档要求:
  - API 文档: 自动生成的 HTML (通过 `zig build docs`)
  - 使用指南: Markdown 教程 (Getting Started, Advanced Usage)
  - 最佳实践: 代码示例和反模式警告
  - 迁移指南: 从 Bun ORM 迁移到 zorm

---

### MVP 范围评估

**范围判断: 恰到好处 (Just Right)** ✅

**理由**:
- ✅ **核心功能完整**: Epic 1-3 提供完整的 CRUD 能力，足以构建真实应用
- ✅ **递进式复杂度**: Epic 4-6 添加生产必需特性 (多数据库、Schema、事务)
- ✅ **高级特性合理**: Epic 7-8 提供竞争力特性 (CTE、关系映射)，但可以后期交付
- ✅ **技术基础扎实**: Epic 1 的 8 个 Story 确保了坚实的基础架构

**可选的范围调整建议**:
- **如果时间紧张，可以推迟**:
  - Epic 7 (高级查询) - CTE 和窗口函数可以 v1.1 再做
  - Epic 8 (关系映射) - 复杂度高，可以先交付 Epic 1-6 作为 v1.0
- **不建议削减**:
  - Epic 1-3: 基础架构，不可妥协
  - Epic 4: 多数据库支持是核心卖点
  - Epic 5: Schema 管理是 ORM 的必备功能
  - Epic 6: 事务支持是生产环境必需

**复杂度关注**:
- ⚠️ Epic 2.8 (结果扫描) 和 Epic 8 (关系映射) 可能需要比预期更多时间
- ⚠️ Epic 4 (方言系统) 需要大量测试工作 (3 个数据库 × 所有功能)
- 建议在 Story 估算时对这些 Epic 增加 20-30% 的缓冲

---

### 技术就绪度评估

**编译时特性清晰度**: ✅ **优秀**
- comptime、Allocator、!T 错误处理等核心技术决策清晰明确
- NFR1-NFR4 提供了强有力的技术约束

**技术风险识别**: ⚠️ **需要改进**
- 应显式标记高风险领域:
  - `@typeInfo` 的限制和边界情况
  - 跨方言的 SQL 语法一致性
  - 关系映射的 N+1 问题避免策略
  - 性能目标 (<5% 开销) 的可行性验证

**架构调研需求**: ⚠️ **需要定义**
- 建议在架构阶段进行以下原型验证:
  1. **Prototype 1**: comptime 类型反射和 SQL 生成 (验证可行性)
  2. **Prototype 2**: 跨方言占位符转换 (验证性能开销)
  3. **Prototype 3**: 批量操作内存管理 (验证 Arena Allocator 效率)
  4. **Prototype 4**: 关系加载防 N+1 策略 (验证 Eager Loading 实现)

**性能假设验证**: ⚠️ **需要早期验证**
- NFR5 的 <5% 开销目标是核心卖点，但尚未验证
- 建议在 Epic 1 完成后立即进行性能基准测试:
  - 简单 SELECT 性能 (对比手写 SQL)
  - 参数绑定开销测量
  - Arena Allocator 开销测量
  - 如果超过 5%，需要调整策略或放宽目标

---

### 建议行动

#### 对于 Product Manager:

**1. 立即行动**:
- 添加 "Project Timeline" 章节 (预估 Epic 1-3: 2 个月, Epic 4-6: 2 个月, Epic 7-8: 2 个月)
- 添加 "Out of Scope for MVP" 章节
- 添加 "MVP Validation Strategy" 章节
- 在 Technical Guidance 中标记 "High Complexity Areas"

**2. 与 Architect 同步前**:
- 细化用户画像 (3 个典型 Persona)
- 定义明确的里程碑和成功标准
- 与 Zig 社区联系，寻找 Beta 测试候选人

#### 对于 Architect:

**1. 优先技术调研**:
- 创建 4 个原型验证关键技术假设 (comptime 反射、方言系统、内存管理、关系映射)
- 进行早期性能基准测试，验证 <5% 开销目标的可行性

**2. 架构文档重点**:
- 详细定义模块边界和接口 (特别是 core、query、dialect 之间)
- 设计可扩展的方言系统 (支持第三方方言)
- 定义清晰的错误传播和上下文附加机制
- 提供详细的内存管理模式和 Arena 使用指南

**3. 风险缓解策略**:
- 为 Epic 8 (关系映射) 准备降级方案 (如果时间不够，先交付基础关系加载)
- 为性能目标准备 Plan B (如果 <5% 无法达成，调整为 <10% 或提供性能调优指南)

---

### 最终决策

**✅ READY FOR ARCHITECT (With Conditions)**

PRD 质量高，功能定义清晰完整，Epic 结构合理。**在补充以下 4 个关键领域后，即可进入架构设计阶段**:

1. **Timeline & Milestones** (必须)
2. **Out of Scope Definition** (必须)
3. **MVP Validation Plan** (必须)
4. **High Complexity Areas Flagging** (必须)

**预计补充工作量**: 2-4 小时

**补充后的 PRD 质量预期**: 90%+，完全满足架构设计需求

---

## Next Steps

### UX Expert Prompt

*(Not applicable - zorm is a backend library without UI components)*

### Architect Prompt

请基于本 PRD 创建 zorm 的技术架构文档。重点关注：

1. **模块设计**: 详细定义 core、query、dialect、schema、transaction 等模块的职责和接口
2. **comptime 架构**: 阐述如何在编译时实现类型安全和代码生成，确保零运行时开销
3. **内存管理策略**: 定义 Allocator 使用模式、Arena 优化策略、资源清理规范
4. **错误处理流程**: 设计错误传播路径、错误上下文附加机制、用户错误处理指南
5. **方言系统设计**: 定义方言接口、特性检测机制、SQL 生成策略
6. **性能优化策略**: 识别热路径、定义内联策略、批量操作优化、连接池设计
7. **测试架构**: 单元测试框架、集成测试环境、性能基准测试、内存泄漏检测
8. **代码组织**: 目录结构、命名约定、文档标准、代码风格指南

请创建一份完整的 `docs/architecture.md` 文档，包含详细的技术决策、接口定义、UML 图、代码示例和最佳实践。

---

**文档结束**
