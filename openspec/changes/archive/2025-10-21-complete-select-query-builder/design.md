# Design: Complete SELECT Query Builder

## Goals

1. **API 一致性**：确保实现与功能规格 2.2.1 完全对齐
2. **向后兼容**：保持现有 API 不变，所有新增都是增量功能
3. **类型安全**：利用 Zig 的 comptime 特性实现编译时类型检查
4. **零运行时开销**：comptime 反射和方言分派不增加运行时成本

## Architecture

### Current State

```zig
pub fn SelectQuery(comptime T: type, comptime dialect: Dialect) type {
    return struct {
        // ... 现有字段 ...

        pub fn build(self: *Self, alloc: ?Allocator) ![]const u8 { ... }
        pub fn scan(self: *Self) ![]T { ... }
        pub fn scanOne(self: *Self) !T { ... }
        pub fn count(self: *Self) !usize { ... }
    };
}
```

### Proposed Changes

#### 1. 方法命名统一

**设计决策**：同时保留 `build()` 和 `buildSQL()` 两个方法

**理由**：
- `build()` 是现有实现，支持自定义 allocator，提供更大灵活性
- `buildSQL()` 是规格定义，使用默认 allocator，更符合用户预期
- 保留两者实现向后兼容，避免破坏现有代码

**实现**：
```zig
/// 构建 SQL（使用默认 allocator）
pub fn buildSQL(self: *Self) ![]const u8 {
    return self.build(null);
}

/// 构建 SQL（支持自定义 allocator）
pub fn build(self: *Self, alloc: ?Allocator) ![]const u8 {
    // 现有实现
}
```

#### 2. Comptime 反射的 allColumns()

**设计决策**：使用 `inline for` 遍历结构体字段，编译时展开

**理由**：
- Zig 的 `@typeInfo` 提供编译时类型反射
- `inline for` 确保零运行时开销
- 自动从模型类型获取所有字段名，减少手动输入

**实现**：
```zig
/// 选择所有列（comptime 反射）
pub fn allColumns(self: *Self) !*Self {
    const fields = @typeInfo(T).Struct.fields;
    inline for (fields) |field| {
        try self.columns.append(self.allocator, field.name);
    }
    return self;
}
```

**行为**：
- 追加到现有列列表（而非替换）
- 支持混合使用：`query.column("id").allColumns().column("custom")`
- 编译时展开，运行时无反射开销

#### 3. 参数收集方法

**设计决策**：返回临时切片，由查询对象管理生命周期

**理由**：
- WHERE 和 HAVING 子句都包含参数
- 参数需要按顺序传递给数据库驱动
- 内部使用，无需暴露给用户

**实现**：
```zig
/// 收集所有查询参数（内部方法）
fn collectArgs(self: *Self) ![]const QueryArg {
    var args = std.ArrayList(QueryArg).init(self.allocator);
    errdefer args.deinit();

    // WHERE 子句参数
    for (self.where_clauses.items) |clause| {
        try args.appendSlice(clause.args);
    }

    // HAVING 子句参数
    for (self.having_clauses.items) |clause| {
        try args.appendSlice(clause.args);
    }

    return try args.toOwnedSlice();
}
```

**生命周期管理**：
- 返回的切片由调用者负责释放
- 在 `scan()`, `scanOne()`, `count()` 中使用完毕后立即释放
- 使用 `defer` 确保异常时也能正确释放

#### 4. 辅助函数位置

**设计决策**：保持当前位置，确保可见性

**现状**：
- `getTableName` 在 `src/reflect/table.zig` 中（通过 comptime 获取）
- `allocArgs`, `argFromValue` 在 `src/query/query.zig` 中（模块级私有函数）
- `scanRow` 功能在 `src/mapper/result_scanner.zig` 中（通过 `scanOne` 和 `scanAll` 实现）

**确认**：
- 当前位置合理，无需调整
- `SelectQuery` 可以正常访问这些函数

## Trade-offs

### Alternative 1: 只保留 `buildSQL()`，移除 `build()`

**优点**：
- API 更简洁
- 完全符合规格

**缺点**：
- ❌ 破坏现有代码
- ❌ 失去自定义 allocator 的灵活性
- ❌ 与 `QueryContext` 集成受限

**决策**：❌ 不采用

### Alternative 2: `allColumns()` 替换现有列列表

**优点**：
- 行为更明确
- 避免重复列

**缺点**：
- ❌ 失去灵活性，无法混合使用
- ❌ 与 `column()` 行为不一致

**决策**：❌ 不采用

### Alternative 3: `collectArgs()` 返回 ArrayList 而非切片

**优点**：
- 调用者可以继续添加参数

**缺点**：
- ❌ 增加调用者责任
- ❌ 内存管理复杂化
- ❌ 内部方法无需暴露实现细节

**决策**：❌ 不采用

## Implementation Plan

### Phase 1: 核心方法实现 (1 小时)

1. 添加 `buildSQL()` 别名方法
2. 实现 `allColumns()` comptime 反射
3. 实现 `collectArgs()` 参数收集

