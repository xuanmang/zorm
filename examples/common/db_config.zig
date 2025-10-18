//! 数据库配置模块
//!
//! 提供统一的数据库配置和连接管理功能。
//! 所有示例程序都通过这个模块获取数据库连接。

const std = @import("std");
const zorm = @import("zorm");

/// 数据库配置结构体
pub const DBConfig = struct {
    host: []const u8,
    port: u16,
    user: []const u8,
    password: []const u8,
    dbname: []const u8,
    /// 可选的默认 schema，null 表示使用 public
    schema: ?[]const u8 = null,

    /// 生成 PostgreSQL DSN 连接字符串
    /// 格式: "host=X port=Y user=Z password=W dbname=D"
    pub fn toDSN(self: DBConfig, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(
            allocator,
            "host={s} port={d} user={s} password={s} dbname={s}",
            .{ self.host, self.port, self.user, self.password, self.dbname },
        );
    }
};

/// 获取默认的数据库配置
///
/// 返回用于示例的标准 PostgreSQL 配置：
/// - Host: 127.0.0.1
/// - Port: 5432
/// - User: pguser
/// - Password: Pg#123!
/// - Database: postgres
/// - Schema: null (使用 public)
pub fn getDefaultConfig() DBConfig {
    return .{
        .host = "127.0.0.1",
        .port = 5432,
        .user = "pguser",
        .password = "Pg#123!",
        .dbname = "postgres",
        .schema = null, // 默认使用 public schema
    };
}

/// 获取带自定义 schema 的配置
///
/// ## 参数
/// - schema_name: schema 名称，null 表示使用 public
///
/// ## 示例
/// ```zig
/// const config = getConfigWithSchema("myapp");
/// // 将使用 myapp schema
/// ```
pub fn getConfigWithSchema(schema_name: ?[]const u8) DBConfig {
    return .{
        .host = "127.0.0.1",
        .port = 5432,
        .user = "pguser",
        .password = "Pg#123!",
        .dbname = "postgres",
        .schema = schema_name,
    };
}

/// 从环境变量读取 schema 配置
///
/// 读取 DB_SCHEMA 环境变量。如果未设置，使用 public。
///
/// ## 环境变量
/// - DB_SCHEMA: schema 名称（可选）
///
/// ## 示例
/// ```bash
/// export DB_SCHEMA=myapp
/// # 程序将使用 myapp schema
/// ```
pub fn getConfigFromEnv() DBConfig {
    const schema = std.process.getEnvVarOwned(
        std.heap.page_allocator,
        "DB_SCHEMA",
    ) catch null;

    return .{
        .host = "127.0.0.1",
        .port = 5432,
        .user = "pguser",
        .password = "Pg#123!",
        .dbname = "postgres",
        .schema = if (schema) |s| s else null,
    };
}

/// 初始化 schema
///
/// 创建指定的 schema（如果不存在），并设置 search_path。
/// 如果 schema 为 null，则使用 public schema。
///
/// ## 参数
/// - db: 数据库连接
/// - schema_name: schema 名称，null 表示使用 public
/// - drop_if_exists: 是否先删除已存在的 schema（默认 false）
///
/// ## 错误
/// - error.QueryFailed: SQL 执行失败
///
/// ## 示例
/// ```zig
/// // 创建并使用 myapp schema
/// try initSchema(db, "myapp", false);
///
/// // 使用 public schema（不做任何操作）
/// try initSchema(db, null, false);
///
/// // 重建 myapp schema（删除旧数据）
/// try initSchema(db, "myapp", true);
/// ```
pub fn initSchema(
    db: anytype,
    schema_name: ?[]const u8,
    drop_if_exists: bool,
) !void {
    if (schema_name) |schema| {
        // 删除旧 schema（如果需要）
        if (drop_if_exists) {
            const drop_sql = try std.fmt.allocPrint(
                std.heap.page_allocator,
                "DROP SCHEMA IF EXISTS {s} CASCADE",
                .{schema},
            );
            defer std.heap.page_allocator.free(drop_sql);
            try db.exec(drop_sql, &.{});
        }

        // 创建 schema
        const create_sql = try std.fmt.allocPrint(
            std.heap.page_allocator,
            "CREATE SCHEMA IF NOT EXISTS {s}",
            .{schema},
        );
        defer std.heap.page_allocator.free(create_sql);
        try db.exec(create_sql, &.{});

        // 设置 search_path
        const set_path_sql = try std.fmt.allocPrint(
            std.heap.page_allocator,
            "SET search_path TO {s}, public",
            .{schema},
        );
        defer std.heap.page_allocator.free(set_path_sql);
        try db.exec(set_path_sql, &.{});
    }
    // 如果 schema_name 为 null，不做任何操作，使用默认的 public schema
}

/// 创建 PostgreSQL 驱动实例
///
/// 使用提供的配置创建数据库驱动。调用者负责调用 driver.close() 释放资源。
///
/// ## 参数
/// - allocator: 内存分配器
/// - config: 数据库配置
///
/// ## 返回
/// PostgresDriver 实例
///
/// ## 错误
/// - error.ConnectionFailed: 连接失败
/// - error.OutOfMemory: 内存分配失败
///
/// ## 示例
/// ```zig
/// const config = getDefaultConfig();
/// var driver = try createDriver(allocator, config);
/// defer driver.close() catch {};
/// ```
pub fn createDriver(allocator: std.mem.Allocator, config: DBConfig) !zorm.PostgresDriver {
    const dsn = try config.toDSN(allocator);
    defer allocator.free(dsn);

    return zorm.PostgresDriver.connect(allocator, dsn);
}

