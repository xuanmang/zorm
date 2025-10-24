//! Schema - 数据库模式管理
//!
//! 提供:
//! - 表结构定义和反射
//! - 模式迁移
//! - 类型映射

const std = @import("std");
const dialect_module = @import("../dialect/dialect.zig");

/// 列类型
/// 字段 Schema 配置
/// 用于在结构体中通过 comptime 定义字段的数据库属性
pub const FieldSchema = struct {
    /// 自定义列名（如果不指定，使用字段名）
    column_name: ?[]const u8 = null,
    /// 显式指定 SQL 类型（覆盖自动推断）
    sql_type: ?[]const u8 = null,
    /// 主键标记
    primary_key: bool = false,
    /// 自增标记（PostgreSQL 使用 SERIAL/BIGSERIAL）
    auto_increment: bool = false,
    /// 唯一约束
    unique: bool = false,
    /// 默认值表达式
    default: ?[]const u8 = null,
    /// CHECK 约束表达式
    check: ?[]const u8 = null,
    /// 显式 NOT NULL 控制（如果不指定，根据类型是否可选自动判断）
    not_null: ?bool = null,
};

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

    // 数组类型
    smallint_array,
    int_array,
    bigint_array,
    float_array,
    double_array,
    boolean_array,
    text_array,
    timestamp_array,
    uuid_array,
    jsonb_array,

    /// 获取 SQL 类型名称 (PostgreSQL)
    pub fn sqlType(self: ColumnType, comptime dialect: dialect_module.Dialect) []const u8 {
        _ = dialect; // PostgreSQL 专用
        return switch (self) {
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
            // 数组类型
            .smallint_array => "SMALLINT[]",
            .int_array => "INTEGER[]",
            .bigint_array => "BIGINT[]",
            .float_array => "REAL[]",
            .double_array => "DOUBLE PRECISION[]",
            .boolean_array => "BOOLEAN[]",
            .text_array => "TEXT[]",
            .timestamp_array => "TIMESTAMP[]",
            .uuid_array => "UUID[]",
            .jsonb_array => "JSONB[]",
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
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("getTableMeta requires a struct type, got " ++ @typeName(T));
    }

    // 获取表名 (优先使用 table_name 常量)
    const table_name = if (@hasDecl(T, "table_name"))
        @field(T, "table_name")
    else
        @typeName(T);

    // 提取字段信息
    const fields = type_info.@"struct".fields;
    comptime var columns: [fields.len]ColumnMeta = undefined;

    inline for (fields, 0..) |field, i| {
        columns[i] = .{
            .name = field.name,
            .type = inferColumnType(field.type),
            .nullable = isNullable(field.type),
            .primary_key = isPrimaryKey(field.name),
            .auto_increment = isAutoIncrement(field.name, field.type),
            .default_value = null,
        };
    }

    const final_columns = columns;
    return .{
        .name = table_name,
        .columns = &final_columns,
    };
}

/// 从 Zig 类型推断列类型 (编译时)
fn inferColumnType(comptime ZigType: type) ColumnType {
    // 处理可选类型 (?T)
    const actual_type = if (@typeInfo(ZigType) == .optional)
        @typeInfo(ZigType).optional.child
    else
        ZigType;

    const type_info = @typeInfo(actual_type);

    return switch (type_info) {
        .int => |int_info| {
            return switch (int_info.bits) {
                1...16 => .smallint,
                17...32 => .int,
                else => .bigint,
            };
        },
        .bool => .boolean,
        .float => |float_info| {
            return if (float_info.bits <= 32) .float else .double;
        },
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                return .text; // []const u8 或 []u8 映射为 TEXT
            }
            @compileError("Unsupported pointer type: " ++ @typeName(actual_type));
        },
        else => @compileError("Unsupported type for database column: " ++ @typeName(actual_type)),
    };
}

/// 检查类型是否可空 (编译时)
fn isNullable(comptime ZigType: type) bool {
    return @typeInfo(ZigType) == .optional;
}

/// 检查字段是否为主键 (基于约定: 名为 "id" 的字段)
fn isPrimaryKey(comptime field_name: []const u8) bool {
    return std.mem.eql(u8, field_name, "id");
}

