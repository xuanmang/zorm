# Tasks: Implement CREATE TABLE Query Builder API

本文档将实现分解为小的、可验证的工作项，每个任务都能提供用户可见的进展。

## Task 1: 验证类型映射系统 (Type Mapping Verification)

**目标**: 确保所有 Zig 类型到 PostgreSQL 类型的映射符合 PRD 规范

**验收标准**:
- [x] 检查 `src/schema/reflection.zig` 中的类型映射逻辑
- [x] 验证整数类型映射（i8~i64, u8~u64）
- [x] 验证浮点类型映射（f32, f64）
- [x] 验证布尔和文本类型映射
- [x] 如有缺失或错误，修复类型映射代码

**验证方式**:
```bash
# 编译测试
zig build test --summary all
```

**依赖**: 无

**预估时间**: 2 小时

---

## Task 2: 编写类型映射单元测试 (Type Mapping Unit Tests)

**目标**: 为所有 Zig 类型编写单元测试，验证生成的 SQL 类型正确

**验收标准**:
- [x] 测试所有整数类型（i8, i16, i32, i64, u8, u16, u32, u64）
- [x] 测试浮点类型（f32, f64）
- [x] 测试布尔类型
- [x] 测试文本类型（[]const u8）
- [x] 测试可选类型（?i64, ?[]const u8 等）
- [x] 所有测试通过，无内存泄漏

**测试文件**: `src/query/query.zig`（在现有测试后添加）

**验证方式**:
```bash
zig build test --summary all | grep "CreateTableQuery: 类型映射"
```

**依赖**: Task 1

**预估时间**: 3 小时

---

## Task 3: 验证主键检测逻辑 (Primary Key Detection Verification)

**目标**: 确保主键自动检测逻辑符合 PRD 规范

**验收标准**:
- [x] 检查 `src/schema/reflection.zig` 中的主键检测逻辑
- [x] 验证字段名为 `id` 时自动设置主键
- [x] 验证主键字段自动添加 NOT NULL 约束
- [x] 如有缺失或错误，修复主键检测代码

**验证方式**:
```bash
# 代码审查 + 编译测试
rg "primary_key" src/schema/reflection.zig
zig build test
```

**依赖**: 无

**预估时间**: 1 小时

---

## Task 4: 编写主键检测单元测试 (Primary Key Detection Unit Tests)

**目标**: 为主键检测逻辑编写完整测试

**验收标准**:
- [x] 测试 `id` 字段自动设置为主键
- [x] 测试主键字段自动添加 NOT NULL
- [x] 测试非 `id` 字段不自动设置主键
- [x] 测试无主键的表生成正确 SQL
- [x] 所有测试通过

**测试文件**: `src/query/query.zig`

**验证方式**:
```bash
zig build test --summary all | grep "CreateTableQuery: 主键"
```

**依赖**: Task 3

**预估时间**: 2 小时

---

## Task 5: 验证可选类型处理逻辑 (Optional Type Handling Verification)

**目标**: 确保可选类型（?T）正确处理 NULL 约束

**验收标准**:
- [x] 检查 `src/schema/reflection.zig` 中的可选类型处理
- [x] 验证 `?T` 字段不添加 NOT NULL 约束
- [x] 验证非可选字段添加 NOT NULL 约束
- [x] 如有缺失或错误，修复可选类型处理代码

**验证方式**:
```bash
# 代码审查 + 编译测试
rg "nullable" src/schema/reflection.zig
zig build test
```

**依赖**: 无

**预估时间**: 1 小时

---

## Task 6: 编写可选类型处理单元测试 (Optional Type Handling Unit Tests)

**目标**: 为可选类型处理编写完整测试

**验收标准**:
- [x] 测试 `?i64`, `?u32` 等可选数值类型
- [x] 测试 `?[]const u8` 可选文本类型
- [x] 测试 `?bool` 可选布尔类型
- [x] 测试混合可选和非可选字段的结构体
- [x] 验证生成的 SQL 中 NULL 约束正确
- [x] 所有测试通过

**测试文件**: `src/query/query.zig`

**验证方式**:
```bash
zig build test --summary all | grep "CreateTableQuery: 可选类型"
```

**依赖**: Task 5

**预估时间**: 2 小时

---

## Task 7: 验证 ifNotExists 功能 (IF NOT EXISTS Verification)

**目标**: 确保 ifNotExists() 方法正确生成 IF NOT EXISTS 子句

**验收标准**:
- [x] 调用 `ifNotExists()` 后生成包含 `IF NOT EXISTS` 的 SQL
- [x] 不调用 `ifNotExists()` 时不包含 `IF NOT EXISTS`
- [x] 支持链式调用（`query.ifNotExists().exec()`）
- [x] 现有测试通过

**测试文件**: `src/query/query.zig`（已有测试 "CreateTableQuery: IF NOT EXISTS"）

