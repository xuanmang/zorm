# Tasks: Complete SELECT Query Builder

## Phase 1: 核心方法实现

### 1.1 添加 buildSQL() 别名方法

**验收标准**：
- `buildSQL()` 方法实现并通过测试
- 行为与 `build(null)` 完全一致
- 包含完整的文档注释和示例

**实施步骤**：
1. 在 `src/query/query.zig` 的 `SelectQuery` 中添加 `buildSQL()` 方法
2. 实现为 `return self.build(null);`
3. 添加文档注释，说明与 `build()` 的关系
4. 添加单元测试验证等价性

**依赖**：无

**预计时间**：15 分钟

---

### 1.2 实现 allColumns() comptime 反射

**验收标准**：
- `allColumns()` 方法使用 `@typeInfo` 和 `inline for` 实现
- 编译时展开，零运行时开销
- 追加到现有列列表（不清空）
- 通过单元测试验证字段顺序和数量

**实施步骤**：
1. 在 `SelectQuery` 中添加 `allColumns()` 方法
2. 使用 `@typeInfo(T).Struct.fields` 获取字段列表
3. 使用 `inline for` 遍历字段并调用 `self.columns.append()`
4. 添加文档注释，说明 comptime 行为
5. 添加单元测试验证以下场景：
   - 自动添加所有字段
   - 字段顺序正确
   - 可以与 `column()` 混合使用

**依赖**：无

**预计时间**：30 分钟

---

### 1.3 实现 collectArgs() 参数收集

**验收标准**：
- `collectArgs()` 方法正确收集 WHERE 和 HAVING 参数
- 参数顺序保持一致
- 返回的切片需调用者释放
- 包含错误处理（errdefer）

**实施步骤**：
1. 在 `SelectQuery` 中添加私有方法 `collectArgs()`
2. 创建 `std.ArrayList(QueryArg)` 临时列表
3. 遍历 `self.where_clauses.items`，追加所有参数
4. 遍历 `self.having_clauses.items`，追加所有参数
5. 返回 `try args.toOwnedSlice()`
6. 添加单元测试验证参数收集和顺序

**依赖**：无

**预计时间**：45 分钟

---

## Phase 2: 集成和测试

### 2.1 更新 scan() 使用 collectArgs()

**验收标准**：
- `scan()` 方法调用 `collectArgs()` 获取参数
- 参数正确传递给数据库驱动
- 内存正确释放（使用 defer）
- 通过集成测试验证

**实施步骤**：
1. 修改 `scan()` 方法，替换现有参数收集逻辑
2. 调用 `const args = try self.collectArgs()`
3. 添加 `defer self.allocator.free(args)`
4. 将参数传递给 `db.driver.query()`
5. 运行集成测试验证查询结果正确

**依赖**：1.3 完成

**预计时间**：20 分钟

---

### 2.2 更新 scanOne() 使用 collectArgs()

**验收标准**：
- `scanOne()` 方法调用 `collectArgs()` 获取参数
- 单行查询正确返回结果
- 无内存泄漏

**实施步骤**：
1. 修改 `scanOne()` 方法，使用 `collectArgs()`
2. 添加 defer 释放参数切片
3. 运行集成测试验证单行查询

**依赖**：1.3 完成

**预计时间**：15 分钟

---

### 2.3 更新 count() 使用 collectArgs()

**验收标准**：
- `count()` 方法调用 `collectArgs()` 获取参数
- COUNT 查询正确返回计数
- 无内存泄漏

**实施步骤**：
1. 修改 `count()` 方法，使用 `collectArgs()`
2. 添加 defer 释放参数切片
3. 运行集成测试验证计数查询

**依赖**：1.3 完成

**预计时间**：15 分钟

---

### 2.4 编写完整单元测试套件

**验收标准**：
- 所有新方法有独立单元测试
- 测试覆盖正常路径和边界情况
- 测试验证向后兼容性
- 所有测试通过

**实施步骤**：
1. 创建测试文件或在现有测试中添加测试用例
2. 测试 `buildSQL()` 与 `build(null)` 等价性
3. 测试 `allColumns()` 自动字段添加
4. 测试 `allColumns()` 与 `column()` 混合使用
5. 测试 `collectArgs()` 参数收集和顺序
6. 测试 `scan()`, `scanOne()`, `count()` 参数传递
7. 运行 `zig build test` 验证所有测试通过

**依赖**：1.1, 1.2, 1.3, 2.1, 2.2, 2.3 完成

**预计时间**：30 分钟

---

### 2.5 编写集成测试

**验收标准**：
- 与实际数据库集成测试
- 验证 SQL 正确执行
- 验证查询结果正确
- 所有集成测试通过

**实施步骤**：
1. 设置测试数据库环境
2. 插入测试数据
3. 使用 `allColumns()`, `buildSQL()` 执行查询
4. 验证返回的数据正确
5. 清理测试数据

**依赖**：1.1, 1.2, 2.1, 2.2, 2.3 完成

**预计时间**：30 分钟

---

## Phase 3: 文档和优化

### 3.1 更新模块文档注释

