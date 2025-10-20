# Proposal: 清理 build.zig 中已删除的测试和示例引用

## Why

构建系统配置应该与实际代码结构保持一致。当前 build.zig 包含大量对已删除文件的引用，这不仅造成配置混乱，还可能导致构建错误，降低开发效率和代码可维护性。通过清理这些死代码引用，我们可以：

1. 确保构建系统的准确性和可靠性
2. 提高开发者对项目结构的理解
3. 避免误导性的构建步骤和配置
4. 简化构建配置，使其更易于维护

## Context

当前 `build.zig` 文件包含大量对已删除的测试文件和示例文件的引用，这些引用导致构建系统配置冗余且可能引发错误。根据 git status 和文件系统检查，以下目录几乎为空或完全不存在：

- `tests/` 目录下的大部分单元测试文件已被删除
- `examples/` 目录下的所有示例文件已被删除
- 相关的辅助模块（test_helper、seed_data、common 等）也已删除

## Problem

`build.zig` 中存在以下问题：

1. 引用不存在的测试辅助模块（test_helper、seed_data）
2. 引用不存在的示例公共模块（examples/common/db_config.zig、examples/common/models.zig）
3. 配置了大量不存在的测试步骤（test-db-unit、test-pool、test-types 等）
4. 配置了不存在的示例构建步骤（setup_database、basic_connection 等）
5. 包含已删除文件的格式化检查路径（examples）

这些死代码引用会：
- 导致构建配置混乱
- 可能引发运行时错误
- 降低代码可维护性
- 误导开发者关于项目实际结构

## Proposed Solution

清理 `build.zig` 文件，移除所有对已删除测试和示例文件的引用，仅保留：

1. **核心库构建**：zorm 模块的基本配置
2. **文档生成**：docs 步骤配置
3. **代码格式化**：仅保留 src 和 build.zig 的格式化
4. **基础测试框架**：保留 src/zorm.zig 的单元测试（如果该文件包含测试）

移除的内容包括：
- 所有测试辅助模块引用（test_helper、seed_data）
- 所有示例相关的构建配置
- 所有独立测试步骤配置（test-db-unit、test-pool 等）
- 所有集成测试配置
- PostgreSQL 特定的测试配置（test-postgres、test-simple-pg 等）

## Success Criteria

1. `zig build` 成功执行，无任何模块导入错误
2. `zig build fmt` 仅格式化存在的文件
3. `zig build docs` 成功生成文档
4. `zig build test` 仅运行存在的测试（如果有）
5. 所有构建步骤不引用已删除的文件

## Impact Assessment

### Affected Components
- build.zig（核心影响）
- 构建系统使用者的工作流

### Breaking Changes
- 移除所有测试步骤命令（test-db-unit、test-pool 等）
- 移除所有示例构建命令（run-example、run-all-examples 等）
- 移除 test-all 命令

### Migration Path
开发者需要：
1. 停止使用已移除的构建命令
2. 如需测试，需重新创建测试文件和配置
3. 如需示例，需重新创建示例文件和配置

## Open Questions

1. 是否需要保留 PostgreSQL 依赖配置（pg.zig）？
   - **建议**：保留，因为核心模块可能仍在使用

2. 是否保留 `enable_postgres` 构建选项？
   - **建议**：保留，保持配置灵活性

3. 是否需要创建最小化的测试配置？
   - **建议**：在本次清理中不创建，保持纯粹的清理操作

## References

- Git status 显示大量测试和示例文件已删除
- 当前 tests/ 目录仅包含空的 integration/ 子目录
- 当前 examples/ 目录完全为空
