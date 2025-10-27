# Tasks: 示例程序高层级 API 重构

## 实施任务列表

### 阶段 1: Basic CRUD 示例重构 (basic.zig)

- [ ] **Task 1.1**: 重构 INSERT 操作使用 `db.newInsert()`
  - 替换插入 "张三" 的代码
  - 替换插入 "李四" 的代码
  - 替换插入 "王五" 的代码
  - **验证**: 编译通过,运行正常,影响行数正确
  - **依赖**: insert-query-api

- [ ] **Task 1.2**: 重构 SELECT 操作使用 `db.newSelect()`
  - 替换条件查询 (age >= 25) 的代码
  - 添加 `column()` 方法链式调用
  - 添加 `where()` 和 `orderBy()` 方法
  - **验证**: 查询结果与原代码一致,返回 2 条记录
  - **依赖**: select-query-api

- [ ] **Task 1.3**: 重构 UPDATE 操作使用 `db.newUpdate()`
  - 替换更新 "张三" 年龄的代码
  - 使用 `set()` 和 `where()` 方法
  - **验证**: 更新成功,影响行数为 1
  - **依赖**: update-query-api

- [ ] **Task 1.4**: 重构验证查询使用 `db.newSelect()`
  - 替换验证更新结果的查询代码
  - **验证**: 查询到的年龄为 29
  - **依赖**: select-query-api

- [ ] **Task 1.5**: 重构 DELETE 操作使用 `db.newDelete()`
  - 替换删除不活跃用户的代码
  - 使用 `where()` 方法
  - **验证**: 删除成功,影响行数为 1
  - **依赖**: delete-query-api

- [ ] **Task 1.6**: 重构统计查询使用 `db.newSelect()`
  - 替换 COUNT(*) 查询代码
  - 使用 `column("COUNT(*)")` 方法
  - **验证**: 统计结果为 2
  - **依赖**: select-query-api

- [ ] **Task 1.7**: 测试 basic.zig 示例
  - 运行 `zig build run-example-basic`
  - 验证所有输出与原示例一致
  - 验证无原始 SQL 字符串 (除表创建)
  - **验证**: 示例运行成功,输出正确

---

### 阶段 2: Transaction 示例重构 (transaction.zig)

- [ ] **Task 2.1**: 重构基础事务中的 INSERT 操作
  - 在 `demonstrateBasicTransaction()` 中使用 `db.newInsert()`
  - 插入 Alice 账户使用查询构建器
  - **验证**: 事务提交成功,数据持久化
  - **依赖**: insert-query-api, transaction-management-api

- [ ] **Task 2.2**: 重构转账准备阶段的 INSERT 操作
  - 在 `demonstrateTransfer()` 中使用 `db.newInsert()`
  - 插入 Frank 和 Grace 账户
  - **验证**: 批量插入成功
  - **依赖**: insert-query-api, transaction-management-api

- [ ] **Task 2.3**: 重构转账函数的余额检查
  - 在 `transfer()` 函数中使用 `db.newSelect()`
  - 查询源账户余额
  - **验证**: 余额不足时正确抛出错误
  - **依赖**: select-query-api, transaction-management-api

- [ ] **Task 2.4**: 重构转账函数的扣款操作
  - 在 `transfer()` 函数中使用 `db.newUpdate()`
  - 从源账户扣款
  - **验证**: 余额正确扣减
  - **依赖**: update-query-api, transaction-management-api

- [ ] **Task 2.5**: 重构转账函数的加款操作
  - 在 `transfer()` 函数中使用 `db.newUpdate()`
  - 向目标账户加款
  - **验证**: 余额正确增加
  - **依赖**: update-query-api, transaction-management-api

- [ ] **Task 2.6**: 重构余额验证函数
  - 在 `verifyBalance()` 函数中使用 `db.newSelect()`
  - 查询账户余额
  - **验证**: 验证结果正确
  - **依赖**: select-query-api

- [ ] **Task 2.7**: 重构手动回滚示例
  - 在 `demonstrateManualRollback()` 中使用 `db.newInsert()`
  - 保留错误处理和回滚逻辑
  - **验证**: 回滚成功,数据未插入
  - **依赖**: insert-query-api, transaction-management-api

- [ ] **Task 2.8**: 测试 transaction.zig 示例
  - 运行 `zig build run-example-transaction`
  - 验证所有事务场景正常工作
  - 验证转账结果正确 (Frank 400, Grace 400)
  - **验证**: 示例运行成功,输出正确

---

### 阶段 3: JOIN 示例重构 (join.zig)

- [ ] **Task 3.1**: 重构数据准备阶段的用户插入
  - 在 `insertSampleData()` 中使用 `db.newInsert(User)`
  - 批量插入 Alice, Bob, Charlie
  - **验证**: 用户插入成功
  - **依赖**: insert-query-api

