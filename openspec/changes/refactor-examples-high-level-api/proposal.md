# 重构示例程序使用高层级 API

## 概述

当前所有示例程序 (`basic.zig`, `transaction.zig`, `join.zig`) 都直接使用底层 SQL 字符串和驱动 API。这违背了 ZORM 的设计初衷,应该展示高层级查询构建器 API 的优势。

## 动机

### 问题
1. **不符合最佳实践**: 示例代码直接使用原始 SQL,未展示 ZORM 的核心价值
2. **类型安全缺失**: 手写 SQL 字符串容易出错,无法利用编译时检查
3. **可维护性差**: SQL 字符串分散在代码中,难以维护和重构
4. **学习曲线陡峭**: 新用户看不到如何正确使用 ZORM 的查询构建器

### 目标
1. 所有示例使用 `db.newSelect()`, `db.newInsert()`, `db.newUpdate()`, `db.newDelete()` 等高层级 API
2. 展示链式 API 的流畅使用体验
3. 利用编译时类型检查确保查询正确性
4. 为用户提供真实、可复用的代码模式

## 影响范围

### 修改的文件
- `examples/basic.zig` - CRUD 操作示例
- `examples/transaction.zig` - 事务管理示例
- `examples/join.zig` - JOIN 查询示例
- `examples/README.md` - 更新文档说明

### 不影响的部分
- `examples/schema.zig` - 保持不变 (已使用反射 API)
- `examples/hooks.zig.example` - 文档示例,稍后单独处理
- 核心库代码 - 仅示例重构,API 不变

## 风险评估

### 低风险
- 仅修改示例代码,不影响库本身
- 现有测试覆盖核心 API,确保功能正确
- 可逐步验证每个示例的正确性

### 潜在问题
- 需要确保新示例在所有场景下都能正常运行
- 需要验证错误处理逻辑的正确性
- 需要保持输出格式一致,方便用户对比

## 验收标准

1. ✅ 所有示例编译通过 (`zig build examples`)
2. ✅ 所有示例运行成功 (连接真实数据库)
3. ✅ 无原始 SQL 字符串 (除 BEGIN/COMMIT/ROLLBACK)
4. ✅ 使用查询构建器的链式 API
5. ✅ 输出结果与原示例一致
6. ✅ 代码更简洁、类型安全

## 实施计划

分三个阶段逐步重构:

### 阶段 1: Basic CRUD 示例
- 使用 `newInsert()`, `newSelect()`, `newUpdate()`, `newDelete()`
- 展示条件查询、排序、参数绑定

### 阶段 2: Transaction 示例
- 保留 `begin()`, `commit()`, `rollback()` (事务控制)
- 在事务中使用查询构建器 API

### 阶段 3: JOIN 示例
- 使用 `newSelect()` 的 `join()`, `leftJoin()` 方法
- 展示多表关联和聚合查询

## 备注

这个重构将使 ZORM 示例成为用户学习的最佳起点,真正展示 ORM 框架的价值。
