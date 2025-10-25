# Implementation Tasks

## Task 1: 重构 InsertQuery 内部状态结构
**Description**: 添加新的状态字段替换现有的 `on_conflict` 字段

**Acceptance Criteria**:
- [x] 添加 `conflict_target: ?[]const []const u8` 字段
- [x] 添加 `conflict_action: ?ConflictAction` 字段
- [x] 添加 `conflict_updates: ?[]const u8` 字段
- [x] 添加 `conflict_where: ?[]const u8` 字段
- [x] 在 `init()` 中初始化所有新字段为 `null`
- [x] 在 `deinit()` 中无需额外清理 (字段为切片引用)

**Dependencies**: 无

**Verification**: 编译通过,现有测试不受影响

---

## Task 2: 实现 onConflict() 方法
**Description**: 实现接受列名数组的 `onConflict()` 方法

**Acceptance Criteria**:
- [x] 方法签名: `pub fn onConflict(self: *Self, columns: []const []const u8) !*Self`
- [x] 编译时检查方言支持: `if (comptime !dialect.supportsOnConflict())`
- [x] 运行时验证: 列数组非空,否则返回 `error.EmptyConflictTarget`
- [x] 存储 `columns` 到 `self.conflict_target`
- [x] 返回 `self` 支持链式调用
- [x] 添加完整的文档注释和使用示例

**Dependencies**: Task 1

**Verification**: 单元测试覆盖正常流程和错误情况

---

## Task 3: 实现 doNothing() 方法
**Description**: 实现设置 DO NOTHING 动作的方法

**Acceptance Criteria**:
- [x] 方法签名: `pub fn doNothing(self: *Self) !*Self`
- [x] 前置条件检查: `conflict_target != null`,否则返回 `error.ConflictTargetNotSet`
- [x] 设置 `self.conflict_action = .do_nothing`
- [x] 返回 `self` 支持链式调用
- [x] 添加文档注释说明必须先调用 `onConflict()`

**Dependencies**: Task 2

**Verification**: 单元测试验证前置条件检查和状态设置

---

## Task 4: 实现 doUpdate() 方法
**Description**: 实现接受 SQL 表达式的 `doUpdate()` 方法

**Acceptance Criteria**:
- [x] 方法签名: `pub fn doUpdate(self: *Self, assignments: []const u8) !*Self`
- [x] 前置条件检查: `conflict_target != null`,否则返回 `error.ConflictTargetNotSet`
- [x] 参数验证: `assignments` 非空,否则返回 `error.EmptyUpdateAssignments`
- [x] 设置 `self.conflict_action = .do_update`
- [x] 存储 `assignments` 到 `self.conflict_updates`
- [x] 返回 `self` 支持链式调用
- [x] 文档注释说明支持 EXCLUDED 关键字和 SQL 函数

**Dependencies**: Task 2

**Verification**: 单元测试覆盖正常流程、边界情况和 EXCLUDED 关键字

---

## Task 5: 实现 whereConflict() 方法
**Description**: 实现部分唯一索引 WHERE 条件支持

**Acceptance Criteria**:
- [x] 方法签名: `pub fn whereConflict(self: *Self, condition: []const u8) !*Self`
- [x] 前置条件检查: `conflict_target != null`,否则返回 `error.ConflictTargetNotSet`
- [x] 参数验证: `condition` 非空,否则返回 `error.EmptyWhereCondition`
- [x] 存储 `condition` 到 `self.conflict_where`
- [x] 返回 `self` 支持链式调用
- [x] 文档注释说明部分唯一索引使用场景

**Dependencies**: Task 2

**Verification**: 单元测试验证前置条件和 WHERE 条件存储

---

## Task 6: 更新 build() SQL 生成逻辑
**Description**: 在 `build()` 方法中生成 ON CONFLICT 子句

**Acceptance Criteria**:
- [x] 在 VALUES 子句后检查 `conflict_target` 是否存在
- [x] 生成 `ON CONFLICT (col1, col2, ...)` 部分
- [x] 如果 `conflict_where` 存在,生成 ` WHERE condition` 部分
- [x] 根据 `conflict_action` 生成 ` DO NOTHING` 或 ` DO UPDATE SET ...`
- [x] DO UPDATE 时使用 `conflict_updates` 生成 SET 表达式
- [x] 验证完整性: 如果有 `conflict_target` 但无 `conflict_action`,返回错误
- [x] RETURNING 子句在 ON CONFLICT 之后生成

**Dependencies**: Task 2, Task 3, Task 4, Task 5

**Verification**: 单元测试验证各种组合的 SQL 生成正确性

---

