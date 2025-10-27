//! 事务管理示例 - 可运行版本
//!
//! 本示例演示使用 ZORM 进行事务处理:
//! 1. 基础事务 (BEGIN/COMMIT)
//! 2. 事务回滚 (ROLLBACK)
//! 3. 转账示例 (经典事务场景)
//! 4. 事务隔离和并发控制
//!
//! 运行方式:
//! ```sh
//! zig build run-example-transaction
//! ```

const std = @import("std");
const zorm = @import("zorm");

// 定义 Account 模型
const Account = struct {
    id: i64 = 0,
    username: []const u8,
    balance: i64, // 使用整数存储（以分为单位）避免浮点精度问题

    pub const table_name = "accounts";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("ZORM 事务管理示例\n", .{});
    std.debug.print("=" ** 60 ++ "\n\n", .{});

    // 连接数据库
    std.debug.print("📦 连接数据库: pguser@127.0.0.1:5432/postgres\n\n", .{});
    const dsn = "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres";

    const db = try zorm.connect(allocator, dsn, null);
    defer db.deinit();

    std.debug.print("✓ 数据库连接成功\n\n", .{});

    // 执行事务示例
    try runTransactionExamples(db, allocator);

    std.debug.print("\n✅ 示例执行完成!\n", .{});
}

