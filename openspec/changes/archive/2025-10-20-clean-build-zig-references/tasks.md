# Tasks: 清理 build.zig 中已删除的测试和示例引用

## Overview

本任务列表按照依赖关系排序，确保清理工作有序进行，每个任务都有明确的验收标准。

所有任务已完成 ✅

---

## Task 1: 移除测试辅助模块配置 ✅

**描述**：从 build.zig 中移除 test_helper 和 seed_data 模块的定义和所有引用

**文件**：build.zig

**操作**：
- 删除 test_helper_module 的定义（第 37-42 行）
- 删除 seed_data_module 的定义（第 44-51 行）
- 移除 unit_test_module 中对 test_helper 和 seed_data 的导入（第 218-219 行）

**验收**：
- `rg "test_helper" build.zig` 无结果
- `rg "seed_data" build.zig` 无结果
- `zig build` 无模块导入错误

**依赖**：无

---

## Task 2: 移除示例公共模块配置 ✅

**描述**：移除所有 examples/common 相关的模块定义

**文件**：build.zig

**操作**：
- 删除 examples_common_module 定义（第 54-60 行）
- 删除 models_module 定义（第 150-154 行）
- 移除所有对这些模块的导入引用

**验收**：
- `rg "examples_common" build.zig` 无结果
- `rg "common/db_config" build.zig` 无结果
- `rg "common/models" build.zig` 无结果

**依赖**：Task 1

---

## Task 3: 移除基础示例构建配置 ✅

**描述**：移除 basic.zig 示例的构建配置

**文件**：build.zig

**操作**：
- 删除 example_module 定义（第 63-69 行）
- 删除 example 可执行文件配置（第 71-78 行）
- 删除 run-basic 步骤配置（第 80-88 行）

**验收**：
- `rg "example_module" build.zig` 无结果（排除 examples_common_module）
- `rg "run-basic" build.zig` 无结果
- `zig build --list-steps` 不显示 run-basic 步骤

**依赖**：Task 2

---

## Task 4: 移除数据库初始化示例配置 ✅

**描述**：移除 setup_database 示例的构建和运行配置

**文件**：build.zig

**操作**：
- 删除 setup_module 定义（第 91-102 行）
- 删除 setup_exe 和 run-setup 步骤（第 104-111 行）

**验收**：
- `rg "setup_module" build.zig` 无结果
- `rg "run-setup" build.zig` 无结果
- `zig build --list-steps` 不显示 run-setup 步骤

**依赖**：Task 2

---

## Task 5: 移除动态示例运行配置 ✅

**描述**：移除 run-example 和 run-all-examples 步骤配置

**文件**：build.zig

**操作**：
- 删除 run_example_module 定义（第 117-129 行）
- 删除 run-example 步骤配置（第 131-138 行）
- 删除 all_examples 数组（第 144-148 行）
- 删除 run-all-examples 步骤配置（第 141-174 行）

**验收**：
- `rg "run-example" build.zig` 无结果（包括 run-all-examples）
- `rg "all_examples" build.zig` 无结果
- `zig build --list-steps` 不显示 run-example 和 run-all-examples 步骤

**依赖**：Task 2

---

## Task 6: 更新格式化路径配置 ✅

**描述**：更新 fmt 和 fmt-check 步骤，移除不存在的 examples 和 tests 路径

**文件**：build.zig

**操作**：
- 修改 fmt_check 的 paths 参数（第 178 行）：从 `&.{ "src", "examples", "build.zig" }` 改为 `&.{ "src", "build.zig" }`
- 修改 fmt 的 paths 参数（第 187 行）：同上修改

**验收**：
- `zig build fmt-check` 仅检查 src/ 和 build.zig
- `zig build fmt` 仅格式化 src/ 和 build.zig
- 命令执行无错误或警告

**依赖**：Task 5

---

## Task 7: 移除独立单元测试步骤 (db-unit, types, create-index) ✅

**描述**：移除 db_test、types_test、create_index_test 的配置

**文件**：build.zig

**操作**：
- 删除 db_unit_test_module 和相关步骤（第 230-249 行）
- 删除 types_test_module 和相关步骤（第 272-289 行）
- 删除 create_index_test_module 和相关步骤（第 292-309 行）
- 从主 test_step 中移除对这些步骤的 dependOn 调用

**验收**：
- `rg "test-db-unit|test-types|test-create-index" build.zig` 无结果
- `zig build --list-steps` 不显示这些测试步骤

