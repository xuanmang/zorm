# Story 004: 实现 Connection 接口

## Status
Draft

## Story
**As a** ZORM 开发者,
**I want** 一个统一的数据库连接接口,
**so that** 能够支持多种数据库驱动,实现编译时多态和零运行时开销

## Acceptance Criteria
1. 定义 Connection 泛型结构体,接受 Driver 类型参数
2. 实现 exec() 方法执行无返回结果的 SQL
3. 实现 query() 方法执行有返回结果的 SQL
4. 实现 close() 方法关闭连接
5. 定义 Result 和 Rows 接口
6. 所有方法使用错误联合类型 (!T) 进行错误处理
7. 编译时多态,无虚函数表开销

## Tasks / Subtasks
- [ ] 创建 src/driver/connection.zig 文件 (AC: 1)
  - [ ] 定义 Connection(comptime Driver: type) 泛型结构体
  - [ ] 添加 driver 字段和 allocator 字段
  - [ ] 实现 init() 和 deinit() 方法
- [ ] 实现连接方法 (AC: 2, 3, 4)
  - [ ] 实现 exec(sql, args) !Result 方法
  - [ ] 实现 query(sql, args) !Rows 方法
  - [ ] 实现 close() !void 方法
- [ ] 定义 Result 结构体 (AC: 5)
  - [ ] last_insert_id 字段
  - [ ] rows_affected 字段
- [ ] 定义 Rows 接口 (AC: 5)
  - [ ] next() !?Row 方法
  - [ ] deinit() 方法
- [ ] 定义 Row 接口 (AC: 5)
  - [ ] VTable 模式实现驱动特定行访问
  - [ ] isNull(index) 方法
  - [ ] getInt/getFloat/getBool/getString 方法
- [ ] 编写文档注释 (AC: 1-7)
  - [ ] 说明编译时多态设计
  - [ ] 提供使用示例
  - [ ] 说明内存管理和生命周期
- [ ] 编写单元测试 (AC: 6, 7)
  - [ ] 测试泛型特化
  - [ ] 测试错误处理
  - [ ] 验证编译时多态(无虚函数调用)

## Dev Notes

