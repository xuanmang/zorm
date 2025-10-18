# ZORM Schema 配置指南

## 📚 概述

ZORM 支持三种方式配置数据库 schema：

1. **默认配置** - 使用 PostgreSQL 默认的 `public` schema
2. **代码配置** - 在代码中指定自定义 schema
3. **环境变量** - 通过环境变量动态配置

---

## 🎯 方式1: 默认配置（public schema）

最简单的方式，使用 PostgreSQL 默认的 `public` schema。

### 代码示例

```zig
const config = db_config.getDefaultConfig();
var db = try db_config.createDBInstance(allocator, config);
defer db.deinit();

// 表将创建在 public schema
try db_config.initSchema(db, config.schema, true);
```

### 使用方法

在 `examples/00_setup_database.zig` 中：

```zig
// 方式1: 使用默认配置（public schema）
const config = db_config.getDefaultConfig();
```

### 查询数据

```sql
-- 直接使用表名（默认在 public schema）
SELECT * FROM users;
SELECT * FROM posts;
```

---

## 🎯 方式2: 代码配置自定义 schema

在代码中显式指定要使用的 schema。

### 代码示例

```zig
const config = db_config.getConfigWithSchema("myapp");
var db = try db_config.createDBInstance(allocator, config);
defer db.deinit();

// 表将创建在 myapp schema
try db_config.initSchema(db, config.schema, true);
```

### 使用方法

在 `examples/00_setup_database.zig` 中修改第 133 行：

```zig
// 方式2: 使用自定义 schema
const config = db_config.getConfigWithSchema("zorm_examples");
```

### 输出示例

```
=== ZORM 数据库初始化 ===

连接到 PostgreSQL...
✓ 数据库连接成功

初始化 schema: zorm_examples
✓ Schema 'zorm_examples' 初始化完成

创建数据表（zorm_examples schema）...
  ✓ users
  ✓ posts
  ✓ comments
  ✓ tags
  ✓ post_tags
✓ 所有表创建成功
```

### 查询数据

```sql
-- 方式1: 使用完整表名
SELECT * FROM zorm_examples.users;

-- 方式2: 设置 search_path（连接时已自动设置）
SELECT * FROM users;  -- 自动查找 zorm_examples.users
```

---

## 🎯 方式3: 环境变量配置

通过环境变量动态配置，无需修改代码。

### 设置环境变量

```bash
# Linux/macOS
export DB_SCHEMA=myapp

# Windows PowerShell
$env:DB_SCHEMA="myapp"

# Windows CMD
set DB_SCHEMA=myapp
```

### 代码示例

```zig
const config = db_config.getConfigFromEnv();
var db = try db_config.createDBInstance(allocator, config);
defer db.deinit();

// 使用环境变量指定的 schema
try db_config.initSchema(db, config.schema, true);
```

### 使用方法

在 `examples/00_setup_database.zig` 中修改第 136 行：

```zig
// 方式3: 从环境变量读取 (export DB_SCHEMA=myapp)
const config = db_config.getConfigFromEnv();
```

### 运行示例

```bash
# 使用 myapp schema
export DB_SCHEMA=myapp
zig build run-setup

# 使用 production schema
export DB_SCHEMA=production
zig build run-setup

# 使用默认 public schema（不设置环境变量）
unset DB_SCHEMA
zig build run-setup
```

---

## 🛠️ Schema 管理函数

### initSchema()

初始化 schema 并设置 search_path。

```zig
/// 参数:
/// - db: 数据库连接
/// - schema_name: schema 名称，null 表示使用 public
/// - drop_if_exists: 是否先删除已存在的 schema
pub fn initSchema(
    db: anytype,
    schema_name: ?[]const u8,
    drop_if_exists: bool,
) !void
```

#### 示例

```zig
// 创建并使用 myapp schema（保留旧数据）
try db_config.initSchema(db, "myapp", false);

// 重建 myapp schema（删除旧数据）
try db_config.initSchema(db, "myapp", true);

// 使用 public schema（不做任何操作）
try db_config.initSchema(db, null, false);
```

### getConfigWithSchema()

