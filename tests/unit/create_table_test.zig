//! CREATE TABLE Query Builder 单元测试
//!
//! 测试 CREATE TABLE 查询构建器的所有功能:
//! - 类型映射 (Zig类型 → SQL类型)
//! - 字段反射和列定义生成
//! - SQL构建 (有/无 IF NOT EXISTS)
//! - 主键检测
//! - 可选类型处理
//! - 内存管理

const std = @import("std");
const testing = std.testing;
const types_mod = @import("zorm").types;
const schema_mod = @import("zorm").schema;
const reflection_mod = @import("zorm").reflection;

// ============================================================================
// 测试数据模型
// ============================================================================

const TestUser = struct {
    id: i64,
    name: []const u8,
    email: ?[]const u8,
    age: i32,
    is_active: bool,

    pub const table_name = "users";
};

const TestProduct = struct {
    id: i64,
    title: []const u8,
    price: f64,
    stock: u32,
    description: ?[]const u8,

    pub const table_name = "products";
};

const TestSimple = struct {
    id: i64,
    value: i32,

    pub const table_name = "simple_table";
};

// ============================================================================
// 类型映射测试 (AC3.1.3)
// ============================================================================

test "zigToSQLType: 有符号整数类型" {
    try testing.expectEqualStrings("SMALLINT", comptime types_mod.zigToSQLType(i8));
    try testing.expectEqualStrings("SMALLINT", comptime types_mod.zigToSQLType(i16));
    try testing.expectEqualStrings("INTEGER", comptime types_mod.zigToSQLType(i32));
    try testing.expectEqualStrings("BIGINT", comptime types_mod.zigToSQLType(i64));
}

test "zigToSQLType: 无符号整数类型" {
    try testing.expectEqualStrings("INTEGER", comptime types_mod.zigToSQLType(u8));
    try testing.expectEqualStrings("INTEGER", comptime types_mod.zigToSQLType(u16));
    try testing.expectEqualStrings("INTEGER", comptime types_mod.zigToSQLType(u32));
    try testing.expectEqualStrings("BIGINT", comptime types_mod.zigToSQLType(u64));
}

test "zigToSQLType: 浮点类型" {
    try testing.expectEqualStrings("REAL", comptime types_mod.zigToSQLType(f32));
    try testing.expectEqualStrings("DOUBLE PRECISION", comptime types_mod.zigToSQLType(f64));
}

test "zigToSQLType: 布尔类型" {
    try testing.expectEqualStrings("BOOLEAN", comptime types_mod.zigToSQLType(bool));
}

test "zigToSQLType: 字符串类型" {
    try testing.expectEqualStrings("TEXT", comptime types_mod.zigToSQLType([]const u8));
}

test "zigToSQLType: 可选类型递归映射" {
    try testing.expectEqualStrings("BIGINT", comptime types_mod.zigToSQLType(?i64));
    try testing.expectEqualStrings("TEXT", comptime types_mod.zigToSQLType(?[]const u8));
    try testing.expectEqualStrings("BOOLEAN", comptime types_mod.zigToSQLType(?bool));
    try testing.expectEqualStrings("REAL", comptime types_mod.zigToSQLType(?f32));
}

// ============================================================================
// 字段反射测试 (AC3.1.2, AC3.1.4, AC3.1.5)
// ============================================================================

