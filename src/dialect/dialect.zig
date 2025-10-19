//! Dialect - PostgreSQL 专用方言系统
//!
//! ZORM 专注于 PostgreSQL，通过 comptime 实现零运行时开销。
//! 定义了:
//! - SQL 占位符语法 ($1, $2, ...)
//! - PostgreSQL 特性集
//! - PostgreSQL 特定的 SQL 语法

const std = @import("std");

/// PostgreSQL 数据库方言
/// 注意：ZORM 仅支持 PostgreSQL
pub const Dialect = enum {
    postgresql,

    /// 获取占位符语法 (运行时)
    /// PostgreSQL: $1, $2, ...
    ///
    /// 注意: 使用 allocPrint 分配内存,调用者负责释放
    pub fn placeholderAlloc(comptime self: Dialect, allocator: std.mem.Allocator, index: usize) ![]const u8 {
        _ = self; // PostgreSQL 专用
        return try std.fmt.allocPrint(allocator, "${d}", .{index});
    }

    /// 获取占位符语法 (编译时 - 用于测试和静态 SQL 生成)
    /// 注意: index 必须是 comptime 已知的值
    pub fn placeholder(comptime self: Dialect, comptime index: usize) []const u8 {
        _ = self; // PostgreSQL 专用
        return comptime std.fmt.comptimePrint("${d}", .{index});
    }

    /// 获取标识符引用字符 (编译时)
    /// PostgreSQL 使用双引号: "identifier"
    pub fn identQuote(comptime self: Dialect) struct { left: u8, right: u8 } {
        _ = self; // PostgreSQL 专用
        return .{ .left = '"', .right = '"' };
    }

    /// 检查是否支持特定功能 (编译时)
    /// PostgreSQL 支持几乎所有现代 SQL 特性
    pub fn supports(comptime self: Dialect, comptime feature: Feature) bool {
        _ = self; // PostgreSQL 专用
        return comptime switch (feature) {
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
        };
    }

    /// 获取 UPSERT 语法 (编译时)
    /// PostgreSQL: ON CONFLICT
    pub fn upsertClause(comptime self: Dialect) []const u8 {
        _ = self; // PostgreSQL 专用
        return "ON CONFLICT";
    }

    /// 获取 LIMIT 语法 (编译时)
    ///
    /// 注意: limit 和 offset 必须是 comptime 已知的值。
    /// 对于运行时 LIMIT/OFFSET,应由查询构建器动态生成 SQL。
    ///
    /// 示例:
    /// ```zig
    /// const clause1 = Dialect.postgresql.limitClause(10, null);    // " LIMIT 10"
    /// const clause2 = Dialect.postgresql.limitClause(10, 5);       // " LIMIT 10 OFFSET 5"
    /// const clause3 = Dialect.postgresql.limitClause(null, 5);     // " OFFSET 5"
    /// ```
    pub fn limitClause(comptime self: Dialect, comptime limit: ?usize, comptime offset: ?usize) []const u8 {
        _ = self; // PostgreSQL 专用
        return comptime blk: {
            if (limit) |l| {
                if (offset) |o| {
                    break :blk std.fmt.comptimePrint(" LIMIT {d} OFFSET {d}", .{ l, o });
                } else {
                    break :blk std.fmt.comptimePrint(" LIMIT {d}", .{l});
                }
            } else if (offset) |o| {
                // PostgreSQL 支持只有 OFFSET
                break :blk std.fmt.comptimePrint(" OFFSET {d}", .{o});
            } else {
                break :blk "";
            }
        };
    }

    /// 获取自动递增列的语法 (编译时)
    /// PostgreSQL: SERIAL 或 GENERATED ALWAYS AS IDENTITY
    pub fn autoIncrementClause(comptime self: Dialect) []const u8 {
        _ = self; // PostgreSQL 专用
        return "SERIAL";
    }

    /// 获取当前时间戳函数 (编译时)
    /// PostgreSQL: CURRENT_TIMESTAMP
    pub fn currentTimestamp(comptime self: Dialect) []const u8 {
        _ = self; // PostgreSQL 专用
        return "CURRENT_TIMESTAMP";
    }

    // ============================================
    // 便捷特性检测函数
    // ============================================

    /// 检查是否支持 RETURNING 子句 (编译时)
    /// PostgreSQL 完全支持 RETURNING
    pub fn supportsReturning(comptime self: Dialect) bool {
        return comptime self.supports(.returning);
    }

    /// 检查是否支持 ON CONFLICT 子句 (编译时)
    /// PostgreSQL 完全支持 ON CONFLICT
    pub fn supportsOnConflict(comptime self: Dialect) bool {
        return comptime self.supports(.on_conflict);
    }

    /// 检查是否支持 CTE (Common Table Expression) (编译时)
    /// PostgreSQL 完全支持 CTE
    pub fn supportsCTE(comptime self: Dialect) bool {
        return comptime self.supports(.cte);
    }

    /// 检查是否支持 JSONB 类型 (编译时)
    /// PostgreSQL 完全支持 JSONB
    pub fn supportsJSONB(comptime self: Dialect) bool {
        return comptime self.supports(.jsonb);
    }

    /// 引用标识符 (编译时)
    /// 返回被双引号包裹的标识符字符串
    /// PostgreSQL: "identifier"
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
    }
}

