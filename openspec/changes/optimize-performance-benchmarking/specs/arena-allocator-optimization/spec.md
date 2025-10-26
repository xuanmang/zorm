# Spec: arena-allocator-optimization

优化查询构建器的内存分配策略，使用 Arena 分配器减少临时内存分配开销，提升查询构建性能。

## ADDED Requirements

### Requirement: 查询构建器默认使用 Arena 分配器

所有查询构建器（SELECT、INSERT、UPDATE、DELETE）MUST 使用 QueryContext 管理临时内存分配，避免频繁的小块内存分配和释放。

#### Scenario: SELECT 查询使用 Arena 分配器构建 SQL

```zig
var ctx = QueryContext.init(db.allocator);
defer ctx.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query.where("age > ?", .{18});
try query.orderBy("created_at", .desc);

// 使用 Arena 分配器构建 SQL
const sql = try query.build(ctx.allocator());

// ctx.deinit() 自动释放所有临时 SQL 构建内存
```

#### Scenario: INSERT 查询批量插入优化

```zig
var ctx = QueryContext.init(db.allocator);
defer ctx.deinit();

const users = [_]User{
    .{ .name = "Alice", .email = "alice@example.com", .age = 25 },
    .{ .name = "Bob", .email = "bob@example.com", .age = 30 },
    // ... 1000 条记录
};

var insert = try db.newInsert(User);
defer insert.deinit();

// Arena 分配器批量管理 SQL 生成内存
const sql = try insert.values(&users).build(ctx.allocator());
try db.exec(sql);

// 单次 deinit 释放所有临时内存
```

### Requirement: QueryContext 支持容量保留的重置

QueryContext.reset() 方法 MUST 清理已分配内存但保留底层缓冲区容量，优化循环中的查询构建场景。

#### Scenario: 循环中复用 QueryContext

```zig
var ctx = QueryContext.init(db.allocator);
defer ctx.deinit();

for (user_ids) |id| {
    var query = try db.newSelect(Post);
    defer query.deinit();

    try query.where("user_id = ?", .{id});
    const sql = try query.build(ctx.allocator());

    // 执行查询...

    // 重置但保留容量，避免下次循环重新分配
    ctx.reset();
}
```

### Requirement: 提供性能对比测试

MUST 添加基准测试验证 Arena 分配器相比逐个分配的性能提升（目标：至少 20% 提升）。

#### Scenario: Arena vs 逐个分配性能对比

```zig
// 基准测试代码示例（简化）
test "Arena allocator vs individual allocations" {
    const allocator = std.testing.allocator;

    // 测试 1: 使用 Arena 分配器
    var arena_timer = try std.time.Timer.start();
    {
        var ctx = QueryContext.init(allocator);
        defer ctx.deinit();

        for (0..1000) |i| {
            var query = try db.newSelect(User);
            defer query.deinit();
            _ = try query.where("id = ?", .{i}).build(ctx.allocator());
            ctx.reset();
        }
    }
    const arena_time = arena_timer.read();

    // 测试 2: 逐个分配和释放
    var individual_timer = try std.time.Timer.start();
    {
        for (0..1000) |i| {
            var query = try db.newSelect(User);
            defer query.deinit();
            const sql = try query.where("id = ?", .{i}).build(allocator);
            defer allocator.free(sql);
        }
    }
    const individual_time = individual_timer.read();

    // 验证 Arena 至少快 20%
    const speedup = @as(f64, @floatFromInt(individual_time)) / @as(f64, @floatFromInt(arena_time));
    try std.testing.expect(speedup >= 1.2);
}
```

## MODIFIED Requirements

### Requirement: 查询构建器 API 支持可选的 allocator 参数

现有的 `buildSQL()` 方法 MUST 接受可选的 allocator 参数，默认使用查询对象的 allocator。

#### Scenario: 兼容现有 API 同时支持 Arena 优化

```zig
// 方式 1: 使用默认 allocator（向后兼容）
var query = try db.newSelect(User);
defer query.deinit();
const sql = try query.buildSQL();
defer db.allocator.free(sql);

// 方式 2: 使用 QueryContext 的 Arena allocator（推荐）
var ctx = QueryContext.init(db.allocator);
defer ctx.deinit();

var query2 = try db.newSelect(User);
defer query2.deinit();
const sql2 = try query2.build(ctx.allocator());
// 不需要手动 free，ctx.deinit() 会自动清理
```
