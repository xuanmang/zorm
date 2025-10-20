# 实现任务清单

本文档定义实现 DB 实例管理功能的详细任务列表，每个任务都是原子的、可验证的工作项。

## 阶段 1：API 完善（P0 - 必需）

### 任务 1.1：实现 scanRows() 方法
**优先级**: P0
**预估时间**: 2 小时
**依赖**: 无

**描述**:
完善 `src/core/db.zig` 中的 `scanRows()` 方法，实现完整的行扫描逻辑。

**验收标准**:
- [x] `scanRows()` 可以正确遍历 Rows 迭代器
- [x] 为每行创建 T 类型实例
- [x] 使用 mapper.field_mapper 填充字段值
- [x] 将扫描的实例添加到 ArrayList
- [x] 处理扫描错误
- [ ] 添加单元测试验证功能(推迟到阶段 3)

**实现步骤**:
1. 引入 `mapper.field_mapper.scanRow` 函数
2. 实现 while 循环遍历 rows
3. 为每行调用 scanRow 创建 T 实例
4. 将实例添加到 dest ArrayList
5. 处理异常情况（错误、空结果等）
6. 编写单元测试

**测试用例**:
```zig
test "scanRows - 扫描多行数据" {
    const allocator = std.testing.allocator;

    var db = try DB(.postgresql).init(allocator, mock_conn, .{});
    defer db.deinit();

    var users = std.ArrayList(User).init(allocator);
    defer users.deinit();

    const result = try db.query("SELECT * FROM users", &[_]QueryArg{});
    defer result.close();

    try db.scanRows(User, &result.rows, &users);

    try std.testing.expectEqual(@as(usize, 3), users.items.len);
    try std.testing.expectEqualStrings("Alice", users.items[0].name);
}
```

---

### 任务 1.2：添加独立的 close() 方法
**优先级**: P1
**预估时间**: 1 小时
**依赖**: 无

**描述**:
添加独立的 `close()` 方法，允许调用者显式关闭连接而不销毁 DB 实例。

**验收标准**:
- [x] `close()` 方法可以独立调用
- [x] 关闭后 DB 实例标记为已关闭
- [x] 后续查询操作返回 ConnectionClosed 错误
- [x] `deinit()` 方法检查连接状态，避免重复关闭
- [ ] 添加单元测试(推迟到阶段 3)

**实现步骤**:
1. 添加 `closed: bool` 字段到 DB 结构体
2. 实现 `close()` 方法
3. 修改 `deinit()` 检查连接状态
4. 修改 `exec()` 和 `query()` 检查连接状态
5. 编写测试

**测试用例**:
```zig
test "close - 关闭连接后无法查询" {
    var db = try DB(.postgresql).init(allocator, conn, .{});
    defer db.deinit();

    try db.close();

    const result = db.query("SELECT 1", &[_]QueryArg{});
    try std.testing.expectError(error.ConnectionClosed, result);
}
```

---

### 任务 1.3：优化查询钩子管理
**优先级**: P1
**预估时间**: 1.5 小时
**依赖**: 无

**描述**:
评估并优化查询钩子管理机制，确保符合规格说明书要求。

**验收标准**:
- [x] 确认当前 `ArrayList(QueryHook)` 实现的优缺点
- [x] 与规格要求的 `ArrayList(*QueryHook)` 对比
- [x] 决定是否需要更改实现(决定保持当前实现)
- [x] 更新文档说明所有权语义(已在设计文档 ADR-003 中说明)
- [ ] 添加或更新测试(推迟到阶段 3)

**实现步骤**:
1. 分析当前实现的所有权语义
2. 评估性能和安全性影响
3. 如需更改，实现新的钩子管理
4. 更新文档
5. 更新测试

---

### 任务 1.4：确保 API 签名一致性
**优先级**: P0
**预估时间**: 1 小时
**依赖**: 任务 1.1, 1.2, 1.3

**描述**:
检查所有方法签名与功能规格说明书 2.1.1 节的一致性。

**验收标准**:
- [x] 所有方法名称与规格一致
- [x] 所有参数类型与规格一致(除了设计改进:query_hooks 使用值语义)
- [x] 所有返回类型与规格一致
- [x] 文档注释完整
- [x] 代码示例正确

**实现步骤**:
1. 逐条对比规格说明书
2. 修正不一致的地方
3. 更新文档
4. 验证示例代码