- [ ] **Task 3.2**: 重构数据准备阶段的文章插入
  - 在 `insertSampleData()` 中使用 `db.newInsert(Post)`
  - 插入 Alice 的 2 篇文章和 Bob 的 1 篇文章
  - **验证**: 文章插入成功
  - **依赖**: insert-query-api

- [ ] **Task 3.3**: 重构数据准备阶段的评论插入
  - 在 `insertSampleData()` 中使用 `db.newInsert(Comment)`
  - 插入 2 条评论
  - **验证**: 评论插入成功
  - **依赖**: insert-query-api

- [ ] **Task 3.4**: 重构 INNER JOIN 查询
  - 使用 `db.newSelect(User)`
  - 添加 `column()`, `join()`, `where()`, `orderBy()` 方法
  - **验证**: 返回 2 条记录,输出格式正确
  - **依赖**: select-query-join-api

- [ ] **Task 3.5**: 重构 LEFT JOIN 聚合查询
  - 使用 `db.newSelect(User)`
  - 添加 `leftJoin()`, `groupBy()` 方法
  - 使用 `column("COUNT(posts.id) as post_count")`
  - **验证**: 返回 3 条记录,统计结果正确
  - **依赖**: select-query-join-api

- [ ] **Task 3.6**: 重构多表 JOIN 查询
  - 使用 `db.newSelect(Post)`
  - 链式调用两个 `join()` 方法
  - **验证**: 返回所有评论,输出格式正确
  - **依赖**: select-query-join-api

- [ ] **Task 3.7**: 测试 join.zig 示例
  - 运行 `zig build run-example-join`
  - 验证所有 JOIN 查询正常工作
  - 验证聚合统计结果正确
  - **验证**: 示例运行成功,输出正确

---

### 阶段 4: 文档更新和验证

- [ ] **Task 4.1**: 更新 examples/README.md
  - 更新示例说明,强调使用高层级 API
  - 添加查询构建器使用说明
  - 更新代码片段和输出示例
  - **验证**: 文档准确反映新的实现

- [ ] **Task 4.2**: 添加代码注释
  - 在关键位置添加注释说明 API 用法
  - 标注 why 而不是 what
  - **验证**: 注释清晰、有用

- [ ] **Task 4.3**: 运行所有示例的集成测试
  - 运行 `zig build examples`
  - 逐个运行每个示例,验证输出
  - 对比新旧输出的一致性
  - **验证**: 所有示例编译运行成功

- [ ] **Task 4.4**: 代码审查和清理
  - 检查是否有遗留的原始 SQL 字符串
  - 确保所有 `defer deinit()` 正确放置
  - 统一代码风格和格式
  - **验证**: 代码质量符合标准

- [ ] **Task 4.5**: 性能验证 (可选)
  - 对比查询构建器和原始 SQL 的性能
  - 确保无明显性能退化
  - **验证**: 性能符合预期

---

## 任务依赖关系

```
阶段 1 (basic.zig)
├── Task 1.1 → Task 1.2 → Task 1.3 → Task 1.4 → Task 1.5 → Task 1.6 → Task 1.7
└── 所有任务可并行执行,最后统一测试

阶段 2 (transaction.zig)
├── Task 2.1 → Task 2.2
├── Task 2.3 → Task 2.4 → Task 2.5
├── Task 2.6 (独立)
├── Task 2.7 (独立)
└── Task 2.8 (最后测试)

阶段 3 (join.zig)
├── Task 3.1, 3.2, 3.3 (数据准备,可并行)
├── Task 3.4, 3.5, 3.6 (查询重构,可并行)
└── Task 3.7 (最后测试)

阶段 4 (文档和验证)
├── 依赖阶段 1, 2, 3 完成
└── Task 4.1 → Task 4.2 → Task 4.3 → Task 4.4 → Task 4.5
```

## 估算工作量

- **阶段 1**: 2-3 小时
- **阶段 2**: 3-4 小时
- **阶段 3**: 2-3 小时
- **阶段 4**: 1-2 小时
- **总计**: 8-12 小时

## 风险和缓解措施

1. **风险**: 查询构建器 API 可能不支持某些复杂查询
   - **缓解**: 提前测试 API 覆盖范围,必要时使用 `newRaw()`

2. **风险**: 重构后输出格式变化
   - **缓解**: 逐步对比输出,保持一致性

3. **风险**: 性能退化
   - **缓解**: 进行基准测试,优化查询构建器

4. **风险**: 错误处理逻辑变化
   - **缓解**: 仔细测试错误场景,确保行为一致
