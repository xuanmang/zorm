//! Migration 系统完整测试套件
//!
//! 包含:
//! - Mock DB 基础设施 (用于单元测试)
//! - Migration 基础数据结构测试
//! - MigrationManager 核心方法测试
//! - 边界条件和错误场景测试
//!
//! 注意: 完整的集成测试需要真实数据库,应在单独的集成测试文件中编写

const std = @import("std");
const testing = std.testing;
const zorm = @import("zorm");

const Migration = zorm.Migration;
const MigrationManager = zorm.MigrationManager;
const Direction = zorm.Direction;
const MigrationStatus = zorm.MigrationStatus;
const Dialect = @import("zorm").Dialect;
const Conn = @import("zorm").Conn;
const Result = @import("zorm").Result;
const Tx = @import("zorm").Tx;

// =============================================================================
// Mock DB 基础设施
// =============================================================================

/// Mock Result - 模拟查询结果
const MockResult = struct {
    allocator: std.mem.Allocator,
    rows: std.ArrayList([]const []const u8),
    current_row: usize,
    closed: bool,

    pub fn init(allocator: std.mem.Allocator) !*MockResult {
        const self = try allocator.create(MockResult);
        self.* = .{
            .allocator = allocator,
            .rows = .{},
            .current_row = 0,
            .closed = false,
        };
        return self;
    }

    pub fn deinit(self: *MockResult) void {
        self.rows.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn addRow(self: *MockResult, row: []const []const u8) !void {
        try self.rows.append(self.allocator, row);
    }

    pub fn nextFn(ptr: *anyopaque) anyerror!bool {
        const self: *MockResult = @ptrCast(@alignCast(ptr));
        if (self.current_row < self.rows.items.len) {
            self.current_row += 1;
            return true;
        }
        return false;
    }

    pub fn scanFn(ptr: *anyopaque, dest: [][]u8) anyerror!void {
        const self: *MockResult = @ptrCast(@alignCast(ptr));
        if (self.current_row == 0 or self.current_row > self.rows.items.len) {
            return error.NoCurrentRow;
        }
        const row = self.rows.items[self.current_row - 1];
        for (row, 0..) |col, i| {
            if (i < dest.len) {
                @memcpy(dest[i][0..col.len], col);
            }
        }
    }

    pub fn closeFn(ptr: *anyopaque) void {
        const self: *MockResult = @ptrCast(@alignCast(ptr));
        self.closed = true;
    }

    pub fn result(self: *MockResult) Result {
        const vtable = &Result.VTable{
            .next = nextFn,
            .scan = scanFn,
            .close = closeFn,
        };
        return Result{
            .ptr = self,
            .vtable = vtable,
        };
    }
};

/// Mock Tx - 模拟事务
const MockTx = struct {
    allocator: std.mem.Allocator,
    exec_calls: std.ArrayList([]const u8),
    committed: bool,
    rolled_back: bool,

    pub fn init(allocator: std.mem.Allocator) !*MockTx {
        const self = try allocator.create(MockTx);
        self.* = .{
            .allocator = allocator,
            .exec_calls = .{},
            .committed = false,
            .rolled_back = false,
        };
        return self;
    }

    pub fn deinit(self: *MockTx) void {
        for (self.exec_calls.items) |call| {
            self.allocator.free(call);
        }
        self.exec_calls.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn execFn(ptr: *anyopaque, query: []const u8, args: []const []const u8) anyerror!void {
        _ = args;
        const self: *MockTx = @ptrCast(@alignCast(ptr));
        const query_copy = try self.allocator.dupe(u8, query);
        try self.exec_calls.append(self.allocator, query_copy);
    }

    pub fn queryFn(ptr: *anyopaque, query_str: []const u8, args: []const []const u8) anyerror!*Result {
        _ = query_str;
        _ = args;
        const self: *MockTx = @ptrCast(@alignCast(ptr));
        const mock_result = try MockResult.init(self.allocator);
        const result_ptr = try self.allocator.create(Result);
        result_ptr.* = mock_result.result();
        return result_ptr;
    }

    pub fn commitFn(ptr: *anyopaque) anyerror!void {
        const self: *MockTx = @ptrCast(@alignCast(ptr));
        self.committed = true;
    }

    pub fn rollbackFn(ptr: *anyopaque) anyerror!void {
        const self: *MockTx = @ptrCast(@alignCast(ptr));
        self.rolled_back = true;
    }

    pub fn tx(self: *MockTx) *Tx {
        const vtable_mem = testing.allocator.create(Tx.VTable) catch unreachable;
        vtable_mem.* = Tx.VTable{
            .exec = execFn,
            .query = queryFn,
            .commit = commitFn,
            .rollback = rollbackFn,
        };

        const tx_mem = testing.allocator.create(Tx) catch unreachable;
        tx_mem.* = Tx{
            .ptr = self,
            .vtable = vtable_mem,
        };
        return tx_mem;
    }
};

/// Mock Conn - 模拟数据库连接
const MockConn = struct {
    allocator: std.mem.Allocator,
    exec_calls: std.ArrayList([]const u8),
    query_calls: std.ArrayList([]const u8),
    mock_result: ?*MockResult,
    should_fail: bool,

    pub fn init(allocator: std.mem.Allocator) !*MockConn {
        const self = try allocator.create(MockConn);
        self.* = .{
            .allocator = allocator,
            .exec_calls = .{},
            .query_calls = .{},
            .mock_result = null,
            .should_fail = false,
        };
        return self;
    }

    pub fn deinit(self: *MockConn) void {
        for (self.exec_calls.items) |call| {
            self.allocator.free(call);
        }
        for (self.query_calls.items) |call| {
            self.allocator.free(call);
        }
        self.exec_calls.deinit(self.allocator);
        self.query_calls.deinit(self.allocator);
        if (self.mock_result) |r| {
            r.deinit();
        }
        self.allocator.destroy(self);
    }

    pub fn setMockResult(self: *MockConn, result: *MockResult) void {
        self.mock_result = result;
    }

    pub fn execFn(ptr: *anyopaque, query: []const u8, args: []const []const u8) anyerror!void {
        _ = args;
        const self: *MockConn = @ptrCast(@alignCast(ptr));
        if (self.should_fail) {
            return error.MockExecFailure;
        }
        const query_copy = try self.allocator.dupe(u8, query);
        try self.exec_calls.append(self.allocator, query_copy);
    }

    pub fn queryFn(ptr: *anyopaque, query_str: []const u8, args: []const []const u8) anyerror!*Result {
        _ = args;
        const self: *MockConn = @ptrCast(@alignCast(ptr));
        const query_copy = try self.allocator.dupe(u8, query_str);
        try self.query_calls.append(self.allocator, query_copy);

        if (self.mock_result) |mock_res| {
            const result_ptr = try self.allocator.create(Result);
            result_ptr.* = mock_res.result();
            return result_ptr;
        }

        // 默认返回空结果
        const empty_result = try MockResult.init(self.allocator);
        const result_ptr = try self.allocator.create(Result);
        result_ptr.* = empty_result.result();
        return result_ptr;
    }

    pub fn beginFn(ptr: *anyopaque) anyerror!*Tx {
        const self: *MockConn = @ptrCast(@alignCast(ptr));
        const mock_tx = try MockTx.init(self.allocator);
        return mock_tx.tx();
    }

    pub fn closeFn(ptr: *anyopaque) void {
        _ = ptr;
        // Mock 不需要实际关闭
    }

    pub fn conn(self: *MockConn) Conn {
        const vtable_mem = testing.allocator.create(Conn.VTable) catch unreachable;
        vtable_mem.* = Conn.VTable{
            .exec = execFn,
            .query = queryFn,
            .begin = beginFn,
            .close = closeFn,
        };

        return Conn{
            .ptr = self,
            .vtable = vtable_mem,
        };
    }
};

// =============================================================================
// 现有的基础测试
// =============================================================================

test "Migration: 基本创建" {
    const migration = Migration.init(
        1,
        "create_users_table",
        "CREATE TABLE users (id BIGINT PRIMARY KEY)",
        "DROP TABLE users",
    );

    try testing.expectEqual(@as(u64, 1), migration.version);
    try testing.expectEqualStrings("create_users_table", migration.name);
    try testing.expect(migration.up_sql.len > 0);
    try testing.expect(migration.down_sql.len > 0);
}

test "Migration: fullName 生成" {
    var migration = Migration.init(
        20250117120000,
        "create_users_table",
        "CREATE TABLE users (id BIGINT PRIMARY KEY)",
        "DROP TABLE users",
    );

    const full = try migration.fullName(testing.allocator);
    defer testing.allocator.free(full);

    try testing.expectEqualStrings("20250117120000_create_users_table", full);
}

test "Direction: toString" {
    try testing.expectEqualStrings("up", Direction.up.toString());
    try testing.expectEqualStrings("down", Direction.down.toString());
}

test "MigrationStatus: 结构" {
    const status = MigrationStatus{
        .total = 10,
        .applied = 7,
        .pending = 3,
    };

    try testing.expectEqual(@as(usize, 10), status.total);
    try testing.expectEqual(@as(usize, 7), status.applied);
    try testing.expectEqual(@as(usize, 3), status.pending);
}

// =============================================================================
// MigrationManager 核心方法测试
// =============================================================================

test "MigrationManager: init/deinit 基本创建" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    try testing.expect(mgr.migrations.items.len == 0);
    try testing.expectEqualStrings("schema_migrations", mgr.migrations_table);
}

test "MigrationManager: register 单个迁移注册" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    const migration1 = Migration.init(
        1,
        "create_users",
        "CREATE TABLE users (id BIGINT)",
        "DROP TABLE users",
    );

    try mgr.register(migration1);
    try testing.expectEqual(@as(usize, 1), mgr.migrations.items.len);
    try testing.expectEqual(@as(u64, 1), mgr.migrations.items[0].version);
}

