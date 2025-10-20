# Proposal: enhance-postgresql-dialect

## Summary
完善 ZORM PostgreSQL 方言系统的 comptime 实现，确保与功能规格说明书 2.1.4 对齐，强化编译时特性检测、SQL 生成和零运行时开销保证。

## Motivation

### 当前状态
ZORM 现有方言系统（`src/dialect/dialect.zig`）已实现基础的 PostgreSQL 专用功能：
- ✅ Comptime 占位符生成 (`$1`, `$2`, ...)
- ✅ Comptime 标识符引用 (`"identifier"`)
- ✅ Comptime 特性检测 (`supports()`)
- ✅ 基础 SQL 工具函数（转义、占位符生成）

### 问题与差距
1. **特性覆盖不完整**：功能规格列举的特性（如 `output_clause`, `merge`, `full_text_search`）未完全定义
2. **运行时分派缺失**：虽有 `placeholderAlloc()`，但缺乏统一的运行时方言分派机制
3. **文档与示例不足**：缺少编译时方言分派 (`dialectDispatch()`) 的完整示例
4. **类型安全性**：需明确 comptime 求值的边界和类型约束
5. **测试覆盖**：现有测试未覆盖所有 comptime 特性组合

### 目标
按照功能规格说明书 2.1.4 的要求，完善 PostgreSQL 方言系统的 comptime 实现：
- 🎯 **完整的特性枚举**：覆盖 PostgreSQL 支持的所有现代 SQL 特性
- 🎯 **编译时方言分派**：实现 `dialectDispatch()` 和 comptime 错误检测
- 🎯 **零运行时开销保证**：所有方言决策在编译时完成
- 🎯 **完善文档和示例**：提供清晰的使用模式和测试

## Scope

### 包含（In Scope）
- ✅ 完善 `Feature` 枚举，添加 PostgreSQL 特有特性
- ✅ 实现编译时方言分派函数 `dialectDispatch()`
- ✅ 增强 comptime SQL 生成工具（LIMIT/OFFSET, UPSERT, 时间戳等）
- ✅ 添加完整的编译时测试覆盖
- ✅ 更新文档和代码注释，明确 comptime 语义
- ✅ 提供功能规格中的示例代码

### 不包含（Out of Scope）
- ❌ 多数据库方言支持（MySQL, SQLite, MSSQL, Oracle）
- ❌ 运行时方言切换机制
- ❌ 方言自动检测或连接字符串解析
- ❌ 驱动层的方言适配（仅限编译时抽象）

### 影响范围
- **文件变更**：`src/dialect/dialect.zig`, `src/dialect/sql.zig`
- **新增测试**：完整的 comptime 特性组合测试
- **文档更新**：代码注释和使用示例

## Design Considerations

### 原则
1. **PostgreSQL 专用，不妥协**：所有设计决策针对 PostgreSQL 优化
2. **Comptime 优先**：最大化编译时求值，确保零运行时开销
3. **类型安全**：利用 Zig 的 comptime 类型系统防止运行时错误
4. **向后兼容**：保持现有 API 不变，仅扩展功能

### 技术选择
- **特性检测**：使用 comptime switch 表达式，编译时已知
- **方言分派**：利用 `@compileError` 在不支持的特性上编译失败
- **SQL 生成**：使用 `std.fmt.comptimePrint` 实现零分配

### 权衡
- **灵活性 vs 性能**：选择性能（comptime），不支持运行时方言切换
- **完整性 vs 简洁性**：选择完整性，明确列举所有特性标志
- **通用性 vs 专用性**：选择专用性，针对 PostgreSQL 深度优化

## Dependencies
- 无外部依赖变更
- 依赖 Zig 0.15.2+ 的 comptime 特性
- 依赖现有 `std.fmt.comptimePrint` 和类型系统

## Testing Strategy
- ✅ Comptime 特性检测测试（所有 Feature 枚举值）
- ✅ Comptime SQL 生成测试（占位符、引用、LIMIT/OFFSET）
- ✅ DialectDispatch 编译时错误测试（不支持的特性触发 @compileError）
- ✅ 类型安全测试（comptime 类型推导和边界检查）
- ✅ 零运行时开销验证（通过编译器输出确认）

## Rollout Plan
1. **Phase 1**: 扩展 Feature 枚举和 supports() 实现
2. **Phase 2**: 实现 dialectDispatch() 和相关工具函数
3. **Phase 3**: 添加完整的 comptime 测试覆盖
4. **Phase 4**: 更新文档和示例代码
5. **Phase 5**: 集成到现有查询构建器和 Schema 系统

## Alternatives Considered

### 替代方案 1：多方言支持
**描述**：实现功能规格完整要求的 MySQL, SQLite, MSSQL, Oracle 支持

**优点**：
- 符合功能规格说明书原文
- 提供更广泛的数据库兼容性

**缺点**：
- 违背项目当前的 PostgreSQL 专用定位
- 增加代码复杂度和维护成本
- 缺乏其他数据库的实际驱动实现

**决策**：❌ **不采纳**，维持 PostgreSQL 专用战略

### 替代方案 2：运行时方言切换
**描述**：支持在运行时选择数据库方言

**优点**：
- 更灵活的部署模式

**缺点**：
- 引入运行时开销
- 违背 Zig 零成本抽象原则
- 与 comptime 设计理念冲突

**决策**：❌ **不采纳**，坚持 comptime 优先

### 替代方案 3：最小化实现
**描述**：仅保留当前已有功能，不扩展

**优点**：
- 代码变更最小

**缺点**：
- 与功能规格不一致
- 缺少关键的 dialectDispatch() 机制
- 测试覆盖不足

**决策**：❌ **不采纳**，需要适度完善

## Open Questions
- Q1: 是否需要为 PostgreSQL 扩展（如 PostGIS, TimescaleDB）添加特性标志？
  - **暂定**：暂不包含，等待实际需求

- Q2: 是否需要 comptime 的版本检测（如 PostgreSQL 15+ 的新特性）？
  - **暂定**：暂不包含，假设使用现代 PostgreSQL 版本

- Q3: 如何处理方言与驱动层的耦合？
  - **暂定**：方言层保持纯编译时抽象，驱动层负责运行时执行

## Success Metrics
- ✅ 所有 Feature 枚举值有对应的 supports() 测试
- ✅ dialectDispatch() 函数实现并通过测试
- ✅ 零新增运行时分支（通过编译器输出验证）
- ✅ 代码覆盖率 > 95%（方言相关代码）
- ✅ 文档示例可编译且通过测试