/// 检查字段是否自增 (主键且为整数类型)
fn isAutoIncrement(comptime field_name: []const u8, comptime ZigType: type) bool {
    if (!isPrimaryKey(field_name)) {
        return false;
    }

    const actual_type = if (@typeInfo(ZigType) == .optional)
        @typeInfo(ZigType).optional.child
    else
        ZigType;

    return @typeInfo(actual_type) == .int;
}

/// 检查类型是否有 schema 配置
pub fn hasSchemaConfig(comptime T: type) bool {
    return @hasDecl(T, "schema");
}

/// 获取字段的 Schema 配置
/// 如果字段没有配置或结构体没有 schema 声明，返回默认的 FieldSchema
pub fn getFieldSchema(comptime T: type, comptime field_name: []const u8) FieldSchema {
    if (!@hasDecl(T, "schema")) {
        return .{};
    }

    const schema_config = @field(T, "schema");
    const schema_type = @TypeOf(schema_config);

    if (@hasField(schema_type, field_name)) {
        const field_config = @field(schema_config, field_name);
        // 将匿名结构体转换为 FieldSchema
        return .{
            .column_name = if (@hasField(@TypeOf(field_config), "column_name")) field_config.column_name else null,
            .sql_type = if (@hasField(@TypeOf(field_config), "sql_type")) field_config.sql_type else null,
            .primary_key = if (@hasField(@TypeOf(field_config), "primary_key")) field_config.primary_key else false,
            .auto_increment = if (@hasField(@TypeOf(field_config), "auto_increment")) field_config.auto_increment else false,
            .unique = if (@hasField(@TypeOf(field_config), "unique")) field_config.unique else false,
            .default = if (@hasField(@TypeOf(field_config), "default")) field_config.default else null,
            .check = if (@hasField(@TypeOf(field_config), "check")) field_config.check else null,
            .not_null = if (@hasField(@TypeOf(field_config), "not_null")) field_config.not_null else null,
        };
    }

    return .{};
}

/// 检测字段是否为 JSONB 类型
///
/// 通过检查 schema 配置中的 sql_type 是否为 "JSONB" 来判断
///
/// ## 参数
/// - `T`: 结构体类型
/// - `field_name`: 字段名称
///
/// ## 返回值
/// 如果字段配置为 JSONB 类型,返回 true,否则返回 false
///
/// ## 示例
/// ```zig
/// const Article = struct {
///     id: i64,
///     metadata: []const u8,
///     pub const schema = .{
///         .metadata = .{ .sql_type = "JSONB" },
///     };
/// };
/// const is_jsonb = isJSONBField(Article, "metadata"); // true
/// ```
pub fn isJSONBField(comptime T: type, comptime field_name: []const u8) bool {
    const schema_cfg = getFieldSchema(T, field_name);
    if (schema_cfg.sql_type) |sql_type| {
        return std.mem.eql(u8, sql_type, "JSONB");
    }
    return false;
}

/// 检测字段是否为 UUID 类型
///
/// 通过检查 Zig 类型是否为 [16]u8 来判断
///
/// ## 参数
/// - `T`: 结构体类型
/// - `field_name`: 字段名称
///
/// ## 返回值
/// 如果字段类型为 [16]u8,返回 true,否则返回 false
pub fn isUUIDField(comptime T: type, comptime field_name: []const u8) bool {
    const fields = @typeInfo(T).@"struct".fields;
    inline for (fields) |field| {
        if (std.mem.eql(u8, field.name, field_name)) {
            const field_type = field.type;
            const type_info = @typeInfo(field_type);
            if (type_info == .array) {
                const arr_info = type_info.array;
                return arr_info.len == 16 and arr_info.child == u8;
            }
            return false;
        }
    }
    return false;
}

