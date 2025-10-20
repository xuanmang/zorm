# 任务清单

## Phase 1: 代码修复 (10 分钟)

### Task 1.1: 修复 SelectQuery.init() 中的 ArrayList 初始化
**预估时间**: 3 分钟
**优先级**: P0 (阻塞构建)

修改 `src/query/query.zig` 第 87-93 行：
- 将所有 `ArrayList(T).init(allocator)` 改为 `ArrayList(T){}`
- 受影响的字段：columns, where_clauses, join_clauses, order_by_clauses, group_by_columns, having_clauses

**验收标准**:
- SelectQuery 初始化相关的编译错误消失
- 代码格式符合 `zig fmt` 规范

### Task 1.2: 修复 InsertQuery.buildSQL() 中的缓冲区初始化
**预估时间**: 2 分钟
**优先级**: P0 (阻塞构建)

修改 `src/query/query.zig` 第 948 行：
- 将 `ArrayList(u8).init(allocator)` 改为 `ArrayList(u8){}`

**验收标准**:
- InsertQuery.buildSQL() 相关的编译错误消失

### Task 1.3: 修复 UpdateQuery.buildSQL() 中的缓冲区初始化
**预估时间**: 2 分钟
**优先级**: P0 (阻塞构建)

修改 `src/query/query.zig` 第 1464 行：
- 将 `ArrayList(u8).init(allocator)` 改为 `ArrayList(u8){}`

**验收标准**:
- UpdateQuery.buildSQL() 相关的编译错误消失

### Task 1.4: 修复 DeleteQuery.buildSQL() 中的缓冲区初始化
**预估时间**: 2 分钟
**优先级**: P0 (阻塞构建)

修改 `src/query/query.zig` 第 1899 行：
- 将 `ArrayList(u8).init(allocator)` 改为 `ArrayList(u8){}`

**验收标准**:
- DeleteQuery.buildSQL() 相关的编译错误消失

### Task 1.5: 代码格式化
**预估时间**: 1 分钟
**优先级**: P1

```bash
zig fmt src/query/query.zig
```

**验收标准**:
- 代码格式符合 Zig 标准

## Phase 2: 验证和测试 (5 分钟)

### Task 2.1: 编译验证
**预估时间**: 2 分钟
**优先级**: P0

```bash
zig build-lib src/query/query.zig -femit-bin=/dev/null
```

**验收标准**:
- 无编译错误
- 无编译警告

### Task 2.2: 运行完整测试套件
**预估时间**: 3 分钟
**优先级**: P0

```bash
zig build test
```

**验收标准**:
- 所有测试编译成功
- 所有测试运行通过
- 无内存泄漏（Zig 的内存检查器会报告）

## Phase 3: 文档和提交 (10 分钟)

### Task 3.1: OpenSpec 验证
**预估时间**: 2 分钟
**优先级**: P1

```bash
openspec validate fix-zig-015-arraylist-api --strict
```

**验收标准**:
- OpenSpec 验证通过

### Task 3.2: 全局搜索其他潜在问题
**预估时间**: 3 分钟
**优先级**: P2 (预防性)

```bash
rg "ArrayList.*\.init\(" src/
```

**验收标准**:
- 确认其他文件没有类似问题
- 如有问题，记录在提案中

### Task 3.3: Git 提交
**预估时间**: 5 分钟
**优先级**: P1

```bash
git add src/query/query.zig openspec/changes/fix-zig-015-arraylist-api/
git commit -m "fix: 修复 Zig 0.15 ArrayList API 兼容性问题 (openspec: fix-zig-015-arraylist-api)"
```

提交信息模板：
```
fix: 修复 Zig 0.15 ArrayList API 兼容性问题 (openspec: fix-zig-015-arraylist-api)

修复由于 Zig 0.15 ArrayList API 变更导致的 4 个编译错误。

## 主要变更

- 将 ArrayList(T).init(allocator) 改为 ArrayList(T){}
- 影响位置: src/query/query.zig (第 87-93, 948, 1464, 1899 行)

## 技术细节

Zig 0.15 移除了 ArrayList(T).init() 方法：
- 旧 API: ArrayList(T).init(allocator)
- 新 API: ArrayList(T){} 或 ArrayList(T).empty

## 验收标准

- [x] 所有编译错误已修复
- [x] zig build test 通过
- [x] 所有测试运行成功
- [x] OpenSpec 验证通过

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
Authored-By: mobus <mobussun@gmail.com>
```

**验收标准**:
- 提交包含所有必要文件
- 提交信息清晰准确
- 包含 OpenSpec 变更引用

## Phase 4: 归档 (可选，5 分钟)

### Task 4.1: 归档变更提案
**预估时间**: 2 分钟
**优先级**: P2

```bash
openspec archive fix-zig-015-arraylist-api --yes
```

**验收标准**:
- 变更提案已归档到 archive 目录
- 如果需要创建规格，则创建相应规格

### Task 4.2: 最终验证
**预估时间**: 3 分钟
**优先级**: P2

```bash
openspec validate --all --strict
```

**验收标准**:
- 所有规格验证通过
- 项目处于一致状态

## 总预估时间

- Phase 1: 10 分钟
- Phase 2: 5 分钟
- Phase 3: 10 分钟
- Phase 4: 5 分钟 (可选)

**总计**: 25-30 分钟

## 并行化机会

- Task 1.1-1.4 可以顺序完成（单个文件）
- Task 2.1 和 2.2 必须顺序执行
- Task 3.2 可以与 Task 3.1 并行

## 风险和阻塞

- **低风险**: 修改范围小，影响明确
- **无阻塞**: 不依赖其他变更或外部服务
- **快速回滚**: 如有问题可直接 `git revert`

## 依赖关系

```
Task 1.1 ──┐
Task 1.2 ──┼─→ Task 1.5 ─→ Task 2.1 ─→ Task 2.2 ─→ Task 3.1 ─→ Task 3.3
Task 1.3 ──┤                                         ↓
Task 1.4 ──┘                                    Task 3.2 (并行)
```

## 检查清单

完成后检查：
- [ ] 所有 4 处 ArrayList 初始化已修复
- [ ] zig build test 通过
- [ ] 代码格式化完成
- [ ] OpenSpec 验证通过
- [ ] Git 提交完成
- [ ] 无其他潜在问题