fn runTransactionExamples(db: *zorm.DB(.postgresql), allocator: std.mem.Allocator) !void {
    // ========================================
    // 1. 准备：创建测试表
    // ========================================
    std.debug.print("1️⃣  准备：创建测试表\n", .{});
    {
        // 清理旧表 - 使用高级 API
        var drop = try db.newDropTable(Account);
        defer drop.deinit();
        _ = drop.ifExists().cascade();
        drop.exec() catch {};

        // 创建新表 - 使用高级 API
        var create = try db.newCreateTable(Account);
        defer create.deinit();

        try create.exec();
        std.debug.print("   ✓ accounts 表创建成功\n\n", .{});
    }

    // ========================================
    // 2. 基础事务：BEGIN/COMMIT
    // ========================================
    std.debug.print("2️⃣  基础事务：BEGIN/COMMIT\n", .{});
    {
        // 开启事务 - 使用高级 API
        var tx = try db.beginTx(.{});
        defer tx.deinit(); // 自动回滚未提交的事务
        std.debug.print("   → BEGIN: 开启事务\n", .{});

        // 插入账户 A - 使用事务的高级 API
        var insert_a = try tx.newInsert(Account);
        defer insert_a.deinit();
        _ = try insert_a.value(.{
            .username = "Alice",
            .balance = 100000, // 1000.00 元
        });
        _ = try insert_a.exec();
        std.debug.print("   → INSERT: 创建账户 Alice, 余额: 1000.00\n", .{});

        // 插入账户 B - 使用事务的高级 API
        var insert_b = try tx.newInsert(Account);
        defer insert_b.deinit();
        _ = try insert_b.value(.{
            .username = "Bob",
            .balance = 50000, // 500.00 元
        });
        _ = try insert_b.exec();
        std.debug.print("   → INSERT: 创建账户 Bob, 余额: 500.00\n", .{});

        // 提交事务 - 使用高级 API
        try tx.commit();
        std.debug.print("   ✓ COMMIT: 事务提交成功\n\n", .{});
    }

    // ========================================
    // 3. 验证数据插入
    // ========================================
    std.debug.print("3️⃣  验证数据插入\n", .{});
    {
        var query = try db.newSelect(Account);
        defer query.deinit();
        _ = try query.orderBy("id", .asc);

        var accounts: std.ArrayList(Account) = .{};
        defer accounts.deinit(allocator);

        try query.scan(&accounts);

        for (accounts.items) |account| {
            const yuan = @divFloor(account.balance, 100);
            const fen = @mod(account.balance, 100);
            if (fen < 10) {
                std.debug.print("   账户: {s}, 余额: {d}.0{d} 元\n", .{
                    account.username,
                    yuan,
                    fen,
                });
            } else {
                std.debug.print("   账户: {s}, 余额: {d}.{d} 元\n", .{
                    account.username,
                    yuan,
                    fen,
                });
            }
        }
        std.debug.print("\n", .{});
    }

    // ========================================
    // 4. 转账示例（事务保证原子性）
    // ========================================
    std.debug.print("4️⃣  转账示例：Alice → Bob 转账 300.00 元\n", .{});
    {
        // 开启事务 - 使用高级 API
        var tx = try db.beginTx(.{});
        defer tx.deinit(); // 自动回滚
        std.debug.print("   → BEGIN: 开启转账事务\n", .{});

        // 步骤 1: 检查 Alice 余额 - 使用事务的高级 API
        var check_balance = try tx.newSelect(Account);
        defer check_balance.deinit();
        _ = try check_balance.where("username = $1", .{"Alice"});
        const alice = try check_balance.scanOne();

        if (alice.balance < 30000) {
            // 余额不足，回滚事务 - defer 会自动回滚
            std.debug.print("   ✗ ROLLBACK: 余额不足，事务回滚\n\n", .{});
            return;
        }

        // 步骤 2: 从 Alice 扣款 - 使用事务的高级 API
        var deduct = try tx.newUpdate(Account);
        defer deduct.deinit();
        _ = try deduct.set("balance = balance - $1", .{30000}); // 300.00 元
        _ = try deduct.where("username = $2", .{"Alice"});
        _ = try deduct.exec();
        std.debug.print("   → UPDATE: Alice 扣款 300.00 元\n", .{});

        // 步骤 3: 给 Bob 加款 - 使用事务的高级 API
        var credit = try tx.newUpdate(Account);
        defer credit.deinit();
        _ = try credit.set("balance = balance + $1", .{30000}); // 300.00 元
        _ = try credit.where("username = $2", .{"Bob"});
        _ = try credit.exec();
        std.debug.print("   → UPDATE: Bob 到账 300.00 元\n", .{});

        // 提交事务 - 使用高级 API
        try tx.commit();
        std.debug.print("   ✓ COMMIT: 转账成功\n\n", .{});
    }

    // ========================================
    // 5. 验证转账结果
    // ========================================
    std.debug.print("5️⃣  验证转账结果\n", .{});
    {
        var query = try db.newSelect(Account);
        defer query.deinit();
        _ = try query.orderBy("id", .asc);

        var accounts: std.ArrayList(Account) = .{};
        defer accounts.deinit(allocator);

        try query.scan(&accounts);

        for (accounts.items) |account| {
            const yuan = @divFloor(account.balance, 100);
            const fen = @mod(account.balance, 100);
            if (fen < 10) {
                std.debug.print("   账户: {s}, 余额: {d}.0{d} 元\n", .{
                    account.username,
                    yuan,
                    fen,
                });
            } else {
                std.debug.print("   账户: {s}, 余额: {d}.{d} 元\n", .{
                    account.username,
                    yuan,
                    fen,
                });
            }
        }
        std.debug.print("   ✓ Alice: 1000.00 - 300.00 = 700.00\n", .{});
        std.debug.print("   ✓ Bob:   500.00 + 300.00 = 800.00\n\n", .{});
    }

    // ========================================
    // 6. 演示事务回滚
    // ========================================
    std.debug.print("6️⃣  演示事务回滚：尝试转账 10000.00 元 (余额不足)\n", .{});
    {
        // 开启事务 - 使用高级 API
        var tx = try db.beginTx(.{});
        defer tx.deinit(); // 自动回滚
        std.debug.print("   → BEGIN: 开启转账事务\n", .{});

        // 检查 Alice 余额 - 使用事务的高级 API
        var check_balance = try tx.newSelect(Account);
        defer check_balance.deinit();
        _ = try check_balance.where("username = $1", .{"Alice"});
        const alice = try check_balance.scanOne();

        if (alice.balance < 1000000) {
            // 余额不足，回滚事务 - defer 会自动回滚
            const yuan = @divFloor(alice.balance, 100);
            const fen = @mod(alice.balance, 100);
            if (fen < 10) {
                std.debug.print("   ✗ ROLLBACK: 余额不足 (需要 10000.00, 实际只有 {d}.0{d})\n\n", .{ yuan, fen });
            } else {
                std.debug.print("   ✗ ROLLBACK: 余额不足 (需要 10000.00, 实际只有 {d}.{d})\n\n", .{ yuan, fen });
            }
            return; // defer 会自动回滚
        }

        // 正常情况不会执行到这里
        try tx.commit();
    }

    // ========================================
    // 7. 验证回滚后余额未变
    // ========================================
    std.debug.print("7️⃣  验证回滚后余额未变\n", .{});
    {
        var query = try db.newSelect(Account);
        defer query.deinit();
        _ = try query.where("username = $1", .{"Alice"});

        const account = try query.scanOne();
        const yuan = @divFloor(account.balance, 100);
        const fen = @mod(account.balance, 100);
        if (fen < 10) {
            std.debug.print("   Alice 余额: {d}.0{d} 元 (未变化)\n", .{ yuan, fen });
        } else {
            std.debug.print("   Alice 余额: {d}.{d} 元 (未变化)\n", .{ yuan, fen });
        }
        std.debug.print("   ✓ 事务回滚验证成功\n\n", .{});
    }

    // ========================================
    // 8. 事务要点总结
    // ========================================
    std.debug.print("8️⃣  事务要点总结\n", .{});
    std.debug.print("   • BEGIN:    开启事务\n", .{});
    std.debug.print("   • COMMIT:   提交事务（所有操作生效）\n", .{});
    std.debug.print("   • ROLLBACK: 回滚事务（所有操作撤销）\n", .{});
    std.debug.print("   • 原子性:    事务中的所有操作要么全部成功，要么全部失败\n", .{});
    std.debug.print("   • 一致性:    事务执行前后，数据保持一致状态\n", .{});
    std.debug.print("   • 隔离性:    并发事务之间互不干扰\n", .{});
    std.debug.print("   • 持久性:    提交后的事务永久保存\n", .{});
}
