# Spec: sql-buffer-preallocation

优化 SQL 生成过程，预分配缓冲区减少字符串拼接过程中的多次内存分配，提升 SQL 构建性能。

## ADDED Requirements

### Requirement: SQL 构建器使用预估容量初始化缓冲区

SQL 构建器 MUST 在 SQL 生成开始前，根据查询复杂度估算所需缓冲区大小并预分配，避免多次 resize。

#### Scenario: 简单 SELECT 查询容量预估

```zig
// 内部实现示例
fn buildSelectSQL(self: *SelectQuery, allocator: Allocator) ![]const u8 {
    // 预估容量：基础语句 + 表名 + WHERE 条件 + ORDER BY 等
    const estimated_size = 100 + // SELECT * FROM
        self.table_name.len +
        self.estimateWhereClauseSize() +
        self.estimateOrderBySize() +
        self.estimateLimitOffsetSize();

    var buffer = try std.ArrayList(u8).initCapacity(allocator, estimated_size);
    errdefer buffer.deinit();

    // 构建 SQL 字符串...
    try buffer.appendSlice("SELECT ");
    // ...

    return buffer.toOwnedSlice();
}
```

#### Scenario: 批量 INSERT 查询容量预估

```zig
// 内部实现示例
fn buildBatchInsertSQL(self: *InsertQuery, allocator: Allocator) ![]const u8 {
    const row_count = self.values.len;
    const columns_count = self.columns.len;

    // 预估：INSERT INTO table (cols) VALUES (placeholders) * row_count
    const estimated_size =
        50 + // INSERT INTO
        self.table_name.len +
        (columns_count * 20) + // 列名平均长度
        row_count * (columns_count * 5 + 10); // 每行的占位符

    var buffer = try std.ArrayList(u8).initCapacity(allocator, estimated_size);
    errdefer buffer.deinit();

    // 构建批量 INSERT SQL...

    return buffer.toOwnedSlice();
}
```

### Requirement: 提供容量预估策略配置

MUST 允许用户调整缓冲区预估策略的保守程度（trade-off：内存使用 vs 性能）。

#### Scenario: 配置缓冲区预估策略

```zig
const BufferStrategy = enum {
    conservative, // 预估较小，可能需要 resize
    balanced,     // 默认：平衡内存和性能
    aggressive,   // 预估较大，减少 resize 但可能浪费内存
};

const db = try DB.init(allocator, conn, .postgresql, .{
    .buffer_strategy = .balanced,
});
```

### Requirement: 测量和验证预分配效果

MUST 添加基准测试验证预分配相比动态扩展的性能提升（目标：减少至少 30% 的分配次数）。

#### Scenario: 预分配 vs 动态扩展性能对比

```zig
test "SQL buffer preallocation reduces allocation count" {
    const allocator = std.testing.allocator;

    // 使用计数分配器追踪分配次数
    var counting_allocator = CountingAllocator.init(allocator);
    defer counting_allocator.deinit();

    // 测试 1: 使用预分配
    counting_allocator.reset();
    {
        var query = try db.newSelect(User);
        defer query.deinit();
        _ = try query.where("age > ?", .{18})
            .orderBy("name", .asc)
            .limit(100)
            .build(counting_allocator.allocator());
    }
    const prealloc_count = counting_allocator.alloc_count;

    // 测试 2: 不使用预分配（模拟动态扩展）
    counting_allocator.reset();
    {
        var buffer = std.ArrayList(u8).init(counting_allocator.allocator());
        defer buffer.deinit();
        // 逐步添加 SQL 片段...
    }
    const dynamic_count = counting_allocator.alloc_count;

    // 验证预分配减少至少 30% 的分配次数
    const reduction = @as(f64, @floatFromInt(dynamic_count - prealloc_count)) /
        @as(f64, @floatFromInt(dynamic_count));
    try std.testing.expect(reduction >= 0.3);
}
```

## MODIFIED Requirements

### Requirement: 优化现有 SQL 构建逻辑

MUST 重构现有的 SQL 构建代码，使用 ArrayList 替代字符串拼接，并应用容量预估策略。

#### Scenario: 重构 WHERE 条件构建

```zig
// 旧代码（多次字符串拼接）
fn buildWhereClause(self: *SelectQuery) ![]const u8 {
    var result: []const u8 = "";
    for (self.conditions) |cond| {
        result = try std.fmt.allocPrint(allocator, "{s} AND {s}", .{result, cond});
    }
    return result;
}

// 新代码（使用预分配缓冲区）
fn buildWhereClause(self: *SelectQuery, buffer: *std.ArrayList(u8)) !void {
    if (self.conditions.len == 0) return;

    try buffer.appendSlice(" WHERE ");
    for (self.conditions, 0..) |cond, i| {
        if (i > 0) {
            try buffer.appendSlice(" AND ");
        }
        try buffer.appendSlice(cond);
    }
}
```
