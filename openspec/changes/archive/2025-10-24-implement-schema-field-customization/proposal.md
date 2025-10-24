# Proposal: Implement Schema Field Customization with Struct Tags

## Why

完成 PRD Epic 3 Story 3.2，为 ZORM 提供灵活的 Schema 字段定制能力。当前用户只能依赖 Zig 结构体字段的自动映射，无法精确控制生成的 SQL Schema（如自定义列名、显式指定 SQL 类型、添加约束等），限制了 Schema 管理的灵活性。本提案通过 comptime struct tags 机制实现零运行时开销的字段定制，显著提升 Schema 管理的表达能力。

## Overview

完成 PRD Epic 3 Story 3.2 中定义的 Schema Field Customization 功能。该功能允许开发者通过 `pub const schema` 配置块自定义表字段的各种属性（列名、SQL 类型、约束、默认值等），无需受限于 Zig 结构体字段的命名和类型。

## Context

当前 ZORM 已实现 CREATE TABLE Query Builder 基础功能（Story 3.1），支持从 Zig 结构体自动生成表定义。但自动映射缺乏灵活性，无法满足以下场景：

1. **列名映射**：数据库列名与 Zig 字段名不一致（如 `user_name` → `username`）
2. **类型覆盖**：需要特定的 SQL 类型（如 `VARCHAR(50)` 而非默认的 `TEXT`）
3. **约束添加**：需要 UNIQUE、CHECK、DEFAULT 等约束
4. **主键配置**：复合主键或非 `id` 字段作为主键

### 现有实现

项目中已存在以下相关代码：

1. **src/schema/schema.zig**: 已实现 `FieldSchema` 结构和 `getFieldSchema()` 函数
   - 支持读取 `pub const schema` 配置
   - 已定义所有需要的字段属性（column_name, sql_type, primary_key, auto_increment, unique, default, check, not_null）
   - 提供 `generateColumnDefinition()` 函数生成单列定义

2. **src/schema/reflection.zig**: `generateColumns()` 函数已使用 schema 配置
   - 读取 primary_key、auto_increment、unique、default、check 等属性
   - 但 column_name 和 sql_type 尚未完全集成

3. **src/schema/table.zig**: `Column` 结构支持所有约束
   - 支持 unique, default_value, check_expr 等字段
   - `toSQL()` 方法已能生成包含所有约束的 DDL

### 差距分析

根据 PRD Story 3.2 的 8 个 Acceptance Criteria（AC3.2.1 ~ AC3.2.8）：

**已实现的功能**：
- ✅ AC3.2.1: 支持通过 comptime 元数据定义列属性（`FieldSchema` 结构）
- ✅ AC3.2.4: 支持 UNIQUE 约束标记（已集成到 reflection.zig）
- ✅ AC3.2.5: 支持 DEFAULT 值设置（已集成到 reflection.zig）
- ✅ AC3.2.6: 支持 CHECK 约束（已集成到 reflection.zig）
- ✅ AC3.2.7: 使用 Zig comptime 结构定义 Schema 配置

**需要补充/验证的功能**：
- ⚠️ AC3.2.2: 自定义列名支持（FieldSchema 有定义，但未集成到 CREATE TABLE 生成）
- ⚠️ AC3.2.3: 显式指定 SQL 类型（FieldSchema 有定义，但未集成到 CREATE TABLE 生成）
- ❌ AC3.2.8: 缺少完整的测试覆盖和文档示例

## Goals

1. **集成自定义列名**：在 CREATE TABLE 生成中使用 `column_name` 配置
2. **集成 SQL 类型覆盖**：在 CREATE TABLE 生成中使用 `sql_type` 配置
3. **补充测试覆盖**：为所有 AC 编写完整的单元测试和集成测试
4. **文档完善**：确保 API 文档清晰、示例代码可运行
5. **示例程序更新**：在 `examples/schema.zig` 中添加字段定制示例

## Scope

### In Scope

- 集成 `column_name` 配置到 `generateColumns()` 和 CREATE TABLE SQL 生成
- 集成 `sql_type` 配置到 `generateColumns()` 和 CREATE TABLE SQL 生成
- 编写覆盖所有 AC 的单元测试
- 编写集成测试验证完整的字段定制工作流
- 完善 API 文档和代码注释
- 更新 `examples/schema.zig` 添加字段定制示例