### 架构参考
- **文档位置**: [docs/architecture.md#ConnectionManager](architecture.md#核心模块详细设计) (行 259-366)
- **关键设计原则**:
  - 使用泛型结构体 Connection(comptime Driver: type) 实现编译时多态
  - 避免使用接口和虚函数表
  - 每个驱动类型在编译时生成专用的 Connection 实例
  - 零运行时反射开销
  - 使用 VTable 模式仅在必要时(如 Row 访问)

### 文件位置
- **目标文件**: `src/driver/connection.zig`
- **依赖文件**:
  - `src/error.zig` (连接错误)
  - `src/types.zig` (QueryArg 类型)

### Connection 接口设计

#### 1. Connection 泛型结构体
```zig
/// 连接接口 (编译时多态)
///
/// 每个数据库驱动(PostgreSQL, MySQL, SQLite)都会在编译时生成
/// 一个专用的 Connection 类型,实现零运行时开销
pub fn Connection(comptime Driver: type) type {
    return struct {
        const Self = @This();

        driver: Driver,
        allocator: Allocator,

        /// 执行查询
        pub fn exec(self: *Self, sql: []const u8, args: []const QueryArg) !Result {
            return self.driver.exec(sql, args);
        }

        /// 执行查询并返回结果集
        pub fn query(self: *Self, sql: []const u8, args: []const QueryArg) !Rows {
            return self.driver.query(sql, args);
        }

        /// 关闭连接
        pub fn close(self: *Self) !void {
            try self.driver.close();
        }
    };
}
```

#### 2. Result 结构体
```zig
/// 查询执行结果 (不返回行)
pub const Result = struct {
    /// 最后插入的 ID (INSERT 操作)
    last_insert_id: i64,

    /// 受影响的行数
    rows_affected: u64,
};
```

#### 3. Rows 结构体
```zig
/// 查询结果集
pub const Rows = struct {
    driver_rows: *anyopaque,
    vtable: *const RowsVTable,
    allocator: Allocator,

    pub const RowsVTable = struct {
        next: *const fn (*anyopaque) anyerror!?Row,
        deinit: *const fn (*anyopaque, Allocator) void,
    };

    /// 获取下一行
    pub fn next(self: *Rows) !?Row {
        return self.vtable.next(self.driver_rows);
    }

    /// 释放结果集
    pub fn deinit(self: *Rows) void {
        self.vtable.deinit(self.driver_rows, self.allocator);
    }
};
```

#### 4. Row 结构体 (VTable 模式)
```zig
/// 结果集中的一行
pub const Row = struct {
    driver_row: *anyopaque,
    vtable: *const RowVTable,

    pub const RowVTable = struct {
        isNull: *const fn (*anyopaque, usize) bool,
        getInt: *const fn (*anyopaque, comptime type, usize) anyerror!i64,
        getFloat: *const fn (*anyopaque, comptime type, usize) anyerror!f64,
        getBool: *const fn (*anyopaque, usize) anyerror!bool,
        getString: *const fn (*anyopaque, usize) anyerror![]const u8,
    };

    pub fn isNull(self: *Row, index: usize) bool {
        return self.vtable.isNull(self.driver_row, index);
    }

    pub fn getInt(self: *Row, comptime T: type, index: usize) !T {
        const value = try self.vtable.getInt(self.driver_row, T, index);
        return @intCast(value);
    }

    // ... 其他方法
};
```

### 实现指南

1. **编译时多态示例**
   ```zig
   // 编译时生成 PostgreSQL 专用连接类型
   const PostgresConnection = Connection(PostgresDriver);

   // 编译时生成 MySQL 专用连接类型
   const MySQLConnection = Connection(MySQLDriver);

   // 每个类型在编译时已知,无虚函数调用
   var pg_conn = PostgresConnection{ .driver = pg_driver, .allocator = allocator };
   try pg_conn.exec("INSERT INTO ...", &.{}); // 直接调用,无虚函数表
   ```

2. **错误处理**
   ```zig
   pub fn exec(self: *Self, sql: []const u8, args: []const QueryArg) !Result {
       return self.driver.exec(sql, args) catch |err| {
           std.log.err("Query execution failed: {s}", .{sql});
           return err;
       };
   }
   ```

3. **资源清理**
   ```zig
   pub fn query(self: *Self, sql: []const u8, args: []const QueryArg) !Rows {
       const rows = try self.driver.query(sql, args);
       errdefer rows.deinit();
       return rows;
   }
   ```

4. **使用示例**
   ```zig
   const conn = Connection(PostgresDriver){ .driver = driver, .allocator = allocator };
   defer conn.close() catch {};

   // 执行无返回结果的查询
   const result = try conn.exec("INSERT INTO users (name) VALUES ($1)", &.{
       QueryArg{ .string = "Alice" }
   });
   std.debug.print("Inserted ID: {}\n", .{result.last_insert_id});

   // 执行有返回结果的查询
   const rows = try conn.query("SELECT * FROM users", &.{});
   defer rows.deinit();

   while (try rows.next()) |row| {
       const id = try row.getInt(i64, 0);
       const name = try row.getString(1);
       std.debug.print("User: id={}, name={s}\n", .{id, name});
   }
   ```

### Testing
- **测试文件位置**: `tests/unit/connection_test.zig`
- **测试框架**: Zig 内置测试框架
- **测试策略**:
  - 使用 Mock Driver 测试泛型特化
  - 验证编译时多态(无虚函数调用)
  - 测试错误处理路径
  - 验证资源清理 (defer/errdefer)
  - 测试 Row VTable 接口

### 技术约束
- **Zig 版本**: 0.15.2+
- **性能要求**: 零运行时反射,零虚函数表开销
- **内存管理**: 使用 Allocator 模式
- **错误处理**: 所有方法返回 !T

### 依赖项
- `src/error.zig`: 连接相关错误
- `src/types.zig`: QueryArg 类型

### 设计权衡

**为什么 Connection 使用泛型而不是接口?**
- Zig 没有传统的接口概念
- 泛型特化在编译时完成,无运行时开销
- 每个驱动类型生成专用代码,性能最优

**为什么 Row 使用 VTable 模式?**
- Row 需要跨驱动边界传递
- VTable 提供运行时多态但开销可控
- 只在必要的地方使用动态分发

## Code Examples

### Connection 接口骨架
```zig
// src/driver/connection.zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = @import("../error.zig").Error;
const QueryArg = @import("../types.zig").QueryArg;

/// 连接接口 (编译时多态)
///
/// 通过泛型参数 Driver 实现编译时特化,避免虚函数表开销
///
/// 示例:
/// ```zig
/// const PostgresConn = Connection(PostgresDriver);
/// var conn = PostgresConn{ .driver = driver, .allocator = allocator };
/// ```
pub fn Connection(comptime Driver: type) type {
    return struct {
        const Self = @This();

        driver: Driver,
        allocator: Allocator,

        /// 执行查询 (无返回结果)
        pub fn exec(self: *Self, sql: []const u8, args: []const QueryArg) !Result {
            return self.driver.exec(sql, args);
        }

        /// 执行查询 (有返回结果)
        pub fn query(self: *Self, sql: []const u8, args: []const QueryArg) !Rows {
            return self.driver.query(sql, args);
        }

        /// 关闭连接
        pub fn close(self: *Self) !void {
            try self.driver.close();
        }
    };
}

/// 查询执行结果
pub const Result = struct {
    last_insert_id: i64,
    rows_affected: u64,
};

/// 查询结果集
pub const Rows = struct {
    driver_rows: *anyopaque,
    vtable: *const RowsVTable,
    allocator: Allocator,

    pub const RowsVTable = struct {
        next: *const fn (*anyopaque) anyerror!?Row,
        deinit: *const fn (*anyopaque, Allocator) void,
    };

    pub fn next(self: *Rows) !?Row {
        return self.vtable.next(self.driver_rows);
    }

    pub fn deinit(self: *Rows) void {
        self.vtable.deinit(self.driver_rows, self.allocator);
    }
};

/// 结果集中的一行
pub const Row = struct {
    driver_row: *anyopaque,
    vtable: *const RowVTable,

    pub const RowVTable = struct {
        isNull: *const fn (*anyopaque, usize) bool,
        getInt: *const fn (*anyopaque, comptime type, usize) anyerror!i64,
        getFloat: *const fn (*anyopaque, comptime type, usize) anyerror!f64,
        getBool: *const fn (*anyopaque, usize) anyerror!bool,
        getString: *const fn (*anyopaque, usize) anyerror![]const u8,
    };

    pub fn isNull(self: *Row, index: usize) bool {
        return self.vtable.isNull(self.driver_row, index);
    }

    pub fn getInt(self: *Row, comptime T: type, index: usize) !T {
        const value = try self.vtable.getInt(self.driver_row, T, index);
        return @intCast(value);
    }

    // TODO: 实现其他方法...
};

// ========== 测试 ==========
test "Connection generic specialization" {
    // Mock Driver for testing
    const MockDriver = struct {
        pub fn exec(self: *@This(), sql: []const u8, args: []const QueryArg) !Result {
            _ = self;
            _ = sql;
            _ = args;
            return Result{ .last_insert_id = 1, .rows_affected = 1 };
        }

        pub fn query(self: *@This(), sql: []const u8, args: []const QueryArg) !Rows {
            _ = self;
            _ = sql;
            _ = args;
            return error.NotImplemented;
        }

        pub fn close(self: *@This()) !void {
            _ = self;
        }
    };

    const MockConn = Connection(MockDriver);
    var driver = MockDriver{};
    var conn = MockConn{
        .driver = driver,
        .allocator = std.testing.allocator,
    };

    const result = try conn.exec("INSERT INTO test VALUES (1)", &.{});
    try std.testing.expectEqual(@as(i64, 1), result.last_insert_id);
}
```

## Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob (Scrum Master) |

## Dev Agent Record
_此部分将由开发 Agent 在实现过程中填写_

### Agent Model Used
_待填写_

### Debug Log References
_待填写_

### Completion Notes
_待填写_

### File List
_待填写_

## QA Results
_此部分将由 QA Agent 在审查后填写_