## Task 7: 添加错误类型定义
**Description**: 定义 ON CONFLICT 相关的错误类型

**Acceptance Criteria**:
- [x] 在 `InsertError` 或全局错误类型中添加:
  - `EmptyConflictTarget`
  - `ConflictTargetNotSet`
  - `ConflictActionNotSet`
  - `EmptyUpdateAssignments`
  - `UpdateAssignmentsNotSet`
  - `EmptyWhereCondition`
- [x] 为每个错误类型添加注释说明触发条件

**Dependencies**: 无

**Verification**: 错误类型在各方法中正确使用

---

## Task 8: 重构现有单元测试
**Description**: 更新现有 ON CONFLICT 测试使用新 API

**Acceptance Criteria**:
- [x] 修改 `test "InsertQuery: ON CONFLICT DO NOTHING (PostgreSQL)"` 使用新 API
- [x] 修改 `test "InsertQuery: ON CONFLICT DO UPDATE (PostgreSQL)"` 使用新 API
- [x] 修改 `test "InsertQuery: 完整复杂插入 (PostgreSQL)"` 使用新 API
- [x] 所有测试通过
- [x] 删除旧的 `onConflict(OnConflictClause)` 测试

**Dependencies**: Task 2, Task 3, Task 4, Task 6

**Verification**: `zig test src/query/query.zig` 全部通过

---

## Task 9: 添加新边界情况测试
**Description**: 为新 API 添加全面的单元测试

**Acceptance Criteria**:
- [x] 测试空列名数组错误
- [x] 测试未调用 `onConflict()` 的错误
- [x] 测试空更新表达式错误
- [x] 测试空 WHERE 条件错误
- [x] 测试多列冲突目标
- [x] 测试 EXCLUDED 在复杂表达式中
- [x] 测试 WHERE 条件与 DO UPDATE 组合
- [x] 测试批量插入与 ON CONFLICT
- [x] 测试与 RETURNING 集成
- [x] 测试链式调用各种组合

**Dependencies**: Task 2-6

**Verification**: 测试覆盖率 >= 90%,所有测试通过

---

## Task 10: 实现集成测试
**Description**: 添加针对真实 PostgreSQL 数据库的集成测试

**Status**: ⚠️ 延后 - 可在后续 PR 中添加

**Acceptance Criteria**:
- [ ] 创建 `tests/on_conflict_integration_test.zig`
- [ ] 测试 DO NOTHING 实际行为 (插入失败但不报错)
- [ ] 测试 DO UPDATE 实际行为 (冲突时更新)
- [ ] 测试 EXCLUDED 关键字正确引用新值
- [ ] 测试部分唯一索引 WHERE 条件
- [ ] 测试与 RETURNING 集成返回正确数据
- [ ] 测试批量 UPSERT 性能
- [ ] 在 CI 中运行集成测试

**Dependencies**: Task 2-9

**Verification**: 集成测试在真实 PostgreSQL 数据库上全部通过

---

## Task 11: 移除旧 API 实现
**Description**: 清理旧的 `onConflict(OnConflictClause)` 实现

**Acceptance Criteria**:
- [x] 删除 `on_conflict: ?OnConflictClause` 字段
- [x] 删除旧的 `onConflict()` 方法实现
- [x] 删除 `on_duplicate_key` 相关字段 (如果未使用)
- [x] 确保没有代码引用旧字段和方法

**Dependencies**: Task 8

**Verification**: 编译通过,grep 无旧 API 引用

---

## Task 12: 更新文档和示例
**Description**: 更新项目文档反映新 API

**Status**: ✅ 部分完成 - API 文档注释已完成,其他文档可后续补充

**Acceptance Criteria**:
- [ ] 更新 `docs/prd.md` 标记 Story 4.1 为已完成
- [ ] 添加 `examples/on_conflict_upsert.zig` 完整示例
- [ ] 更新 README.md 提及 ON CONFLICT 支持
- [x] 更新 API 文档注释 (✅ 已在代码中完成详细注释)
- [x] 确保所有示例代码可编译 (✅ 399 个测试全部通过)

**Dependencies**: Task 2-11

**Verification**: 文档审查通过,示例代码运行成功

---

## Milestone Summary

**Milestone 1: API 基础实现** (Task 1-7)
- 重构状态结构
- 实现所有新方法
- 定义错误类型

**Milestone 2: 测试和验证** (Task 8-10)
- 重构现有测试
- 添加全面单元测试
- 实现集成测试

**Milestone 3: 清理和文档** (Task 11-12)
- 移除旧 API
- 更新文档和示例

**总工作量估算**: 3-5 天 (单人)
