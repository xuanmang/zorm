//! PostgreSQL 驱动实现
//! 基于 pg.zig 库提供 PostgreSQL 数据库连接和查询功能
//!
//! 主要功能:
//! - 数据库连接管理 (使用连接池)
//! - SQL 查询执行 (exec/query)
//! - 结果集处理
//! - 参数化查询支持
//! - 错误处理

const std = @import("std");
const pg = @import("pg");
const Allocator = std.mem.Allocator;
const QueryArg = @import("../types.zig").QueryArg;
const connection = @import("connection.zig");
const Result = connection.Result;
const Rows = connection.Rows;
const Row = connection.Row;
const RowsVTable = Rows.RowsVTable;
const RowVTable = Row.RowVTable;
const Error = connection.Error;

// 注意：由于 Zig 不支持 anytype 作为返回类型，
// 并且 pg.zig 的 exec/query 需要 comptime tuple 参数，
// 我们使用 pg.Stmt 的 bind 方法，它可以逐个绑定参数
// 这样可以避免编译时类型不匹配的问题

/// PostgreSQL 驱动
/// 使用 pg.zig 的连接池管理数据库连接
pub const PostgresDriver = struct {
    pool: *pg.Pool,
    allocator: Allocator,

    /// 连接到 PostgreSQL 数据库
    /// dsn 格式: "host=127.0.0.1 port=5432 user=pguser password=Pg#123! dbname=postgres"
    pub fn connect(allocator: Allocator, dsn: []const u8) !PostgresDriver {
        // 解析 DSN 字符串
        const config = try parseDSN(allocator, dsn);
        defer {
            if (config.host) |h| allocator.free(h);
            if (config.username) |u| allocator.free(u);
            if (config.password) |p| allocator.free(p);
            if (config.database) |d| allocator.free(d);
        }

        // 创建连接池 (pg.Pool.init 返回 *Pool)
        const pool = pg.Pool.init(allocator, .{
            .size = 5,
            .connect = .{
                .host = config.host orelse "127.0.0.1",
                .port = config.port,
            },
            .auth = .{
                .username = config.username orelse "postgres",
                .password = config.password,
                .database = config.database,
                .timeout = 10_000,
            },
        }) catch |err| {
            return switch (err) {
                error.Unexpected => Error.ConnectionFailed,
                error.OutOfMemory => Error.OutOfMemory,
                else => Error.ConnectionFailed,
            };
        };

        return PostgresDriver{
            .pool = pool,
            .allocator = allocator,
        };
    }

    /// 关闭数据库连接
    pub fn close(self: *PostgresDriver) !void {
        self.pool.deinit();
    }

    /// 执行 SQL 语句 (INSERT, UPDATE, DELETE)
    /// 返回影响的行数
    pub fn exec(self: *PostgresDriver, sql: []const u8, args: []const QueryArg) !Result {
        // 无参数的简单情况，直接使用 pool.exec
        if (args.len == 0) {
            const rows_affected = self.pool.exec(sql, .{}) catch |err| {
                return switch (err) {
                    error.Unexpected => Error.QueryFailed,
                    error.OutOfMemory => Error.OutOfMemory,
                    else => Error.QueryFailed,
                };
            };
            return Result{
                .last_insert_id = 0,
                .rows_affected = @intCast(rows_affected orelse 0),
            };
        }

        // 有参数的情况，使用 prepared statement
        // 获取连接
        const conn = self.pool.acquire() catch {
            return Error.ConnectionFailed;
        };
        defer self.pool.release(conn);

        // 创建 statement
        var stmt = pg.Stmt.init(conn, .{}) catch {
            return Error.QueryFailed;
        };
        defer stmt.deinit();

        // Prepare SQL
        stmt.prepare(sql, null) catch {
            return Error.QueryFailed;
        };

        // Prepare for binding
        stmt.prepareForBind(@intCast(args.len)) catch {
            return Error.QueryFailed;
        };

        // Bind parameters
        for (args) |arg| {
            switch (arg) {
                .int => |v| try stmt.bind(v),
                .uint => |v| try stmt.bind(@as(i64, @intCast(v))),
                .float => |v| try stmt.bind(v),
                .bool => |v| try stmt.bind(v),
                .string => |v| try stmt.bind(v),
                .bytes => |v| try stmt.bind(v),
                .null_val => try stmt.bind(@as(?i32, null)),
            }
        }

        // Execute
        const result = stmt.execute() catch {
            return Error.QueryFailed;
        };
        defer result.deinit();

        // 注意：pg.Stmt.execute() 返回的 Result 不包含影响行数
        // 需要使用 RETURNING 子句或其他方式获取
        // 暂时返回 0
        return Result{
            .last_insert_id = 0, // PostgreSQL 需要 RETURNING 子句获取 ID
            .rows_affected = 0,  // 暂时不支持获取影响行数
        };
    }

    /// 执行 SELECT 查询
    /// 返回结果集迭代器
    pub fn query(self: *PostgresDriver, sql: []const u8, args: []const QueryArg) !Rows {
        // 无参数的简单情况，直接使用 pool.query
        const result = if (args.len == 0) blk: {
            const r = self.pool.query(sql, .{}) catch |err| {
                return switch (err) {
                    error.Unexpected => Error.QueryFailed,
                    error.OutOfMemory => Error.OutOfMemory,
                    else => Error.QueryFailed,
                };
            };
            break :blk r;
        } else blk: {
            // 有参数的情况，使用 prepared statement
            // 获取连接
            const conn = self.pool.acquire() catch {
                return Error.ConnectionFailed;
            };
            // 注意：不能 defer release，因为 result 需要保持连接

            // 创建 statement
            var stmt = pg.Stmt.init(conn, .{}) catch {
                self.pool.release(conn);
                return Error.QueryFailed;
            };
            defer stmt.deinit();

            // Prepare SQL
            stmt.prepare(sql, null) catch {
                self.pool.release(conn);
                return Error.QueryFailed;
            };

            // Prepare for binding
            stmt.prepareForBind(@intCast(args.len)) catch {
                self.pool.release(conn);
                return Error.QueryFailed;
            };

            // Bind parameters
            for (args) |arg| {
                const bind_result = switch (arg) {
                    .int => |v| stmt.bind(v),
                    .uint => |v| stmt.bind(@as(i64, @intCast(v))),
                    .float => |v| stmt.bind(v),
                    .bool => |v| stmt.bind(v),
                    .string => |v| stmt.bind(v),
                    .bytes => |v| stmt.bind(v),
                    .null_val => stmt.bind(@as(?i32, null)),
                };
                bind_result catch {
                    self.pool.release(conn);
                    return Error.QueryFailed;
                };
            }

            // Execute
            const r = stmt.execute() catch {
                self.pool.release(conn);
                return Error.QueryFailed;
            };

            // 释放连接回池
            self.pool.release(conn);
            break :blk r;
        };

        // 创建 PostgresRows 包装器
        const postgres_rows = try self.allocator.create(PostgresRows);
        postgres_rows.* = .{
            .result = result,
            .allocator = self.allocator,
            .postgres_row = null, // 延迟创建
            .row_vtable = null,   // 延迟创建
        };

        // 创建 Rows VTable（只创建一次）
        const vtable = try self.allocator.create(RowsVTable);
        vtable.* = .{
            .next = &PostgresRows.next,
            .deinit = &PostgresRows.deinit,
        };

        return Rows{
            .driver_rows = postgres_rows,
            .vtable = vtable,
            .allocator = self.allocator,
        };
    }
};

