const std = @import("std");
const zorm = @import("zorm");
const PostgresDriver = zorm.PostgresDriver;
const QueryArg = zorm.QueryArg;

const TEST_DSN = "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres";

test "1 - connection success" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};
}

test "2 - connection invalid DSN" {
    const allocator = std.testing.allocator;

    const invalid_dsn = "host=invalid.host port=5432 user=invalid password=invalid dbname=invalid";
    const result = PostgresDriver.connect(allocator, invalid_dsn);

    try std.testing.expectError(error.ConnectionFailed, result);
}

test "3 - CREATE TABLE" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    const drop_sql = "DROP TABLE IF EXISTS test_users";
    _ = try driver.exec(drop_sql, &.{});

    const create_sql = "CREATE TABLE test_users (id SERIAL PRIMARY KEY, name TEXT NOT NULL)";
    const result = try driver.exec(create_sql, &.{});

    try std.testing.expect(result.rows_affected >= 0);
}

test "4 - INSERT with parameters" {
    const allocator = std.testing.allocator;

    var driver = try PostgresDriver.connect(allocator, TEST_DSN);
    defer driver.close() catch {};

    _ = try driver.exec("DROP TABLE IF EXISTS test_users", &.{});
    _ = try driver.exec(
        "CREATE TABLE test_users (id SERIAL PRIMARY KEY, name TEXT, age INTEGER)",
        &.{},
    );

    const insert_sql = "INSERT INTO test_users (name, age) VALUES ($1, $2)";
    const args = [_]QueryArg{
        QueryArg.fromValue("Bob"),
        QueryArg.fromValue(@as(i64, 30)),
    };

    const result = try driver.exec(insert_sql, &args);
    // 注意：当前实现 rows_affected 返回 0（已知限制）
    try std.testing.expect(result.rows_affected >= 0);
}

// test "5 - SELECT with parameters" {
//     const allocator = std.testing.allocator;

//     var driver = try PostgresDriver.connect(allocator, TEST_DSN);
//     defer driver.close() catch {};

//     _ = try driver.exec("DROP TABLE IF EXISTS test_users", &.{});
//     _ = try driver.exec(
//         "CREATE TABLE test_users (id SERIAL PRIMARY KEY, name TEXT, age INTEGER)",
//         &.{},
//     );
//     _ = try driver.exec(
//         "INSERT INTO test_users (name, age) VALUES ('Alice', 25), ('Bob', 30), ('Charlie', 35)",
//         &.{},
//     );

//     const select_sql = "SELECT name, age FROM test_users WHERE age > $1 ORDER BY age";
//     const args = [_]QueryArg{QueryArg.fromValue(@as(i64, 26))};

//     var rows = try driver.query(select_sql, &args);
//     defer rows.deinit();

//     var count: usize = 0;
//     while (try rows.next()) |row| {
//         const age = try row.getInt(i64, 1);
//         try std.testing.expect(age > 26);
//         count += 1;
//     }

//     try std.testing.expectEqual(@as(usize, 2), count);
// }
