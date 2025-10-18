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
            .host = std.posix.getenv("ZORM_DB_HOST") orelse "127.0.0.1",
            .port = if (std.posix.getenv("ZORM_DB_PORT")) |port_str|
                std.fmt.parseInt(u16, port_str, 10) catch 5432
            else
                5432,
            .user = std.posix.getenv("ZORM_DB_USER") orelse "pguser",
            .password = std.posix.getenv("ZORM_DB_PASSWORD") orelse "Pg#123!",
            .database = std.posix.getenv("ZORM_DB_NAME") orelse "postgres",
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
