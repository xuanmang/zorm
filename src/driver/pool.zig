// src/driver/pool.zig
// ZORM 连接池管理
// 提供线程安全的连接池,支持连接复用、生命周期管理和并发控制

const std = @import("std");
const Allocator = std.mem.Allocator;
const connection = @import("connection.zig");
const Connection = connection.Connection;
const Error = @import("../error.zig").Error;

/// 连接池配置
pub const PoolConfig = struct {
    /// 最大打开连接数
    max_open_conns: u32 = 25,

    /// 最大空闲连接数
    max_idle_conns: u32 = 25,

    /// 连接最大生命周期 (秒)
    /// 0 表示无限制
    conn_max_lifetime: u64 = 300,

    /// 空闲连接超时时间 (秒)
    /// 0 表示无限制
    conn_max_idle_time: u64 = 60,

    /// 获取连接的超时时间 (毫秒)
    /// 0 表示无限制,立即返回错误
    acquire_timeout_ms: u64 = 5000,
};

/// 连接池元数据
const PooledConnection = struct {
    /// 实际的数据库连接
    conn: *anyopaque,

    /// 连接创建时间 (纳秒时间戳)
    created_at: i128,

    /// 最后使用时间 (纳秒时间戳)
    last_used_at: i128,

    /// 连接是否正在使用
    in_use: bool,
};

