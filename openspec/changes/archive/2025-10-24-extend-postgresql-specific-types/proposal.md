# Proposal: Extend PostgreSQL Specific Types

## Change ID
`extend-postgresql-specific-types`

## Status
Draft

## Overview
扩展 ZORM 的类型系统,完整支持 PostgreSQL 特有数据类型,包括数组类型、JSONB、UUID 和时间戳类型的精确映射,并提供完整的序列化/反序列化支持。

## Motivation
当前 ZORM 的类型系统已经定义了 JSONB、UUID、TIMESTAMPTZ 等 PostgreSQL 特有类型的枚举值,但缺乏完整的端到端支持:

1. **数组类型缺失**: 无法将 Zig 的 slice 类型(如 `[]i64`)自动映射到 PostgreSQL 数组类型(如 `BIGINT[]`)
2. **序列化不完整**: 虽然有 `serializeArray` 和 `deserializeArray` 函数,但未集成到 Query Builder 中
3. **JSONB 支持不完善**: 只有类型定义,缺少 JSON 序列化/反序列化逻辑
4. **UUID 转换缺失**: 无法在 Zig 的 `[16]u8` 和 PostgreSQL UUID 字符串之间转换

这导致开发者无法充分利用 PostgreSQL 的强大功能,特别是在需要存储复杂数据结构时(如标签数组、JSON 元数据、UUID 主键等)。

## Goals
1. 支持 PostgreSQL 数组类型的自动映射和序列化/反序列化
2. 完善 JSONB 类型的 JSON 序列化/反序列化支持
3. 实现 UUID 类型的字符串转换支持
4. 确保 CREATE TABLE、INSERT、SELECT 等操作中这些类型能正常工作
5. 提供清晰的错误处理和类型安全保证

## Non-Goals
- 不支持 PostgreSQL 复合类型 (composite types)
- 不支持自定义枚举类型 (enum types)
- 不支持范围类型 (range types)
- 不支持多维数组 (只支持一维数组)

## Target PRD Story
- **Epic 3**: Schema Management & Type System
- **Story 3.6**: Complete Type Mapping System with PostgreSQL Specific Types
  - AC3.6.1: 支持 JSONB 类型映射
  - AC3.6.2: 支持数组类型
  - AC3.6.3: 支持 UUID 类型
  - AC3.6.4: 支持 TIMESTAMP WITH/WITHOUT TIME ZONE
  - AC3.6.5: 提供显式类型覆盖机制
  - AC3.6.6: CREATE TABLE 中正确生成特有类型
  - AC3.6.7: INSERT/SELECT 中正确处理序列化
  - AC3.6.8: PRD 示例验证

## Success Metrics
- [ ] 所有 AC3.6.x 验收标准通过
- [ ] PRD AC3.6.8 示例代码可编译并通过测试
- [ ] 数组序列化/反序列化测试覆盖率 100%
- [ ] JSONB 序列化/反序列化测试覆盖率 100%
- [ ] UUID 转换测试覆盖率 100%
- [ ] 集成测试验证 CREATE TABLE、INSERT、SELECT 端到端流程

## Dependencies
- 依赖现有的 `schema-field-customization` 规范 (提供 `sql_type` 覆盖机制)
- 依赖现有的 `create-table-api` 规范 (CREATE TABLE 生成逻辑)
- 依赖现有的 `insert-query-api` 规范 (INSERT 查询构建)
- 依赖现有的 `select-query-api` 规范 (SELECT 查询构建)

## Related Changes
- 无直接相关变更
- 此变更为 Story 3.6 的独立实现

## Open Questions
1. **数组嵌套深度**: 是否支持多维数组 (如 `[][]i64`)? → 决定: 仅支持一维数组,多维数组通过 JSONB 存储
2. **UUID 输入格式**: 是否同时支持 `[16]u8` 和字符串输入? → 决定: 主要支持 `[16]u8`,字符串通过显式转换
3. **JSONB 库依赖**: 是否引入第三方 JSON 库? → 决定: 使用 `std.json` 标准库

## Rollout Plan
1. **阶段 1**: 实现数组类型映射和序列化 (1-2 天)
2. **阶段 2**: 实现 JSONB 序列化/反序列化 (1 天)
3. **阶段 3**: 实现 UUID 转换 (1 天)
4. **阶段 4**: 集成到 Query Builder (1-2 天)
5. **阶段 5**: 编写集成测试和文档 (1 天)

## Alternatives Considered
### 备选方案 1: 仅通过 `custom_sql_type` 支持
- **优点**: 实现简单,无需修改类型系统
- **缺点**: 开发者体验差,需要手动序列化,无类型安全保证
- **决定**: 不采用,违背 ZORM 类型安全原则

### 备选方案 2: 引入 ORM 映射层
- **优点**: 更灵活,支持复杂类型映射
- **缺点**: 增加复杂度,偏离 SQL-first 设计理念
- **决定**: 不采用,保持简单直接的设计

## Risks and Mitigations
| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 序列化性能开销 | Medium | 使用 Arena 分配器优化临时分配 |
| PostgreSQL 版本兼容性 | Low | 仅支持 PostgreSQL 12+ (主流版本) |
| 边界情况处理 (空数组、NULL) | Medium | 完善测试覆盖边界情况 |
| 与现有代码的向后兼容性 | Low | 新功能为可选,不影响现有代码 |

## Reviewers
- @Core Team (类型系统设计)
- @Schema Team (Schema 配置集成)
- @Query Builder Team (序列化集成)

Authored-By: mobus <mobussun@gmail.com>
