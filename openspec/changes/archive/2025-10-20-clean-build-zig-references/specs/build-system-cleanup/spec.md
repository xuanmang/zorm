# Spec: 构建系统清理

## Overview

清理 build.zig 文件，移除所有对已删除测试和示例文件的引用，保持构建系统配置与实际代码结构一致。

## REMOVED Requirements

### Requirement: 测试辅助模块配置
**移除原因**：test_helper.zig 和 seed_data.zig 文件已删除

构建系统 MUST NOT 包含以下模块配置：
- test_helper_module 模块定义
- seed_data_module 模块定义
- 对这些模块的任何导入引用

#### Scenario: 移除测试辅助模块配置

**Given** build.zig 包含 test_helper 和 seed_data 模块配置
**When** 清理构建配置
**Then** 所有测试辅助模块定义和引用被完全移除

---

### Requirement: 示例公共模块配置
**移除原因**：examples/common/ 目录及其文件已删除

构建系统 MUST NOT 包含：
- examples_common_module 模块定义
- models_module 模块定义
- examples/common/db_config.zig 的任何引用
- examples/common/models.zig 的任何引用

#### Scenario: 移除示例公共模块

**Given** build.zig 包含示例公共模块配置
**When** 清理构建配置
**Then** 所有示例公共模块定义和引用被移除

---

### Requirement: 独立测试步骤
**移除原因**：对应的测试文件已删除

构建系统 MUST NOT 包含以下测试步骤：
- test-db-unit（tests/unit/db_test.zig）
- test-pool（tests/pool_test.zig）
- test-types（tests/unit/types_test.zig）
- test-create-index（tests/unit/create_index_test.zig）
- test-column-distinct（tests/column_distinct_test.zig）
- test-insert-query（tests/insert_query_test.zig）
- test-examples（examples/tests/setup_test.zig）
- test-db-integration（tests/db_integration_test.zig）
- test-infrastructure（tests/infrastructure_test.zig）
- test-postgres（tests/integration/postgres_test.zig）
- test-isolation（tests/integration/isolation_level_test.zig）
- test-minimal（minimal_test.zig）
- test-simple-pg（simple_pg_test.zig）
- test-simple（simple_test.zig）

#### Scenario: 移除所有独立测试步骤

**Given** build.zig 包含多个独立测试步骤配置
**When** 清理构建配置
**Then** 所有独立测试步骤的模块定义和步骤注册被移除

---

### Requirement: 示例构建配置
**移除原因**：所有示例文件已删除

构建系统 MUST NOT 包含：
- example_module（examples/basic.zig）
- setup_module（examples/00_setup_database.zig）
- run-example 步骤配置
- run-all-examples 步骤配置
- run-basic 步骤配置
- run-setup 步骤配置
- all_examples 数组定义

#### Scenario: 移除所有示例构建配置

**Given** build.zig 包含示例构建和运行配置
**When** 清理构建配置
**Then** 所有示例相关的模块、可执行文件和步骤被移除

---

### Requirement: PostgreSQL 特定测试配置
**移除原因**：相关测试文件已删除

构建系统 MUST NOT 在 enable_postgres 条件块中包含：
- postgres_test_module 配置
- simple_pg_test_module 配置
- minimal_test_module 配置
- simple_test_module 配置
- test-all 步骤（组合单元和集成测试）
- 相关的可执行文件和运行步骤

#### Scenario: 移除 PostgreSQL 特定测试

**Given** build.zig 包含 enable_postgres 条件的测试配置
**When** 清理构建配置
**Then** enable_postgres 块中所有测试相关配置被移除，但块本身和 PostgreSQL 依赖配置保留

---

## MODIFIED Requirements

### Requirement: 格式化路径配置

格式化步骤 MUST 仅包含存在的目录（src/ 和 build.zig），且 MUST NOT 包含 examples/ 目录（目录为空）或 tests/ 目录（测试文件已删除）。

#### Scenario: 更新格式化路径

**Given** build.zig 的 fmt 和 fmt-check 步骤包含 examples 和 tests 路径
**When** 清理构建配置
**Then** 格式化路径仅包含 "src" 和 "build.zig"

---

### Requirement: 主测试步骤简化

主测试步骤（test）MUST 仅保留 src/zorm.zig 的单元测试（通过 unit_tests），且 MUST 移除所有对已删除测试步骤的 dependOn 调用。单元测试模块 MUST 保留 build_options 和 pg 模块导入，且 MUST 移除 test_helper 和 seed_data 模块导入。

#### Scenario: 简化主测试步骤

**Given** build.zig 的 test 步骤依赖多个子测试步骤
**When** 清理构建配置
**Then** test 步骤仅运行 unit_tests，不依赖任何已删除的测试

---

## ADDED Requirements

### Requirement: 构建配置一致性验证

清理后的构建系统 MUST 成功执行 `zig build` 而不产生任何模块未找到错误，且 MUST 成功执行 `zig build test` 而不引用不存在的文件，且 MUST 成功执行 `zig build fmt` 而不尝试格式化不存在的目录，且 MUST 成功执行 `zig build docs` 生成 API 文档。

#### Scenario: 验证清理后的构建系统

**Given** build.zig 已完成清理
**When** 执行所有保留的构建命令
**Then** 所有命令成功执行，无错误或警告

---

### Requirement: 核心功能保留

清理后的 build.zig MUST 保留 zorm_module 的完整定义和配置，且 MUST 保留 PostgreSQL 依赖（pg）的导入和配置，且 MUST 保留 enable_postgres 构建选项，且 MUST 保留 build_options 的创建和配置，且 MUST 保留 docs 步骤用于文档生成，且 MUST 保留 fmt 和 fmt-check 步骤用于代码格式化。

#### Scenario: 验证核心功能完整性

**Given** build.zig 已完成清理
**When** 检查核心构建配置
**Then** 所有核心模块、选项和步骤均保持不变且功能正常
