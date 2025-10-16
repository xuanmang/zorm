//! Dialect - 数据库方言系统
//!
//! 通过 comptime 实现零运行时开销的多数据库支持。
//! 每个方言定义了:
//! - SQL 占位符语法
//! - 支持的特性集
//! - 特定的 SQL 语法变体

const std = @import("std");

/// 支持的数据库方言
pub const Dialect = enum {
    postgresql,
    mysql,
    sqlite,
    mssql,
    oracle,

    /// 获取占位符语法 (编译时)
    /// PostgreSQL: $1, $2, ...
    /// MySQL/SQLite: ?, ?, ...
    /// MSSQL: @p1, @p2, ...
    /// Oracle: :1, :2, ...
    pub fn placeholder(comptime self: Dialect, index: usize) []const u8 {
        return comptime switch (self) {
            .postgresql => blk: {
                var buf: [16]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "${d}", .{index}) catch unreachable;
                break :blk str[0..str.len].*;
            },
            .mysql, .sqlite => "?",
            .mssql => blk: {
                var buf: [16]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "@p{d}", .{index}) catch unreachable;
                break :blk str[0..str.len].*;
            },
            .oracle => blk: {
                var buf: [16]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, ":{d}", .{index}) catch unreachable;
                break :blk str[0..str.len].*;
            },
        };
    }

    /// 获取标识符引用字符 (编译时)
    pub fn identQuote(comptime self: Dialect) struct { left: u8, right: u8 } {
        return comptime switch (self) {
            .postgresql, .sqlite => .{ .left = '"', .right = '"' },
            .mysql => .{ .left = '`', .right = '`' },
            .mssql => .{ .left = '[', .right = ']' },
            .oracle => .{ .left = '"', .right = '"' },
        };
    }

    /// 检查是否支持特定功能 (编译时)
    pub fn supports(comptime self: Dialect, comptime feature: Feature) bool {
        return comptime switch (self) {
            .postgresql => switch (feature) {
                .returning => true,
                .cte => true,
                .arrays => true,
                .jsonb => true,
                .on_conflict => true,
                .window_functions => true,
                .lateral_join => true,
                .upsert => true,
                .generate_series => true,
                .listen_notify => true,
            },
            .mysql => switch (feature) {
                .returning => false, // MySQL 8.0.21+ 支持,但这里简化为 false
                .cte => true, // MySQL 8.0+
                .arrays => false,
                .jsonb => true, // JSON 类型
                .on_conflict => false,
                .window_functions => true, // MySQL 8.0+
                .lateral_join => false,
                .upsert => true, // ON DUPLICATE KEY UPDATE
                .generate_series => false,
                .listen_notify => false,
            },
            .sqlite => switch (feature) {
                .returning => true, // SQLite 3.35.0+
                .cte => true,
                .arrays => false,
                .jsonb => true, // JSON 函数支持
                .on_conflict => true,
                .window_functions => true, // SQLite 3.25.0+
                .lateral_join => false,
                .upsert => true,
                .generate_series => true, // generate_series() 函数
                .listen_notify => false,
            },
            .mssql => switch (feature) {
                .returning => true, // OUTPUT 子句
                .cte => true,
                .arrays => false,
                .jsonb => true, // JSON 函数支持
                .on_conflict => false,
                .window_functions => true,
                .lateral_join => true, // CROSS APPLY
                .upsert => true, // MERGE
                .generate_series => false,
                .listen_notify => false,
            },
            .oracle => switch (feature) {
                .returning => true,
                .cte => true,
                .arrays => true, // VARRAY, NESTED TABLE
                .jsonb => true, // JSON 类型
                .on_conflict => false,
                .window_functions => true,
                .lateral_join => true,
                .upsert => true, // MERGE
                .generate_series => false,
                .listen_notify => false,
            },
        };
    }

    /// 获取 UPSERT 语法 (编译时)
    pub fn upsertClause(comptime self: Dialect) []const u8 {
        return comptime switch (self) {
            .postgresql => "ON CONFLICT",
            .mysql => "ON DUPLICATE KEY UPDATE",
            .sqlite => "ON CONFLICT",
            .mssql => "MERGE", // MSSQL 使用 MERGE 语句
            .oracle => "MERGE",
        };
    }

    /// 获取 LIMIT 语法 (编译时)
    pub fn limitClause(comptime self: Dialect, limit: ?usize, offset: ?usize) []const u8 {
        return comptime switch (self) {
            .postgresql, .mysql, .sqlite => blk: {
                var buf: [64]u8 = undefined;
                var str: []const u8 = "";

                if (limit) |l| {
                    str = std.fmt.bufPrint(&buf, " LIMIT {d}", .{l}) catch unreachable;

                    if (offset) |o| {
                        str = std.fmt.bufPrint(&buf, " LIMIT {d} OFFSET {d}", .{ l, o }) catch unreachable;
                    }
                } else if (offset) |o| {
                    // PostgreSQL 支持只有 OFFSET
                    if (self == .postgresql) {
                        str = std.fmt.bufPrint(&buf, " OFFSET {d}", .{o}) catch unreachable;
                    }
                }

                break :blk str[0..str.len].*;
            },
            .mssql => blk: {
                // MSSQL 使用 OFFSET FETCH
                var buf: [64]u8 = undefined;
                var str: []const u8 = "";

                if (offset) |o| {
                    if (limit) |l| {
                        str = std.fmt.bufPrint(&buf, " OFFSET {d} ROWS FETCH NEXT {d} ROWS ONLY", .{ o, l }) catch unreachable;
                    } else {
                        str = std.fmt.bufPrint(&buf, " OFFSET {d} ROWS", .{o}) catch unreachable;
                    }
                } else if (limit) |l| {
                    str = std.fmt.bufPrint(&buf, " OFFSET 0 ROWS FETCH NEXT {d} ROWS ONLY", .{l}) catch unreachable;
                }

                break :blk str[0..str.len].*;
            },
            .oracle => blk: {
                // Oracle 12c+ 使用 OFFSET FETCH
                var buf: [64]u8 = undefined;
                var str: []const u8 = "";

                if (offset) |o| {
                    if (limit) |l| {
                        str = std.fmt.bufPrint(&buf, " OFFSET {d} ROWS FETCH NEXT {d} ROWS ONLY", .{ o, l }) catch unreachable;
                    } else {
                        str = std.fmt.bufPrint(&buf, " OFFSET {d} ROWS", .{o}) catch unreachable;
                    }
                } else if (limit) |l| {
                    str = std.fmt.bufPrint(&buf, " FETCH NEXT {d} ROWS ONLY", .{l}) catch unreachable;
                }

                break :blk str[0..str.len].*;
            },
        };
    }

    /// 获取自动递增列的语法 (编译时)
    pub fn autoIncrementClause(comptime self: Dialect) []const u8 {
        return comptime switch (self) {
            .postgresql => "SERIAL",
            .mysql => "AUTO_INCREMENT",
            .sqlite => "AUTOINCREMENT",
            .mssql => "IDENTITY(1,1)",
            .oracle => "GENERATED ALWAYS AS IDENTITY",
        };
    }

    /// 获取当前时间戳函数 (编译时)
    pub fn currentTimestamp(comptime self: Dialect) []const u8 {
        return comptime switch (self) {
            .postgresql => "CURRENT_TIMESTAMP",
            .mysql => "CURRENT_TIMESTAMP",
            .sqlite => "CURRENT_TIMESTAMP",
            .mssql => "GETDATE()",
            .oracle => "CURRENT_TIMESTAMP",
        };
    }
};