/// 生成单个列的定义 SQL
/// 综合考虑字段类型和 Schema 配置
pub fn generateColumnDefinition(
    allocator: std.mem.Allocator,
    comptime field_name: []const u8,
    comptime field_type: type,
    comptime schema_cfg: FieldSchema,
) ![]const u8 {
    // 列名：优先使用配置的列名,否则使用字段名
    const col_name = schema_cfg.column_name orelse field_name;

    // 判断类型是否可选
    const is_optional = @typeInfo(field_type) == .optional;
    const base_type = if (is_optional) @typeInfo(field_type).optional.child else field_type;

    // SQL 类型：优先使用配置的类型,否则自动推断
    var sql_type: []const u8 = undefined;
    if (schema_cfg.sql_type) |explicit_type| {
        sql_type = explicit_type;
    } else if (schema_cfg.auto_increment) {
        // AUTO_INCREMENT: i64 -> BIGSERIAL, i32 -> SERIAL
        const type_info = @typeInfo(base_type);
        if (type_info == .int) {
            sql_type = if (type_info.int.bits == 64) "BIGSERIAL" else "SERIAL";
        } else {
            sql_type = columnTypeToSQL(inferColumnType(base_type));
        }
    } else {
        sql_type = columnTypeToSQL(inferColumnType(base_type));
    }

    // 构建约束列表 (Zig 0.15.2 新 ArrayList API)
    var constraints: std.ArrayList([]const u8) = .{};
    defer constraints.deinit(allocator);

    // 跟踪需要释放的动态分配字符串
    var allocated_constraints: std.ArrayList([]const u8) = .{};
    defer {
        for (allocated_constraints.items) |item| {
            allocator.free(item);
        }
        allocated_constraints.deinit(allocator);
    }

    // PRIMARY KEY
    if (schema_cfg.primary_key) {
        try constraints.append(allocator, "PRIMARY KEY");
    }

    // UNIQUE
    if (schema_cfg.unique) {
        try constraints.append(allocator, "UNIQUE");
    }

    // NOT NULL (SERIAL/BIGSERIAL 自动 NOT NULL,不需要额外添加)
    const not_null = schema_cfg.not_null orelse !is_optional;
    if (not_null and !schema_cfg.auto_increment) {
        try constraints.append(allocator, "NOT NULL");
    }

    // DEFAULT
    if (schema_cfg.default) |default_val| {
        const default_clause = try std.fmt.allocPrint(allocator, "DEFAULT {s}", .{default_val});
        try allocated_constraints.append(allocator, default_clause);
        try constraints.append(allocator, default_clause);
    }

    // CHECK
    if (schema_cfg.check) |check_expr| {
        const check_clause = try std.fmt.allocPrint(allocator, "CHECK ({s})", .{check_expr});
        try allocated_constraints.append(allocator, check_clause);
        try constraints.append(allocator, check_clause);
    }

    // 组装完整的列定义
    if (constraints.items.len > 0) {
        const constraints_str = try std.mem.join(allocator, " ", constraints.items);
        defer allocator.free(constraints_str);
        return try std.fmt.allocPrint(allocator, "{s} {s} {s}", .{ col_name, sql_type, constraints_str });
    } else {
        return try std.fmt.allocPrint(allocator, "{s} {s}", .{ col_name, sql_type });
    }
}

/// 将 ColumnType 转换为 SQL 类型字符串 (PostgreSQL)
fn columnTypeToSQL(col_type: ColumnType) []const u8 {
    return col_type.sqlType(.postgresql);
}

/// 生成所有列的定义
pub fn generateColumnDefinitions(
    allocator: std.mem.Allocator,
    comptime T: type,
) ![]const u8 {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("generateColumnDefinitions requires a struct type, got " ++ @typeName(T));
    }

    const fields = type_info.@"struct".fields;
    var column_defs: std.ArrayList([]const u8) = .{};
    defer {
        // 释放所有列定义字符串
        for (column_defs.items) |item| {
            allocator.free(item);
        }
        column_defs.deinit(allocator);
    }

    inline for (fields) |field| {
        const schema_cfg = comptime getFieldSchema(T, field.name);
        const col_def = try generateColumnDefinition(allocator, field.name, field.type, schema_cfg);
        try column_defs.append(allocator, col_def);
    }

    return try std.mem.join(allocator, ",\n    ", column_defs.items);
}

// =============================================================================
// 单元测试
// =============================================================================

const testing = std.testing;

// 测试用模型定义
const TestUser = struct {
    id: i64,
    name: []const u8,
    email: ?[]const u8,
    age: i32,
    active: bool,

    pub const table_name = "users";
};

const TestProduct = struct {
    id: i64,
    title: []const u8,
    price: f64,
    stock: i32,
    // 没有 table_name,使用类型名
};

const TestSimple = struct {
    id: i64,
    value: i32,

    pub const table_name = "simple_table";
};

