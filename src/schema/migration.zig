//! Migration 系统 - 数据库 Schema 版本管理
//!
//! 提供完整的数据库迁移支持:
//! - 版本化的 up/down 迁移
//! - 迁移历史记录表管理
//! - 多数据库方言支持
//! - 事务安全的迁移执行
//!
//! # 核心功能
//! - 定义和执行迁移
//! - 自动管理 schema_migrations 历史表
//! - 支持向上迁移 (up) 和向下回滚 (down)
//! - 版本号管理和验证
//!
//! # 设计原则
//! - 使用 Builder 模式定义迁移
//! - 事务中执行迁移,确保原子性
//! - 编译时类型检查和方言适配
//!
//! # 安全性警告
//! **迁移 SQL 验证**: 本模块不验证迁移 SQL 的安全性。
//! - up_sql 和 down_sql 将被直接执行
//! - 调用方必须确保迁移 SQL 来自可信源
//! - 恶意迁移可能导致数据丢失或数据库损坏
//! - 建议在生产环境前在测试环境中验证所有迁移
//!
//! **事务限制**:
//! - DDL 语句在某些数据库中不支持事务回滚 (如 MySQL 的 CREATE/DROP TABLE)
//! - 迁移失败可能导致部分应用的状态,需要手动修复

const std = @import("std");
const Allocator = std.mem.Allocator;
const Dialect = @import("../dialect/dialect.zig").Dialect;
const DB = @import("../core/db.zig").DB;

/// 迁移方向
pub const Direction = enum {
    up, // 向上迁移
    down, // 向下回滚

    pub fn toString(self: Direction) []const u8 {
        return switch (self) {
            .up => "up",
            .down => "down",
        };
    }
};

/// 迁移记录
pub const MigrationRecord = struct {
    version: u64,
    name: []const u8,
    applied_at: i64, // Unix timestamp
};

/// 迁移定义
///
/// 代表单个数据库迁移,包含版本号、名称和 up/down SQL
pub const Migration = struct {
    version: u64,
    name: []const u8,
    up_sql: []const u8,
    down_sql: []const u8,

    /// 创建迁移
    pub fn init(version: u64, name: []const u8, up_sql: []const u8, down_sql: []const u8) Migration {
        return .{
            .version = version,
            .name = name,
            .up_sql = up_sql,
            .down_sql = down_sql,
        };
    }

    /// 获取完整的迁移标识符
    pub fn fullName(self: *const Migration, allocator: Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{d}_{s}", .{ self.version, self.name });
    }
};