---

## 阶段 2：内存管理增强（P1 - 重要）

### 任务 2.1：完善 Arena 分配器使用模式
**优先级**: P1
**预估时间**: 2 小时
**依赖**: 无

**描述**:
添加 QueryContext 封装 Arena 分配器，简化临时内存管理。

**验收标准**:
- [ ] 定义 QueryContext 结构体
- [ ] 实现 init/deinit/allocator/reset 方法
- [ ] 提供使用示例
- [ ] 添加单元测试
- [ ] 更新文档

**实现步骤**:
1. 在适当的模块中定义 QueryContext
2. 实现所有方法
3. 编写使用示例
4. 添加测试
5. 更新文档

**示例代码**:
```zig
pub const QueryContext = struct {
    arena: std.heap.ArenaAllocator,
    base_allocator: Allocator,

    pub fn init(base_allocator: Allocator) QueryContext {
        return .{
            .arena = std.heap.ArenaAllocator.init(base_allocator),
            .base_allocator = base_allocator,
        };
    }

    pub fn deinit(self: *QueryContext) void {
        self.arena.deinit();
    }

    pub fn allocator(self: *QueryContext) Allocator {
        return self.arena.allocator();
    }

    pub fn reset(self: *QueryContext) void {
        _ = self.arena.reset(.retain_capacity);
    }
};
```

---

### 任务 2.2：增强内存泄漏检测机制
**优先级**: P1
**预估时间**: 2 小时
**依赖**: 无

**描述**:
为所有核心功能添加内存泄漏检测测试。

**验收标准**:
- [ ] 所有测试使用 testing.allocator
- [ ] 测试覆盖所有资源分配场景
- [ ] 包含负面测试（忘记 deinit 的情况）
- [ ] 所有测试通过
- [ ] 文档说明泄漏检测最佳实践

**实现步骤**:
1. 为每个公共 API 添加泄漏检测测试
2. 添加负面测试用例
3. 验证所有测试通过
4. 编写最佳实践文档

**测试用例**:
```zig
test "DB - 无内存泄漏" {
    const allocator = std.testing.allocator;

    var db = try DB(.postgresql).init(allocator, mock_conn, .{});
    defer db.deinit();

    var query = try db.newSelect(User);
    defer query.deinit();

    // testing.allocator 会在测试结束时验证无泄漏
}

test "查询构建器 - 忘记 deinit 会失败" {
    const allocator = std.testing.allocator;

    var db = try DB(.postgresql).init(allocator, mock_conn, .{});
    defer db.deinit();

    var query = try db.newSelect(User);
    // defer query.deinit(); // 忘记这行会导致测试失败
}
```

---

### 任务 2.3：添加资源清理最佳实践示例
**优先级**: P2
**预估时间**: 1.5 小时
**依赖**: 任务 2.1, 2.2

**描述**:
在文档和示例代码中展示资源清理的最佳实践。

**验收标准**:
- [ ] 提供完整的示例程序
- [ ] 展示 defer 使用模式
- [ ] 展示 errdefer 使用模式
- [ ] 展示 Arena 使用模式
- [ ] 文档清晰易懂

**实现步骤**:
1. 创建 `examples/memory_management.zig`
2. 编写多个场景示例
3. 添加详细注释
4. 验证示例可编译运行
5. 更新主文档

---

### 任务 2.4：优化内存分配策略
**优先级**: P2
**预估时间**: 2 小时
**依赖**: 任务 2.1

**描述**:
实现缓冲区复用和容量预分配优化。

**验收标准**:
- [ ] QueryBuilder 支持 reset() 保留容量
- [ ] 提供 allocWithCapacity() 辅助函数
- [ ] 添加性能基准测试
- [ ] 文档说明优化策略

**实现步骤**:
1. 为常用结构体添加 reset() 方法
2. 实现预分配辅助函数
3. 编写性能基准测试
4. 对比优化前后性能
5. 更新文档

---

## 阶段 3：测试和文档（P0 - 必需）

### 任务 3.1：编写完整的单元测试
**优先级**: P0
**预估时间**: 4 小时
**依赖**: 阶段 1 完成

**描述**:
为所有 DB 实例管理功能编写完整的单元测试。

