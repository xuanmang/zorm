// src/driver/connection.zig
// ZORM 数据库连接接口
// 提供编译时多态的连接抽象,支持多种数据库驱动,实现零运行时开销

const std = @import("std");
const Allocator = std.mem.Allocator;
pub const Error = @import("../error.zig").Error;
const QueryArg = @import("../types.zig").QueryArg;

/// 连接接口 (编译时多态)
///
/// 通过泛型参数 Driver 实现编译时特化,避免虚函数表开销。
/// 每个数据库驱动(PostgreSQL, MySQL, SQLite)都会在编译时生成
/// 一个专用的 Connection 类型,实现零运行时开销。
///
/// 设计原则:
/// - 使用泛型结构体 Connection(comptime Driver: type) 实现编译时多态
/// - 避免使用接口和虚函数表 (Zig 不支持传统的接口)
/// - 每个驱动类型在编译时生成专用的 Connection 实例
/// - 零运行时反射开销
///
/// 示例:
/// ```zig
/// const PostgresConnection = Connection(PostgresDriver);
/// var conn = PostgresConnection{
///     .driver = driver,
///     .allocator = allocator
/// };
/// try conn.exec("INSERT INTO ...", &.{});
/// ```
///
/// 为什么 Connection 使用泛型而不是接口?
/// - Zig 没有传统的接口概念
/// - 泛型特化在编译时完成,无运行时开销
/// - 每个驱动类型生成专用代码,性能最优
pub fn Connection(comptime Driver: type) type {
    return struct {
        const Self = @This();

        /// 驱动实例 (由具体驱动实现,如 PostgresDriver)
        driver: Driver,

        /// 内存分配器 (用于分配连接相关的内存)
        allocator: Allocator,

        /// 执行查询 (无返回结果)
        ///
        /// 用于 INSERT, UPDATE, DELETE 等不返回行的操作。
        ///
        /// 参数:
        /// - sql: SQL 语句字符串
        /// - args: 绑定参数数组
        ///
        /// 返回:
        /// - Result: 执行结果,包含 last_insert_id 和 rows_affected
        ///
        /// 错误:
        /// - error.QueryFailed: SQL 执行失败
        /// - error.InvalidSQL: SQL 语法错误
        /// - error.ConnectionClosed: 连接已关闭
        pub fn exec(self: *Self, sql: []const u8, args: []const QueryArg) !Result {
            return self.driver.exec(sql, args);
        }

        /// 执行查询 (有返回结果)
        ///
        /// 用于 SELECT 等返回行的操作。
        ///
        /// 参数:
        /// - sql: SQL 语句字符串
        /// - args: 绑定参数数组
        ///
        /// 返回:
        /// - Rows: 结果集迭代器
        ///
        /// 错误:
        /// - error.QueryFailed: SQL 执行失败
        /// - error.InvalidSQL: SQL 语法错误
        /// - error.ConnectionClosed: 连接已关闭
        ///
        /// 使用示例:
        /// ```zig
        /// const rows = try conn.query("SELECT * FROM users", &.{});
        /// defer rows.deinit();
        ///
        /// while (try rows.next()) |row| {
        ///     const id = try row.getInt(i64, 0);
        ///     const name = try row.getString(1);
        ///     std.debug.print("User: id={}, name={s}\n", .{id, name});
        /// }
        /// ```
        pub fn query(self: *Self, sql: []const u8, args: []const QueryArg) !Rows {
            return self.driver.query(sql, args);
        }

        /// 关闭连接
        ///
        /// 释放数据库连接资源。连接关闭后不能再使用。
        ///
        /// 错误:
        /// - error.ConnectionClosed: 连接已关闭
        ///
        /// 使用示例:
        /// ```zig
        /// defer conn.close() catch {};
        /// ```
        pub fn close(self: *Self) !void {
            try self.driver.close();
        }
    };
}

