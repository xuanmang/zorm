# 设计文档：Zig 0.15 ArrayList API 迁移

## 概述

本文档详细说明从 Zig 0.14 的 `ArrayList(T).init()` API 迁移到 Zig 0.15 的新 API 的设计决策和实现细节。

## 问题分析

### Zig 0.15 的 ArrayList 类型系统

Zig 0.15 引入了两种 ArrayList 类型：

#### 1. Aligned (新的默认类型)

```zig
pub fn Aligned(comptime T: type, comptime alignment: ?mem.Alignment) type {
    return struct {
        items: Slice = &[_]T{},
        capacity: usize = 0,

        pub const empty: Self = .{
            .items = &.{},
            .capacity = 0,
        };

        pub fn initCapacity(gpa: Allocator, num: usize) Allocator.Error!Self {
            var self = Self{};
            try self.ensureTotalCapacityPrecise(gpa, num);
            return self;
        }

        // 所有方法需要显式传递 allocator
        pub fn append(self: *Self, allocator: Allocator, item: T) Allocator.Error!void { ... }
        pub fn deinit(self: *Self, allocator: Allocator) void { ... }
    };
}

// 类型别名
pub const ArrayList = Aligned;
```

**特点**：
- 不存储 allocator
- 无 `init()` 方法
- 所有操作需要显式传递 allocator
- 有默认值和 `empty` 常量
- 有 `initCapacity()` 用于预分配

#### 2. AlignedManaged (兼容旧 API)

```zig
/// Deprecated.
pub fn AlignedManaged(comptime T: type, comptime alignment: ?mem.Alignment) type {
    return struct {
        items: Slice,
        capacity: usize,
        allocator: Allocator,  // 存储 allocator

        pub fn init(gpa: Allocator) Self {
            return Self{
                .items = &[_]T{},
                .capacity = 0,
                .allocator = gpa,
            };
        }

        // 方法不需要传递 allocator
        pub fn append(self: *Self, item: T) Allocator.Error!void { ... }
        pub fn deinit(self: *Self) void { ... }
    };
}

// 类型别名
pub const ArrayListManaged = AlignedManaged;
```

**特点**：
- 存储 allocator（额外 16 字节开销）
- 有 `init()` 方法（向后兼容）
- 方法不需要传递 allocator
- 已标记为 deprecated

### API 对比表

| 特性 | Aligned (新) | AlignedManaged (旧) |
|------|-------------|-------------------|
| 存储 allocator | ❌ | ✅ (16 bytes) |
| init() 方法 | ❌ | ✅ |
| empty 常量 | ✅ | ❌ |
| initCapacity() | ✅ | ✅ |
| 方法签名 | `append(self, allocator, item)` | `append(self, item)` |
| 灵活性 | 可用不同 allocator | 固定 allocator |
| 状态 | 推荐 | Deprecated |

## 设计决策

### 决策 1：选择 Aligned 而非 Managed

**选择**: 使用 `ArrayList(T)` (Aligned) ✅

**理由**:

1. **符合语言方向**: Managed 已被标记为 deprecated
2. **性能优势**: 减少 16 字节存储开销（每个 ArrayList）
3. **灵活性**: 允许不同操作使用不同 allocator
4. **代码已有 allocator**: SelectQuery 等结构已存储 allocator 字段
5. **清晰的所有权**: 显式传递 allocator 使内存管理更透明

**权衡**:
- ✅ 更好的长期维护性
- ✅ 符合 Zig 零成本抽象原则
- ⚠️ 需要修改所有 ArrayList 方法调用（但本项目已经这样做）

### 决策 2：初始化策略

#### 场景 A: 空列表初始化

**当前代码**:
```zig
self.* = .{
    .columns = std.ArrayList([]const u8).init(allocator),
    .where_clauses = std.ArrayList(WhereClause).init(allocator),
    // ...
};
```

**修复方案**:
```zig
self.* = .{
    .columns = std.ArrayList([]const u8){},
    .where_clauses = std.ArrayList(WhereClause){},
    // ...
};
```

**备选方案**:
```zig
self.* = .{
    .columns = .{},  // 类型推导
    .where_clauses = .{},
    // ...
};
```

**选择**: 使用 `ArrayList(T){}` ✅

**理由**:
- 更明确的类型信息
- 避免编译器推导歧义
- 与项目现有代码风格一致

#### 场景 B: 预分配容量初始化

**当前代码**:
```zig
const estimated_size = self.estimateSQLSize();
var buf = std.ArrayList(u8).init(allocator);
errdefer buf.deinit();
try buf.ensureTotalCapacity(estimated_size);
```

