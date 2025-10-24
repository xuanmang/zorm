# Tasks for implement-drop-table-query-api

## Specification Phase

- [x] **Task 1**: 创建 `drop-table-query-api` 规格文档
  - 定义所有 API 要求（newDropTable、ifExists、cascade、restrict、exec）
  - 为每个要求编写至少 1-2 个场景示例
  - 参考 `update-query-api` 规格格式
  - **验证**: spec.md 文件包含完整的 Requirements 和 Scenarios

## Testing Phase

- [x] **Task 2**: 编写 `newDropTable()` 工厂方法测试
  - 测试创建查询构建器
  - 测试自动提取表名
  - 测试内存管理（allocator 正确性）
  - **验证**: 测试通过，覆盖 AC3.3.1 和 AC3.3.2

- [x] **Task 3**: 编写 `ifExists()` 方法测试
  - 测试 SQL 包含 `IF EXISTS` 子句
  - 测试链式调用支持
  - **验证**: 测试通过，覆盖 AC3.3.3

- [x] **Task 4**: 编写 `cascade()` 和 `restrict()` 方法测试
  - 测试 CASCADE 选项生成正确 SQL
  - 测试 RESTRICT 选项生成正确 SQL
  - 测试 CASCADE 和 RESTRICT 互斥行为
  - 测试默认行为（无 CASCADE 或 RESTRICT）
  - **验证**: 测试通过，覆盖 AC3.3.4 和 AC3.3.5

- [x] **Task 5**: 编写 `build()` 方法 SQL 生成测试
  - 测试基本 DROP TABLE: `DROP TABLE users`
  - 测试带 IF EXISTS: `DROP TABLE IF EXISTS users`
  - 测试带 CASCADE: `DROP TABLE users CASCADE`
  - 测试带 RESTRICT: `DROP TABLE users RESTRICT`
  - 测试组合选项: `DROP TABLE IF EXISTS users CASCADE`
  - **验证**: 所有 SQL 生成场景测试通过

- [x] **Task 6**: 编写 `exec()` 方法集成测试
  - 创建测试表
  - 执行 DROP TABLE（基本）
  - 执行 DROP TABLE IF EXISTS（表不存在情况）
  - 执行 DROP TABLE CASCADE（有依赖对象情况）
  - **验证**: 集成测试通过，覆盖 AC3.3.6

## Documentation Phase

- [x] **Task 7**: 验证 PRD 示例代码
  - 提取 PRD AC3.3.7 示例代码
  - 编写测试验证示例可编译运行
  - 确保生成的 SQL 与注释一致
  - **验证**: PRD 示例代码测试通过

- [x] **Task 8**: 完善 API 文档和注释
  - 检查 DropTableQuery 所有方法的文档注释
  - 补充缺失的注释
  - 确保注释清晰描述参数、返回值、错误情况
  - **验证**: 所有公共方法有完整文档注释

## Validation Phase

- [x] **Task 9**: 运行 OpenSpec 验证
  - 执行 `openspec validate implement-drop-table-query-api --strict`
  - 修复所有验证错误
  - 确保规格格式正确
  - **验证**: `openspec validate --strict` 通过

- [x] **Task 10**: 运行完整测试套件
  - 执行 `zig build test`
  - 确保所有新增测试通过
  - 检查测试覆盖率达到 80%+
  - 验证无内存泄漏（std.testing.allocator）
  - **验证**: 所有测试通过，覆盖率达标

## Task Dependencies

```
Task 1 (规格文档)
  ↓
Task 2-6 (测试编写) - 可并行
  ↓
Task 7-8 (文档验证) - 可并行
  ↓
Task 9-10 (最终验证)
```

## Estimated Effort

- Task 1: 2 小时（规格文档编写）
- Task 2-6: 3 小时（测试编写，可部分并行）
- Task 7-8: 1 小时（文档验证）
- Task 9-10: 1 小时（验证和修复）

**总计**: 约 7 小时（1 个工作日）

## Success Metrics

- ✅ 所有 10 个任务完成
- ✅ OpenSpec 验证通过
- ✅ 测试覆盖率 ≥ 80%
- ✅ 所有测试通过，无内存泄漏
- ✅ PRD AC3.3.1 ~ AC3.3.7 全部验证通过
