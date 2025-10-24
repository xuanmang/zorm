# Implementation Tasks: Complete Transaction API

## Overview
本任务列表针对 Story 2.4 (Transaction Management API) 和 Story 2.5 (Transaction Isolation Levels) 的实现验证和完善工作。核心功能已在 `src/core/tx_manager.zig` 和 `src/core/types.zig` 中实现，本阶段主要进行测试增强和文档完善。

## Task Status
- ✅ Completed
- ⏳ In Progress
- ❌ Blocked
- 🔄 Review

---

## Phase 1: 代码验证和测试增强

### Task 1.1: 验证 TxManager 核心功能
**Status**: ⏳
**Assignee**: -
**Dependencies**: None
**Estimate**: 1h

**Description**:
验证 `src/core/tx_manager.zig` 实现符合所有 AC 要求：
- ✅ `beginTx()` API (AC2.4.1)
- ✅ 查询构建器方法 (AC2.4.2)
- ✅ `commit()` 方法 (AC2.4.3)
- ✅ `rollback()` 方法 (AC2.4.4)
- ✅ `errdefer` 支持 (AC2.4.5)
- ✅ 连接共享 (AC2.4.6)
- ✅ 嵌套事务检测 (AC2.4.7)

**Validation**:
```bash
# 检查代码实现
rg -n "pub fn beginTx" src/core/db.zig
rg -n "pub fn commit" src/core/tx_manager.zig
rg -n "pub fn rollback" src/core/tx_manager.zig
rg -n "NestedTransaction" src/core/tx_manager.zig
```

---

### Task 1.2: 验证隔离级别功能
**Status**: ⏳
**Assignee**: -
**Dependencies**: None
**Estimate**: 0.5h

**Description**:
验证 `src/core/types.zig` 中 `IsolationLevel` 定义和 `toSQL()` 方法符合 AC 要求：
- ✅ IsolationLevel 枚举 (AC2.5.1)
- ✅ TxOptions 包含 isolation_level (AC2.5.2)
- ✅ toSQL() 转换方法
- ✅ `SET TRANSACTION ISOLATION LEVEL` 执行 (AC2.5.4)

**Validation**:
```bash
# 检查代码实现
rg -n "pub const IsolationLevel" src/core/types.zig
rg -n "pub fn toSQL" src/core/types.zig
rg -n "SET TRANSACTION ISOLATION LEVEL" src/core/tx_manager.zig
```

---

### Task 1.3: 编写事务基本功能测试
**Status**: ⏳
**Assignee**: -
**Dependencies**: Task 1.1
**Estimate**: 2h

**Description**:
在 `src/query/query.zig` 或新建 `tests/transaction_test.zig` 文件中添加以下测试用例：

1. **基本事务流程**:
   - 开启事务 → 插入数据 → 提交 → 验证数据存在
   - 开启事务 → 插入数据 → 回滚 → 验证数据不存在

2. **errdefer 自动回滚**:
   - 开启事务 → 插入数据 → 触发错误 → 验证数据不存在

3. **deinit 自动回滚**:
   - 开启事务 → 插入数据 → 离开作用域 → 验证数据不存在

4. **嵌套事务检测**:
   - 开启事务 → 尝试开启第二个事务 → 验证返回 `error.NestedTransaction`

5. **状态跟踪**:
   - 验证 `is_active`, `is_committed`, `is_rolled_back` 状态正确性

**Validation**:
```bash
zig test src/query/query.zig --test-filter "事务"
```

---

### Task 1.4: 编写隔离级别测试
**Status**: ⏳
**Assignee**: -
**Dependencies**: Task 1.2
**Estimate**: 1.5h

**Description**:
在测试文件中添加以下隔离级别测试用例：

1. **IsolationLevel 枚举**:
   - 验证四个枚举值正确定义
   - 验证 `toSQL()` 转换正确

2. **TxOptions 默认值**:
   - 验证 `isolation_level` 默认为 `null`

3. **隔离级别设置**:
   - 开启事务（指定 `serializable`）→ 查询事务隔离级别 → 验证设置成功

