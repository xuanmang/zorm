# Tasks: 增强 GROUP BY 和聚合函数测试覆盖

## 任务列表

### 1. 添加基础聚合函数单元测试

**描述**: 为所有标准聚合函数(COUNT, SUM, AVG, MAX, MIN)添加单元测试,验证 SQL 生成的正确性。

**验收标准**:
- [x] COUNT 聚合测试通过
- [x] SUM 聚合测试通过
- [x] AVG 聚合测试通过
- [x] MAX 和 MIN 聚合测试通过
- [x] 所有测试使用 `std.testing.expectEqualStrings` 验证 SQL 字符串

**依赖**: 无

**文件**: `src/query/query.zig`

---

### 2. 添加 DISTINCT 聚合单元测试

**描述**: 添加 DISTINCT 关键字聚合的测试,验证 `COUNT(DISTINCT col)` 等语法的 SQL 生成。

**验收标准**:
- [x] COUNT(DISTINCT column) 测试通过
- [x] 多个 DISTINCT 聚合测试通过
- [x] SQL 生成包含正确的 DISTINCT 关键字

**依赖**: 任务 1

**文件**: `src/query/query.zig`

---

### 3. 添加多列 GROUP BY 单元测试

**描述**: 验证两种多列 GROUP BY 的用法:单次调用逗号分隔和多次链式调用。

**验收标准**:
- [x] 单次调用 `groupBy("col1, col2")` 测试通过
- [x] 多次调用 `groupBy("col1").groupBy("col2")` 测试通过
- [x] 两种方式生成相同的 SQL

**依赖**: 无

**文件**: `src/query/query.zig`

---

### 4. 添加聚合结果映射集成测试

**描述**: 创建集成测试,验证聚合查询结果能正确扫描到自定义结构体。

**验收标准**:
- [x] 创建测试数据库表(users, posts)
- [x] 插入测试数据
- [x] 定义 UserStats 结构体
- [x] 执行聚合查询并扫描结果
- [x] 验证聚合字段值的正确性(post_count, total_views, avg_views)
- [x] 测试包含 NULL 值的聚合结果

**依赖**: 任务 1

**文件**: `tests/integration/select_aggregation_test.zig` (新建)

---

### 5. 添加 JOIN + GROUP BY + HAVING 组合测试

**描述**: 验证聚合查询与 JOIN 和 HAVING 子句的组合使用。

**验收标准**:
- [x] 单元测试验证 JOIN + GROUP BY 的 SQL 生成
- [x] 集成测试验证 JOIN + GROUP BY + HAVING 的实际查询
- [x] 测试 HAVING 条件正确过滤分组结果
- [x] 测试 ORDER BY 对聚合结果的排序

**依赖**: 任务 4

**文件**: `src/query/query.zig`, `tests/integration/select_aggregation_test.zig`

---

### 6. 更新文档和示例

**描述**: 完善 `groupBy()` 和 `having()` 方法的文档注释,添加完整的使用示例。

**验收标准**:
- [x] `groupBy()` 方法包含详细文档注释
- [x] 文档包含单列和多列分组的示例
- [x] 文档包含与聚合函数配合的示例
- [x] 文档包含 JOIN + GROUP BY + HAVING 的完整示例
- [x] 添加独立的示例测试用例(用于文档生成)

**依赖**: 任务 1-5

**文件**: `src/query/query.zig`

---

### 7. 验证测试覆盖率

**描述**: 运行所有测试并检查覆盖率,确保新增测试有效。

**验收标准**:
- [x] 所有单元测试通过
- [x] 所有集成测试通过(需要 PostgreSQL 环境)
- [x] 无内存泄漏(使用 `std.testing.allocator`)
- [x] `openspec validate` 通过

**依赖**: 任务 1-6

**命令**:
```bash
zig build test
openspec validate enhance-group-by-aggregation-testing --strict
```

---

## 任务执行顺序

```
1. 基础聚合函数单元测试
   ↓
2. DISTINCT 聚合单元测试
   ↓
3. 多列 GROUP BY 单元测试
   ↓
4. 聚合结果映射集成测试 ← 可并行
   ↓
5. JOIN + GROUP BY + HAVING 组合测试
   ↓
6. 更新文档和示例
   ↓
7. 验证测试覆盖率
```

## 预估工时

- 任务 1-3 (单元测试): 2 小时
- 任务 4 (集成测试基础): 2 小时
- 任务 5 (组合场景): 1.5 小时
- 任务 6 (文档更新): 1 小时
- 任务 7 (验证): 0.5 小时

**总计**: 约 7 小时

## 测试文件结构

```
tests/
├── integration/
│   └── select_aggregation_test.zig (新建)
│       ├── 基础聚合结果映射测试
│       ├── NULL 值聚合测试
│       └── JOIN + GROUP BY + HAVING 测试
│
src/query/
└── query.zig
    ├── test "SelectQuery: COUNT aggregation"
    ├── test "SelectQuery: SUM aggregation"
    ├── test "SelectQuery: AVG aggregation"
    ├── test "SelectQuery: MAX and MIN aggregation"
    ├── test "SelectQuery: COUNT DISTINCT aggregation"
    ├── test "SelectQuery: multi-column GROUP BY (single call)"
    ├── test "SelectQuery: multi-column GROUP BY (chained calls)"
    ├── test "SelectQuery: JOIN with GROUP BY"
    └── test "Example: comprehensive aggregation query"
```
