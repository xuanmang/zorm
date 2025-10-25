# Proposal: Implement JOIN Query Support

## Change ID
`implement-join-query-support`

## Status
Draft

## Overview
为 `SelectQuery` 添加完整的 JOIN 查询支持规范和集成测试，确保符合 PRD Story 4.2 的所有验收标准。虽然基础 JOIN API 已实现，但缺少正式规范文档和完整的集成测试验证。

## Motivation

### 当前状态
1. **API 已实现**: `join()`, `innerJoin()`, `leftJoin()`, `rightJoin()`, `fullJoin()`, `crossJoin()` 方法已存在
2. **SQL 生成已支持**: `build()` 方法已正确处理 JOIN 子句
3. **类型定义完整**: `JoinType` 枚举和 `JoinClause` 结构体已定义

### 存在问题
1. **规范缺失**: 没有正式的 OpenSpec 规范文档定义 JOIN 功能
2. **测试不足**: 缺少集成测试验证真实 PostgreSQL 数据库 JOIN 行为
3. **文档不完整**: 缺少多表连接、表别名、参数绑定等场景的示例
4. **验收标准未验证**: PRD Story 4.2 的 AC4.2.6（JOIN 结果扫描到自定义结构体）未测试

### 业务价值
- **规范化**: 通过 OpenSpec 正式定义 JOIN 功能，便于维护和扩展
- **质量保证**: 集成测试确保 JOIN 在真实数据库环境下正常工作
- **开发体验**: 完整的文档和示例降低学习曲线
- **PRD 对齐**: 验证所有 AC 要求，确保符合产品需求

## Scope

### In Scope
- 创建 `select-query-join-api` 规范文档
- 编写完整的 JOIN 集成测试（多种 JOIN 类型、多个 JOIN、表别名、参数绑定）
- 验证 JOIN 结果扫描到自定义结构体（AC4.2.6）
- 补充 SQL 生成的单元测试（边界情况、错误处理）
- 更新相关文档和示例

### Out of Scope
- JOIN 性能优化（未来变更）
- JOIN 查询计划分析工具（未来变更）
- 子查询作为 JOIN 源（Story 4.4）
- 自动 JOIN 条件推断（未来变更）

## Design Highlights

### API 已实现的功能
```zig
// 基础 JOIN 方法
pub fn join(self: *Self, join_type: JoinType, table: []const u8, condition: []const u8) !*Self

// 便捷方法（已实现）
pub fn innerJoin(self: *Self, table: []const u8, condition: []const u8) !*Self
pub fn leftJoin(self: *Self, table: []const u8, condition: []const u8) !*Self
pub fn rightJoin(self: *Self, table: []const u8, condition: []const u8) !*Self
pub fn fullJoin(self: *Self, table: []const u8, condition: []const u8) !*Self
pub fn crossJoin(self: *Self, table: []const u8) !*Self
```

### 需要验证的关键场景
```zig
// 场景 1: 多个 JOIN 链式调用
var query = try db.newSelect(UserWithProfile);
defer query.deinit();

try query
    .column("u.id AS user_id")
    .column("u.name AS user_name")
    .column("p.bio AS profile_bio")
    .column("o.total AS order_total")
    .from("users AS u")
    .leftJoin("profiles AS p", "p.user_id = u.id")
    .leftJoin("orders AS o", "o.user_id = u.id")
    .where("u.is_active = $1", .{true})
    .scan(&results);

// 场景 2: JOIN 条件中使用参数绑定
var query = try db.newSelect(Result);
defer query.deinit();

try query
    .from("users AS u")
    .innerJoin("orders AS o", "o.user_id = u.id AND o.status = $1")
    .where("u.age > $2", .{"completed", 18})
    .scan(&results);

// 场景 3: 自定义结构体接收 JOIN 结果
const UserWithProfile = struct {
    user_id: i64,
    user_name: []const u8,
    profile_bio: ?[]const u8,
};

var results = std.ArrayList(UserWithProfile).init(allocator);
defer results.deinit();

try query.scan(&results);
```

## Dependencies
- 依赖 `select-query-api` 规范（已存在）
- 依赖 `query-context-api` 规范（已存在）
- 依赖 PostgreSQL 数据库驱动集成测试环境

## Risks and Mitigations

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| JOIN 结果扫描类型映射错误 | 高 | 集成测试覆盖各种字段类型组合 |
| 多表 JOIN 性能问题 | 中 | 文档中提供性能优化建议，后续优化 |
| 参数绑定顺序错误 | 中 | 测试覆盖参数顺序敏感场景 |
| 表别名解析失败 | 低 | PostgreSQL 原生支持，驱动层处理 |

## Success Criteria
- [ ] 所有 AC4.2.1 - AC4.2.8 验收标准通过
- [ ] 集成测试覆盖所有 JOIN 类型（INNER, LEFT, RIGHT, FULL, CROSS）
- [ ] 集成测试验证多个 JOIN 链式调用
- [ ] 集成测试验证表别名功能
- [ ] 集成测试验证 JOIN 条件中的参数绑定
- [ ] 集成测试验证 JOIN 结果扫描到自定义结构体
- [ ] `openspec validate --strict` 通过
- [ ] 生成的 SQL 符合 PostgreSQL 语法规范

## Alternatives Considered

### 方案 A: 仅添加测试，不创建规范（已拒绝）
- 优点: 工作量小
- 缺点: 缺少正式规范，难以维护和扩展

### 方案 B: 重构 JOIN API（已拒绝）
- 优点: 可能改进设计
- 缺点: 当前 API 已符合 PRD，重构无必要

### 方案 C: 补充规范和测试（已选择）
- 优点: 规范化现有功能，确保质量
- 缺点: 需要编写文档工作
- 理由: 符合 OpenSpec 工作流，长期价值高

## Related Changes
- 无前置依赖变更
- 可能触发后续变更: Story 4.4 子查询支持
