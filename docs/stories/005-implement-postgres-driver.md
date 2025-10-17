# Story 005: 实现 PostgreSQL 驱动

## Status
Approved

## Story
**As a** ZORM 开发者,
**I want** 完整的 PostgreSQL 数据库驱动实现,
**so that** 能够通过 libpq 连接和操作 PostgreSQL 数据库

## Acceptance Criteria
1. 实现 PostgresDriver 结构体,封装 libpq C 接口
2. 实现数据库连接功能 (PQconnectdb)
3. 实现查询执行功能 (PQexec, PQexecParams)
4. 实现结果集处理 (PQresult, PQgetvalue)
5. 实现参数绑定和类型转换
6. 正确处理 PostgreSQL 特定错误
7. 编写集成测试,连接真实 PostgreSQL 数据库

## Tasks / Subtasks
- [ ] 创建 src/driver/postgres.zig 文件 (AC: 1)
  - [ ] 导入 libpq C 绑定 (@cImport)
  - [ ] 定义 PostgresDriver 结构体
  - [ ] 封装 PGconn 和 PGresult 指针
- [ ] 实现连接功能 (AC: 2)
  - [ ] connect(allocator, dsn) 函数
  - [ ] 使用 PQconnectdb 建立连接
  - [ ] 检查连接状态 (PQstatus)
  - [ ] 处理连接错误 (PQerrorMessage)
- [ ] 实现查询执行 (AC: 3)
  - [ ] exec(sql, args) !Result 方法
  - [ ] query(sql, args) !Rows 方法
  - [ ] 使用 PQexecParams 进行参数化查询
  - [ ] 处理 PGRES_COMMAND_OK 和 PGRES_TUPLES_OK 状态
- [ ] 实现结果集处理 (AC: 4)
  - [ ] PostgresRows 结构体
  - [ ] PostgresRow 结构体
  - [ ] next() 方法遍历结果集
  - [ ] getInt/getFloat/getBool/getString 方法
  - [ ] isNull 检查
- [ ] 实现参数绑定 (AC: 5)
  - [ ] QueryArg 到 PostgreSQL 格式的转换
  - [ ] 处理二进制和文本格式
  - [ ] Oid 类型映射
- [ ] 错误处理 (AC: 6)
  - [ ] 映射 PostgreSQL 错误到 ZORM Error
  - [ ] 提取错误消息和 SQLSTATE
- [ ] 编写集成测试 (AC: 7)
  - [ ] 连接 PostgreSQL 数据库
  - [ ] 测试 INSERT/SELECT/UPDATE/DELETE
  - [ ] 测试参数绑定
  - [ ] 测试结果集遍历
  - [ ] 测试错误处理

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md

