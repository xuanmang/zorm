# 设计文档: 示例程序高层级 API 重构

## 架构决策

### 核心原则

1. **展示最佳实践**: 示例应该是用户学习的榜样,必须使用推荐的 API
2. **类型安全优先**: 利用 Zig 的编译时类型检查,避免运行时 SQL 错误
3. **渐进式学习**: 从简单到复杂,逐步展示 API 的强大功能
4. **真实场景**: 示例应该反映实际项目中的常见用例

### API 选择策略

#### 查询构建器 API (推荐)
```zig
// ✅ 推荐: 类型安全、链式 API
var query = try db.newSelect(User);
defer query.deinit();

try query.column("name").column("email")
    .where("age", .gte, QueryArg{ .int = 18 })
    .orderBy("id", .desc)
    .limit(10);

const sql = try query.build();
var rows = try query.exec();
```

#### 原始 SQL (仅特殊场景)
```zig
// ⚠️ 仅用于: BEGIN/COMMIT/ROLLBACK, 或查询构建器不支持的场景
_ = try db.exec("BEGIN", &[_]QueryArg{});
_ = try db.exec("COMMIT", &[_]QueryArg{});
```

### 重构策略

#### Basic CRUD 示例

**之前 (原始 SQL):**
```zig
const sql = "INSERT INTO users (name, email, age) VALUES ($1, $2, $3)";
const args = [_]QueryArg{
    .{ .string = "Alice" },
    .{ .string = "alice@example.com" },
    .{ .int = 28 },
};
_ = try driver.exec(sql, &args);
```

**之后 (查询构建器):**
```zig
var insert = try db.newInsert(User);
defer insert.deinit();

const user = User{
    .name = "Alice",
    .email = "alice@example.com",
    .age = 28,
    .active = true,
};

try insert.values(&user);
_ = try insert.exec();
```

#### Transaction 示例

**设计考量:**
- 事务控制 (`BEGIN`, `COMMIT`, `ROLLBACK`) 保留原始 SQL
- 事务内的 CRUD 操作使用查询构建器
- 错误处理使用 `errdefer` 确保回滚

**模式:**
```zig
_ = try db.begin();
errdefer _ = db.rollback() catch {};

// 使用查询构建器执行操作
var update = try db.newUpdate(Account);
defer update.deinit();

try update.set("balance", .{ .float = new_balance })
    .where("username", .eq, .{ .string = from });
_ = try update.exec();

_ = try db.commit();
```

#### JOIN 示例

**设计考量:**
- 使用 `join()`, `leftJoin()` 方法
- 聚合函数使用 `column("COUNT(*) as count")`
- GROUP BY 使用 `groupBy()` 方法

**模式:**
```zig
var query = try db.newSelect(User);
defer query.deinit();

try query.column("users.name")
    .column("posts.title")
    .join("posts", "posts.user_id = users.id")
    .where("posts.published", .eq, .{ .bool = true })
    .orderBy("users.id", .asc);

var rows = try query.exec();
defer rows.deinit();
```

## 技术权衡

### 优势
1. **类型安全**: 编译时检查列名、类型、表名
2. **可维护性**: 查询逻辑集中,易于修改和测试
3. **可读性**: 链式 API 比 SQL 字符串更直观
4. **防注入**: 参数自动转义,无需手动处理

### 劣势
1. **学习曲线**: 需要学习查询构建器 API
2. **灵活性**: 某些复杂 SQL 可能需要原始查询

### 解决方案
- 为复杂场景提供 `newRaw()` API
- 文档中说明何时使用哪种 API
- 示例覆盖常见场景,但不过度复杂

## 测试策略

### 验证方法
1. **编译测试**: `zig build examples` 必须成功
2. **运行测试**: 连接真实数据库,验证输出
3. **对比测试**: 新旧输出一致性检查
4. **错误场景**: 验证错误处理逻辑

### 测试覆盖
- ✅ INSERT 单条/多条
- ✅ SELECT 条件查询、排序、分页
- ✅ UPDATE 条件更新
- ✅ DELETE 条件删除
- ✅ 事务提交/回滚
- ✅ INNER JOIN / LEFT JOIN
- ✅ 聚合查询 (COUNT, GROUP BY)

## 向后兼容性

### 不影响
- 核心库 API 保持不变
- 现有用户代码不受影响
- 测试套件继续运行

### 受益
- 新用户获得更好的学习材料
- 文档和示例保持一致
- 减少误用和错误报告

## 实施步骤

1. **准备**: 确保查询构建器 API 完整且稳定
2. **重构**: 逐个示例重写,保持功能一致
3. **验证**: 运行并对比输出
4. **文档**: 更新 README 和注释
5. **发布**: 作为下个版本的一部分

## 未来考虑

- 添加更多高级示例 (子查询、CTE、窗口函数)
- 性能基准测试 (查询构建器 vs 原始 SQL)
- 最佳实践指南文档