test "getTableMeta: 基本功能" {
    const meta = comptime getTableMeta(TestUser);

    // 验证表名
    try testing.expectEqualStrings("users", meta.name);

    // 验证列数
    try testing.expectEqual(5, meta.columns.len);

    // 验证 id 列
    try testing.expectEqualStrings("id", meta.columns[0].name);
    try testing.expectEqual(ColumnType.bigint, meta.columns[0].type);
    try testing.expectEqual(false, meta.columns[0].nullable);
    try testing.expectEqual(true, meta.columns[0].primary_key);
    try testing.expectEqual(true, meta.columns[0].auto_increment);

    // 验证 name 列
    try testing.expectEqualStrings("name", meta.columns[1].name);
    try testing.expectEqual(ColumnType.text, meta.columns[1].type);
    try testing.expectEqual(false, meta.columns[1].nullable);
    try testing.expectEqual(false, meta.columns[1].primary_key);

    // 验证 email 列 (可空)
    try testing.expectEqualStrings("email", meta.columns[2].name);
    try testing.expectEqual(ColumnType.text, meta.columns[2].type);
    try testing.expectEqual(true, meta.columns[2].nullable);
    try testing.expectEqual(false, meta.columns[2].primary_key);

    // 验证 age 列
    try testing.expectEqualStrings("age", meta.columns[3].name);
    try testing.expectEqual(ColumnType.int, meta.columns[3].type);
    try testing.expectEqual(false, meta.columns[3].nullable);

    // 验证 active 列
    try testing.expectEqualStrings("active", meta.columns[4].name);
    try testing.expectEqual(ColumnType.boolean, meta.columns[4].type);
    try testing.expectEqual(false, meta.columns[4].nullable);
}

test "getTableMeta: 使用类型名作为表名" {
    const meta = comptime getTableMeta(TestProduct);

    // 类型名包含完整路径,只检查是否包含 "TestProduct"
    try testing.expect(std.mem.indexOf(u8, meta.name, "TestProduct") != null);

    // 验证列数
    try testing.expectEqual(4, meta.columns.len);
}

test "getTableMeta: 简单结构" {
    const meta = comptime getTableMeta(TestSimple);

    try testing.expectEqualStrings("simple_table", meta.name);
    try testing.expectEqual(2, meta.columns.len);

    // id 应该是主键且自增
    try testing.expectEqual(true, meta.columns[0].primary_key);
    try testing.expectEqual(true, meta.columns[0].auto_increment);

    // value 不是主键
    try testing.expectEqual(false, meta.columns[1].primary_key);
    try testing.expectEqual(false, meta.columns[1].auto_increment);
}

test "inferColumnType: 整数类型" {
    try testing.expectEqual(ColumnType.smallint, comptime inferColumnType(i8));
    try testing.expectEqual(ColumnType.smallint, comptime inferColumnType(i16));
    try testing.expectEqual(ColumnType.int, comptime inferColumnType(i32));
    try testing.expectEqual(ColumnType.bigint, comptime inferColumnType(i64));

    try testing.expectEqual(ColumnType.smallint, comptime inferColumnType(u8));
    try testing.expectEqual(ColumnType.smallint, comptime inferColumnType(u16));
    try testing.expectEqual(ColumnType.int, comptime inferColumnType(u32));
    try testing.expectEqual(ColumnType.bigint, comptime inferColumnType(u64));
}

test "inferColumnType: 浮点类型" {
    try testing.expectEqual(ColumnType.float, comptime inferColumnType(f32));
    try testing.expectEqual(ColumnType.double, comptime inferColumnType(f64));
}

test "inferColumnType: 布尔类型" {
    try testing.expectEqual(ColumnType.boolean, comptime inferColumnType(bool));
}

test "inferColumnType: 字符串类型" {
    try testing.expectEqual(ColumnType.text, comptime inferColumnType([]const u8));
    try testing.expectEqual(ColumnType.text, comptime inferColumnType([]u8));
}

test "inferColumnType: 可选类型" {
    try testing.expectEqual(ColumnType.bigint, comptime inferColumnType(?i64));
    try testing.expectEqual(ColumnType.text, comptime inferColumnType(?[]const u8));
    try testing.expectEqual(ColumnType.boolean, comptime inferColumnType(?bool));
    try testing.expectEqual(ColumnType.float, comptime inferColumnType(?f32));
}

