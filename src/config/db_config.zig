//! 数据库配置模块
//!
//! 提供统一的数据库配置和连接管理功能，简化 ZORM 的使用。
//!
//! ## 主要功能
//! - PostgreSQL 连接配置管理
//! - Schema 管理（创建、删除、切换）
//! - 驱动适配器（PostgresDriver → Conn 接口）
//! - 环境变量配置支持
//!
//! ## 快速开始
//! ```zig
//! const zorm = @import("zorm");
//!
//! // 方式1: 使用默认配置（需要设置环境变量）
//! var config = try zorm.config.DBConfig.fromEnv(allocator);
//! defer config.deinit(allocator);
//! var db = try config.connect(allocator);
//! defer db.deinit();
//!
//! // 方式2: 手动配置
//! var config = zorm.config.DBConfig{
//!     .host = "localhost",
//!     .port = 5432,
//!     .user = "myuser",
//!     .password = "mypass",
//!     .dbname = "mydb",
//!     .schema = "myschema",
//! };
//! var db = try config.connect(allocator);
//! defer db.deinit();
//! ```

const std = @import("std");
const root = @import("../zorm.zig");
const PostgresDriver = root.PostgresDriver;
const core = root.core;
const QueryArg = root.QueryArg;

/// 数据库配置结构体
pub const DBConfig = struct {
    host: []const u8,
    port: u16,
    user: []const u8,
    password: []const u8,
    dbname: []const u8,
    /// 可选的默认 schema，null 表示使用 public
    schema: ?[]const u8 = null,

    /// 用于释放从环境变量分配的字符串
    allocator: ?std.mem.Allocator = null,

    /// 生成 PostgreSQL DSN 连接字符串
    ///
    /// ## 参数
    /// - allocator: 内存分配器
    ///
    /// ## 返回
    /// DSN 字符串，格式: "host=X port=Y user=Z password=W dbname=D"
    ///
    /// ## 示例
    /// ```zig
    /// const dsn = try config.toDSN(allocator);
    /// defer allocator.free(dsn);
    /// ```
    pub fn toDSN(self: DBConfig, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(
            allocator,
            "host={s} port={d} user={s} password={s} dbname={s}",
            .{ self.host, self.port, self.user, self.password, self.dbname },
        );
    }

    /// 创建默认配置（用于测试和示例）
    ///
    /// ⚠️ **警告**: 此配置仅用于开发和测试！
    /// 生产环境请使用 fromEnv() 或手动配置。
    ///
    /// ## 默认值
    /// - Host: 127.0.0.1
    /// - Port: 5432
    /// - User: postgres
    /// - Password: (空)
    /// - Database: postgres
    /// - Schema: null (public)
    pub fn default() DBConfig {
        return .{
            .host = "127.0.0.1",
            .port = 5432,
            .user = "postgres",
            .password = "",
            .dbname = "postgres",
            .schema = null,
        };
    }

    /// 从环境变量读取配置
    ///
    /// ## 环境变量
    /// - DB_HOST: 数据库主机（默认: 127.0.0.1）
    /// - DB_PORT: 数据库端口（默认: 5432）
    /// - DB_USER: 数据库用户（必需）
    /// - DB_PASSWORD: 数据库密码（可选）
    /// - DB_NAME: 数据库名称（默认: postgres）
    /// - DB_SCHEMA: Schema 名称（可选，默认: public）
    ///
    /// ## 示例
    /// ```bash
    /// export DB_USER=myuser
    /// export DB_PASSWORD=mypass
    /// export DB_NAME=mydb
    /// export DB_SCHEMA=myschema
    /// ```
    ///
    /// ```zig
    /// var config = try DBConfig.fromEnv(allocator);
    /// defer config.deinit(allocator);
    /// ```
    pub fn fromEnv(allocator: std.mem.Allocator) !DBConfig {
        const host = std.process.getEnvVarOwned(
            allocator,
            "DB_HOST",
        ) catch try allocator.dupe(u8, "127.0.0.1");

        const port_str = std.process.getEnvVarOwned(
            allocator,
            "DB_PORT",
        ) catch try allocator.dupe(u8, "5432");
        defer allocator.free(port_str);
        const port = try std.fmt.parseInt(u16, port_str, 10);

        const user = try std.process.getEnvVarOwned(
            allocator,
            "DB_USER",
        );

        const password = std.process.getEnvVarOwned(
            allocator,
            "DB_PASSWORD",
        ) catch try allocator.dupe(u8, "");

        const dbname = std.process.getEnvVarOwned(
            allocator,
            "DB_NAME",
        ) catch try allocator.dupe(u8, "postgres");

        const schema = std.process.getEnvVarOwned(
            allocator,
            "DB_SCHEMA",
        ) catch null;

        return .{
            .host = host,
            .port = port,
            .user = user,
            .password = password,
            .dbname = dbname,
            .schema = schema,
            .allocator = allocator,
        };
    }

    /// 释放从环境变量分配的资源
    pub fn deinit(self: *DBConfig, allocator: std.mem.Allocator) void {
        if (self.allocator) |_| {
            allocator.free(self.host);
            allocator.free(self.user);
            allocator.free(self.password);
            allocator.free(self.dbname);
            if (self.schema) |s| allocator.free(s);
        }
    }

    /// 连接数据库并返回 DB 实例
    ///
    /// ## 参数
    /// - allocator: 内存分配器
    ///
    /// ## 返回
    /// DB 实例指针
    ///
    /// ## 示例
    /// ```zig
    /// var db = try config.connect(allocator);
    /// defer db.deinit();
    /// ```
    pub fn connect(self: DBConfig, allocator: std.mem.Allocator) !*root.DB(.postgresql) {
        // 创建 driver
        const driver = try allocator.create(PostgresDriver);
        errdefer allocator.destroy(driver);

        const dsn = try self.toDSN(allocator);
        defer allocator.free(dsn);

        driver.* = try PostgresDriver.connect(allocator, dsn);
        errdefer driver.close() catch {};

        // 创建适配器
        const adapter = try allocator.create(PostgresDriverConnAdapter);
        errdefer allocator.destroy(adapter);
        adapter.* = .{
            .driver = driver,
            .allocator = allocator,
        };

        // 创建 Conn 接口
        const conn = core.Conn{
            .ptr = adapter,
            .vtable = &PostgresDriverConnAdapter.vtable,
        };

        // 创建 DB 实例
        return root.DB(.postgresql).init(allocator, conn, .{});
    }
};

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

