# 调试模式和错误上下文增强 - 设计文档

## Context

ZORM 当前已实现基础的错误处理机制（error.zig）和查询日志选项（enable_query_log），但缺少：
1. 面向开发者的便捷调试模式
2. 错误发生时的详细上下文信息
3. 查询构建器的 SQL 预览能力（explain 方法）

PRD Story 4.6 要求提供生产就绪的调试体验，确保开发者能够快速定位问题，无需额外配置复杂的日志系统。

**约束条件**:
- 零运行时开销：debug 模式关闭时不应有性能影响
- 向后兼容：不破坏现有 API
- Zig 惯例：使用 std.log 标准日志接口
- 简洁 API：debug 模式应该一行配置即可启用

## Goals / Non-Goals

### Goals
1. **简化调试**：开发者通过 `debug: true` 一键启用 SQL 打印
2. **丰富错误信息**：错误消息自动包含 SQL、参数、错误类型
3. **语义化 API**：`explain()` 方法提供清晰的 SQL 预览能力
4. **零性能影响**：debug 模式关闭时无额外开销

### Non-Goals
1. **不实现**复杂的日志级别控制（使用 std.log 的现有机制）
2. **不实现**日志文件写入（由应用层的 std.log 配置控制）
3. **不实现**查询性能分析（已有 query hooks 机制，Story 4.5）
4. **不实现**SQL 高亮或格式化（保持简单文本输出）

## Decisions

### 1. Debug 模式实现方式

**决策**: 在 `DBOptions` 中添加 `debug: bool` 字段，在 `DB.exec()` 和 `DB.query()` 中检查该标志。

**原因**:
- 简单直接，用户一行配置即可启用
- 与现有 `enable_query_log` 选项保持一致
- 编译器可以优化掉未使用的分支（当 debug = false 时）

**替代方案**:
- ❌ 使用环境变量 `ZORM_DEBUG`：需要运行时解析，增加复杂性
- ❌ 使用 comptime 参数：无法在运行时动态切换
- ✅ **采用** 配置选项：平衡了灵活性和性能

**实现细节**:
```zig
pub const DBOptions = struct {
    // ... 其他选项

    /// 启用 Debug 模式，自动打印所有 SQL 语句和参数
    /// 仅用于开发环境，生产环境应设置为 false（默认）
    debug: bool = false,
};
```

### 2. SQL 和参数的日志输出

**决策**: 使用 `std.log.debug` 输出 SQL 和参数，格式化为易读的多行文本。

**格式**:
```
[ZORM Debug] Executing Query
SQL: SELECT * FROM users WHERE age > $1 ORDER BY created_at DESC LIMIT $2
Args: [18, 10]
```

**原因**:
- `std.log.debug` 是 Zig 标准日志接口，应用层可配置日志级别
- 多行格式便于阅读长 SQL 语句
- 参数格式化为 JSON-like 数组，清晰表达绑定关系

**替代方案**:
- ❌ 使用 `std.debug.print`：绕过日志系统，难以控制输出
- ❌ 单行格式：长 SQL 难以阅读
- ✅ **采用** std.log.debug + 多行格式

**实现细节**:
```zig
if (self.options.debug) {
    std.log.debug("[ZORM Debug] Executing Query", .{});
    std.log.debug("SQL: {s}", .{sql});
    std.log.debug("Args: {any}", .{args});
}
```

### 3. 错误上下文增强

**决策**: 在 `DB.exec()` 和 `DB.query()` 的错误处理分支中，使用 `std.log.err` 输出结构化错误信息。

**格式**:
```
[ZORM Error] QueryFailed
SQL: INSERT INTO users (name, email) VALUES ($1, $2)
Args: ["Alice", "alice@example.com"]
Cause: duplicate key value violates unique constraint "users_email_key"
```

**原因**:
- 错误发生时自动记录完整上下文，无需额外日志配置
- 使用 `@errorName(err)` 获取错误类型名称，清晰标识错误类别
- 底层数据库错误消息（Cause）由 pg 驱动提供

**实现细节**:
```zig
const result = self.conn.exec(sql, args) catch |err| {
    std.log.err("[ZORM Error] {s}", .{@errorName(err)});
    std.log.err("SQL: {s}", .{sql});
    std.log.err("Args: {any}", .{args});
    if (@errorReturnTrace()) |trace| {
        std.log.err("Trace: {}", .{trace});
    }
    return err;
};
```

### 4. Explain 方法设计

**决策**: 为所有查询构建器添加 `explain()` 方法，作为 `buildSQL()` 的语义化别名。