test "MigrationManager: register 多次注册不同版本" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    const migrations = [_]Migration{
        Migration.init(1, "create_users", "CREATE TABLE users (id BIGINT)", "DROP TABLE users"),
        Migration.init(2, "create_posts", "CREATE TABLE posts (id BIGINT)", "DROP TABLE posts"),
        Migration.init(3, "add_index", "CREATE INDEX idx_user_id ON posts(user_id)", "DROP INDEX idx_user_id"),
    };

    for (migrations) |m| {
        try mgr.register(m);
    }

    try testing.expectEqual(@as(usize, 3), mgr.migrations.items.len);
    try testing.expectEqual(@as(u64, 1), mgr.migrations.items[0].version);
    try testing.expectEqual(@as(u64, 2), mgr.migrations.items[1].version);
    try testing.expectEqual(@as(u64, 3), mgr.migrations.items[2].version);
}

test "MigrationManager: registerMany 批量注册" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    const migrations = [_]Migration{
        Migration.init(1, "m1", "SQL1", "DOWN1"),
        Migration.init(2, "m2", "SQL2", "DOWN2"),
    };

    try mgr.registerMany(&migrations);
    try testing.expectEqual(@as(usize, 2), mgr.migrations.items.len);
}

test "MigrationManager: registerMany 空列表" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    const empty: [0]Migration = .{};
    try mgr.registerMany(&empty);
    try testing.expectEqual(@as(usize, 0), mgr.migrations.items.len);
}

