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

    /// 获取占位符语法 (运行时)
    /// PostgreSQL: $1, $2, ...
    /// MySQL/SQLite: ?, ?, ...
    ///
    /// 注意: 对于 PostgreSQL,需要使用 allocPrint 分配内存,调用者负责释放
    pub fn placeholderAlloc(comptime self: Dialect, allocator: std.mem.Allocator, index: usize) ![]const u8 {
        return switch (self) {
            .postgresql => try std.fmt.allocPrint(allocator, "${d}", .{index}),
            .mysql, .sqlite => "?",
        };
    }

    /// 获取占位符语法 (编译时 - 仅用于测试)
    /// 注意: index 必须是 comptime 已知的值
    pub fn placeholder(comptime self: Dialect, comptime index: usize) []const u8 {
        return comptime switch (self) {
            .postgresql => std.fmt.comptimePrint("${d}", .{index}),
            .mysql, .sqlite => "?",
        };
    }

    /// 获取标识符引用字符 (编译时)
    pub fn identQuote(comptime self: Dialect) struct { left: u8, right: u8 } {
        return comptime switch (self) {
            .postgresql, .sqlite => .{ .left = '"', .right = '"' },
            .mysql => .{ .left = '`', .right = '`' },
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
        };
    }

    /// 获取 UPSERT 语法 (编译时)
    pub fn upsertClause(comptime self: Dialect) []const u8 {
        return comptime switch (self) {
            .postgresql => "ON CONFLICT",
            .mysql => "ON DUPLICATE KEY UPDATE",
            .sqlite => "ON CONFLICT",
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
        };
    }

    /// 获取自动递增列的语法 (编译时)
    pub fn autoIncrementClause(comptime self: Dialect) []const u8 {
        return comptime switch (self) {
            .postgresql => "SERIAL",
            .mysql => "AUTO_INCREMENT",
            .sqlite => "AUTOINCREMENT",
        };
    }

    /// 获取当前时间戳函数 (编译时)
    pub fn currentTimestamp(comptime self: Dialect) []const u8 {
        return comptime switch (self) {
            .postgresql => "CURRENT_TIMESTAMP",
            .mysql => "CURRENT_TIMESTAMP",
            .sqlite => "CURRENT_TIMESTAMP",
        };
    }

    // ============================================
    // 便捷特性检测函数 (按 Story 007 规范)
    // ============================================

    /// 检查是否支持 RETURNING 子句 (编译时)
    pub fn supportsReturning(comptime self: Dialect) bool {
        return comptime self.supports(.returning);
    }

    /// 检查是否支持 ON CONFLICT 子句 (编译时)
    pub fn supportsOnConflict(comptime self: Dialect) bool {
        return comptime self.supports(.on_conflict);
    }

    /// 检查是否支持 CTE (Common Table Expression) (编译时)
    pub fn supportsCTE(comptime self: Dialect) bool {
        return comptime self.supports(.cte);
    }

    /// 检查是否支持 JSONB 类型 (编译时)
    pub fn supportsJSONB(comptime self: Dialect) bool {
        return comptime self.supports(.jsonb);
    }

    /// 引用标识符 (编译时)
    /// 返回被引号包裹的标识符字符串
    pub fn quoteIdentifier(comptime self: Dialect, comptime identifier: []const u8) []const u8 {
        const quotes = comptime self.identQuote();
        return comptime std.fmt.comptimePrint("{c}{s}{c}", .{ quotes.left, identifier, quotes.right });
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

// ============================================
// Story 007: 新增便捷 API 测试
// ============================================

test "supportsReturning convenience function" {
    comptime {
        // PostgreSQL 支持 RETURNING
        std.debug.assert(Dialect.postgresql.supportsReturning());

        // MySQL 不支持 RETURNING
        std.debug.assert(!Dialect.mysql.supportsReturning());

        // SQLite 支持 RETURNING
        std.debug.assert(Dialect.sqlite.supportsReturning());
    }
}

test "supportsOnConflict convenience function" {
    comptime {
        // PostgreSQL 支持 ON CONFLICT
        std.debug.assert(Dialect.postgresql.supportsOnConflict());

        // MySQL 不支持 ON CONFLICT
        std.debug.assert(!Dialect.mysql.supportsOnConflict());

        // SQLite 支持 ON CONFLICT
        std.debug.assert(Dialect.sqlite.supportsOnConflict());
    }
}

test "supportsCTE convenience function" {
    comptime {
        // 所有数据库都支持 CTE
        std.debug.assert(Dialect.postgresql.supportsCTE());
        std.debug.assert(Dialect.mysql.supportsCTE());
        std.debug.assert(Dialect.sqlite.supportsCTE());
    }
}

test "supportsJSONB convenience function" {
    comptime {
        // 所有主流数据库都支持 JSON/JSONB
        std.debug.assert(Dialect.postgresql.supportsJSONB());
        std.debug.assert(Dialect.mysql.supportsJSONB());
        std.debug.assert(Dialect.sqlite.supportsJSONB());
    }
}

test "quoteIdentifier function" {
    comptime {
        // PostgreSQL: "users"
        const pg_quoted = Dialect.postgresql.quoteIdentifier("users");
        std.debug.assert(std.mem.eql(u8, pg_quoted, "\"users\""));

        // MySQL: `users`
        const mysql_quoted = Dialect.mysql.quoteIdentifier("users");
        std.debug.assert(std.mem.eql(u8, mysql_quoted, "`users`"));

        // SQLite: "users"
        const sqlite_quoted = Dialect.sqlite.quoteIdentifier("users");
        std.debug.assert(std.mem.eql(u8, sqlite_quoted, "\"users\""));
    }
}

test "all dialect placeholders" {
    comptime {
        // PostgreSQL: $1, $2, $3
        std.debug.assert(std.mem.eql(u8, Dialect.postgresql.placeholder(1), "$1"));
        std.debug.assert(std.mem.eql(u8, Dialect.postgresql.placeholder(2), "$2"));

        // MySQL: ?, ?, ?
        std.debug.assert(std.mem.eql(u8, Dialect.mysql.placeholder(1), "?"));
        std.debug.assert(std.mem.eql(u8, Dialect.mysql.placeholder(2), "?"));

        // SQLite: ?, ?, ?
        std.debug.assert(std.mem.eql(u8, Dialect.sqlite.placeholder(1), "?"));
    }
}

test "comptime evaluation - zero runtime cost" {
    // 编译时验证：所有方言函数都必须在编译时求值
    comptime {
        // 特性检测必须在编译时完成
        const pg_returning = Dialect.postgresql.supportsReturning();
        _ = pg_returning;

        // 占位符生成必须在编译时完成
        const pg_ph = Dialect.postgresql.placeholder(1);
        _ = pg_ph;

        // 标识符引用必须在编译时完成
        const pg_quoted = Dialect.postgresql.quoteIdentifier("table_name");
        _ = pg_quoted;

        // 如果这些不是 comptime，编译会失败
    }
}
