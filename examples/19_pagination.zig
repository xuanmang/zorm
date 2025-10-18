//! 分页查询示例
//!
//! 学习目标:
//! - LIMIT/OFFSET 分页
//! - 游标分页（Cursor-based）
//! - 计算总页数
//! - 分页性能优化
//!
//! 对应功能需求: FR11
//! 难度: 中级

const std = @import("std");
const pg = @import("pg");
const config = @import("common/db_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZORM 示例 19: 分页查询 ===\n\n", .{});

    const db_config = config.Config.default();
    var pool = try pg.Pool.init(allocator, .{
        .size = 5,
        .connect = .{
            .host = db_config.host,
            .port = db_config.port,
        },
        .auth = .{
            .username = db_config.user,
            .password = db_config.password,
            .database = db_config.database,
        },
    });
    defer pool.deinit();

    var conn = try pool.acquire();
    defer conn.release();

    // 示例 1: LIMIT/OFFSET 分页
    try limitOffsetPagination(&conn);

    // 示例 2: 计算总页数
    try calculateTotalPages(&conn);

    // 示例 3: 游标分页（性能更好）
    try cursorPagination(&conn);

    std.debug.print("\n✅ 示例执行成功！\n", .{});
}

fn limitOffsetPagination(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 1: LIMIT/OFFSET 分页\n", .{});

    const page_size: i64 = 3;
    const page_number: i64 = 1; // 第 1 页（从 0 开始）

    // why: OFFSET 跳过前面的记录，LIMIT 限制返回数量
    const offset = page_number * page_size;

    var result = try conn.query(
        \\SELECT id, name, email
        \\FROM zorm_examples.users
        \\ORDER BY id
        \\LIMIT $1 OFFSET $2
    ,
        .{ page_size, offset },
    );
    defer result.deinit();

    std.debug.print("  第 {d} 页（每页 {d} 条）:\n", .{ page_number + 1, page_size });
    var count: usize = 0;
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const name = row.get([]const u8, 1);
        const email = row.get([]const u8, 2);

        std.debug.print("    [{d}] {s} <{s}>\n", .{ id, name, email });
        count += 1;
    }

    if (count == 0) {
        std.debug.print("    （本页无数据）\n", .{});
    }

    std.debug.print("\n", .{});
}

fn calculateTotalPages(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 2: 计算总页数\n", .{});

    const page_size: i64 = 5;

    // why: 先查询总记录数
    var count_opt = try conn.row(
        "SELECT COUNT(*) FROM zorm_examples.users",
        .{},
    );

    if (count_opt) |*count_result| {
        defer count_result.deinit() catch {};
        const total_records = count_result.get(i64, 0);

        // 计算总页数（向上取整）
        const total_pages = (total_records + page_size - 1) / page_size;

        std.debug.print("  分页统计:\n", .{});
        std.debug.print("    总记录数: {d}\n", .{total_records});
        std.debug.print("    每页大小: {d}\n", .{page_size});
        std.debug.print("    总页数: {d}\n", .{total_pages});

        // 遍历所有页
        var page: i64 = 0;
        while (page < total_pages) : (page += 1) {
            const offset = page * page_size;

            var result = try conn.query(
                \\SELECT id, name
                \\FROM zorm_examples.users
                \\ORDER BY id
                \\LIMIT $1 OFFSET $2
            ,
                .{ page_size, offset },
            );
            defer result.deinit();

            std.debug.print("  页 {d}/{d}:", .{ page + 1, total_pages });

            var page_count: usize = 0;
            while (try result.next()) |row| {
                const id = row.get(i64, 0);
                const name = row.get([]const u8, 1);

                if (page_count == 0) std.debug.print(" ", .{});
                std.debug.print("[{d}]{s}", .{ id, name });
                if (page_count < 4) std.debug.print(", ", .{});
                page_count += 1;
            }

            std.debug.print("\n", .{});
        }

        std.debug.print("\n", .{});
    }
}

fn cursorPagination(conn: *pg.Conn) !void {
    std.debug.print("📌 示例 3: 游标分页（性能优化）\n", .{});

    const page_size: i64 = 3;
    var last_id: ?i64 = null;

    std.debug.print("  使用游标分页（WHERE id > last_id）:\n", .{});

    var page_num: usize = 1;
    while (page_num <= 3) : (page_num += 1) {
        var result = if (last_id) |last|
            // why: 使用 WHERE id > last_id 代替 OFFSET，性能更好
            try conn.query(
                \\SELECT id, name, email
                \\FROM zorm_examples.users
                \\WHERE id > $1
                \\ORDER BY id
                \\LIMIT $2
            ,
                .{ last, page_size },
            )
        else
            try conn.query(
                \\SELECT id, name, email
                \\FROM zorm_examples.users
                \\ORDER BY id
                \\LIMIT $1
            ,
                .{page_size},
            );

        defer result.deinit();

        std.debug.print("  页 {d}:\n", .{page_num});

        var count: usize = 0;
        while (try result.next()) |row| {
            const id = row.get(i64, 0);
            const name = row.get([]const u8, 1);
            const email = row.get([]const u8, 2);

            std.debug.print("    [{d}] {s} <{s}>\n", .{ id, name, email });
            last_id = id; // 记录当前页最后一条的 ID
            count += 1;
        }

        if (count == 0) {
            std.debug.print("    （没有更多数据）\n", .{});
            break;
        }
    }

    std.debug.print("\n优势:\n", .{});
    std.debug.print("  - OFFSET 方式: 需要跳过前面所有记录（慢）\n", .{});
    std.debug.print("  - 游标方式: 直接从上次位置开始（快）\n", .{});
    std.debug.print("  - 适用于大数据集和无限滚动\n", .{});
}