**验证方式**:
```bash
zig build test --summary all | grep "IF NOT EXISTS"
```

**依赖**: 无

**预估时间**: 30 分钟

---

## Task 8: 编写完整工作流集成测试 (End-to-End Integration Tests)

**目标**: 编写完整的工作流测试，验证从结构体定义到 DDL 执行的全流程

**验收标准**:
- [x] 测试 PRD 示例代码可编译并生成正确 SQL
- [x] 测试完整的 CREATE TABLE 流程（init → ifNotExists → exec）
- [x] 测试复杂结构体（多种类型、可选字段、主键）
- [x] 验证生成的 SQL 与预期完全一致
- [x] 所有测试通过，无内存泄漏

**测试文件**: `src/query/query.zig`

**验证方式**:
```bash
zig build test --summary all | grep "CreateTableQuery: 完整工作流"
```

**依赖**: Tasks 1-7

**预估时间**: 3 小时

---

## Task 9: 完善 API 文档和注释 (API Documentation and Comments)

**目标**: 确保所有公共 API 都有完整的文档注释

**验收标准**:
- [x] `CreateTableQuery` 结构体有完整文档
- [x] `init()` 方法有文档、参数说明、示例
- [x] `ifNotExists()` 方法有文档和示例
- [x] `exec()` 方法有文档、错误说明、示例
- [x] `column()` 方法有文档和示例（手动模式）
- [x] 文档中的所有示例代码可编译

**验证方式**:
```bash
# 检查文档覆盖率
rg "pub fn" src/query/query.zig | grep -c "CreateTableQuery"
rg "///" src/query/query.zig | grep -c "CreateTableQuery"
```

**依赖**: Tasks 1-8

**预估时间**: 2 小时

---

## Task 10: 创建示例程序 (Example Program)

**目标**: 创建 `examples/schema.zig` 示例程序，演示完整使用场景

**验收标准**:
- [x] 文件 `examples/schema.zig` 存在
- [x] 示例包含结构体定义
- [x] 示例包含 CREATE TABLE 调用
- [x] 示例包含 ifNotExists 使用
- [x] 示例包含详细注释说明每个步骤
- [x] 示例可编译并运行
- [x] 在 `build.zig` 中添加 `run-example-schema` 目标

**验证方式**:
```bash
zig build run-example-schema
```

**依赖**: Tasks 1-9

**预估时间**: 2 小时

---

## Task 11: 验证测试覆盖率 (Test Coverage Verification)

**目标**: 确保单元测试覆盖率达到 80%+

**验收标准**:
- [x] 运行所有测试并收集覆盖率数据
- [x] CREATE TABLE 相关代码覆盖率 ≥ 80%
- [x] 所有测试通过
- [x] 无内存泄漏

**验证方式**:
```bash
zig build test --summary all
# 检查测试通过率
```

**依赖**: Tasks 1-10

**预估时间**: 1 小时

---

## Task 12: 运行 OpenSpec 验证 (OpenSpec Validation)

**目标**: 确保提案符合 OpenSpec 规范

**验收标准**:
- [x] 运行 `openspec validate implement-create-table-query-api --strict`
- [x] 所有验证检查通过
- [x] 无错误或警告

**验证方式**:
```bash
openspec validate implement-create-table-query-api --strict
```

**依赖**: Tasks 1-11

**预估时间**: 30 分钟

---

## 任务总结

| 任务 | 预估时间 | 依赖 | 可并行 |
|------|---------|------|--------|
| Task 1: 验证类型映射系统 | 2h | 无 | ✅ |
| Task 2: 编写类型映射单元测试 | 3h | Task 1 | - |
| Task 3: 验证主键检测逻辑 | 1h | 无 | ✅ |
| Task 4: 编写主键检测单元测试 | 2h | Task 3 | - |
| Task 5: 验证可选类型处理逻辑 | 1h | 无 | ✅ |
| Task 6: 编写可选类型处理单元测试 | 2h | Task 5 | - |
| Task 7: 验证 ifNotExists 功能 | 0.5h | 无 | ✅ |
| Task 8: 编写完整工作流集成测试 | 3h | Tasks 1-7 | - |
| Task 9: 完善 API 文档和注释 | 2h | Tasks 1-8 | - |
| Task 10: 创建示例程序 | 2h | Tasks 1-9 | - |
| Task 11: 验证测试覆盖率 | 1h | Tasks 1-10 | - |
| Task 12: 运行 OpenSpec 验证 | 0.5h | Tasks 1-11 | - |

**总预估时间**: 20 小时（约 2.5 个工作日）

**关键路径**: Task 1 → Task 2 → Task 8 → Task 9 → Task 10 → Task 11 → Task 12

**可并行执行**: Tasks 1, 3, 5, 7 可同时开始（验证现有实现）
