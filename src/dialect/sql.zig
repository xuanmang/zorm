//! SQL 生成工具函数
//!
//! 提供安全的 SQL 生成工具,防止 SQL 注入:
//! - escapeIdentifier: 转义标识符(表名/列名)
//! - escapeString: 转义字符串字面量
//! - generatePlaceholders: 生成占位符数组
//! - buildInClause: 构建 IN 子句
//!
//! 所有函数都支持编译时和运行时使用,专为 PostgreSQL 优化。

const std = @import("std");
const Dialect = @import("dialect.zig").Dialect;
const Allocator = std.mem.Allocator;

// ============================================
// 1. 标识符转义 (Identifier Escaping)
// ============================================

/// 转义 SQL 标识符 (表名、列名等)
///
/// PostgreSQL 使用双引号包裹标识符: "identifier"
///
/// 如果标识符内包含双引号,会进行双写转义。
///
/// 参数:
/// - allocator: 内存分配器
/// - dialect: 数据库方言 (仅支持 PostgreSQL)
/// - identifier: 需要转义的标识符
///
/// 返回: 转义后的标识符字符串
///
/// 示例:
/// ```zig
/// const escaped = try escapeIdentifier(allocator, .postgresql, "user_table");
/// // 结果: "user_table"
///
/// const escaped2 = try escapeIdentifier(allocator, .postgresql, "user\"table");
/// // 结果: "user""table"
/// ```
pub fn escapeIdentifier(
    allocator: Allocator,
    comptime dialect: Dialect,
    identifier: []const u8,
) ![]const u8 {
    const quotes = comptime dialect.identQuote();
    const quote_char = quotes.left;

    // 检查是否需要转义 (是否包含引号字符)
    var needs_escape = false;
    for (identifier) |c| {
        if (c == quote_char) {
            needs_escape = true;
            break;
        }
    }

    if (!needs_escape) {
        // 快速路径: 不需要转义,直接添加引号
        return std.fmt.allocPrint(allocator, "{c}{s}{c}", .{
            quote_char,
            identifier,
            quotes.right,
        });
    }

    // 慢速路径: 需要转义引号字符 (双写)
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.append(quote_char);

    for (identifier) |c| {
        try result.append(c);
        // 如果是引号字符,需要双写
        if (c == quote_char) {
            try result.append(c);
        }
    }

    try result.append(quotes.right);

    return result.toOwnedSlice();
}

// ============================================
// 2. 字符串转义 (String Escaping)
// ============================================

/// 转义 SQL 字符串字面量
///
/// 将字符串转义为安全的 SQL 字符串字面量格式。
/// PostgreSQL 使用单引号包裹,单引号需要双写转义。
/// 同时处理特殊字符:
/// - 单引号 ' -> ''
/// - NULL 字节、换行符等控制字符
///
/// 参数:
/// - allocator: 内存分配器
/// - dialect: 数据库方言 (仅支持 PostgreSQL)
/// - str: 需要转义的字符串
///
/// 返回: 转义后的字符串字面量 (包含单引号)
///
/// 示例:
/// ```zig
/// const escaped = try escapeString(allocator, .postgresql, "hello world");
/// // 结果: 'hello world'
///
/// const escaped2 = try escapeString(allocator, .postgresql, "it's");
/// // 结果: 'it''s'
/// ```
pub fn escapeString(
    allocator: Allocator,
    comptime dialect: Dialect,
    str: []const u8,
) ![]const u8 {
    _ = dialect; // PostgreSQL 专用

    // 检查是否需要转义
    var needs_escape = false;
    for (str) |c| {
        if (c == '\'' or c == '\\' or c == 0 or c == '\n' or c == '\r' or c == '\t') {
            needs_escape = true;
            break;
        }
    }

    if (!needs_escape) {
        // 快速路径: 不需要转义,直接添加单引号
        return std.fmt.allocPrint(allocator, "'{s}'", .{str});
    }

    // 慢速路径: 需要转义特殊字符
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.append('\'');

    for (str) |c| {
        switch (c) {
            '\'' => {
                // 单引号双写转义 (PostgreSQL 标准)
                try result.appendSlice("''");
            },
            '\\' => {
                // PostgreSQL 不需要转义反斜杠 (使用标准 SQL)
                try result.append('\\');
            },
            0 => {
                // NULL 字节: 使用 \0 表示
                try result.appendSlice("\\0");
            },
            '\n' => {
                // 换行符: 使用 \n 表示
                try result.appendSlice("\\n");
            },
            '\r' => {
                // 回车符: 使用 \r 表示
                try result.appendSlice("\\r");
            },
            '\t' => {
                // 制表符: 使用 \t 表示
                try result.appendSlice("\\t");
            },
            else => {
                try result.append(c);
            },
        }
    }

    try result.append('\'');

    return result.toOwnedSlice();
}