4. **不同隔离级别测试**:
   - 测试所有四个隔离级别的事务

**Validation**:
```bash
zig test src/core/types.zig --test-filter "IsolationLevel"
```

---

### Task 1.5: 编写查询构建器集成测试
**Status**: ⏳
**Assignee**: -
**Dependencies**: Task 1.1
**Estimate**: 2h

**Description**:
验证事务管理器的查询构建器方法正常工作：

1. **tx.newSelect()**:
   - 在事务中执行 SELECT 查询

2. **tx.newInsert()**:
   - 在事务中执行 INSERT 查询
   - 使用 RETURNING 子句

3. **tx.newUpdate()**:
   - 在事务中执行 UPDATE 查询

4. **tx.newDelete()**:
   - 在事务中执行 DELETE 查询

5. **tx.newRaw()**:
   - 在事务中执行 Raw SQL

**Validation**:
```bash
zig test src/query/query.zig --test-filter "事务查询构建器"
```

---

### Task 1.6: 编写幂等性测试
**Status**: ⏳
**Assignee**: -
**Dependencies**: Task 1.1
**Estimate**: 1h

**Description**:
验证 `commit()` 和 `rollback()` 的幂等性：

1. **重复 commit**:
   - 开启事务 → 提交 → 再次提交 → 验证返回 `error.AlreadyCommitted`

2. **重复 rollback**:
   - 开启事务 → 回滚 → 再次回滚 → 验证不报错（幂等）

3. **commit 后 rollback**:
   - 开启事务 → 提交 → 尝试回滚 → 验证返回 `error.AlreadyCommitted`

**Validation**:
```bash
zig test src/core/tx_manager.zig --test-filter "幂等"
```

---

## Phase 2: 文档和示例

### Task 2.1: 更新 PRD 示例为可运行测试
**Status**: ⏳
**Assignee**: -
**Dependencies**: Task 1.3, Task 1.4
**Estimate**: 1h

**Description**:
将 PRD 中的事务示例（AC2.4.8, AC2.5.5）转换为可执行的测试用例。

**Validation**:
```bash
# 验证 PRD 示例测试通过
zig test src/query/query.zig --test-filter "PRD 示例"
```

---

### Task 2.2: 编写事务使用文档
**Status**: 🔄
**Assignee**: -
**Dependencies**: Phase 1 完成
**Estimate**: 1.5h

**Description**:
在 `docs/` 目录创建事务使用指南：
- 基本事务操作
- 隔离级别选择指南
- 错误处理最佳实践
- 性能优化建议
- 常见陷阱和注意事项

**Files**:
- `docs/transaction-guide.md`

**Validation**:
文档包含完整的代码示例和最佳实践建议。

---

### Task 2.3: 创建事务示例程序
**Status**: 🔄
**Assignee**: -
**Dependencies**: Phase 1 完成
**Estimate**: 2h

**Description**:
在 `examples/` 目录创建完整的事务示例程序（符合 PRD AC4.7.3）：
- `examples/transaction_basic.zig` - 基本事务操作
- `examples/transaction_isolation.zig` - 隔离级别示例

**Validation**:
```bash
zig build examples
./zig-out/bin/transaction_basic
./zig-out/bin/transaction_isolation
```

---

## Phase 3: 验证和发布

### Task 3.1: 运行完整测试套件
**Status**: ⏳
**Assignee**: -
**Dependencies**: Phase 1, Phase 2 完成
**Estimate**: 0.5h

**Description**:
运行所有测试，确保无回归：

```bash
zig build test
```

**Validation**:
- 所有测试通过
- 无内存泄漏（std.testing.allocator）
- 测试覆盖率 > 80%

---

### Task 3.2: OpenSpec 验证
**Status**: ⏳
**Assignee**: -
**Dependencies**: Task 3.1
**Estimate**: 0.5h

**Description**:
验证 OpenSpec 提案格式正确：

```bash
openspec validate complete-transaction-api --strict
```

**Validation**:
验证通过，无错误或警告。

---

### Task 3.3: 代码审查和清理
**Status**: 🔄
**Assignee**: -
**Dependencies**: Task 3.1, Task 3.2
**Estimate**: 1h