/// 连接池泛型结构
///
/// 通过 comptime Driver 实现编译时特化,为每种数据库驱动生成专用连接池。
///
/// 特性:
/// - 线程安全 (使用 Mutex 保护共享状态)
/// - 连接复用 (减少连接创建开销)
/// - 生命周期管理 (自动清理过期连接)
/// - 并发控制 (限制最大连接数)
///
/// 使用示例:
/// ```zig
/// const PostgresPool = Pool(PostgresDriver);
/// const pool = try PostgresPool.init(allocator, "host=localhost", .{
///     .max_open_conns = 10,
///     .max_idle_conns = 5,
///     .conn_max_lifetime = 300,
/// });
/// defer pool.deinit();
///
/// const conn = try pool.acquire();
/// defer pool.release(conn) catch {};
///
/// const result = try conn.exec("INSERT INTO ...", &.{});
/// ```
pub fn Pool(comptime Driver: type) type {
    return struct {
        const Self = @This();
        const Conn = Connection(Driver);

        /// 内存分配器
        allocator: Allocator,

        /// 所有连接的元数据列表
        pool_metadata: std.array_list.Managed(PooledConnection),

        /// 可用连接的索引列表
        available_indices: std.array_list.Managed(usize),

        /// 线程互斥锁 (保护并发访问)
        mutex: std.Thread.Mutex,

        /// 连接池配置
        config: PoolConfig,

        /// DSN 连接字符串 (用于创建新连接)
        dsn: []const u8,

        /// 当前打开的连接数
        open_count: u32,

        /// 初始化连接池
        ///
        /// 参数:
        /// - allocator: 内存分配器
        /// - dsn: 数据库连接字符串
        /// - config: 连接池配置
        ///
        /// 返回:
        /// - *Self: 连接池实例指针
        ///
        /// 错误:
        /// - error.OutOfMemory: 内存分配失败
        pub fn init(allocator: Allocator, dsn: []const u8, config: PoolConfig) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            const dsn_copy = try allocator.dupe(u8, dsn);
            errdefer allocator.free(dsn_copy);

            self.* = Self{
                .allocator = allocator,
                .pool_metadata = std.array_list.Managed(PooledConnection).init(allocator),
                .available_indices = std.array_list.Managed(usize).init(allocator),
                .mutex = .{},
                .config = config,
                .dsn = dsn_copy,
                .open_count = 0,
            };

            return self;
        }

        /// 获取连接
        ///
        /// 从连接池中获取一个可用连接。如果没有可用连接且未达到最大连接数,
        /// 则创建新连接。如果连接池耗尽,根据配置返回错误或等待。
        ///
        /// 返回:
        /// - *Conn: 数据库连接
        ///
        /// 错误:
        /// - error.ConnectionPoolExhausted: 连接池耗尽
        /// - error.ConnectionTimeout: 获取连接超时
        /// - error.ConnectionFailed: 创建连接失败
        /// - error.OutOfMemory: 内存分配失败
        pub fn acquire(self: *Self) !*Conn {
            self.mutex.lock();
            defer self.mutex.unlock();

            const now = std.time.nanoTimestamp();

            // 1. 检查是否有可用连接
            while (self.available_indices.items.len > 0) {
                const idx = self.available_indices.pop() orelse break;
                var metadata = &self.pool_metadata.items[idx];

                // 检查连接是否过期
                if (self.isConnectionExpired(metadata, now)) {
                    try self.closeConnectionAtIndex(idx);
                    continue;
                }

                // 标记为使用中
                metadata.in_use = true;
                metadata.last_used_at = now;

                const conn: *Conn = @ptrCast(@alignCast(metadata.conn));
                return conn;
            }

            // 2. 没有可用连接,检查是否可以创建新连接
            if (self.open_count >= self.config.max_open_conns) {
                return Error.ConnectionPoolExhausted;
            }

            // 3. 创建新连接
            const conn = try self.createConnection();
            errdefer self.allocator.destroy(conn);

            // 4. 添加到连接池
            const metadata = PooledConnection{
                .conn = conn,
                .created_at = now,
                .last_used_at = now,
                .in_use = true,
            };

            try self.pool_metadata.append(metadata);
            self.open_count += 1;

            return conn;
        }

        /// 释放连接
        ///
        /// 将连接归还到连接池供后续使用。如果空闲连接数超过限制,
        /// 则关闭连接。
        ///
        /// 参数:
        /// - conn: 要释放的连接
        ///
        /// 错误:
        /// - error.ConnectionClosed: 连接不在池中
        pub fn release(self: *Self, conn: *Conn) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // 查找连接在池中的索引
            const conn_ptr: *anyopaque = conn;
            for (self.pool_metadata.items, 0..) |*metadata, i| {
                if (metadata.conn == conn_ptr) {
                    if (!metadata.in_use) {
                        return Error.ConnectionClosed;
                    }

                    // 检查空闲连接数是否超过限制
                    const idle_count = self.countIdleConnections();
                    if (idle_count >= self.config.max_idle_conns) {
                        // 关闭连接
                        try self.closeConnectionAtIndex(i);
                        return;
                    }

                    // 标记为可用
                    metadata.in_use = false;
                    metadata.last_used_at = std.time.nanoTimestamp();
                    try self.available_indices.append(i);
                    return;
                }
            }

            return Error.ConnectionClosed;
        }

        /// 清理连接池
        ///
        /// 关闭所有连接并释放资源。
        pub fn deinit(self: *Self) void {
            self.mutex.lock();

            // 关闭所有连接
            for (self.pool_metadata.items) |*metadata| {
                const conn: *Conn = @ptrCast(@alignCast(metadata.conn));
                conn.close() catch {};
                // 释放连接内存
                self.allocator.destroy(conn);
            }

            self.pool_metadata.deinit();
            self.available_indices.deinit();

            const allocator = self.allocator;
            allocator.free(self.dsn);

            self.mutex.unlock();
            allocator.destroy(self);
        }

        /// 创建新连接
        ///
        /// 内部方法,创建一个新的数据库连接。
        ///
        /// 返回:
        /// - *Conn: 新创建的连接
        ///
        /// 错误:
        /// - error.ConnectionFailed: 连接失败
        /// - error.OutOfMemory: 内存分配失败
        fn createConnection(self: *Self) !*Conn {
            // 创建 Driver 实例
            var driver = try Driver.connect(self.allocator, self.dsn);
            errdefer driver.close() catch {};

            // 创建 Connection 包装器
            const conn = try self.allocator.create(Conn);
            conn.* = Conn{
                .driver = driver,
                .allocator = self.allocator,
            };

            return conn;
        }

        /// 关闭指定索引的连接
        ///
        /// 内部方法,关闭并移除指定索引的连接。
        ///
        /// 参数:
        /// - index: 连接在 pool_metadata 中的索引
        fn closeConnectionAtIndex(self: *Self, index: usize) !void {
            const metadata = &self.pool_metadata.items[index];
            const conn: *Conn = @ptrCast(@alignCast(metadata.conn));

            // 关闭连接
            try conn.close();

            // 释放连接内存
            self.allocator.destroy(conn);

            // 从池中移除 (使用 swapRemove 保持 O(1) 复杂度)
            _ = self.pool_metadata.swapRemove(index);

            // 更新 available_indices (移除对应索引)
            for (self.available_indices.items, 0..) |idx, i| {
                if (idx == index) {
                    _ = self.available_indices.swapRemove(i);
                    break;
                } else if (idx == self.pool_metadata.items.len) {
                    // swapRemove 导致最后一个元素移动到了 index 位置
                    self.available_indices.items[i] = index;
                }
            }

            self.open_count -= 1;
        }

        /// 检查连接是否过期
        ///
        /// 根据配置的生命周期和空闲时间判断连接是否应该被清理。
        ///
        /// 参数:
        /// - metadata: 连接元数据
        /// - now: 当前时间戳 (纳秒)
        ///
        /// 返回:
        /// - true: 连接已过期
        /// - false: 连接仍然有效
        fn isConnectionExpired(self: *Self, metadata: *const PooledConnection, now: i128) bool {
            // 检查最大生命周期
            if (self.config.conn_max_lifetime > 0) {
                const lifetime_ns = @as(i128, @intCast(self.config.conn_max_lifetime)) * std.time.ns_per_s;
                if (now - metadata.created_at > lifetime_ns) {
                    return true;
                }
            }

            // 检查空闲超时 (仅对未使用的连接)
            if (!metadata.in_use and self.config.conn_max_idle_time > 0) {
                const idle_time_ns = @as(i128, @intCast(self.config.conn_max_idle_time)) * std.time.ns_per_s;
                if (now - metadata.last_used_at > idle_time_ns) {
                    return true;
                }
            }

            return false;
        }

        /// 统计空闲连接数
        ///
        /// 内部方法,用于检查是否超过最大空闲连接数限制。
        ///
        /// 返回:
        /// - u32: 当前空闲连接数
        fn countIdleConnections(self: *Self) u32 {
            var count: u32 = 0;
            for (self.pool_metadata.items) |metadata| {
                if (!metadata.in_use) {
                    count += 1;
                }
            }
            return count;
        }

        /// 清理过期连接
        ///
        /// 主动清理所有过期的空闲连接,通常在后台定期调用。
        ///
        /// 返回:
        /// - usize: 清理的连接数
        pub fn cleanupExpiredConnections(self: *Self) !usize {
            self.mutex.lock();
            defer self.mutex.unlock();

            const now = std.time.nanoTimestamp();
            var cleaned: usize = 0;

            var i: usize = 0;
            while (i < self.pool_metadata.items.len) {
                const metadata = &self.pool_metadata.items[i];

                // 只清理未使用的连接
                if (!metadata.in_use and self.isConnectionExpired(metadata, now)) {
                    try self.closeConnectionAtIndex(i);
                    cleaned += 1;
                    // closeConnectionAtIndex 会使用 swapRemove,所以不需要递增 i
                } else {
                    i += 1;
                }
            }

            return cleaned;
        }

        /// 获取连接池统计信息
        ///
        /// 返回连接池的当前状态,用于监控和诊断。
        pub fn stats(self: *Self) PoolStats {
            self.mutex.lock();
            defer self.mutex.unlock();

            var in_use: u32 = 0;
            for (self.pool_metadata.items) |metadata| {
                if (metadata.in_use) {
                    in_use += 1;
                }
            }

            return PoolStats{
                .total_connections = self.open_count,
                .idle_connections = self.open_count - in_use,
                .in_use_connections = in_use,
                .max_open_conns = self.config.max_open_conns,
                .max_idle_conns = self.config.max_idle_conns,
            };
        }
    };
}

/// 连接池统计信息
pub const PoolStats = struct {
    /// 总连接数
    total_connections: u32,

    /// 空闲连接数
    idle_connections: u32,

    /// 使用中连接数
    in_use_connections: u32,

    /// 最大打开连接数
    max_open_conns: u32,

    /// 最大空闲连接数
    max_idle_conns: u32,
};
