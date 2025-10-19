//! DB 集成测试
//!
//! 测试 DB 层与 Driver 层的集成,验证:
//! - 类型安全的参数传递 (QueryArg)
//! - 接口签名的一致性
//! - 编译时类型检查

const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");

// 测试用户模型
const User = struct {
    id: i32,
    name: []const u8,
    email: []const u8,
    age: ?i32 = null,
};

test "DB integration - type safety with QueryArg" {
    // 这个测试验证类型签名的一致性
    // 不需要真实数据库连接,只验证编译时类型安全

    const QueryArg = zorm.QueryArg;

    // 验证 QueryArg 的基本用法
    const args = [_]QueryArg{
        QueryArg.fromValue(@as(i64, 1)),
        QueryArg.fromValue("test@example.com"),
    };

    try testing.expectEqual(@as(usize, 2), args.len);
    try testing.expectEqual(@as(i64, 1), args[0].int);
    try testing.expectEqualStrings("test@example.com", args[1].string);
}

test "DB integration - query builder types exist" {
    // 验证查询构建器类型存在且可被实例化
    // 这确保了它们被正确导出

    // 测试类型是否存在
    const SelectQueryType = zorm.SelectQuery(User, .postgresql);
    const InsertQueryType = zorm.InsertQuery(User, .postgresql);
    const UpdateQueryType = zorm.UpdateQuery(User, .postgresql);
    const DeleteQueryType = zorm.DeleteQuery(User, .postgresql);
    const CreateTableQueryType = zorm.CreateTableQuery(User, .postgresql);

    // 验证类型大小合理(即类型定义正确)
    try testing.expect(@sizeOf(SelectQueryType) > 0);
    try testing.expect(@sizeOf(InsertQueryType) > 0);
    try testing.expect(@sizeOf(UpdateQueryType) > 0);
    try testing.expect(@sizeOf(DeleteQueryType) > 0);
    try testing.expect(@sizeOf(CreateTableQueryType) > 0);
}

test "DB integration - QueryArg type conversions" {
    // 测试 QueryArg 对各种 Zig 类型的支持
    const QueryArg = zorm.QueryArg;

    // 整数类型
    const int_arg = QueryArg.fromValue(@as(i32, 42));
    try testing.expectEqual(@as(i64, 42), int_arg.int);

    // 无符号整数
    const uint_arg = QueryArg.fromValue(@as(u32, 100));
    try testing.expectEqual(@as(u64, 100), uint_arg.uint);

    // 浮点数
    const float_arg = QueryArg.fromValue(@as(f32, 3.14));
    try testing.expectApproxEqAbs(@as(f64, 3.14), float_arg.float, 0.01);

    // 布尔值
    const bool_arg = QueryArg.fromValue(true);
    try testing.expectEqual(true, bool_arg.bool);

    // 字符串
    const string_arg = QueryArg.fromValue("hello");
    try testing.expectEqualStrings("hello", string_arg.string);
}

test "DB integration - interface types exist" {
    // 验证核心接口类型存在
    // 这是编译时检查,确保模块正确导出

    const Conn = zorm.core.Conn;
    const Tx = zorm.core.Tx;
    const DBType = zorm.DB(.postgresql);

    // 验证类型存在
    try testing.expect(@sizeOf(Conn) > 0);
    try testing.expect(@sizeOf(Tx) > 0);
    try testing.expect(@sizeOf(DBType) > 0);
}

test "DB integration - schema types exist" {
    // 验证 Schema 相关类型被正确导出
    const Table = zorm.Table;
    const Column = zorm.Column;
    const ColumnType = zorm.ColumnType;

    // 验证类型存在
    try testing.expect(@sizeOf(Table) > 0);
    try testing.expect(@sizeOf(Column) > 0);
    try testing.expect(@sizeOf(ColumnType) > 0);
}
