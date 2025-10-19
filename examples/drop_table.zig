const std = @import("std");

// 注意: 这个示例展示 DROP TABLE API 用法,但实际运行需要真实的数据库连接
// 在实际使用中,请替换为真实的 DB 实例

const User = struct {
    id: i64,
    name: []const u8,
    email: ?[]const u8,
    created_at: i64,

    pub const table_name = "users";
};

const Post = struct {
    id: i64,
    title: []const u8,
    user_id: i64,

    pub const table_name = "posts";
};

pub fn main() !void {
    std.debug.print("=== DROP TABLE Query Builder 示例 ===\n\n", .{});

    // 示例 1: 基础 DROP TABLE
    std.debug.print("示例 1: 基础 DROP TABLE\n", .{});
    std.debug.print("代码: var drop = try db.newDropTable(User);\n", .{});
    std.debug.print("      try drop.exec();\n", .{});
    std.debug.print("SQL:  DROP TABLE users\n\n", .{});

    // 示例 2: DROP TABLE IF EXISTS
    std.debug.print("示例 2: DROP TABLE IF EXISTS\n", .{});
    std.debug.print("代码: var drop = try db.newDropTable(User);\n", .{});
    std.debug.print("      try drop.ifExists().exec();\n", .{});
    std.debug.print("SQL:  DROP TABLE IF EXISTS users\n", .{});
    std.debug.print("说明: 如果表不存在,不会报错\n\n", .{});

    // 示例 3: DROP TABLE CASCADE
    std.debug.print("示例 3: DROP TABLE CASCADE\n", .{});
    std.debug.print("代码: var drop = try db.newDropTable(User);\n", .{});
    std.debug.print("      try drop.ifExists().cascade().exec();\n", .{});
    std.debug.print("SQL:  DROP TABLE IF EXISTS users CASCADE\n", .{});
    std.debug.print("说明: 级联删除所有依赖对象(视图、外键等)\n", .{});
    std.debug.print("警告: ⚠️  谨慎使用,可能删除意外的对象!\n\n", .{});

    // 示例 4: DROP TABLE RESTRICT
    std.debug.print("示例 4: DROP TABLE RESTRICT\n", .{});
    std.debug.print("代码: var drop = try db.newDropTable(User);\n", .{});
    std.debug.print("      try drop.ifExists().restrict().exec();\n", .{});
    std.debug.print("SQL:  DROP TABLE IF EXISTS users RESTRICT\n", .{});
    std.debug.print("说明: 如果有依赖对象,拒绝删除并返回错误(默认行为)\n\n", .{});

    // 示例 5: 完整的资源管理
    std.debug.print("示例 5: 完整的资源管理示例\n", .{});
    std.debug.print("```zig\n", .{});
    std.debug.print("var drop = try db.newDropTable(User);\n", .{});
    std.debug.print("defer drop.deinit();  // 自动清理资源\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("try drop.ifExists().cascade().exec();\n", .{});
    std.debug.print("```\n\n", .{});

    // 示例 6: 链式调用
    std.debug.print("示例 6: 链式调用\n", .{});
    std.debug.print("```zig\n", .{});
    std.debug.print("try db.newDropTable(Post)\n", .{});
    std.debug.print("    .ifExists()\n", .{});
    std.debug.print("    .cascade()\n", .{});
    std.debug.print("    .exec();\n", .{});
    std.debug.print("```\n\n", .{});

    // 示例 7: CASCADE 和 RESTRICT 互斥性
    std.debug.print("示例 7: CASCADE 和 RESTRICT 互斥性\n", .{});
    std.debug.print("代码: var drop = try db.newDropTable(User);\n", .{});
    std.debug.print("      _ = drop.cascade();   // 设置 CASCADE\n", .{});
    std.debug.print("      _ = drop.restrict();  // 覆盖为 RESTRICT\n", .{});
    std.debug.print("SQL:  DROP TABLE users RESTRICT\n", .{});
    std.debug.print("说明: 后调用的选项覆盖前面的选项\n\n", .{});

    // 示例 8: 构建 SQL 但不执行
    std.debug.print("示例 8: 构建 SQL 但不执行\n", .{});
    std.debug.print("```zig\n", .{});
    std.debug.print("const allocator = std.heap.page_allocator;\n", .{});
    std.debug.print("var drop = try db.newDropTable(User);\n", .{});
    std.debug.print("defer drop.deinit();\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("const sql = try drop.ifExists().build();\n", .{});
    std.debug.print("defer allocator.free(sql);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("std.debug.print(\"SQL: {{s}}\\n\", .{{sql}});\n", .{});
    std.debug.print("// 输出: DROP TABLE IF EXISTS users\n", .{});
    std.debug.print("```\n\n", .{});

    // 使用建议
    std.debug.print("=== 使用建议 ===\n\n", .{});
    std.debug.print("1. 推荐始终使用 .ifExists() 避免表不存在时报错\n", .{});
    std.debug.print("2. CASCADE 应谨慎使用,仅在明确需要级联删除时使用\n", .{});
    std.debug.print("3. RESTRICT 是默认行为,显式使用主要为代码可读性\n", .{});
    std.debug.print("4. 在生产环境删除表前,务必备份数据!\n", .{});
    std.debug.print("5. 使用 defer drop.deinit() 确保资源释放\n\n", .{});

    std.debug.print("✅ 示例完成!\n", .{});
}