test "dialect features" {
    comptime {
        // PostgreSQL 支持所有核心特性
        std.debug.assert(Dialect.postgresql.supports(.returning));
        std.debug.assert(Dialect.postgresql.supports(.on_conflict));
        std.debug.assert(Dialect.postgresql.supports(.cte));
        std.debug.assert(Dialect.postgresql.supports(.jsonb));
    }
}

test "dialect ident quote" {
    comptime {
        const pg_quote = Dialect.postgresql.identQuote();
        std.debug.assert(pg_quote.left == '"');
        std.debug.assert(pg_quote.right == '"');
    }
}

test "dialect upsert" {
    comptime {
        const pg_upsert = Dialect.postgresql.upsertClause();
        std.debug.assert(std.mem.eql(u8, pg_upsert, "ON CONFLICT"));
    }
}

test "supportsReturning convenience function" {
    comptime {
        // PostgreSQL 支持 RETURNING
        std.debug.assert(Dialect.postgresql.supportsReturning());
    }
}

test "supportsOnConflict convenience function" {
    comptime {
        // PostgreSQL 支持 ON CONFLICT
        std.debug.assert(Dialect.postgresql.supportsOnConflict());
    }
}

test "supportsCTE convenience function" {
    comptime {
        // PostgreSQL 支持 CTE
        std.debug.assert(Dialect.postgresql.supportsCTE());
    }
}

test "supportsJSONB convenience function" {
    comptime {
        // PostgreSQL 支持 JSONB
        std.debug.assert(Dialect.postgresql.supportsJSONB());
    }
}

test "quoteIdentifier function" {
    comptime {
        // PostgreSQL: "users"
        const pg_quoted = Dialect.postgresql.quoteIdentifier("users");
        std.debug.assert(std.mem.eql(u8, pg_quoted, "\"users\""));
    }
}

test "all dialect placeholders" {
    comptime {
        // PostgreSQL: $1, $2, $3
        std.debug.assert(std.mem.eql(u8, Dialect.postgresql.placeholder(1), "$1"));
        std.debug.assert(std.mem.eql(u8, Dialect.postgresql.placeholder(2), "$2"));
        std.debug.assert(std.mem.eql(u8, Dialect.postgresql.placeholder(3), "$3"));
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

test "limitClause comptime safety" {
    comptime {
        // PostgreSQL: LIMIT + OFFSET
        const pg1 = Dialect.postgresql.limitClause(10, 5);
        std.debug.assert(std.mem.eql(u8, pg1, " LIMIT 10 OFFSET 5"));

        // PostgreSQL: 只有 LIMIT
        const pg2 = Dialect.postgresql.limitClause(10, null);
        std.debug.assert(std.mem.eql(u8, pg2, " LIMIT 10"));

        // PostgreSQL: 只有 OFFSET (PostgreSQL 支持)
        const pg3 = Dialect.postgresql.limitClause(null, 5);
        std.debug.assert(std.mem.eql(u8, pg3, " OFFSET 5"));
    }
}