/// 查询执行结果 (不返回行)
///
/// 用于 INSERT, UPDATE, DELETE 等操作的返回值。
///
/// 示例:
/// ```zig
/// const result = try conn.exec("INSERT INTO users (name) VALUES ($1)", &.{
///     QueryArg.fromValue("Alice")
/// });
/// std.debug.print("Inserted ID: {}\n", .{result.last_insert_id});
/// std.debug.print("Affected rows: {}\n", .{result.rows_affected});
/// ```
pub const Result = struct {
    /// 最后插入的 ID (INSERT 操作)
    ///
    /// 对于 INSERT 操作,通常是自增主键的值。
    /// 对于其他操作(UPDATE, DELETE),该值可能为 0。
    ///
    /// 注意: 不同数据库的行为可能不同:
    /// - PostgreSQL: 需要使用 RETURNING id 子句
    /// - MySQL: 自动返回 AUTO_INCREMENT 的值
    /// - SQLite: 自动返回 ROWID
    last_insert_id: i64,

    /// 受影响的行数
    ///
    /// 对于 INSERT/UPDATE/DELETE,表示受影响的行数。
    /// 对于 SELECT,该值通常为 0。
    rows_affected: u64,
};

/// 查询结果集
///
/// 提供迭代器接口,用于逐行读取查询结果。
/// 使用 VTable 模式实现运行时多态,因为结果集需要跨驱动边界传递。
///
/// 为什么 Rows 使用 VTable 模式?
/// - Rows 需要跨驱动边界传递 (从驱动传递到用户代码)
/// - VTable 提供运行时多态但开销可控
/// - 只在必要的地方使用动态分发
///
/// 使用示例:
/// ```zig
/// const rows = try conn.query("SELECT * FROM users", &.{});
/// defer rows.deinit();
///
/// while (try rows.next()) |row| {
///     // 处理每一行
/// }
/// ```
pub const Rows = struct {
    /// 驱动特定的结果集实现 (类型擦除)
    driver_rows: *anyopaque,

    /// 虚函数表 (实现运行时多态)
    vtable: *RowsVTable,

    /// 内存分配器
    allocator: Allocator,

    /// Rows 虚函数表
    ///
    /// 定义了所有驱动必须实现的方法。
    pub const RowsVTable = struct {
        /// 获取下一行
        ///
        /// 返回 ?Row:
        /// - null 表示没有更多行
        /// - Row 表示当前行
        next: *const fn (*anyopaque) Error!?Row,

        /// 释放结果集
        ///
        /// 清理驱动特定的资源。
        deinit: *const fn (*anyopaque, Allocator) void,
    };

    /// 获取下一行
    ///
    /// 返回:
    /// - ?Row: 下一行,如果没有更多行则返回 null
    ///
    /// 错误:
    /// - error.QueryFailed: 读取失败
    ///
    /// 使用示例:
    /// ```zig
    /// while (try rows.next()) |row| {
    ///     const id = try row.getInt(i64, 0);
    ///     std.debug.print("ID: {}\n", .{id});
    /// }
    /// ```
    pub fn next(self: *Rows) !?Row {
        return self.vtable.next(self.driver_rows);
    }

    /// 释放结果集
    ///
    /// 必须在使用完结果集后调用,否则会导致内存泄漏。
    ///
    /// 使用示例:
    /// ```zig
    /// const rows = try conn.query(...);
    /// defer rows.deinit(); // 确保资源释放
    /// ```
    pub fn deinit(self: *Rows) void {
        self.vtable.deinit(self.driver_rows, self.allocator);
        // 释放 VTable 本身
        self.allocator.destroy(self.vtable);
    }
};