### Phase 2: 集成和测试 (1 小时)

1. 更新 `scan()`, `scanOne()`, `count()` 使用 `collectArgs()`
2. 编写单元测试验证新方法
3. 测试向后兼容性

### Phase 3: 文档和示例 (30 分钟)

1. 更新模块文档注释
2. 添加 `allColumns()` 使用示例
3. 更新功能规格说明书中的代码示例

## Testing Strategy

### Unit Tests

```zig
test "buildSQL alias for build" {
    const allocator = std.testing.allocator;
    const db = try createTestDB(allocator);
    defer db.deinit();

    var query = try db.newSelect(TestUser);
    defer query.deinit();

    const sql1 = try query.build(null);
    defer allocator.free(sql1);

    const sql2 = try query.buildSQL();
    defer allocator.free(sql2);

    try std.testing.expectEqualStrings(sql1, sql2);
}

test "allColumns with comptime reflection" {
    const allocator = std.testing.allocator;
    const db = try createTestDB(allocator);
    defer db.deinit();

    const TestUser = struct {
        id: i64,
        name: []const u8,
        email: []const u8,
    };

    var query = try db.newSelect(TestUser);
    defer query.deinit();

    try query.allColumns();

    try std.testing.expectEqual(@as(usize, 3), query.columns.items.len);
    try std.testing.expectEqualStrings("id", query.columns.items[0]);
    try std.testing.expectEqualStrings("name", query.columns.items[1]);
    try std.testing.expectEqualStrings("email", query.columns.items[2]);
}

test "collectArgs from WHERE and HAVING" {
    const allocator = std.testing.allocator;
    const db = try createTestDB(allocator);
    defer db.deinit();

    var query = try db.newSelect(TestUser);
    defer query.deinit();

    try query.where("age > $1", .{18});
    try query.having("COUNT(*) > $2", .{5});

    const args = try query.collectArgs();
    defer allocator.free(args);

    try std.testing.expectEqual(@as(usize, 2), args.len);
    try std.testing.expectEqual(@as(i64, 18), args[0].int);
    try std.testing.expectEqual(@as(i64, 5), args[1].int);
}

test "allColumns mixed with column" {
    const allocator = std.testing.allocator;
    const db = try createTestDB(allocator);
    defer db.deinit();

    var query = try db.newSelect(TestUser);
    defer query.deinit();

    try query.column("COUNT(*) as count")
        .allColumns()
        .column("created_at");

    try std.testing.expectEqual(@as(usize, 5), query.columns.items.len);
}
```

### Integration Tests

```zig
test "SELECT with allColumns integration" {
    const allocator = std.testing.allocator;
    const db = try createRealDB(allocator);
    defer db.deinit();

    var query = try db.newSelect(User);
    defer query.deinit();

    const users = try query
        .allColumns()
        .where("age > $1", .{18})
        .orderBy("created_at", .desc)
        .limit(10)
        .scan();
    defer allocator.free(users);

    // Verify results
    try std.testing.expect(users.len <= 10);
}
```

## Performance Considerations

### Comptime Overhead

- `allColumns()` 使用 `inline for` 在编译时展开
- 生成的代码等价于手动调用 `column()` 多次
- 零运行时反射开销

### Memory Management

- `collectArgs()` 创建临时切片，需及时释放
- 建议使用 `QueryContext.allocator()` 优化临时分配
- 所有参数最终由 `where_clauses` 和 `having_clauses` 持有，无额外拷贝

### SQL Building

- `buildSQL()` 只是 `build(null)` 的别名，无额外开销
- SQL 构建逻辑保持不变，性能不受影响

## Security Considerations

### SQL Injection Prevention

- 所有参数化查询使用占位符（`$1`, `$2`, ...）
- `collectArgs()` 保持参数顺序，确保正确绑定
- 用户提供的条件字符串需谨慎处理（当前由用户负责）

### Type Safety

- `allColumns()` 通过 comptime 反射确保列名正确
- 编译时类型检查，避免运行时错误

## Dependencies

### Internal

- `src/types.zig` - 提供 `QueryArg`, `WhereClause`, `HavingClause` 类型
- `src/mapper/result_scanner.zig` - 提供 `scanOne`, `scanAll` 功能
- `src/reflect/table.zig` - 提供 `getTableName` 功能
- `src/allocator.zig` - 提供 `QueryContext`（可选优化）

### External

- Zig 标准库 `std.mem.Allocator`
- Zig 编译时特性 `@typeInfo`, `inline for`

## Future Enhancements

1. **CTE (WITH 子句) 支持**：添加 `.with()` 方法构建公共表表达式
2. **子查询支持**：允许嵌套 `SelectQuery` 作为子查询
3. **UNION/INTERSECT/EXCEPT**：支持集合操作
4. **窗口函数**：添加 `.window()` 方法支持 `OVER` 子句
5. **查询优化器提示**：支持数据库特定的优化提示

这些增强将在后续提案中逐步实现。