### Out of Scope

- 自定义列名在 INSERT/SELECT/UPDATE/DELETE 查询中的使用（将在后续提案中实现）
- SQL 类型字符串的 comptime 验证（接受任意字符串）
- Story 3.3~3.6（其他 Schema 管理功能）

## Design Overview

### 自定义列名集成

在 `src/schema/reflection.zig` 的 `generateColumns()` 中：

```zig
// 使用 column_name 配置（如果有），否则使用字段名
const col_name = if (schema_cfg.column_name) |custom_name|
    custom_name
else
    field.name;

columns[i] = .{
    .name = col_name,  // 使用自定义列名
    // ... 其他字段
};
```

### SQL 类型覆盖集成

在 `src/schema/reflection.zig` 的 `generateColumns()` 中：

```zig
// 使用 sql_type 配置（如果有），否则自动推断
var sql_type: types.SQLType = undefined;
if (schema_cfg.sql_type) |custom_type| {
    // 自定义类型需要存储为字符串，不能直接用 SQLType enum
    // 需要修改 Column 结构支持自定义类型字符串
} else if (is_auto_increment) {
    // ... 自增逻辑
} else {
    sql_type = types.zigToSQLType(field.type);
}
```

**注意**：当前 `Column.column_type` 使用 `ColumnType` enum，无法存储任意 SQL 类型字符串。需要两种方案之一：

1. **方案 A**：修改 `Column` 结构，添加 `custom_sql_type: ?[]const u8` 字段
2. **方案 B**：在 `ColumnType` enum 中添加 `custom` 变体，携带字符串

本提案选择**方案 A**，因为更简单且向后兼容。

### 测试策略

1. **自定义列名测试**：验证 `column_name` 配置正确映射到生成的 SQL
2. **SQL 类型覆盖测试**：验证 `sql_type` 配置覆盖自动推断的类型
3. **组合约束测试**：测试 UNIQUE + DEFAULT + CHECK 等多约束组合
4. **完整示例测试**：测试 PRD AC3.2.8 中的示例代码

## Capabilities

### schema-field-customization

完整实现 Schema Field Customization，包括：
- 自定义列名（column_name）
- 显式 SQL 类型（sql_type）
- UNIQUE、DEFAULT、CHECK 约束（已有，需验证）
- 主键和自增配置（已有，需验证）
- 完整测试覆盖

## Tasks

详见 `tasks.md`

## Dependencies

- 依赖 Story 3.1（CREATE TABLE Query Builder）已完成
- 需要修改 `src/schema/table.zig` 的 `Column` 结构（添加 `custom_sql_type` 字段）

## Success Criteria

1. ✅ 自定义列名测试通过（column_name 配置生效）
2. ✅ SQL 类型覆盖测试通过（sql_type 配置生效）
3. ✅ 所有约束组合测试通过（UNIQUE, DEFAULT, CHECK, PRIMARY KEY, AUTO_INCREMENT）
4. ✅ PRD AC3.2.8 示例代码可编译并通过测试
5. ✅ `examples/schema.zig` 示例程序包含字段定制示例
6. ✅ 单元测试覆盖率达到 80%+
7. ✅ `openspec validate --strict` 通过

## Timeline

预计 1-2 天完成：
- Day 1: 修改 Column 结构、集成 column_name 和 sql_type、编写测试
- Day 2: 完善文档、更新示例、修复问题、通过验证

## Risks

1. **Column 结构修改影响现有代码**：添加 `custom_sql_type` 字段可能影响现有 Table 相关代码
   - 缓解措施：使用可选字段（`?[]const u8`），确保向后兼容；充分测试
2. **SQL 类型字符串无验证**：用户可能输入无效的 SQL 类型导致运行时错误
   - 缓解措施：文档中明确说明用户责任；提供常见类型示例；运行时错误由数据库返回

## References

- PRD: docs/prd.md - Epic 3, Story 3.2
- 现有实现:
  - src/schema/schema.zig (`FieldSchema`, `getFieldSchema`)
  - src/schema/reflection.zig (`generateColumns`)
  - src/schema/table.zig (`Column`, `Table`)
