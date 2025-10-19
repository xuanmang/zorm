const std = @import("std");
const zorm = @import("zorm");

// 用户模型
const User = struct {
    id: i64,
    username: []const u8,
    email: []const u8,
    age: i32,
    status: []const u8,
    is_active: bool,
    created_at: i64,

    pub const table_name = "users";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM CREATE INDEX 示例 ===\n\n", .{});

    // 示例 1: 简单索引
    std.debug.print("示例 1: 简单索引\n", .{});
    std.debug.print("------------------------\n", .{});
    {
        const db_mod = @import("zorm").core;
        const DBType = db_mod.DB(.postgresql);

        var mock_db: DBType = undefined;
        mock_db.allocator = allocator;

        var idx = try mock_db.newCreateIndex(User);
        defer idx.deinit();

        _ = idx.index("idx_users_email");
        _ = try idx.column("email");

        const sql = try idx.build();
        defer allocator.free(sql);

        std.debug.print("SQL: {s}\n", .{sql});
        std.debug.print("说明: 为 email 列创建简单索引,加速 email 查询\n\n", .{});
    }

    // 示例 2: 复合索引
    std.debug.print("示例 2: 复合索引（多列）\n", .{});
    std.debug.print("------------------------\n", .{});
    {
        const db_mod = @import("zorm").core;
        const DBType = db_mod.DB(.postgresql);

        var mock_db: DBType = undefined;
        mock_db.allocator = allocator;

        var idx = try mock_db.newCreateIndex(User);
        defer idx.deinit();

        _ = idx.index("idx_users_status_created");
        _ = try idx.column("status");
        _ = try idx.column("created_at");

        const sql = try idx.build();
        defer allocator.free(sql);

        std.debug.print("SQL: {s}\n", .{sql});
        std.debug.print("说明: 为 status 和 created_at 创建复合索引\n", .{});
        std.debug.print("     适用于同时按这两列查询的场景（最左前缀原则）\n\n", .{});
    }

    // 示例 3: 唯一索引
    std.debug.print("示例 3: 唯一索引\n", .{});
    std.debug.print("------------------------\n", .{});
    {
        const db_mod = @import("zorm").core;
        const DBType = db_mod.DB(.postgresql);

        var mock_db: DBType = undefined;
        mock_db.allocator = allocator;

        var idx = try mock_db.newCreateIndex(User);
        defer idx.deinit();

        _ = idx.index("idx_users_username_unique");
        _ = try idx.column("username");
        _ = idx.unique();

        const sql = try idx.build();
        defer allocator.free(sql);

        std.debug.print("SQL: {s}\n", .{sql});
        std.debug.print("说明: 创建唯一索引,强制 username 列值唯一\n\n", .{});
    }

    // 示例 4: IF NOT EXISTS 子句
    std.debug.print("示例 4: IF NOT EXISTS 子句\n", .{});
    std.debug.print("------------------------\n", .{});
    {
        const db_mod = @import("zorm").core;
        const DBType = db_mod.DB(.postgresql);

        var mock_db: DBType = undefined;
        mock_db.allocator = allocator;

        var idx = try mock_db.newCreateIndex(User);
        defer idx.deinit();

        _ = idx.index("idx_users_email");
        _ = try idx.column("email");
        _ = idx.ifNotExists();

        const sql = try idx.build();
        defer allocator.free(sql);

        std.debug.print("SQL: {s}\n", .{sql});
        std.debug.print("说明: 使用 IF NOT EXISTS 避免索引已存在时报错\n\n", .{});
    }

    // 示例 5: 表达式索引
    std.debug.print("示例 5: 表达式索引\n", .{});
    std.debug.print("------------------------\n", .{});
    {
        const db_mod = @import("zorm").core;
        const DBType = db_mod.DB(.postgresql);

        var mock_db: DBType = undefined;
        mock_db.allocator = allocator;

        var idx = try mock_db.newCreateIndex(User);
        defer idx.deinit();

        _ = idx.index("idx_users_email_lower");
        _ = try idx.column("LOWER(email)");

        const sql = try idx.build();
        defer allocator.free(sql);

        std.debug.print("SQL: {s}\n", .{sql});
        std.debug.print("说明: 索引 LOWER(email) 表达式,用于大小写不敏感搜索\n\n", .{});
    }

    // 示例 6: 部分索引（WHERE 子句）
    std.debug.print("示例 6: 部分索引（WHERE 子句）\n", .{});
    std.debug.print("------------------------\n", .{});
    {
        const db_mod = @import("zorm").core;
        const DBType = db_mod.DB(.postgresql);

        var mock_db: DBType = undefined;
        mock_db.allocator = allocator;

        var idx = try mock_db.newCreateIndex(User);
        defer idx.deinit();

        _ = idx.index("idx_users_active_email");
        _ = try idx.column("email");
        _ = idx.where("is_active = true");

        const sql = try idx.build();
        defer allocator.free(sql);

        std.debug.print("SQL: {s}\n", .{sql});
        std.debug.print("说明: 部分索引,只索引 is_active = true 的行\n", .{});
        std.debug.print("     减小索引大小,提升查询性能\n\n", .{});
    }

    // 示例 7: 完整链式调用
    std.debug.print("示例 7: 完整链式调用\n", .{});
    std.debug.print("------------------------\n", .{});
    {
        const db_mod = @import("zorm").core;
        const DBType = db_mod.DB(.postgresql);

        var mock_db: DBType = undefined;
        mock_db.allocator = allocator;

        var idx = try mock_db.newCreateIndex(User);
        defer idx.deinit();

        _ = idx
            .index("idx_users_active_status")
            .unique()
            .ifNotExists();
        _ = try idx.column("status");
        _ = try idx.column("created_at");
        _ = idx.where("is_active = true");

        const sql = try idx.build();
        defer allocator.free(sql);

        std.debug.print("SQL: {s}\n", .{sql});
        std.debug.print("说明: 组合多个功能:\n", .{});
        std.debug.print("     - UNIQUE: 唯一索引\n", .{});
        std.debug.print("     - IF NOT EXISTS: 避免重复创建\n", .{});
        std.debug.print("     - 复合索引: status + created_at\n", .{});
        std.debug.print("     - WHERE: 部分索引,只索引活跃用户\n\n", .{});
    }

    std.debug.print("=== 所有示例完成 ===\n", .{});
}
