// tests/integration/postgres_test.zig
// PostgreSQL 驱动集成测试
// 测试真实 PostgreSQL 数据库的连接、CRUD 操作、参数绑定和错误处理

const std = @import("std");
const zorm = @import("zorm");
const PostgresDriver = zorm.PostgresDriver;
const QueryArg = zorm.QueryArg;

// 测试数据库连接配置
const TEST_DSN = "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres";

test "PostgreSQL connection - success" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    // 连接成功 (通过 try 关键字已验证)
    // pg.Pool 不暴露底层连接，所以无需检查 conn 字段
}

test "PostgreSQL connection - invalid DSN" {
    const allocator = std.testing.allocator;

    const invalid_dsn = "host=invalid.host port=5432 user=invalid password=invalid dbname=invalid";
    const result = PostgresDriver.connect(allocator, invalid_dsn);

    // 预期连接失败
    try std.testing.expectError(error.ConnectionFailed, result);
}

test "PostgreSQL exec - CREATE TABLE" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    // 创建测试表
    const create_sql =
        \\DROP TABLE IF EXISTS test_users;
        \\CREATE TABLE test_users (
        \\    id SERIAL PRIMARY KEY,
        \\    name TEXT NOT NULL,
        \\    email TEXT,
        \\    age INTEGER,
        \\    active BOOLEAN DEFAULT true
        \\);
    ;

    const result = try driver.exec(create_sql, &.{});
    try std.testing.expect(result.rows_affected >= 0);
}

test "PostgreSQL exec - INSERT without parameters" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    // 先创建表
    _ = try driver.exec(
        "DROP TABLE IF EXISTS test_users; CREATE TABLE test_users (id SERIAL PRIMARY KEY, name TEXT NOT NULL);",
        &.{},
    );

    // 插入数据
    const insert_sql = "INSERT INTO test_users (name) VALUES ('Alice')";
    const result = try driver.exec(insert_sql, &.{});

    try std.testing.expectEqual(@as(u64, 1), result.rows_affected);
}

test "PostgreSQL exec - INSERT with parameters" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    // 先创建表
    _ = try driver.exec(
        \\DROP TABLE IF EXISTS test_users;
        \\CREATE TABLE test_users (
        \\    id SERIAL PRIMARY KEY,
        \\    name TEXT NOT NULL,
        \\    email TEXT,
        \\    age INTEGER,
        \\    active BOOLEAN
        \\);
    , &.{});

    // 插入数据 (使用参数化查询)
    const insert_sql = "INSERT INTO test_users (name, email, age, active) VALUES ($1, $2, $3, $4)";
    const args = [_]QueryArg{
        QueryArg.fromValue("Bob"),
        QueryArg.fromValue("bob@example.com"),
        QueryArg.fromValue(@as(i64, 30)),
        QueryArg.fromValue(true),
    };

    const result = try driver.exec(insert_sql, &args);
    try std.testing.expectEqual(@as(u64, 1), result.rows_affected);
}

test "PostgreSQL exec - UPDATE with parameters" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    // 准备测试数据
    _ = try driver.exec(
        \\DROP TABLE IF EXISTS test_users;
        \\CREATE TABLE test_users (id SERIAL PRIMARY KEY, name TEXT, age INTEGER);
        \\INSERT INTO test_users (name, age) VALUES ('Charlie', 25);
    , &.{});

    // 更新数据
    const update_sql = "UPDATE test_users SET age = $1 WHERE name = $2";
    const args = [_]QueryArg{
        QueryArg.fromValue(@as(i64, 26)),
        QueryArg.fromValue("Charlie"),
    };

    const result = try driver.exec(update_sql, &args);
    try std.testing.expectEqual(@as(u64, 1), result.rows_affected);
}

test "PostgreSQL exec - DELETE with parameters" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    // 准备测试数据
    _ = try driver.exec(
        \\DROP TABLE IF EXISTS test_users;
        \\CREATE TABLE test_users (id SERIAL PRIMARY KEY, name TEXT);
        \\INSERT INTO test_users (name) VALUES ('David'), ('Eve');
    , &.{});

    // 删除数据
    const delete_sql = "DELETE FROM test_users WHERE name = $1";
    const args = [_]QueryArg{QueryArg.fromValue("David")};

    const result = try driver.exec(delete_sql, &args);
    try std.testing.expectEqual(@as(u64, 1), result.rows_affected);
}

test "PostgreSQL query - SELECT without parameters" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    // 准备测试数据
    _ = try driver.exec(
        \\DROP TABLE IF EXISTS test_users;
        \\CREATE TABLE test_users (id SERIAL PRIMARY KEY, name TEXT NOT NULL);
        \\INSERT INTO test_users (name) VALUES ('Frank'), ('Grace');
    , &.{});

    // 查询数据
    const select_sql = "SELECT id, name FROM test_users ORDER BY id";
    var rows = try driver.query(select_sql, &.{});
    defer rows.deinit();

    var count: usize = 0;
    while (try rows.next()) |row| {
        const id = try row.getInt(i64, 0);
        const name = try row.getString(1);

        try std.testing.expect(id > 0);
        try std.testing.expect(name.len > 0);

        count += 1;
    }

    try std.testing.expectEqual(@as(usize, 2), count);
}

