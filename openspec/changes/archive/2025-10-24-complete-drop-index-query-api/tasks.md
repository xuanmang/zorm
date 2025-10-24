# Tasks for complete-drop-index-query-api

## Phase 1: API 统一和完善

### Task 1.1: 分析和确认 API 设计
**Goal**: 确定统一的 DropIndexQuery API 设计,确保与 CREATE INDEX 和 DROP TABLE 一致

**Actions**:
- 比较 `src/query/query.zig` 和 `src/schema/schema.zig` 中的 DropIndexQuery 实现
- 对比 CreateIndexQuery 和 DropTableQuery 的 API 模式
- 确定最终的统一 API 设计(字段、方法、行为)
- 文档化设计决策

**Validation**:
- [x] 设计文档完成,列出所有方法和字段
- [x] 与 CREATE INDEX 和 DROP TABLE 的 API 对称性验证通过
- [x] 团队 review 通过

**Dependencies**: None

---

### Task 1.2: 在 src/query/query.zig 中添加 restrict() 方法
**Goal**: 为 DropIndexQuery 添加 `restrict()` 方法,支持 RESTRICT 选项

**Actions**:
- 在 DropIndexQuery 结构体中添加 `restrict_flag: bool` 字段
- 实现 `restrict()` 方法,设置 restrict_flag 为 true
- 在 `build()` 方法中处理 RESTRICT 关键字生成
- 确保方法返回 `*Self` 支持链式调用

**Validation**:
- [x] restrict() 方法实现完成
- [x] 单元测试验证 RESTRICT 关键字生成
- [x] 链式调用测试通过
- [x] 代码编译无警告

**Dependencies**: Task 1.1

---

### Task 1.3: 实现 CASCADE 和 RESTRICT 互斥逻辑
**Goal**: 确保 CASCADE 和 RESTRICT 不能同时存在,后调用的覆盖前面的

**Actions**:
- 修改 `cascade()` 方法:设置 cascade_flag 为 true 时,同时设置 restrict_flag 为 false
- 修改 `restrict()` 方法:设置 restrict_flag 为 true 时,同时设置 cascade_flag 为 false
- 在 `build()` 方法中验证逻辑:CASCADE 和 RESTRICT 不会同时出现在 SQL 中
- 参考 DROP TABLE 的实现模式

**Validation**:
- [x] 互斥逻辑测试通过(先 cascade 后 restrict,反之亦然)
- [x] 生成的 SQL 验证正确(只包含一个选项或都不包含)
- [x] 所有测试用例覆盖互斥场景

**Dependencies**: Task 1.2

---

### Task 1.4: 统一 src/schema/schema.zig 中的实现
**Goal**: 确保 src/schema/schema.zig 中的 DropIndexQuery 与 src/query/query.zig 保持一致

**Actions**:
- 检查 src/schema/schema.zig 版本是否已有 restrict() 方法
- 如果没有,添加 restrict() 方法和互斥逻辑
- 确保两个文件中的 API 签名完全一致
- 同步文档注释

**Validation**:
- [x] 两个版本的 API 完全一致
- [x] 交叉验证测试通过(相同输入产生相同 SQL)
- [x] 代码审查通过

**Dependencies**: Task 1.3

---

## Phase 2: 测试覆盖

### Task 2.1: 创建 drop_index_test.zig 单元测试文件
**Goal**: 创建专门的 DROP INDEX 单元测试文件,覆盖所有 API 方法

**Actions**:
- 在 `tests/` 目录创建 `drop_index_test.zig`
- 设置测试框架和测试 fixtures
- 创建测试用的 User 结构体定义
- 添加基本的测试辅助函数

**Validation**:
- [x] 测试文件创建完成
- [x] 测试框架运行正常
- [x] `zig build test` 包含新文件

**Dependencies**: None (可与 Phase 1 并行)

---

### Task 2.2: 编写核心方法单元测试
**Goal**: 为所有核心方法编写单元测试

**Actions**:
- 测试 `newDropIndex()` 工厂方法
- 测试 `.index()` 方法(设置索引名称)
- 测试 `.ifExists()` 方法(IF EXISTS 子句)
- 测试 `.cascade()` 方法(CASCADE 选项)
- 测试 `.restrict()` 方法(RESTRICT 选项)
- 测试 `.build()` 方法(SQL 生成)
- 测试 `.deinit()` 方法(内存清理)

