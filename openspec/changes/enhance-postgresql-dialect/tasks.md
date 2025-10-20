# Tasks: enhance-postgresql-dialect

本文档按优先级列出完善 PostgreSQL 方言系统所需的具体任务。

## Phase 1: Feature 枚举扩展 (1-2 天)

### Task 1.1: 扩展 Feature 枚举定义
**描述**: 在 `src/dialect/dialect.zig` 中扩展 `Feature` 枚举，按功能类别组织。

**验收标准**:
- [x] Feature 枚举包含以下分类：
  - DML Features: `returning`, `on_conflict`, `upsert`, `insert_ignore`, `on_duplicate_key`, `merge`, `output_clause`
  - Query Features: `cte`, `window_functions`, `lateral_join`
  - Data Types: `arrays`, `jsonb`, `uuid`
  - PostgreSQL Specific: `generate_series`, `listen_notify`, `full_text_search`
  - DDL Features: `create_index_concurrently`, `drop_index_concurrently`
- [x] 每个枚举值都有清晰的文档注释
- [x] 代码格式化通过 `zig fmt`

**依赖**: 无

**输出**: `src/dialect/dialect.zig` 更新

---

### Task 1.2: 更新 supports() 函数实现
**描述**: 更新 `Dialect.supports()` 函数，为所有新增特性添加明确分支。

**验收标准**:
- [x] 所有 Feature 枚举值都有对应的 true/false 分支
- [x] PostgreSQL 支持的特性返回 `true`
- [x] PostgreSQL 不支持的特性（如 `insert_ignore`, `output_clause`）返回 `false`
- [x] 不使用 else 分支，确保穷尽性检查
- [x] 通过 `zig test src/dialect/dialect.zig` 所有测试 (27/27)

**依赖**: Task 1.1

**输出**: `src/dialect/dialect.zig` 更新

---

### Task 1.3: 添加便捷特性检测函数
**描述**: 为常用特性添加便捷检测函数（如 `supportsFullTextSearch()`, `supportsUUID()`）。

**验收标准**:
- [x] 实现以下便捷函数：
  - `supportsFullTextSearch()`
  - `supportsUUID()`
  - `supportsGenerateSeries()`
  - `supportsListenNotify()`
- [x] 每个函数内部调用 `supports()` 函数
- [x] 添加对应的单元测试
- [x] 所有测试通过

**依赖**: Task 1.2

**输出**: `src/dialect/dialect.zig` 更新

---

## Phase 2: Comptime 方言分派 (2-3 天)

### Task 2.1: 实现 dialectDispatch() 函数
**描述**: 实现编译时方言分派函数，不支持的特性触发 `@compileError`。

**验收标准**:
- [x] 实现 `dialectDispatch()` 函数签名：
  ```zig
  pub fn dialectDispatch(
      comptime dialect: Dialect,
      comptime feature: Feature,
      comptime callback: anytype,
  ) @TypeOf(callback())
  ```
- [x] 支持的特性调用 callback 并返回结果
- [ ] 不支持的特性触发 `@compileError`，包含方言名和特性名
- [x] 添加成功场景的单元测试
- [ ] 手动验证编译错误场景（文档注释中说明）

**依赖**: Task 1.2

**输出**: `src/dialect/dialect.zig` 更新

---

### Task 2.2: 添加 dialectDispatch 类型安全测试
**描述**: 验证 dialectDispatch 的类型推导和类型安全性。

**验收标准**:
- [x] 测试不同返回类型的 callback（`[]const u8`, `bool`, `usize`）
- [x] 验证编译器正确推导返回类型
- [x] 添加测试文档说明类型不匹配的编译错误示例
- [x] 所有测试通过

**依赖**: Task 2.1

**输出**: `src/dialect/dialect.zig` 更新

---

### Task 2.3: 创建 dialectDispatch 使用示例
**描述**: 在测试和文档中提供清晰的 dialectDispatch 使用示例。

**验收标准**:
- [x] 添加至少 3 个不同场景的示例：
  - RETURNING 子句生成
  - LIMIT/OFFSET 子句生成
  - UPSERT 子句生成
- [x] 示例代码可编译并通过测试
- [x] 更新 `src/dialect/dialect.zig` 的模块级文档注释

**依赖**: Task 2.1

**输出**: `src/dialect/dialect.zig` 更新

---

## Phase 3: SQL 生成工具增强 (2 天)

### Task 3.1: 增强 limitClause() 函数
**描述**: 确保 `limitClause()` 完整支持 PostgreSQL 的 LIMIT/OFFSET 语法。

