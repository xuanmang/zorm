# ZORM 功能示例文档系统 - 产品需求文档

**版本**: v1.0
**日期**: 2025-10-17
**作者**: John (Product Manager)
**项目**: ZORM Examples Documentation System
**状态**: Ready for Development

---

## 变更日志

| 变更 | 日期 | 版本 | 描述 | 作者 |
|------|------|------|------|------|
| 初始创建 | 2025-10-17 | v1.0 | 创建 ZORM 示例文档系统 PRD | John |

---

## 1. 项目分析和上下文

### 1.1 现有项目概述

**分析来源**: IDE 环境分析，基于现有项目文档

**当前项目状态**:
- **项目**: ZORM - 受 Bun ORM 启发的 Zig 语言 SQL-first ORM 库
- **当前阶段**: Alpha 阶段，核心架构已完成
- **主要功能**:
  - 类型安全的查询构建器
  - 多数据库方言支持 (PostgreSQL, MySQL, SQLite)
  - 编译时优化 (comptime)
  - 显式内存管理
  - 强制错误处理

### 1.2 可用文档分析

**现有文档**:
- ✅ 技术栈文档 - Zig 0.15.2+, PostgreSQL/MySQL/SQLite
- ✅ 源码树/架构 - src/ 目录结构清晰
- ✅ 编码标准 - 遵循 Zig 惯例
- ✅ API 文档 - 详细的功能规格说明书 (2,335行)
- ✅ 技术债务文档 - README 标注了待实现功能

**缺少的文档**:
- ❌ 用户实践指南 - 如何使用 ZORM 的详细示例
- ❌ 最佳实践文档 - 性能优化、安全实践指南
- ❌ 常见问题解答 - 故障排查和问题解决

### 1.3 增强范围定义

**增强类型**:
- ✅ 新功能添加 - 添加完整的示例文档系统
- ✅ 中等影响 - 不改变现有代码，但显著提升用户体验

**增强描述**:
为 ZORM 项目的每个核心功能创建完整的、可运行的 PostgreSQL 代码示例，形成一个完整的用户实践指南。示例应涵盖从基础连接到高级特性（如事务、关系映射、迁移）的所有场景。

**影响评估**:
- ✅ 最小影响 (隔离添加) - 示例代码独立于核心库

### 1.4 目标和背景

**目标**:
- 为每个功能规格中定义的特性创建对应的代码示例
- 所有示例使用统一的 PostgreSQL 数据库环境
- 示例代码可直接运行和测试
- 覆盖率达到功能规格中 P0 和 P1 优先级特性的 100%
- 形成结构化的示例文档系统

**背景上下文**:

当前 ZORM 拥有完整的功能规格说明书 (2,335行)，详细定义了所有需要实现的功能。然而，**规格文档侧重于"应该做什么"，而缺少"如何使用"的实践指导**。

作为一个新的 Zig ORM 库，潜在用户需要:
1. 快速理解如何连接数据库
2. 学习如何构建常见查询
3. 掌握高级特性的使用方法
4. 获得最佳实践的参考

这个增强将弥合规格文档和用户实践之间的鸿沟，降低学习曲线，促进社区采用。

---

## 2. 需求

### 2.1 功能需求

**FR1: 基础连接示例**
提供数据库连接建立和配置的完整示例，包括错误处理和资源清理。

**FR2: CRUD 操作示例集**
为 SELECT/INSERT/UPDATE/DELETE 四大操作提供从简单到复杂的渐进式示例。

**FR3: 查询构建器示例**
展示链式 API 的使用，包括 WHERE、JOIN、ORDER BY、LIMIT 等子句的组合。

**FR4: 事务管理示例**
演示事务的开启、提交、回滚以及嵌套事务的处理。

**FR5: 关系映射示例**
提供 Belongs-To、Has-Many、Many-to-Many 三种关系的定义和查询示例。

**FR6: Schema 迁移示例**
展示表创建、修改、删除以及版本管理的完整流程。

**FR7: 批量操作示例**
演示批量插入、批量更新的性能优化实践。

**FR8: 高级查询示例**
包括子查询、CTE (WITH)、UNION、窗口函数等高级 SQL 特性。

**FR9: 类型映射示例**
展示 Zig 类型到 PostgreSQL 类型的双向转换。

**FR10: 错误处理示例**
演示各种数据库错误的捕获和处理方式。

**FR11: 钩子系统示例**
展示查询前后钩子的注册和使用（如日志记录、性能监控）。

