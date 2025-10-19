//! Table 管理 - 表定义和 CREATE TABLE SQL 生成
//!
//! 提供声明式的表定义 API 和跨数据库方言的 DDL 生成。
//!
//! # 核心功能
//! - 表结构定义 (Table, Column)
//! - 约束定义 (主键、外键、唯一约束)
//! - CREATE TABLE SQL 生成
//! - 多数据库方言支持
//!
//! # 设计原则
//! - 使用 Builder 模式构建表定义
//! - 编译时验证和优化
//! - 支持链式 API

const std = @import("std");
const Allocator = std.mem.Allocator;
const Dialect = @import("../dialect/dialect.zig").Dialect;
pub const ColumnType = @import("schema.zig").ColumnType;

/// 列约束类型
pub const ConstraintType = enum {
    primary_key, // 主键
    foreign_key, // 外键
    unique, // 唯一约束
    not_null, // 非空约束
    default_value, // 默认值
    check, // 检查约束
};

/// 列定义
pub const Column = struct {
    name: []const u8,
    column_type: ColumnType,
    nullable: bool = true,
    primary_key: bool = false,
    auto_increment: bool = false,
    unique: bool = false,
    default_value: ?[]const u8 = null,
    check_expr: ?[]const u8 = null,

    /// 外键引用
    foreign_key: ?ForeignKeyRef = null,

    pub const ForeignKeyRef = struct {
        table: []const u8,
        column: []const u8,
        on_delete: OnAction = .no_action,
        on_update: OnAction = .no_action,

        pub const OnAction = enum {
            no_action,
            restrict,
            cascade,
            set_null,
            set_default,

            pub fn toSQL(self: OnAction) []const u8 {
                return switch (self) {
                    .no_action => "NO ACTION",
                    .restrict => "RESTRICT",
                    .cascade => "CASCADE",
                    .set_null => "SET NULL",
                    .set_default => "SET DEFAULT",
                };
            }
        };
    };

    /// 创建列定义
    pub fn init(name: []const u8, column_type: ColumnType) Column {
        return .{
            .name = name,
            .column_type = column_type,
        };
    }

    /// 设置为主键
    pub fn setPrimaryKey(self: *Column) *Column {
        self.primary_key = true;
        self.nullable = false;
        return self;
    }

    /// 设置为自增
    pub fn setAutoIncrement(self: *Column) *Column {
        self.auto_increment = true;
        return self;
    }

    /// 设置为唯一
    pub fn setUnique(self: *Column) *Column {
        self.unique = true;
        return self;
    }

    /// 设置为非空
    pub fn setNotNull(self: *Column) *Column {
        self.nullable = false;
        return self;
    }

    /// 设置默认值
    pub fn setDefault(self: *Column, value: []const u8) *Column {
        self.default_value = value;
        return self;
    }

    /// 设置检查约束
    pub fn setCheck(self: *Column, expr: []const u8) *Column {
        self.check_expr = expr;
        return self;
    }

    /// 设置外键引用
    pub fn setForeignKey(self: *Column, table: []const u8, column: []const u8) *Column {
        self.foreign_key = .{
            .table = table,
            .column = column,
        };
        return self;
    }
};

