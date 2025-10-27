//! 事务管理示例
//!
//! 本示例演示 ZORM 的事务处理:
//! 1. 开启事务 (BEGIN)
//! 2. 提交事务 (COMMIT)
//! 3. 回滚事务 (ROLLBACK)
//! 4. 使用 errdefer 自动回滚
//! 5. 事务隔离级别设置
//! 6. 嵌套事务 (SavePoint)
//!
//! 运行方式:
//! ```sh
//! zig build run-example-transaction
//! ```

const std = @import("std");
const zorm = @import("zorm");

const Account = struct {
    id: i64 = 0,
    username: []const u8,
    balance: f64,

    pub const table_name = "accounts";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("ZORM 事务管理示例\n", .{});
    std.debug.print("=" ** 60 ++ "\n\n", .{});

    try demonstrateTransactions(allocator);

    std.debug.print("\n✅ 示例执行完成!\n", .{});
}

fn demonstrateTransactions(allocator: std.mem.Allocator) !void {
    std.debug.print("📝 演示事务管理 API:\n\n", .{});

    // ========================================
    // 1. 基础事务: BEGIN / COMMIT
    // ========================================
    std.debug.print("1️⃣  基础事务: BEGIN / COMMIT\n", .{});
    try demonstrateBasicTransaction(allocator);

    // ========================================
    // 2. 事务回滚: ROLLBACK
    // ========================================
    std.debug.print("\n2️⃣  事务回滚: ROLLBACK\n", .{});
    try demonstrateRollback(allocator);

    // ========================================
    // 3. 使用 errdefer 自动回滚
    // ========================================
    std.debug.print("\n3️⃣  使用 errdefer 自动回滚\n", .{});
    try demonstrateErrdefer(allocator);

    // ========================================
    // 4. 事务隔离级别
    // ========================================
    std.debug.print("\n4️⃣  事务隔离级别\n", .{});
    try demonstrateIsolationLevels(allocator);

    // ========================================
    // 5. 转账示例 (经典事务场景)
    // ========================================
    std.debug.print("\n5️⃣  转账示例 (经典事务场景)\n", .{});
    try demonstrateTransfer(allocator);
}

/// 演示基础事务
fn demonstrateBasicTransaction(allocator: std.mem.Allocator) !void {
    // 伪代码示例
    _ = allocator;

    std.debug.print("   // 开启事务\n", .{});
    std.debug.print("   var tx = try db.begin();\n", .{});
    std.debug.print("   defer tx.deinit();\n\n", .{});

    std.debug.print("   // 执行操作\n", .{});
    std.debug.print("   try tx.exec(\"INSERT INTO accounts ...\");\n", .{});
    std.debug.print("   try tx.exec(\"UPDATE accounts ...\");\n\n", .{});

    std.debug.print("   // 提交事务\n", .{});
    std.debug.print("   try tx.commit();\n", .{});
}

/// 演示事务回滚
fn demonstrateRollback(allocator: std.mem.Allocator) !void {
    _ = allocator;

    std.debug.print("   var tx = try db.begin();\n", .{});
    std.debug.print("   defer tx.deinit();\n\n", .{});

    std.debug.print("   try tx.exec(\"UPDATE accounts SET balance = balance - 100 WHERE id = 1\");\n\n", .{});

    std.debug.print("   // 检测到问题,回滚事务\n", .{});
    std.debug.print("   if (检测到错误) {{\n", .{});
    std.debug.print("       try tx.rollback();\n", .{});
    std.debug.print("       return error.TransactionFailed;\n", .{});
    std.debug.print("   }}\n", .{});
}

/// 演示 errdefer 自动回滚
fn demonstrateErrdefer(allocator: std.mem.Allocator) !void {
    _ = allocator;

    std.debug.print("   var tx = try db.begin();\n", .{});
    std.debug.print("   defer tx.deinit();\n", .{});
    std.debug.print("   errdefer tx.rollback() catch {{}}; // 出错时自动回滚\n\n", .{});

    std.debug.print("   // 任何错误都会触发 errdefer 回滚\n", .{});
    std.debug.print("   try tx.exec(\"UPDATE accounts ...\");\n", .{});
    std.debug.print("   try tx.exec(\"UPDATE accounts ...\"); // 如果失败自动回滚\n\n", .{});

    std.debug.print("   try tx.commit();\n", .{});
}

/// 演示隔离级别
fn demonstrateIsolationLevels(allocator: std.mem.Allocator) !void {
    _ = allocator;

    std.debug.print("   // 默认隔离级别 (READ COMMITTED)\n", .{});
    std.debug.print("   var tx1 = try db.begin();\n\n", .{});

    std.debug.print("   // 设置 REPEATABLE READ 隔离级别\n", .{});
    std.debug.print("   var tx2 = try db.beginTx(.{{ .isolation_level = .repeatable_read }});\n\n", .{});

    std.debug.print("   // 设置 SERIALIZABLE 隔离级别\n", .{});
    std.debug.print("   var tx3 = try db.beginTx(.{{ .isolation_level = .serializable }});\n\n", .{});

    std.debug.print("   // 设置 READ UNCOMMITTED 隔离级别\n", .{});
    std.debug.print("   var tx4 = try db.beginTx(.{{ .isolation_level = .read_uncommitted }});\n", .{});
}

/// 演示转账 (经典事务场景)
fn demonstrateTransfer(allocator: std.mem.Allocator) !void {
    _ = allocator;

    std.debug.print("   // 转账函数: 从账户 A 转给账户 B\n", .{});
    std.debug.print("   fn transfer(db: *DB, from_id: i64, to_id: i64, amount: f64) !void {{\n", .{});
    std.debug.print("       // 开启事务\n", .{});
    std.debug.print("       var tx = try db.begin();\n", .{});
    std.debug.print("       defer tx.deinit();\n", .{});
    std.debug.print("       errdefer tx.rollback() catch {{}};\n\n", .{});

    std.debug.print("       // 1. 从源账户扣款\n", .{});
    std.debug.print("       var deduct = db.newUpdate(Account)\n", .{});
    std.debug.print("           .set(\"balance\", \"balance - $1\")\n", .{});
    std.debug.print("           .where(\"id\", .eq, from_id)\n", .{});
    std.debug.print("           .where(\"balance\", .gte, amount); // 确保余额充足\n", .{});
    std.debug.print("       const deduct_result = try tx.exec(&deduct, .{{amount}});\n", .{});
    std.debug.print("       if (deduct_result.rows_affected == 0) {{\n", .{});
    std.debug.print("           return error.InsufficientBalance;\n", .{});
    std.debug.print("       }}\n\n", .{});

    std.debug.print("       // 2. 向目标账户加款\n", .{});
    std.debug.print("       var credit = db.newUpdate(Account)\n", .{});
    std.debug.print("           .set(\"balance\", \"balance + $1\")\n", .{});
    std.debug.print("           .where(\"id\", .eq, to_id);\n", .{});
    std.debug.print("       _ = try tx.exec(&credit, .{{amount}});\n\n", .{});

    std.debug.print("       // 3. 提交事务\n", .{});
    std.debug.print("       try tx.commit();\n", .{});
    std.debug.print("   }}\n", .{});
}