test "isNullable: 正确识别可选类型" {
    try testing.expectEqual(false, comptime isNullable(i64));
    try testing.expectEqual(true, comptime isNullable(?i64));
    try testing.expectEqual(false, comptime isNullable([]const u8));
    try testing.expectEqual(true, comptime isNullable(?[]const u8));
    try testing.expectEqual(false, comptime isNullable(bool));
    try testing.expectEqual(true, comptime isNullable(?bool));
}

test "isPrimaryKey: 基于字段名识别" {
    try testing.expectEqual(true, comptime isPrimaryKey("id"));
    try testing.expectEqual(false, comptime isPrimaryKey("user_id"));
    try testing.expectEqual(false, comptime isPrimaryKey("name"));
    try testing.expectEqual(false, comptime isPrimaryKey("ID")); // 大小写敏感
}

test "isAutoIncrement: 主键且为整数" {
    try testing.expectEqual(true, comptime isAutoIncrement("id", i64));
    try testing.expectEqual(true, comptime isAutoIncrement("id", i32));
    try testing.expectEqual(false, comptime isAutoIncrement("id", []const u8)); // 主键但非整数
    try testing.expectEqual(false, comptime isAutoIncrement("name", i64)); // 整数但非主键
    try testing.expectEqual(true, comptime isAutoIncrement("id", ?i64)); // 可选整数主键
}

test "ColumnType.sqlType: PostgreSQL" {
    try testing.expectEqualStrings("INTEGER", ColumnType.int.sqlType(.postgresql));
    try testing.expectEqualStrings("BIGINT", ColumnType.bigint.sqlType(.postgresql));
    try testing.expectEqualStrings("BOOLEAN", ColumnType.boolean.sqlType(.postgresql));
    try testing.expectEqualStrings("TEXT", ColumnType.text.sqlType(.postgresql));
    try testing.expectEqualStrings("JSONB", ColumnType.jsonb.sqlType(.postgresql));
}

test "完整流程: 从类型到 SQL DDL" {
    const meta = comptime getTableMeta(TestUser);

    // 验证可以使用元数据生成 SQL 类型
    try testing.expectEqualStrings("BIGINT", meta.columns[0].type.sqlType(.postgresql));
    try testing.expectEqualStrings("TEXT", meta.columns[1].type.sqlType(.postgresql));
    try testing.expectEqualStrings("BOOLEAN", meta.columns[4].type.sqlType(.postgresql));
}

test "编译时元数据: 零运行时开销" {
    // 验证所有操作都可以在编译时完成
    comptime {
        const meta = getTableMeta(TestUser);
        std.debug.assert(std.mem.eql(u8, meta.name, "users"));
        std.debug.assert(meta.columns.len == 5);
        std.debug.assert(meta.columns[0].primary_key);
        std.debug.assert(meta.columns[2].nullable);
    }
}

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

    const meta = comptime getTableMeta(ComplexModel);

    try testing.expectEqualStrings("complex_models", meta.name);
    try testing.expectEqual(7, meta.columns.len);

    // id 列
    try testing.expectEqual(ColumnType.bigint, meta.columns[0].type);
    try testing.expectEqual(true, meta.columns[0].primary_key);
    try testing.expectEqual(true, meta.columns[0].auto_increment);

    // uuid 列
    try testing.expectEqual(ColumnType.text, meta.columns[1].type);
    try testing.expectEqual(false, meta.columns[1].nullable);

    // count 列
    try testing.expectEqual(ColumnType.int, meta.columns[2].type);

    // price 列
    try testing.expectEqual(ColumnType.double, meta.columns[3].type);

    // discount 列 (可空)
    try testing.expectEqual(ColumnType.float, meta.columns[4].type);
    try testing.expectEqual(true, meta.columns[4].nullable);

    // active 列
    try testing.expectEqual(ColumnType.boolean, meta.columns[5].type);

    // description 列 (可空)
    try testing.expectEqual(ColumnType.text, meta.columns[6].type);
    try testing.expectEqual(true, meta.columns[6].nullable);
}

// =============================================================================
// FieldSchema 和配置功能测试
// =============================================================================

