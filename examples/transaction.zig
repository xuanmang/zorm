//! Transaction Example - Story 2.4
//!
//! 演示 ZORM 事务管理功能:
//! - beginTx() 开启事务
//! - commit() 提交事务
//! - rollback() 回滚事务
//! - errdefer 自动回滚
//! - 嵌套事务检测
//!
//! 编译运行:
//! zig build && ./zig-out/bin/transaction_example

const std = @import("std");
const zorm = @import("zorm");

/// 示例:用户模型
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: i32,

    pub const table_name = "users";
};

/// 示例:文章模型
const Post = struct {
    id: i64,
    user_id: i64,
    title: []const u8,
    content: []const u8,
    created_at: i64,

    pub const table_name = "posts";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== ZORM Transaction Example (Story 2.4) ===\n\n", .{});

    // 注意:此示例仅演示 API 使用,不连接真实数据库
    std.debug.print("1. 基本事务流程\n", .{});
    try exampleBasicTransaction(allocator);

    std.debug.print("\n2. 错误回滚 (errdefer)\n", .{});
    try exampleErrorRollback(allocator);

    std.debug.print("\n3. 嵌套事务检测\n", .{});
    try exampleNestedTransaction(allocator);

    std.debug.print("\n4. 自动回滚 (deinit)\n", .{});
    try exampleAutoRollback(allocator);

    std.debug.print("\n=== 示例完成 ===\n", .{});
}

/// 示例 1: 基本事务流程
fn exampleBasicTransaction(allocator: std.mem.Allocator) !void {
    _ = allocator;

    std.debug.print("   - 开启事务: db.beginTx()\n", .{});
    std.debug.print("   - 执行操作: tx.newInsert(User)...\n", .{});
    std.debug.print("   - 提交事务: tx.commit()\n", .{});

    // 伪代码演示
    std.debug.print("   ```zig\n", .{});
    std.debug.print("   var tx = try db.beginTx(.{});\n", .{});
    std.debug.print("   defer tx.deinit();\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   var insert = try tx.newInsert(User);\n", .{});
    std.debug.print("   defer insert.deinit();\n", .{});
    std.debug.print("   try insert.value(user).exec();\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   try tx.commit();\n", .{});
    std.debug.print("   ```\n", .{});
}

/// 示例 2: 错误回滚
fn exampleErrorRollback(allocator: std.mem.Allocator) !void {
    _ = allocator;

    std.debug.print("   - 使用 errdefer 确保错误时回滚\n", .{});
    std.debug.print("   - 业务逻辑失败自动回滚事务\n", .{});

    std.debug.print("   ```zig\n", .{});
    std.debug.print("   var tx = try db.beginTx(.{});\n", .{});
    std.debug.print("   defer tx.deinit();\n", .{});
    std.debug.print("   errdefer tx.rollback() catch {};\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 插入用户\n", .{});
    std.debug.print("   var insert_user = try tx.newInsert(User);\n", .{});
    std.debug.print("   defer insert_user.deinit();\n", .{});
    std.debug.print("   try insert_user.value(user).exec();\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 业务逻辑验证\n", .{});
    std.debug.print("   if (user.age < 18) {\n", .{});
    std.debug.print("       return error.InvalidAge; // 自动回滚\n", .{});
    std.debug.print("   }\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   try tx.commit();\n", .{});
    std.debug.print("   ```\n", .{});
}

/// 示例 3: 嵌套事务检测
fn exampleNestedTransaction(allocator: std.mem.Allocator) !void {
    _ = allocator;

    std.debug.print("   - Story 2.4 禁止嵌套事务\n", .{});
    std.debug.print("   - beginTx() 会检测并返回 error.NestedTransaction\n", .{});

    std.debug.print("   ```zig\n", .{});
    std.debug.print("   var tx1 = try db.beginTx(.{});\n", .{});
    std.debug.print("   defer tx1.deinit();\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 尝试开启嵌套事务\n", .{});
    std.debug.print("   var tx2 = db.beginTx(.{});\n", .{});
    std.debug.print("   // 错误: error.NestedTransaction\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   注意: SAVEPOINT 支持将在 v2.0 实现\n", .{});
}

/// 示例 4: 自动回滚
fn exampleAutoRollback(allocator: std.mem.Allocator) !void {
    _ = allocator;

    std.debug.print("   - deinit() 自动回滚未提交的事务\n", .{});
    std.debug.print("   - 防止意外的数据不一致\n", .{});

    std.debug.print("   ```zig\n", .{});
    std.debug.print("   {\n", .{});
    std.debug.print("       var tx = try db.beginTx(.{});\n", .{});
    std.debug.print("       defer tx.deinit(); // 自动回滚\n", .{});
    std.debug.print("       \n", .{});
    std.debug.print("       var insert = try tx.newInsert(User);\n", .{});
    std.debug.print("       defer insert.deinit();\n", .{});
    std.debug.print("       try insert.value(user).exec();\n", .{});
    std.debug.print("       \n", .{});
    std.debug.print("       // 忘记 commit(),离开作用域时自动回滚\n", .{});
    std.debug.print("   }\n", .{});
    std.debug.print("   ```\n", .{});
}
