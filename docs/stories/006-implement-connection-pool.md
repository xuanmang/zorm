# Story 006: 实现连接池管理

## Status
Ready for Review

## Story
**As a** ZORM 开发者,
**I want** 高效的数据库连接池管理,
**so that** 能够复用连接,提高并发性能,减少连接开销

## Acceptance Criteria
1. 实现 Pool(comptime Driver: type) 泛型连接池
2. 支持配置最大连接数和空闲连接数
3. 实现 acquire() 获取连接和 release() 释放连接
4. 支持连接生命周期管理和超时控制
5. 线程安全,使用 Mutex 保护共享状态
6. 连接池耗尽时返回错误
7. 编写并发测试验证线程安全性

## Tasks / Subtasks
- [x] 创建 src/driver/pool.zig 文件
  - [x] 定义 Pool(comptime Driver: type) 泛型结构体
  - [x] 定义 PoolConfig 配置结构体
  - [x] 添加连接列表和可用连接列表
  - [x] 添加 Mutex 保证线程安全
- [x] 实现连接池管理
  - [x] init() 初始化连接池
  - [x] acquire() 获取连接
  - [x] release() 释放连接
  - [x] createConnection() 创建新连接
  - [x] closeConnection() 关闭连接
  - [x] deinit() 清理连接池
- [x] 实现连接生命周期管理
  - [x] 连接最大生命周期检查
  - [x] 空闲连接超时清理
  - [x] 连接健康检查 (通过 isConnectionExpired 实现)
- [x] 编写单元测试和并发测试
  - [x] 测试连接获取和释放
  - [x] 测试连接池耗尽场景
  - [x] 测试多线程并发访问
  - [x] 测试连接超时和清理

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md