/// 数据库特性枚举
pub const Feature = enum {
    /// RETURNING 子句支持
    returning,
    /// CTE (Common Table Expression) 支持
    cte,
    /// 数组类型支持
    arrays,
    /// JSON/JSONB 类型支持
    jsonb,
    /// ON CONFLICT 支持
    on_conflict,
    /// 窗口函数支持
    window_functions,
    /// LATERAL JOIN 支持
    lateral_join,
    /// UPSERT 操作支持
    upsert,
    /// generate_series 函数支持
    generate_series,
    /// LISTEN/NOTIFY 支持
    listen_notify,
};

// 编译时测试
test "dialect placeholder" {
    comptime {
        const pg_ph = Dialect.postgresql.placeholder(1);
        std.debug.assert(std.mem.eql(u8, pg_ph, "$1"));

        const mysql_ph = Dialect.mysql.placeholder(1);
        std.debug.assert(std.mem.eql(u8, mysql_ph, "?"));
    }
}

test "dialect features" {
    comptime {
        // PostgreSQL 支持 RETURNING
        std.debug.assert(Dialect.postgresql.supports(.returning));

        // MySQL 不支持 RETURNING
        std.debug.assert(!Dialect.mysql.supports(.returning));

        // SQLite 支持 RETURNING
        std.debug.assert(Dialect.sqlite.supports(.returning));
    }
}

test "dialect ident quote" {
    comptime {
        const pg_quote = Dialect.postgresql.identQuote();
        std.debug.assert(pg_quote.left == '"');
        std.debug.assert(pg_quote.right == '"');

        const mysql_quote = Dialect.mysql.identQuote();
        std.debug.assert(mysql_quote.left == '`');
        std.debug.assert(mysql_quote.right == '`');
    }
}

test "dialect upsert" {
    comptime {
        const pg_upsert = Dialect.postgresql.upsertClause();
        std.debug.assert(std.mem.eql(u8, pg_upsert, "ON CONFLICT"));

        const mysql_upsert = Dialect.mysql.upsertClause();
        std.debug.assert(std.mem.eql(u8, mysql_upsert, "ON DUPLICATE KEY UPDATE"));
    }
}