test "hasSchemaConfig: 检测 schema 配置存在性" {
    const WithSchema = struct {
        id: i64,
        name: []const u8,

        pub const schema = .{
            .id = .{ .primary_key = true },
        };
    };

    const WithoutSchema = struct {
        id: i64,
        name: []const u8,
    };

    try testing.expectEqual(true, comptime hasSchemaConfig(WithSchema));
    try testing.expectEqual(false, comptime hasSchemaConfig(WithoutSchema));
}

test "getFieldSchema: 读取字段配置" {
    const User = struct {
        id: i64,
        username: []const u8,
        email: []const u8,
        age: i32,

        pub const schema = .{
            .id = .{ .primary_key = true, .auto_increment = true },
            .username = .{ .unique = true, .sql_type = "VARCHAR(50)" },
            .email = .{ .unique = true },
        };
    };

    // 测试有配置的字段
    const id_schema = comptime getFieldSchema(User, "id");
    try testing.expectEqual(true, id_schema.primary_key);
    try testing.expectEqual(true, id_schema.auto_increment);

    const username_schema = comptime getFieldSchema(User, "username");
    try testing.expectEqual(true, username_schema.unique);
    try testing.expectEqualStrings("VARCHAR(50)", username_schema.sql_type.?);

    // 测试没有配置的字段（应返回默认值）
    const age_schema = comptime getFieldSchema(User, "age");
    try testing.expectEqual(false, age_schema.primary_key);
    try testing.expectEqual(false, age_schema.unique);
    try testing.expectEqual(null, age_schema.sql_type);
}

test "generateColumnDefinition: 自定义列名" {
    const allocator = testing.allocator;

    const col_def = try generateColumnDefinition(
        allocator,
        "user_name",
        []const u8,
        .{ .column_name = "username" },
    );
    defer allocator.free(col_def);

    try testing.expect(std.mem.startsWith(u8, col_def, "username TEXT"));
}

test "generateColumnDefinition: 显式 SQL 类型" {
    const allocator = testing.allocator;

    const col_def = try generateColumnDefinition(
        allocator,
        "username",
        []const u8,
        .{ .sql_type = "VARCHAR(50)" },
    );
    defer allocator.free(col_def);

    try testing.expect(std.mem.startsWith(u8, col_def, "username VARCHAR(50)"));
}

test "generateColumnDefinition: UNIQUE 约束" {
    const allocator = testing.allocator;

    const col_def = try generateColumnDefinition(
        allocator,
        "email",
        []const u8,
        .{ .unique = true },
    );
    defer allocator.free(col_def);

    try testing.expect(std.mem.indexOf(u8, col_def, "UNIQUE") != null);
    try testing.expect(std.mem.indexOf(u8, col_def, "NOT NULL") != null);
}

test "generateColumnDefinition: DEFAULT 值" {
    const allocator = testing.allocator;

    const col_def = try generateColumnDefinition(
        allocator,
        "status",
        []const u8,
        .{ .default = "'active'" },
    );
    defer allocator.free(col_def);

    try testing.expect(std.mem.indexOf(u8, col_def, "DEFAULT 'active'") != null);
}

test "generateColumnDefinition: CHECK 约束" {
    const allocator = testing.allocator;

    const col_def = try generateColumnDefinition(
        allocator,
        "age",
        i32,
        .{ .check = "age >= 0 AND age <= 150" },
    );
    defer allocator.free(col_def);

    try testing.expect(std.mem.indexOf(u8, col_def, "CHECK (age >= 0 AND age <= 150)") != null);
}

test "generateColumnDefinition: AUTO_INCREMENT (SERIAL)" {
    const allocator = testing.allocator;

    const col_def = try generateColumnDefinition(
        allocator,
        "id",
        i32,
        .{ .primary_key = true, .auto_increment = true },
    );
    defer allocator.free(col_def);

    try testing.expect(std.mem.indexOf(u8, col_def, "SERIAL") != null);
    try testing.expect(std.mem.indexOf(u8, col_def, "PRIMARY KEY") != null);
}

test "generateColumnDefinition: AUTO_INCREMENT (BIGSERIAL)" {
    const allocator = testing.allocator;

    const col_def = try generateColumnDefinition(
        allocator,
        "id",
        i64,
        .{ .primary_key = true, .auto_increment = true },
    );
    defer allocator.free(col_def);

    try testing.expect(std.mem.indexOf(u8, col_def, "BIGSERIAL") != null);
    try testing.expect(std.mem.indexOf(u8, col_def, "PRIMARY KEY") != null);
}

