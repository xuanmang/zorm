//! DELETE 查询构建器基本使用示例
//!
//! 本示例演示了 ZORM DeleteQuery 的各种用法，包括：
//! - 基本 DELETE 操作
//! - WHERE 条件组合
//! - 批量删除 (WHERE IN)
//! - RETURNING 子句使用 (审计日志场景)
//! - 强制 WHERE 安全检查
//! - 链式调用语法

const std = @import("std");
const zorm = @import("zorm");

// 定义用户模型
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: u32,
    status: []const u8,
    created_at: i64,

    pub const table_name = "users";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM DeleteQuery 示例 ===\n\n", .{});

    // ============================================
    // 示例 1: 基本 DELETE 操作
    // ============================================
    std.debug.print("示例 1: 基本 DELETE 操作\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("删除单行数据:\n", .{});
    std.debug.print("  DELETE FROM users WHERE id = $1\n", .{});
    std.debug.print("  参数: {{123}}\n\n", .{});

    // 代码示例（需要数据库连接时才能执行）:
    // var delete_query = try db.newDelete(User);
    // defer delete_query.deinit();
    //
    // const result = try delete_query
    //     .where("id = ?", .{123})
    //     .exec();
    //
    // std.debug.print("删除了 {d} 行\n", .{result.rows_affected});

    // ============================================
    // 示例 2: WHERE 条件组合 (AND)
    // ============================================
    std.debug.print("示例 2: WHERE 条件组合\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("删除满足多个条件的数据:\n", .{});
    std.debug.print("  DELETE FROM users WHERE status = $1 AND age < $2\n", .{});
    std.debug.print("  参数: {{\"inactive\", 18}}\n\n", .{});

    // 代码示例:
    // var delete_query = try db.newDelete(User);
    // defer delete_query.deinit();
    //
    // const result = try delete_query
    //     .where("status = ?", .{"inactive"})
    //     .where("age < ?", .{18})
    //     .exec();
    //
    // std.debug.print("删除了 {d} 行\n", .{result.rows_affected});

    // ============================================
    // 示例 3: WHERE 条件组合 (OR)
    // ============================================
    std.debug.print("示例 3: WHERE 条件组合 (OR)\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("删除满足任一条件的数据:\n", .{});
    std.debug.print("  DELETE FROM users WHERE status = $1 OR status = $2\n", .{});
    std.debug.print("  参数: {{\"inactive\", \"pending\"}}\n\n", .{});

    // 代码示例:
    // var delete_query = try db.newDelete(User);
    // defer delete_query.deinit();
    //
    // const result = try delete_query
    //     .where("status = ?", .{"inactive"})
    //     .whereOr("status = ?", .{"pending"})
    //     .exec();

    // ============================================
    // 示例 4: 批量删除 (WHERE IN)
    // ============================================
    std.debug.print("示例 4: 批量删除 (WHERE IN)\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("删除多个指定 ID 的用户:\n", .{});
    std.debug.print("  DELETE FROM users WHERE id IN ($1, $2, $3, $4, $5)\n", .{});
    std.debug.print("  参数: {{1, 2, 3, 5, 8}}\n\n", .{});

    // 代码示例:
    // const user_ids = [_]i64{ 1, 2, 3, 5, 8 };
    // var delete_query = try db.newDelete(User);
    // defer delete_query.deinit();
    //
    // const result = try delete_query
    //     .whereIn("id", &user_ids)
    //     .exec();
    //
    // std.debug.print("删除了 {d} 行\n", .{result.rows_affected});

    // ============================================
    // 示例 5: 批量排除 (WHERE NOT IN)
    // ============================================
    std.debug.print("示例 5: 批量排除 (WHERE NOT IN)\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("删除除了指定 ID 之外的用户:\n", .{});
    std.debug.print("  DELETE FROM users WHERE id NOT IN ($1, $2) AND status = $3\n", .{});
    std.debug.print("  参数: {{99, 100, \"inactive\"}}\n\n", .{});

    // 代码示例:
    // const protected_ids = [_]i64{ 99, 100 };
    // var delete_query = try db.newDelete(User);
    // defer delete_query.deinit();
    //
    // const result = try delete_query
    //     .whereNotIn("id", &protected_ids)
    //     .where("status = ?", .{"inactive"})
    //     .exec();

    // ============================================
    // 示例 6: RETURNING 子句 (审计日志场景)
    // ============================================
    std.debug.print("示例 6: RETURNING 子句 - 审计日志\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("删除并记录被删除的数据:\n", .{});
    std.debug.print("  DELETE FROM users WHERE status = $1 RETURNING *\n", .{});
    std.debug.print("  参数: {{\"inactive\"}}\n\n", .{});

    // 代码示例（仅 PostgreSQL 支持）:
    // var deleted_users = std.ArrayList(User){};
    // defer deleted_users.deinit(allocator);
    //
    // var delete_query = try db.newDelete(User);
    // defer delete_query.deinit();
    //
    // try delete_query
    //     .where("status = ?", .{"inactive"})
    //     .setReturning(&.{"*"})
    //     .execReturning(&deleted_users);
    //
    // // 记录被删除的用户（用于审计）
    // std.debug.print("删除了 {d} 个用户:\n", .{deleted_users.items.len});
    // for (deleted_users.items) |user| {
    //     std.debug.print("  - ID: {d}, Name: {s}, Email: {s}\n",
    //         .{user.id, user.name, user.email});
    // }

    // ============================================
    // 示例 7: RETURNING 指定列
    // ============================================
    std.debug.print("示例 7: RETURNING 指定列\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("删除并返回部分列:\n", .{});
    std.debug.print("  DELETE FROM users WHERE id = $1 RETURNING id, email\n", .{});
    std.debug.print("  参数: {{123}}\n\n", .{});

    // 代码示例:
    // var delete_query = try db.newDelete(User);
    // defer delete_query.deinit();
    //
    // try delete_query
    //     .where("id = ?", .{123})
    //     .setReturning(&.{"id", "email"});

    // ============================================
    // ⚠️ 安全提示：强制 WHERE 检查
    // ============================================
    std.debug.print("\n⚠️  安全提示：强制 WHERE 检查\n", .{});
    std.debug.print("====================================\n", .{});
    std.debug.print("ZORM 强制要求 DELETE 操作必须包含 WHERE 条件,\n", .{});
    std.debug.print("以防止意外删除所有数据。\n\n", .{});

    std.debug.print("❌ 错误示例 (无 WHERE 条件):\n", .{});
    std.debug.print("  var delete_query = try db.newDelete(User);\n", .{});
    std.debug.print("  const result = try delete_query.exec();\n", .{});
    std.debug.print("  // ↑ 错误: error.MissingWhereClause\n\n", .{});

    std.debug.print("✅ 如果确实需要删除所有行,请使用 Raw SQL:\n", .{});
    std.debug.print("  try db.exec(\"DELETE FROM users\", .{{}});\n\n", .{});

    // ============================================
    // 最佳实践总结
    // ============================================
    std.debug.print("\n=== 最佳实践 ===\n", .{});
    std.debug.print("--------------------\n", .{});
    std.debug.print("1. ✅ 总是使用 WHERE 条件,避免误删\n", .{});
    std.debug.print("2. ✅ 使用 RETURNING 记录审计日志\n", .{});
    std.debug.print("3. ✅ 批量删除使用 WHERE IN\n", .{});
    std.debug.print("4. ✅ 使用参数绑定防止 SQL 注入\n", .{});
    std.debug.print("5. ✅ 在事务中执行删除操作\n", .{});
    std.debug.print("6. ⚠️  删除操作不可逆,执行前务必确认\n", .{});
    std.debug.print("7. ⚠️  大批量删除应分批进行\n\n", .{});

    // ============================================
    // 常见使用模式
    // ============================================
    std.debug.print("=== 常见使用模式 ===\n", .{});
    std.debug.print("--------------------\n\n", .{});

    std.debug.print("模式 1: 软删除（推荐）\n", .{});
    std.debug.print("  使用 UPDATE 设置 deleted_at 字段，而不是真正删除:\n", .{});
    std.debug.print("  var update = try db.newUpdate(User);\n", .{});
    std.debug.print("  _ = try update.set(\"deleted_at = ?\", .{{timestamp}});\n", .{});
    std.debug.print("  _ = try update.where(\"id = ?\", .{{123}});\n\n", .{});

    std.debug.print("模式 2: 级联删除\n", .{});
    std.debug.print("  先删除关联数据，再删除主数据:\n", .{});
    std.debug.print("  const tx = try db.begin();\n", .{});
    std.debug.print("  errdefer tx.rollback() catch {{}};\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // 删除子记录\n", .{});
    std.debug.print("  var delete_posts = try db.newDelete(Post);\n", .{});
    std.debug.print("  _ = try delete_posts.where(\"user_id = ?\", .{{user_id}}).exec();\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // 删除主记录\n", .{});
    std.debug.print("  var delete_user = try db.newDelete(User);\n", .{});
    std.debug.print("  _ = try delete_user.where(\"id = ?\", .{{user_id}}).exec();\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  try tx.commit();\n\n", .{});

    std.debug.print("模式 3: 条件删除 + 审计日志\n", .{});
    std.debug.print("  删除过期数据并记录日志:\n", .{});
    std.debug.print("  var deleted_users = std.ArrayList(User){{}};\n", .{});
    std.debug.print("  defer deleted_users.deinit(allocator);\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  var delete_query = try db.newDelete(User);\n", .{});
    std.debug.print("  _ = try delete_query.where(\"created_at < ?\", .{{cutoff_date}});\n", .{});
    std.debug.print("  _ = delete_query.setReturning(&.{{\"*\"}});\n", .{});
    std.debug.print("  try delete_query.execReturning(&deleted_users);\n", .{});
    std.debug.print("  \n", .{});
    std.debug.print("  // 写入审计日志\n", .{});
    std.debug.print("  for (deleted_users.items) |user| {{\n", .{});
    std.debug.print("      try audit_log.write(\"Deleted user: {{}}\", .{{user.email}});\n", .{});
    std.debug.print("  }}\n\n", .{});

    std.debug.print("=== 示例完成 ===\n", .{});
}
