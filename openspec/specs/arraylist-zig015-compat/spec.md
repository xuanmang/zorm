# arraylist-zig015-compat Specification

## Purpose
TBD - created by archiving change fix-zig-015-arraylist-api. Update Purpose after archive.
## Requirements
### Requirement: 使用 Zig 0.15 的 ArrayList Aligned API

查询构建器模块 MUST 使用 Zig 0.15 的新 ArrayList API（Aligned 类型）而非已弃用的 Managed API。

**Rationale**: Zig 0.15 将 `ArrayList(T).init()` 方法移除，引入了新的 Aligned 类型系统。Aligned 类型不存储 allocator，提供更好的性能和灵活性，符合 Zig 的零成本抽象原则。

#### Scenario: 空 ArrayList 初始化

**Given** 需要初始化一个空的 ArrayList
**When** 在结构体字段或局部变量中初始化
**Then** MUST 使用 `ArrayList(T){}` 或 `ArrayList(T).empty` 而非 `ArrayList(T).init(allocator)`

```zig
// ✅ 正确
self.* = .{
    .columns = std.ArrayList([]const u8){},
    .where_clauses = std.ArrayList(WhereClause){},
};

// ✅ 也正确
var list = std.ArrayList(Item).empty;

// ❌ 错误（Zig 0.15 不支持）
.columns = std.ArrayList([]const u8).init(allocator),
```

#### Scenario: 预分配容量初始化

**Given** 需要初始化一个预分配容量的 ArrayList
**When** 知道预期元素数量
**Then** SHOULD 使用 `ArrayList(T).initCapacity(allocator, size)` 或先初始化为空再调用 `ensureTotalCapacity(allocator, size)`

```zig
// ✅ 推荐（一步初始化）
var buf = try std.ArrayList(u8).initCapacity(allocator, 1024);

// ✅ 也可以（两步初始化）
var buf = std.ArrayList(u8){};
try buf.ensureTotalCapacity(allocator, 1024);

// ❌ 错误
var buf = std.ArrayList(u8).init(allocator);
```

### Requirement: ArrayList 方法调用显式传递 Allocator

所有 ArrayList 的方法调用 MUST 显式传递 allocator 参数。

**Rationale**: Zig 0.15 的 Aligned 类型不存储 allocator，所有内存操作需要显式提供 allocator，确保内存管理的透明性。

#### Scenario: append() 方法调用

**Given** 需要向 ArrayList 添加元素
**When** 调用 append() 方法
**Then** MUST 显式传递 allocator 参数

```zig
// ✅ 正确
try list.append(allocator, item);
try list.appendSlice(allocator, items);

// ❌ 错误（Zig 0.15 不支持）
try list.append(item);
```

#### Scenario: deinit() 方法调用

**Given** 需要释放 ArrayList 内存
**When** 调用 deinit() 方法
**Then** MUST 显式传递 allocator 参数

```zig
// ✅ 正确
defer list.deinit(allocator);
errdefer list.deinit(allocator);

// ❌ 错误
defer list.deinit();
```

#### Scenario: ensureTotalCapacity() 方法调用

**Given** 需要确保 ArrayList 有足够容量
**When** 调用 ensureTotalCapacity() 方法
**Then** MUST 显式传递 allocator 参数作为第一个参数

```zig
// ✅ 正确
try buf.ensureTotalCapacity(allocator, estimated_size);

// ❌ 错误
try buf.ensureTotalCapacity(estimated_size);
```

### Requirement: SelectQuery 初始化使用空 ArrayList

`SelectQuery.init()` 方法 MUST 将所有 ArrayList 字段初始化为空列表。

**Rationale**: 修复 `src/query/query.zig:87-93` 的编译错误，确保与 Zig 0.15 兼容。

#### Scenario: SelectQuery 所有 ArrayList 字段初始化

**Given** SelectQuery 包含 6 个 ArrayList 字段
**When** 调用 `SelectQuery.init()`
**Then** 所有 ArrayList 字段 MUST 使用 `ArrayList(T){}` 初始化

受影响的字段：
- `columns: ArrayList([]const u8)`
- `where_clauses: ArrayList(WhereClause)`
- `join_clauses: ArrayList(JoinClause)`
- `order_by_clauses: ArrayList(OrderByClause)`
- `group_by_columns: ArrayList([]const u8)`
- `having_clauses: ArrayList(HavingClause)`

```zig
// src/query/query.zig:84-97
self.* = .{
    .allocator = allocator,
    .db = db,
    .columns = std.ArrayList([]const u8){},           // 修复
    .table_name = table_name,
    .where_clauses = std.ArrayList(WhereClause){},    // 修复
    .join_clauses = std.ArrayList(JoinClause){},      // 修复
    .order_by_clauses = std.ArrayList(OrderByClause){}, // 修复
    .group_by_columns = std.ArrayList([]const u8){},  // 修复
    .having_clauses = std.ArrayList(HavingClause){},  // 修复
    .limit_value = null,
    .offset_value = null,
    .distinct_value = false,
};
```