/// 表定义
pub const Table = struct {
    name: []const u8,
    columns: std.ArrayList(Column),
    allocator: Allocator,

    /// 创建表定义
    pub fn init(allocator: Allocator, name: []const u8) !Table {
        return .{
            .name = name,
            .columns = .{},
            .allocator = allocator,
        };
    }

    /// 释放资源
    pub fn deinit(self: *Table) void {
        self.columns.deinit(self.allocator);
    }

    /// 添加列
    pub fn addColumn(self: *Table, column: Column) !*Table {
        try self.columns.append(self.allocator, column);
        return self;
    }

    /// 生成 CREATE TABLE SQL
    pub fn toSQL(self: *const Table, comptime dialect: Dialect) ![]const u8 {
        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(self.allocator);
        const writer = buf.writer(self.allocator);

        // 先获取主键列数量，以决定如何处理主键
        const pk_columns = try self.getPrimaryKeyColumns();
        defer self.allocator.free(pk_columns);
        const has_composite_pk = pk_columns.len > 1;

        // CREATE TABLE table_name
        try writer.print("CREATE TABLE {s} (\n", .{self.name});

        // 列定义
        for (self.columns.items, 0..) |col, i| {
            if (i > 0) {
                try writer.writeAll(",\n");
            }
            try writer.writeAll("  ");
            // 传递是否为组合主键的信息
            try writeColumnDefinition(writer, &col, dialect, has_composite_pk);
        }

        // 主键约束 (如果有多列主键,需要单独声明)
        if (has_composite_pk) {
            try writer.writeAll(",\n  PRIMARY KEY (");
            for (pk_columns, 0..) |pk_col, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll(pk_col);
            }
            try writer.writeAll(")");
        }

        try writer.writeAll("\n)");

        return buf.toOwnedSlice(self.allocator);
    }

    /// 获取主键列名列表
    fn getPrimaryKeyColumns(self: *const Table) ![]const []const u8 {
        var pk_list: std.ArrayList([]const u8) = .{};
        errdefer pk_list.deinit(self.allocator);

        for (self.columns.items) |col| {
            if (col.primary_key) {
                try pk_list.append(self.allocator, col.name);
            }
        }

        return pk_list.toOwnedSlice(self.allocator);
    }
};

/// 写入列定义到 writer
fn writeColumnDefinition(writer: anytype, col: *const Column, comptime dialect: Dialect, has_composite_pk: bool) !void {
    // 列名
    try writer.print("{s} ", .{col.name});

    // 列类型（PostgreSQL 自增列使用 SERIAL/BIGSERIAL）
    if (col.auto_increment and dialect == .postgresql) {
        const serial_type = switch (col.column_type) {
            .bigint => "BIGSERIAL",
            .int => "SERIAL",
            .smallint => "SMALLSERIAL",
            else => col.column_type.sqlType(dialect),
        };
        try writer.writeAll(serial_type);
    } else {
        const sql_type = col.column_type.sqlType(dialect);
        try writer.writeAll(sql_type);
    }

    // 主键 (只有单列主键时才在列定义中声明)
    if (col.primary_key and !has_composite_pk) {
        try writer.writeAll(" PRIMARY KEY");
    }

    // 自增（PostgreSQL 的 SERIAL 已包含自增语义）
    if (col.auto_increment) {
        switch (dialect) {
            .postgresql => {}, // SQLite 的 INTEGER PRIMARY KEY 自动自增
        }
    }

    // NOT NULL
    if (!col.nullable and !col.primary_key) { // 主键隐含 NOT NULL
        try writer.writeAll(" NOT NULL");
    }

    // UNIQUE
    if (col.unique and !col.primary_key) { // 主键隐含 UNIQUE
        try writer.writeAll(" UNIQUE");
    }

    // DEFAULT
    if (col.default_value) |default| {
        try writer.print(" DEFAULT {s}", .{default});
    }

    // CHECK
    if (col.check_expr) |check| {
        try writer.print(" CHECK ({s})", .{check});
    }

    // FOREIGN KEY (内联定义)
    if (col.foreign_key) |fk| {
        try writer.print(" REFERENCES {s}({s})", .{ fk.table, fk.column });
        if (fk.on_delete != .no_action) {
            try writer.print(" ON DELETE {s}", .{fk.on_delete.toSQL()});
        }
        if (fk.on_update != .no_action) {
            try writer.print(" ON UPDATE {s}", .{fk.on_update.toSQL()});
        }
    }
}

// =============================================================================
// 单元测试
// =============================================================================

const testing = std.testing;

test "Column: 基本创建" {
    const col = Column.init("id", .bigint);
    try testing.expectEqualStrings("id", col.name);
    try testing.expectEqual(ColumnType.bigint, col.column_type);
    try testing.expect(col.nullable);
    try testing.expect(!col.primary_key);
}

test "Column: 链式 API" {
    var col = Column.init("id", .bigint);
    _ = col.setPrimaryKey().setAutoIncrement();

    try testing.expect(col.primary_key);
    try testing.expect(col.auto_increment);
    try testing.expect(!col.nullable); // setPrimaryKey 自动设置为非空
}

test "Column: 约束设置" {
    var col = Column.init("email", .varchar);
    _ = col.setUnique().setNotNull().setDefault("''");

    try testing.expect(col.unique);
    try testing.expect(!col.nullable);
    try testing.expectEqualStrings("''", col.default_value.?);
}

