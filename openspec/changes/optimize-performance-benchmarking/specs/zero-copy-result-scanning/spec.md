# Spec: zero-copy-result-scanning

优化结果扫描过程，最小化数据拷贝，提升查询结果处理性能。

## ADDED Requirements

### Requirement: 结果扫描直接使用 PostgreSQL 返回的缓冲区

结果扫描 MUST 在安全的前提下，尽可能直接引用 PostgreSQL 返回的数据缓冲区，避免不必要的内存拷贝。

#### Scenario: 字符串字段零拷贝引用

```zig
// 对于字符串类型，直接引用 PostgreSQL 返回的缓冲区
const User = struct {
    id: i64,
    name: []const u8,  // 直接引用，不拷贝
    email: []const u8, // 直接引用，不拷贝
};

var users: std.ArrayList(User) = .{};
defer users.deinit(allocator);

// scan() 内部直接引用 PostgreSQL 缓冲区
try query.scan(&users);

// 注意：users 的生命周期必须短于查询结果的生命周期
for (users.items) |user| {
    std.debug.print("User: {s}\n", .{user.name}); // 安全的引用
}
```

### Requirement: 提供显式拷贝选项以延长数据生命周期

MUST 对于需要长期保存的数据，提供 `scanCopy()` 方法进行深拷贝。

#### Scenario: 显式拷贝查询结果

```zig
var users: std.ArrayList(User) = .{};
defer users.deinit(allocator);

// scanCopy() 执行深拷贝，用户拥有数据所有权
try query.scanCopy(&users, allocator);

// 可以在查询结果释放后继续使用
query.deinit(); // 查询结果缓冲区被释放

// users 仍然有效，因为数据已被拷贝
for (users.items) |user| {
    std.debug.print("User: {s}\n", .{user.name}); // 安全
}
```

### Requirement: 编译时警告潜在的生命周期问题

MUST 使用 comptime 检测和警告可能的生命周期问题（例如，查询结果在扫描之前被释放）。

#### Scenario: 编译时生命周期检查

```zig
// 这会产生编译错误或警告
test "lifetime violation detection" {
    var query = try db.newSelect(User);
    var users: std.ArrayList(User) = .{};
    defer users.deinit(allocator);

    try query.scan(&users); // 零拷贝扫描
    query.deinit(); // 释放查询结果缓冲区

    // 编译器应该警告：users 引用的数据已被释放
    _ = users.items[0].name; // 潜在的悬垂引用
}
```

### Requirement: 基准测试验证零拷贝性能提升

MUST 测量零拷贝相比拷贝模式的性能提升（目标：至少 30% 提升，对于大结果集）。

#### Scenario: 零拷贝 vs 拷贝性能对比

```zig
test "zero-copy vs copy performance" {
    const allocator = std.testing.allocator;

    // 准备大量测试数据（模拟查询结果）
    const row_count = 10000;

    // 测试 1: 零拷贝扫描
    var zero_copy_timer = try std.time.Timer.start();
    {
        var users: std.ArrayList(User) = .{};
        defer users.deinit(allocator);
        try query.scan(&users); // 零拷贝
    }
    const zero_copy_time = zero_copy_timer.read();

    // 测试 2: 拷贝扫描
    var copy_timer = try std.time.Timer.start();
    {
        var users: std.ArrayList(User) = .{};
        defer users.deinit(allocator);
        try query.scanCopy(&users, allocator); // 拷贝
    }
    const copy_time = copy_timer.read();

    // 验证零拷贝至少快 30%
    const speedup = @as(f64, @floatFromInt(copy_time)) / @as(f64, @floatFromInt(zero_copy_time));
    try std.testing.expect(speedup >= 1.3);
}
```

## MODIFIED Requirements

### Requirement: 明确文档化数据所有权和生命周期

MUST 在所有扫描方法的文档中明确说明数据所有权和生命周期规则。

#### Scenario: 清晰的 API 文档

```zig
/// scan - 零拷贝扫描查询结果
///
/// 直接引用 PostgreSQL 返回的数据缓冲区，避免内存拷贝。
///
/// **数据所有权**:
/// - 返回的结构体字段（如 []const u8）直接引用查询结果缓冲区
/// - 数据生命周期绑定到查询对象的生命周期
/// - 调用者**不能**在查询对象 deinit() 后继续使用扫描结果
///
/// **生命周期规则**:
/// 1. 查询对象必须在扫描结果使用期间保持有效
/// 2. 不要在 defer query.deinit() 后访问扫描结果
/// 3. 如需长期保存数据，使用 scanCopy() 方法
///
/// 示例:
/// ```zig
/// var query = try db.newSelect(User);
/// defer query.deinit(); // 在使用完 users 后再释放
///
/// var users: std.ArrayList(User) = .{};
/// defer users.deinit(allocator);
///
/// try query.scan(&users);
///
/// // ✅ 安全：查询对象仍然有效
/// for (users.items) |user| {
///     std.debug.print("{s}\n", .{user.name});
/// }
///
/// // query.deinit() 在这里自动调用
/// ```
pub fn scan(self: *Self, dest: *std.ArrayList(T)) !void {
    // 实现...
}
```