**修复方案 1** (两步初始化):
```zig
const estimated_size = self.estimateSQLSize();
var buf = std.ArrayList(u8){};
errdefer buf.deinit(allocator);
try buf.ensureTotalCapacity(allocator, estimated_size);
```

**修复方案 2** (一步初始化):
```zig
const estimated_size = self.estimateSQLSize();
var buf = try std.ArrayList(u8).initCapacity(allocator, estimated_size);
errdefer buf.deinit(allocator);
```

**选择**: 使用方案 1（两步初始化）✅

**理由**:
- 保持代码结构一致性
- 更清晰的错误处理（errdefer 位置）
- 最小化代码变更
- `initCapacity` 可能分配比 estimated_size 更多内存

### 决策 3：deinit() 调用

**影响**: 所有 `buf.deinit()` 需要改为 `buf.deinit(allocator)`

**示例**:
```zig
// 旧代码
defer buf.deinit();

// 新代码
defer buf.deinit(allocator);
```

**注意**: 本项目代码已经正确使用了 `deinit(allocator)`，无需修改。

## 实现计划

### 修改范围

```
src/query/query.zig
├── Line 87-93: SelectQuery.init()
│   ├── columns: ArrayList([]const u8)
│   ├── where_clauses: ArrayList(WhereClause)
│   ├── join_clauses: ArrayList(JoinClause)
│   ├── order_by_clauses: ArrayList(OrderByClause)
│   ├── group_by_columns: ArrayList([]const u8)
│   └── having_clauses: ArrayList(HavingClause)
├── Line 948: InsertQuery.buildSQL()
│   └── buf: ArrayList(u8)
├── Line 1464: UpdateQuery.buildSQL()
│   └── buf: ArrayList(u8)
└── Line 1899: DeleteQuery.buildSQL()
    └── buf: ArrayList(u8)
```

### 具体修改

#### 1. SelectQuery.init() (第 84-97 行)

```diff
 self.* = .{
     .allocator = allocator,
     .db = db,
-    .columns = std.ArrayList([]const u8).init(allocator),
+    .columns = std.ArrayList([]const u8){},
     .table_name = table_name,
-    .where_clauses = std.ArrayList(WhereClause).init(allocator),
+    .where_clauses = std.ArrayList(WhereClause){},
-    .join_clauses = std.ArrayList(JoinClause).init(allocator),
+    .join_clauses = std.ArrayList(JoinClause){},
-    .order_by_clauses = std.ArrayList(OrderByClause).init(allocator),
+    .order_by_clauses = std.ArrayList(OrderByClause){},
-    .group_by_columns = std.ArrayList([]const u8).init(allocator),
+    .group_by_columns = std.ArrayList([]const u8){},
-    .having_clauses = std.ArrayList(HavingClause).init(allocator),
+    .having_clauses = std.ArrayList(HavingClause){},
     .limit_value = null,
     .offset_value = null,
     .distinct_value = false,
 };
```

#### 2. InsertQuery.buildSQL() (第 946-950 行)

```diff
 // AC1.5.2: 内存优化 - 预估并预分配 SQL 缓冲区
 const estimated_size = self.estimateSQLSize();
-var buf = std.ArrayList(u8).init(allocator);
+var buf = std.ArrayList(u8){};
 errdefer buf.deinit();
-try buf.ensureTotalCapacity(estimated_size);
+try buf.ensureTotalCapacity(allocator, estimated_size);
```

#### 3. UpdateQuery.buildSQL() (第 1462-1466 行)

```diff
 const estimated_size = self.estimateSQLSize();
-var buf = std.ArrayList(u8).init(allocator);
+var buf = std.ArrayList(u8){};
 errdefer buf.deinit();
-try buf.ensureTotalCapacity(estimated_size);
+try buf.ensureTotalCapacity(allocator, estimated_size);
```

#### 4. DeleteQuery.buildSQL() (第 1897-1901 行)

```diff
 const estimated_size = self.estimateSQLSize();
-var buf = std.ArrayList(u8).init(allocator);
+var buf = std.ArrayList(u8){};
 errdefer buf.deinit();
-try buf.ensureTotalCapacity(estimated_size);
+try buf.ensureTotalCapacity(allocator, estimated_size);
```

### 验证检查

#### 编译时检查

```bash
# 1. 检查语法错误
zig fmt --check src/query/query.zig

# 2. 检查编译错误
zig build-lib src/query/query.zig -femit-bin=/dev/null

# 3. 运行测试
zig build test
```