**FR12: 连接池示例**
演示连接池的配置和管理。

**FR13: 原始 SQL 示例**
提供直接执行 SQL 的场景和最佳实践。

**FR14: 分页查询示例**
展示高效的分页查询实现。

**FR15: 聚合查询示例**
提供 COUNT、SUM、AVG、GROUP BY、HAVING 等聚合操作示例。

### 2.2 非功能需求

**NFR1: 代码可运行性**
所有示例代码必须能够在提供的 PostgreSQL 环境中直接运行，无需修改连接参数外的代码。

**NFR2: 代码风格一致性**
所有示例遵循项目既定的 Zig 编码规范，包括命名约定、错误处理模式、内存管理。

**NFR3: 渐进式学习曲线**
示例按照从简单到复杂的顺序组织，每个示例基于前面示例的知识。

**NFR4: 完整性**
每个示例必须包含完整的上下文（imports、结构体定义、main 函数），而非片段代码。

**NFR5: 文档化**
每个示例包含详细注释，解释关键概念和为什么这样实现（why, not what）。

**NFR6: 测试覆盖**
示例代码应包含基本的断言或验证逻辑，证明功能正常工作。

**NFR7: 性能考虑**
在适当的地方展示性能优化技巧（如批量操作、连接池使用）。

**NFR8: 安全实践**
示例必须展示安全的数据库操作（如参数化查询防止 SQL 注入）。

**NFR9: 资源管理**
严格遵循 Zig 的内存管理原则，所有示例正确使用 defer 和 errdefer。

**NFR10: 维护性**
示例代码结构清晰，易于后续维护和扩展。

### 2.3 兼容性需求

**CR1: Zig 版本兼容**
所有示例必须兼容 Zig 0.15.2+ 版本，使用该版本的标准库 API。

**CR2: PostgreSQL 版本兼容**
示例使用 PostgreSQL 12+ 的标准 SQL 语法，避免特定版本的专有特性。

**CR3: 现有 API 一致性**
示例代码使用的 API 必须与 `docs/functional_spec.md` 中定义的接口完全一致。

**CR4: 构建系统兼容**
示例应能通过项目的 `build.zig` 系统编译，无需额外配置。

---

## 3. 技术约束和集成要求

### 3.1 现有技术栈

**语言**: Zig 0.15.2+
**框架**: ZORM (自研 ORM)
**数据库**: PostgreSQL 12+ (开发环境: 127.0.0.1:5432)
**外部依赖**:

- github.com/karlseguin/pg.zig
- std.zig (Zig 标准库)

### 3.2 集成方法

**数据库集成策略**:

- 使用已提供的 PostgreSQL 实例 (host=127.0.0.1, port=5432, user=pguser, password=Pg#123!, dbname=postgres)
- 示例代码创建独立的 schema (`zorm_examples`) 以避免污染默认 public schema
- 每个示例负责创建和清理自己的测试数据

**API 集成策略**:

- 所有示例严格遵循 `docs/functional_spec.md` 中定义的 API 接口
- 使用功能规格中的 P0 (必需) 和 P1 (重要) 优先级特性
- 暂不使用 P2 (可选) 特性，除非对理解核心概念有帮助

**测试集成策略**:
- 示例代码通过 `zig build run-examples` 运行
- 每个示例包含基本的断言验证
- 使用 `std.testing` 框架进行单元测试

### 3.3 代码组织和标准

**文件结构方法**:
```
examples/
├── 00_setup_database.zig         # 数据库初始化脚本
├── 01_basic_connection.zig       # FR1: 基础连接
├── 02_simple_select.zig          # FR2: 简单查询
├── 03_insert_operations.zig      # FR2: 插入操作
├── 04_update_operations.zig      # FR2: 更新操作
├── 05_delete_operations.zig      # FR2: 删除操作
├── 06_query_builder.zig          # FR3: 查询构建器
├── 07_transactions.zig           # FR4: 事务管理
├── 08_relations_belongs_to.zig   # FR5: Belongs-To 关系
├── 09_relations_has_many.zig     # FR5: Has-Many 关系
├── 10_relations_many_to_many.zig # FR5: Many-to-Many 关系
├── 11_schema_migrations.zig      # FR6: Schema 迁移
├── 12_bulk_operations.zig        # FR7: 批量操作
├── 13_advanced_queries.zig       # FR8: 高级查询
├── 14_type_mapping.zig           # FR9: 类型映射
├── 15_error_handling.zig         # FR10: 错误处理
├── 16_hooks.zig                  # FR11: 钩子系统
├── 17_connection_pool.zig        # FR12: 连接池
├── 18_raw_sql.zig                # FR13: 原始 SQL
├── 19_pagination.zig             # FR14: 分页查询
├── 20_aggregation.zig            # FR15: 聚合查询
├── common/
│   ├── models.zig                # 共享的模型定义
│   └── db_config.zig             # 数据库配置
└── README.md                     # 示例索引和使用说明
```

**命名约定**:
- 文件名：小写 + 下划线分隔 (snake_case)
- 结构体：大驼峰 (PascalCase)
- 函数/变量：小驼峰 (camelCase)
- 常量：大写 + 下划线分隔 (SCREAMING_SNAKE_CASE)

**编码标准**:
- 严格遵循 Zig 0.15.2+ 语法
- 所有错误必须处理或传播 (!T 模式)
- 显式内存管理，正确使用 defer/errdefer
- 注释说明 "why" 而非 "what"
- 每个示例包含完整的 main 函数

**文档标准**:
- 每个示例文件顶部包含功能说明和学习目标
- 关键代码块包含详细注释
- examples/README.md 提供完整索引和学习路径

### 3.4 部署和运维

**构建过程集成**:
- 在 `build.zig` 中添加 `run-examples` 步骤
- 支持运行单个示例: `zig build run-example -Dexample=01_basic_connection`
- 支持运行所有示例: `zig build run-all-examples`

**配置管理**:
- 数据库连接信息在 `examples/common/db_config.zig` 中集中管理
- 支持通过环境变量覆盖默认配置

**监控和日志**:
- 示例使用 std.debug.print 输出执行过程
- 关键操作记录执行时间

### 3.5 风险评估和缓解

**技术风险**:
- **风险 1**: PostgreSQL 驱动尚未完全实现
  **缓解**: 优先实现示例所需的核心功能
- **风险 2**: 某些高级特性 (如 CTE) API 可能变化
  **缓解**: 使用功能规格中稳定的 API，标注实验性特性

**集成风险**:
- **风险 1**: 数据库连接失败
  **缓解**: 示例包含清晰的错误提示和故障排查指南
- **风险 2**: API 与功能规格不一致
  **缓解**: 与开发团队同步，确保 API 稳定后再创建示例

**部署风险**:
- **风险 1**: 用户环境没有 PostgreSQL
  **缓解**: 提供 Docker Compose 快速启动方案
- **风险 2**: libpq 库版本不兼容
  **缓解**: 文档说明支持的版本范围

**缓解策略**:
1. 每个示例独立可运行，降低依赖风险
2. 提供清晰的环境设置文档
3. 包含常见问题排查指南
4. 使用简单的博客 Schema，易于理解和调试

---

## 4. Epic 和 Story 结构

### 4.1 Epic 方法

**Epic 结构决定**: 单一 Epic

**理由**:
- 所有示例代码共享相同的目标：帮助用户学习 ZORM
- 共享相同的技术栈和数据库环境
- 示例之间有明确的递进关系（从基础到高级）
- 统一的代码组织和质量标准
- 便于统一管理和版本发布

---

## 5. Epic 1: ZORM 功能示例文档系统

**Epic 目标**: 创建完整的、可运行的 PostgreSQL 代码示例集，覆盖 ZORM 的所有核心功能，降低用户学习曲线，促进社区采用。

**集成要求**:
- 与现有 build.zig 构建系统集成
- 遵循功能规格说明书定义的 API
- 使用提供的 PostgreSQL 测试环境
- 保持与项目编码规范一致

---

### Story 023: 环境准备和共享基础设施

**作为** ZORM 用户，
**我想要** 快速设置示例运行环境和了解共享的模型定义，
**以便** 我可以专注于学习 ZORM 功能而不是环境配置。

#### 验收标准

1. ✅ 提供数据库初始化脚本 (`00_setup_database.zig`)，创建示例 schema 和表
2. ✅ 创建共享的博客系统模型定义 (User, Post, Comment, Tag)
3. ✅ 提供统一的数据库配置模块 (`common/db_config.zig`)
4. ✅ 创建 examples/README.md，包含环境设置说明和示例索引
5. ✅ 在 build.zig 中添加 `run-examples` 构建步骤

#### 集成验证

- **IV1**: 验证数据库初始化脚本能成功连接并创建 schema
- **IV2**: 验证共享配置模块可被所有示例引用
- **IV3**: 验证构建系统能正确编译和运行示例

---

### Story 024: 基础连接和 CRUD 操作示例 (FR1, FR2)

**作为** ZORM 初学者，
**我想要** 学习如何建立数据库连接和执行基本的 CRUD 操作，
**以便** 我可以开始使用 ZORM 进行数据库操作。

#### 验收标准

1. ✅ 创建基础连接示例 (`01_basic_connection.zig`)，展示连接建立、配置和错误处理
2. ✅ 创建简单 SELECT 示例 (`02_simple_select.zig`)，展示基本查询和结果扫描
3. ✅ 创建 INSERT 操作示例 (`03_insert_operations.zig`)，包括单条和批量插入
4. ✅ 创建 UPDATE 操作示例 (`04_update_operations.zig`)，包括条件更新
5. ✅ 创建 DELETE 操作示例 (`05_delete_operations.zig`)，包括软删除和硬删除
6. ✅ 每个示例包含完整的错误处理和资源清理

#### 集成验证

- **IV1**: 验证所有示例能成功连接到提供的 PostgreSQL 数据库
- **IV2**: 验证 CRUD 操作正确修改数据库状态
- **IV3**: 验证错误情况下资源正确释放（无内存泄漏）

---

### Story 025: 查询构建器和事务管理示例 (FR3, FR4)

**作为** ZORM 中级用户，
**我想要** 学习如何使用链式 API 构建复杂查询和管理事务，
**以便** 我可以编写更高效和安全的数据库操作代码。

#### 验收标准

1. ✅ 创建查询构建器示例 (`06_query_builder.zig`)，展示 WHERE、JOIN、ORDER BY、LIMIT、OFFSET 的组合使用
2. ✅ 展示查询构建器的类型安全特性和编译时检查
3. ✅ 创建事务管理示例 (`07_transactions.zig`)，展示事务开启、提交、回滚
4. ✅ 展示事务中的错误处理和自动回滚机制
5. ✅ 包含嵌套事务（Savepoint）的示例

#### 集成验证

- **IV1**: 验证查询构建器生成正确的 SQL 语句
- **IV2**: 验证事务提交后数据持久化
- **IV3**: 验证事务回滚后数据恢复原状
- **IV4**: 验证错误情况下事务自动回滚

---

### Story 026: 关系映射示例 (FR5)

**作为** ZORM 用户，
**我想要** 学习如何定义和查询表之间的关系，
**以便** 我可以建模复杂的业务领域。

#### 验收标准

1. ✅ 创建 Belongs-To 关系示例 (`08_relations_belongs_to.zig`)，展示 Post -> User 的多对一关系
2. ✅ 创建 Has-Many 关系示例 (`09_relations_has_many.zig`)，展示 User -> Posts 的一对多关系
3. ✅ 创建 Many-to-Many 关系示例 (`10_relations_many_to_many.zig`)，展示 Post <-> Tags 的多对多关系
4. ✅ 展示关系的预加载（Eager Loading）和延迟加载（Lazy Loading）
5. ✅ 包含避免 N+1 查询问题的最佳实践

#### 集成验证

- **IV1**: 验证关系查询返回正确的关联数据
- **IV2**: 验证预加载减少了查询次数
- **IV3**: 验证多对多关系的中间表正确创建和使用

---

### Story 027: Schema 管理和迁移示例 (FR6)

**作为** ZORM 用户，
**我想要** 学习如何使用代码管理数据库 schema 的演进，
**以便** 我可以安全地进行数据库结构变更。

#### 验收标准

1. ✅ 创建 Schema 迁移示例 (`11_schema_migrations.zig`)，展示表的创建、修改、删除
2. ✅ 展示列的添加、修改类型、重命名、删除
3. ✅ 展示索引和约束的管理
4. ✅ 展示迁移版本管理和回滚机制
5. ✅ 包含数据迁移（Data Migration）的示例

#### 集成验证

- **IV1**: 验证迁移正确修改数据库 schema
- **IV2**: 验证迁移版本正确记录
- **IV3**: 验证回滚操作正确恢复 schema
- **IV4**: 验证数据迁移不丢失现有数据

---

### Story 028: 批量操作和高级查询示例 (FR7, FR8)

**作为** ZORM 高级用户，
**我想要** 学习如何进行高性能的批量操作和使用高级 SQL 特性，
**以便** 我可以优化应用的数据库性能。

#### 验收标准

1. ✅ 创建批量操作示例 (`12_bulk_operations.zig`)，展示批量插入和批量更新的优化技巧
2. ✅ 展示使用 PostgreSQL COPY 协议的高性能批量导入
3. ✅ 创建高级查询示例 (`13_advanced_queries.zig`)，包括子查询、CTE (WITH)、UNION、窗口函数
4. ✅ 展示递归 CTE 的使用场景（如树形结构查询）
5. ✅ 包含性能对比和最佳实践说明

#### 集成验证

- **IV1**: 验证批量操作的性能优于逐条操作
- **IV2**: 验证高级查询返回正确结果
- **IV3**: 验证 CTE 和子查询的性能特征

---

### Story 029: 类型映射和错误处理示例 (FR9, FR10)

**作为** ZORM 用户，
**我想要** 理解 Zig 类型和 SQL 类型之间的映射以及如何处理各种数据库错误，
**以便** 我可以编写健壮的应用程序。

#### 验收标准

1. ✅ 创建类型映射示例 (`14_type_mapping.zig`)，展示所有基础类型的双向转换
2. ✅ 展示复杂类型的处理（JSON、数组、自定义类型）
3. ✅ 展示 NULL 值的处理（使用 Zig 的 optional 类型）
4. ✅ 创建错误处理示例 (`15_error_handling.zig`)，展示常见数据库错误的捕获和处理
5. ✅ 展示自定义错误类型和错误恢复策略

#### 集成验证

- **IV1**: 验证类型转换的正确性和边界情况处理
- **IV2**: 验证 NULL 值正确映射到 optional 类型
- **IV3**: 验证错误处理不会导致资源泄漏

---

### Story 030: 钩子系统和连接池示例 (FR11, FR12)

**作为** ZORM 用户，
**我想要** 学习如何使用钩子系统实现横切关注点和配置连接池，
**以便** 我可以实现日志记录、性能监控和资源优化。

#### 验收标准

1. ✅ 创建钩子系统示例 (`16_hooks.zig`)，展示查询前后钩子的注册和使用
2. ✅ 实现日志记录钩子、性能监控钩子、查询审计钩子
3. ✅ 展示钩子的组合和链式调用
4. ✅ 创建连接池示例 (`17_connection_pool.zig`)，展示连接池的配置和管理
5. ✅ 展示连接池的性能优势和最佳实践配置

#### 集成验证

- **IV1**: 验证钩子在正确的时机被触发
- **IV2**: 验证钩子可以修改查询或取消执行
- **IV3**: 验证连接池正确复用连接
- **IV4**: 验证连接池在高并发下的稳定性

---

### Story 031: 原始 SQL 和分页查询示例 (FR13, FR14)

**作为** ZORM 用户，
**我想要** 学习何时以及如何使用原始 SQL 和实现高效的分页，
**以便** 我可以处理查询构建器无法覆盖的场景。

#### 验收标准

1. ✅ 创建原始 SQL 示例 (`18_raw_sql.zig`)，展示直接执行 SQL 的场景
2. ✅ 展示参数化查询防止 SQL 注入
3. ✅ 展示原始 SQL 与查询构建器的混合使用
4. ✅ 创建分页查询示例 (`19_pagination.zig`)，展示 OFFSET/LIMIT 分页
5. ✅ 展示 Cursor-based 分页的实现和性能优势
6. ✅ 包含大数据量下的分页性能优化技巧

#### 集成验证

- **IV1**: 验证原始 SQL 正确执行并返回结果
- **IV2**: 验证参数化查询阻止 SQL 注入
- **IV3**: 验证分页返回正确的数据子集
- **IV4**: 验证 Cursor-based 分页的性能优于 OFFSET

---

### Story 032: 聚合查询和文档完善 (FR15)

**作为** ZORM 用户，
**我想要** 学习如何执行聚合查询和拥有完整的示例索引文档，
**以便** 我可以进行数据分析和快速找到需要的示例。

#### 验收标准

1. ✅ 创建聚合查询示例 (`20_aggregation.zig`)，展示 COUNT、SUM、AVG、MIN、MAX
2. ✅ 展示 GROUP BY 和 HAVING 子句的使用
3. ✅ 展示多维度聚合和 ROLLUP/CUBE 操作
4. ✅ 完善 examples/README.md，包含：
   - 完整的示例索引表（编号、标题、功能需求、难度）
   - 推荐的学习路径（初级 -> 中级 -> 高级）
   - 环境设置详细步骤
   - 常见问题排查指南
5. ✅ 在主项目 README.md 中添加示例文档入口链接

#### 集成验证

- **IV1**: 验证聚合查询返回正确的统计结果
- **IV2**: 验证 GROUP BY 正确分组数据
- **IV3**: 验证文档链接正确且可访问
- **IV4**: 验证所有示例在索引中有对应条目

---

## 6. 附录

### 6.1 数据库环境配置

**PostgreSQL 连接信息**:
```
Host: 127.0.0.1
Port: 5432
User: pguser
Password: Pg#123!
Database: postgres
```

**示例 Schema 设计** (博客系统):

```sql
-- users 表
CREATE TABLE zorm_examples.users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- posts 表
CREATE TABLE zorm_examples.posts (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES zorm_examples.users(id),
    title VARCHAR(255) NOT NULL,
    content TEXT,
    status VARCHAR(20) DEFAULT 'draft',
    published_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- comments 表
CREATE TABLE zorm_examples.comments (
    id BIGSERIAL PRIMARY KEY,
    post_id BIGINT NOT NULL REFERENCES zorm_examples.posts(id),
    user_id BIGINT NOT NULL REFERENCES zorm_examples.users(id),
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- tags 表
CREATE TABLE zorm_examples.tags (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL
);

-- post_tags 表 (多对多关系)
CREATE TABLE zorm_examples.post_tags (
    post_id BIGINT NOT NULL REFERENCES zorm_examples.posts(id),
    tag_id BIGINT NOT NULL REFERENCES zorm_examples.tags(id),
    PRIMARY KEY (post_id, tag_id)
);
```

### 6.2 示例索引表 (预览)

| 编号 | 文件名 | 标题 | 功能需求 | 难度 | 学习路径 |
|------|--------|------|----------|------|----------|
| 00 | 00_setup_database.zig | 数据库初始化 | - | 基础 | 预备 |
| 01 | 01_basic_connection.zig | 基础连接 | FR1 | 基础 | 第1天 |
| 02 | 02_simple_select.zig | 简单查询 | FR2 | 基础 | 第1天 |
| 03 | 03_insert_operations.zig | 插入操作 | FR2 | 基础 | 第1天 |
| 04 | 04_update_operations.zig | 更新操作 | FR2 | 基础 | 第1天 |
| 05 | 05_delete_operations.zig | 删除操作 | FR2 | 基础 | 第1天 |
| 06 | 06_query_builder.zig | 查询构建器 | FR3 | 中级 | 第2天 |
| 07 | 07_transactions.zig | 事务管理 | FR4 | 中级 | 第2天 |
| 08 | 08_relations_belongs_to.zig | Belongs-To 关系 | FR5 | 中级 | 第3天 |
| 09 | 09_relations_has_many.zig | Has-Many 关系 | FR5 | 中级 | 第3天 |
| 10 | 10_relations_many_to_many.zig | Many-to-Many 关系 | FR5 | 高级 | 第3天 |
| 11 | 11_schema_migrations.zig | Schema 迁移 | FR6 | 高级 | 第4天 |
| 12 | 12_bulk_operations.zig | 批量操作 | FR7 | 中级 | 第4天 |
| 13 | 13_advanced_queries.zig | 高级查询 | FR8 | 高级 | 第5天 |
| 14 | 14_type_mapping.zig | 类型映射 | FR9 | 中级 | 第5天 |
| 15 | 15_error_handling.zig | 错误处理 | FR10 | 基础 | 第2天 |
| 16 | 16_hooks.zig | 钩子系统 | FR11 | 高级 | 第6天 |
| 17 | 17_connection_pool.zig | 连接池 | FR12 | 中级 | 第6天 |
| 18 | 18_raw_sql.zig | 原始 SQL | FR13 | 基础 | 第2天 |
| 19 | 19_pagination.zig | 分页查询 | FR14 | 中级 | 第4天 |
| 20 | 20_aggregation.zig | 聚合查询 | FR15 | 中级 | 第5天 |

### 6.3 术语表

| 术语 | 定义 |
|------|------|
| ZORM | Zig ORM - 本项目的名称 |
| comptime | Zig 的编译时计算特性 |
| Allocator | Zig 的内存分配器接口 |
| Error Union | Zig 的错误处理类型 (!T) |
| Dialect | 数据库方言，不同数据库的 SQL 语法差异 |
| ORM | Object-Relational Mapping，对象关系映射 |
| CRUD | Create, Read, Update, Delete 基本操作 |
| CTE | Common Table Expression，公用表表达式 |
| N+1 查询 | 一种性能反模式，循环中执行查询导致大量数据库访问 |

---

**文档结束**

Authored-By: mobus <mobussun@gmail.com>
