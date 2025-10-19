//! 事务隔离级别示例 (Story 2.5)
//!
//! 演示如何使用不同的事务隔离级别:
//! - 默认隔离级别 (READ COMMITTED)
//! - 显式设置 SERIALIZABLE
//! - 显式设置 REPEATABLE READ
//!
//! 编译:
//!   zig build-exe examples/transaction_isolation.zig
//!
//! 运行:
//!   ./transaction_isolation

const std = @import("std");
const zorm = @import("zorm");

const User = struct {
    id: i64,
    name: []const u8,
    balance: i64,

    pub const table_name = "users";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== ZORM 事务隔离级别示例 ===\n\n", .{});

    // ============================================
    // 示例 1: 默认隔离级别 (不指定)
    // ============================================
    std.debug.print("示例 1: 默认隔离级别 (READ COMMITTED)\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 创建事务时不指定 isolation_level
    // PostgreSQL 将使用默认级别: READ COMMITTED
    const default_opts = zorm.TxOptions{};

    std.debug.print("TxOptions: {{ .isolation_level = null }}\n", .{});
    std.debug.print("PostgreSQL 将使用默认级别: READ COMMITTED\n", .{});
    std.debug.print("特性: 查询只能看到事务开始前已提交的数据\n", .{});
    std.debug.print("适用场景: 大多数 OLTP 应用,高并发场景\n", .{});
    std.debug.print("\n");

    // 伪代码示例 (需要真实数据库连接)
    std.debug.print("伪代码:\n", .{});
    std.debug.print("  var tx = try db.beginTx(default_opts);\n", .{});
    std.debug.print("  defer tx.deinit();\n", .{});
    std.debug.print("  errdefer tx.rollback() catch {{}};\n", .{});
    std.debug.print("\n  // 执行业务逻辑...\n", .{});
    std.debug.print("  try tx.commit();\n", .{});
    std.debug.print("\n");

    // ============================================
    // 示例 2: SERIALIZABLE 隔离级别
    // ============================================
    std.debug.print("示例 2: SERIALIZABLE 隔离级别\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const serializable_opts = zorm.TxOptions{
        .isolation_level = .serializable,
    };

    std.debug.print("TxOptions: {{ .isolation_level = .serializable }}\n", .{});
    std.debug.print("SQL: SET TRANSACTION ISOLATION LEVEL SERIALIZABLE\n", .{});
    std.debug.print("特性: 最高隔离级别,完全避免并发异常\n", .{});
    std.debug.print("适用场景: 金融系统、关键业务逻辑\n", .{});
    std.debug.print("注意: 可能导致事务串行化错误,需要重试逻辑\n", .{});
    std.debug.print("\n");

    std.debug.print("伪代码:\n", .{});
    std.debug.print("  var tx = try db.beginTx(serializable_opts);\n", .{});
    std.debug.print("  defer tx.deinit();\n", .{});
    std.debug.print("  errdefer tx.rollback() catch {{}};\n", .{});
    std.debug.print("\n  // 金融转账逻辑 (需要完全隔离)\n", .{});
    std.debug.print("  var from_user = try tx.newSelect(User)\n", .{});
    std.debug.print("      .where(\"id = ?\", .{{from_id}})\n", .{});
    std.debug.print("      .scanOne();\n", .{});
    std.debug.print("\n  var to_user = try tx.newSelect(User)\n", .{});
    std.debug.print("      .where(\"id = ?\", .{{to_id}})\n", .{});
    std.debug.print("      .scanOne();\n", .{});
    std.debug.print("\n  // 更新余额...\n", .{});
    std.debug.print("  try tx.commit();\n", .{});
    std.debug.print("\n");

    // ============================================
    // 示例 3: REPEATABLE READ 隔离级别
    // ============================================
    std.debug.print("示例 3: REPEATABLE READ 隔离级别\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const repeatable_read_opts = zorm.TxOptions{
        .isolation_level = .repeatable_read,
    };

    std.debug.print("TxOptions: {{ .isolation_level = .repeatable_read }}\n", .{});
    std.debug.print("SQL: SET TRANSACTION ISOLATION LEVEL REPEATABLE READ\n", .{});
    std.debug.print("特性: 事务内的查询看到一致性快照\n", .{});
    std.debug.print("适用场景: 需要一致性读的报表或分析\n", .{});
    std.debug.print("性能: 中等开销,平衡一致性和并发性\n", .{});
    std.debug.print("\n");

    std.debug.print("伪代码:\n", .{});
    std.debug.print("  var tx = try db.beginTx(repeatable_read_opts);\n", .{});
    std.debug.print("  defer tx.deinit();\n", .{});
    std.debug.print("  errdefer tx.rollback() catch {{}};\n", .{});
    std.debug.print("\n  // 生成报表 (需要一致性快照)\n", .{});
    std.debug.print("  var users = std.ArrayList(User).init(allocator);\n", .{});
    std.debug.print("  defer users.deinit();\n", .{});
    std.debug.print("\n  var query = try tx.newSelect(User);\n", .{});
    std.debug.print("  defer query.deinit();\n", .{});
    std.debug.print("  try query.scan(&users);\n", .{});
    std.debug.print("\n  // 多次查询看到相同的数据快照...\n", .{});
    std.debug.print("  try tx.commit();\n", .{});
    std.debug.print("\n");

    // ============================================
    // 示例 4: 完整配置 (隔离级别 + 其他选项)
    // ============================================
    std.debug.print("示例 4: 完整事务配置\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const full_opts = zorm.TxOptions{
        .isolation_level = .serializable,
        .read_only = false,
        .timeout = 5000, // 5 秒超时
    };

    std.debug.print("TxOptions: {{\n", .{});
    std.debug.print("  .isolation_level = .serializable,\n", .{});
    std.debug.print("  .read_only = false,\n", .{});
    std.debug.print("  .timeout = 5000,\n", .{});
    std.debug.print("}}\n", .{});
    std.debug.print("\n");

    // ============================================
    // 隔离级别选择建议
    // ============================================
    std.debug.print("\n=== 隔离级别选择建议 ===\n\n", .{});

    std.debug.print("1. READ COMMITTED (默认)\n", .{});
    std.debug.print("   ✓ 大多数 Web 应用\n", .{});
    std.debug.print("   ✓ 高并发 OLTP\n", .{});
    std.debug.print("   ✓ 性能优先场景\n", .{});
    std.debug.print("\n");

    std.debug.print("2. REPEATABLE READ\n", .{});
    std.debug.print("   ✓ 报表生成\n", .{});
    std.debug.print("   ✓ 数据分析\n", .{});
    std.debug.print("   ✓ 需要一致性快照的长事务\n", .{});
    std.debug.print("\n");

    std.debug.print("3. SERIALIZABLE\n", .{});
    std.debug.print("   ✓ 金融转账\n", .{});
    std.debug.print("   ✓ 库存扣减\n", .{});
    std.debug.print("   ✓ 关键业务逻辑\n", .{});
    std.debug.print("   ⚠ 需要重试逻辑处理串行化错误\n", .{});
    std.debug.print("\n");

    std.debug.print("4. READ UNCOMMITTED\n", .{});
    std.debug.print("   ⚠ PostgreSQL 不支持,会自动升级为 READ COMMITTED\n", .{});
    std.debug.print("   ⚠ 不推荐使用\n", .{});
    std.debug.print("\n");

    // ============================================
    // 性能权衡
    // ============================================
    std.debug.print("\n=== 性能权衡 ===\n\n", .{});

    std.debug.print("隔离级别越高,性能开销越大:\n", .{});
    std.debug.print("\n");
    std.debug.print("  READ COMMITTED    → 最低开销,最高并发\n", .{});
    std.debug.print("       ↓\n", .{});
    std.debug.print("  REPEATABLE READ   → 中等开销,一致性快照\n", .{});
    std.debug.print("       ↓\n", .{});
    std.debug.print("  SERIALIZABLE      → 最高开销,可能串行化冲突\n", .{});
    std.debug.print("\n");

    std.debug.print("建议:\n", .{});
    std.debug.print("- 默认使用 READ COMMITTED\n", .{});
    std.debug.print("- 仅在需要时提升隔离级别\n", .{});
    std.debug.print("- SERIALIZABLE 需要应用层重试逻辑\n", .{});
    std.debug.print("\n");

    // 避免未使用警告
    _ = allocator;
    _ = default_opts;
    _ = serializable_opts;
    _ = repeatable_read_opts;
    _ = full_opts;
}