### Requirement: buildSQL() 方法使用空 ArrayList 初始化缓冲区

`InsertQuery.buildSQL()`, `UpdateQuery.buildSQL()`, `DeleteQuery.buildSQL()` 方法 MUST 将 SQL 缓冲区初始化为空 ArrayList。

**Rationale**: 修复 `src/query/query.zig:948, 1464, 1899` 的编译错误，确保与 Zig 0.15 兼容。

#### Scenario: InsertQuery.buildSQL() 缓冲区初始化

**Given** InsertQuery 需要构建 SQL 字符串
**When** 调用 `buildSQL()` 方法（第 946-950 行）
**Then** MUST 使用 `ArrayList(u8){}` 初始化缓冲区

```zig
// src/query/query.zig:946-950
const estimated_size = self.estimateSQLSize();
var buf = std.ArrayList(u8){};  // 修复
errdefer buf.deinit(allocator);
try buf.ensureTotalCapacity(allocator, estimated_size);  // 修复
```

#### Scenario: UpdateQuery.buildSQL() 缓冲区初始化

**Given** UpdateQuery 需要构建 SQL 字符串
**When** 调用 `buildSQL()` 方法（第 1462-1466 行）
**Then** MUST 使用 `ArrayList(u8){}` 初始化缓冲区

```zig
// src/query/query.zig:1462-1466
const estimated_size = self.estimateSQLSize();
var buf = std.ArrayList(u8){};  // 修复
errdefer buf.deinit(allocator);
try buf.ensureTotalCapacity(allocator, estimated_size);  // 修复
```

#### Scenario: DeleteQuery.buildSQL() 缓冲区初始化

**Given** DeleteQuery 需要构建 SQL 字符串
**When** 调用 `buildSQL()` 方法（第 1897-1901 行）
**Then** MUST 使用 `ArrayList(u8){}` 初始化缓冲区

```zig
// src/query/query.zig:1897-1901
const estimated_size = self.estimateSQLSize();
var buf = std.ArrayList(u8){};  // 修复
errdefer buf.deinit(allocator);
try buf.ensureTotalCapacity(allocator, estimated_size);  // 修复
```

### Requirement: 避免使用已弃用的 ArrayListManaged API

代码 MUST NOT 使用 `ArrayListManaged(T)` 或 `AlignedManaged(T, alignment)` 类型。

**Rationale**: 这些 API 在 Zig 0.15 中已标记为 deprecated，将在未来版本移除。使用新的 Aligned API 确保长期维护性。

#### Scenario: 禁止使用 Managed 类型

**Given** 需要声明或使用 ArrayList
**When** 编写新代码或修改现有代码
**Then** MUST NOT 使用 `ArrayListManaged` 或 `AlignedManaged`

```zig
// ✅ 正确
var list: std.ArrayList(T) = .{};

// ❌ 错误（已弃用）
var list: std.ArrayListManaged(T) = std.ArrayListManaged(T).init(allocator);
```

### Requirement: 编译时验证

所有修改 MUST 通过 Zig 0.15.2 的编译检查。

**Rationale**: 确保代码与 Zig 0.15 完全兼容，无编译错误和警告。

#### Scenario: zig build test 编译成功

**Given** 修复了所有 ArrayList API 问题
**When** 运行 `zig build test`
**Then** MUST 编译成功，无错误和警告

```bash
$ zig build test
Build Summary: 3/3 steps succeeded
test success
```

#### Scenario: 无其他潜在 ArrayList.init() 问题

**Given** 项目中可能存在其他 ArrayList.init() 使用
**When** 运行全局搜索 `rg "ArrayList.*\.init\(" src/`
**Then** SHOULD 确认其他文件无类似问题

### Requirement: 性能不回退

修复后的代码 MUST 保持或改善性能，不应引入性能回退。

**Rationale**: Zig 0.15 的 Aligned API 通过减少 allocator 存储开销提供更好的性能。

#### Scenario: 内存占用减少

**Given** 使用 Aligned 类型替代 Managed 类型
**When** 创建 SelectQuery 实例
**Then** 每个 ArrayList 字段 SHOULD 减少 16 字节内存占用（allocator 指针）

预期优化：
- SelectQuery: 6 个 ArrayList → 节省 96 字节
- InsertQuery/UpdateQuery/DeleteQuery: 各节省 16 字节

#### Scenario: 运行时性能保持或改善

**Given** 修复后的代码
**When** 运行现有性能测试
**Then** MUST 保持或改善性能基准

性能指标：
- ✅ 初始化更快（无需复制 allocator）
- ✅ 更好的缓存局部性（结构体更紧凑）
- ✅ 编译器优化机会更多（参数明确）