// ============================================
// 3. 占位符生成 (Placeholder Generation)
// ============================================

/// 生成占位符数组
///
/// PostgreSQL 使用位置占位符: $1, $2, $3, ...
///
/// 参数:
/// - allocator: 内存分配器
/// - dialect: 数据库方言 (仅支持 PostgreSQL)
/// - count: 占位符数量
/// - start_index: 起始索引 (默认为 1)
///
/// 返回: 占位符字符串数组的切片
///
/// 示例:
/// ```zig
/// const placeholders = try generatePlaceholders(allocator, .postgresql, 3, 1);
/// // 结果: ["$1", "$2", "$3"]
/// ```
pub fn generatePlaceholders(
    allocator: Allocator,
    comptime dialect: Dialect,
    count: usize,
    start_index: usize,
) ![]const []const u8 {
    _ = dialect; // PostgreSQL 专用

    if (count == 0) {
        return &[_][]const u8{};
    }

    var placeholders = try allocator.alloc([]const u8, count);
    errdefer allocator.free(placeholders);

    // PostgreSQL: $1, $2, $3, ...
    for (0..count) |i| {
        placeholders[i] = try std.fmt.allocPrint(
            allocator,
            "${d}",
            .{start_index + i},
        );
    }

    return placeholders;
}

/// 释放 generatePlaceholders 生成的占位符数组
pub fn freePlaceholders(allocator: Allocator, placeholders: []const []const u8) void {
    for (placeholders) |ph| {
        allocator.free(ph);
    }
    allocator.free(placeholders);
}

// ============================================
// 4. IN 子句构建 (IN Clause Building)
// ============================================

/// 构建 IN 子句
///
/// 生成 PostgreSQL IN 子句,包含指定数量的位置占位符。
///
/// 参数:
/// - allocator: 内存分配器
/// - dialect: 数据库方言 (仅支持 PostgreSQL)
/// - count: IN 子句中的值数量
/// - start_index: 起始占位符索引 (默认为 1)
///
/// 返回: IN 子句字符串 (例如: "IN ($1, $2, $3)")
///
/// 示例:
/// ```zig
/// const in_clause = try buildInClause(allocator, .postgresql, 3, 1);
/// // 结果: "IN ($1, $2, $3)"
/// ```
pub fn buildInClause(
    allocator: Allocator,
    comptime dialect: Dialect,
    count: usize,
    start_index: usize,
) ![]const u8 {
    _ = dialect; // PostgreSQL 专用

    if (count == 0) {
        return allocator.dupe(u8, "IN ()");
    }

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.appendSlice("IN (");

    // PostgreSQL: IN ($1, $2, $3)
    for (0..count) |i| {
        if (i > 0) {
            try result.appendSlice(", ");
        }
        try std.fmt.format(result.writer(), "${d}", .{start_index + i});
    }

    try result.append(')');

    return result.toOwnedSlice();
}

// ============================================
// 测试 - 移到独立的测试文件
// ============================================
// 测试代码移至 tests/dialect_sql_test.zig
