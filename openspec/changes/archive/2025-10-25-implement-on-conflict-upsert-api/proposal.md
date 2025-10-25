# Proposal: Implement ON CONFLICT Upsert API

## Change ID
`implement-on-conflict-upsert-api`

## Status
Draft

## Overview
重构 `InsertQuery` 的 ON CONFLICT API 以符合 PRD Story 4.1 要求，提供符合 Bun ORM 风格的链式 API，支持 PostgreSQL UPSERT 操作的完整功能。

## Motivation

### 当前问题
1. **API 设计不一致**: 当前 `onConflict()` 方法接受单个配置结构体，不符合链式 API 风格
2. **PRD 不匹配**: PRD 期望分离的 `doNothing()` 和 `doUpdate()` 方法
3. **功能缺失**: 缺少部分唯一索引的 WHERE 条件支持 (AC4.1.6)
4. **测试不足**: 缺少集成测试验证真实数据库行为
5. **规范缺失**: 没有完整的 OpenSpec 规范文档

### 业务价值
- **开发体验**: 提供直观的链式 API，降低学习曲线
- **功能完整**: 支持 PostgreSQL ON CONFLICT 的所有特性
- **类型安全**: 编译时验证 SQL 语法正确性
- **文档规范**: 完整的规范和示例代码

## Scope

### In Scope
- 重构 `InsertQuery.onConflict()` API 为链式风格
- 实现 `doNothing()` 方法
- 实现 `doUpdate(assignments)` 方法
- 实现 `whereConflict(condition)` 方法支持部分唯一索引
- 更新 SQL 生成逻辑支持新 API
- 重构现有单元测试
- 添加集成测试验证数据库行为
- 创建完整的 OpenSpec 规范

### Out of Scope
- MySQL ON DUPLICATE KEY UPDATE 语法 (未来变更)
- SQLite UPSERT 支持 (未来变更)
- 多列冲突目标的自动推断
- ON CONFLICT 的性能优化

## Design Highlights

### 新 API 设计
```zig
// 示例 1: DO NOTHING
var query = try db.newInsert(User);
defer query.deinit();

_ = try query
    .value(user)
    .onConflict(&.{"email"})  // 指定冲突列
    .doNothing()              // 冲突时忽略
    .exec();

// 示例 2: DO UPDATE
var query2 = try db.newInsert(User);
defer query2.deinit();

var upserted = std.ArrayList(User).init(allocator);
defer upserted.deinit();

try query2
    .value(user)
    .onConflict(&.{"email"})
    .doUpdate("name = EXCLUDED.name, age = EXCLUDED.age")
    .returning(&.{"*"})
    .execReturning(&upserted);

// 示例 3: 部分唯一索引 (带 WHERE)
var query3 = try db.newInsert(User);
defer query3.deinit();

_ = try query3
    .value(user)
    .onConflict(&.{"email"})
    .whereConflict("active = true")  // 部分唯一索引条件
    .doUpdate("updated_at = CURRENT_TIMESTAMP")
    .exec();
```

### 内部状态管理
```zig
// InsertQuery 新增字段
conflict_target: ?[]const []const u8 = null,
conflict_action: ?ConflictAction = null,
conflict_updates: ?[]const u8 = null,
conflict_where: ?[]const u8 = null,
```

## Alternatives Considered

### 方案 A: 保持当前结构体 API (已拒绝)
- 优点: 无破坏性变更
- 缺点: 不符合 PRD，用户体验差

### 方案 B: 提供两套 API (已拒绝)
- 优点: 向后兼容
- 缺点: API 表面过大，维护成本高，用户混淆

### 方案 C: 完全重构为链式 API (已选择)
- 优点: 符合 PRD，符合 Bun ORM 风格，用户体验优秀
- 缺点: 需要修改现有测试
- 理由: 项目早期阶段，重构成本可控

## Dependencies
- 依赖 `dialect-comptime-features` 规范 (已存在)
- 依赖 `insert-query-api` 规范 (需更新)

## Risks and Mitigations

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 破坏现有代码 | 中 | 项目早期，用户少，修改成本低 |
| SQL 生成逻辑复杂 | 低 | 参考 PostgreSQL 官方文档，充分测试 |
| WHERE 条件解析错误 | 中 | 使用字符串拼接，由用户保证正确性 |

## Success Criteria
- [ ] 所有 AC4.1.1 - AC4.1.7 验收标准通过
- [ ] 单元测试覆盖所有 API 方法和边界情况
- [ ] 集成测试验证真实 PostgreSQL 数据库行为
- [ ] `openspec validate --strict` 通过
- [ ] 生成的 SQL 符合 PostgreSQL 官方语法规范

## Related Changes
- 无前置依赖变更
- 可能触发后续变更: MySQL ON DUPLICATE KEY UPDATE 支持