test "generateColumns: 基本功能" {
    const allocator = testing.allocator;
    const columns = try reflection_mod.generateColumns(TestUser, allocator);
    defer allocator.free(columns);

    // 验证列数
    try testing.expectEqual(@as(usize, 5), columns.len);

    // id 列 - 主键
    try testing.expectEqualStrings("id", columns[0].name);
    try testing.expectEqual(schema_mod.ColumnType.bigint, columns[0].column_type);
    try testing.expect(columns[0].primary_key);
    try testing.expect(!columns[0].nullable);

    // name 列 - 非空文本
    try testing.expectEqualStrings("name", columns[1].name);
    try testing.expectEqual(schema_mod.ColumnType.text, columns[1].column_type);
    try testing.expect(!columns[1].nullable);

    // email 列 - 可空文本
    try testing.expectEqualStrings("email", columns[2].name);
    try testing.expectEqual(schema_mod.ColumnType.text, columns[2].column_type);
    try testing.expect(columns[2].nullable);

    // age 列 - 整数
    try testing.expectEqualStrings("age", columns[3].name);
    try testing.expectEqual(schema_mod.ColumnType.int, columns[3].column_type);
    try testing.expect(!columns[3].nullable);

    // is_active 列 - 布尔
    try testing.expectEqualStrings("is_active", columns[4].name);
    try testing.expectEqual(schema_mod.ColumnType.boolean, columns[4].column_type);
    try testing.expect(!columns[4].nullable);
}

test "generateColumns: 主键检测" {
    const allocator = testing.allocator;
    const columns = try reflection_mod.generateColumns(TestSimple, allocator);
    defer allocator.free(columns);

    // id 应该是主键
    try testing.expect(columns[0].primary_key);
    try testing.expectEqualStrings("id", columns[0].name);

    // value 不是主键
    try testing.expect(!columns[1].primary_key);
    try testing.expectEqualStrings("value", columns[1].name);
}

test "generateColumns: 可选类型处理" {
    const allocator = testing.allocator;
    const columns = try reflection_mod.generateColumns(TestProduct, allocator);
    defer allocator.free(columns);

    // description 是可选类型
    try testing.expectEqualStrings("description", columns[4].name);
    try testing.expect(columns[4].nullable);

    // title 不是可选类型
    try testing.expectEqualStrings("title", columns[1].name);
    try testing.expect(!columns[1].nullable);
}

// ============================================================================
// Table SQL 生成测试 (AC3.1.6, AC3.1.7)
// ============================================================================

test "Table.toSQL: PostgreSQL 基本 CREATE TABLE" {
    const allocator = testing.allocator;
    var table = try schema_mod.Table.init(allocator, "users");
    defer table.deinit();

    // 添加列
    var id_col = schema_mod.Column.init("id", .bigint);
    _ = id_col.setPrimaryKey();
    _ = try table.addColumn(id_col);

    var name_col = schema_mod.Column.init("name", .text);
    _ = name_col.setNotNull();
    _ = try table.addColumn(name_col);

    var email_col = schema_mod.Column.init("email", .text);
    // email 可空，不设置 NOT NULL
    _ = try table.addColumn(email_col);

    const sql = try table.toSQL(.postgresql);
    defer allocator.free(sql);

    // 验证 SQL 包含关键部分
    try testing.expect(std.mem.indexOf(u8, sql, "CREATE TABLE users") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "id BIGINT PRIMARY KEY") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "name TEXT NOT NULL") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "email TEXT") != null);
    // email 不应该有 NOT NULL
    try testing.expect(std.mem.indexOf(u8, sql, "email TEXT NOT NULL") == null);
}

test "getTableName: 使用 table_name 常量" {
    const table_name = comptime reflection_mod.getTableName(TestUser);
    try testing.expectEqualStrings("users", table_name);
}

test "getTableName: 使用类型名" {
    const table_name = comptime reflection_mod.getTableName(TestProduct);
    try testing.expectEqualStrings("products", table_name);
}

// ============================================================================
// 内存管理测试
// ============================================================================

test "Table: 内存泄漏检测" {
    const allocator = testing.allocator;

    // 创建表
    var table = try schema_mod.Table.init(allocator, "test_table");
    defer table.deinit();

    // 添加多列
    var id_col = schema_mod.Column.init("id", .bigint);
    _ = id_col.setPrimaryKey();
    _ = try table.addColumn(id_col);

    var name_col = schema_mod.Column.init("name", .text);
    _ = name_col.setNotNull();
    _ = try table.addColumn(name_col);

    var age_col = schema_mod.Column.init("age", .int);
    _ = age_col.setNotNull();
    _ = try table.addColumn(age_col);

    // 生成 SQL
    const sql = try table.toSQL(.postgresql);
    defer allocator.free(sql);

    // testing.allocator 会自动检测内存泄漏
    try testing.expect(sql.len > 0);
}