/// 结果集中的一行
///
/// 提供类型安全的列访问接口。
/// 使用 VTable 模式实现运行时多态。
///
/// 使用示例:
/// ```zig
/// const row = (try rows.next()).?;
///
/// // 检查列是否为 NULL
/// if (row.isNull(2)) {
///     std.debug.print("Email is NULL\n", .{});
/// }
///
/// // 获取列值
/// const id = try row.getInt(i64, 0);
/// const name = try row.getString(1);
/// const email = if (!row.isNull(2)) try row.getString(2) else null;
/// ```
pub const Row = struct {
    /// 驱动特定的行实现 (类型擦除)
    driver_row: *anyopaque,

    /// 虚函数表 (实现运行时多态)
    vtable: *RowVTable,

    /// Row 虚函数表
    ///
    /// 定义了所有驱动必须实现的列访问方法。
    pub const RowVTable = struct {
        /// 检查列是否为 NULL
        ///
        /// 参数:
        /// - index: 列索引 (从 0 开始)
        ///
        /// 返回:
        /// - true: 列值为 NULL
        /// - false: 列值不为 NULL
        isNull: *const fn (*anyopaque, usize) bool,

        /// 获取整数列值
        ///
        /// 参数:
        /// - index: 列索引 (从 0 开始)
        ///
        /// 返回:
        /// - i64: 整数值
        ///
        /// 错误:
        /// - error.TypeMismatch: 列类型不是整数
        /// - error.NullValue: 列值为 NULL
        getInt: *const fn (*anyopaque, usize) Error!i64,

        /// 获取浮点数列值
        ///
        /// 参数:
        /// - index: 列索引 (从 0 开始)
        ///
        /// 返回:
        /// - f64: 浮点值
        ///
        /// 错误:
        /// - error.TypeMismatch: 列类型不是浮点数
        /// - error.NullValue: 列值为 NULL
        getFloat: *const fn (*anyopaque, usize) Error!f64,

        /// 获取布尔列值
        ///
        /// 参数:
        /// - index: 列索引 (从 0 开始)
        ///
        /// 返回:
        /// - bool: 布尔值
        ///
        /// 错误:
        /// - error.TypeMismatch: 列类型不是布尔
        /// - error.NullValue: 列值为 NULL
        getBool: *const fn (*anyopaque, usize) Error!bool,

        /// 获取字符串列值
        ///
        /// 参数:
        /// - index: 列索引 (从 0 开始)
        ///
        /// 返回:
        /// - []const u8: 字符串切片 (不拥有内存,生命周期绑定到 Row)
        ///
        /// 错误:
        /// - error.TypeMismatch: 列类型不是字符串
        /// - error.NullValue: 列值为 NULL
        ///
        /// 注意: 返回的字符串借用 Row 的内存,如需长期持有需要复制。
        getString: *const fn (*anyopaque, usize) Error![]const u8,
    };

    /// 检查列是否为 NULL
    ///
    /// 参数:
    /// - index: 列索引 (从 0 开始)
    ///
    /// 返回:
    /// - true: 列值为 NULL
    /// - false: 列值不为 NULL
    ///
    /// 使用示例:
    /// ```zig
    /// if (row.isNull(2)) {
    ///     std.debug.print("Column 2 is NULL\n", .{});
    /// } else {
    ///     const value = try row.getString(2);
    ///     std.debug.print("Column 2: {s}\n", .{value});
    /// }
    /// ```
    pub fn isNull(self: *const Row, index: usize) bool {
        return self.vtable.isNull(self.driver_row, index);
    }

    /// 获取整数列值
    ///
    /// 参数:
    /// - T: 目标整数类型 (i8, i16, i32, i64, u8, u16, u32, u64)
    /// - index: 列索引 (从 0 开始)
    ///
    /// 返回:
    /// - T: 整数值
    ///
    /// 错误:
    /// - error.TypeMismatch: 列类型不是整数
    /// - error.NullValue: 列值为 NULL
    ///
    /// 使用示例:
    /// ```zig
    /// const id = try row.getInt(i64, 0);
    /// const age: u32 = @intCast(try row.getInt(i64, 1));
    /// ```
    pub fn getInt(self: *const Row, comptime T: type, index: usize) !T {
        const value = try self.vtable.getInt(self.driver_row, index);
        return @intCast(value);
    }

    /// 获取浮点数列值
    ///
    /// 参数:
    /// - T: 目标浮点类型 (f32, f64)
    /// - index: 列索引 (从 0 开始)
    ///
    /// 返回:
    /// - T: 浮点值
    ///
    /// 错误:
    /// - error.TypeMismatch: 列类型不是浮点数
    /// - error.NullValue: 列值为 NULL
    ///
    /// 使用示例:
    /// ```zig
    /// const price = try row.getFloat(f64, 0);
    /// const rating: f32 = @floatCast(try row.getFloat(f64, 1));
    /// ```
    pub fn getFloat(self: *const Row, comptime T: type, index: usize) !T {
        const value = try self.vtable.getFloat(self.driver_row, index);
        return @floatCast(value);
    }

    /// 获取布尔列值
    ///
    /// 参数:
    /// - index: 列索引 (从 0 开始)
    ///
    /// 返回:
    /// - bool: 布尔值
    ///
    /// 错误:
    /// - error.TypeMismatch: 列类型不是布尔
    /// - error.NullValue: 列值为 NULL
    ///
    /// 使用示例:
    /// ```zig
    /// const is_active = try row.getBool(0);
    /// ```
    pub fn getBool(self: *const Row, index: usize) !bool {
        return self.vtable.getBool(self.driver_row, index);
    }

    /// 获取字符串列值
    ///
    /// 参数:
    /// - index: 列索引 (从 0 开始)
    ///
    /// 返回:
    /// - []const u8: 字符串切片 (不拥有内存,生命周期绑定到 Row)
    ///
    /// 错误:
    /// - error.TypeMismatch: 列类型不是字符串
    /// - error.NullValue: 列值为 NULL
    ///
    /// 注意:
    /// - 返回的字符串借用 Row 的内存
    /// - 如需长期持有,需要使用 allocator.dupe() 复制
    ///
    /// 使用示例:
    /// ```zig
    /// const name = try row.getString(0);
    /// std.debug.print("Name: {s}\n", .{name});
    ///
    /// // 如需长期持有
    /// const name_copy = try allocator.dupe(u8, name);
    /// defer allocator.free(name_copy);
    /// ```
    pub fn getString(self: *const Row, index: usize) ![]const u8 {
        return self.vtable.getString(self.driver_row, index);
    }
};

