//! Dialect - PostgreSQL 专用方言系统
//!
//! ZORM 专注于 PostgreSQL，通过 comptime 实现零运行时开销。
//!
//! ## 主要功能
//!
//! ### 1. 特性检测 (Feature Detection)
//! - `supports(feature)` - 检查方言是否支持特定特性
//! - 便捷函数: `supportsReturning()`, `supportsUUID()`, `supportsFullTextSearch()` 等
//! - 编译时求值，确保零运行时开销
//!
//! ### 2. SQL 生成工具 (SQL Generation)
//! - `placeholder(index)` - 生成占位符 ($1, $2, ...)
//! - `quoteIdentifier(name)` - 引用标识符 ("table_name")
//! - `limitClause(limit, offset)` - 生成 LIMIT/OFFSET 子句
//! - `upsertClause()` - 生成 UPSERT 子句 (ON CONFLICT)
//! - `autoIncrementClause()` - 生成自增列语法 (SERIAL)
//! - `currentTimestamp()` - 生成当前时间戳函数 (CURRENT_TIMESTAMP)
//!
//! ### 3. 编译时方言分派 (Dialect Dispatch)
//! - `dialectDispatch(feature, callback)` - 条件执行 comptime 代码
//! - 不支持的特性在编译时触发 @compileError
//! - 确保只有受支持的 SQL 特性才能编译通过
//!
//! ## 设计原则
//!
//! 1. **Comptime 优先**: 所有决策在编译时完成，确保零运行时开销
//! 2. **PostgreSQL 专用**: 不妥协地优化 PostgreSQL，不考虑其他数据库
//! 3. **类型安全**: 利用 Zig 的 comptime 类型系统防止错误
//! 4. **零成本抽象**: 没有运行时分支，没有虚函数表
//!
//! ## 使用示例
//!
//! ```zig
//! const dialect = Dialect.postgresql;
//!
//! // 特性检测
//! if (comptime dialect.supports(.returning)) {
//!     // 使用 RETURNING 子句
//! }
//!
//! // SQL 生成
//! const ph1 = comptime dialect.placeholder(1);    // "$1"
//! const quoted = comptime dialect.quoteIdentifier("users");  // "\"users\""
//! const limit = comptime dialect.limitClause(10, 5);  // " LIMIT 10 OFFSET 5"
//!
//! // 方言分派
//! const returning = comptime dialect.dialectDispatch(.returning, struct {
//!     pub fn apply() []const u8 {
//!         return " RETURNING *";
//!     }
//! }.apply);
//! ```
//!
//! ## Comptime vs 运行时
//!
//! - **Comptime 函数**: `placeholder()`, `limitClause()` 等 - 用于静态 SQL 生成
//! - **运行时函数**: `placeholderAlloc()` - 用于动态 SQL 生成，需要 allocator
//!
//! 优先使用 comptime 函数以获得最佳性能。

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
    ///
    /// 注意: 使用穷尽性 switch 确保所有特性都被明确声明
    pub fn supports(comptime self: Dialect, comptime feature: Feature) bool {
        _ = self; // PostgreSQL 专用
        return comptime switch (feature) {
            // DML Features
            .returning => true, // PostgreSQL 完全支持
            .on_conflict => true, // PostgreSQL 完全支持
            .insert_ignore => false, // MySQL 特性, PostgreSQL 不支持
            .on_duplicate_key => false, // MySQL 特性, PostgreSQL 不支持
            .merge => true, // PostgreSQL 15+ 支持
            .upsert => true, // PostgreSQL 通过 ON CONFLICT 实现
            .output_clause => false, // SQL Server 特性, PostgreSQL 使用 RETURNING

            // Query Features
            .cte => true, // PostgreSQL 完全支持
            .window_functions => true, // PostgreSQL 完全支持
            .lateral_join => true, // PostgreSQL 完全支持

            // Data Types
            .arrays => true, // PostgreSQL 完全支持
            .jsonb => true, // PostgreSQL 完全支持
            .uuid => true, // PostgreSQL 完全支持

            // PostgreSQL Specific Features
            .generate_series => true, // PostgreSQL 专有函数
            .listen_notify => true, // PostgreSQL 专有特性
            .full_text_search => true, // PostgreSQL 专有特性

            // DDL Features
            .create_index_concurrently => true, // PostgreSQL 完全支持
            .drop_index_concurrently => true, // PostgreSQL 完全支持
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

    /// 检查是否支持全文搜索 (编译时)
    /// PostgreSQL 通过 tsvector/tsquery 完全支持
    pub fn supportsFullTextSearch(comptime self: Dialect) bool {
        return comptime self.supports(.full_text_search);
    }

    /// 检查是否支持 UUID 类型 (编译时)
    /// PostgreSQL 完全支持 UUID
    pub fn supportsUUID(comptime self: Dialect) bool {
        return comptime self.supports(.uuid);
    }

    /// 检查是否支持 generate_series 函数 (编译时)
    /// PostgreSQL 专有函数
    pub fn supportsGenerateSeries(comptime self: Dialect) bool {
        return comptime self.supports(.generate_series);
    }

    /// 检查是否支持 LISTEN/NOTIFY (编译时)
    /// PostgreSQL 专有特性
    pub fn supportsListenNotify(comptime self: Dialect) bool {
        return comptime self.supports(.listen_notify);
    }

    /// 引用标识符 (编译时)
    /// 返回被双引号包裹的标识符字符串
    /// PostgreSQL: "identifier"
    pub fn quoteIdentifier(comptime self: Dialect, comptime identifier: []const u8) []const u8 {
        const quotes = comptime self.identQuote();
        return comptime std.fmt.comptimePrint("{c}{s}{c}", .{ quotes.left, identifier, quotes.right });
    }

    // ============================================
    // 编译时方言分派
    // ============================================

    /// 编译时方言分派
    ///
    /// 如果方言不支持指定特性，在编译时触发错误。
    /// 这确保了不支持的 SQL 特性无法编译通过。
    ///
    /// 参数:
    /// - feature: 要检查的特性标志
    /// - callback: 特性支持时执行的 comptime 函数
    ///
    /// 返回:
    /// - 返回 callback 的返回值，类型由编译器自动推导
    ///
    /// 编译时错误:
    /// - 如果方言不支持该特性，触发 @compileError
    ///
    /// 示例:
    /// ```zig
    /// // ✅ 编译通过 - PostgreSQL 支持 RETURNING
    /// const returning_clause = Dialect.postgresql.dialectDispatch(.returning, struct {
    ///     pub fn apply() []const u8 {
    ///         return " RETURNING id, name";
    ///     }
    /// }.apply);
    ///
    /// // ❌ 编译错误 - PostgreSQL 不支持 OUTPUT (SQL Server 特性)
    /// const output_clause = Dialect.postgresql.dialectDispatch(.output_clause, struct {
    ///     pub fn apply() []const u8 {
    ///         return " OUTPUT INSERTED.*";
    ///     }
    /// }.apply);
    /// // 编译器错误: Dialect postgresql does not support feature output_clause
    /// ```
    pub fn dialectDispatch(
        comptime self: Dialect,
        comptime feature: Feature,
        comptime callback: anytype,
    ) @TypeOf(callback()) {
        if (comptime self.supports(feature)) {
            return callback();
        } else {
            @compileError(std.fmt.comptimePrint(
                "Dialect {s} does not support feature {s}",
                .{ @tagName(self), @tagName(feature) },
            ));
        }
    }
};

/// 数据库特性枚举
/// 按功能类别组织，便于维护和扩展
pub const Feature = enum {
    // ============================================
    // DML Features (数据操作语言特性)
    // ============================================
    /// RETURNING 子句支持 (PostgreSQL 支持)
    returning,
    /// ON CONFLICT 子句支持 (PostgreSQL 支持)
    on_conflict,
    /// INSERT IGNORE 支持 (PostgreSQL 不支持, MySQL 特性)
    insert_ignore,
    /// ON DUPLICATE KEY UPDATE 支持 (PostgreSQL 不支持, MySQL 特性)
    on_duplicate_key,
    /// MERGE 语句支持 (PostgreSQL 15+ 支持)
    merge,
    /// UPSERT 操作支持 (PostgreSQL 通过 ON CONFLICT 实现)
    upsert,
    /// OUTPUT 子句支持 (PostgreSQL 不支持, SQL Server 特性)
    output_clause,

    // ============================================
    // Query Features (查询特性)
    // ============================================
    /// CTE (Common Table Expression) 支持 (PostgreSQL 支持)
    cte,
    /// 窗口函数支持 (PostgreSQL 支持)
    window_functions,
    /// LATERAL JOIN 支持 (PostgreSQL 支持)
    lateral_join,

    // ============================================
    // Data Types (数据类型特性)
    // ============================================
    /// 数组类型支持 (PostgreSQL 支持)
    arrays,
    /// JSON/JSONB 类型支持 (PostgreSQL 支持)
    jsonb,
    /// UUID 类型支持 (PostgreSQL 支持)
    uuid,

    // ============================================
    // PostgreSQL Specific Features (PostgreSQL 专有特性)
    // ============================================
    /// generate_series 函数支持 (PostgreSQL 专有)
    generate_series,
    /// LISTEN/NOTIFY 支持 (PostgreSQL 专有)
    listen_notify,
    /// 全文搜索支持 (PostgreSQL 专有)
    full_text_search,

    // ============================================
    // DDL Features (数据定义语言特性)
    // ============================================
    /// CREATE INDEX CONCURRENTLY 支持 (PostgreSQL 支持)
    create_index_concurrently,
    /// DROP INDEX CONCURRENTLY 支持 (PostgreSQL 支持)
    drop_index_concurrently,
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

// ============================================
// Phase 1: 新增便捷特性检测函数测试
// ============================================

test "supportsFullTextSearch convenience function" {
    comptime {
        // PostgreSQL 支持全文搜索
        std.debug.assert(Dialect.postgresql.supportsFullTextSearch());
    }
}

test "supportsUUID convenience function" {
    comptime {
        // PostgreSQL 支持 UUID
        std.debug.assert(Dialect.postgresql.supportsUUID());
    }
}

test "supportsGenerateSeries convenience function" {
    comptime {
        // PostgreSQL 支持 generate_series
        std.debug.assert(Dialect.postgresql.supportsGenerateSeries());
    }
}

test "supportsListenNotify convenience function" {
    comptime {
        // PostgreSQL 支持 LISTEN/NOTIFY
        std.debug.assert(Dialect.postgresql.supportsListenNotify());
    }
}

// ============================================
// Phase 2: dialectDispatch 测试
// ============================================

test "dialectDispatch with supported feature" {
    const result = comptime Dialect.postgresql.dialectDispatch(.returning, struct {
        pub fn apply() []const u8 {
            return " RETURNING *";
        }
    }.apply);

    try std.testing.expectEqualStrings(" RETURNING *", result);
}

test "dialectDispatch with different return types" {
    // 测试返回字符串
    const str_result = comptime Dialect.postgresql.dialectDispatch(.returning, struct {
        pub fn apply() []const u8 {
            return "RETURNING id";
        }
    }.apply);
    try std.testing.expectEqualStrings("RETURNING id", str_result);

    // 测试返回布尔值
    const bool_result = comptime Dialect.postgresql.dialectDispatch(.jsonb, struct {
        pub fn apply() bool {
            return true;
        }
    }.apply);
    try std.testing.expect(bool_result);

    // 测试返回数值
    const num_result = comptime Dialect.postgresql.dialectDispatch(.cte, struct {
        pub fn apply() usize {
            return 42;
        }
    }.apply);
    try std.testing.expectEqual(@as(usize, 42), num_result);
}

test "dialectDispatch RETURNING example" {
    const returning_clause = comptime Dialect.postgresql.dialectDispatch(.returning, struct {
        pub fn apply() []const u8 {
            return " RETURNING id, name, created_at";
        }
    }.apply);

    try std.testing.expectEqualStrings(" RETURNING id, name, created_at", returning_clause);
}

test "dialectDispatch UPSERT example" {
    const upsert_clause = comptime Dialect.postgresql.dialectDispatch(.on_conflict, struct {
        pub fn apply() []const u8 {
            return " ON CONFLICT (email) DO UPDATE SET updated_at = CURRENT_TIMESTAMP";
        }
    }.apply);

    try std.testing.expect(std.mem.indexOf(u8, upsert_clause, "ON CONFLICT") != null);
}

test "dialectDispatch with complex callback" {
    const limit_clause = comptime Dialect.postgresql.dialectDispatch(.cte, struct {
        pub fn apply() []const u8 {
            return " LIMIT 10 OFFSET 5";
        }
    }.apply);

    try std.testing.expectEqualStrings(" LIMIT 10 OFFSET 5", limit_clause);
}

// 注意: 无法直接测试 dialectDispatch 的编译错误场景
// 因为 @compileError 会导致测试编译失败
// 以下代码是编译错误示例（已注释）:
//
// test "dialectDispatch with unsupported feature - COMPILE ERROR EXAMPLE" {
//     // ❌ 这会导致编译错误
//     const output_clause = comptime Dialect.postgresql.dialectDispatch(.output_clause, struct {
//         pub fn apply() []const u8 {
//             return " OUTPUT INSERTED.*";
//         }
//     }.apply);
//     // 编译器错误: Dialect postgresql does not support feature output_clause
// }

// ============================================
// Phase 4: 完整特性测试
// ============================================

test "all features have supports() implementation" {
    comptime {
        // 遍历所有 Feature 枚举值，确保每个都有 supports() 实现
        const feature_info = @typeInfo(Feature);
        switch (feature_info) {
            .@"enum" => |enum_info| {
                for (enum_info.fields) |field| {
                    const feature: Feature = @enumFromInt(field.value);
                    _ = Dialect.postgresql.supports(feature);
                    // 如果 supports() 没有穷尽所有枚举值，编译会失败
                }
            },
            else => @compileError("Feature must be an enum"),
        }
    }
}

test "PostgreSQL supported features" {
    comptime {
        // DML Features
        std.debug.assert(Dialect.postgresql.supports(.returning) == true);
        std.debug.assert(Dialect.postgresql.supports(.on_conflict) == true);
        std.debug.assert(Dialect.postgresql.supports(.merge) == true);
        std.debug.assert(Dialect.postgresql.supports(.upsert) == true);

        // Query Features
        std.debug.assert(Dialect.postgresql.supports(.cte) == true);
        std.debug.assert(Dialect.postgresql.supports(.window_functions) == true);
        std.debug.assert(Dialect.postgresql.supports(.lateral_join) == true);

        // Data Types
        std.debug.assert(Dialect.postgresql.supports(.arrays) == true);
        std.debug.assert(Dialect.postgresql.supports(.jsonb) == true);
        std.debug.assert(Dialect.postgresql.supports(.uuid) == true);

        // PostgreSQL Specific
        std.debug.assert(Dialect.postgresql.supports(.generate_series) == true);
        std.debug.assert(Dialect.postgresql.supports(.listen_notify) == true);
        std.debug.assert(Dialect.postgresql.supports(.full_text_search) == true);

        // DDL Features
        std.debug.assert(Dialect.postgresql.supports(.create_index_concurrently) == true);
        std.debug.assert(Dialect.postgresql.supports(.drop_index_concurrently) == true);
    }
}

test "PostgreSQL unsupported features" {
    comptime {
        // MySQL 特性
        std.debug.assert(Dialect.postgresql.supports(.insert_ignore) == false);
        std.debug.assert(Dialect.postgresql.supports(.on_duplicate_key) == false);

        // SQL Server 特性
        std.debug.assert(Dialect.postgresql.supports(.output_clause) == false);
    }
}

test "zero runtime overhead - comptime only" {
    comptime {
        // 所有方言函数必须在编译时求值
        const ph = Dialect.postgresql.placeholder(1);
        const quoted = Dialect.postgresql.quoteIdentifier("users");
        const limit = Dialect.postgresql.limitClause(10, 5);
        const upsert = Dialect.postgresql.upsertClause();
        const auto_inc = Dialect.postgresql.autoIncrementClause();
        const ts = Dialect.postgresql.currentTimestamp();
        const supports_ret = Dialect.postgresql.supportsReturning();

        // 验证类型为编译时已知
        _ = ph;
        _ = quoted;
        _ = limit;
        _ = upsert;
        _ = auto_inc;
        _ = ts;
        _ = supports_ret;

        // 如果这些不是 comptime，会导致编译错误
    }
}

test "autoIncrementClause function" {
    comptime {
        const pg_auto_inc = Dialect.postgresql.autoIncrementClause();
        std.debug.assert(std.mem.eql(u8, pg_auto_inc, "SERIAL"));
    }
}

test "currentTimestamp function" {
    comptime {
        const pg_ts = Dialect.postgresql.currentTimestamp();
        std.debug.assert(std.mem.eql(u8, pg_ts, "CURRENT_TIMESTAMP"));
    }
}
