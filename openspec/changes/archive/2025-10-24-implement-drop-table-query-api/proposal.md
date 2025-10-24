# Proposal: Implement DROP TABLE Query Builder API

## Why

完成 PRD Epic 3 Story 3.3，为 ZORM 提供类型安全的 DROP TABLE 能力。当前 DROP TABLE 功能已在代码中实现，但缺少完整的规格文档和测试覆盖。本提案通过补充 OpenSpec 规格和测试用例，确保 DROP TABLE API 符合 PRD 要求并达到生产就绪状态。

## Overview

完成 PRD Epic 3 Story 3.3 中定义的 DROP TABLE Query Builder 功能验证和测试。该功能允许开发者通过简洁的 API 从 Zig 结构体自动生成 PostgreSQL DROP TABLE 语句，支持 IF EXISTS、CASCADE 和 RESTRICT 选项。

## Context

当前 ZORM 已实现完整的 Schema DDL Query Builder（CREATE TABLE、DROP TABLE、CREATE INDEX、DROP INDEX）。DROP TABLE Query Builder 的代码实现已存在于 `src/query/query.zig` 中，但缺少：

1. OpenSpec 规格文档
2. 完整的单元测试覆盖
3. 集成测试验证

### 现有实现

项目中已存在以下相关代码：

1. **src/query/query.zig**: 提供 `DropTableQuery` 类型，包含：
   - `init()`: 从结构体自动获取表名
   - `ifExists()`: 添加 IF EXISTS 子句
   - `cascade()`: 添加 CASCADE 选项
   - `restrict()`: 添加 RESTRICT 选项
   - `build()`: 生成 DROP TABLE SQL
   - `exec()`: 执行 DDL

2. **src/core/db.zig**: 提供 `DB.newDropTable(T)` 工厂方法

3. **src/schema/reflection.zig**: 提供 comptime 表名获取功能

### 差距分析

根据 PRD Story 3.3 的 7 个 Acceptance Criteria（AC3.3.1 ~ AC3.3.7）：

**已实现的功能**：
- ✅ AC3.3.1: 提供 `db.newDropTable(T)` API
- ✅ AC3.3.2: 自动从 Zig 结构体获取表名
- ✅ AC3.3.3: 提供 `.ifExists()` 方法
- ✅ AC3.3.4: 提供 `.cascade()` 方法
- ✅ AC3.3.5: 提供 `.restrict()` 方法
- ✅ AC3.3.6: 提供 `.exec()` 方法

**需要补充的工作**：
- ❌ 缺少 OpenSpec 规格文档
- ❌ 缺少完整的单元测试（验证 SQL 生成正确性）
- ❌ 缺少集成测试（验证实际数据库操作）
- ⚠️ AC3.3.7: 需验证使用示例可运行

## Goals

1. **创建 OpenSpec 规格文档**：定义 DROP TABLE API 的完整规格要求和场景
2. **补充测试覆盖**：为所有 AC 编写完整的单元测试和集成测试
3. **验证示例代码**：确保 PRD 中的示例代码可运行
4. **文档完善**：确保 API 文档清晰、代码注释完整

## Scope

### In Scope

- 创建 `drop-table-query-api` 规格文档
- 编写 `newDropTable()` 工厂方法的测试
- 编写 `ifExists()` 方法的测试
- 编写 `cascade()` 和 `restrict()` 方法的测试（包括互斥行为验证）
- 编写 `build()` 方法的 SQL 生成测试
- 编写 `exec()` 方法的集成测试
- 验证 PRD 示例代码可运行

### Out of Scope

- Story 3.2（Schema Field Customization）- 已在其他提案中实现
- Story 3.4/3.5（CREATE INDEX / DROP INDEX）- 已实现
- Story 3.6（PostgreSQL Specific Types）- 将在后续提案中实现
- 对现有 DROP TABLE 实现的重构（实现已符合要求，仅需测试和文档）

## Design Overview

### API 设计验证

根据 PRD AC3.3.1 ~ AC3.3.6，需验证以下 API：

```zig
// AC3.3.1: db.newDropTable(T) 工厂方法
var drop = try db.newDropTable(User);
defer drop.deinit();

// AC3.3.3: ifExists() 添加 IF EXISTS 子句
_ = drop.ifExists();

// AC3.3.4: cascade() 添加 CASCADE 选项
_ = drop.cascade();

// AC3.3.5: restrict() 添加 RESTRICT 选项
_ = drop.restrict();

// AC3.3.6: exec() 执行 DDL
try drop.exec();
```

### SQL 生成逻辑验证

需验证以下 SQL 生成场景：

1. 基本 DROP TABLE: `DROP TABLE users`
2. 带 IF EXISTS: `DROP TABLE IF EXISTS users`
3. 带 CASCADE: `DROP TABLE users CASCADE`
4. 带 RESTRICT: `DROP TABLE users RESTRICT`
5. 组合选项: `DROP TABLE IF EXISTS users CASCADE`

### CASCADE 和 RESTRICT 互斥行为验证

根据代码实现，`cascade()` 和 `restrict()` 是互斥的：
- 调用 `cascade()` 会自动清除 `restrict_flag`
- 调用 `restrict()` 会自动清除 `cascade_flag`

需要测试验证这一行为。

### 测试策略

1. **SQL 生成测试**：验证各种选项组合生成正确的 SQL
2. **工厂方法测试**：验证 `newDropTable()` 正确创建查询构建器
3. **表名提取测试**：验证从结构体自动获取表名
4. **互斥行为测试**：验证 CASCADE 和 RESTRICT 的互斥逻辑
5. **集成测试**：在真实数据库上执行 DROP TABLE 操作
6. **示例代码测试**：确保 PRD 中的示例可编译运行

## Capabilities

### drop-table-query-api

完整的 DROP TABLE Query Builder API 规格和测试，包括：
- 工厂方法创建
- 表名自动提取
- IF EXISTS 支持
- CASCADE 和 RESTRICT 选项
- SQL 生成和执行
- 完整测试覆盖

## Tasks

详见 `tasks.md`

## Dependencies

无外部依赖。本提案基于现有代码进行规格化和测试补充。

## Success Criteria

1. ✅ OpenSpec 规格文档创建完成
2. ✅ 所有 SQL 生成场景测试通过
3. ✅ CASCADE 和 RESTRICT 互斥行为测试通过
4. ✅ 集成测试验证数据库操作成功
5. ✅ PRD 中所有示例代码可编译运行
6. ✅ 单元测试覆盖率达到 80%+
7. ✅ `openspec validate --strict` 通过

## Timeline

预计 1 天完成：
- 上午: 创建规格文档、编写测试用例
- 下午: 运行测试、修复问题、通过验证

## Risks

1. **测试环境依赖**：集成测试需要真实 PostgreSQL 数据库
   - 缓解措施：确保测试环境配置正确，提供清晰的测试设置说明
2. **CASCADE 和 RESTRICT 行为理解**：需确保测试正确验证 PostgreSQL 的实际行为
   - 缓解措施：参考 PostgreSQL 官方文档，编写详细的测试场景

## References

- PRD: docs/prd.md - Epic 3, Story 3.3
- 现有实现: src/query/query.zig (`DropTableQuery`)
- DB 接口: src/core/db.zig (`DB.newDropTable`)
- 类型反射: src/schema/reflection.zig
- 参考规格: openspec/specs/update-query-api/spec.md