/// 配置结构
const Config = struct {
    host: ?[]const u8 = null,
    port: u16 = 5432,
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
    database: ?[]const u8 = null,
};

/// 解析 DSN 字符串
/// 格式: "key1=value1 key2=value2 ..."
fn parseDSN(allocator: Allocator, dsn: []const u8) !Config {
    var config = Config{};
    var it = std.mem.tokenizeScalar(u8, dsn, ' ');

    while (it.next()) |pair| {
        var pair_it = std.mem.tokenizeScalar(u8, pair, '=');
        const key = pair_it.next() orelse continue;
        const value = pair_it.next() orelse continue;

        if (std.mem.eql(u8, key, "host")) {
            config.host = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "port")) {
            config.port = try std.fmt.parseInt(u16, value, 10);
        } else if (std.mem.eql(u8, key, "user")) {
            config.username = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "password")) {
            config.password = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "dbname")) {
            config.database = try allocator.dupe(u8, value);
        }
    }

    return config;
}

/// PostgreSQL 结果集包装器
const PostgresRows = struct {
    result: *pg.Result,
    allocator: Allocator,
    // 重用的 Row 对象，避免每次 next() 都分配内存
    postgres_row: ?*PostgresRow = null,
    row_vtable: ?*RowVTable = null,

    fn next(ptr: *anyopaque) Error!?Row {
        const self: *PostgresRows = @ptrCast(@alignCast(ptr));

        const pg_row = self.result.next() catch {
            return Error.QueryFailed;
        };

        if (pg_row == null) {
            return null;
        }

        // 延迟初始化 PostgresRow 和 VTable（只创建一次）
        if (self.postgres_row == null) {
            self.postgres_row = try self.allocator.create(PostgresRow);
            self.row_vtable = try self.allocator.create(RowVTable);
            self.row_vtable.?.* = .{
                .isNull = &PostgresRow.isNull,
                .getInt = &PostgresRow.getInt,
                .getFloat = &PostgresRow.getFloat,
                .getBool = &PostgresRow.getBool,
                .getString = &PostgresRow.getString,
            };
        }

        // 更新 Row 数据（重用对象）
        self.postgres_row.?.* = .{
            .row = pg_row.?,
            .allocator = self.allocator,
        };

        return Row{
            .driver_row = self.postgres_row.?,
            .vtable = self.row_vtable.?,
        };
    }

    fn deinit(ptr: *anyopaque, allocator: Allocator) void {
        const self: *PostgresRows = @ptrCast(@alignCast(ptr));

        // 释放重用的 Row 对象
        if (self.postgres_row) |row| {
            allocator.destroy(row);
        }
        if (self.row_vtable) |vtable| {
            allocator.destroy(vtable);
        }

        self.result.deinit();
        allocator.destroy(self);
    }
};