// ============================================
// PostgresDriver 适配器
// ============================================

/// PostgresDriver 到 Conn 接口的适配器
const PostgresDriverConnAdapter = struct {
    driver: *PostgresDriver,
    allocator: std.mem.Allocator,

    fn exec(ptr: *anyopaque, query_str: []const u8, args: []const QueryArg) anyerror!void {
        const self: *PostgresDriverConnAdapter = @ptrCast(@alignCast(ptr));
        _ = try self.driver.exec(query_str, args);
    }

    fn query(ptr: *anyopaque, query_str: []const u8, args: []const QueryArg) anyerror!*core.Result {
        const self: *PostgresDriverConnAdapter = @ptrCast(@alignCast(ptr));
        const rows = try self.driver.query(query_str, args);

        // 创建 ResultWrapper 来适配 Rows 到 Result 接口
        const wrapper = try self.allocator.create(ResultWrapper);
        wrapper.* = .{
            .allocator = self.allocator,
        };

        // 创建 Result VTable
        const result_vtable = try self.allocator.create(core.Result.VTable);
        result_vtable.* = .{
            .next = ResultWrapper.next,
            .scan = ResultWrapper.scan,
            .close = ResultWrapper.close,
        };

        // 创建 Result 接口 - 包含 rows 字段
        const result = try self.allocator.create(core.Result);
        result.* = .{
            .ptr = wrapper,
            .vtable = result_vtable,
            .rows = rows,
        };
        return result;
    }

    fn begin(ptr: *anyopaque) anyerror!*core.Tx {
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

    const vtable = core.Conn.VTable{
        .exec = exec,
        .query = query,
        .begin = begin,
        .close = close,
    };
};

const ResultWrapper = struct {
    allocator: std.mem.Allocator,

    fn next(ptr: *anyopaque) anyerror!bool {
        _ = ptr;
        return error.NotImplemented;
    }

    fn scan(ptr: *anyopaque, dest: [][]u8) anyerror!void {
        _ = ptr;
        _ = dest;
        return error.NotImplemented;
    }

    fn close(ptr: *anyopaque) void {
        const self: *ResultWrapper = @ptrCast(@alignCast(ptr));
        self.allocator.destroy(self);
    }
};