/// 迁移管理器
///
/// 负责执行迁移和管理迁移历史
pub fn MigrationManager(comptime dialect: Dialect) type {
    return struct {
        const Self = @This();
        const DbType = DB(dialect);

        allocator: Allocator,
        db: *DbType,
        migrations: std.ArrayList(Migration),
        migrations_table: []const u8,

        /// 创建迁移管理器
        ///
        /// ## 参数
        /// - allocator: 内存分配器
        /// - db: 数据库实例
        ///
        /// ## 示例
        /// ```zig
        /// var mgr = try MigrationManager(.postgresql).init(allocator, db);
        /// defer mgr.deinit();
        /// ```
        pub fn init(allocator: Allocator, db: *DbType) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.* = .{
                .allocator = allocator,
                .db = db,
                .migrations = .{},
                .migrations_table = "schema_migrations",
            };

            return self;
        }

        /// 释放资源
        pub fn deinit(self: *Self) void {
            self.migrations.deinit(self.allocator);
            self.allocator.destroy(self);
        }

        /// 设置迁移历史表名
        pub fn setMigrationsTable(self: *Self, table_name: []const u8) void {
            self.migrations_table = table_name;
        }

        /// 注册迁移
        ///
        /// ## 参数
        /// - migration: 迁移定义
        pub fn register(self: *Self, migration: Migration) !void {
            try self.migrations.append(self.allocator, migration);
        }

        /// 批量注册迁移
        pub fn registerMany(self: *Self, migration_list: []const Migration) !void {
            for (migration_list) |migration| {
                try self.register(migration);
            }
        }

        /// 确保迁移历史表存在
        fn ensureMigrationsTable(self: *Self) !void {
            const create_table_sql = comptime switch (dialect) {
                .postgresql =>
                \\CREATE TABLE IF NOT EXISTS {s} (
                \\  version BIGINT PRIMARY KEY,
                \\  name VARCHAR(255) NOT NULL,
                \\  applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                \\)
                ,
                .postgresql =>
                \\CREATE TABLE IF NOT EXISTS {s} (
                \\  version BIGINT PRIMARY KEY,
                \\  name VARCHAR(255) NOT NULL,
                \\  applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                \\)
                ,
                .postgresql =>
                \\CREATE TABLE IF NOT EXISTS {s} (
                \\  version INTEGER PRIMARY KEY,
                \\  name TEXT NOT NULL,
                \\  applied_at INTEGER NOT NULL
                \\)
                ,
            };

            const sql = try std.fmt.allocPrint(
                self.allocator,
                create_table_sql,
                .{self.migrations_table},
            );
            defer self.allocator.free(sql);

            try self.db.exec(sql, &.{});
        }

        /// 获取已应用的迁移版本列表
        fn getAppliedVersions(self: *Self) !std.ArrayList(u64) {
            var versions: std.ArrayList(u64) = .{};
            errdefer versions.deinit(self.allocator);

            const sql = try std.fmt.allocPrint(
                self.allocator,
                "SELECT version FROM {s} ORDER BY version ASC",
                .{self.migrations_table},
            );
            defer self.allocator.free(sql);

            const result = try self.db.query(sql, &.{});
            defer result.close();

            // 注意: 这里简化了结果扫描逻辑
            // 实际项目中需要使用完整的结果扫描器
            while (try result.next()) {
                var row_data: [1][]u8 = undefined;
                try result.scan(&row_data);
                const version = try std.fmt.parseInt(u64, row_data[0], 10);
                try versions.append(self.allocator, version);
            }

            return versions;
        }

        /// 记录迁移应用
        fn recordMigration(self: *Self, migration: *const Migration) !void {
            const timestamp = std.time.timestamp();

            const sql = comptime switch (dialect) {
                .postgresql => "INSERT INTO {s} (version, name, applied_at) VALUES ($1, $2, to_timestamp($3))",
                .postgresql => "INSERT INTO {s} (version, name, applied_at) VALUES (?, ?, FROM_UNIXTIME(?))",
                .postgresql => "INSERT INTO {s} (version, name, applied_at) VALUES (?, ?, ?)",
            };

            const query = try std.fmt.allocPrint(
                self.allocator,
                sql,
                .{self.migrations_table},
            );
            defer self.allocator.free(query);

            // 准备参数
            var version_buf: [32]u8 = undefined;
            const version_str = try std.fmt.bufPrint(&version_buf, "{d}", .{migration.version});

            var timestamp_buf: [32]u8 = undefined;
            const timestamp_str = try std.fmt.bufPrint(&timestamp_buf, "{d}", .{timestamp});

            const args = [_][]const u8{ version_str, migration.name, timestamp_str };
            try self.db.exec(query, &args);
        }

        /// 删除迁移记录
        fn removeMigration(self: *Self, version: u64) !void {
            const sql = try std.fmt.allocPrint(
                self.allocator,
                comptime switch (dialect) {
                    .postgresql => "DELETE FROM {s} WHERE version = $1",
                    .postgresql, .postgresql => "DELETE FROM {s} WHERE version = ?",
                },
                .{self.migrations_table},
            );
            defer self.allocator.free(sql);

            // 使用参数化查询防止 SQL 注入
            var version_buf: [32]u8 = undefined;
            const version_str = try std.fmt.bufPrint(&version_buf, "{d}", .{version});
            const args = [_][]const u8{version_str};

            try self.db.exec(sql, &args);
        }

        /// 执行单个迁移
        fn executeMigration(self: *Self, migration: *const Migration, direction: Direction) !void {
            const sql = switch (direction) {
                .up => migration.up_sql,
                .down => migration.down_sql,
            };

            // 在事务中执行迁移
            _ = try self.db.begin();
            errdefer self.db.rollback() catch {};

            // 执行迁移 SQL
            try self.db.exec(sql, &.{});

            // 更新迁移记录
            switch (direction) {
                .up => try self.recordMigration(migration),
                .down => try self.removeMigration(migration.version),
            }

            // 提交事务
            try self.db.commit();
        }

        /// 向上迁移到指定版本
        ///
        /// 如果 target_version 为 null,则迁移到最新版本
        ///
        /// ## 参数
        /// - target_version: 目标版本号 (null = 最新版本)
        ///
        /// ## 返回
        /// 返回已应用的迁移数量
        pub fn up(self: *Self, target_version: ?u64) !usize {
            try self.ensureMigrationsTable();

            // 获取已应用的版本
            var applied = try self.getAppliedVersions();
            defer applied.deinit(self.allocator);

            // 排序迁移列表
            const migrations_slice = self.migrations.items;
            std.mem.sort(Migration, migrations_slice, {}, struct {
                fn lessThan(_: void, a: Migration, b: Migration) bool {
                    return a.version < b.version;
                }
            }.lessThan);

            var applied_count: usize = 0;

            // 应用未执行的迁移
            for (migrations_slice) |*migration| {
                // 检查是否已应用
                var already_applied = false;
                for (applied.items) |v| {
                    if (v == migration.version) {
                        already_applied = true;
                        break;
                    }
                }

                if (already_applied) continue;

                // 检查是否超过目标版本
                if (target_version) |target| {
                    if (migration.version > target) break;
                }

                // 执行迁移
                try self.executeMigration(migration, .up);
                applied_count += 1;

                std.log.info("Applied migration: {d}_{s}", .{ migration.version, migration.name });
            }

            return applied_count;
        }

        /// 向下回滚指定数量的迁移
        ///
        /// ## 参数
        /// - steps: 回滚的步数 (默认 1)
        ///
        /// ## 返回
        /// 返回已回滚的迁移数量
        pub fn down(self: *Self, steps: usize) !usize {
            try self.ensureMigrationsTable();

            // 获取已应用的版本
            var applied = try self.getAppliedVersions();
            defer applied.deinit(self.allocator);

            if (applied.items.len == 0) {
                return 0;
            }

            // 按版本倒序排列
            std.mem.sort(u64, applied.items, {}, struct {
                fn lessThan(_: void, a: u64, b: u64) bool {
                    return a > b;
                }
            }.lessThan);

            var rolled_back: usize = 0;
            const to_rollback = @min(steps, applied.items.len);

            // 回滚最近的 N 个迁移
            for (applied.items[0..to_rollback]) |version| {
                // 查找对应的迁移
                var migration: ?*const Migration = null;
                for (self.migrations.items) |*m| {
                    if (m.version == version) {
                        migration = m;
                        break;
                    }
                }

                if (migration) |m| {
                    try self.executeMigration(m, .down);
                    rolled_back += 1;

                    std.log.info("Rolled back migration: {d}_{s}", .{ m.version, m.name });
                } else {
                    std.log.warn("Migration {d} not found in registered migrations", .{version});
                }
            }

            return rolled_back;
        }

        /// 获取迁移状态
        ///
        /// ## 返回
        /// 返回已应用和待应用的迁移信息
        pub fn status(self: *Self) !MigrationStatus {
            try self.ensureMigrationsTable();

            var applied = try self.getAppliedVersions();
            defer applied.deinit(self.allocator);

            var pending_count: usize = 0;
            for (self.migrations.items) |migration| {
                var is_applied = false;
                for (applied.items) |v| {
                    if (v == migration.version) {
                        is_applied = true;
                        break;
                    }
                }
                if (!is_applied) {
                    pending_count += 1;
                }
            }

            return MigrationStatus{
                .total = self.migrations.items.len,
                .applied = applied.items.len,
                .pending = pending_count,
            };
        }

        /// 重置所有迁移 (仅用于测试!)
        ///
        /// 警告: 这将删除迁移历史表,请谨慎使用
        pub fn reset(self: *Self) !void {
            const sql = try std.fmt.allocPrint(
                self.allocator,
                "DROP TABLE IF EXISTS {s}",
                .{self.migrations_table},
            );
            defer self.allocator.free(sql);

            try self.db.exec(sql, &.{});
        }
    };
}

/// 迁移状态
pub const MigrationStatus = struct {
    total: usize, // 总迁移数
    applied: usize, // 已应用数
    pending: usize, // 待应用数
};

// =============================================================================
// 单元测试
// =============================================================================

const testing = std.testing;

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

// 注意: 完整的集成测试需要真实的数据库连接
// 这里只提供了基础的单元测试
// 集成测试应该在 tests/ 目录中单独编写
