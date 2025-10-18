# ZORM 示例代码集

本目录包含 ZORM 的完整使用示例，从基础到高级，帮助你快速掌握 ZORM。

## 🚀 快速开始

### 1. 环境要求

- Zig 0.15.2 或更高版本
- PostgreSQL 12 或更高版本
- 数据库连接信息 (见下方配置)

### 2. 数据库配置

默认配置:
```bash
ZORM_DB_HOST=127.0.0.1
ZORM_DB_PORT=5432
ZORM_DB_USER=pguser
ZORM_DB_PASSWORD=Pg#123!
ZORM_DB_NAME=postgres
```

你可以通过环境变量覆盖这些默认值：
```bash
export ZORM_DB_HOST=localhost
export ZORM_DB_PORT=5432
export ZORM_DB_USER=myuser
export ZORM_DB_PASSWORD=mypassword
export ZORM_DB_NAME=mydb
```

### 3. 初始化数据库

首次运行前，需要初始化数据库结构:

```bash
zig build run-example -Dexample=00_setup_database
```

### 4. 运行示例

运行单个示例:
```bash
zig build run-example -Dexample=01_basic_connection
```

运行所有示例:
```bash
zig build run-all-examples
```

## 📚 示例索引

### 🟢 基础篇 (第1天)

| 编号 | 文件名 | 标题 | 功能需求 | 说明 |
|------|--------|------|----------|------|
| 00 | 00_setup_database.zig | 数据库初始化 | - | 创建表结构和种子数据 |
| 01 | 01_basic_connection.zig | 基础连接 | FR1 | 学习如何连接数据库 |
| 02 | 02_simple_select.zig | 简单查询 | FR2 | 基本的 SELECT 查询 |
| 03 | 03_insert_operations.zig | 插入操作 | FR2 | INSERT 单条和批量 |
| 04 | 04_update_operations.zig | 更新操作 | FR2 | UPDATE 条件更新 |
| 05 | 05_delete_operations.zig | 删除操作 | FR2 | DELETE 软删除和硬删除 |

### 🟡 中级篇 (第2-4天)

| 编号 | 文件名 | 标题 | 功能需求 | 说明 |
|------|--------|------|----------|------|
| 06 | 06_query_builder.zig | 查询构建 | FR3 | 复杂 WHERE、JOIN、聚合 |
| 07 | 07_transactions.zig | 事务管理 | FR4 | begin/commit/rollback |
| 08 | 08_relations_belongs_to.zig | Belongs-To 关系 | FR5 | 多对一关系（Post → User） |
| 09 | 09_relations_has_many.zig | Has-Many 关系 | FR5 | 一对多关系（User → Posts） |
| 10 | 10_relations_many_to_many.zig | Many-to-Many 关系 | FR5 | 多对多关系（Post ↔ Tags） |
| 12 | 12_batch_operations.zig | 批量操作 | FR2 | 批量插入/更新/UPSERT |
| 14 | 14_type_mapping.zig | 类型映射 | FR7 | PostgreSQL ↔ Zig 类型 |
| 15 | 15_error_handling.zig | 错误处理 | FR8 | 约束违反、事务回滚 |
| 17 | 17_connection_pool.zig | 连接池 | FR1 | 连接池配置和管理 |
| 18 | 18_raw_sql.zig | 原始 SQL | FR10 | 直接执行 SQL + 防注入 |
| 19 | 19_pagination.zig | 分页查询 | FR11 | OFFSET/LIMIT 和 Cursor |

### 🔴 高级篇 (第5-6天)

| 编号 | 文件名 | 标题 | 功能需求 | 说明 |
|------|--------|------|----------|------|
| 11 | 11_schema_migrations.zig | Schema 迁移 | FR6 | 迁移版本管理和执行 |
| 13 | 13_advanced_queries.zig | 高级查询 | FR3 | CTE、窗口函数、CASE |
| 16 | 16_hooks_system.zig | Hooks 系统 | FR9 | 查询钩子、日志、审计 |
| 20 | 20_aggregation.zig | 聚合查询 | FR12 | COUNT、SUM、GROUP BY、HAVING |

## 🎓 推荐学习路径

