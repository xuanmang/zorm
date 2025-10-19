//! ZORM Type System Unit Tests
//!
//! 测试类型系统的所有公共 API,包括类型映射、字段反射和辅助函数。

const std = @import("std");
const zorm = @import("zorm");
const types = zorm.types;

// ============ getFields() 测试 ============

test "getFields: extract struct fields" {
    const User = struct {
        id: i64,
        name: []const u8,
        age: u32,
    };

    const fields = comptime types.getFields(User);

    try std.testing.expectEqual(@as(usize, 3), fields.len);
    try std.testing.expectEqualStrings("id", fields[0].name);
    try std.testing.expectEqualStrings("name", fields[1].name);
    try std.testing.expectEqualStrings("age", fields[2].name);

    // 验证字段类型
    try std.testing.expect(fields[0].type == i64);
    try std.testing.expect(fields[1].type == []const u8);
    try std.testing.expect(fields[2].type == u32);
}

test "getFields: empty struct" {
    const Empty = struct {};

    const fields = comptime types.getFields(Empty);

    try std.testing.expectEqual(@as(usize, 0), fields.len);
}

// ============ getTableName() 测试 ============

test "getTableName: custom table name" {
    const User = struct {
        id: i64,
        pub const table_name = "app_users";
    };

    const name = comptime types.getTableName(User);
    try std.testing.expectEqualStrings("app_users", name);
}

test "getTableName: default table name from simple type" {
    const User = struct {
        id: i64,
    };

    const name = comptime types.getTableName(User);
    try std.testing.expectEqualStrings("user", name);
}

test "getTableName: default table name from PascalCase" {
    const UserProfile = struct {
        id: i64,
    };

    const name = comptime types.getTableName(UserProfile);
    try std.testing.expectEqualStrings("user_profile", name);
}

test "getTableName: qualified type name" {
    // 模拟完全限定名
    const MyModule = struct {
        pub const User = struct {
            id: i64,
        };
    };

    const name = comptime types.getTableName(MyModule.User);
    // 类型名会是 "types_test.test.getTableName: qualified type name.MyModule.User"
    // 提取最后部分应该是 "User" -> "user"
    try std.testing.expectEqualStrings("user", name);
}

// ============ zigToSQLType() 测试 ============

test "zigToSQLType: signed integer types" {
    comptime {
        try std.testing.expectEqualStrings("SMALLINT", types.zigToSQLType(i8));
        try std.testing.expectEqualStrings("SMALLINT", types.zigToSQLType(i16));
        try std.testing.expectEqualStrings("INTEGER", types.zigToSQLType(i32));
        try std.testing.expectEqualStrings("BIGINT", types.zigToSQLType(i64));
    }
}

test "zigToSQLType: unsigned integer types" {
    comptime {
        try std.testing.expectEqualStrings("INTEGER", types.zigToSQLType(u8));
        try std.testing.expectEqualStrings("INTEGER", types.zigToSQLType(u16));
        try std.testing.expectEqualStrings("INTEGER", types.zigToSQLType(u32));
        try std.testing.expectEqualStrings("BIGINT", types.zigToSQLType(u64));
    }
}

test "zigToSQLType: float types" {
    comptime {
        try std.testing.expectEqualStrings("REAL", types.zigToSQLType(f32));
        try std.testing.expectEqualStrings("DOUBLE PRECISION", types.zigToSQLType(f64));
    }
}

test "zigToSQLType: bool type" {
    comptime {
        try std.testing.expectEqualStrings("BOOLEAN", types.zigToSQLType(bool));
    }
}

test "zigToSQLType: string type" {
    comptime {
        try std.testing.expectEqualStrings("TEXT", types.zigToSQLType([]const u8));
    }
}

test "zigToSQLType: optional types" {
    comptime {
        try std.testing.expectEqualStrings("BIGINT", types.zigToSQLType(?i64));
        try std.testing.expectEqualStrings("TEXT", types.zigToSQLType(?[]const u8));
        try std.testing.expectEqualStrings("BOOLEAN", types.zigToSQLType(?bool));
        try std.testing.expectEqualStrings("INTEGER", types.zigToSQLType(?u32));
    }
}

// ============ getFieldNames() 测试 ============

test "getFieldNames: extract field names" {
    const User = struct {
        id: i64,
        name: []const u8,
        email: []const u8,
    };

    const names = comptime types.getFieldNames(User);

    try std.testing.expectEqual(@as(usize, 3), names.len);
    try std.testing.expectEqualStrings("id", names[0]);
    try std.testing.expectEqualStrings("name", names[1]);
    try std.testing.expectEqualStrings("email", names[2]);
}

// ============ getFieldTypes() 测试 ============

test "getFieldTypes: extract field types" {
    const User = struct {
        id: i64,
        name: []const u8,
        active: bool,
    };

    const field_types = comptime types.getFieldTypes(User);

    try std.testing.expectEqual(@as(usize, 3), field_types.len);
    try std.testing.expect(field_types[0] == i64);
    try std.testing.expect(field_types[1] == []const u8);
    try std.testing.expect(field_types[2] == bool);
}

// ============ validateType() 测试 ============

test "validateType: valid struct with basic types" {
    const User = struct {
        id: i64,
        name: []const u8,
        age: u32,
        balance: f64,
        active: bool,
    };

    comptime types.validateType(User);
    // 通过表示验证成功
}

test "validateType: valid struct with optional types" {
    const User = struct {
        id: i64,
        name: []const u8,
        bio: ?[]const u8,
        age: ?u32,
    };

    comptime types.validateType(User);
    // 通过表示验证成功
}

// ============ isOptional() 测试 ============

test "isOptional: check optional types" {
    comptime {
        try std.testing.expect(types.isOptional(?i64) == true);
        try std.testing.expect(types.isOptional(?[]const u8) == true);
        try std.testing.expect(types.isOptional(i64) == false);
        try std.testing.expect(types.isOptional([]const u8) == false);
    }
}

// Note: toLowerSnakeCase 和 extractTypeName 是内部函数,
// 通过 getTableName 间接测试

// ============ 集成测试 ============

test "type system integration: complete workflow" {
    const User = struct {
        id: i64,
        name: []const u8,
        email: []const u8,
        age: ?u32,
        bio: ?[]const u8,

        pub const table_name = "users";
    };

    // 验证类型有效
    comptime types.validateType(User);

    // 获取表名
    const table_name = comptime types.getTableName(User);
    try std.testing.expectEqualStrings("users", table_name);

    // 获取字段
    const fields = comptime types.getFields(User);
    try std.testing.expectEqual(@as(usize, 5), fields.len);

    // 获取字段名
    const field_names = comptime types.getFieldNames(User);
    try std.testing.expectEqual(@as(usize, 5), field_names.len);
    try std.testing.expectEqualStrings("id", field_names[0]);

    // 验证类型映射
    comptime {
        try std.testing.expectEqualStrings("BIGINT", types.zigToSQLType(i64));
        try std.testing.expectEqualStrings("TEXT", types.zigToSQLType([]const u8));
        try std.testing.expectEqualStrings("INTEGER", types.zigToSQLType(?u32));
    }

    // 检查可选类型
    try std.testing.expect(types.isOptional(?u32) == true);
    try std.testing.expect(types.isOptional(i64) == false);
}