test "generateColumnDefinition: 可选类型自动 NULL" {
    const allocator = testing.allocator;

    const col_def = try generateColumnDefinition(
        allocator,
        "description",
        ?[]const u8,
        .{},
    );
    defer allocator.free(col_def);

    // 可选类型不应该有 NOT NULL
    try testing.expect(std.mem.indexOf(u8, col_def, "NOT NULL") == null);
}

test "generateColumnDefinition: 非可选类型自动 NOT NULL" {
    const allocator = testing.allocator;

    const col_def = try generateColumnDefinition(
        allocator,
        "name",
        []const u8,
        .{},
    );
    defer allocator.free(col_def);

    try testing.expect(std.mem.indexOf(u8, col_def, "NOT NULL") != null);
}

test "generateColumnDefinition: 综合约束" {
    const allocator = testing.allocator;

    const col_def = try generateColumnDefinition(
        allocator,
        "username",
        []const u8,
        .{
            .column_name = "user_name",
            .sql_type = "VARCHAR(50)",
            .unique = true,
            .check = "LENGTH(user_name) >= 3",
        },
    );
    defer allocator.free(col_def);

    try testing.expect(std.mem.startsWith(u8, col_def, "user_name VARCHAR(50)"));
    try testing.expect(std.mem.indexOf(u8, col_def, "UNIQUE") != null);
    try testing.expect(std.mem.indexOf(u8, col_def, "NOT NULL") != null);
    try testing.expect(std.mem.indexOf(u8, col_def, "CHECK (LENGTH(user_name) >= 3)") != null);
}

test "generateColumnDefinitions: 完整示例" {
    const allocator = testing.allocator;

    const User = struct {
        id: i64,
        username: []const u8,
        email: []const u8,
        age: i32,
        status: []const u8,
        created_at: i64,

        pub const table_name = "users";

        pub const schema = .{
            .id = .{ .primary_key = true, .auto_increment = true },
            .username = .{ .unique = true, .sql_type = "VARCHAR(50)" },
            .email = .{ .unique = true },
            .age = .{ .check = "age >= 0 AND age <= 150" },
            .status = .{ .default = "'active'" },
            .created_at = .{ .default = "CURRENT_TIMESTAMP" },
        };
    };

    const columns_sql = try generateColumnDefinitions(allocator, User);
    defer allocator.free(columns_sql);

    // 验证包含所有列
    try testing.expect(std.mem.indexOf(u8, columns_sql, "id BIGSERIAL PRIMARY KEY") != null);
    try testing.expect(std.mem.indexOf(u8, columns_sql, "username VARCHAR(50) UNIQUE NOT NULL") != null);
    try testing.expect(std.mem.indexOf(u8, columns_sql, "email TEXT UNIQUE NOT NULL") != null);
    try testing.expect(std.mem.indexOf(u8, columns_sql, "age INTEGER NOT NULL CHECK (age >= 0 AND age <= 150)") != null);
    try testing.expect(std.mem.indexOf(u8, columns_sql, "status TEXT NOT NULL DEFAULT 'active'") != null);
    try testing.expect(std.mem.indexOf(u8, columns_sql, "created_at BIGINT NOT NULL DEFAULT CURRENT_TIMESTAMP") != null);
}