**Description**:
审查和清理代码：
- 检查代码注释完整性
- 验证错误消息清晰度
- 确认遵循 Zig 最佳实践
- 移除调试代码和注释

**Validation**:
代码审查通过，无遗留 TODO 或 FIXME。

---

### Task 3.4: 提交代码到 Git
**Status**: ⏳
**Assignee**: -
**Dependencies**: Task 3.3
**Estimate**: 0.5h

**Description**:
提交所有变更到 Git：

```bash
git add openspec/changes/complete-transaction-api/
git add src/core/tx_manager.zig src/core/types.zig src/core/db.zig
git add tests/transaction_test.zig
git add docs/transaction-guide.md
git add examples/transaction_*.zig

git commit -m "feat: 完成事务管理 API (PRD Story 2.4 & 2.5) 并增强测试覆盖

## 主要变更

### 1. OpenSpec 提案 (openspec/changes/complete-transaction-api/)
- 📝 创建 proposal.md，design.md，tasks.md
- 📝 创建 transaction-management-api 规格说明
- 📝 创建 transaction-isolation-levels 规格说明
- ✅ 验证通过 \`openspec validate --strict\`

### 2. 测试增强
- ✅ 添加事务基本功能测试
- ✅ 添加隔离级别测试
- ✅ 添加查询构建器集成测试
- ✅ 添加幂等性测试
- ✅ 所有 PRD 示例转换为可执行测试

### 3. 文档和示例
- 📚 创建事务使用指南 (docs/transaction-guide.md)
- 📚 创建事务示例程序 (examples/transaction_*.zig)

## AC 验证

✅ AC2.4.1: 提供 \`db.beginTx()\` API
✅ AC2.4.2: TxManager 提供查询构建器方法
✅ AC2.4.3: 提供 \`tx.commit()\` 方法
✅ AC2.4.4: 提供 \`tx.rollback()\` 方法
✅ AC2.4.5: 支持 \`errdefer\` 自动回滚
✅ AC2.4.6: 事务内操作共享连接
✅ AC2.4.7: 嵌套事务检测并返回错误
✅ AC2.4.8: PRD 示例验证通过

✅ AC2.5.1: 定义 IsolationLevel 枚举
✅ AC2.5.2: TxOptions 包含 isolation_level
✅ AC2.5.3: 默认使用 PostgreSQL 默认级别
✅ AC2.5.4: 执行 SET TRANSACTION ISOLATION LEVEL
✅ AC2.5.5: PRD 示例验证通过

## 测试结果

\`\`\`
Build Summary: XXX/XXX tests passed
- TxManager 所有测试通过
- IsolationLevel 所有测试通过
- 无内存泄漏
- 测试覆盖率 > 80%
\`\`\`

## 相关 PRD

- Epic 2: Complete CRUD & Transaction Support
- Story 2.4: Transaction Management API
- Story 2.5: Transaction Isolation Levels

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Authored-By: mobus <mobussun@gmail.com>"
```

**Validation**:
提交成功，commit message 清晰完整。

---

## Summary

### Total Tasks: 14
- Phase 1 (验证和测试): 6 tasks
- Phase 2 (文档): 3 tasks
- Phase 3 (发布): 5 tasks

### Estimated Time: ~14.5 hours
- Phase 1: 8.5h
- Phase 2: 4.5h
- Phase 3: 2.5h

### Critical Path
Task 1.1 → Task 1.3 → Task 1.5 → Task 3.1 → Task 3.2 → Task 3.3 → Task 3.4

### Parallelizable Tasks
- Task 1.2 和 Task 1.1 可以并行
- Task 1.4 和 Task 1.3 可以并行（在各自依赖满足后）
- Task 2.2 和 Task 2.3 可以并行

### Success Criteria
- [ ] 所有测试通过（zig build test）
- [ ] OpenSpec 验证通过（openspec validate --strict）
- [ ] 测试覆盖率 > 80%
- [ ] 文档完整且示例可运行
- [ ] 代码审查通过
- [ ] 成功提交到 Git