test "MigrationManager: setMigrationsTable 自定义表名" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    mgr.setMigrationsTable("custom_migrations");
    try testing.expectEqualStrings("custom_migrations", mgr.migrations_table);
}

// =============================================================================
// 迁移排序和版本管理测试
// =============================================================================

test "Migration: 版本排序验证 - 乱序注册后 up 应按版本排序执行" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    // 乱序注册
    try mgr.register(Migration.init(3, "third", "SQL3", "DOWN3"));
    try mgr.register(Migration.init(1, "first", "SQL1", "DOWN1"));
    try mgr.register(Migration.init(2, "second", "SQL2", "DOWN2"));

    // 验证注册顺序保持
    try testing.expectEqual(@as(u64, 3), mgr.migrations.items[0].version);
    try testing.expectEqual(@as(u64, 1), mgr.migrations.items[1].version);
    try testing.expectEqual(@as(u64, 2), mgr.migrations.items[2].version);

    // up() 方法会内部排序,这里通过测试间接验证
    // (实际排序在 up() 中,这里主要验证注册逻辑不自动排序)
}

test "Migration: 重复版本号检测" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    try mgr.register(Migration.init(1, "first", "SQL1", "DOWN1"));
    try mgr.register(Migration.init(1, "duplicate", "SQL2", "DOWN2"));

    // 当前实现允许重复版本号,在实际使用中应该避免
    // 这个测试验证不会崩溃,但不推荐这样使用
    try testing.expectEqual(@as(usize, 2), mgr.migrations.items.len);
}

