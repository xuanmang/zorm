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
