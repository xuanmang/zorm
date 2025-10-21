# Implementation Tasks

## 1. 核心实现（已完成）
- [x] 1.1 实现 InsertQuery 结构体和 init/deinit 方法
- [x] 1.2 实现 value() 单行插入方法
- [x] 1.3 实现 values() 批量插入方法
- [x] 1.4 实现 returning() RETURNING 子句方法
- [x] 1.5 实现 build() SQL 生成方法
- [x] 1.6 实现 exec() 执行插入方法
- [x] 1.7 实现 execReturning() 执行并返回数据方法
- [x] 1.8 在 DB 中添加 newInsert() 工厂方法

## 2. 优化实现（已完成）
- [x] 2.1 实现 SQL 缓冲区预分配优化（estimateSQLSize）
- [x] 2.2 实现批量容量预分配（ensureTotalCapacity）
- [x] 2.3 添加批量大小限制检查（MAX_BATCH_SIZE = 1000）
- [x] 2.4 添加 PostgreSQL 参数限制检查（65535 参数）

## 3. 测试实现
- [x] 3.1 添加单行插入基本测试
- [x] 3.2 添加批量插入基本测试
- [x] 3.3 添加 RETURNING 子句测试
- [x] 3.4 添加链式调用测试
- [ ] 3.5 添加性能基准测试（AC1.5.4）
  - 验证批量插入比单行插入快 10 倍以上
  - 测试不同批量大小的性能
- [ ] 3.6 添加边界条件测试
  - 批量大小限制测试
  - PostgreSQL 参数限制测试
  - 空值列表错误测试

## 4. 文档完善
- [ ] 4.1 补充 InsertQuery 的文档注释
  - value() 方法文档
  - values() 方法文档
  - returning() 方法文档
  - exec() 方法文档
  - execReturning() 方法文档
- [ ] 4.2 添加使用示例到文档注释
- [ ] 4.3 更新 README 中的 INSERT 示例

## 5. 集成验证
- [ ] 5.1 运行所有单元测试
- [ ] 5.2 运行集成测试（需要真实数据库）
- [ ] 5.3 验证内存泄漏检测通过
- [ ] 5.4 验证编译时类型检查工作正常

## 6. OpenSpec 流程
- [x] 6.1 创建 proposal.md
- [x] 6.2 创建 specs/insert-query-api/spec.md
- [x] 6.3 创建 tasks.md
- [ ] 6.4 运行 `openspec validate implement-insert-query-api --strict`
- [ ] 6.5 修复验证错误（如果有）

## 7. 提交代码
- [ ] 7.1 确保所有测试通过
- [ ] 7.2 提交代码变更
- [ ] 7.3 编写清晰的提交信息
