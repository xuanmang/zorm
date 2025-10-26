//! Comptime 反射和 SQL 模板生成优化
//!
//! AC4.8.4: 利用 Zig comptime 特性将类型映射和 SQL 模板生成移到编译时

const std = @import("std");

/// 在编译时生成列名列表（逗号分隔）
/// 例如: "id, name, email, age"
pub fn generateColumnList(comptime T: type) []const u8 {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("generateColumnList requires a struct type");
    }
    const fields = type_info.@"struct".fields;
    comptime var result: []const u8 = "";
    inline for (fields, 0..) |field, i| {
        if (i > 0) result = result ++ ", ";
        result = result ++ field.name;
    }
    return result;
}

/// 在编译时生成 SELECT 查询模板
/// 例如: "SELECT id, name, email, age FROM users"
pub fn generateSelectTemplate(comptime T: type, comptime table_name: []const u8) []const u8 {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("generateSelectTemplate requires a struct type");
    }
    const fields = type_info.@"struct".fields;

    // 在单个 scope 内构建完整的 SQL 字符串
    comptime var result: []const u8 = "SELECT ";
    inline for (fields, 0..) |field, i| {
        if (i > 0) result = result ++ ", ";
        result = result ++ field.name;
    }
    result = result ++ " FROM " ++ table_name;
    return result;
}

/// 在编译时生成占位符列表（用于 INSERT）
/// 例如: "$1, $2, $3, $4"
pub fn generatePlaceholders(comptime T: type, comptime start_index: usize) []const u8 {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("generatePlaceholders requires a struct type");
    }
    const fields = type_info.@"struct".fields;
    comptime var result: []const u8 = "";
    inline for (fields, 0..) |_, i| {
        if (i > 0) result = result ++ ", ";
        const idx = start_index + i;
        // 简单的数字转字符串实现（支持 1-20）
        if (idx == 1) result = result ++ "$1"
        else if (idx == 2) result = result ++ "$2"
        else if (idx == 3) result = result ++ "$3"
        else if (idx == 4) result = result ++ "$4"
        else if (idx == 5) result = result ++ "$5"
        else if (idx == 6) result = result ++ "$6"
        else if (idx == 7) result = result ++ "$7"
        else if (idx == 8) result = result ++ "$8"
        else if (idx == 9) result = result ++ "$9"
        else if (idx == 10) result = result ++ "$10"
        else if (idx == 11) result = result ++ "$11"
        else if (idx == 12) result = result ++ "$12"
        else if (idx == 13) result = result ++ "$13"
        else if (idx == 14) result = result ++ "$14"
        else if (idx == 15) result = result ++ "$15"
        else if (idx == 16) result = result ++ "$16"
        else if (idx == 17) result = result ++ "$17"
        else if (idx == 18) result = result ++ "$18"
        else if (idx == 19) result = result ++ "$19"
        else if (idx == 20) result = result ++ "$20"
        else @compileError("generatePlaceholders: index > 20 not supported");
    }
    return result;
}

/// 在编译时生成 INSERT 查询模板
/// 例如: "INSERT INTO users (id, name, email, age) VALUES ($1, $2, $3, $4)"
pub fn generateInsertTemplate(comptime T: type, comptime table_name: []const u8) []const u8 {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("generateInsertTemplate requires a struct type");
    }
    const fields = type_info.@"struct".fields;

    // 在单个 scope 内构建完整的 INSERT SQL
    comptime var result: []const u8 = "INSERT INTO " ++ table_name ++ " (";

    // 列名列表
    inline for (fields, 0..) |field, i| {
        if (i > 0) result = result ++ ", ";
        result = result ++ field.name;
    }

    result = result ++ ") VALUES (";

    // 占位符列表
    inline for (fields, 0..) |_, i| {
        if (i > 0) result = result ++ ", ";
        const idx = i + 1;
        if (idx == 1) result = result ++ "$1"
        else if (idx == 2) result = result ++ "$2"
        else if (idx == 3) result = result ++ "$3"
        else if (idx == 4) result = result ++ "$4"
        else if (idx == 5) result = result ++ "$5"
        else if (idx == 6) result = result ++ "$6"
        else if (idx == 7) result = result ++ "$7"
        else if (idx == 8) result = result ++ "$8"
        else if (idx == 9) result = result ++ "$9"
        else if (idx == 10) result = result ++ "$10"
        else if (idx == 11) result = result ++ "$11"
        else if (idx == 12) result = result ++ "$12"
        else if (idx == 13) result = result ++ "$13"
        else if (idx == 14) result = result ++ "$14"
        else if (idx == 15) result = result ++ "$15"
        else if (idx == 16) result = result ++ "$16"
        else if (idx == 17) result = result ++ "$17"
        else if (idx == 18) result = result ++ "$18"
        else if (idx == 19) result = result ++ "$19"
        else if (idx == 20) result = result ++ "$20"
        else @compileError("generateInsertTemplate: too many fields (> 20)");
    }

    result = result ++ ")";
    return result;
}

/// 在编译时获取字段数量
pub fn fieldCount(comptime T: type) usize {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("fieldCount requires a struct type");
    }
    return type_info.@"struct".fields.len;
}

test "generateColumnList" {
    const User = struct {
        id: i64,
        name: []const u8,
        email: []const u8,
        age: i32,
    };

    const columns = generateColumnList(User);
    try std.testing.expectEqualStrings("id, name, email, age", columns);
}

test "generateSelectTemplate" {
    const User = struct {
        id: i64,
        name: []const u8,
        email: []const u8,
    };

    const sql = generateSelectTemplate(User, "users");
    try std.testing.expectEqualStrings("SELECT id, name, email FROM users", sql);
}

test "generatePlaceholders" {
    const User = struct {
        id: i64,
        name: []const u8,
        email: []const u8,
    };

    const placeholders = generatePlaceholders(User, 1);
    try std.testing.expectEqualStrings("$1, $2, $3", placeholders);
}

test "generateInsertTemplate" {
    const User = struct {
        id: i64,
        name: []const u8,
    };

    const sql = generateInsertTemplate(User, "users");
    try std.testing.expectEqualStrings("INSERT INTO users (id, name) VALUES ($1, $2)", sql);
}

test "fieldCount" {
    const User = struct {
        id: i64,
        name: []const u8,
        email: []const u8,
        age: i32,
    };

    try std.testing.expectEqual(4, fieldCount(User));
}
