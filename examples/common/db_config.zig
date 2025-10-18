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
pub fn getDefaultConfig() DBConfig {
    return .{
        .host = "127.0.0.1",
        .port = 5432,
        .user = "pguser",
        .password = "Pg#123!",
        .dbname = "postgres",
    };
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