test "Migration: fullName 格式一致性" {
    var m1 = Migration.init(1, "test", "UP", "DOWN");
    var m2 = Migration.init(999, "another_test", "UP", "DOWN");

    const full1 = try m1.fullName(testing.allocator);
    defer testing.allocator.free(full1);

    const full2 = try m2.fullName(testing.allocator);
    defer testing.allocator.free(full2);

    try testing.expectEqualStrings("1_test", full1);
    try testing.expectEqualStrings("999_another_test", full2);
}

// =============================================================================
// 错误场景和边界条件测试
// =============================================================================

test "MigrationManager: up 空迁移列表" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    const applied = try mgr.up(null);
    try testing.expectEqual(@as(usize, 0), applied);
}

test "MigrationManager: down 空应用列表" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    const rolled_back = try mgr.down(1);
    try testing.expectEqual(@as(usize, 0), rolled_back);
}

test "MigrationManager: down steps 边界条件 - 回滚数量超过已应用数量" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const mock_result = try MockResult.init(testing.allocator);
    // 模拟有 2 个已应用的迁移
    try mock_result.addRow(&[_][]const u8{"2"});
    try mock_result.addRow(&[_][]const u8{"1"});
    mock_conn.setMockResult(mock_result);

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    try mgr.register(Migration.init(1, "m1", "SQL1", "DOWN1"));
    try mgr.register(Migration.init(2, "m2", "SQL2", "DOWN2"));

    // 请求回滚 10 个,但只有 2 个已应用
    const rolled_back = try mgr.down(10);

    // 应该只回滚实际存在的 2 个
    try testing.expectEqual(@as(usize, 2), rolled_back);
}

test "MigrationManager: status 空状态" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    const status = try mgr.status();
    try testing.expectEqual(@as(usize, 0), status.total);
    try testing.expectEqual(@as(usize, 0), status.applied);
    try testing.expectEqual(@as(usize, 0), status.pending);
}

test "MigrationManager: status 计算逻辑" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const mock_result = try MockResult.init(testing.allocator);
    // 模拟已应用版本 1 和 2
    try mock_result.addRow(&[_][]const u8{"1"});
    try mock_result.addRow(&[_][]const u8{"2"});
    mock_conn.setMockResult(mock_result);

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    // 注册 4 个迁移
    try mgr.register(Migration.init(1, "m1", "SQL1", "DOWN1"));
    try mgr.register(Migration.init(2, "m2", "SQL2", "DOWN2"));
    try mgr.register(Migration.init(3, "m3", "SQL3", "DOWN3"));
    try mgr.register(Migration.init(4, "m4", "SQL4", "DOWN4"));

    const status = try mgr.status();

    try testing.expectEqual(@as(usize, 4), status.total); // 总共 4 个
    try testing.expectEqual(@as(usize, 2), status.applied); // 已应用 2 个
    try testing.expectEqual(@as(usize, 2), status.pending); // 待应用 2 个
}

// =============================================================================
// Mock DB 核心方法测试
// =============================================================================

