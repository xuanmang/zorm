# ZORM 示例程序

本目录包含 ZORM 的使用示例和参考代码。

## 可运行示例

### schema.zig
展示如何使用 ZORM 的反射系统自动生成 CREATE TABLE 语句。

```bash
zig build run-example-schema
```

## 文档示例 (*.example 文件)

以下文件是 API 使用参考,展示了各种功能的用法模式。这些示例需要配合完整的数据库驱动才能实际运行,当前作为文档参考:

- **basic.zig.example** - 基础 CRUD 操作示例
  - SELECT、INSERT、UPDATE、DELETE 查询构建
  - 参数绑定
  - 条件查询和排序

- **transaction.zig.example** - 事务管理示例
  - BEGIN、COMMIT、ROLLBACK
  - 事务隔离级别
  - 使用 errdefer 自动回滚
  - 转账示例 (经典事务场景)

- **join.zig.example** - JOIN 查询示例
  - INNER JOIN、LEFT JOIN、RIGHT JOIN
  - 多表关联查询
  - 子查询和派生表
  - 聚合 JOIN

- **upsert.zig.example** - UPSERT 操作示例
  - ON CONFLICT DO NOTHING
  - ON CONFLICT DO UPDATE
  - 使用 EXCLUDED 关键字
  - 批量 UPSERT

- **hooks.zig.example** - 查询钩子示例
  - 内置 LoggingHook
  - 内置 PerformanceHook
  - 自定义钩子实现
  - 钩子链执行

## 如何使用这些示例

1. **查看示例代码**: 打开 `.example` 文件查看 API 使用方法
2. **复制到项目**: 将代码模式复制到您的项目中
3. **调整参数**: 根据您的数据模型调整结构体定义
4. **集成驱动**: 当 PostgreSQL 驱动集成完成后,这些示例可以实际运行

## 编译所有可运行示例

```bash
zig build examples
```

## 注意事项

- `.example` 文件是文档参考,不会被编译
- 实际运行需要数据库驱动支持 (开发中)
- 所有示例都使用相同的模式,易于理解和复用

## 开发路线图

### 查询构建器 API

ZORM 提供了高层级查询构建器 API (`newInsert()`, `newSelect()`, `newUpdate()`, `newDelete()`),目标是为常见的 CRUD 操作提供类型安全、链式调用的接口。

**当前状态**:
- ✅ INSERT 操作完全支持
- ✅ UPDATE 操作完全支持
- ✅ DELETE 操作完全支持
- 🚧 SELECT 操作部分支持 (建议复杂查询使用原始 SQL)

**未来计划**:
- 完善 SELECT 查询构建器的结果遍历 API
- 添加更多便捷方法(如 `findOne()`, `findAll()` 等)
- 改进查询结果的类型安全性

**当前最佳实践**:
1. 对于简单的 INSERT/UPDATE/DELETE,优先使用查询构建器
2. 对于复杂的 SELECT (特别是多表 JOIN、子查询),使用原始 SQL
3. 混合使用策略:在同一个项目中根据需求选择合适的方式

示例:
```zig
// ✅ 推荐:使用查询构建器进行 INSERT
var insert = try db.newInsert(User);
defer insert.deinit();
_ = try insert.value(.{ .name = "Alice", .age = 30 });
const result = try insert.exec();

// ✅ 推荐:复杂查询使用原始 SQL
const sql =
    \\SELECT users.name, posts.title
    \\FROM users
    \\INNER JOIN posts ON posts.user_id = users.id
    \\WHERE posts.published = true
;
var rows = try db.query(sql, &[_]zorm.QueryArg{});
defer rows.close();
```