**依赖**：Task 1

---

## Task 8: 移除连接池和其他单元测试步骤 ✅

**描述**：移除 pool_test、column_distinct_test、insert_query_test 的配置

**文件**：build.zig

**操作**：
- 删除 pool_test_module 和相关步骤（第 252-269 行）
- 删除 column_distinct_test_module 和相关步骤（第 312-329 行）
- 删除 insert_query_test_module 和相关步骤（第 332-349 行）
- 从主 test_step 中移除对这些步骤的 dependOn 调用

**验收**：
- `rg "test-pool|test-column-distinct|test-insert-query" build.zig` 无结果
- `zig build --list-steps` 不显示这些测试步骤

**依赖**：Task 1

---

## Task 9: 移除示例和集成测试步骤 ✅

**描述**：移除 examples_test、db_integration_test、infrastructure_test 的配置

**文件**：build.zig

**操作**：
- 删除 examples_test_module 和相关步骤（第 352-370 行）
- 删除 db_integration_test_module 和相关步骤（第 373-390 行）
- 删除 infrastructure_test_module 和相关步骤（第 393-412 行）
- 从主 test_step 中移除对这些步骤的 dependOn 调用

**验收**：
- `rg "test-examples|test-db-integration|test-infrastructure" build.zig` 无结果
- `zig build --list-steps` 不显示这些测试步骤

**依赖**：Task 1, Task 2

---

## Task 10: 清理 PostgreSQL 特定测试配置 ✅

**描述**：移除 enable_postgres 块中的所有测试配置，但保留块本身和 PostgreSQL 依赖

**文件**：build.zig

**操作**：
- 保留 enable_postgres 条件判断（第 415 行）
- 删除 postgres_test_module 和相关步骤（第 416-430 行）
- 删除 test-all 步骤配置（第 432-434 行）
- 删除 simple_pg_test_module 和相关步骤（第 437-454 行）
- 删除 minimal_test_module 和相关步骤（第 457-471 行）
- 删除 simple_test_module 和相关步骤（第 474-491 行）
- 删除 isolation_test_module 和相关步骤（第 494-508 行）
- 可以完全移除 enable_postgres 块，或保留为空块以便将来添加

**验收**：
- `rg "test-postgres|test-all|test-simple-pg|test-minimal|test-simple|test-isolation" build.zig` 无结果
- enable_postgres 选项仍然存在（第 11 行）
- PostgreSQL 依赖配置保留（第 19-22 行）

**依赖**：Task 1

---

## Task 11: 简化主测试步骤 ✅

**描述**：确保主 test 步骤仅运行保留的单元测试

**文件**：build.zig

**操作**：
- 检查 test_step 的 dependOn 调用，确保只有 run_unit_tests
- 移除所有对已删除测试的 dependOn 调用

**验收**：
- `zig build test` 仅运行 src/zorm.zig 的测试
- 无任何文件未找到错误

**依赖**：Task 7, Task 8, Task 9, Task 10

---

## Task 12: 验证构建系统完整性 ✅

**描述**：执行所有保留的构建命令，确保无错误

**文件**：无（验证任务）

**操作**：
- 执行 `zig build` 并验证成功
- 执行 `zig build test` 并验证成功
- 执行 `zig build fmt-check` 并验证成功
- 执行 `zig build docs` 并验证成功
- 执行 `zig build --list-steps` 并验证仅显示保留的步骤

**验收**：
- 所有命令成功执行，无错误或警告
- 构建步骤列表仅包含：test, fmt, fmt-check, docs

**依赖**：Task 1-11

---

## Task 13: 代码格式化 ✅

**描述**：格式化清理后的 build.zig 文件

**文件**：build.zig

**操作**：
- 执行 `zig build fmt` 格式化代码

**验收**：
- `zig build fmt-check` 无格式问题

**依赖**：Task 12

---

## Task 14: OpenSpec 验证 ✅

**描述**：验证提案符合 OpenSpec 规范

**文件**：openspec/changes/clean-build-zig-references/

**操作**：
- 执行 `openspec validate clean-build-zig-references --strict`

**验收**：
- 验证通过，无错误或警告

**依赖**：Task 13

---

## Summary

- **总任务数**：14
- **预计工时**：2-3 小时
- **风险**：低（纯粹的清理操作，不涉及功能变更）
- **可并行执行**：Task 3-5 可以并行；Task 7-10 可以并行