**验收标准**:
- [x] 支持 LIMIT only: `limitClause(10, null)` → `" LIMIT 10"`
- [x] 支持 OFFSET only: `limitClause(null, 5)` → `" OFFSET 5"`
- [x] 支持 LIMIT + OFFSET: `limitClause(10, 5)` → `" LIMIT 10 OFFSET 5"`
- [x] 支持空子句: `limitClause(null, null)` → `""`
- [x] 添加完整的 comptime 测试覆盖
- [x] 更新函数文档注释

**依赖**: 无

**输出**: `src/dialect/dialect.zig` 更新

---

### Task 3.2: 添加其他 SQL 生成工具
**描述**: 为常用 SQL 模式添加 comptime 生成函数。

**验收标准**:
- [x] 实现 `autoIncrementClause()` - 返回 `"SERIAL"`
- [x] 实现 `currentTimestamp()` - 返回 `"CURRENT_TIMESTAMP"`
- [x] 实现 `upsertClause()` - 返回 `"ON CONFLICT"`
- [x] 每个函数都有 comptime 测试
- [x] 所有测试通过

**依赖**: 无

**输出**: `src/dialect/dialect.zig` 更新

---

### Task 3.3: 验证 SQL 工具函数的 SQL 注入防护
**描述**: 确保 `sql.zig` 中的转义函数正确防止 SQL 注入。

**验收标准**:
- [x] 测试 `escapeIdentifier()` 正确转义双引号（双写）
- [x] 测试 `escapeString()` 正确转义单引号、特殊字符
- [x] 测试恶意 SQL 注入尝试（如 `' OR '1'='1`）
- [x] 添加模糊测试（fuzz testing）案例（可选）
- [x] 所有测试通过

**依赖**: 无

**输出**: `src/dialect/sql.zig` 测试更新

---

## Phase 4: 测试覆盖完善 (2-3 天)

### Task 4.1: 添加完整的 comptime 特性测试
**描述**: 确保所有 Feature 枚举值都有对应的 `supports()` 测试。

**验收标准**:
- [x] 实现测试遍历所有 Feature 枚举值
- [x] 验证每个特性的 `supports()` 返回值符合预期
- [x] 测试编译时求值（在 comptime 块中调用）
- [x] 所有测试通过

**依赖**: Task 1.2

**输出**: `src/dialect/dialect.zig` 测试更新

---

### Task 4.2: 添加零运行时开销验证测试
**描述**: 验证所有 comptime 函数不产生运行时代码。

**验收标准**:
- [x] 测试 `placeholder()`, `quoteIdentifier()`, `limitClause()` 等在 comptime 块中调用
- [x] 验证不产生堆分配（通过 testing.allocator）
- [x] 添加死代码消除测试（条件分支优化）
- [x] 文档说明如何手动验证编译器输出

**依赖**: Task 2.1, Task 3.1

**输出**: `src/dialect/dialect.zig` 测试更新

---

### Task 4.3: 添加类型安全测试
**描述**: 验证方言系统的编译时类型检查。

**验收标准**:
- [x] 测试 comptime 参数强制（运行时值触发编译错误）
- [x] 测试 Feature 枚举 switch 穷尽性检查
- [x] 测试 dialectDispatch 返回类型推导
- [x] 文档说明编译错误示例（无法作为测试）

**依赖**: Task 2.2

**输出**: `src/dialect/dialect.zig` 测试更新

---

### Task 4.4: 添加集成测试
**描述**: 验证方言系统与查询构建器的集成。

**验收标准**:
- [x] 测试查询构建器使用 `placeholder()` 生成占位符
- [x] 测试查询构建器使用 `quoteIdentifier()` 引用标识符
- [x] 测试查询构建器使用 `limitClause()` 生成 LIMIT/OFFSET
- [x] 测试查询构建器使用 `dialectDispatch()` 条件生成 RETURNING
- [x] 所有测试通过

**依赖**: Task 2.1, Task 3.1

**输出**: `src/query/query.zig` 测试更新（如果需要）

---

## Phase 5: 文档和示例 (1-2 天)

### Task 5.1: 更新模块级文档注释
**描述**: 更新 `src/dialect/dialect.zig` 和 `src/dialect/sql.zig` 的模块级文档。

**验收标准**:
- [x] 模块头部注释清晰说明方言系统的目的和用法
- [x] 列举所有主要功能（特性检测、SQL 生成、方言分派）
- [x] 提供简洁的使用示例
- [x] 说明 comptime vs 运行时的区别

**依赖**: 所有 Phase 1-4 任务

**输出**: `src/dialect/dialect.zig`, `src/dialect/sql.zig` 文档更新

---

### Task 5.2: 创建完整的使用示例
**描述**: 创建展示所有方言特性的综合示例代码。