创建带自定义 schema 的配置。

```zig
pub fn getConfigWithSchema(schema_name: ?[]const u8) DBConfig
```

#### 示例

```zig
// 使用 myapp schema
const config1 = db_config.getConfigWithSchema("myapp");

// 使用 public schema
const config2 = db_config.getConfigWithSchema(null);
```

### getConfigFromEnv()

从环境变量读取配置。

```zig
pub fn getConfigFromEnv() DBConfig
```

#### 环境变量

- `DB_SCHEMA`: schema 名称（可选，未设置时使用 public）

---

## 📊 实际应用场景

### 场景1: 开发环境隔离

```zig
// 开发环境
const config = db_config.getConfigWithSchema("dev");

// 测试环境
const config = db_config.getConfigWithSchema("test");

// 生产环境
const config = db_config.getConfigWithSchema("prod");
```

### 场景2: 多租户应用

```zig
// 为每个租户创建独立 schema
const tenant_id = "tenant_123";
const config = db_config.getConfigWithSchema(tenant_id);
```

### 场景3: 功能模块隔离

```zig
// 用户管理模块
const config = db_config.getConfigWithSchema("user_module");

// 订单管理模块
const config = db_config.getConfigWithSchema("order_module");
```

### 场景4: CI/CD 流水线

```bash
#!/bin/bash

# 根据分支设置不同的 schema
if [ "$GIT_BRANCH" = "main" ]; then
    export DB_SCHEMA=production
elif [ "$GIT_BRANCH" = "develop" ]; then
    export DB_SCHEMA=development
else
    export DB_SCHEMA="feature_${GIT_BRANCH}"
fi

# 运行数据库初始化
zig build run-setup
```

---

## ⚠️ 注意事项

### 1. Schema 权限

确保数据库用户有创建 schema 的权限：

```sql
-- 授予创建 schema 权限
GRANT CREATE ON DATABASE postgres TO pguser;

-- 授予使用 schema 权限
GRANT USAGE ON SCHEMA myapp TO pguser;
GRANT ALL ON ALL TABLES IN SCHEMA myapp TO pguser;
```

### 2. Search Path

`initSchema()` 会自动设置 search_path：

```sql
SET search_path TO myapp, public;
```

这意味着：
- 首先在 `myapp` schema 中查找表
- 如果未找到，再在 `public` schema 中查找

### 3. 删除数据

使用 `drop_if_exists = true` 会**删除整个 schema 及其所有数据**：

```zig
// ⚠️ 这会删除所有数据！
try db_config.initSchema(db, "myapp", true);
```

生产环境建议：
```zig
// ✅ 保留数据，只创建不存在的表
try db_config.initSchema(db, "myapp", false);
```

---

## 🔍 验证 Schema

### 查看当前 search_path

```sql
SHOW search_path;
```

### 列出所有 schema

```sql
SELECT schema_name
FROM information_schema.schemata
ORDER BY schema_name;
```

### 查看指定 schema 中的表

```sql
\dt myapp.*
```

或

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'myapp';
```

---

## 📝 完整示例

```zig
const std = @import("std");
const db_config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 选择配置方式
    const config = db_config.getConfigWithSchema("myapp");
    // const config = db_config.getConfigFromEnv();
    // const config = db_config.getDefaultConfig();

    // 连接数据库
    var db = try db_config.createDBInstance(allocator, config);
    defer db.deinit();

    // 初始化 schema
    try db_config.initSchema(db, config.schema, true);

    // 创建表（会在指定的 schema 中创建）
    // ...

    std.debug.print("✅ 完成！\n", .{});
}
```

---

## 🎓 总结

| 方式 | 优点 | 适用场景 |
|------|------|----------|
| 默认配置 | 最简单 | 简单应用、快速开发 |
| 代码配置 | 明确可控 | 固定 schema、模块化应用 |
| 环境变量 | 灵活动态 | CI/CD、多环境部署 |

选择建议：
- 🟢 **小型项目**: 使用默认 public schema
- 🟡 **中型项目**: 代码配置固定 schema
- 🔴 **大型项目**: 环境变量 + 多 schema 隔离