**验收标准**：
- 所有新方法有完整的文档注释
- 包含使用示例
- 说明设计决策（如 comptime, 向后兼容）
- 文档格式符合 Zig 标准

**实施步骤**：
1. 为 `buildSQL()` 添加文档注释和示例
2. 为 `allColumns()` 添加文档注释，说明 comptime 行为
3. 为 `collectArgs()` 添加文档注释（私有方法）
4. 更新 `SelectQuery` 模块级文档
5. 运行 `zig build docs` 验证文档生成

**依赖**：所有实现任务完成

**预计时间**：30 分钟

---

### 3.2 更新功能规格示例代码

**验收标准**：
- 功能规格 2.2.1 的示例代码可以编译运行
- 示例展示新增方法的用法
- 示例验证与实现一致

**实施步骤**：
1. 审查 `docs/functional_spec.md` 中 2.2.1 的示例
2. 确认示例代码与实现一致
3. 如有差异，更新示例或提出问题
4. 添加 `allColumns()` 的使用示例

**依赖**：所有实现任务完成

**预计时间**：20 分钟

---

### 3.3 性能基准测试（可选）

**验收标准**：
- `allColumns()` 性能与手动调用 `column()` 相当
- 验证 comptime 展开无运行时开销
- 基准测试结果记录在文档中

**实施步骤**：
1. 创建性能基准测试
2. 比较 `allColumns()` 与手动调用的性能
3. 验证误差在可接受范围（±10%）
4. 将结果记录在 design.md 中

**依赖**：1.2 完成

**预计时间**：30 分钟

---

## Phase 4: 验证和提交

### 4.1 运行 openspec validate

**验收标准**：
- `openspec validate complete-select-query-builder --strict` 通过
- 所有规格增量格式正确
- 所有场景有明确的验收条件

**实施步骤**：
1. 运行 `openspec validate complete-select-query-builder --strict`
2. 修复任何验证错误
3. 确认所有需求和场景格式正确

**依赖**：所有文档和实现完成

**预计时间**：15 分钟

---

### 4.2 代码格式化和检查

**验收标准**：
- 代码通过 `zig fmt --check` 检查
- 代码符合项目编码规范
- 无编译警告

**实施步骤**：
1. 运行 `zig fmt src/query/query.zig`
2. 运行 `zig build` 验证编译
3. 检查编译输出，确保无警告

**依赖**：所有实现完成

**预计时间**：10 分钟

---

### 4.3 最终测试运行

**验收标准**：
- 所有单元测试通过
- 所有集成测试通过
- 无内存泄漏（使用 testing allocator）

**实施步骤**：
1. 运行 `zig build test` 执行所有测试
2. 验证所有测试通过
3. 检查测试输出，确认无内存泄漏

**依赖**：所有实现和测试完成

**预计时间**：10 分钟

---

### 4.4 创建 Git 提交

**验收标准**：
- 提交信息符合项目规范
- 提交包含所有相关文件
- 提交信息引用 OpenSpec 变更 ID

**实施步骤**：
1. 暂存所有修改的文件
2. 编写提交信息：
   ```
   feat: 完善 SELECT 查询构建器 API (openspec: complete-select-query-builder)

   实现功能规格 2.2.1 定义的完整 SELECT 查询构建器 API：

   - 添加 buildSQL() 方法作为 build(null) 的别名
   - 实现 allColumns() comptime 反射自动选择所有字段
   - 实现 collectArgs() 统一参数收集
   - 更新 scan(), scanOne(), count() 使用 collectArgs()
   - 添加完整的单元测试和集成测试
   - 更新文档和示例

   🤖 Generated with [Claude Code](https://claude.com/claude-code)

   Co-Authored-By: Claude <noreply@anthropic.com>
   Authored-By: mobus <mobussun@gmail.com>
   ```
3. 执行 `git commit`

**依赖**：所有任务完成

**预计时间**：10 分钟

---

## 总结

**总预计时间**：约 4 小时

### 任务优先级

**P0 - 必须完成**：
- 1.1 添加 buildSQL() 别名
- 1.2 实现 allColumns()
- 1.3 实现 collectArgs()
- 2.1, 2.2, 2.3 更新查询方法
- 2.4 单元测试
- 4.1 OpenSpec 验证

**P1 - 重要**：
- 2.5 集成测试
- 3.1 文档更新
- 4.2, 4.3 代码检查和测试

**P2 - 可选**：
- 3.2 示例代码更新
- 3.3 性能基准测试

### 并行执行可能性

- 1.1, 1.2 可以并行实现（独立方法）
- 2.4 单元测试可以在实现过程中逐步编写
- 3.1 文档可以在实现的同时编写

### 阻塞关系

```
1.3 (collectArgs)
  ├── 2.1 (scan)
  ├── 2.2 (scanOne)
  └── 2.3 (count)
       └── 2.4 (单元测试)
            └── 2.5 (集成测试)
                 └── 3.1 (文档)
                      └── 4.x (验证和提交)

1.1 (buildSQL) ──┐
1.2 (allColumns) ┘──> 可并行实现 ──> 2.4 (单元测试)
```
