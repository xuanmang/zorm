//! DROP INDEX 查询构建器使用示例
//!
//! 本示例展示如何使用 ZORM 的 DropIndexQuery API 删除数据库索引

const std = @import("std");

// 模拟 ZORM API（等待真实实现集成）
const MockDB = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MockDB {
        return .{ .allocator = allocator };
    }
};

const User = struct {
    id: i64,
    username: []const u8,
    email: []const u8,
    age: u32,

    pub const table_name = "users";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM DROP INDEX 示例 ===\n\n", .{});

    // 示例 1: 基础 DROP INDEX
    std.debug.print("示例 1: 基础 DROP INDEX\n", .{});
    {
        var db = MockDB.init(allocator);
        _ = db;

        // 注意: 此处使用模拟代码展示 API 使用方式
        // 真实使用时应该是:
        // var drop_idx = try db.newDropIndex(User);
        // defer drop_idx.deinit();
        //
        // try drop_idx
        //     .index("idx_users_email")
        //     .exec();

        std.debug.print("  SQL: DROP INDEX idx_users_email\n", .{});
        std.debug.print("  用途: 删除 users 表的 email 索引\n\n", .{});
    }

    // 示例 2: IF EXISTS - 幂等性删除
    std.debug.print("示例 2: IF EXISTS - 幂等性删除\n", .{});
    {
        var db = MockDB.init(allocator);
        _ = db;

        // 真实使用:
        // var drop_idx = try db.newDropIndex(User);
        // defer drop_idx.deinit();
        //
        // try drop_idx
        //     .index("idx_users_email")
        //     .ifExists()
        //     .exec();

        std.debug.print("  SQL: DROP INDEX IF EXISTS idx_users_email\n", .{});
        std.debug.print("  用途: 如果索引存在则删除，不存在也不报错\n", .{});
        std.debug.print("  场景: 迁移脚本、重复执行的清理脚本\n\n", .{});
    }

    // 示例 3: CASCADE - 级联删除依赖对象
    std.debug.print("示例 3: CASCADE - 级联删除依赖对象\n", .{});
    {
        var db = MockDB.init(allocator);
        _ = db;

        // 真实使用:
        // var drop_idx = try db.newDropIndex(User);
        // defer drop_idx.deinit();
        //
        // try drop_idx
        //     .index("idx_users_email")
        //     .ifExists()
        //     .cascade()
        //     .exec();

        std.debug.print("  SQL: DROP INDEX IF EXISTS idx_users_email CASCADE\n", .{});
        std.debug.print("  用途: 删除索引及其所有依赖对象\n", .{});
        std.debug.print("  注意: PostgreSQL 中很少有对象依赖索引，此选项较少使用\n\n", .{});
    }

    // 示例 4: 链式调用
    std.debug.print("示例 4: 链式调用\n", .{});
    {
        var db = MockDB.init(allocator);
        _ = db;

        std.debug.print("  方式 1: 分步调用\n", .{});
        std.debug.print("    var drop_idx = try db.newDropIndex(User);\n", .{});
        std.debug.print("    defer drop_idx.deinit();\n", .{});
        std.debug.print("    drop_idx.index(\"idx_users_email\");\n", .{});
        std.debug.print("    drop_idx.ifExists();\n", .{});
        std.debug.print("    try drop_idx.exec();\n\n", .{});

        std.debug.print("  方式 2: 链式调用\n", .{});
        std.debug.print("    var drop_idx = try db.newDropIndex(User);\n", .{});
        std.debug.print("    defer drop_idx.deinit();\n", .{});
        std.debug.print("    try drop_idx.index(\"idx_users_email\").ifExists().exec();\n\n", .{});
    }

    // 示例 5: 仅构建 SQL（不执行）
    std.debug.print("示例 5: 仅构建 SQL（不执行）\n", .{});
    {
        var db = MockDB.init(allocator);
        _ = db;

        // 真实使用:
        // var drop_idx = try db.newDropIndex(User);
        // defer drop_idx.deinit();
        //
        // const sql = try drop_idx
        //     .index("idx_users_email")
        //     .ifExists()
        //     .build();
        // defer allocator.free(sql);
        //
        // std.debug.print("生成的 SQL: {s}\n", .{sql});

        std.debug.print("  用途: 预览 SQL 语句，用于调试或日志记录\n", .{});
        std.debug.print("  注意: build() 返回的字符串需要手动释放\n\n", .{});
    }

    std.debug.print("=== 示例完成 ===\n", .{});
}
