# ZORM Schema 配置快速开始

## 🎯 三种配置方式

ZORM 提供了三种灵活的方式来指定数据库 schema：

---

## 方式1: 使用默认 public schema（最简单）

适合：快速开发、小型项目

```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 使用默认配置（public schema）
    var config = zorm.config.DBConfig.default();
    var db = try config.connect(allocator);
    defer db.deinit();

    // 表将创建在 public schema
    // 查询: SELECT * FROM users;
}
```

---

## 方式2: 代码中指定自定义 schema

适合：固定schema、模块化应用

```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 手动配置 schema
    var config = zorm.config.DBConfig{
        .host = "127.0.0.1",
        .port = 5432,
        .user = "pguser",
        .password = "Pg#123!",
        .dbname = "postgres",
        .schema = "myapp",  // ✨ 指定 schema
    };

    var db = try config.connect(allocator);
    defer db.deinit();

    // 初始化 schema（创建并设置 search_path）
    try zorm.config.initSchema(db, config.schema, true);

    // 表将创建在 myapp schema
    // 查询: SELECT * FROM myapp.users;
    // 或者: SELECT * FROM users;  (search_path 已设置)
}
```

---

## 方式3: 环境变量配置（推荐生产环境）

适合：CI/CD、多环境部署、灵活配置

### 设置环境变量

```bash
# Linux/macOS
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=pguser
export DB_PASSWORD=Pg#123!
export DB_NAME=mydb
export DB_SCHEMA=production  # 可选，不设置则使用 public
```

```powershell
# Windows PowerShell
$env:DB_HOST="localhost"
$env:DB_PORT="5432"
$env:DB_USER="pguser"
$env:DB_PASSWORD="Pg#123!"
$env:DB_NAME="mydb"
$env:DB_SCHEMA="production"
```

### 代码

```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 从环境变量读取配置
    var config = try zorm.config.DBConfig.fromEnv(allocator);
    defer config.deinit(allocator);  // 释放环境变量分配的内存

    var db = try config.connect(allocator);
    defer db.deinit();

    // 初始化 schema
    try zorm.config.initSchema(db, config.schema, false);

    // schema 由环境变量决定
}
```

### 运行

```bash
# 开发环境
export DB_SCHEMA=development
zig build run

# 测试环境
export DB_SCHEMA=test
zig build test

# 生产环境
export DB_SCHEMA=production
zig build run
```

---

## 🛠️ Schema 管理

### initSchema() 函数

创建 schema 并设置 search_path：

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

### 示例

```zig
// 创建 myapp schema（保留旧数据）
try zorm.config.initSchema(db, "myapp", false);

// 重建 myapp schema（⚠️ 删除所有旧数据）
try zorm.config.initSchema(db, "myapp", true);

// 使用 public schema（不做任何操作）
try zorm.config.initSchema(db, null, false);
```

---

## 📊 实际应用场景

### 场景1: 多环境隔离

```bash
# .env.development
DB_SCHEMA=dev

# .env.test
DB_SCHEMA=test

# .env.production
DB_SCHEMA=prod
```

### 场景2: 多租户应用

```zig
fn connectTenant(allocator: Allocator, tenant_id: []const u8) !*DB(.postgresql) {
    var config = zorm.config.DBConfig{
        .host = "localhost",
        .user = "app_user",
        .dbname = "multi_tenant",
        .schema = tenant_id,  // 每个租户一个 schema
    };

    var db = try config.connect(allocator);
    try zorm.config.initSchema(db, config.schema, false);
    return db;
}

// 使用
var tenant1_db = try connectTenant(allocator, "tenant_123");
var tenant2_db = try connectTenant(allocator, "tenant_456");
```

### 场景3: 功能模块隔离

```zig
// 用户模块
var user_db = try connectWithSchema(allocator, "user_module");

// 订单模块
var order_db = try connectWithSchema(allocator, "order_module");

// 产品模块
var product_db = try connectWithSchema(allocator, "product_module");
```

---

## ⚠️ 注意事项

### 1. 数据库权限

确保用户有创建 schema 的权限：

```sql
-- 授予创建权限
GRANT CREATE ON DATABASE mydb TO myuser;

-- 授予使用权限
GRANT USAGE ON SCHEMA myapp TO myuser;
GRANT ALL ON ALL TABLES IN SCHEMA myapp TO myuser;
```

### 2. Search Path

`initSchema()` 会自动设置：

```sql
SET search_path TO myapp, public;
```

之后可以直接使用表名：

```zig
// 这两种方式等价
var users1 = try db.query("SELECT * FROM myapp.users", &.{});
var users2 = try db.query("SELECT * FROM users", &.{});  // ✅ 推荐
```

### 3. 删除数据警告

使用 `drop_if_exists = true` 会删除整个 schema：

```zig
// ⚠️ 危险！会删除所有数据
try zorm.config.initSchema(db, "myapp", true);

// ✅ 安全：只创建不存在的表
try zorm.config.initSchema(db, "myapp", false);
```

---

## 🔍 验证和故障排查

### 查看当前 search_path

```sql
SHOW search_path;
-- 输出: myapp, public
```

### 列出所有 schema

```sql
SELECT schema_name FROM information_schema.schemata;
```

### 查看指定 schema 中的表

```sql
-- psql 命令
\dt myapp.*

-- SQL 查询
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'myapp';
```

### 常见问题

**Q: 为什么找不到表？**
```sql
-- 检查表在哪个 schema
SELECT schemaname, tablename
FROM pg_tables
WHERE tablename = 'users';

-- 检查 search_path
SHOW search_path;
```

**Q: 权限不足？**
```sql
-- 查看用户权限
SELECT * FROM information_schema.role_table_grants
WHERE grantee = current_user;
```

---

## 📚 完整示例

查看完整的使用示例和说明：
- `examples/00_setup_database.zig` - 数据库初始化脚本
- `examples/schema_example.md` - 详细配置指南

---

## 🎓 总结

| 方式 | 优点 | 适用场景 |
|------|------|----------|
| 默认 public | 最简单 | 快速开发、小型项目 |
| 代码配置 | 明确可控 | 固定 schema、模块化应用 |
| 环境变量 | 灵活动态 | CI/CD、多环境部署、生产环境 |

**推荐实践**：
- 🟢 开发：默认 public 或代码配置
- 🟡 测试：环境变量 + 独立 schema
- 🔴 生产：环境变量 + 权限管理

---

需要更多帮助？查看 `examples/schema_example.md` 获取详细说明！
