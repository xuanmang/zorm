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
- ✅ 查询钩子系统
- ✅ Schema 类型映射
- ✅ 构建系统 (build.zig)

**待实现:**
- 🔨 数据库驱动实现 (libpq, libmysqlclient, sqlite3)
- 🔨 完整的结果扫描和序列化
- 🔨 关系映射 (Belongs-To, Has-Many, Many-to-Many)
- 🔨 Schema 迁移系统
- 🔨 连接池管理
- 🔨 事务隔离级别
- 🔨 预编译语句缓存

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

## 📚 文档

详细文档请参阅:
- [功能需求规格说明书](docs/functional_spec.md) - 完整的功能定义和 API 设计
- [API 文档](zig-out/docs/index.html) - 通过 `zig build docs` 生成

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