**Validation**:
- [x] 每个方法至少有 2 个测试用例
- [x] 覆盖正常场景和边界条件
- [x] 所有测试通过
- [x] 使用 std.testing.allocator 检测内存泄漏

**Dependencies**: Task 2.1, Task 1.4

---

### Task 2.3: 编写互斥逻辑测试
**Goal**: 验证 CASCADE 和 RESTRICT 互斥行为

**Actions**:
- 测试先 cascade 后 restrict 的场景
- 测试先 restrict 后 cascade 的场景
- 测试默认行为(两者都不设置)
- 验证生成的 SQL 中只包含一个选项

**Validation**:
- [x] 所有互斥场景测试通过
- [x] SQL 生成验证正确
- [x] 覆盖所有可能的调用顺序

**Dependencies**: Task 2.2, Task 1.3

---

### Task 2.4: 编写链式调用测试
**Goal**: 验证 Fluent Interface 模式正确工作

**Actions**:
- 测试完整的链式调用场景
- 测试不同方法调用顺序产生相同结果
- 测试链式调用的可读性示例
- 验证所有方法都返回 *Self

**Validation**:
- [x] 链式调用测试通过
- [x] 方法顺序测试通过
- [x] 代码示例清晰易读

**Dependencies**: Task 2.2

---

### Task 2.5: 编写错误处理测试
**Goal**: 验证所有错误场景正确处理

**Actions**:
- 测试缺少索引名称时的错误(IndexNameRequired)
- 测试内存分配失败场景
- 测试数据库执行错误(索引不存在且无 IF EXISTS)
- 验证错误消息清晰明确

**Validation**:
- [x] 所有错误场景测试通过
- [x] 错误消息包含足够上下文
- [x] 错误类型正确

**Dependencies**: Task 2.2

---

### Task 2.6: 编写 PRD 示例代码验证测试
**Goal**: 确保 PRD AC3.5.6 中的示例代码可编译并正确运行

**Actions**:
- 将 PRD 示例代码转换为测试用例
- 验证生成的 SQL 与 PRD 注释一致
- 验证所有操作成功执行
- 添加文档注释说明这是 PRD 验证测试

**Validation**:
- [x] PRD 示例代码测试通过
- [x] 生成的 SQL 与 PRD 完全一致
- [x] 测试文档清晰

**Dependencies**: Task 2.2

---

### Task 2.7: 编写集成测试
**Goal**: 针对真实 PostgreSQL 数据库验证 DROP INDEX 功能

**Actions**:
- 创建集成测试文件 `tests/integration/drop_index_integration_test.zig`
- 设置真实 PostgreSQL 连接
- 测试完整的索引创建和删除流程
- 测试 IF EXISTS 在真实数据库中的行为
- 测试 CASCADE/RESTRICT 在真实数据库中的行为(如果有依赖对象场景)

**Validation**:
- [ ] 集成测试连接到真实 PostgreSQL
- [ ] 所有 DROP INDEX 操作成功执行
- [ ] IF EXISTS、CASCADE、RESTRICT 验证通过
- [ ] 测试清理正确(不留残留数据)

**Dependencies**: Task 2.6, Phase 1 完成

---

## Phase 3: 文档和示例

### Task 3.1: 完善 API 文档注释
**Goal**: 为所有公共 API 添加完整的文档注释

**Actions**:
- 为 DropIndexQuery 结构体添加文档注释
- 为所有公共方法添加文档注释(参数、返回值、错误、示例)
- 说明 CASCADE 和 RESTRICT 的应用场景
- 说明 PostgreSQL DROP INDEX 的特性和限制

**Validation**:
- [x] 所有公共 API 都有文档注释
- [x] 文档包含参数说明、返回值、错误类型
- [x] 文档包含使用示例
- [x] `zig build docs` 生成完整文档

**Dependencies**: Phase 1 完成

---

### Task 3.2: 创建使用示例
**Goal**: 提供清晰的 DROP INDEX 使用示例

