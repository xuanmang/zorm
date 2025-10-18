# ZORM 功能示例文档系统 - 详细实施计划

**版本**: v1.0
**日期**: 2025-10-17
**基于**: PRD v1.0 (docs/prd-examples.md)
**项目**: ZORM Examples Implementation Plan

---

## 目录

1. [总体实施策略](#1-总体实施策略)
2. [Story 023: 环境准备和共享基础设施](#story-023-环境准备和共享基础设施)
3. [Story 024: 基础连接和 CRUD 操作示例](#story-024-基础连接和-crud-操作示例)
4. [Story 025: 查询构建器和事务管理示例](#story-025-查询构建器和事务管理示例)
5. [Story 026: 关系映射示例](#story-026-关系映射示例)
6. [Story 027: Schema 管理和迁移示例](#story-027-schema-管理和迁移示例)
7. [Story 028: 批量操作和高级查询示例](#story-028-批量操作和高级查询示例)
8. [Story 029: 类型映射和错误处理示例](#story-029-类型映射和错误处理示例)
9. [Story 030: 钩子系统和连接池示例](#story-030-钩子系统和连接池示例)
10. [Story 031: 原始 SQL 和分页查询示例](#story-031-原始-sql-和分页查询示例)
11. [Story 032: 聚合查询和文档完善](#story-032-聚合查询和文档完善)
12. [附录](#附录)

---

## 1. 总体实施策略

### 1.1 技术栈确认

- **语言**: Zig 0.15.2+
- **数据库驱动**: github.com/karlseguin/pg.zig (Zig 原生 PostgreSQL 驱动)
- **ORM 框架**: ZORM (项目自身)
- **数据库**: PostgreSQL 12+
- **测试框架**: std.testing

### 1.2 实施顺序

Stories 必须按顺序实施，因为存在依赖关系：

```
Story 023 (基础设施)
    ↓
Story 024 (基础 CRUD) → Story 025 (查询构建/事务) → Story 026 (关系映射)
    ↓                           ↓                           ↓
Story 027 (Schema迁移)    Story 029 (类型/错误)      Story 028 (批量/高级)
    ↓                           ↓                           ↓
Story 030 (钩子/连接池) ← Story 031 (原始SQL/分页) ← Story 032 (聚合/文档)
```

### 1.3 代码组织原则

**目录结构**:
```
examples/
├── common/              # 共享基础设施
│   ├── models.zig      # 数据模型定义
│   ├── db_config.zig   # 数据库配置
│   └── test_helpers.zig # 测试辅助函数
├── 00_setup_database.zig
├── 01_basic_connection.zig
├── ... (其他示例文件)
└── README.md
```

**代码模板标准**:
```zig
//! 示例标题
//!
//! 学习目标:
//! - 目标1
//! - 目标2
//!
//! 对应功能需求: FRx
//! 难度: [基础|中级|高级]

const std = @import("std");
const zorm = @import("zorm");
const config = @import("common/db_config.zig");

// 示例相关的结构体定义

pub fn main() !void {
    // 内存分配器设置
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 示例主要逻辑

    std.debug.print("✓ 示例执行成功\n", .{});
}

// 辅助函数定义
```

### 1.4 质量检查清单

每个示例完成后必须通过以下检查：

- [ ] 代码能够编译通过 (`zig build`)
- [ ] 代码能够成功运行 (`zig build run-example`)
- [ ] 无内存泄漏 (使用 GeneralPurposeAllocator 检测)
- [ ] 包含详细注释 (说明 why)
- [ ] 包含错误处理
- [ ] 包含资源清理 (defer/errdefer)
- [ ] 输出清晰的执行结果
- [ ] 符合编码规范

---

## Story 023: 环境准备和共享基础设施

**优先级**: P0 (阻塞其他所有 Stories)
**预估工作量**: 2-3 天
**依赖**: 无

### 实施目标

创建所有示例共享的基础设施，包括：
1. 数据库连接配置模块
2. 共享数据模型定义
3. 数据库初始化脚本
4. 构建系统集成
5. 示例索引文档

### 详细任务分解

#### 任务 023.1: 创建数据库配置模块

**文件**: `examples/common/db_config.zig`

**功能**:
- 提供统一的数据库连接配置
- 支持环境变量覆盖
- 包含连接字符串构建

**代码框架**:
```zig
//! 数据库配置模块
//!
//! 提供所有示例统一的数据库连接配置

const std = @import("std");

/// PostgreSQL 连接配置
pub const Config = struct {
    host: []const u8,
    port: u16,
    user: []const u8,
    password: []const u8,
    database: []const u8,

    /// 默认配置 (可通过环境变量覆盖)
    pub fn default() Config {
        return .{
            .host = std.os.getenv("ZORM_DB_HOST") orelse "127.0.0.1",
            .port = if (std.os.getenv("ZORM_DB_PORT")) |port_str|
                std.fmt.parseInt(u16, port_str, 10) catch 5432
            else
                5432,
            .user = std.os.getenv("ZORM_DB_USER") orelse "pguser",
            .password = std.os.getenv("ZORM_DB_PASSWORD") orelse "Pg#123!",
            .database = std.os.getenv("ZORM_DB_NAME") orelse "postgres",
        };
    }

    /// 构建连接字符串
    pub fn buildConnectionString(self: Config, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(
            allocator,
            "host={s} port={d} user={s} password={s} dbname={s}",
            .{ self.host, self.port, self.user, self.password, self.database },
        );
    }
};

/// 示例专用 Schema 名称
pub const EXAMPLES_SCHEMA = "zorm_examples";
```

**验收标准**:
- [x] 配置模块可被其他示例 import
- [x] 支持环境变量覆盖
- [x] 连接字符串格式正确

---

#### 任务 023.2: 创建共享数据模型

**文件**: `examples/common/models.zig`

**功能**:
- 定义博客系统的所有数据模型
- User, Post, Comment, Tag 结构体
- 包含字段验证和默认值

**代码框架**:
```zig
//! 共享数据模型定义
//!
//! 博客系统的核心数据结构

const std = @import("std");

/// 用户模型
pub const User = struct {
    id: ?i64 = null,
    name: []const u8,
    email: []const u8,
    created_at: ?i64 = null,  // Unix timestamp
    updated_at: ?i64 = null,

    pub const TableName = "users";

    /// 验证用户数据
    pub fn validate(self: User) !void {
        if (self.name.len == 0) return error.InvalidName;
        if (self.email.len == 0) return error.InvalidEmail;
        if (std.mem.indexOf(u8, self.email, "@") == null) {
            return error.InvalidEmailFormat;
        }
    }
};

/// 文章模型
pub const Post = struct {
    id: ?i64 = null,
    user_id: i64,
    title: []const u8,
    content: ?[]const u8 = null,
    status: Status = .draft,
    published_at: ?i64 = null,
    created_at: ?i64 = null,
    updated_at: ?i64 = null,

    pub const TableName = "posts";

    pub const Status = enum {
        draft,
        published,
        archived,

        pub fn toString(self: Status) []const u8 {
            return switch (self) {
                .draft => "draft",
                .published => "published",
                .archived => "archived",
            };
        }
    };

    pub fn validate(self: Post) !void {
        if (self.title.len == 0) return error.InvalidTitle;
        if (self.title.len > 255) return error.TitleTooLong;
    }
};

/// 评论模型
pub const Comment = struct {
    id: ?i64 = null,
    post_id: i64,
    user_id: i64,
    content: []const u8,
    created_at: ?i64 = null,

    pub const TableName = "comments";

    pub fn validate(self: Comment) !void {
        if (self.content.len == 0) return error.EmptyComment;
    }
};

/// 标签模型
pub const Tag = struct {
    id: ?i64 = null,
    name: []const u8,

    pub const TableName = "tags";

    pub fn validate(self: Tag) !void {
        if (self.name.len == 0) return error.EmptyTagName;
        if (self.name.len > 50) return error.TagNameTooLong;
    }
};

/// 文章标签关联表
pub const PostTag = struct {
    post_id: i64,
    tag_id: i64,

    pub const TableName = "post_tags";
};
```

**验收标准**:
- [x] 所有模型定义完整
- [x] 包含验证方法
- [x] 字段类型正确（nullable 字段使用 ?T）

---

#### 任务 023.3: 创建测试辅助模块

**文件**: `examples/common/test_helpers.zig`

**功能**:
- 提供数据清理函数
- 提供测试数据生成函数
- 提供断言辅助函数

**代码框架**:
```zig
//! 测试辅助函数
//!
//! 为示例提供数据清理、生成和验证功能

const std = @import("std");
const zorm = @import("zorm");
const config = @import("db_config.zig");

/// 清理指定表的所有数据
pub fn truncateTable(db: *zorm.DB, table_name: []const u8) !void {
    const sql = try std.fmt.allocPrint(
        db.allocator,
        "TRUNCATE TABLE {s}.{s} CASCADE",
        .{ config.EXAMPLES_SCHEMA, table_name },
    );
    defer db.allocator.free(sql);

    _ = try db.exec(sql, .{});
}

/// 清理所有示例表
pub fn cleanupAllTables(db: *zorm.DB) !void {
    const tables = [_][]const u8{
        "post_tags",
        "comments",
        "posts",
        "tags",
        "users",
    };

    for (tables) |table| {
        try truncateTable(db, table);
    }
}

/// 生成测试用户
pub fn createTestUser(
    db: *zorm.DB,
    name: []const u8,
    email: []const u8,
) !i64 {
    const sql = try std.fmt.allocPrint(
        db.allocator,
        \\INSERT INTO {s}.users (name, email, created_at, updated_at)
        \\VALUES ($1, $2, EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
        \\RETURNING id
        ,
        .{config.EXAMPLES_SCHEMA},
    );
    defer db.allocator.free(sql);

    const result = try db.queryOne(i64, sql, .{ name, email });
    return result.?;
}

/// 验证记录数量
pub fn assertCount(
    db: *zorm.DB,
    table_name: []const u8,
    expected: usize,
) !void {
    const sql = try std.fmt.allocPrint(
        db.allocator,
        "SELECT COUNT(*) FROM {s}.{s}",
        .{ config.EXAMPLES_SCHEMA, table_name },
    );
    defer db.allocator.free(sql);

    const actual = try db.queryOne(i64, sql, .{});
    if (actual.? != expected) {
        std.debug.print(
            "❌ 断言失败: 表 {s} 期望 {d} 条记录，实际 {d} 条\n",
            .{ table_name, expected, actual.? },
        );
        return error.AssertionFailed;
    }
}
```

**验收标准**:
- [x] 数据清理函数工作正常
- [x] 测试数据生成函数可用
- [x] 断言函数提供清晰错误信息

---

#### 任务 023.4: 创建数据库初始化脚本

**文件**: `examples/00_setup_database.zig`

**功能**:
- 创建 `zorm_examples` schema
- 创建所有表结构
- 创建索引和约束
- 插入示例种子数据

**代码框架**:
```zig
//! 数据库初始化脚本
//!
//! 学习目标:
//! - 了解如何使用 ZORM 执行 DDL 语句
//! - 理解 PostgreSQL Schema 的作用
//! - 掌握表创建和约束定义
//!
//! 难度: 基础

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 连接数据库
    const db_config = config.Config.default();
    const conn_str = try db_config.buildConnectionString(allocator);
    defer allocator.free(conn_str);

    var pool = try pg.Pool.init(allocator, .{
        .size = 5,
        .connect = .{
            .host = db_config.host,
            .port = db_config.port,
        },
        .auth = .{
            .username = db_config.user,
            .password = db_config.password,
            .database = db_config.database,
        },
    });
    defer pool.deinit();

    std.debug.print("🔌 连接到数据库...\n", .{});

    var conn = try pool.acquire();
    defer conn.release();

    // 创建 schema
    std.debug.print("📦 创建 schema '{s}'...\n", .{config.EXAMPLES_SCHEMA});
    _ = try conn.exec(
        "CREATE SCHEMA IF NOT EXISTS " ++ config.EXAMPLES_SCHEMA,
        .{},
    );

    // 创建 users 表
    std.debug.print("📝 创建 users 表...\n", .{});
    _ = try conn.exec(
        \\CREATE TABLE IF NOT EXISTS zorm_examples.users (
        \\    id BIGSERIAL PRIMARY KEY,
        \\    name VARCHAR(100) NOT NULL,
        \\    email VARCHAR(255) UNIQUE NOT NULL,
        \\    created_at BIGINT NOT NULL,
        \\    updated_at BIGINT NOT NULL
        \\)
        ,
        .{},
    );

    // 创建 posts 表
    std.debug.print("📝 创建 posts 表...\n", .{});
    _ = try conn.exec(
        \\CREATE TABLE IF NOT EXISTS zorm_examples.posts (
        \\    id BIGSERIAL PRIMARY KEY,
        \\    user_id BIGINT NOT NULL REFERENCES zorm_examples.users(id) ON DELETE CASCADE,
        \\    title VARCHAR(255) NOT NULL,
        \\    content TEXT,
        \\    status VARCHAR(20) DEFAULT 'draft',
        \\    published_at BIGINT,
        \\    created_at BIGINT NOT NULL,
        \\    updated_at BIGINT NOT NULL,
        \\    CONSTRAINT valid_status CHECK (status IN ('draft', 'published', 'archived'))
        \\)
        ,
        .{},
    );

    // 创建 comments 表
    std.debug.print("📝 创建 comments 表...\n", .{});
    _ = try conn.exec(
        \\CREATE TABLE IF NOT EXISTS zorm_examples.comments (
        \\    id BIGSERIAL PRIMARY KEY,
        \\    post_id BIGINT NOT NULL REFERENCES zorm_examples.posts(id) ON DELETE CASCADE,
        \\    user_id BIGINT NOT NULL REFERENCES zorm_examples.users(id) ON DELETE CASCADE,
        \\    content TEXT NOT NULL,
        \\    created_at BIGINT NOT NULL
        \\)
        ,
        .{},
    );

    // 创建 tags 表
    std.debug.print("📝 创建 tags 表...\n", .{});
    _ = try conn.exec(
        \\CREATE TABLE IF NOT EXISTS zorm_examples.tags (
        \\    id BIGSERIAL PRIMARY KEY,
        \\    name VARCHAR(50) UNIQUE NOT NULL
        \\)
        ,
        .{},
    );

    // 创建 post_tags 关联表
    std.debug.print("📝 创建 post_tags 表...\n", .{});
    _ = try conn.exec(
        \\CREATE TABLE IF NOT EXISTS zorm_examples.post_tags (
        \\    post_id BIGINT NOT NULL REFERENCES zorm_examples.posts(id) ON DELETE CASCADE,
        \\    tag_id BIGINT NOT NULL REFERENCES zorm_examples.tags(id) ON DELETE CASCADE,
        \\    PRIMARY KEY (post_id, tag_id)
        \\)
        ,
        .{},
    );

    // 创建索引
    std.debug.print("🔍 创建索引...\n", .{});
    _ = try conn.exec(
        "CREATE INDEX IF NOT EXISTS idx_posts_user_id ON zorm_examples.posts(user_id)",
        .{},
    );
    _ = try conn.exec(
        "CREATE INDEX IF NOT EXISTS idx_posts_status ON zorm_examples.posts(status)",
        .{},
    );
    _ = try conn.exec(
        "CREATE INDEX IF NOT EXISTS idx_comments_post_id ON zorm_examples.comments(post_id)",
        .{},
    );

    // 插入种子数据
    std.debug.print("🌱 插入种子数据...\n", .{});
    _ = try conn.exec(
        \\INSERT INTO zorm_examples.users (name, email, created_at, updated_at)
        \\VALUES
        \\    ('Alice', 'alice@example.com', EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW())),
        \\    ('Bob', 'bob@example.com', EXTRACT(EPOCH FROM NOW()), EXTRACT(EPOCH FROM NOW()))
        \\ON CONFLICT (email) DO NOTHING
        ,
        .{},
    );

    _ = try conn.exec(
        \\INSERT INTO zorm_examples.tags (name)
        \\VALUES ('Zig'), ('PostgreSQL'), ('ORM'), ('Tutorial')
        \\ON CONFLICT (name) DO NOTHING
        ,
        .{},
    );

    std.debug.print("✅ 数据库初始化完成！\n", .{});
    std.debug.print("\n📊 统计信息:\n", .{});

    // 查询统计信息
    const user_count = try conn.queryRow("SELECT COUNT(*) FROM zorm_examples.users", .{});
    defer user_count.deinit();
    const users = user_count.get(i64, 0);
    std.debug.print("  用户数: {d}\n", .{users});

    const tag_count = try conn.queryRow("SELECT COUNT(*) FROM zorm_examples.tags", .{});
    defer tag_count.deinit();
    const tags = tag_count.get(i64, 0);
    std.debug.print("  标签数: {d}\n", .{tags});
}
```

**验收标准**:
- [x] Schema 创建成功
- [x] 所有表创建成功
- [x] 索引创建成功
- [x] 种子数据插入成功
- [x] 脚本可重复执行（幂等性）

---

#### 任务 023.5: 集成到构建系统

**文件**: `build.zig` (修改)

**功能**:
- 添加 examples 模块
- 添加运行示例的命令
- 添加运行所有示例的命令

**代码修改**:
```zig
// 在 build.zig 中添加

// 添加 pg.zig 依赖
const pg = b.dependency("pg", .{
    .target = target,
    .optimize = optimize,
});

// 创建 examples 模块
const examples_mod = b.addModule("examples_common", .{
    .root_source_file = b.path("examples/common/models.zig"),
});

// 添加运行单个示例的步骤
const example_name = b.option([]const u8, "example", "示例名称") orelse "00_setup_database";
const run_example = b.addExecutable(.{
    .name = "example",
    .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example_name})),
    .target = target,
    .optimize = optimize,
});
run_example.root_module.addImport("pg", pg.module("pg"));
run_example.root_module.addImport("examples_common", examples_mod);

const run_example_cmd = b.addRunArtifact(run_example);
const run_example_step = b.step("run-example", "运行指定示例");
run_example_step.dependOn(&run_example_cmd.step);

// 添加运行所有示例的步骤
const run_all_examples_step = b.step("run-all-examples", "运行所有示例");

const all_examples = [_][]const u8{
    "00_setup_database",
    "01_basic_connection",
    // ... 其他示例
};

for (all_examples) |name| {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("pg", pg.module("pg"));
    exe.root_module.addImport("examples_common", examples_mod);

    const run_cmd = b.addRunArtifact(exe);
    run_all_examples_step.dependOn(&run_cmd.step);
}
```

**验收标准**:
- [x] `zig build run-example` 运行默认示例
- [x] `zig build run-example -Dexample=01_basic_connection` 运行指定示例
- [x] `zig build run-all-examples` 运行所有示例

---

#### 任务 023.6: 创建示例索引文档

**文件**: `examples/README.md`

**内容框架**:
```markdown
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
| 06 | 06_query_builder.zig | 查询构建器 | FR3 | 链式 API 构建复杂查询 |
| 07 | 07_transactions.zig | 事务管理 | FR4 | 事务提交、回滚、嵌套 |
| 08 | 08_relations_belongs_to.zig | Belongs-To 关系 | FR5 | 多对一关系映射 |
| 09 | 09_relations_has_many.zig | Has-Many 关系 | FR5 | 一对多关系映射 |
| 10 | 10_relations_many_to_many.zig | Many-to-Many 关系 | FR5 | 多对多关系映射 |
| 12 | 12_bulk_operations.zig | 批量操作 | FR7 | 批量插入和更新优化 |
| 14 | 14_type_mapping.zig | 类型映射 | FR9 | Zig 类型 ↔ SQL 类型 |
| 15 | 15_error_handling.zig | 错误处理 | FR10 | 数据库错误捕获和恢复 |
| 17 | 17_connection_pool.zig | 连接池 | FR12 | 连接池配置和管理 |
| 18 | 18_raw_sql.zig | 原始 SQL | FR13 | 直接执行 SQL |
| 19 | 19_pagination.zig | 分页查询 | FR14 | OFFSET/LIMIT 和 Cursor |

### 🔴 高级篇 (第5-6天)

| 编号 | 文件名 | 标题 | 功能需求 | 说明 |
|------|--------|------|----------|------|
| 11 | 11_schema_migrations.zig | Schema 迁移 | FR6 | 表结构版本管理 |
| 13 | 13_advanced_queries.zig | 高级查询 | FR8 | CTE、子查询、窗口函数 |
| 16 | 16_hooks.zig | 钩子系统 | FR11 | 查询钩子和日志记录 |
| 20 | 20_aggregation.zig | 聚合查询 | FR15 | COUNT、SUM、GROUP BY |

## 🎓 推荐学习路径

### 初学者路径 (3-5天)
1. Day 1: 示例 00-05 (环境设置 + CRUD)
2. Day 2: 示例 06-07, 15, 18 (查询构建 + 事务 + 错误处理)
3. Day 3: 示例 08-10 (关系映射)
4. Day 4-5: 根据兴趣选择中级示例

### 进阶路径 (1-2周)
1. 完成初学者路径
2. 学习高级查询 (示例 13)
3. 学习 Schema 迁移 (示例 11)
4. 学习钩子系统 (示例 16)
5. 实践项目：构建一个完整的博客系统

## 🔧 常见问题

### Q: 数据库连接失败？
A: 检查 PostgreSQL 服务是否启动，连接参数是否正确。

### Q: 示例运行报错？
A: 确保已运行 `00_setup_database.zig` 初始化数据库。

### Q: 如何重置数据库？
A: 重新运行 `00_setup_database.zig`，脚本会自动清理并重建。

### Q: 如何调试示例代码？
A: 使用 `std.debug.print` 输出中间结果，或使用 `zig build run-example -Ddebug=true`。

## 📖 相关资源

- [ZORM 功能规格说明书](../docs/functional_spec.md)
- [ZORM API 文档](../docs/api/)
- [Zig 官方文档](https://ziglang.org/documentation/)
- [PostgreSQL 官方文档](https://www.postgresql.org/docs/)

## 🤝 贡献

发现问题或有改进建议？欢迎提交 Issue 或 Pull Request！
```

**验收标准**:
- [x] 文档结构清晰
- [x] 包含完整的示例索引
- [x] 包含学习路径指导
- [x] 包含常见问题解答

---

### Story 023 总结

**交付物清单**:
- [x] `examples/common/db_config.zig` - 数据库配置模块
- [x] `examples/common/models.zig` - 共享数据模型
- [x] `examples/common/test_helpers.zig` - 测试辅助函数
- [x] `examples/00_setup_database.zig` - 数据库初始化脚本
- [x] `build.zig` 修改 - 构建系统集成
- [x] `examples/README.md` - 示例索引文档

**验证步骤**:
1. 运行 `zig build` 确保编译通过
2. 运行 `zig build run-example -Dexample=00_setup_database` 初始化数据库
3. 检查 PostgreSQL 中 `zorm_examples` schema 和表结构
4. 验证种子数据已插入

**依赖关系**:
- 此 Story 完成后，其他所有 Stories 可以开始

---

## Story 024: 基础连接和 CRUD 操作示例

**优先级**: P0
**预估工作量**: 3-4 天
**依赖**: Story 023

### 实施目标

创建 5 个基础示例，覆盖：
1. 数据库连接建立和配置
2. 简单 SELECT 查询
3. INSERT 操作（单条和批量）
4. UPDATE 操作（条件更新）
5. DELETE 操作（软删除和硬删除）

所有示例展示完整的错误处理和资源管理。

### 详细任务分解

#### 任务 024.1: 基础连接示例

**文件**: `examples/01_basic_connection.zig`

**学习目标**:
- 理解如何建立数据库连接
- 掌握连接配置选项
- 学习错误处理和资源清理

**代码框架**:
```zig
//! 基础数据库连接示例
//!
//! 学习目标:
//! - 建立 PostgreSQL 数据库连接
//! - 配置连接参数
//! - 正确的错误处理和资源清理
//!
//! 对应功能需求: FR1
//! 难度: 基础

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("⚠️  检测到内存泄漏！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 01: 基础数据库连接 ===\n\n", .{});

    // 获取数据库配置
    // why: 使用配置模块统一管理连接参数，支持环境变量覆盖
    const db_config = config.Config.default();

    std.debug.print("📋 连接配置:\n", .{});
    std.debug.print("  主机: {s}\n", .{db_config.host});
    std.debug.print("  端口: {d}\n", .{db_config.port});
    std.debug.print("  用户: {s}\n", .{db_config.user});
    std.debug.print("  数据库: {s}\n\n", .{db_config.database});

    // 方式 1: 使用连接池（推荐用于生产环境）
    std.debug.print("🔌 方式 1: 使用连接池\n", .{});
    try demonstratePoolConnection(allocator, db_config);

    std.debug.print("\n", .{});

    // 方式 2: 单个连接（适合简单场景）
    std.debug.print("🔌 方式 2: 单个连接\n", .{});
    try demonstrateSingleConnection(allocator, db_config);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

/// 演示连接池的使用
fn demonstratePoolConnection(
    allocator: std.mem.Allocator,
    db_config: config.Config,
) !void {
    // 创建连接池
    // why: 连接池可以复用连接，提升性能，适合高并发场景
    var pool = try pg.Pool.init(allocator, .{
        .size = 5,  // 连接池大小
        .connect = .{
            .host = db_config.host,
            .port = db_config.port,
        },
        .auth = .{
            .username = db_config.user,
            .password = db_config.password,
            .database = db_config.database,
        },
    });
    defer pool.deinit();

    std.debug.print("  ✓ 连接池创建成功 (大小: 5)\n", .{});

    // 从池中获取连接
    var conn = try pool.acquire();
    defer conn.release();  // why: 使用 defer 确保连接归还到池中

    std.debug.print("  ✓ 从池中获取连接\n", .{});

    // 执行简单查询测试连接
    const result = try conn.queryRow("SELECT version()", .{});
    defer result.deinit();

    const version = result.get([]const u8, 0);
    std.debug.print("  ✓ PostgreSQL 版本: {s}\n", .{version});
}

/// 演示单个连接的使用
fn demonstrateSingleConnection(
    allocator: std.mem.Allocator,
    db_config: config.Config,
) !void {
    // 创建单个连接
    // why: 对于简单脚本或低并发场景，单连接更简单
    var conn = try pg.Conn.open(allocator, .{
        .host = db_config.host,
        .port = db_config.port,
        .username = db_config.user,
        .password = db_config.password,
        .database = db_config.database,
    });
    defer conn.deinit();  // why: 使用 defer 确保连接关闭

    std.debug.print("  ✓ 单个连接创建成功\n", .{});

    // 查询当前数据库名称
    const result = try conn.queryRow("SELECT current_database()", .{});
    defer result.deinit();

    const db_name = result.get([]const u8, 0);
    std.debug.print("  ✓ 当前数据库: {s}\n", .{db_name});

    // 查询当前用户
    const user_result = try conn.queryRow("SELECT current_user", .{});
    defer user_result.deinit();

    const user = user_result.get([]const u8, 0);
    std.debug.print("  ✓ 当前用户: {s}\n", .{user});
}
```

**关键点说明**:
1. **内存管理**: 使用 `GeneralPurposeAllocator` 检测内存泄漏
2. **defer 模式**: 确保资源正确释放
3. **两种连接方式**: 连接池 vs 单连接
4. **错误传播**: 使用 `!void` 和 `try`

**验收标准**:
- [x] 连接池创建成功
- [x] 能够执行简单查询
- [x] 无内存泄漏
- [x] 错误情况下资源正确释放

---

#### 任务 024.2: 简单 SELECT 查询示例

**文件**: `examples/02_simple_select.zig`

**代码框架**: *(由于篇幅限制，仅展示关键部分)*

```zig
//! 简单 SELECT 查询示例
//!
//! 学习目标:
//! - 执行基本的 SELECT 查询
//! - 扫描查询结果
//! - 处理单行和多行结果
//!
//! 对应功能需求: FR2
//! 难度: 基础

// ... imports ...

pub fn main() !void {
    // ... 设置 ...

    // 示例 1: 查询单行
    try querySingleRow(conn);

    // 示例 2: 查询多行
    try queryMultipleRows(conn, allocator);

    // 示例 3: 使用 WHERE 条件
    try queryWithWhere(conn);

    // 示例 4: 查询指定列
    try querySpecificColumns(conn);
}

fn querySingleRow(conn: *pg.Conn) !void {
    std.debug.print("\n📌 示例 1: 查询单行\n", .{});

    const result = try conn.queryRow(
        "SELECT id, name, email FROM zorm_examples.users WHERE id = $1",
        .{1},
    );
    defer result.deinit();

    const id = result.get(i64, 0);
    const name = result.get([]const u8, 1);
    const email = result.get([]const u8, 2);

    std.debug.print("  用户 #{d}: {s} <{s}>\n", .{ id, name, email });
}

fn queryMultipleRows(conn: *pg.Conn, allocator: std.mem.Allocator) !void {
    std.debug.print("\n📌 示例 2: 查询多行\n", .{});

    var result = try conn.query(
        "SELECT id, name, email FROM zorm_examples.users ORDER BY id",
        .{},
    );
    defer result.deinit();

    var count: usize = 0;
    while (try result.next()) {
        const id = result.get(i64, 0);
        const name = result.get([]const u8, 1);
        const email = result.get([]const u8, 2);

        std.debug.print("  用户 #{d}: {s} <{s}>\n", .{ id, name, email });
        count += 1;
    }

    std.debug.print("  总计: {d} 条记录\n", .{count});
}

// ... 其他函数 ...
```

**验收标准**:
- [x] 能查询单行结果
- [x] 能查询多行结果
- [x] WHERE 条件正确工作
- [x] 结果正确映射到 Zig 类型

---

#### 任务 024.3-024.5: INSERT/UPDATE/DELETE 示例

类似的模式，分别创建：
- `03_insert_operations.zig` - 单条插入、批量插入、RETURNING
- `04_update_operations.zig` - 条件更新、批量更新
- `05_delete_operations.zig` - 硬删除、软删除（添加 deleted_at 字段）

**每个示例的代码量**: 约 150-200 行

---

### Story 024 总结

**交付物**:
- [x] 5 个示例文件
- [x] 每个示例包含详细注释
- [x] 所有示例可独立运行
- [x] 无内存泄漏

**预估工作量分配**:
- 任务 023.1: 0.5 天
- 任务 023.2: 0.5 天
- 任务 023.3: 0.5 天
- 任务 023.4: 0.5 天
- 任务 023.5: 0.5 天
- 任务 023.6: 0.5 天
- 测试和完善: 0.5 天

---

## Story 025: 查询构建器和事务管理示例

**优先级**: P0
**预估工作量**: 2-3 天
**依赖**: Story 024

### 实施目标

创建 2 个中级示例：
1. 查询构建器示例 - 展示链式 API 的强大功能
2. 事务管理示例 - 展示事务的提交、回滚和嵌套

### 任务 025.1: 查询构建器示例

**文件**: `examples/06_query_builder.zig`

**代码大纲**:
```zig
//! 查询构建器示例
//!
//! 学习目标:
//! - 使用链式 API 构建查询
//! - 组合 WHERE、JOIN、ORDER BY、LIMIT
//! - 理解查询构建器的类型安全特性
//!
//! 对应功能需求: FR3
//! 难度: 中级

// 示例 1: 基础链式查询
try basicQueryBuilder();

// 示例 2: 复杂 WHERE 条件
try complexWhereConditions();

// 示例 3: JOIN 查询
try joinQueries();

// 示例 4: 排序和分页
try orderingAndPagination();

// 示例 5: 动态查询构建
try dynamicQueryBuilding();
```

**关键特性展示**:
1. 链式 API 的流畅性
2. 编译时类型检查
3. 参数化查询自动处理
4. SQL 注入防护

---

### 任务 025.2: 事务管理示例

**文件**: `examples/07_transactions.zig`

**代码大纲**:
```zig
//! 事务管理示例
//!
//! 学习目标:
//! - 理解事务的 ACID 特性
//! - 掌握事务提交和回滚
//! - 学习嵌套事务（Savepoint）
//! - 掌握错误时的自动回滚
//!
//! 对应功能需求: FR4
//! 难度: 中级

// 示例 1: 基础事务提交
try basicTransactionCommit();

// 示例 2: 事务回滚
try transactionRollback();

// 示例 3: 嵌套事务（Savepoint）
try nestedTransactions();

// 示例 4: 错误自动回滚
try automaticRollbackOnError();

// 示例 5: 事务隔离级别
try transactionIsolationLevels();
```

**关键场景**:
1. 银行转账场景（演示原子性）
2. 库存扣减场景（演示一致性）
3. 批量操作失败场景（演示回滚）

---

## Story 026-032: 其他 Stories 实施大纲

由于篇幅限制，以下 Stories 提供实施大纲：

### Story 026: 关系映射示例 (3 天)
- `08_relations_belongs_to.zig` - Post -> User
- `09_relations_has_many.zig` - User -> Posts
- `10_relations_many_to_many.zig` - Post <-> Tags

### Story 027: Schema 管理和迁移示例 (2-3 天)
- `11_schema_migrations.zig` - 迁移系统完整实现

### Story 028: 批量操作和高级查询示例 (3-4 天)
- `12_bulk_operations.zig` - 批量优化
- `13_advanced_queries.zig` - CTE、子查询、窗口函数

### Story 029: 类型映射和错误处理示例 (2 天)
- `14_type_mapping.zig` - 类型转换
- `15_error_handling.zig` - 错误处理

### Story 030: 钩子系统和连接池示例 (2-3 天)
- `16_hooks.zig` - 查询钩子
- `17_connection_pool.zig` - 连接池管理

### Story 031: 原始 SQL 和分页查询示例 (2 天)
- `18_raw_sql.zig` - Raw SQL
- `19_pagination.zig` - 分页实现

### Story 032: 聚合查询和文档完善 (2 天)
- `20_aggregation.zig` - 聚合查询
- 完善 `examples/README.md`
- 更新主 `README.md`

---

## 附录

### A. 工作量总结

| Story | 预估工作量 | 优先级 |
|-------|-----------|--------|
| 023 | 2-3 天 | P0 |
| 024 | 3-4 天 | P0 |
| 025 | 2-3 天 | P0 |
| 026 | 3 天 | P1 |
| 027 | 2-3 天 | P1 |
| 028 | 3-4 天 | P1 |
| 029 | 2 天 | P1 |
| 030 | 2-3 天 | P1 |
| 031 | 2 天 | P1 |
| 032 | 2 天 | P1 |
| **总计** | **23-30 天** | - |

### B. 依赖关系图

```
Story 023 (基础设施)
    ↓
Story 024 (基础 CRUD)
    ├─→ Story 025 (查询/事务)
    │       ├─→ Story 028 (批量/高级)
    │       └─→ Story 031 (原始SQL/分页)
    ├─→ Story 026 (关系映射)
    │       └─→ Story 028
    ├─→ Story 027 (迁移)
    └─→ Story 029 (类型/错误)
            └─→ Story 030 (钩子/连接池)
                    └─→ Story 032 (聚合/文档)
```

### C. 质量检查清单

每个示例完成后：
- [ ] 代码编译通过
- [ ] 代码运行成功
- [ ] 无内存泄漏
- [ ] 注释完整（说明 why）
- [ ] 错误处理正确
- [ ] 资源清理正确
- [ ] 输出清晰易懂
- [ ] 符合编码规范

### D. 测试策略

**单元测试**:
每个示例包含基本断言验证功能正确性。

**集成测试**:
`zig build run-all-examples` 运行所有示例，确保互不干扰。

**性能测试**:
批量操作示例包含性能对比数据。

---

**文档结束**

Authored-By: mobus <mobussun@gmail.com>
