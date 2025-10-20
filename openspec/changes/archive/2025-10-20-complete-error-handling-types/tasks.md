# Tasks: Complete Error Handling Types

## Overview
本任务列表用于实现功能规格说明书 2.1.3 中定义的错误处理类型别名，使 ZORM 错误处理系统完全符合规格要求。

## Task List

### ✅ Phase 1: 规格更新
- [ ] **T1.1**: 更新 `db-error-handling` 规格，添加类型别名需求
  - 添加 `QueryResult(T)` 类型别名需求
  - 添加 `VoidResult` 类型别名需求
  - 添加使用场景和示例
  - **验证**: `openspec show db-error-handling --type spec` 包含新需求
  - **依赖**: 无
  - **预估**: 15 分钟

### ✅ Phase 2: 核心实现
- [ ] **T2.1**: 在 `src/error.zig` 添加 `QueryResult(T)` 类型别名
  - 添加泛型类型函数 `pub fn QueryResult(comptime T: type) type`
  - 添加详细的文档注释说明用途和使用示例
  - 确保返回 `Error!T` 类型
  - **验证**: 编译通过，类型别名可用
  - **依赖**: 无
  - **预估**: 10 分钟

- [ ] **T2.2**: 在 `src/error.zig` 添加 `VoidResult` 类型别名
  - 添加常量 `pub const VoidResult = Error!void`
  - 添加详细的文档注释说明用途和使用示例
  - **验证**: 编译通过，类型别名可用
  - **依赖**: 无
  - **预估**: 5 分钟

### ✅ Phase 3: 测试实现
- [ ] **T3.1**: 添加 `QueryResult(T)` 类型别名测试
  - 测试 `QueryResult(T)` 与 `Error!T` 等价性
  - 测试成功情况返回正确值
  - 测试错误情况正确传播
  - 测试在函数签名中使用
  - **验证**: `zig build test` 通过所有测试
  - **依赖**: T2.1
  - **预估**: 15 分钟

- [ ] **T3.2**: 添加 `VoidResult` 类型别名测试
  - 测试 `VoidResult` 与 `Error!void` 等价性
  - 测试成功情况
  - 测试错误情况正确传播
  - 测试在函数签名中使用
  - **验证**: `zig build test` 通过所有测试
  - **依赖**: T2.2
  - **预估**: 10 分钟

- [ ] **T3.3**: 添加综合场景测试
  - 测试嵌套使用 `QueryResult(QueryResult(T))`
  - 测试与现有 `!T` 类型完全兼容
  - 测试在复杂函数签名中使用
  - **验证**: `zig build test` 通过所有测试
  - **依赖**: T3.1, T3.2
  - **预估**: 10 分钟

### ✅ Phase 4: 验证和文档
- [ ] **T4.1**: 运行完整测试套件
  - 执行 `zig build test` 确保所有测试通过
  - 执行 `zig build` 确保编译无错误
  - 检查测试覆盖率
  - **验证**: 构建和测试全部成功
  - **依赖**: T3.1, T3.2, T3.3
  - **预估**: 5 分钟

- [ ] **T4.2**: 验证 OpenSpec 规格
  - 执行 `openspec validate complete-error-handling-types --strict`
  - 解决所有验证错误
  - **验证**: OpenSpec 验证通过
  - **依赖**: T1.1, T2.1, T2.2
  - **预估**: 10 分钟

- [ ] **T4.3**: 格式化代码
  - 执行 `zig fmt src/error.zig` 格式化代码
  - 检查代码风格一致性
  - **验证**: 代码格式规范
  - **依赖**: T2.1, T2.2, T3.1, T3.2, T3.3
  - **预估**: 2 分钟

### ✅ Phase 5: 提交和归档
- [ ] **T5.1**: 提交代码变更
  - 使用 `git add` 添加修改的文件
  - 编写清晰的提交消息，引用 OpenSpec 变更 ID
  - 执行 `git commit` 提交变更
  - **验证**: 代码已提交到 Git
  - **依赖**: T4.1, T4.2, T4.3
  - **预估**: 5 分钟

- [ ] **T5.2**: 归档 OpenSpec 变更
  - 执行 `openspec archive complete-error-handling-types --yes`
  - 验证变更已移动到 archive 目录
  - 验证规格已创建或更新
  - **验证**: `openspec list` 不再显示此变更
  - **依赖**: T5.1
  - **预估**: 5 分钟

## Dependency Graph
```
T1.1 (规格更新)
  ↓
T2.1 (QueryResult 实现) ──→ T3.1 (QueryResult 测试)
  ↓                              ↓
T2.2 (VoidResult 实现) ──→ T3.2 (VoidResult 测试)
  ↓                              ↓
  └──────────→ T3.3 (综合测试) ←─┘
                  ↓
              T4.1 (完整测试)
                  ↓
              T4.2 (OpenSpec 验证)
                  ↓
              T4.3 (代码格式化)
                  ↓
              T5.1 (提交代码)
                  ↓
              T5.2 (归档变更)
```

## Parallel Execution
以下任务可以并行执行：
- **并行组 1**: T2.1 和 T2.2 可以同时实现（不同的代码位置）
- **并行组 2**: T3.1 和 T3.2 可以同时编写（不同的测试用例）

## Total Estimated Time
- **最短路径**: 约 60 分钟（并行执行）
- **最长路径**: 约 90 分钟（顺序执行）
- **推荐方式**: 并行执行并行组，约 70 分钟

## Notes
1. 所有任务都是小粒度的，可以独立验证
2. 每个任务都有明确的验证标准
3. 任务之间的依赖关系清晰
4. 支持部分并行执行提高效率

## Success Criteria
- ✅ 所有测试通过（`zig build test`）
- ✅ 编译无错误（`zig build`）
- ✅ OpenSpec 验证通过（`openspec validate --strict`）
- ✅ 代码格式规范（`zig fmt --check`）
- ✅ 功能规格 2.1.3 完全实现
- ✅ 代码已提交到 Git
- ✅ OpenSpec 变更已归档
