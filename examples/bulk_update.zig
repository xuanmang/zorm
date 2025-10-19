// examples/bulk_update.zig
// 演示批量 UPDATE 功能

const std = @import("std");
const zorm = @import("zorm");

// 用户模型
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    status: []const u8,
    age: i32,
    verified: bool,
    updated_at: i64,

    pub const table_name = "users";
};

// 文章模型
const Post = struct {
    id: i64,
    user_id: i64,
    title: []const u8,
    published: bool,

    pub const table_name = "posts";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    _ = allocator; // 示例代码，allocator 未实际使用

    std.debug.print("\n=== ZORM 批量 UPDATE 示例 ===\n\n", .{});

    // 示例 1: 使用 whereIn() 批量更新多行
    {
        std.debug.print("【示例 1】批量更新用户状态 (WHERE IN)\n", .{});

        // 模拟连接（实际使用时需要真实的数据库连接）
        // var db = try DB.init(allocator, conn, .postgresql);
        // defer db.deinit();

        // 要更新的用户 ID 列表
        const user_ids = [_]i64{ 1, 2, 3, 5, 8 };
        _ = user_ids;

        // 创建批量更新查询
        // var update = try db.newUpdate(User);
        // defer update.deinit();
        //
        // const result = try update
        //     .set("status = ?", .{"verified"})
        //     .set("verified = ?", .{true})
        //     .set("updated_at = ?", .{std.time.timestamp()})
        //     .whereIn("id", &user_ids)
        //     .exec();

        std.debug.print("  SQL: UPDATE users SET status = $1, verified = $2, updated_at = $3\n", .{});
        std.debug.print("       WHERE id IN ($4, $5, $6, $7, $8)\n", .{});
        std.debug.print("  参数: [\"verified\", true, 1234567890, 1, 2, 3, 5, 8]\n", .{});
        // std.debug.print("  结果: 更新了 {} 行\n\n", .{result.rows_affected});
    }

    // 示例 2: 使用 whereNotIn() 批量排除
    {
        std.debug.print("【示例 2】更新除特定用户外的所有用户\n", .{});

        const excluded_ids = [_]i64{ 99, 100 };
        _ = excluded_ids;

        std.debug.print("  SQL: UPDATE users SET status = $1\n", .{});
        std.debug.print("       WHERE id NOT IN ($2, $3)\n", .{});
        std.debug.print("  参数: [\"active\", 99, 100]\n\n", .{});
    }

    // 示例 3: 复杂 WHERE 条件组合
    {
        std.debug.print("【示例 3】复杂条件批量更新\n", .{});

        const target_ids = [_]i64{ 1, 2, 3 };
        _ = target_ids;

        std.debug.print("  SQL: UPDATE users SET verified = $1\n", .{});
        std.debug.print("       WHERE age > $2 AND id IN ($3, $4, $5)\n", .{});
        std.debug.print("  参数: [true, 18, 1, 2, 3]\n\n", .{});
    }

    // 示例 4: 使用子查询批量更新
    {
        std.debug.print("【示例 4】使用子查询更新用户\n", .{});

        // 创建子查询：查找所有发布过文章的用户
        // var subquery = try db.newSelect(Post);
        // defer subquery.deinit();
        // try subquery
        //     .column("DISTINCT user_id")
        //     .where("published = ?", .{true});
        //
        // // 使用子查询更新用户
        // var update = try db.newUpdate(User);
        // defer update.deinit();
        //
        // const result = try update
        //     .set("verified = ?", .{true})
        //     .set("updated_at = ?", .{std.time.timestamp()})
        //     .whereInSubquery("id", subquery)
        //     .exec();

        std.debug.print("  SQL: UPDATE users SET verified = $1, updated_at = $2\n", .{});
        std.debug.print("       WHERE id IN (SELECT DISTINCT user_id FROM posts WHERE published = $3)\n", .{});
        std.debug.print("  参数: [true, 1234567890, true]\n\n", .{});
    }

    // 示例 5: 批量更新 + RETURNING
    {
        std.debug.print("【示例 5】批量更新并返回更新后的数据\n", .{});

        const user_ids = [_]i64{ 1, 2, 3 };
        _ = user_ids;

        // var updated_users = std.ArrayList(User){};
        // defer updated_users.deinit(allocator);
        //
        // var update = try db.newUpdate(User);
        // defer update.deinit();
        //
        // try update
        //     .set("status = ?", .{"premium"})
        //     .whereIn("id", &user_ids)
        //     .setReturning(&.{ "id", "name", "status", "updated_at" })
        //     .execReturning(&updated_users);
        //
        // std.debug.print("  更新了 {} 个用户:\n", .{updated_users.items.len});
        // for (updated_users.items) |user| {
        //     std.debug.print("    - User {}: {} ({})\n", .{ user.id, user.name, user.status });
        // }

        std.debug.print("  SQL: UPDATE users SET status = $1\n", .{});
        std.debug.print("       WHERE id IN ($2, $3, $4)\n", .{});
        std.debug.print("       RETURNING id, name, status, updated_at\n", .{});
        std.debug.print("  参数: [\"premium\", 1, 2, 3]\n\n", .{});
    }

    // 示例 6: 性能对比 (批量 vs 循环)
    {
        std.debug.print("【示例 6】性能对比：批量更新 vs 循环单行更新\n", .{});

        const user_ids = [_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
        _ = user_ids;

        // ❌ 低效方式：循环单行更新
        std.debug.print("  ❌ 低效方式 (循环 10 次):\n", .{});
        std.debug.print("     for (user_ids) |id| {{\n", .{});
        std.debug.print("       UPDATE users SET status = $1 WHERE id = $2\n", .{});
        std.debug.print("     }}\n", .{});
        std.debug.print("     → 10 次数据库往返，慢！\n\n", .{});

        // ✅ 高效方式：批量更新
        std.debug.print("  ✅ 高效方式 (单次查询):\n", .{});
        std.debug.print("     UPDATE users SET status = $1\n", .{});
        std.debug.print("     WHERE id IN ($2, $3, ..., $11)\n", .{});
        std.debug.print("     → 1 次数据库往返，快 10-100 倍！\n\n", .{});
    }

    // 示例 7: 多个 whereIn() 组合
    {
        std.debug.print("【示例 7】多个 whereIn() 条件组合\n", .{});

        const user_ids = [_]i64{ 1, 2, 3 };
        const age_values = [_]i32{ 18, 25, 30 };
        _ = user_ids;
        _ = age_values;

        std.debug.print("  SQL: UPDATE users SET status = $1\n", .{});
        std.debug.print("       WHERE id IN ($2, $3, $4) AND age IN ($5, $6, $7)\n", .{});
        std.debug.print("  参数: [\"active\", 1, 2, 3, 18, 25, 30]\n\n", .{});
    }

    // 最佳实践建议
    {
        std.debug.print("【最佳实践】\n", .{});
        std.debug.print("  1. 使用批量更新代替循环，性能提升 10-100 倍\n", .{});
        std.debug.print("  2. WHERE IN 数组不宜过大 (建议 < 1000 个元素)\n", .{});
        std.debug.print("  3. 对于超大数组，考虑分批更新\n", .{});
        std.debug.print("  4. 结合 RETURNING 避免额外的 SELECT 查询\n", .{});
        std.debug.print("  5. 使用子查询动态确定更新目标\n\n", .{});
    }

    std.debug.print("=== 示例结束 ===\n\n", .{});
}