/// DropIndexQuery - DROP INDEX 查询构建器
///
/// 提供类型安全的 DROP INDEX DDL 语句构建功能。
///
/// ## 功能特性
/// - 支持 IF EXISTS 子句（幂等性删除）
/// - 支持 CASCADE 选项（级联删除依赖对象）
/// - 链式 API 调用
/// - 编译时类型安全
///
/// ## 使用示例
/// ```zig
/// var drop_idx = try db.newDropIndex(User);
/// defer drop_idx.deinit();
///
/// try drop_idx
///     .index("idx_users_email")
///     .ifExists()
///     .exec();
/// ```
///
/// 生成的 SQL: `DROP INDEX IF EXISTS idx_users_email`
pub fn DropIndexQuery(comptime T: type, comptime dialect: dialect_module.Dialect) type {
    _ = T; // 类型参数用于与其他 Query 保持一致,实际 DROP INDEX 不需要表名
    const db_mod = @import("../core/db.zig");
    const DBType = db_mod.DB(dialect);

    return struct {
        const Self = @This();
        const Allocator = std.mem.Allocator;

        allocator: Allocator,
        db: *DBType,
        index_name: ?[]const u8,
        if_exists_flag: bool,
        cascade_flag: bool,
        restrict_flag: bool,

        /// 初始化 DropIndexQuery
        pub fn init(allocator: Allocator, db: *DBType) !*Self {
            const query = try allocator.create(Self);
            query.* = .{
                .allocator = allocator,
                .db = db,
                .index_name = null,
                .if_exists_flag = false,
                .cascade_flag = false,
                .restrict_flag = false,
            };
            return query;
        }

        /// 指定要删除的索引名称
        ///
        /// ## 参数
        /// - `name`: 索引名称
        ///
        /// ## 返回值
        /// 返回 self 指针支持链式调用
        pub fn index(self: *Self, name: []const u8) *Self {
            self.index_name = name;
            return self;
        }

        /// 添加 IF EXISTS 子句
        ///
        /// 如果索引不存在,不会抛出错误,静默成功。
        /// 适用于幂等性脚本(可重复执行)。
        ///
        /// ## 返回值
        /// 返回 self 指针支持链式调用
        pub fn ifExists(self: *Self) *Self {
            self.if_exists_flag = true;
            return self;
        }

        /// 添加 CASCADE 选项
        ///
        /// 级联删除依赖于该索引的对象。
        /// 注意:PostgreSQL 中很少有对象依赖索引,此选项较少使用。
        /// CASCADE 和 RESTRICT 互斥,后调用的会覆盖前面的。
        ///
        /// ## 返回值
        /// 返回 self 指针支持链式调用
        pub fn cascade(self: *Self) *Self {
            self.cascade_flag = true;
            self.restrict_flag = false;
            return self;
        }

        /// 添加 RESTRICT 选项
        ///
        /// 如果有对象依赖于该索引,则拒绝删除。
        /// 这是默认行为,显式指定可以提高代码可读性。
        /// CASCADE 和 RESTRICT 互斥,后调用的会覆盖前面的。
        ///
        /// ## 返回值
        /// 返回 self 指针支持链式调用
        pub fn restrict(self: *Self) *Self {
            self.restrict_flag = true;
            self.cascade_flag = false;
            return self;
        }

        /// 构建 DROP INDEX SQL 语句
        ///
        /// ## 返回值
        /// 返回分配的 SQL 字符串,调用者负责使用 allocator.free() 释放
        ///
        /// ## 错误
        /// - `error.IndexNameRequired`: index_name 未设置
        /// - `error.OutOfMemory`: 内存分配失败
        pub fn build(self: *Self) ![]const u8 {
            if (self.index_name == null) {
                return error.IndexNameRequired;
            }

            var sql_buf: std.ArrayList(u8) = .{};
            errdefer sql_buf.deinit(self.allocator);

            try sql_buf.appendSlice(self.allocator, "DROP INDEX ");

            if (self.if_exists_flag) {
                try sql_buf.appendSlice(self.allocator, "IF EXISTS ");
            }

            try sql_buf.appendSlice(self.allocator, self.index_name.?);

            if (self.cascade_flag) {
                try sql_buf.appendSlice(self.allocator, " CASCADE");
            } else if (self.restrict_flag) {
                try sql_buf.appendSlice(self.allocator, " RESTRICT");
            }

            defer sql_buf.deinit(self.allocator);
            return self.allocator.dupe(u8, sql_buf.items);
        }

        /// 执行 DROP INDEX DDL 语句
        ///
        /// ## 错误
        /// - `error.IndexNameRequired`: index_name 未设置
        /// - `error.OutOfMemory`: 内存分配失败
        /// - 数据库连接相关错误
        pub fn exec(self: *Self) !void {
            if (self.index_name == null) {
                return error.IndexNameRequired;
            }

            const sql = try self.build();
            defer self.allocator.free(sql);

            // TODO: 执行 DDL - 等待真实数据库连接集成
            // 示例: try self.db.conn.execute(sql);
            // 当前只是占位符实现,避免编译器警告
            if (sql.len == 0) return error.EmptySQL;
        }

        /// 释放资源
        pub fn deinit(self: *Self) void {
            // 释放 Query 结构体本身
            self.allocator.destroy(self);
        }
    };
}