**验收标准**:
- [ ] DBStats 测试（记录、获取、原子性）
- [ ] DB 生命周期测试（init, deinit, clone）
- [ ] 查询执行测试（exec, query, 钩子）
- [ ] 错误处理测试（所有错误类型）
- [ ] 事务管理测试（begin, commit, rollback）
- [ ] 测试覆盖率 > 80%

**实现步骤**:
1. 创建 `tests/unit/db_instance_test.zig`
2. 为每个功能编写测试用例
3. 运行测试验证通过
4. 使用 kcov 或类似工具检查覆盖率
5. 补充缺失的测试

**测试分组**:
```zig
// DBStats 测试组
test "DBStats - 记录查询" { }
test "DBStats - 记录错误" { }
test "DBStats - 原子操作" { }

// DB 生命周期测试组
test "DB - init/deinit" { }
test "DB - clone" { }
test "DB - withQueryHook" { }

// 查询执行测试组
test "DB - exec 成功" { }
test "DB - exec 失败" { }
test "DB - query 成功" { }
test "DB - query 失败" { }
test "DB - 钩子调用顺序" { }

// 错误处理测试组
test "DB - ConnectionFailed" { }
test "DB - QueryTimeout" { }
test "DB - NoRows" { }
```

---

### 任务 3.2：编写集成测试
**优先级**: P0
**预估时间**: 3 小时
**依赖**: 任务 3.1

**描述**:
编写集成测试验证 DB 与数据库驱动的实际交互。

**验收标准**:
- [ ] 完整查询流程测试（连接 → 查询 → 扫描 → 关闭）
- [ ] 事务场景测试（提交、回滚、错误处理）
- [ ] 钩子集成测试（日志、性能监控）
- [ ] 所有测试通过
- [ ] 提供测试数据库设置说明

**实现步骤**:
1. 创建 `tests/integration/db_integration_test.zig`
2. 设置测试数据库环境
3. 编写端到端测试场景
4. 运行并验证测试
5. 编写环境设置文档

**测试场景**:
```zig
test "集成 - 完整查询流程" {
    // 连接数据库
    // 执行查询
    // 扫描结果
    // 验证数据
    // 关闭连接
}

test "集成 - 事务提交" {
    // 开启事务
    // 插入数据
    // 提交事务
    // 验证数据已保存
}

test "集成 - 事务回滚" {
    // 开启事务
    // 插入数据
    // 触发错误
    // 验证回滚
    // 验证数据未保存
}
```

---

### 任务 3.3：添加详细的 API 文档
**优先级**: P0
**预估时间**: 3 小时
**依赖**: 阶段 1, 2 完成

**描述**:
为所有公共 API 添加详细的文档注释和使用示例。

**验收标准**:
- [ ] 所有公共函数有文档注释
- [ ] 文档包含功能描述
- [ ] 文档包含参数说明
- [ ] 文档包含返回值说明
- [ ] 文档包含错误说明
- [ ] 文档包含使用示例
- [ ] 使用 Zig 标准文档格式

**实现步骤**:
1. 为每个公共 API 添加 `///` 文档注释
2. 添加 `## 参数`, `## 返回`, `## 错误`, `## 示例` 章节
3. 验证文档格式正确
4. 生成 HTML 文档预览
5. 修正格式问题