test "Column: 外键设置" {
    var col = Column.init("user_id", .bigint);
    _ = col.setForeignKey("users", "id");

    try testing.expect(col.foreign_key != null);
    try testing.expectEqualStrings("users", col.foreign_key.?.table);
    try testing.expectEqualStrings("id", col.foreign_key.?.column);
}

test "Table: 创建和释放" {
    var table = try Table.init(testing.allocator, "users");
    defer table.deinit();

    try testing.expectEqualStrings("users", table.name);
    try testing.expectEqual(@as(usize, 0), table.columns.items.len);
}

test "Table: 添加列" {
    var table = try Table.init(testing.allocator, "users");
    defer table.deinit();

    var id_col = Column.init("id", .bigint);
    _ = id_col.setPrimaryKey().setAutoIncrement();
    _ = try table.addColumn(id_col);

    var name_col = Column.init("name", .varchar);
    _ = name_col.setNotNull();
    _ = try table.addColumn(name_col);

    try testing.expectEqual(@as(usize, 2), table.columns.items.len);
    try testing.expectEqualStrings("id", table.columns.items[0].name);
    try testing.expectEqualStrings("name", table.columns.items[1].name);
}

test "Table: PostgreSQL CREATE TABLE SQL" {
    var table = try Table.init(testing.allocator, "users");
    defer table.deinit();

    var id_col = Column.init("id", .bigint);
    _ = id_col.setPrimaryKey().setAutoIncrement();
    _ = try table.addColumn(id_col);

    var name_col = Column.init("name", .varchar);
    _ = name_col.setNotNull();
    _ = try table.addColumn(name_col);

    var email_col = Column.init("email", .varchar);
    _ = email_col.setUnique();
    _ = try table.addColumn(email_col);

    const sql = try table.toSQL(.postgresql);
    defer testing.allocator.free(sql);

    // 验证 SQL 包含关键部分
    try testing.expect(std.mem.indexOf(u8, sql, "CREATE TABLE users") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "id BIGSERIAL PRIMARY KEY") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "name VARCHAR NOT NULL") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "email VARCHAR UNIQUE") != null);
}

test "Table: 外键约束" {
    var table = try Table.init(testing.allocator, "posts");
    defer table.deinit();

    var id_col = Column.init("id", .bigint);
    _ = id_col.setPrimaryKey();
    _ = try table.addColumn(id_col);

    var user_id_col = Column.init("user_id", .bigint);
    _ = user_id_col.setForeignKey("users", "id").setNotNull();
    _ = try table.addColumn(user_id_col);

    const sql = try table.toSQL(.postgresql);
    defer testing.allocator.free(sql);

    try testing.expect(std.mem.indexOf(u8, sql, "user_id BIGINT NOT NULL REFERENCES users(id)") != null);
}

test "Table: CHECK 约束" {
    var table = try Table.init(testing.allocator, "products");
    defer table.deinit();

    var id_col = Column.init("id", .bigint);
    _ = id_col.setPrimaryKey();
    _ = try table.addColumn(id_col);

    var price_col = Column.init("price", .decimal);
    _ = price_col.setCheck("price > 0").setNotNull();
    _ = try table.addColumn(price_col);

    const sql = try table.toSQL(.postgresql);
    defer testing.allocator.free(sql);

    try testing.expect(std.mem.indexOf(u8, sql, "price DECIMAL NOT NULL CHECK (price > 0)") != null);
}

test "Table: 复合主键" {
    var table = try Table.init(testing.allocator, "user_roles");
    defer table.deinit();

    var user_id_col = Column.init("user_id", .bigint);
    _ = user_id_col.setPrimaryKey();
    _ = try table.addColumn(user_id_col);

    var role_id_col = Column.init("role_id", .bigint);
    _ = role_id_col.setPrimaryKey();
    _ = try table.addColumn(role_id_col);

    const sql = try table.toSQL(.postgresql);
    defer testing.allocator.free(sql);

    // 复合主键应该单独声明
    try testing.expect(std.mem.indexOf(u8, sql, "PRIMARY KEY (user_id, role_id)") != null);
}
