# Story 006: 实现连接池管理

## Status
Approved

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
- [ ] 创建 src/driver/pool.zig 文件
  - [ ] 定义 Pool(comptime Driver: type) 泛型结构体
  - [ ] 定义 PoolConfig 配置结构体
  - [ ] 添加连接列表和可用连接列表
  - [ ] 添加 Mutex 保证线程安全
- [ ] 实现连接池管理
  - [ ] init() 初始化连接池
  - [ ] acquire() 获取连接
  - [ ] release() 释放连接
  - [ ] createConnection() 创建新连接
  - [ ] closeConnection() 关闭连接
  - [ ] deinit() 清理连接池
- [ ] 实现连接生命周期管理
  - [ ] 连接最大生命周期检查
  - [ ] 空闲连接超时清理
  - [ ] 连接健康检查
- [ ] 编写单元测试和并发测试
  - [ ] 测试连接获取和释放
  - [ ] 测试连接池耗尽场景
  - [ ] 测试多线程并发访问
  - [ ] 测试连接超时和清理

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

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |

## Dev Agent Record
_待填写_

## QA Results
_待填写_