### 初学者路径 (3-5天)
1. **Day 1**: 示例 00-05 (环境设置 + CRUD)
   - 先运行 00_setup_database 初始化数据库
   - 学习 01_basic_connection 理解连接管理
   - 掌握 02-05 的基本 CRUD 操作

2. **Day 2**: 示例 06-07, 15, 18 (查询构建 + 事务 + 错误处理)
   - 学习查询构建器的链式 API
   - 理解事务的 ACID 特性
   - 掌握错误处理最佳实践

3. **Day 3**: 示例 08-10 (关系映射)
   - 理解表之间的关系类型
   - 学习如何避免 N+1 查询问题
   - 掌握关系数据的查询技巧

4. **Day 4-5**: 根据兴趣选择中级示例
   - 连接池管理 (17)
   - 分页查询 (19)
   - 类型映射 (14)

### 进阶路径 (1-2周)
1. 完成初学者路径
2. 学习高级查询 (示例 13)
3. 学习 Schema 迁移 (示例 11)
4. 学习钩子系统 (示例 16)
5. 实践项目：构建一个完整的博客系统

## 🔧 常见问题

### Q: 数据库连接失败？
A: 检查 PostgreSQL 服务是否启动，连接参数是否正确。可以通过以下命令测试：
```bash
psql -h 127.0.0.1 -p 5432 -U pguser -d postgres
```

### Q: 权限不足错误 (permission denied)？
A: 确保数据库用户有足够的权限创建 schema。以超级用户身份连接并授权：
```sql
-- 以 postgres 超级用户身份连接
psql -h 127.0.0.1 -p 5432 -U postgres -d postgres

-- 授予创建 schema 的权限
GRANT CREATE ON DATABASE postgres TO pguser;

-- 或者创建一个新的数据库并授予所有权限
CREATE DATABASE zorm_examples OWNER pguser;
```

然后修改环境变量使用新数据库：
```bash
export ZORM_DB_NAME=zorm_examples
```

### Q: 示例运行报错？
A: 确保已运行 `00_setup_database.zig` 初始化数据库。如果已运行但仍报错，可以重新运行该脚本（具有幂等性）。

### Q: 如何重置数据库？
A: 重新运行 `00_setup_database.zig`，脚本会自动处理已存在的表（使用 `IF NOT EXISTS`）。如需完全重置，可手动删除 schema：
```sql
DROP SCHEMA IF EXISTS zorm_examples CASCADE;
```
然后重新运行初始化脚本。

### Q: 如何调试示例代码？
A: 使用 `std.debug.print` 输出中间结果。你也可以在代码中添加断点（使用 `@breakpoint()`）并使用 GDB/LLDB 调试。

### Q: 环境变量不生效？
A: 确保在运行 `zig build` 命令之前设置环境变量。你可以这样运行：
```bash
ZORM_DB_HOST=localhost zig build run-example -Dexample=00_setup_database
```

## 📖 相关资源

- [ZORM 功能规格说明书](../docs/functional_spec.md)
- [ZORM 架构文档](../docs/architecture.md)
- [Zig 官方文档](https://ziglang.org/documentation/)
- [PostgreSQL 官方文档](https://www.postgresql.org/docs/)
- [pg.zig GitHub](https://github.com/karlseguin/pg.zig)

## 🏗️ 项目结构

```
examples/
├── common/              # 共享基础设施
│   ├── models.zig      # 数据模型定义
│   ├── db_config.zig   # 数据库配置
│   └── test_helpers.zig # 测试辅助函数
├── 00_setup_database.zig
├── 01_basic_connection.zig
├── ... (其他示例文件)
└── README.md           # 本文件
```

## 🤝 贡献

发现问题或有改进建议？欢迎提交 Issue 或 Pull Request！

## 📝 博客系统数据模型

所有示例使用统一的博客系统数据模型：

- **users** - 用户表
- **posts** - 文章表
- **comments** - 评论表
- **tags** - 标签表
- **post_tags** - 文章标签关联表（多对多）

详细的表结构定义请参考 `examples/common/models.zig` 和 `00_setup_database.zig`。

---

**开始学习 ZORM 之旅吧！** 🚀
