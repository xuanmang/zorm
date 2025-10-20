# Proposal: Complete Error Handling Types

## Summary
完善错误处理系统，添加功能规格说明书 2.1.3 中定义的类型别名 `QueryResult(T)` 和 `VoidResult`，提升代码语义清晰性和类型安全性。

## Why
为了完全实现功能规格说明书 2.1.3 错误处理系统的要求，提升 API 的语义清晰性和可读性，同时保持零运行时开销。这些类型别名使函数签名更具表达力，明确区分查询结果和空操作，符合 Zig 语言的最佳实践。

## What Changes
在 `src/error.zig` 中添加两个类型别名：
1. `QueryResult(T)` - 泛型查询结果类型，等价于 `Error!T`
2. `VoidResult` - 空结果类型，等价于 `Error!void`

同时添加完整的文档注释、使用示例和测试用例，更新 `db-error-handling` 规格文档。

**影响文件**：
- `src/error.zig` - 添加类型别名定义和测试
- `openspec/specs/db-error-handling/spec.md` - 更新规格（由归档时自动完成）

**向后兼容性**：完全兼容，不破坏任何现有代码。

## Background
当前 `src/error.zig` 已经实现了完整的错误集定义和基本的错误处理辅助函数，但功能规格说明书 2.1.3 节中要求的类型别名尚未实现：

```zig
/// 查询结果类型
pub fn QueryResult(comptime T: type) type {
    return Error!T;
}

/// 空结果类型
pub const VoidResult = Error!void;
```

这些类型别名的缺失导致：
1. API 签名不够语义化，`Error!User` 不如 `QueryResult(User)` 清晰
2. 与功能规格文档不一致
3. 未来重构错误类型时需要修改所有使用处

## Motivation
### 为什么需要这个变更？
1. **语义清晰性**：`QueryResult(User)` 比 `Error!User` 更明确表达这是查询操作的结果
2. **类型安全**：通过类型别名统一查询结果类型，便于类型检查和文档生成
3. **规格一致性**：完全实现功能规格说明书 2.1.3 的要求
4. **未来可扩展**：如果需要修改错误处理机制，只需修改类型别名定义

### 不做这个变更会怎样？
- API 文档不够友好，使用者需要理解 `!T` 的含义
- 与功能规格文档存在差异，造成理解混淆
- 代码可读性降低，特别是在复杂的嵌套场景中

## Proposed Solution
### 核心变更
在 `src/error.zig` 中添加类型别名定义：

```zig
/// 查询结果类型
///
/// 所有查询操作返回此类型，明确表达操作可能成功返回 T 或失败返回错误。
/// 这是 `Error!T` 的语义化别名。
///
/// 使用示例:
/// ```zig
/// pub fn findUser(db: *DB, id: i64) QueryResult(User) {
///     // ...
/// }
/// ```
pub fn QueryResult(comptime T: type) type {
    return Error!T;
}

/// 空结果类型
///
/// 用于不返回数据的操作（如 INSERT/UPDATE/DELETE），明确表达操作可能成功或失败。
/// 这是 `Error!void` 的语义化别名。
///
/// 使用示例:
/// ```zig
/// pub fn deleteUser(db: *DB, id: i64) VoidResult {
///     // ...
/// }
/// ```
pub const VoidResult = Error!void;
```

### 实施步骤
1. 在 `src/error.zig` 添加类型别名定义和文档注释
2. 添加测试验证类型别名与 `Error!T` 完全兼容
3. 更新 `db-error-handling` 规格，添加类型别名需求
4. 后续可选：逐步在现有代码中采用新类型别名

### 影响范围
- **核心文件**：`src/error.zig`
- **测试文件**：`src/error.zig` 中的测试
- **规格文件**：`openspec/specs/db-error-handling/spec.md`
- **代码影响**：向后兼容，不破坏现有代码

## Alternatives Considered
### 方案 1：不添加类型别名（现状）
- **优点**：代码更简洁，避免额外的抽象层
- **缺点**：语义不清晰，与规格不一致

### 方案 2：使用更复杂的包装类型
```zig
pub const QueryResult = struct {
    pub fn Of(comptime T: type) type {
        return struct {
            value: Error!T,
        };
    }
};
```
- **优点**：可以在未来扩展附加功能（如元数据、追踪信息）
- **缺点**：过度设计，增加运行时开销，与 Zig 惯用法不符

### 选择当前方案的原因
- 零运行时开销，符合 Zig 的零成本抽象原则
- 语义清晰，易于理解和使用
- 与功能规格完全对齐
- 向后兼容，不影响现有代码

## Implementation Details
### 类型别名实现
```zig
// src/error.zig 新增部分

