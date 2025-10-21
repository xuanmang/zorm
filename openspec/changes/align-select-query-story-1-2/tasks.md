# Tasks

## 1. 添加 setDistinct() 方法

**Owner**: Implementation Team
**Priority**: High
**Estimated Time**: 10 分钟

在 `src/query/query.zig` 的 `SelectQuery` 结构体中添加 `setDistinct()` 方法作为 `distinct()` 的别名。

**验证**:
- [ ] `setDistinct()` 方法存在并设置 `distinct_value = true`
- [ ] 支持链式调用（返回 `*Self`）
- [ ] 包含完整的文档注释和示例代码

**依赖**: 无

---

## 2. 更新 distinct() 方法文档

**Owner**: Implementation Team
**Priority**: Medium
**Estimated Time**: 5 分钟

更新 `distinct()` 方法的文档注释，说明推荐使用 `setDistinct()` 以符合 PRD 规范。

**验证**:
- [ ] 文档注释包含"推荐使用 setDistinct()"的说明
- [ ] 说明此方法保留用于向后兼容

**依赖**: 任务 1

---

## 3. 添加 setDistinct() 单元测试

**Owner**: Implementation Team
**Priority**: High
**Estimated Time**: 15 分钟

在 `src/query/query.zig` 的测试部分添加 `setDistinct()` 方法的测试用例。

**验证**:
- [ ] 测试 `setDistinct()` 正确生成 `SELECT DISTINCT` SQL
- [ ] 测试 `setDistinct()` 与 `distinct()` 功能等价
- [ ] 测试 `setDistinct()` 支持链式调用
- [ ] 测试 `setDistinct()` 与 `column()` 组合使用
- [ ] 测试 `setDistinct()` 与 `count()` 组合使用

**依赖**: 任务 1

---

## 4. 验证 PRD 示例代码

**Owner**: QA Team
**Priority**: High
**Estimated Time**: 10 分钟

使用 PRD Story 1.3 的示例代码验证 API 可用性。

**验证**:
- [ ] PRD 示例代码可编译
- [ ] PRD 示例代码执行正确
- [ ] 生成的 SQL 符合预期

**依赖**: 任务 1, 任务 3

---

## 5. 运行完整测试套件

**Owner**: CI/CD
**Priority**: High
**Estimated Time**: 5 分钟

运行所有测试确保没有引入回归问题。

**验证**:
- [ ] 所有现有测试通过
- [ ] 新增测试通过
- [ ] 无内存泄漏（使用 `std.testing.allocator`）

**依赖**: 任务 3

---

## Implementation Order

1. 添加 setDistinct() 方法（任务 1）
2. 更新 distinct() 方法文档（任务 2）
3. 添加单元测试（任务 3）
4. 验证 PRD 示例代码（任务 4）
5. 运行完整测试套件（任务 5）

## Parallel Work Opportunities

- 任务 2 可以与任务 1 并行进行
- 任务 4 可以在任务 3 完成后立即开始

## Definition of Done

- [ ] 所有任务完成并验证通过
- [ ] 代码审查完成
- [ ] 文档更新完成
- [ ] 所有测试通过（包括内存泄漏检测）
- [ ] 代码已提交并推送
