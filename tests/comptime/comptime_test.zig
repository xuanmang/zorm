//! ZORM Comptime Tests
//!
//! 验证类型系统的编译时行为和零运行时开销特性

const std = @import("std");
const zorm = @import("zorm");
const types = zorm.types;

test "comptime: type mapping executed at compile time" {
    comptime {
        const User = struct {
            id: i64,
            name: []const u8,
        };

        // 所有操作在编译时完成
        const table_name = types.getTableName(User);
        const fields = types.getFields(User);
        const id_type = types.zigToSQLType(i64);

        // 编译时断言
        if (!std.mem.eql(u8, table_name, "user")) {
            @compileError("Table name mismatch");
        }

        if (fields.len != 2) {
            @compileError("Field count mismatch");
        }

        if (!std.mem.eql(u8, id_type, "BIGINT")) {
            @compileError("SQL type mismatch");
        }
    }

    // 运行时无任何开销
}

test "comptime: custom table name resolution" {
    comptime {
        const User = struct {
            id: i64,
            pub const table_name = "app_users";
        };

        const name = types.getTableName(User);
        if (!std.mem.eql(u8, name, "app_users")) {
            @compileError("Custom table name not respected");
        }
    }
}

test "comptime: optional type handling" {
    comptime {
        const User = struct {
            id: i64,
            bio: ?[]const u8,
        };

        const fields = types.getFields(User);

        // 验证第二个字段是可选类型
        const bio_field = fields[1];
        const bio_type_info = @typeInfo(bio_field.type);

        if (bio_type_info != .optional) {
            @compileError("bio should be optional type");
        }

        // 验证 SQL 类型映射
        const bio_sql_type = types.zigToSQLType(bio_field.type);
        if (!std.mem.eql(u8, bio_sql_type, "TEXT")) {
            @compileError("Optional string should map to TEXT");
        }
    }
}

test "comptime: field names extraction" {
    comptime {
        const User = struct {
            id: i64,
            name: []const u8,
            email: []const u8,
        };

        const field_names = types.getFieldNames(User);

        if (field_names.len != 3) {
            @compileError("Should have 3 fields");
        }

        if (!std.mem.eql(u8, field_names[0], "id")) {
            @compileError("First field should be 'id'");
        }

        if (!std.mem.eql(u8, field_names[1], "name")) {
            @compileError("Second field should be 'name'");
        }
    }
}

test "comptime: type validation" {
    comptime {
        const ValidUser = struct {
            id: i64,
            name: []const u8,
            age: u32,
            balance: f64,
            active: bool,
        };

        // 验证通过
        types.validateType(ValidUser);
    }
}

test "comptime: all SQL type mappings" {
    comptime {
        // 整数类型
        const i8_sql = types.zigToSQLType(i8);
        const i16_sql = types.zigToSQLType(i16);
        const i32_sql = types.zigToSQLType(i32);
        const i64_sql = types.zigToSQLType(i64);

        if (!std.mem.eql(u8, i8_sql, "SMALLINT")) @compileError("i8 mapping failed");
        if (!std.mem.eql(u8, i16_sql, "SMALLINT")) @compileError("i16 mapping failed");
        if (!std.mem.eql(u8, i32_sql, "INTEGER")) @compileError("i32 mapping failed");
        if (!std.mem.eql(u8, i64_sql, "BIGINT")) @compileError("i64 mapping failed");

        // 无符号整数
        const u8_sql = types.zigToSQLType(u8);
        const u16_sql = types.zigToSQLType(u16);
        const u32_sql = types.zigToSQLType(u32);
        const u64_sql = types.zigToSQLType(u64);

        if (!std.mem.eql(u8, u8_sql, "INTEGER")) @compileError("u8 mapping failed");
        if (!std.mem.eql(u8, u16_sql, "INTEGER")) @compileError("u16 mapping failed");
        if (!std.mem.eql(u8, u32_sql, "INTEGER")) @compileError("u32 mapping failed");
        if (!std.mem.eql(u8, u64_sql, "BIGINT")) @compileError("u64 mapping failed");

        // 浮点类型
        const f32_sql = types.zigToSQLType(f32);
        const f64_sql = types.zigToSQLType(f64);

        if (!std.mem.eql(u8, f32_sql, "REAL")) @compileError("f32 mapping failed");
        if (!std.mem.eql(u8, f64_sql, "DOUBLE PRECISION")) @compileError("f64 mapping failed");

        // 布尔和字符串
        const bool_sql = types.zigToSQLType(bool);
        const str_sql = types.zigToSQLType([]const u8);

        if (!std.mem.eql(u8, bool_sql, "BOOLEAN")) @compileError("bool mapping failed");
        if (!std.mem.eql(u8, str_sql, "TEXT")) @compileError("string mapping failed");
    }
}

test "comptime: zero runtime overhead verification" {
    // 这个测试演示所有类型操作都在编译时完成
    comptime {
        const User = struct {
            id: i64,
            name: []const u8,
            age: ?u32,
        };

        // 以下所有操作都在编译时完成,生成常量
        const table_name = types.getTableName(User);
        const fields = types.getFields(User);
        const field_names = types.getFieldNames(User);
        const field_types = types.getFieldTypes(User);

        // 验证结果
        _ = table_name;
        _ = fields;
        _ = field_names;
        _ = field_types;

        // 编译器会优化掉所有这些操作,运行时无开销
    }

    // 运行时代码为空
    try std.testing.expect(true);
}