/// 创建 PostgreSQL 驱动实例 (使用默认配置)
///
/// 便捷函数,使用默认配置创建驱动。
///
/// ## 参数
/// - allocator: 内存分配器
///
/// ## 返回
/// PostgresDriver 实例
pub fn createDefaultDriver(allocator: std.mem.Allocator) !zorm.PostgresDriver {
    return createDriver(allocator, getDefaultConfig());
}

/// PostgresDriver 到 Conn 接口的适配器
const PostgresDriverConnAdapter = struct {
    driver: *zorm.PostgresDriver,
    allocator: std.mem.Allocator,

    fn exec(ptr: *anyopaque, query_str: []const u8, args: []const zorm.QueryArg) anyerror!void {
        const self: *PostgresDriverConnAdapter = @ptrCast(@alignCast(ptr));
        _ = try self.driver.exec(query_str, args);
    }

    fn query(ptr: *anyopaque, query_str: []const u8, args: []const zorm.QueryArg) anyerror!*zorm.core.Result {
        const self: *PostgresDriverConnAdapter = @ptrCast(@alignCast(ptr));
        const rows = try self.driver.query(query_str, args);

        // 创建 ResultWrapper 来适配 Rows 到 Result 接口
        const wrapper = try self.allocator.create(ResultWrapper);
        wrapper.* = .{
            .allocator = self.allocator,
        };

        // 创建 Result VTable
        const result_vtable = try self.allocator.create(zorm.core.Result.VTable);
        result_vtable.* = .{
            .next = ResultWrapper.next,
            .scan = ResultWrapper.scan,
            .close = ResultWrapper.close,
        };

        // 创建 Result 接口 - 包含 rows 字段
        const result = try self.allocator.create(zorm.core.Result);
        result.* = .{
            .ptr = wrapper,
            .vtable = result_vtable,
            .rows = rows,
        };
        return result;
    }

    fn begin(ptr: *anyopaque) anyerror!*zorm.core.Tx {
        _ = ptr;
        return error.NotImplemented;
    }

    fn close(ptr: *anyopaque) void {
        const self: *PostgresDriverConnAdapter = @ptrCast(@alignCast(ptr));
        // 关闭驱动连接
        self.driver.close() catch {};
        // 释放驱动和适配器的内存
        self.allocator.destroy(self.driver);
        self.allocator.destroy(self);
    }

    const vtable = zorm.core.Conn.VTable{
        .exec = exec,
        .query = query,
        .begin = begin,
        .close = close,
    };
};

/// ResultWrapper: 将 connection.Rows 适配到 core.Result 接口
const ResultWrapper = struct {
    allocator: std.mem.Allocator,

    fn next(ptr: *anyopaque) anyerror!bool {
        _ = ptr;
        // 实际的 next 操作由 Result.rows.next() 完成
        // 这里只是 VTable 的占位符
        return error.NotImplemented;
    }

    fn scan(ptr: *anyopaque, dest: [][]u8) anyerror!void {
        _ = ptr;
        _ = dest;
        return error.NotImplemented;
    }

    fn close(ptr: *anyopaque) void {
        const self: *ResultWrapper = @ptrCast(@alignCast(ptr));
        // 清理 wrapper 自身
        self.allocator.destroy(self);
    }
};

/// 创建 ZORM DB 实例
///
/// 使用提供的配置创建完整的 DB 实例,支持查询构建器等高级功能。
///
/// ## 参数
/// - allocator: 内存分配器
/// - config: 数据库配置
///
/// ## 返回
/// DB 实例指针,调用者负责调用 db.deinit() 释放资源
///
/// ## 示例
/// ```zig
/// const config = getDefaultConfig();
/// var db = try createDBInstance(allocator, config);
/// defer db.deinit();
///
/// var query = try db.newSelect(User);
/// defer query.deinit();
/// const users = try query.scan();
/// ```
pub fn createDBInstance(allocator: std.mem.Allocator, config: DBConfig) !*zorm.DB(.postgresql) {
    // 创建 driver
    const driver = try allocator.create(zorm.PostgresDriver);
    errdefer allocator.destroy(driver);
    driver.* = try createDriver(allocator, config);
    errdefer driver.close() catch {};

    // 创建适配器
    const adapter = try allocator.create(PostgresDriverConnAdapter);
    errdefer allocator.destroy(adapter);
    adapter.* = .{
        .driver = driver,
        .allocator = allocator,
    };

    // 创建 Conn 接口
    const conn = zorm.core.Conn{
        .ptr = adapter,
        .vtable = &PostgresDriverConnAdapter.vtable,
    };

    // 创建 DB 实例
    const db = try zorm.DB(.postgresql).init(allocator, conn, .{});
    return db;
}

/// 创建 ZORM DB 实例 (使用默认配置)
///
/// 便捷函数,使用默认配置创建 DB 实例。
///
/// ## 参数
/// - allocator: 内存分配器
///
/// ## 返回
/// DB 实例指针
pub fn createDefaultDBInstance(allocator: std.mem.Allocator) !*zorm.DB(.postgresql) {
    return createDBInstance(allocator, getDefaultConfig());
}