### 架构参考
- [docs/architecture.md#ConnectionManager](architecture.md#核心模块详细设计) (行 294-366)

### 依赖项
- `src/driver/connection.zig`
- `src/error.zig`

## Code Examples
```zig
pub fn Pool(comptime Driver: type) type {
    return struct {
        const Self = @This();
        const Conn = Connection(Driver);

        allocator: Allocator,
        connections: std.ArrayList(*Conn),
        available: std.ArrayList(*Conn),
        mutex: std.Thread.Mutex,
        config: PoolConfig,

        pub const PoolConfig = struct {
            max_open_conns: u32 = 25,
            max_idle_conns: u32 = 25,
            conn_max_lifetime: u64 = 300,
        };

        pub fn init(allocator: Allocator, config: PoolConfig) !*Self {
            // TODO: 实现
        }

        pub fn acquire(self: *Self) !*Conn {
            // TODO: 实现
        }

        pub fn release(self: *Self, conn: *Conn) !void {
            // TODO: 实现
        }
    };
}
```

## File List
| File | Status | Description |
|------|--------|-------------|
| src/driver/pool.zig | ✅ Created | 连接池核心实现 (433 行) |
| tests/pool_test.zig | ✅ Created | 单元测试和并发测试 (426 行) |
| src/zorm.zig | ✅ Modified | 导出 Pool/PoolConfig/PoolStats 类型 |
| build.zig | ✅ Modified | 添加 pool 测试配置 |

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
| 2025-01-17 | 2.0 | 完成连接池实现和测试 | James 💻 |

## Dev Agent Record

### 实现概述
成功实现线程安全的连接池管理系统，支持连接复用、生命周期管理和并发控制。

### 核心实现 (src/driver/pool.zig - 433 行)

#### 1. 数据结构设计
- **Pool(comptime Driver: type)**: 泛型连接池，编译时特化
- **PooledConnection**: 连接元数据，包含创建时间、最后使用时间、使用状态
- **PoolConfig**: 配置参数 (max_open_conns, max_idle_conns, conn_max_lifetime, conn_max_idle_time, acquire_timeout_ms)
- **PoolStats**: 统计信息 (total_connections, idle_connections, in_use_connections)

#### 2. 核心功能
- **init()**: 初始化连接池，分配内存，复制 DSN
- **acquire()**: 获取连接，优先复用空闲连接，自动清理过期连接
- **release()**: 释放连接，检查空闲连接数限制，必要时关闭连接
- **deinit()**: 清理所有连接，释放资源
- **cleanupExpiredConnections()**: 主动清理过期连接
- **stats()**: 返回连接池统计信息

#### 3. 线程安全
- 使用 `std.Thread.Mutex` 保护所有共享状态
- 所有公共方法都进行互斥锁保护
- 使用 `defer` 确保锁总是被释放

#### 4. 内存管理
- 使用 `std.array_list.Managed` 管理连接列表 (Zig 0.15.2 API)
- 使用 `swapRemove` 保持 O(1) 删除复杂度
- 正确处理 `errdefer` 和资源清理顺序

### 测试覆盖 (tests/pool_test.zig - 426 行)

#### 单元测试 (8 个)
1. ✅ init and deinit: 基本初始化和清理
2. ✅ acquire single connection: 单连接获取
3. ✅ acquire and release multiple connections: 多连接复用
4. ✅ connection pool exhaustion: 连接池耗尽场景
5. ✅ max idle connections limit: 空闲连接数限制
6. ✅ connection lifecycle expiration: 连接过期清理
7. ✅ stats reporting: 统计信息准确性
8. ✅ double release error: 重复释放检测

#### 并发测试 (3 个)
1. ✅ concurrent acquire and release: 10 线程 × 20 次操作
2. ✅ stress test with many threads: 20 线程 × 100 次操作
3. ✅ cleanup expired connections during concurrent access: 5 个 worker + 1 个 cleaner 并发运行

#### Mock Driver
实现完整的 MockDriver 用于测试，支持：
- connect/exec/query/close 操作
- 连接状态跟踪 (is_closed, exec_count)
- 错误场景模拟

### 技术挑战与解决方案

#### 1. Zig 0.15.2 API 兼容性
**问题**: ArrayList API 在 Zig 0.15.2 发生重大变化
- `std.ArrayList(T).init(allocator)` 不再存在
- `std.ArrayList(T)` 没有 `.Managed` 成员

**解决方案**:
```zig
// 旧 API (不可用)
connections: std.ArrayList(*Conn).init(allocator)

// 新 API (Zig 0.15.2)
connections: std.array_list.Managed(*Conn) = std.array_list.Managed(*Conn).init(allocator)
```

#### 2. 时间戳类型
**问题**: `std.time.nanoTimestamp()` 返回 `i128`，不是 `i64`

**解决方案**:
```zig
// PooledConnection 使用 i128
created_at: i128,
last_used_at: i128,

// isConnectionExpired 参数也使用 i128
fn isConnectionExpired(self: *Self, metadata: *const PooledConnection, now: i128) bool
```

#### 3. Sleep API 变更
**问题**: `std.time.sleep()` 已移至 `std.Thread.sleep()`

**解决方案**: 更新所有测试代码使用 `std.Thread.sleep()`

#### 4. Const 限定符
**问题**: `Driver.connect()` 返回值不能是 const

**解决方案**:
```zig
// 错误
const driver = try Driver.connect(self.allocator, self.dsn);

// 正确
var driver = try Driver.connect(self.allocator, self.dsn);
```

#### 5. 内存安全 (deinit 顺序)
**问题**: 在 `allocator.destroy(self)` 后调用 `mutex.unlock()` 导致段错误

**解决方案**:
```zig
// 保存 allocator 引用
const allocator = self.allocator;
allocator.free(self.dsn);

// 先解锁，再销毁
self.mutex.unlock();
allocator.destroy(self);
```

#### 6. Optional 类型处理
**问题**: `pop()` 返回 `?T` 而非 `T`

**解决方案**:
```zig
const idx = self.available_indices.pop() orelse break;
```

#### 7. 连接过期测试时序
**问题**: `conn_max_lifetime = 0` 表示无限制，不是立即过期

**解决方案**: 使用 `conn_max_lifetime = 1` (1秒) + 睡眠 1.1 秒

### 测试结果
```bash
$ zig build test-pool
✅ 11/11 测试通过
- 8 个单元测试
- 3 个并发测试
- 0 个失败
```

### 技术亮点
1. **编译时泛型**: 使用 `comptime Driver: type` 实现零开销抽象
2. **线程安全**: Mutex + defer 模式确保无死锁
3. **内存安全**: 显式 Allocator + errdefer 模式
4. **O(1) 操作**: 使用 swapRemove 和索引列表
5. **生命周期管理**: 自动过期清理 + 手动触发清理
6. **并发测试**: 验证多线程环境下的正确性和性能

## QA Results
_待填写_
