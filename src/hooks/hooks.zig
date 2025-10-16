//! Hooks - 查询生命周期钩子
//!
//! 提供查询执行前后的钩子机制,支持:
//! - 查询日志记录
//! - 查询性能监控
//! - 查询修改和验证
//! - 自定义业务逻辑注入

const std = @import("std");

/// 查询类型
pub const QueryType = enum {
    select,
    insert,
    update,
    delete,
    create_table,
    drop_table,
    raw,
};

/// 查询上下文
pub const QueryContext = struct {
    query_type: QueryType,
    query_string: []const u8,
    args: []const []const u8,
    start_time: i64,
    error_msg: ?[]const u8 = null,
};

/// 查询钩子接口
pub const QueryHook = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        before_query: ?*const fn (ptr: *anyopaque, ctx: *QueryContext) anyerror!void,
        after_query: ?*const fn (ptr: *anyopaque, ctx: *QueryContext) anyerror!void,
    };

    pub fn beforeQuery(self: *QueryHook, ctx: *QueryContext) !void {
        if (self.vtable.before_query) |func| {
            return func(self.ptr, ctx);
        }
    }

    pub fn afterQuery(self: *QueryHook, ctx: *QueryContext) !void {
        if (self.vtable.after_query) |func| {
            return func(self.ptr, ctx);
        }
    }
};

/// 简单的日志钩子实现
pub const LoggingHook = struct {
    enabled: bool = true,

    pub fn init() LoggingHook {
        return .{ .enabled = true };
    }

    pub fn hook(self: *LoggingHook) QueryHook {
        return .{
            .ptr = self,
            .vtable = &.{
                .before_query = beforeQueryImpl,
                .after_query = afterQueryImpl,
            },
        };
    }

    fn beforeQueryImpl(ptr: *anyopaque, ctx: *QueryContext) !void {
        const self: *LoggingHook = @ptrCast(@alignCast(ptr));
        if (!self.enabled) return;

        std.debug.print("[ZORM] Query: {s}\n", .{ctx.query_string});
    }

    fn afterQueryImpl(ptr: *anyopaque, ctx: *QueryContext) !void {
        const self: *LoggingHook = @ptrCast(@alignCast(ptr));
        if (!self.enabled) return;

        const end_time = std.time.milliTimestamp();
        const duration = end_time - ctx.start_time;

        if (ctx.error_msg) |err| {
            std.debug.print("[ZORM] Query failed: {s} (took {d}ms)\n", .{ err, duration });
        } else {
            std.debug.print("[ZORM] Query completed (took {d}ms)\n", .{duration});
        }
    }
};

test "logging hook" {
    var logging_hook = LoggingHook.init();
    var hook = logging_hook.hook();

    var ctx = QueryContext{
        .query_type = .select,
        .query_string = "SELECT * FROM users",
        .args = &.{},
        .start_time = std.time.milliTimestamp(),
    };

    try hook.beforeQuery(&ctx);
    try hook.afterQuery(&ctx);
}
