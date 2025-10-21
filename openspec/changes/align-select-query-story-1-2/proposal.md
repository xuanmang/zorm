# 对齐 SELECT 查询构建器 API 与 PRD Story 1.2

## Why

PRD Story 1.2 和 1.3 定义了 SELECT 查询构建器的完整 API 规范，但当前实现与 PRD 存在命名不一致：

1. **AC1.3.3 API 不一致**：PRD 要求 `setDistinct()` 方法，但代码实现为 `distinct()` 方法
2. **API 可发现性问题**：用户按照 PRD 文档编写 `.setDistinct()` 时会遇到编译错误
3. **文档与代码不同步**：降低开发者信任，增加学习成本

不解决这个问题将导致：
- 用户无法按照 PRD 示例代码使用 API
- 需要额外查找源码才能找到正确的方法名
- 影响 ZORM 作为"文档驱动开发"的项目形象

## Problem

PRD Story 1.3 的验收标准 AC1.3.3 明确要求：
> 支持 `.setDistinct()` 方法启用 DISTINCT 去重

但当前 `src/query/query.zig` 实现的是：
```zig
pub fn distinct(self: *Self) !*Self {
    self.distinct_value = true;
    return self;
}
```

这导致：
1. PRD 示例代码 `.setDistinct()` 无法编译
2. API 命名与 PRD 不一致
3. 缺少 PRD 示例验证

## What Changes

添加 `setDistinct()` 方法作为 `distinct()` 的别名，同时保留 `distinct()` 方法以保持向后兼容：

1. **新增 setDistinct() 方法**：调用 `distinct()` 实现，符合 PRD 规范
2. **保留 distinct() 方法**：保持向后兼容，避免破坏现有代码
3. **添加测试用例**：验证 `setDistinct()` 和 `distinct()` 功能等价
4. **更新文档注释**：说明两个方法的关系和推荐使用 `setDistinct()`

影响范围：
- **文件修改**：`src/query/query.zig`（SelectQuery 结构体）
- **新增测试**：单元测试验证 `setDistinct()` 方法
- **文档更新**：方法文档注释

## Solution

在 `SelectQuery` 结构体中添加 `setDistinct()` 方法：

```zig
/// 设置 DISTINCT（PRD 规范方法名）
///
/// 启用 DISTINCT 去重，生成 `SELECT DISTINCT ...` 语句。
/// 此方法是 `distinct()` 的别名，符合 PRD Story 1.3 AC1.3.3 规范。
///
/// 返回:
/// - *Self: 支持链式调用
///
/// 示例:
/// ```zig
/// var query = try db.newSelect(User);
/// defer query.deinit();
/// try query.column("department")
///     .setDistinct()
///     .scan(&users);
/// // 生成: SELECT DISTINCT department FROM users
/// ```
pub fn setDistinct(self: *Self) !*Self {
    return self.distinct();
}
```

同时更新 `distinct()` 方法的文档注释：

```zig
/// 设置 DISTINCT
///
/// 启用 DISTINCT 去重，生成 `SELECT DISTINCT ...` 语句。
///
/// **注意**：推荐使用 `setDistinct()` 以符合 PRD 规范。
/// 此方法保留用于向后兼容。
///
/// 返回:
/// - *Self: 支持链式调用
pub fn distinct(self: *Self) !*Self {
    self.distinct_value = true;
    return self;
}
```

## Impact

### Benefits
- ✅ API 与 PRD Story 1.3 完全一致
- ✅ 用户可按照 PRD 示例代码直接使用
- ✅ 保持向后兼容，不破坏现有代码
- ✅ 提升文档可信度和用户体验

### Breaking Changes
- 无破坏性变更，所有现有代码继续工作

### Migration
不需要迁移，现有使用 `distinct()` 的代码无需修改，新代码推荐使用 `setDistinct()`。

## Related

- PRD Story 1.2: Type-Safe SELECT Query Builder (Basic)
- PRD Story 1.3: SELECT Query Builder with Column Selection and Distinct
- 现有实现：`src/query/query.zig` (SelectQuery.distinct)
- 相关规格：`select-query-scan-api`

## Timeline

估计实现时间：30 分钟

1. 添加 `setDistinct()` 方法 - 10 分钟
2. 更新文档注释 - 10 分钟
3. 编写测试用例 - 10 分钟

## Open Questions

1. ✅ **已解决**：是否应该废弃 `distinct()` 方法？
   - 决策：不废弃，保留用于向后兼容，但文档推荐使用 `setDistinct()`

2. ✅ **已解决**：是否需要在其他查询构建器中也添加类似的别名方法？
   - 决策：当前仅针对 SELECT 查询，其他查询构建器按需处理