**原因**:
- `explain()` 语义清晰，表达"解释/预览 SQL"的意图
- 内部调用 `buildSQL()`，零额外实现成本
- 与 Bun ORM 的 API 保持一致（PRD 要求）

**API 示例**:
```zig
pub fn explain(self: *Self) ![]const u8 {
    return self.buildSQL();
}
```

**文档注释**:
```zig
/// 返回生成的 SQL 语句（不执行）
///
/// 用于调试和验证 SQL 生成逻辑。返回的 SQL 字符串由调用者负责释放。
///
/// ## 示例
/// ```zig
/// var query = try db.newSelect(User);
/// defer query.deinit();
///
/// const sql = try query.where("age > ?", .{18}).explain();
/// defer db.allocator.free(sql);
/// std.debug.print("Generated SQL:\n{s}\n", .{sql});
/// ```
///
/// ## 等价于
/// `explain()` 与 `buildSQL()` 完全等价，选择语义更清晰的命名。
pub fn explain(self: *Self) ![]const u8 {
    return self.buildSQL();
}
```

### 5. 参数格式化策略

**决策**: 使用 Zig 的 `{any}` 格式化器直接打印参数元组/数组。

**原因**:
- 简单高效，无需手动序列化
- 格式化输出足够清晰（如 `{ 18, 10 }` 或 `{ "Alice", "alice@example.com" }`）
- 避免引入 JSON 序列化依赖

**限制**:
- 对于复杂类型（如 JSONB、数组），输出可能不够友好
- 未来可考虑为特定类型提供自定义格式化（非本次范围）

**示例输出**:
```
Args: { 18, 10 }
Args: { "Alice", "alice@example.com" }
```

## Risks / Trade-offs

### 风险 1: Debug 模式的性能影响

**风险**: 即使 debug = false，条件检查也可能引入微小的性能开销。

**缓解**:
- Zig 编译器可以优化掉未使用的分支
- 条件检查是简单的布尔值比较，开销极小（<1ns）
- 性能测试验证开销 <5%（PRD 要求）

### 风险 2: 日志输出过多

**风险**: 高并发场景下，debug 模式可能产生大量日志，影响性能或填满磁盘。

**缓解**:
- 文档明确说明 debug 模式仅用于开发环境
- 默认 `debug: false`，生产环境不启用
- 应用层可通过 std.log 配置控制日志输出

### 风险 3: 参数中的敏感信息泄露

**风险**: Debug 模式打印参数可能暴露敏感信息（如密码、API 密钥）。

**缓解**:
- 文档警告：debug 模式不应在生产环境启用
- 未来可考虑参数脱敏机制（如 `[REDACTED]`），非本次范围
- 开发者应自行控制日志输出的访问权限

**权衡**:
- ✅ 开发便利性优先：完整的参数输出对调试至关重要
- ❌ 安全性次要：通过文档和默认配置降低风险

## Migration Plan

### 步骤 1: 添加 debug 选项（无破坏性）
- 在 `DBOptions` 中添加 `debug: bool = false`
- 默认值保持现有行为（不打印 debug 信息）

### 步骤 2: 实现 debug 日志输出
- 修改 `DB.exec()` 和 `DB.query()`，检查 `self.options.debug`
- 添加 SQL 和参数的日志输出

### 步骤 3: 增强错误上下文
- 修改错误处理分支，添加 `std.log.err` 输出
- 格式化 SQL、参数、错误类型

### 步骤 4: 添加 explain() 方法
- 为所有查询构建器添加 `explain()` 方法
- 更新文档和测试

### 回滚计划
- 如果发现严重性能问题：移除 debug 检查，恢复为可选的查询钩子
- 如果发现日志格式问题：调整日志输出格式，不影响核心逻辑

## Open Questions

1. **Q**: 是否需要为参数提供脱敏机制？
   **A**: 暂不实现。建议在文档中明确说明 debug 模式的安全风险，让开发者自行控制。

2. **Q**: 是否需要支持自定义日志格式？
   **A**: 暂不支持。保持简单，使用固定格式。未来可通过查询钩子实现自定义。

3. **Q**: explain() 方法是否应该返回参数绑定信息？
   **A**: 不需要。explain() 仅返回 SQL 字符串，参数由 debug 模式打印。

4. **Q**: 是否需要为不同类型的查询（SELECT/INSERT/UPDATE/DELETE）提供不同的 debug 输出？
   **A**: 不需要。统一格式即可，类型信息已包含在 SQL 语句中。
