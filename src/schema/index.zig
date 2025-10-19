//! Index 管理 - 索引定义和 CREATE INDEX SQL 生成
//!
//! 提供声明式的索引定义 API 和跨数据库方言的 DDL 生成。
//!
//! # 核心功能
//! - 索引结构定义 (Index)
//! - 普通索引和唯一索引
//! - 多列索引
//! - CREATE INDEX SQL 生成
//! - 多数据库方言支持
//!
//! # 设计原则
//! - 使用 Builder 模式构建索引定义
//! - 编译时验证和优化
//! - 支持链式 API
//!
//! # 安全性说明
//! **SQL 注入防护责任**: 本模块不对索引名、表名、列名进行转义或引用。
//! 调用方必须确保所有标识符(name, table_name, columns)来自可信源,
//! 或已通过标识符验证(仅包含字母、数字、下划线)。
//! 对于用户输入,建议使用白名单验证或标识符引用机制。

const std = @import("std");
const Allocator = std.mem.Allocator;
const Dialect = @import("../dialect/dialect.zig").Dialect;
const Error = @import("../error.zig").Error;

/// 索引方法类型（主要针对 PostgreSQL）
pub const IndexMethod = enum {
    btree, // B-tree 索引（默认，所有数据库都支持）
    hash, // Hash 索引（PostgreSQL）
    gist, // GiST 索引（PostgreSQL）
    gin, // GIN 索引（PostgreSQL）
    brin, // BRIN 索引（PostgreSQL）

    /// 转换为 SQL 关键字
    pub fn toSQL(self: IndexMethod) []const u8 {
        return switch (self) {
            .btree => "BTREE",
            .hash => "HASH",
            .gist => "GIST",
            .gin => "GIN",
            .brin => "BRIN",
        };
    }
};

/// 索引定义
pub const Index = struct {
    name: []const u8, // 索引名称
    table_name: []const u8, // 表名
    columns: std.ArrayList([]const u8), // 列名列表
    unique: bool = false, // 是否唯一索引
    method: IndexMethod = .btree, // 索引方法（默认 B-tree）
    if_not_exists: bool = false, // IF NOT EXISTS（PostgreSQL/SQLite）
    allocator: Allocator,

    /// 创建索引定义
    pub fn init(allocator: Allocator, name: []const u8, table_name: []const u8) !Index {
        return .{
            .name = name,
            .table_name = table_name,
            .columns = .{},
            .allocator = allocator,
        };
    }

    /// 释放资源
    pub fn deinit(self: *Index) void {
        self.columns.deinit(self.allocator);
    }

    /// 添加列
    pub fn addColumn(self: *Index, column: []const u8) !*Index {
        try self.columns.append(self.allocator, column);
        return self;
    }

    /// 设置为唯一索引
    pub fn setUnique(self: *Index) *Index {
        self.unique = true;
        return self;
    }

    /// 设置索引方法
    pub fn setMethod(self: *Index, method: IndexMethod) *Index {
        self.method = method;
        return self;
    }

    /// 设置 IF NOT EXISTS
    pub fn setIfNotExists(self: *Index) *Index {
        self.if_not_exists = true;
        return self;
    }

    /// 生成 CREATE INDEX SQL
    /// 返回错误 error.NoColumnsSpecified 如果未指定任何列
    pub fn toSQL(self: *const Index, comptime dialect: Dialect) Error![]const u8 {
        // 验证:至少需要一个列
        if (self.columns.items.len == 0) {
            return Error.NoColumnsSpecified;
        }

        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(self.allocator);
        const writer = buf.writer(self.allocator);

        // CREATE [UNIQUE] INDEX
        try writer.writeAll("CREATE ");
        if (self.unique) {
            try writer.writeAll("UNIQUE ");
        }
        try writer.writeAll("INDEX ");

        // IF NOT EXISTS (PostgreSQL 和 SQLite 支持)
        if (self.if_not_exists) {
            switch (dialect) {
                .postgresql => {}, // MySQL 不支持 IF NOT EXISTS
            }
        }

        // 索引名称
        try writer.print("{s} ON {s}", .{ self.name, self.table_name });

        // USING method (仅 PostgreSQL 支持，且仅非默认 B-tree 时需要)
        if (dialect == .postgresql and self.method != .btree) {
            try writer.print(" USING {s}", .{self.method.toSQL()});
        }

        // 列名列表
        try writer.writeAll(" (");
        for (self.columns.items, 0..) |col, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll(col);
        }
        try writer.writeAll(")");

        return buf.toOwnedSlice(self.allocator);
    }
};

// =============================================================================
// 单元测试
// =============================================================================

const testing = std.testing;

test "Index: 基本创建" {
    var idx = try Index.init(testing.allocator, "idx_users_email", "users");
    defer idx.deinit();

    try testing.expectEqualStrings("idx_users_email", idx.name);
    try testing.expectEqualStrings("users", idx.table_name);
    try testing.expectEqual(@as(usize, 0), idx.columns.items.len);
    try testing.expect(!idx.unique);
    try testing.expectEqual(IndexMethod.btree, idx.method);
}