**文档模板**:
```zig
/// 创建数据库实例
///
/// ## 参数
/// - allocator: 内存分配器
/// - conn: 数据库连接
/// - options: 数据库配置选项
///
/// ## 返回
/// 返回新创建的 DB 实例指针,失败时返回错误
///
/// ## 错误
/// - error.OutOfMemory: 内存分配失败
/// - error.InvalidConfig: 配置选项无效
///
/// ## 示例
/// ```zig
/// const db = try DB(.postgresql).init(allocator, conn, .{});
/// defer db.deinit();
/// ```
pub fn init(...) !*Self { }
```

---

### 任务 3.4：提供丰富的使用示例
**优先级**: P0
**预估时间**: 2 小时
**依赖**: 任务 3.3

**描述**:
创建完整的示例程序展示各种使用场景。

**验收标准**:
- [ ] 基础查询示例
- [ ] 事务使用示例
- [ ] 钩子使用示例
- [ ] 错误处理示例
- [ ] 内存管理示例
- [ ] 所有示例可编译运行

**实现步骤**:
1. 创建 `examples/db_basic.zig`
2. 创建 `examples/db_transaction.zig`
3. 创建 `examples/db_hooks.zig`
4. 创建 `examples/db_error_handling.zig`
5. 创建 `examples/db_memory_management.zig`
6. 更新 `build.zig` 添加示例编译目标
7. 验证所有示例可运行

---

## 阶段 4：验证和完善（P0 - 必需）

### 任务 4.1：运行 OpenSpec 验证
**优先级**: P0
**预估时间**: 1 小时
**依赖**: 所有前置任务完成

**描述**:
使用 OpenSpec 工具验证变更提议的完整性和正确性。

**验收标准**:
- [ ] `openspec validate implement-db-instance-management --strict` 通过
- [ ] 所有规范增量格式正确
- [ ] 所有场景都有实现
- [ ] 所有依赖关系正确
- [ ] 任务清单完整

**实现步骤**:
1. 运行 `openspec validate` 命令
2. 修正所有验证错误
3. 重新运行验证直到通过
4. 提交变更提议

---

### 任务 4.2：代码审查和重构
**优先级**: P1
**预估时间**: 2 小时
**依赖**: 任务 4.1

**描述**:
审查所有代码，进行必要的重构和优化。

**验收标准**:
- [ ] 代码符合 Zig 惯例
- [ ] 无未使用的导入和变量
- [ ] 无重复代码
- [ ] 命名清晰一致
- [ ] 注释恰当
- [ ] 格式化正确（`zig fmt`）

**实现步骤**:
1. 运行 `zig fmt` 格式化代码
2. 运行静态分析工具
3. 审查代码质量
4. 重构改进
5. 再次运行测试验证

---

### 任务 4.3：性能基准测试
**优先级**: P2
**预估时间**: 2 小时
**依赖**: 任务 4.2

**描述**:
编写性能基准测试，验证实现满足性能要求。

**验收标准**:
- [ ] 批量插入基准测试
- [ ] 复杂查询基准测试
- [ ] 事务吞吐量基准测试
- [ ] 内存分配开销基准测试
- [ ] 基准结果文档化

**实现步骤**:
1. 创建 `benchmarks/db_bench.zig`
2. 实现各种基准测试
3. 运行基准测试收集数据
4. 分析结果
5. 记录性能指标

---

### 任务 4.4：更新项目文档
**优先级**: P1
**预估时间**: 1.5 小时
**依赖**: 所有任务完成

**描述**:
更新项目级别的文档，反映新实现的功能。

**验收标准**:
- [ ] 更新 README.md
- [ ] 更新 CHANGELOG.md
- [ ] 更新 API 参考文档
- [ ] 更新迁移指南（如有 API 变更）
- [ ] 更新贡献指南

**实现步骤**:
1. 更新 README 的功能列表
2. 在 CHANGELOG 添加版本记录
3. 生成并检查 API 文档
4. 编写迁移指南（如需）
5. 审查所有文档

---

## 任务依赖图

```
阶段 1（API 完善）
├── 任务 1.1: scanRows()
├── 任务 1.2: close()
├── 任务 1.3: 钩子优化
└── 任务 1.4: API 一致性 ──┐
                           │
阶段 2（内存管理）         │
├── 任务 2.1: Arena        │
├── 任务 2.2: 泄漏检测 ────┤
├── 任务 2.3: 最佳实践     │
└── 任务 2.4: 优化         │
                           │
阶段 3（测试和文档）       │
├── 任务 3.1: 单元测试 ────┤
├── 任务 3.2: 集成测试     │
├── 任务 3.3: API 文档 ────┤
└── 任务 3.4: 示例         │
                           │
阶段 4（验证和完善）       │
├── 任务 4.1: OpenSpec ────┘
├── 任务 4.2: 代码审查
├── 任务 4.3: 性能测试
└── 任务 4.4: 项目文档
```

## 总时间估算

- **阶段 1**: 5.5 小时
- **阶段 2**: 7.5 小时
- **阶段 3**: 12 小时
- **阶段 4**: 6.5 小时

**总计**: ~31.5 小时（约 4 个工作日）

## 并行化机会

可以并行执行的任务组：
- 阶段 1 的所有任务可以并行
- 阶段 2.1 和 2.2 可以并行
- 阶段 3.1 和 3.3 可以并行

## 风险缓解

- 每个任务完成后立即运行测试验证
- 保持小的、可回退的提交
- 及时同步代码，避免冲突
- 定期运行完整的测试套件