**验收标准**:
- [x] 示例展示特性检测（`supports()`, `supportsReturning()`）
- [x] 示例展示 SQL 生成（`placeholder()`, `quoteIdentifier()`, `limitClause()`）
- [x] 示例展示方言分派（`dialectDispatch()`）
- [x] 示例展示与查询构建器集成
- [x] 示例代码可编译并通过测试
- [x] 添加到 `examples/` 目录或测试文档中

**依赖**: Task 5.1

**输出**: 新增示例文件或测试文档

---

### Task 5.3: 更新功能规格文档
**描述**: 更新 `docs/functional_spec.md` 的 2.1.4 节，反映实际实现。

**验收标准**:
- [x] 明确说明 ZORM 专注于 PostgreSQL
- [x] 更新 Feature 枚举列表
- [x] 更新示例代码与实际实现一致
- [x] 说明设计决策（为何不支持多方言）

**依赖**: 所有 Phase 1-4 任务

**输出**: `docs/functional_spec.md` 更新

---

## 验证和发布 (1 天)

### Task 6.1: 运行完整测试套件
**描述**: 确保所有测试通过，无回归问题。

**验收标准**:
- [x] 运行 `zig build test` 通过所有测试
- [x] 运行 `zig build` 构建成功
- [x] 运行 `zig fmt --check src/` 代码格式正确
- [ ] 无内存泄漏（通过 testing.allocator 验证）

**依赖**: 所有 Phase 1-5 任务

**输出**: 测试报告

---

### Task 6.2: 性能基准测试
**描述**: 验证 comptime 优化的零运行时开销。

**验收标准**:
- [ ] 对比 comptime vs 运行时占位符生成的性能
- [x] 验证编译时间在可接受范围内（< 5s 增量）
- [x] 验证生成的二进制文件大小无显著增长
- [x] 文档记录基准测试结果

**依赖**: Task 6.1

**输出**: 基准测试报告

---

### Task 6.3: OpenSpec 验证
**描述**: 运行 OpenSpec 验证确保提案符合规范。

**验收标准**:
- [x] 运行 `openspec validate enhance-postgresql-dialect --strict` 通过
- [x] 所有规格需求有对应的实现
- [x] 所有场景有对应的测试覆盖
- [ ] 任务列表完整且可验证

**依赖**: 所有任务

**输出**: OpenSpec 验证报告

---

## 任务依赖图

```
Phase 1: Feature 枚举扩展
├─ Task 1.1: 扩展 Feature 枚举
├─ Task 1.2: 更新 supports() ◄─ 依赖 1.1
└─ Task 1.3: 添加便捷函数 ◄─ 依赖 1.2

Phase 2: Comptime 方言分派
├─ Task 2.1: 实现 dialectDispatch ◄─ 依赖 1.2
├─ Task 2.2: 类型安全测试 ◄─ 依赖 2.1
└─ Task 2.3: 使用示例 ◄─ 依赖 2.1

Phase 3: SQL 生成工具
├─ Task 3.1: 增强 limitClause
├─ Task 3.2: 添加其他工具
└─ Task 3.3: SQL 注入防护测试

Phase 4: 测试覆盖
├─ Task 4.1: Comptime 特性测试 ◄─ 依赖 1.2
├─ Task 4.2: 零开销验证 ◄─ 依赖 2.1, 3.1
├─ Task 4.3: 类型安全测试 ◄─ 依赖 2.2
└─ Task 4.4: 集成测试 ◄─ 依赖 2.1, 3.1

Phase 5: 文档和示例
├─ Task 5.1: 模块文档 ◄─ 依赖所有前置任务
├─ Task 5.2: 使用示例 ◄─ 依赖 5.1
└─ Task 5.3: 规格文档更新 ◄─ 依赖所有前置任务

验证和发布
├─ Task 6.1: 测试套件 ◄─ 依赖所有前置任务
├─ Task 6.2: 性能基准 ◄─ 依赖 6.1
└─ Task 6.3: OpenSpec 验证 ◄─ 依赖所有任务
```

## 并行化建议

可以并行执行的任务组：
- **Group A**: Task 1.1 → 1.2 → 1.3 （顺序）
- **Group B**: Task 3.1, 3.2, 3.3 （并行）
- **Group C**: Task 2.1 依赖 1.2 完成后开始
- **Group D**: Task 4.1-4.4 依赖各自的前置任务，可部分并行

## 总时长估计
- **最快路径**: 7-9 天（并行执行所有可并行任务）
- **保守估计**: 10-14 天（考虑测试调试和文档编写）
- **团队规模**: 1-2 人