**Actions**:
- 创建基本 DROP INDEX 示例
- 创建 IF EXISTS 使用示例
- 创建 CASCADE/RESTRICT 使用示例
- 创建完整的索引生命周期示例(创建 → 使用 → 删除)

**Validation**:
- [ ] 所有示例可编译并运行
- [ ] 示例覆盖常见使用场景
- [ ] 示例代码清晰易懂
- [ ] 示例包含注释说明

**Dependencies**: Task 3.1

---

### Task 3.3: 更新 README 和文档
**Goal**: 在项目文档中添加 DROP INDEX 相关内容

**Actions**:
- 在 README.md 中添加 DROP INDEX 示例
- 更新 Schema DDL 文档章节
- 添加 DROP INDEX 到 API 参考文档
- 确保文档与代码同步

**Validation**:
- [ ] README.md 更新完成
- [ ] API 参考文档完整
- [ ] 文档审查通过

**Dependencies**: Task 3.2

---

## Phase 4: 质量保证和验收

### Task 4.1: 运行完整测试套件
**Goal**: 确保所有测试通过,无内存泄漏

**Actions**:
- 运行 `zig build test` 执行所有单元测试
- 运行集成测试
- 使用 std.testing.allocator 检测内存泄漏
- 验证测试覆盖率达到 80%+

**Validation**:
- [ ] 所有单元测试通过
- [ ] 所有集成测试通过
- [ ] 无内存泄漏报告
- [ ] 测试覆盖率 >= 80%

**Dependencies**: Phase 2 完成

---

### Task 4.2: 代码审查和重构
**Goal**: 确保代码质量和一致性

**Actions**:
- 进行代码 review
- 检查命名一致性
- 优化代码结构
- 确保遵循项目编码规范

**Validation**:
- [ ] 代码审查通过
- [ ] 命名一致性检查通过
- [ ] 代码格式符合规范
- [ ] 无编译警告

**Dependencies**: Phase 1, Phase 2, Phase 3 完成

---

### Task 4.3: 性能验证
**Goal**: 确保 DROP INDEX 性能符合要求

**Actions**:
- 测试 SQL 生成性能(build 方法)
- 测试内存分配效率
- 与直接使用 PostgreSQL 协议对比性能
- 验证性能开销 < 5%

**Validation**:
- [ ] SQL 生成时间 < 1ms
- [ ] 内存分配次数最小化
- [ ] 性能开销 < 5%

**Dependencies**: Task 4.1

---

### Task 4.4: 最终验收测试
**Goal**: 验证所有 PRD 验收标准

**Actions**:
- 验证 AC3.5.1: db.newDropIndex(T) API
- 验证 AC3.5.2: .index(name) 方法
- 验证 AC3.5.3: .ifExists() 方法
- 验证 AC3.5.4: .cascade() 方法
- 验证 AC3.5.5: .exec() 方法
- 验证 AC3.5.6: PRD 示例代码可运行

**Validation**:
- [ ] 所有 AC 验收标准通过
- [ ] PRD 示例代码验证通过
- [ ] 功能完整,无缺失

**Dependencies**: Task 4.1, Task 4.2, Task 4.3

---

## Implementation Notes

**并行任务**:
- Phase 1 (API 完善) 和 Task 2.1 (测试文件创建) 可以并行
- Phase 3 (文档) 可以在 Phase 1 完成后开始,与 Phase 2 部分并行

**关键路径**:
1. Task 1.1 → Task 1.2 → Task 1.3 → Task 1.4 (API 统一)
2. Task 2.1 → Task 2.2 → Task 2.6 → Task 2.7 (测试覆盖)
3. Task 4.1 → Task 4.2 → Task 4.3 → Task 4.4 (质量保证)

**风险和依赖**:
- PostgreSQL 集成测试需要真实数据库连接
- CASCADE/RESTRICT 的真实场景测试可能需要创建复杂的依赖关系
- 性能测试需要基准测试基础设施

**预计工作量**:
- Phase 1: 4-6 小时
- Phase 2: 8-10 小时
- Phase 3: 3-4 小时
- Phase 4: 3-4 小时
- 总计: 18-24 小时