/// PostgreSQL 行包装器
const PostgresRow = struct {
    row: pg.Row,
    allocator: Allocator,

    fn isNull(ptr: *anyopaque, index: usize) bool {
        // pg.Row 不提供 isNull 方法
        // 暂时总是返回 false，实际 NULL 处理需要通过 optional 类型
        _ = ptr;
        _ = index;
        return false;
    }

    fn getInt(ptr: *anyopaque, index: usize) Error!i64 {
        const self: *PostgresRow = @ptrCast(@alignCast(ptr));
        // pg.zig 有严格的类型检查，需要根据列的 OID 使用正确的类型
        // PostgreSQL OID: INT4 (INTEGER) = 23, INT8 (BIGINT) = 20
        const oid = self.row.oids[index];

        if (oid == 23) { // INT4 (INTEGER)
            const value = self.row.get(i32, index);
            return @intCast(value);
        } else if (oid == 20) { // INT8 (BIGINT)
            const value = self.row.get(i64, index);
            return value;
        } else if (oid == 21) { // INT2 (SMALLINT)
            const value = self.row.get(i16, index);
            return @intCast(value);
        }

        return Error.TypeMismatch;
    }

    fn getFloat(ptr: *anyopaque, index: usize) Error!f64 {
        const self: *PostgresRow = @ptrCast(@alignCast(ptr));
        const value = self.row.get(f64, index);
        return value;
    }

    fn getBool(ptr: *anyopaque, index: usize) Error!bool {
        const self: *PostgresRow = @ptrCast(@alignCast(ptr));
        const value = self.row.get(bool, index);
        return value;
    }

    fn getString(ptr: *anyopaque, index: usize) Error![]const u8 {
        const self: *PostgresRow = @ptrCast(@alignCast(ptr));
        const value = self.row.get([]const u8, index);
        return value;
    }
};
