//! UPDATE 查询构建器基本使用示例
//!
//! 本示例演示了 ZORM UpdateQuery 的各种用法，包括：
//! - 基本 UPDATE 操作
//! - WHERE 条件组合
//! - RETURNING 子句使用
//! - 链式调用语法
//! - 最佳实践

const std = @import("std");
const zorm = @import("zorm");

// 定义用户模型
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: u32,
    updated_at: i64,

    pub const table_name = "users";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM UpdateQuery 示例 ===\n\n", .{});

    // ============================================
    // 示例 1: 基本 UPDATE 操作
    // ============================================
    std.debug.print("示例 1: 基本 UPDATE\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("更新单个字段:\n", .{});
    std.debug.print("  UPDATE users SET name = $1 WHERE email = $2\n", .{});
    std.debug.print("  参数: {{\"Alice\", \"alice@example.com\"}}\n\n", .{});

    // 代码示例（需要数据库连接时才能执行）:
    // var update = try db.newUpdate(User);
    // defer update.deinit();
    //
    // const result = try update
    //     .set("name = $1", .{"Alice"})
    //     .where("email = $2", .{"alice@example.com"})
    //     .exec();
    //
    // std.debug.print("更新了 {} 行\n", .{result.rows_affected});

    // ============================================
    // 示例 2: 更新多个字段
    // ============================================
    std.debug.print("示例 2: 更新多个字段\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("UPDATE users SET name = $1, age = $2, updated_at = $3\n", .{});
    std.debug.print("WHERE email = $4\n\n", .{});

    // 代码示例:
    // const timestamp = std.time.timestamp();
    // var update = try db.newUpdate(User);
    // defer update.deinit();
    //
    // const result = try update
    //     .set("name = $1, age = $2, updated_at = $3", .{"Bob", 30, timestamp})
    //     .where("email = $4", .{"bob@example.com"})
    //     .exec();

    // ============================================
    // 示例 3: 使用 SQL 表达式
    // ============================================
    std.debug.print("示例 3: 使用 SQL 表达式\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("递增计数器:\n", .{});
    std.debug.print("  UPDATE users SET age = age + 1, updated_at = $1\n", .{});
    std.debug.print("  WHERE email = $2\n\n", .{});

    // 代码示例:
    // const timestamp = std.time.timestamp();
    // var update = try db.newUpdate(User);
    // defer update.deinit();
    //
    // const result = try update
    //     .set("age = age + 1, updated_at = $1", .{timestamp})
    //     .where("email = $2", .{"charlie@example.com"})
    //     .exec();

    // ============================================
    // 示例 4: WHERE 条件组合 (AND)
    // ============================================
    std.debug.print("示例 4: WHERE 条件组合 (AND)\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("UPDATE users SET name = $1\n", .{});
    std.debug.print("WHERE email = $2 AND age > $3\n\n", .{});

    // 代码示例:
    // var update = try db.newUpdate(User);
    // defer update.deinit();
    //
    // const result = try update
    //     .set("name = $1", .{"David"})
    //     .where("email = $2", .{"david@example.com"})
    //     .where("age > $3", .{25})
    //     .exec();

    // ============================================
    // 示例 5: WHERE 条件组合 (OR)
    // ============================================
    std.debug.print("示例 5: WHERE 条件组合 (OR)\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("UPDATE users SET updated_at = $1\n", .{});
    std.debug.print("WHERE email = $2 OR email = $3\n\n", .{});

    // 代码示例:
    // const timestamp = std.time.timestamp();
    // var update = try db.newUpdate(User);
    // defer update.deinit();
    //
    // const result = try update
    //     .set("updated_at = $1", .{timestamp})
    //     .where("email = $2", .{"eve@example.com"})
    //     .whereOr("email = $3", .{"frank@example.com"})
    //     .exec();

    // ============================================
    // 示例 6: RETURNING 子句（PostgreSQL）
    // ============================================
    std.debug.print("示例 6: RETURNING 子句\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("UPDATE users SET age = $1\n", .{});
    std.debug.print("WHERE email = $2\n", .{});
    std.debug.print("RETURNING *\n\n", .{});

    // 代码示例（仅 PostgreSQL）:
    // var update = try db.newUpdate(User);
    // defer update.deinit();
    //
    // var updated_users = std.ArrayList(User){};
    // defer updated_users.deinit(allocator);
    //
    // try update
    //     .set("age = $1", .{35})
    //     .where("email = $2", .{"grace@example.com"})
    //     .setReturning(&.{"*"})
    //     .execReturning(&updated_users);
    //
    // for (updated_users.items) |user| {
    //     std.debug.print("更新后: ID={}, Name={s}, Age={}\n",
    //         .{user.id, user.name, user.age});
    // }

    // ============================================
    // 示例 7: RETURNING 特定列
    // ============================================
    std.debug.print("示例 7: RETURNING 特定列\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("UPDATE users SET name = $1, updated_at = $2\n", .{});
    std.debug.print("WHERE email = $3\n", .{});
    std.debug.print("RETURNING id, updated_at\n\n", .{});

    // 代码示例:
    // const timestamp = std.time.timestamp();
    // var update = try db.newUpdate(User);
    // defer update.deinit();
    //
    // var updated_users = std.ArrayList(User){};
    // defer updated_users.deinit(allocator);
    //
    // try update
    //     .set("name = $1, updated_at = $2", .{"Henry", timestamp})
    //     .where("email = $3", .{"henry@example.com"})
    //     .setReturning(&.{"id", "updated_at"})
    //     .execReturning(&updated_users);

    // ============================================
    // 示例 8: 批量更新（WHERE IN）
    // ============================================
    std.debug.print("示例 8: 批量更新\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("UPDATE users SET updated_at = $1\n", .{});
    std.debug.print("WHERE email IN ($2, $3, $4)\n\n", .{});

    // 代码示例:
    // const timestamp = std.time.timestamp();
    // var update = try db.newUpdate(User);
    // defer update.deinit();
    //
    // const result = try update
    //     .set("updated_at = $1", .{timestamp})
    //     .where("email IN ($2, $3, $4)",
    //         .{"user1@example.com", "user2@example.com", "user3@example.com"})
    //     .exec();

    // ============================================
    // 最佳实践
    // ============================================
    std.debug.print("最佳实践:\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("1. 总是使用 WHERE 条件，避免误更新所有行\n", .{});
    std.debug.print("2. 使用参数绑定防止 SQL 注入\n", .{});
    std.debug.print("3. 使用 RETURNING 避免额外的 SELECT 查询\n", .{});
    std.debug.print("4. 在事务中执行关键更新操作\n", .{});
    std.debug.print("5. 总是调用 defer query.deinit() 释放资源\n", .{});
    std.debug.print("6. 使用 SQL 表达式实现原子性更新（如计数器递增）\n\n", .{});

    std.debug.print("示例程序结束\n", .{});
}