test "Index: 添加列" {
    var idx = try Index.init(testing.allocator, "idx_users_email", "users");
    defer idx.deinit();

    _ = try idx.addColumn("email");
    try testing.expectEqual(@as(usize, 1), idx.columns.items.len);
    try testing.expectEqualStrings("email", idx.columns.items[0]);
}

test "Index: 多列索引" {
    var idx = try Index.init(testing.allocator, "idx_users_name_email", "users");
    defer idx.deinit();

    _ = try idx.addColumn("name");
    _ = try idx.addColumn("email");

    try testing.expectEqual(@as(usize, 2), idx.columns.items.len);
    try testing.expectEqualStrings("name", idx.columns.items[0]);
    try testing.expectEqualStrings("email", idx.columns.items[1]);
}

test "Index: 链式 API" {
    var idx = try Index.init(testing.allocator, "idx_users_email", "users");
    defer idx.deinit();

    _ = try idx.addColumn("email");
    _ = idx.setUnique().setIfNotExists();

    try testing.expect(idx.unique);
    try testing.expect(idx.if_not_exists);
}

test "Index: 设置索引方法" {
    var idx = try Index.init(testing.allocator, "idx_users_email", "users");
    defer idx.deinit();

    _ = idx.setMethod(.hash);
    try testing.expectEqual(IndexMethod.hash, idx.method);
}

test "Index: PostgreSQL 普通索引 SQL" {
    var idx = try Index.init(testing.allocator, "idx_users_email", "users");
    defer idx.deinit();

    _ = try idx.addColumn("email");

    const sql = try idx.toSQL(.postgresql);
    defer testing.allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX idx_users_email ON users (email)", sql);
}

test "Index: PostgreSQL 唯一索引 SQL" {
    var idx = try Index.init(testing.allocator, "idx_users_email", "users");
    defer idx.deinit();

    _ = try idx.addColumn("email");
    _ = idx.setUnique();

    const sql = try idx.toSQL(.postgresql);
    defer testing.allocator.free(sql);

    try testing.expectEqualStrings("CREATE UNIQUE INDEX idx_users_email ON users (email)", sql);
}

test "Index: PostgreSQL 多列索引 SQL" {
    var idx = try Index.init(testing.allocator, "idx_users_name_email", "users");
    defer idx.deinit();

    _ = try idx.addColumn("name");
    _ = try idx.addColumn("email");

    const sql = try idx.toSQL(.postgresql);
    defer testing.allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX idx_users_name_email ON users (name, email)", sql);
}

test "Index: PostgreSQL IF NOT EXISTS" {
    var idx = try Index.init(testing.allocator, "idx_users_email", "users");
    defer idx.deinit();

    _ = try idx.addColumn("email");
    _ = idx.setIfNotExists();

    const sql = try idx.toSQL(.postgresql);
    defer testing.allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX IF NOT EXISTS idx_users_email ON users (email)", sql);
}

test "Index: PostgreSQL HASH 索引" {
    var idx = try Index.init(testing.allocator, "idx_users_email", "users");
    defer idx.deinit();

    _ = try idx.addColumn("email");
    _ = idx.setMethod(.hash);

    const sql = try idx.toSQL(.postgresql);
    defer testing.allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX idx_users_email ON users USING HASH (email)", sql);
}

test "Index: PostgreSQL GIN 索引" {
    var idx = try Index.init(testing.allocator, "idx_posts_tags", "posts");
    defer idx.deinit();

    _ = try idx.addColumn("tags");
    _ = idx.setMethod(.gin);

    const sql = try idx.toSQL(.postgresql);
    defer testing.allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX idx_posts_tags ON posts USING GIN (tags)", sql);
}

test "Index: 复杂场景 - PostgreSQL 唯一多列 GIN 索引" {
    var idx = try Index.init(testing.allocator, "idx_posts_tags_category", "posts");
    defer idx.deinit();

    _ = try idx.addColumn("tags");
    _ = try idx.addColumn("category");
    _ = idx.setUnique().setMethod(.gin).setIfNotExists();

    const sql = try idx.toSQL(.postgresql);
    defer testing.allocator.free(sql);

    try testing.expectEqualStrings("CREATE UNIQUE INDEX IF NOT EXISTS idx_posts_tags_category ON posts USING GIN (tags, category)", sql);
}

// ========== 边界和错误场景测试 ==========

test "Index: 错误 - 空列名列表" {
    var idx = try Index.init(testing.allocator, "idx_users_email", "users");
    defer idx.deinit();

    // 未添加任何列,应该返回 NoColumnsSpecified 错误
    try testing.expectError(Error.NoColumnsSpecified, idx.toSQL(.postgresql));
}

test "Index: 边界 - 大量列索引" {
    var idx = try Index.init(testing.allocator, "idx_users_all", "users");
    defer idx.deinit();

    // 添加 10 个列
    inline for (1..11) |i| {
        var buf: [16]u8 = undefined;
        const col = try std.fmt.bufPrint(&buf, "col{d}", .{i});
        _ = try idx.addColumn(col);
    }

    const sql = try idx.toSQL(.postgresql);
    defer testing.allocator.free(sql);

    // 验证包含所有列名
    try testing.expect(std.mem.indexOf(u8, sql, "col1") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "col10") != null);
}
