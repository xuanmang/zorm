//! Schema - 数据库模式管理
//!
//! 提供:
//! - 表结构定义和反射
//! - 模式迁移
//! - 类型映射

const std = @import("std");

/// 列类型
pub const ColumnType = enum {
    int,
    bigint,
    smallint,
    boolean,
    varchar,
    text,
    timestamp,
    date,
    time,
    decimal,
    float,
    double,
    json,
    jsonb,
    uuid,
    bytea,

    /// 获取 SQL 类型名称
    pub fn sqlType(self: ColumnType, comptime dialect: @import("../dialect/dialect.zig").Dialect) []const u8 {
        return switch (dialect) {
            .postgresql => switch (self) {
                .int => "INTEGER",
                .bigint => "BIGINT",
                .smallint => "SMALLINT",
                .boolean => "BOOLEAN",
                .varchar => "VARCHAR",
                .text => "TEXT",
                .timestamp => "TIMESTAMP",
                .date => "DATE",
                .time => "TIME",
                .decimal => "DECIMAL",
                .float => "REAL",
                .double => "DOUBLE PRECISION",
                .json => "JSON",
                .jsonb => "JSONB",
                .uuid => "UUID",
                .bytea => "BYTEA",
            },
            .mysql => switch (self) {
                .int => "INT",
                .bigint => "BIGINT",
                .smallint => "SMALLINT",
                .boolean => "BOOLEAN",
                .varchar => "VARCHAR",
                .text => "TEXT",
                .timestamp => "TIMESTAMP",
                .date => "DATE",
                .time => "TIME",
                .decimal => "DECIMAL",
                .float => "FLOAT",
                .double => "DOUBLE",
                .json => "JSON",
                .jsonb => "JSON",
                .uuid => "CHAR(36)",
                .bytea => "BLOB",
            },
            .sqlite => switch (self) {
                .int, .bigint, .smallint => "INTEGER",
                .boolean => "INTEGER",
                .varchar, .text => "TEXT",
                .timestamp, .date, .time => "TEXT",
                .decimal, .float, .double => "REAL",
                .json, .jsonb => "TEXT",
                .uuid => "TEXT",
                .bytea => "BLOB",
            },
        };
    }
};

/// 表元数据
pub const TableMeta = struct {
    name: []const u8,
    columns: []const ColumnMeta,
};

/// 列元数据
pub const ColumnMeta = struct {
    name: []const u8,
    type: ColumnType,
    nullable: bool = true,
    primary_key: bool = false,
    auto_increment: bool = false,
    default_value: ?[]const u8 = null,
};

/// 从 Zig 类型获取表元数据 (编译时)
pub fn getTableMeta(comptime T: type) TableMeta {
    // TODO: 实现完整的类型反射
    return .{
        .name = @typeName(T),
        .columns = &.{},
    };
}
