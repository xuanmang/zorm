//! 测试 Debug 模式和错误上下文增强功能

const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");
const DBOptions = zorm.DBOptions;

// 测试 DBOptions 的 debug 字段默认值
test "DBOptions: debug 选项默认为 false" {
    const options = DBOptions{};
    try testing.expect(options.debug == false);
}

// 测试 DBOptions 的 debug 字段可设置
test "DBOptions: debug 选项可设置为 true" {
    const options = DBOptions{ .debug = true };
    try testing.expect(options.debug == true);
}

// 测试 DBOptions: debug 选项可与其他选项一起使用
test "DBOptions: debug 选项与其他选项兼容" {
    const options = DBOptions{
        .debug = true,
        .enable_query_log = true,
        .max_open_conns = 50,
    };
    try testing.expect(options.debug == true);
    try testing.expect(options.enable_query_log == true);
    try testing.expect(options.max_open_conns == 50);
}