// ========== 测试 ==========

test "Connection generic specialization" {
    const testing = std.testing;

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
    const driver = MockDriver{};
    var conn = MockConn{
        .driver = driver,
        .allocator = std.testing.allocator,
    };

    const result = try conn.exec("INSERT INTO test VALUES (1)", &.{});
    try testing.expectEqual(@as(i64, 1), result.last_insert_id);
    try testing.expectEqual(@as(u64, 1), result.rows_affected);

    try conn.close();
}

test "Result struct fields" {
    const testing = std.testing;

    const result = Result{
        .last_insert_id = 42,
        .rows_affected = 10,
    };

    try testing.expectEqual(@as(i64, 42), result.last_insert_id);
    try testing.expectEqual(@as(u64, 10), result.rows_affected);
}

test "Connection is comptime polymorphic" {
    // 验证 Connection 是编译时多态的,而不是运行时多态

    const DriverA = struct {
        pub fn exec(_: *@This(), _: []const u8, _: []const QueryArg) !Result {
            return Result{ .last_insert_id = 1, .rows_affected = 1 };
        }
        pub fn query(_: *@This(), _: []const u8, _: []const QueryArg) !Rows {
            return error.NotImplemented;
        }
        pub fn close(_: *@This()) !void {}
    };

    const DriverB = struct {
        pub fn exec(_: *@This(), _: []const u8, _: []const QueryArg) !Result {
            return Result{ .last_insert_id = 2, .rows_affected = 2 };
        }
        pub fn query(_: *@This(), _: []const u8, _: []const QueryArg) !Rows {
            return error.NotImplemented;
        }
        pub fn close(_: *@This()) !void {}
    };

    // 验证两个 Connection 类型是不同的
    const ConnA = Connection(DriverA);
    const ConnB = Connection(DriverB);

    // 编译时类型检查: ConnA 和 ConnB 是不同的类型
    comptime {
        const a_name = @typeName(ConnA);
        const b_name = @typeName(ConnB);
        // 类型名不同,证明是不同的类型 (编译时特化)
        if (std.mem.eql(u8, a_name, b_name)) {
            @compileError("Expected different types");
        }
    }
}
