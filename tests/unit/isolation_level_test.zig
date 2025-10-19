//! 单元测试: 事务隔离级别 (Story 2.5)
//!
//! 测试覆盖:
//! - IsolationLevel 枚举定义
//! - toSQL() 转换函数
//! - TxOptions 默认值
//! - IsolationLevel 和 TxOptions 集成

const std = @import("std");
const zorm = @import("zorm");
const IsolationLevel = zorm.types.IsolationLevel;
const TxOptions = zorm.TxOptions;

// ============================================
// IsolationLevel 枚举测试
// ============================================

test "IsolationLevel: toSQL 转换 - read_uncommitted" {
    const level = IsolationLevel.read_uncommitted;
    const sql = level.toSQL();
    try std.testing.expectEqualStrings("READ UNCOMMITTED", sql);
}

test "IsolationLevel: toSQL 转换 - read_committed" {
    const level = IsolationLevel.read_committed;
    const sql = level.toSQL();
    try std.testing.expectEqualStrings("READ COMMITTED", sql);
}

test "IsolationLevel: toSQL 转换 - repeatable_read" {
    const level = IsolationLevel.repeatable_read;
    const sql = level.toSQL();
    try std.testing.expectEqualStrings("REPEATABLE READ", sql);
}

test "IsolationLevel: toSQL 转换 - serializable" {
    const level = IsolationLevel.serializable;
    const sql = level.toSQL();
    try std.testing.expectEqualStrings("SERIALIZABLE", sql);
}

test "IsolationLevel: 所有级别的 toSQL 转换" {
    const levels = [_]IsolationLevel{
        .read_uncommitted,
        .read_committed,
        .repeatable_read,
        .serializable,
    };

    const expected = [_][]const u8{
        "READ UNCOMMITTED",
        "READ COMMITTED",
        "REPEATABLE READ",
        "SERIALIZABLE",
    };

    for (levels, expected) |level, expect| {
        const sql = level.toSQL();
        try std.testing.expectEqualStrings(expect, sql);
    }
}

// ============================================
// TxOptions 测试
// ============================================

test "TxOptions: 默认值 - isolation_level 为 null" {
    const opts = TxOptions{};
    try std.testing.expectEqual(@as(?IsolationLevel, null), opts.isolation_level);
    try std.testing.expectEqual(false, opts.read_only);
    try std.testing.expectEqual(@as(u64, 0), opts.timeout);
}

test "TxOptions: 显式设置 read_committed" {
    const opts = TxOptions{
        .isolation_level = .read_committed,
    };
    try std.testing.expect(opts.isolation_level != null);
    try std.testing.expectEqual(IsolationLevel.read_committed, opts.isolation_level.?);
}

test "TxOptions: 显式设置 serializable" {
    const opts = TxOptions{
        .isolation_level = .serializable,
    };
    try std.testing.expect(opts.isolation_level != null);
    try std.testing.expectEqual(IsolationLevel.serializable, opts.isolation_level.?);
}

test "TxOptions: 显式设置 repeatable_read" {
    const opts = TxOptions{
        .isolation_level = .repeatable_read,
    };
    try std.testing.expect(opts.isolation_level != null);
    try std.testing.expectEqual(IsolationLevel.repeatable_read, opts.isolation_level.?);
}

test "TxOptions: 完整配置" {
    const opts = TxOptions{
        .isolation_level = .serializable,
        .read_only = true,
        .timeout = 5000,
    };

    try std.testing.expect(opts.isolation_level != null);
    try std.testing.expectEqual(IsolationLevel.serializable, opts.isolation_level.?);
    try std.testing.expectEqual(true, opts.read_only);
    try std.testing.expectEqual(@as(u64, 5000), opts.timeout);
}

// ============================================
// 编译时测试
// ============================================

test "IsolationLevel: 编译时类型检查" {
    comptime {
        // 验证 IsolationLevel 是枚举类型
        const type_info = @typeInfo(IsolationLevel);
        try std.testing.expect(type_info == .@"enum");

        // 验证有 4 个枚举值
        try std.testing.expectEqual(4, type_info.@"enum".fields.len);
    }
}

test "IsolationLevel: comptime toSQL 调用" {
    comptime {
        const sql = IsolationLevel.serializable.toSQL();
        try std.testing.expectEqualStrings("SERIALIZABLE", sql);
    }
}