/// 查询结果类型
pub fn QueryResult(comptime T: type) type {
    return Error!T;
}

/// 空结果类型
pub const VoidResult = Error!void;
```

### 测试用例
```zig
test "QueryResult type alias" {
    const testing = std.testing;

    // 验证 QueryResult(T) 等价于 Error!T
    const result1: QueryResult(i32) = 42;
    const result2: Error!i32 = 42;

    try testing.expectEqual(result2, result1);

    // 验证错误情况
    const result3: QueryResult(i32) = error.QueryFailed;
    try testing.expectError(error.QueryFailed, result3);
}

test "VoidResult type alias" {
    const testing = std.testing;

    // 验证 VoidResult 等价于 Error!void
    const result1: VoidResult = {};
    const result2: Error!void = {};

    _ = result1;
    _ = result2;

    // 验证错误情况
    const result3: VoidResult = error.ConnectionClosed;
    try testing.expectError(error.ConnectionClosed, result3);
}

test "QueryResult in function signatures" {
    const testing = std.testing;

    const Helper = struct {
        fn getUserId() QueryResult(i64) {
            return 123;
        }

        fn saveUser() VoidResult {
            return {};
        }
    };

    const id = try Helper.getUserId();
    try testing.expectEqual(@as(i64, 123), id);

    try Helper.saveUser();
}
```

## Dependencies & Sequencing
### 前置依赖
- ✅ `db-error-handling` 规格已存在
- ✅ `src/error.zig` 错误集已定义

### 后续工作（可选）
1. 在 `src/core/db.zig` 中采用新类型别名
2. 在 `src/query/query.zig` 中采用新类型别名
3. 更新示例代码使用新类型别名
4. 在 API 文档中推荐使用类型别名

## Testing Strategy
### 单元测试
- 验证 `QueryResult(T)` 与 `Error!T` 完全等价
- 验证 `VoidResult` 与 `Error!void` 完全等价
- 验证在函数签名中正确工作
- 验证错误传播和捕获机制不受影响

### 编译时测试
- 验证泛型类型推断正确
- 验证类型别名在复杂嵌套场景中正确

### 集成测试
- 无需额外集成测试，类型别名不影响运行时行为

## Rollout Plan
### 阶段 1：核心实现（本提案）
- 添加类型别名定义
- 添加测试用例
- 更新规格文档

### 阶段 2：代码迁移（可选，后续提案）
- 在新代码中使用类型别名
- 逐步重构现有代码使用类型别名
- 更新示例和文档

### 阶段 3：推广使用（文档）
- 在 API 文档中推荐使用
- 在贡献指南中说明

## Success Metrics
- ✅ `openspec validate` 通过
- ✅ 所有测试通过
- ✅ 类型别名正确导出且可用
- ✅ 功能规格 2.1.3 完全实现

## Risks & Mitigation
### 风险
1. **命名冲突**：`QueryResult` 可能与其他模块冲突
   - **缓解**：在 `error` 模块命名空间下，显式导入 `zorm.error.QueryResult`

2. **学习曲线**：新用户可能不理解类型别名
   - **缓解**：在文档和注释中清晰说明

3. **一致性问题**：现有代码使用 `!T`，新代码使用 `QueryResult(T)`
   - **缓解**：两者完全兼容，可以共存，逐步迁移

### 回退策略
如果发现问题，可以简单移除类型别名定义，不影响现有代码。

## Open Questions
- ❓ 是否应该立即重构现有代码使用新类型别名？
  - **建议**：不强制，在新代码和重大重构时采用

- ❓ 是否需要为其他常见场景添加类型别名？
  - **建议**：暂时不需要，按需添加

## References
- 功能规格说明书 2.1.3 错误处理系统
- Zig 语言手册 - Error Union Types
- 现有实现：`src/error.zig`
- 现有规格：`openspec/specs/db-error-handling/spec.md`