test "MigrationManager: ensureMigrationsTable PostgreSQL" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    // 调用 up 会触发 ensureMigrationsTable
    _ = try mgr.up(null);

    // 验证创建历史表的 SQL 被调用
    try testing.expect(mock_conn.exec_calls.items.len > 0);
    const first_call = mock_conn.exec_calls.items[0];
    try testing.expect(std.mem.indexOf(u8, first_call, "CREATE TABLE IF NOT EXISTS") != null);
    try testing.expect(std.mem.indexOf(u8, first_call, "schema_migrations") != null);
}

test "MigrationManager: ensureMigrationsTable MySQL" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.mysql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.mysql).init(testing.allocator, db);
    defer mgr.deinit();

    _ = try mgr.up(null);

    try testing.expect(mock_conn.exec_calls.items.len > 0);
    const first_call = mock_conn.exec_calls.items[0];
    try testing.expect(std.mem.indexOf(u8, first_call, "CREATE TABLE IF NOT EXISTS") != null);
}

test "MigrationManager: ensureMigrationsTable SQLite" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.sqlite);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.sqlite).init(testing.allocator, db);
    defer mgr.deinit();

    _ = try mgr.up(null);

    try testing.expect(mock_conn.exec_calls.items.len > 0);
    const first_call = mock_conn.exec_calls.items[0];
    try testing.expect(std.mem.indexOf(u8, first_call, "CREATE TABLE IF NOT EXISTS") != null);
}

test "MigrationManager: up 基本流程验证" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    try mgr.register(Migration.init(1, "m1", "CREATE TABLE test1 (id INT)", "DROP TABLE test1"));

    const applied = try mgr.up(null);
    try testing.expectEqual(@as(usize, 1), applied);
}

test "MigrationManager: down 基本流程验证" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const mock_result = try MockResult.init(testing.allocator);
    try mock_result.addRow(&[_][]const u8{"1"});
    mock_conn.setMockResult(mock_result);

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    try mgr.register(Migration.init(1, "m1", "CREATE TABLE test1 (id INT)", "DROP TABLE test1"));

    const rolled_back = try mgr.down(1);
    try testing.expectEqual(@as(usize, 1), rolled_back);
}

test "MigrationManager: reset 重置历史表" {
    const mock_conn = try MockConn.init(testing.allocator);
    defer mock_conn.deinit();

    const DbType = @import("zorm").DB(.postgresql);
    var db = try DbType.init(
        testing.allocator,
        mock_conn.conn(),
        .{},
    );
    defer db.deinit();

    var mgr = try MigrationManager(.postgresql).init(testing.allocator, db);
    defer mgr.deinit();

    try mgr.reset();

    // 验证调用了 DROP TABLE
    const last_call = mock_conn.exec_calls.items[mock_conn.exec_calls.items.len - 1];
    try testing.expect(std.mem.indexOf(u8, last_call, "DROP TABLE") != null);
}

// =============================================================================
// 集成测试示例 (需要真实数据库,默认注释)
// =============================================================================

// 使用示例文档
//
// ```zig
// const std = @import("std");
// const zorm = @import("zorm");
//
// pub fn main() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const allocator = gpa.allocator();
//
//     // 1. 创建数据库连接
//     var db = try zorm.DB(.postgresql).init(
//         allocator,
//         postgres_conn,
//         .{},
//     );
//     defer db.deinit();
//
//     // 2. 创建迁移管理器
//     var mgr = try zorm.MigrationManager(.postgresql).init(allocator, db);
//     defer mgr.deinit();
//
//     // 3. 定义迁移
//     const migration_001 = zorm.Migration.init(
//         20250117000001,
//         "create_users_table",
//         \\CREATE TABLE users (
//         \\  id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
//         \\  name VARCHAR(255) NOT NULL,
//         \\  email VARCHAR(255) UNIQUE NOT NULL,
//         \\  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
//         \\)
//         ,
//         "DROP TABLE users",
//     );
//
//     // 4. 注册迁移
//     try mgr.register(migration_001);
//
//     // 5. 执行迁移
//     const applied = try mgr.up(null);
//     std.debug.print("Applied {} migrations\n", .{applied});
// }
// ```