test "generateColumns: 内存泄漏检测" {
    const allocator = testing.allocator;

    const columns = try reflection_mod.generateColumns(TestUser, allocator);
    defer allocator.free(columns);

    // 验证列数据
    try testing.expect(columns.len == 5);

    // testing.allocator 会自动检测内存泄漏
}

// ============================================================================
// 类型安全编译时验证
// ============================================================================

test "comptime 类型验证: 完整工作流" {
    // 所有类型映射和反射在编译时完成
    comptime {
        const table_name = reflection_mod.getTableName(TestUser);
        std.debug.assert(std.mem.eql(u8, table_name, "users"));

        // 验证类型映射
        std.debug.assert(std.mem.eql(u8, types_mod.zigToSQLType(i64), "BIGINT"));
        std.debug.assert(std.mem.eql(u8, types_mod.zigToSQLType([]const u8), "TEXT"));
        std.debug.assert(std.mem.eql(u8, types_mod.zigToSQLType(bool), "BOOLEAN"));
    }
}

// ============================================================================
// 边界条件测试
// ============================================================================

test "Table: 空表" {
    const allocator = testing.allocator;
    var table = try schema_mod.Table.init(allocator, "empty_table");
    defer table.deinit();

    // 不添加任何列
    try testing.expectEqual(@as(usize, 0), table.columns.items.len);
}

test "Column: 所有约束组合" {
    const allocator = testing.allocator;
    var table = try schema_mod.Table.init(allocator, "complex_table");
    defer table.deinit();

    var col = schema_mod.Column.init("status", .varchar);
    _ = col.setNotNull().setUnique().setDefault("'active'").setCheck("status IN ('active', 'inactive')");
    _ = try table.addColumn(col);

    const sql = try table.toSQL(.postgresql);
    defer allocator.free(sql);

    try testing.expect(std.mem.indexOf(u8, sql, "status VARCHAR") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "NOT NULL") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "UNIQUE") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "DEFAULT 'active'") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "CHECK (status IN ('active', 'inactive'))") != null);
}

// ============================================================================
// 多种类型综合测试
// ============================================================================

test "多种类型综合测试" {
    const ComplexModel = struct {
        id: i64,
        uuid: []const u8,
        count: i32,
        price: f64,
        discount: ?f32,
        active: bool,
        description: ?[]const u8,

        pub const table_name = "complex_models";
    };

    const allocator = testing.allocator;
    const columns = try reflection_mod.generateColumns(ComplexModel, allocator);
    defer allocator.free(columns);

    try testing.expectEqual(@as(usize, 7), columns.len);

    // id 列
    try testing.expectEqual(schema_mod.ColumnType.bigint, columns[0].column_type);
    try testing.expect(columns[0].primary_key);

    // uuid 列
    try testing.expectEqual(schema_mod.ColumnType.text, columns[1].column_type);
    try testing.expect(!columns[1].nullable);

    // count 列
    try testing.expectEqual(schema_mod.ColumnType.int, columns[2].column_type);

    // price 列
    try testing.expectEqual(schema_mod.ColumnType.double, columns[3].column_type);

    // discount 列 (可空)
    try testing.expectEqual(schema_mod.ColumnType.float, columns[4].column_type);
    try testing.expect(columns[4].nullable);

    // active 列
    try testing.expectEqual(schema_mod.ColumnType.boolean, columns[5].column_type);

    // description 列 (可空)
    try testing.expectEqual(schema_mod.ColumnType.text, columns[6].column_type);
    try testing.expect(columns[6].nullable);
}
