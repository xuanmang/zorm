const std = @import("std");
const testing = std.testing;

// 测试模型
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

// Mock DB for testing
const MockDB = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MockDB {
        return .{ .allocator = allocator };
    }

    pub fn exec(_: *MockDB, _: []const u8, _: anytype) !void {
        // Mock execution - do nothing
    }
};

test "CreateIndexQuery: 简单索引 SQL 构建" {
    const allocator = testing.allocator;
    const query_mod = @import("zorm");
    const CreateIndexQuery = query_mod.CreateIndexQuery;

    var mock_db = MockDB.init(allocator);
    var query = try CreateIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.index("idx_users_email");
    _ = try query.column("email");

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX idx_users_email ON users (email)", sql);
}

test "CreateIndexQuery: 复合索引（多列）" {
    const allocator = testing.allocator;
    const query_mod = @import("zorm");
    const CreateIndexQuery = query_mod.CreateIndexQuery;

    var mock_db = MockDB.init(allocator);
    var query = try CreateIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.index("idx_users_status_created");
    _ = try query.column("status");
    _ = try query.column("created_at");

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX idx_users_status_created ON users (status, created_at)", sql);
}

test "CreateIndexQuery: 唯一索引" {
    const allocator = testing.allocator;
    const query_mod = @import("zorm");
    const CreateIndexQuery = query_mod.CreateIndexQuery;

    var mock_db = MockDB.init(allocator);
    var query = try CreateIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.index("idx_users_username_unique");
    _ = try query.column("username");
    _ = query.unique();

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("CREATE UNIQUE INDEX idx_users_username_unique ON users (username)", sql);
}

test "CreateIndexQuery: IF NOT EXISTS 子句" {
    const allocator = testing.allocator;
    const query_mod = @import("zorm");
    const CreateIndexQuery = query_mod.CreateIndexQuery;

    var mock_db = MockDB.init(allocator);
    var query = try CreateIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.index("idx_users_email");
    _ = try query.column("email");
    _ = query.ifNotExists();

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX IF NOT EXISTS idx_users_email ON users (email)", sql);
}

test "CreateIndexQuery: 表达式索引" {
    const allocator = testing.allocator;
    const query_mod = @import("zorm");
    const CreateIndexQuery = query_mod.CreateIndexQuery;

    var mock_db = MockDB.init(allocator);
    var query = try CreateIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.index("idx_users_email_lower");
    _ = try query.column("LOWER(email)");

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX idx_users_email_lower ON users (LOWER(email))", sql);
}

test "CreateIndexQuery: 部分索引（WHERE 子句）" {
    const allocator = testing.allocator;
    const query_mod = @import("zorm");
    const CreateIndexQuery = query_mod.CreateIndexQuery;

    var mock_db = MockDB.init(allocator);
    var query = try CreateIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.index("idx_users_active_email");
    _ = try query.column("email");
    _ = query.where("is_active = true");

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings("CREATE INDEX idx_users_active_email ON users (email) WHERE is_active = true", sql);
}

test "CreateIndexQuery: 完整链式调用" {
    const allocator = testing.allocator;
    const query_mod = @import("zorm");
    const CreateIndexQuery = query_mod.CreateIndexQuery;

    var mock_db = MockDB.init(allocator);
    var query = try CreateIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query
        .index("idx_users_active_status")
        .unique()
        .ifNotExists();
    _ = try query.column("status");
    _ = try query.column("created_at");
    _ = query.where("is_active = true");

    const sql = try query.build();
    defer allocator.free(sql);

    try testing.expectEqualStrings(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_active_status ON users (status, created_at) WHERE is_active = true",
        sql,
    );
}

test "CreateIndexQuery: 参数验证 - 索引名必需" {
    const allocator = testing.allocator;
    const query_mod = @import("zorm");
    const CreateIndexQuery = query_mod.CreateIndexQuery;

    var mock_db = MockDB.init(allocator);
    var query = try CreateIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = try query.column("email");

    const result = query.build();
    try testing.expectError(error.IndexNameRequired, result);
}

test "CreateIndexQuery: 参数验证 - 列必需" {
    const allocator = testing.allocator;
    const query_mod = @import("zorm");
    const CreateIndexQuery = query_mod.CreateIndexQuery;

    var mock_db = MockDB.init(allocator);
    var query = try CreateIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
    defer query.deinit();

    _ = query.index("idx_test");

    const result = query.build();
    try testing.expectError(error.ColumnsRequired, result);
}

test "CreateIndexQuery: 内存泄漏检测" {
    const allocator = testing.allocator;
    const query_mod = @import("zorm");
    const CreateIndexQuery = query_mod.CreateIndexQuery;

    var mock_db = MockDB.init(allocator);

    {
        var query = try CreateIndexQuery(User, .postgresql).init(allocator, @ptrCast(&mock_db));
        defer query.deinit();

        _ = query.index("idx_test");
        _ = try query.column("col1");
        _ = try query.column("col2");
        _ = try query.column("col3");

        const sql = try query.build();
        defer allocator.free(sql);

        try testing.expect(sql.len > 0);
    }

    // testing.allocator 会自动检测泄漏
}