test "PostgreSQL query - SELECT with parameters" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    // 准备测试数据
    _ = try driver.exec(
        \\DROP TABLE IF EXISTS test_users;
        \\CREATE TABLE test_users (id SERIAL PRIMARY KEY, name TEXT, age INTEGER);
        \\INSERT INTO test_users (name, age) VALUES ('Helen', 28), ('Ian', 35), ('Jane', 22);
    , &.{});

    // 查询数据 (使用参数化查询)
    const select_sql = "SELECT id, name, age FROM test_users WHERE age > $1 ORDER BY age";
    const args = [_]QueryArg{QueryArg.fromValue(@as(i64, 25))};

    var rows = try driver.query(select_sql, &args);
    defer rows.deinit();

    var count: usize = 0;
    while (try rows.next()) |row| {
        const age = try row.getInt(i64, 2);
        try std.testing.expect(age > 25);
        count += 1;
    }

    try std.testing.expectEqual(@as(usize, 2), count);
}

test "PostgreSQL query - result types (int, float, bool, string)" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    // 准备测试数据
    _ = try driver.exec(
        \\DROP TABLE IF EXISTS test_types;
        \\CREATE TABLE test_types (
        \\    id SERIAL PRIMARY KEY,
        \\    int_val INTEGER,
        \\    float_val DOUBLE PRECISION,
        \\    bool_val BOOLEAN,
        \\    str_val TEXT
        \\);
        \\INSERT INTO test_types (int_val, float_val, bool_val, str_val)
        \\VALUES (42, 3.14, true, 'Hello');
    , &.{});

    // 查询并验证类型
    const select_sql = "SELECT int_val, float_val, bool_val, str_val FROM test_types";
    var rows = try driver.query(select_sql, &.{});
    defer rows.deinit();

    if (try rows.next()) |row| {
        const int_val = try row.getInt(i64, 0);
        const float_val = try row.getFloat(f64, 1);
        const bool_val = try row.getBool(2);
        const str_val = try row.getString(3);

        try std.testing.expectEqual(@as(i64, 42), int_val);
        try std.testing.expect(float_val > 3.13 and float_val < 3.15);
        try std.testing.expectEqual(true, bool_val);
        try std.testing.expectEqualStrings("Hello", str_val);
    } else {
        try std.testing.expect(false); // 应该有一行
    }
}

test "PostgreSQL query - NULL handling" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    // 准备测试数据 (包含 NULL 值)
    _ = try driver.exec(
        \\DROP TABLE IF EXISTS test_nulls;
        \\CREATE TABLE test_nulls (id SERIAL PRIMARY KEY, name TEXT, email TEXT);
        \\INSERT INTO test_nulls (name, email) VALUES ('Kate', NULL);
    , &.{});

    // 查询并检查 NULL
    const select_sql = "SELECT name, email FROM test_nulls";
    var rows = try driver.query(select_sql, &.{});
    defer rows.deinit();

    if (try rows.next()) |row| {
        const name = try row.getString(0);
        try std.testing.expectEqualStrings("Kate", name);

        // email 应该是 NULL
        try std.testing.expect(row.isNull(1));

        // 尝试读取 NULL 值应该返回错误
        const email_result = row.getString(1);
        try std.testing.expectError(error.NullValue, email_result);
    } else {
        try std.testing.expect(false);
    }
}

test "PostgreSQL exec - invalid SQL" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    // 执行无效的 SQL
    const invalid_sql = "INVALID SQL STATEMENT";
    const result = driver.exec(invalid_sql, &.{});

    try std.testing.expectError(error.QueryFailed, result);
}

test "PostgreSQL query - invalid SQL" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    // 执行无效的 SQL
    const invalid_sql = "SELECT * FROM non_existent_table";
    if (driver.query(invalid_sql, &.{})) |rows| {
        var mutable_rows = rows;
        mutable_rows.deinit();
        try std.testing.expect(false); // 应该失败
    } else |err| {
        try std.testing.expectEqual(error.QueryFailed, err);
    }
}

test "PostgreSQL - parameter binding prevents SQL injection" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    // 准备测试数据
    _ = try driver.exec(
        \\DROP TABLE IF EXISTS test_users;
        \\CREATE TABLE test_users (id SERIAL PRIMARY KEY, name TEXT);
        \\INSERT INTO test_users (name) VALUES ('Leo');
    , &.{});

    // 尝试 SQL 注入 (应该被参数化查询阻止)
    const malicious_input = "'; DROP TABLE test_users; --";
    const select_sql = "SELECT * FROM test_users WHERE name = $1";
    const args = [_]QueryArg{QueryArg.fromValue(malicious_input)};

    var rows = try driver.query(select_sql, &args);
    defer rows.deinit();

    // 应该没有找到行 (因为恶意输入被当作普通字符串处理)
    const row = try rows.next();
    try std.testing.expect(row == null);

    // 验证表仍然存在 (没有被 DROP)
    const verify_sql = "SELECT COUNT(*) FROM test_users";
    var verify_rows = try driver.query(verify_sql, &.{});
    defer verify_rows.deinit();

    if (try verify_rows.next()) |verify_row| {
        const count = try verify_row.getInt(i64, 0);
        try std.testing.expectEqual(@as(i64, 1), count);
    } else {
        try std.testing.expect(false);
    }
}

test "PostgreSQL - cleanup after test" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    // 清理所有测试表
    _ = try driver.exec(
        \\DROP TABLE IF EXISTS test_users;
        \\DROP TABLE IF EXISTS test_types;
        \\DROP TABLE IF EXISTS test_nulls;
    , &.{});
}