#### 运行时检查

测试应覆盖：
1. ✅ 空 ArrayList 初始化
2. ✅ append() 操作（需要传递 allocator）
3. ✅ appendSlice() 操作
4. ✅ deinit() 清理
5. ✅ 预分配容量场景

### 潜在问题排查

#### 问题 1: 其他文件的 ArrayList.init()

**检查命令**:
```bash
rg "ArrayList.*\.init\(" src/ --type zig
```

**预期**: 应该只在 `query.zig` 中发现问题

#### 问题 2: errdefer 和 defer 的 allocator

**检查命令**:
```bash
rg "\.deinit\(\)" src/query/query.zig
```

**预期**: 所有 `deinit()` 应该带 `allocator` 参数

#### 问题 3: ensureTotalCapacity 参数

**检查命令**:
```bash
rg "ensureTotalCapacity\(" src/query/query.zig
```

**预期**: 所有调用应该传递 `allocator` 作为第一个参数

## 性能影响分析

### 内存占用

**旧 API (Managed)**:
```zig
struct SelectQuery {
    allocator: Allocator,  // 16 bytes
    columns: ArrayListManaged([]const u8) {
        items: [][]const u8,      // 16 bytes
        capacity: usize,           // 8 bytes
        allocator: Allocator,      // 16 bytes (重复!)
    },
    // ... 5 个其他 ArrayList
}
```

**新 API (Aligned)**:
```zig
struct SelectQuery {
    allocator: Allocator,  // 16 bytes
    columns: ArrayList([]const u8) {
        items: [][]const u8,      // 16 bytes
        capacity: usize,           // 8 bytes
        // 无 allocator 字段
    },
    // ... 5 个其他 ArrayList
}
```

**节省**: 每个 ArrayList 节省 16 字节
- SelectQuery: 6 个 ArrayList → 节省 96 字节
- InsertQuery/UpdateQuery/DeleteQuery: 各节省 16 字节（1 个 ArrayList）

### 运行时性能

- ✅ **初始化更快**: 无需复制 allocator 指针
- ✅ **更好的缓存局部性**: 结构体更紧凑
- ⚠️ **方法调用**: 需要传递额外参数（但编译器会优化）

### 编译时性能

- ✅ **类型推导更简单**: 无 allocator 字段
- ✅ **更好的内联机会**: 函数参数明确

## 向后兼容性

### API 层面

✅ **完全兼容**: 所有公共 API 保持不变
- SelectQuery、InsertQuery、UpdateQuery、DeleteQuery 的公共接口不变
- 用户代码无需修改

### ABI 层面

⚠️ **不兼容**: 结构体布局改变
- 如果有外部代码直接访问 ArrayList 字段，需要重新编译

### 行为层面

✅ **完全一致**: 功能行为不变
- 所有测试应该继续通过
- 内存管理语义相同

## 迁移指南

### 对于未来修改

如果需要添加新的 ArrayList 字段：

```zig
// ✅ 推荐
pub const MyStruct = struct {
    allocator: Allocator,
    items: std.ArrayList(Item),  // 使用 Aligned

    pub fn init(allocator: Allocator) MyStruct {
        return .{
            .allocator = allocator,
            .items = std.ArrayList(Item){},  // 空初始化
        };
    }

    pub fn addItem(self: *MyStruct, item: Item) !void {
        try self.items.append(self.allocator, item);  // 显式传递 allocator
    }

    pub fn deinit(self: *MyStruct) void {
        self.items.deinit(self.allocator);  // 显式传递 allocator
    }
};
```

```zig
// ❌ 避免（已弃用）
pub const MyStruct = struct {
    items: std.ArrayListManaged(Item),  // 不推荐

    pub fn init(allocator: Allocator) MyStruct {
        return .{
            .items = std.ArrayListManaged(Item).init(allocator),
        };
    }

    pub fn addItem(self: *MyStruct, item: Item) !void {
        try self.items.append(item);  // allocator 隐式存储
    }

    pub fn deinit(self: *MyStruct) void {
        self.items.deinit();  // allocator 隐式存储
    }
};
```

## 总结

本次迁移是**零成本抽象**的典型案例：
- ✅ 更好的性能（减少内存占用）
- ✅ 更灵活的 API（可用不同 allocator）
- ✅ 更清晰的所有权语义
- ✅ 完全的向后兼容（公共 API 不变）
- ✅ 符合 Zig 语言设计方向

这正是 Zig 语言哲学的体现：**显式优于隐式，零成本抽象优于便利性**。
