# Proposal: 增强 GROUP BY 和聚合函数测试覆盖

## Why

ZORM 已实现 GROUP BY 和 HAVING 基础功能,但缺少全面的测试覆盖,无法验证所有聚合函数(COUNT/SUM/AVG/MAX/MIN)、DISTINCT 聚合、复杂组合场景是否符合 PRD Story 4.3 的要求。

## What Changes

- 添加所有聚合函数(COUNT, SUM, AVG, MAX, MIN)的单元测试
- 添加 DISTINCT 聚合的测试场景
- 添加多列 GROUP BY 的测试验证
- 添加聚合结果映射到自定义结构体的集成测试
- 添加 JOIN + GROUP BY + HAVING 组合场景测试
- 完善 `groupBy()` 和 `having()` 方法的文档注释

## Impact

- **Affected specs**: `group-by-aggregation-testing` (新建)
- **Affected code**: `src/query/query.zig` (添加测试), `tests/integration/` (新建集成测试文件)
- **Breaking changes**: 无

---

## 详细说明

### 当前状况

当前 ZORM 已实现了 GROUP BY 和 HAVING 的基础功能,但测试覆盖不足:

1. **现有功能**:
   - `groupBy(column)` 方法支持单列和多列分组
   - `having(condition, args)` 方法支持 HAVING 条件
   - 聚合函数可通过 `column()` 方法使用(如 `COUNT(*)`, `SUM(col)`)

2. **测试缺失**:
   - 缺少所有聚合函数(SUM, AVG, MAX, MIN)的完整测试
   - 缺少 DISTINCT 聚合(如 `COUNT(DISTINCT column)`)的测试
   - 缺少聚合结果扫描到自定义结构体的集成测试
   - 缺少 JOIN + GROUP BY + HAVING 组合场景的测试
   - 缺少多列 GROUP BY 的测试

3. **PRD 对齐**:
   - PRD Story 4.3 要求完整的聚合功能验证
   - 需要与 Bun ORM 使用方式对齐的示例

## 目标

1. 添加全面的聚合函数测试(COUNT, SUM, AVG, MAX, MIN)
2. 验证 DISTINCT 聚合功能
3. 添加聚合结果映射到自定义结构体的集成测试
4. 验证 JOIN + GROUP BY + HAVING 的组合场景
5. 验证多列 GROUP BY 的两种用法
6. 完善文档和使用示例

## 设计决策

### 1. 测试策略

采用三层测试结构:

1. **单元测试**: 验证 SQL 生成的正确性
   - 各种聚合函数的 SQL 生成
   - DISTINCT 聚合的 SQL 生成
   - 多列 GROUP BY 的 SQL 生成
   - JOIN + GROUP BY + HAVING 组合的 SQL 生成

2. **集成测试**: 验证实际数据库行为
   - 创建测试表和数据
   - 执行聚合查询
   - 验证结果正确性
   - 验证自定义结构体映射

3. **示例代码**: 提供实用的使用示例
   - 基础聚合查询
   - 多表 JOIN 聚合
   - 复杂分组统计

### 2. 不修改现有 API

当前 API 已满足需求,无需修改:
- `groupBy(column)` 支持单次调用传入逗号分隔的多列
- `groupBy(column)` 支持多次调用链式添加列
- `having(condition, args)` 支持参数绑定
- `column(expr)` 支持任意聚合表达式

### 3. 测试数据设计

使用用户-文章场景:
- `users` 表: 用户基础信息
- `posts` 表: 文章信息(包含 user_id, view_count)
- 测试统计每个用户的文章数、总浏览量、平均浏览量等

## 实现范围

### 规范变更

创建新规范 `group-by-aggregation-testing`,包含以下需求:

1. **多种聚合函数测试**: 验证 COUNT, SUM, AVG, MAX, MIN
2. **DISTINCT 聚合测试**: 验证 COUNT(DISTINCT col)
3. **多列 GROUP BY 测试**: 验证两种用法
4. **聚合结果映射测试**: 验证扫描到自定义结构体
5. **组合场景测试**: 验证 JOIN + GROUP BY + HAVING
6. **文档完善**: 更新示例和注释

### 任务分解

1. 添加单元测试验证 SQL 生成
2. 添加集成测试验证数据库行为
3. 更新文档和示例代码
4. 验证测试覆盖率

## 风险和考虑

1. **PostgreSQL 版本兼容性**:
   - 所有聚合函数在 PostgreSQL 9.5+ 中都支持
   - 不涉及特殊的 PostgreSQL 扩展

2. **浮点数精度**:
   - AVG() 返回浮点数,测试时需考虑精度误差
   - 使用近似比较而非精确相等

3. **NULL 值处理**:
   - COUNT(*) 统计所有行
   - COUNT(column) 只统计非 NULL 行
   - SUM/AVG/MAX/MIN 忽略 NULL 值

## 成功标准

1. 所有聚合函数都有对应的测试场景
2. 集成测试在真实 PostgreSQL 环境通过
3. 测试覆盖 PRD Story 4.3 的所有验收标准
4. 文档包含完整的使用示例
5. `openspec validate` 通过

## 替代方案

无。当前方案是最小化的增强,只添加测试和文档,不改变现有 API。

## 未来扩展

1. 窗口函数支持(OVER, PARTITION BY)
2. ROLLUP, CUBE, GROUPING SETS 支持
3. FILTER 子句支持(聚合过滤)
4. 聚合函数的性能优化

## 时间线

- 单元测试: 1-2 小时
- 集成测试: 2-3 小时
- 文档更新: 1 小时
- 总计: 4-6 小时

## 参考资料

- PRD Story 4.3: GROUP BY and Aggregation Functions
- PostgreSQL 聚合函数文档: https://www.postgresql.org/docs/current/functions-aggregate.html
- Bun ORM GROUP BY 示例
