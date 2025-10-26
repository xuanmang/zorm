# Implementation Tasks

## 1. 类型系统扩展
- [x] 1.1 在 `src/types.zig` 中定义 `SubqueryClause` 结构体
- [x] 1.2 为 `SubqueryClause` 添加 SQL 生成方法
- [x] 1.3 为 `SubqueryClause` 添加参数收集方法
- [x] 1.4 添加 `SubqueryClause` 的单元测试

## 2. WHERE IN/NOT IN 子查询
- [x] 2.1 在 `SelectQuery` 中添加 `subquery_clauses` 字段存储子查询
- [x] 2.2 实现 `whereIn(column, subquery)` 方法
- [x] 2.3 实现 `whereNotIn(column, subquery)` 方法
- [x] 2.4 更新 `buildSQL()` 方法以生成 WHERE IN 子查询 SQL
- [x] 2.5 实现子查询参数合并逻辑
- [x] 2.6 添加 WHERE IN 子查询的单元测试
- [x] 2.7 添加 WHERE NOT IN 子查询的单元测试

## 3. EXISTS/NOT EXISTS 子查询
- [x] 3.1 实现 `whereExists(subquery)` 方法
- [x] 3.2 实现 `whereNotExists(subquery)` 方法
- [x] 3.3 更新 `buildSQL()` 方法以生成 EXISTS 子查询 SQL
- [x] 3.4 添加 EXISTS 子查询的单元测试
- [x] 3.5 添加 NOT EXISTS 子查询的单元测试

## 4. FROM 派生表支持
- [x] 4.1 实现 `fromSubquery(subquery, alias)` 方法
- [x] 4.2 更新 `buildSQL()` 方法以支持 FROM 派生表 SQL 生成
- [x] 4.3 确保派生表别名在查询中正确引用
- [x] 4.4 添加 FROM 派生表的单元测试

## 5. 嵌套子查询支持
- [x] 5.1 验证子查询中可以包含子查询
- [x] 5.2 确保参数合并在多层嵌套时正确工作
- [x] 5.3 添加嵌套子查询的测试用例

## 6. 集成测试
- [ ] 6.1 创建 `tests/query/subquery_integration_tests.zig` 文件
- [ ] 6.2 添加 WHERE IN 子查询的 PostgreSQL 集成测试
- [ ] 6.3 添加 WHERE EXISTS 子查询的 PostgreSQL 集成测试
- [ ] 6.4 添加 FROM 派生表的 PostgreSQL 集成测试
- [ ] 6.5 添加复杂嵌套子查询的集成测试
- [ ] 6.6 验证所有集成测试在真实 PostgreSQL 数据库上通过

## 7. 文档和示例
- [ ] 7.1 为所有子查询方法添加完整的文档注释
- [ ] 7.2 在文档注释中包含使用示例
- [ ] 7.3 在 `examples/` 目录创建 `subquery.zig` 示例程序
- [ ] 7.4 确保示例程序可编译并正确运行
- [ ] 7.5 在 README 中添加子查询功能说明

## 8. 验证和优化
- [x] 8.1 运行 `zig build test` 确保所有测试通过 (9/9 子查询测试通过)
- [x] 8.2 使用 `std.testing.allocator` 检测内存泄漏 (无泄漏)
- [x] 8.3 运行 `openspec validate implement-subquery-support --strict` (通过)
- [ ] 8.4 确保代码覆盖率达到 80% 以上
- [ ] 8.5 性能基准测试:验证子查询开销 < 5%
- [ ] 8.6 代码审查和清理

## Notes

- 每个任务应该是独立可验证的
- 在进入下一个任务前,确保当前任务的测试通过
- 所有内存分配使用 `allocator.create()` 和 `allocator.destroy()`
- 错误处理必须符合 Zig 的错误联合类型模式
- 子查询 SQL 生成应该包裹在括号中: `(SELECT ...)`
- 参数占位符必须正确重新编号以避免冲突
