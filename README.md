# ZORM

**ZORM** 是一个受 [Bun ORM](https://github.com/uptrace/bun) 启发，专为 Zig 语言设计的 SQL-first ORM 库。

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Zig Version](https://img.shields.io/badge/zig-0.15.2+-orange.svg)](https://ziglang.org/)
[![Status](https://img.shields.io/badge/status-alpha-yellow.svg)]()

## ✨ 核心特性

- **🚀 零开销抽象** - 使用 `comptime` 实现编译时多态，无运行时性能损失
- **🔒 类型安全** - 强类型查询构建器，编译时检查 SQL 正确性
- **💾 显式内存管理** - Allocator 模式，完全控制内存分配，无 GC
- **🎯 SQL-First** - 直接生成优化的 SQL，完全控制查询
- **🌍 多数据库支持** - PostgreSQL, MySQL, SQLite
- **⚡ 高性能** - 接近原生 C 性能，零动态分派
- **🛠️ 强制错误处理** - Error union 类型，所有错误必须处理

## 📋 项目状态

> ⚠️ **Alpha 阶段**: 当前项目处于早期开发阶段，API 可能会发生变化。

**已完成:**
- ✅ 核心架构设计
- ✅ Dialect 系统 (comptime 特性检测)
- ✅ DB 连接管理接口
- ✅ 查询构建器框架 (SelectQuery, InsertQuery, UpdateQuery, DeleteQuery)
- ✅ 查询钩子系统 (Logging, Performance, Custom Hooks)
- ✅ Schema 类型映射 (CREATE TABLE, DROP TABLE, CREATE/DROP INDEX)
- ✅ 事务管理 (BEGIN, COMMIT, ROLLBACK, 隔离级别)
- ✅ JOIN 查询 (INNER, LEFT, RIGHT, 多表 JOIN)
- ✅ UPSERT (ON CONFLICT DO NOTHING/UPDATE)
- ✅ 子查询支持 (WHERE IN/NOT IN/EXISTS/NOT EXISTS, FROM 派生表)
- ✅ GROUP BY 和聚合函数
- ✅ 构建系统和示例程序
- ✅ 性能基准测试框架

**待实现:**
- 🔨 完整的结果扫描和序列化
- 🔨 关系映射 (Belongs-To, Has-Many, Many-to-Many)
- 🔨 Schema 迁移系统
- 🔨 连接池管理
- 🔨 预编译语句缓存

## 🚀 快速开始

### 安装

在 `build.zig.zon` 中添加依赖:

```zig
.dependencies = .{
    .zorm = .{
        .url = "https://github.com/yourusername/zorm/archive/main.tar.gz",
        .hash = "...",
    },
},
```

### 基础用法

```zig
const std = @import("std");
const zorm = @import("zorm");

// 定义模型
const User = struct {
    id: i64 = 0,
    name: []const u8,
    email: []const u8,
    age: i32,

    pub const table_name = "users";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 连接数据库 (示例,需要实际驱动)
    // const db = try zorm.DB(.postgresql).init(allocator, conn, .{});
    // defer db.deinit();

    // 2. 构建查询
    var query = zorm.SelectQuery(User, .postgresql).init(allocator);
    defer query.deinit();

    try query.column("id");
    try query.column("name");
    try query.column("email");
    try query.where("age", .gte, 18);
    try query.orderBy("name", .asc);
    query.limit(10);

    const sql = try query.buildSQL();
    defer allocator.free(sql);

    // 输出: SELECT id, name, email FROM users WHERE age >= $1 ORDER BY name ASC LIMIT 10
    std.debug.print("SQL: {s}\n", .{sql});
}
```

### 运行示例

```bash
# 基础 CRUD 操作
zig build run-example-basic

# 事务管理
zig build run-example-transaction

# JOIN 查询
zig build run-example-join

# UPSERT 操作
zig build run-example-upsert

# 查询钩子
zig build run-example-hooks

# Schema 管理
zig build run-example-schema

# 编译所有示例
zig build examples
```

### 运行测试

```bash
# 运行所有测试
zig build test

# 运行性能基准测试
zig build bench
```

### 生成文档

```bash
# 生成 HTML 文档
zig build docs

# 文档输出在 zig-out/docs/
```

## 🏗️ 架构设计

ZORM 基于以下设计原则:

### 1. Comptime 泛型系统

```zig
// 方言特性在编译时检查,零运行时开销
pub fn supports(comptime self: Dialect, comptime feature: Feature) bool {
    return comptime switch (self) {
        .postgresql => switch (feature) {
            .returning => true,
            .jsonb => true,
            // ...
        },
        // ...
    };
}
```

### 2. 显式内存管理

```zig
// 所有分配都通过 Allocator
var db = try DB.init(allocator, conn, .postgresql, .{});
defer db.deinit(); // 显式释放资源
```

### 3. 强制错误处理

```zig
// 所有可能失败的操作返回 error union
pub fn scanOne(self: *Self) !T {
    // 错误必须处理或传播
    const result = try self.db.query(query_str, args);
    // ...
}
```

## 📦 快速开始

### 安装

在 `build.zig.zon` 中添加依赖:

```zig
.dependencies = .{
    .zorm = .{
        .url = "https://github.com/xuanmang/zorm/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "...",
    },
},
```

### 基本使用

```zig
const std = @import("std");
const zorm = @import("zorm");

const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建数据库连接
    var db = try zorm.DB.open(allocator, .{
        .dialect = .postgresql,
        .dsn = "postgres://user:pass@localhost/mydb",
    });
    defer db.close();

    // 构建查询
    var query = try db.newSelect(User);
    defer query.deinit();

    _ = try query
        .column("id")
        .column("name")
        .column("email")
        .where("email LIKE ?", .{"%@example.com"})
        .orderBy("created_at DESC")
        .limit(10);

    // 执行查询
    const users = try query.scan();
    defer allocator.free(users);

    for (users) |user| {
        std.debug.print("User: {s} <{s}>\n", .{ user.name, user.email });
    }
}
```

### 钩子系统 (Hooks)

ZORM 提供了灵活的钩子系统用于查询可观测性、日志记录和性能追踪：

```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = try zorm.DB.open(allocator, .{
        .dialect = .postgresql,
        .dsn = "postgres://user:pass@localhost/mydb",
    });
    defer db.close();

    // 1. 添加日志钩子 - 记录所有查询
    var logger = zorm.LoggingHook.init(allocator);
    defer logger.deinit();
    try db.addHook(&logger.hook);

    // 2. 添加性能钩子 - 追踪慢查询
    var perf_hook = zorm.PerformanceHook.init(allocator, .{
        .slow_query_threshold_ms = 100, // 100ms 阈值
    });
    defer perf_hook.deinit();
    try db.addHook(&perf_hook.hook);

    // 执行查询 - 钩子会自动触发
    var query = try db.newSelect(User);
    defer query.deinit();
    const users = try query.scan();
    defer allocator.free(users);

    // 获取性能统计
    const stats = perf_hook.getStats();
    std.debug.print("总查询数: {}\n", .{stats.total_queries});
    std.debug.print("平均耗时: {}ms\n", .{stats.avg_duration_ms});
    std.debug.print("慢查询数: {}\n", .{stats.slow_queries});
}
```

**内置钩子:**
- `LoggingHook` - 查询日志记录
- `PerformanceHook` - 性能统计和慢查询检测
- `HookChain` - 组合多个钩子

**自定义钩子:**

```zig
const MyHook = struct {
    hook: zorm.QueryHook,

    pub fn init(allocator: std.mem.Allocator) MyHook {
        return .{
            .hook = .{
                .ptr = undefined,
                .beforeQueryFn = beforeQuery,
                .afterQueryFn = afterQuery,
                .onErrorFn = onError,
            },
        };
    }

    fn beforeQuery(ptr: *anyopaque, query: []const u8, args: []const zorm.Value) void {
        // 查询执行前的逻辑
    }

    fn afterQuery(ptr: *anyopaque, query: []const u8, duration_ns: u64) void {
        // 查询执行后的逻辑
    }

    fn onError(ptr: *anyopaque, query: []const u8, err: anyerror) void {
        // 错误处理逻辑
    }
};
```

## 🔧 构建和测试

```bash
# 构建项目
zig build

# 运行测试
zig build test

# 运行示例
zig build run-example

# 生成文档
zig build docs

# 格式化代码
zig build fmt

# 检查格式
zig build fmt-check
```

### 构建选项

```bash
# 启用特定数据库支持
zig build -Dpostgres=true   # PostgreSQL (默认: true)
zig build -Dmysql=true      # MySQL (默认: true)
zig build -Dsqlite=true     # SQLite (默认: true)

# 优化级别
zig build -Doptimize=ReleaseFast  # 最快速度
zig build -Doptimize=ReleaseSafe  # 安全检查
zig build -Doptimize=ReleaseSmall # 最小体积
```

## 📚 文档和资源

### 官方文档
- [功能需求规格说明书](docs/functional_spec.md) - 完整的功能定义和 API 设计
- [API 文档](zig-out/docs/index.html) - 通过 `zig build docs` 生成

### 示例程序
所有示例位于 `examples/` 目录:
- [basic.zig](examples/basic.zig) - 基础 CRUD 操作示例
- [transaction.zig](examples/transaction.zig) - 事务管理示例
- [join.zig](examples/join.zig) - JOIN 查询示例
- [upsert.zig](examples/upsert.zig) - UPSERT (ON CONFLICT) 示例
- [hooks.zig](examples/hooks.zig) - 查询钩子示例
- [schema.zig](examples/schema.zig) - Schema 管理示例

### 性能基准测试
- [benchmarks/](benchmarks/) - 性能基准测试套件
- [基准测试说明](benchmarks/README.md) - 性能目标和测试方法

## 🎯 设计理念

### SQL-First 方法

ZORM 采用 SQL-First 而非 Active Record 模式:

```zig
// ✅ 推荐: 显式 SQL 构建
var query = try db.newSelect(User);
_ = try query.where("age > ? AND status = ?", .{ 18, "active" });

// ❌ 不推荐: 隐式查询 (Active Record)
// users = User.where(age > 18, status = "active")
```

**原因:**
- SQL 是声明式的,表达力强
- 开发者完全控制查询性能
- 避免 N+1 查询等性能陷阱
- 更容易调试和优化

### Comptime > Runtime

ZORM 最大化使用编译时计算:

```zig
// 方言差异在编译时解决
const placeholder = comptime Dialect.postgresql.placeholder(1); // "$1"

// 特性检测在编译时完成
if (comptime dialect.supports(.returning)) {
    // 编译时条件分支
}
```

**优势:**
- 零运行时分支判断
- 更好的优化机会
- 更小的二进制大小
- 编译时错误检查

## 🤝 贡献

欢迎贡献! 请查看 [CONTRIBUTING.md](CONTRIBUTING.md) 了解详情。

## 📄 许可证

本项目采用 Apache 2.0 许可证 - 详见 [LICENSE](LICENSE) 文件。

## 🙏 致谢

- [Bun ORM](https://github.com/uptrace/bun) - 设计灵感来源
- [Zig](https://ziglang.org/) - 优秀的系统编程语言
- 所有贡献者

## 📞 联系方式

- **Issues**: [GitHub Issues](https://github.com/xuanmang/zorm/issues)
- **Discussions**: [GitHub Discussions](https://github.com/xuanmang/zorm/discussions)

---

**Made with ❤️ and Zig**