### 架构参考
- **文档位置**: [docs/architecture.md#ConnectionManager](architecture.md#核心模块详细设计) (行 259-366)
- **PostgreSQL C API**: libpq 文档 (https://www.postgresql.org/docs/current/libpq.html)

### 文件位置
- **目标文件**: `src/driver/postgres.zig`
- **依赖文件**:
  - `src/driver/connection.zig` (Connection 接口)
  - `src/error.zig` (错误定义)
  - `src/types.zig` (QueryArg)

### PostgreSQL Driver 设计

#### 1. C 库绑定
```zig
const c = @cImport({
    @cInclude("libpq-fe.h");
});
```

#### 2. PostgresDriver 结构体
```zig
pub const PostgresDriver = struct {
    conn: ?*c.PGconn,
    allocator: Allocator,

    pub fn connect(allocator: Allocator, dsn: []const u8) !PostgresDriver {
        const conn = c.PQconnectdb(dsn.ptr);
        if (c.PQstatus(conn) != c.CONNECTION_OK) {
            const err_msg = c.PQerrorMessage(conn);
            std.log.err("Connection failed: {s}", .{err_msg});
            c.PQfinish(conn);
            return error.ConnectionFailed;
        }

        return PostgresDriver{
            .conn = conn,
            .allocator = allocator,
        };
    }

    pub fn close(self: *PostgresDriver) !void {
        if (self.conn) |conn| {
            c.PQfinish(conn);
            self.conn = null;
        }
    }

    pub fn exec(self: *PostgresDriver, sql: []const u8, args: []const QueryArg) !Result {
        // 实现查询执行...
    }

    pub fn query(self: *PostgresDriver, sql: []const u8, args: []const QueryArg) !Rows {
        // 实现查询并返回结果集...
    }
};
```

#### 3. 参数绑定
```zig
fn convertArgs(allocator: Allocator, args: []const QueryArg) !struct {
    values: []const [*c]const u8,
    lengths: []const c_int,
    formats: []const c_int,
} {
    var values = try allocator.alloc([*c]const u8, args.len);
    var lengths = try allocator.alloc(c_int, args.len);
    var formats = try allocator.alloc(c_int, args.len);

    for (args, 0..) |arg, i| {
        switch (arg) {
            .int => |val| {
                const str = try std.fmt.allocPrintZ(allocator, "{}", .{val});
                values[i] = str.ptr;
                lengths[i] = @intCast(str.len);
                formats[i] = 0; // 文本格式
            },
            .string => |str| {
                values[i] = str.ptr;
                lengths[i] = @intCast(str.len);
                formats[i] = 0;
            },
            // ... 其他类型
        }
    }

    return .{ .values = values, .lengths = lengths, .formats = formats };
}
```

### 测试环境
- **Host**: 127.0.0.1
- **Port**: 5432
- **Username**: pguser
- **Password**: Pg#123!
- **Database**: postgres

### Testing
- **测试文件位置**: `tests/integration/postgres_test.zig`
- **测试策略**:
  - 使用真实 PostgreSQL 数据库进行集成测试
  - 测试连接建立和关闭
  - 测试所有 CRUD 操作
  - 测试参数绑定
  - 测试错误处理
  - 测试并发连接

### 技术约束
- **Zig 版本**: 0.15.2+
- **PostgreSQL 版本**: 12+
- **libpq**: 系统需要安装 libpq 开发库

### 依赖项
- System: libpq (PostgreSQL C client library)
- `src/driver/connection.zig`
- `src/error.zig`
- `src/types.zig`

## Code Examples

```zig
// src/driver/postgres.zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const Connection = @import("connection.zig").Connection;
const Result = @import("connection.zig").Result;
const Rows = @import("connection.zig").Rows;
const Error = @import("../error.zig").Error;
const QueryArg = @import("../types.zig").QueryArg;

const c = @cImport({
    @cInclude("libpq-fe.h");
});

pub const PostgresDriver = struct {
    conn: ?*c.PGconn,
    allocator: Allocator,

    pub fn connect(allocator: Allocator, dsn: []const u8) !PostgresDriver {
        const dsn_z = try allocator.dupeZ(u8, dsn);
        defer allocator.free(dsn_z);

        const conn = c.PQconnectdb(dsn_z.ptr);
        if (c.PQstatus(conn) != c.CONNECTION_OK) {
            const err_msg = c.PQerrorMessage(conn);
            std.log.err("PostgreSQL connection failed: {s}", .{err_msg});
            c.PQfinish(conn);
            return error.ConnectionFailed;
        }

        std.log.info("PostgreSQL connected successfully", .{});
        return PostgresDriver{
            .conn = conn,
            .allocator = allocator,
        };
    }

    pub fn close(self: *PostgresDriver) !void {
        if (self.conn) |conn| {
            c.PQfinish(conn);
            self.conn = null;
        }
    }

    pub fn exec(self: *PostgresDriver, sql: []const u8, args: []const QueryArg) !Result {
        // TODO: 实现查询执行
        _ = self;
        _ = sql;
        _ = args;
        return error.NotImplemented;
    }

    pub fn query(self: *PostgresDriver, sql: []const u8, args: []const QueryArg) !Rows {
        // TODO: 实现查询
        _ = self;
        _ = sql;
        _ = args;
        return error.NotImplemented;
    }
};

test "PostgreSQL connection" {
    const allocator = std.testing.allocator;

    const dsn = "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres";
    var driver = try PostgresDriver.connect(allocator, dsn);
    defer driver.close() catch {};

    // 连接成功
}
```

## Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob (Scrum Master) |

## Dev Agent Record
_此部分将由开发 Agent 在实现过程中填写_

## QA Results
_此部分将由 QA Agent 在审查后填写_
