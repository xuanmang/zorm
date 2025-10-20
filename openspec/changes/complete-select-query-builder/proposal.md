# Complete SELECT Query Builder Implementation

## Why

完善 SELECT 查询构建器实现，确保与功能规格 2.2.1 完全对齐，是 ZORM 项目成功的关键：

1. **API 一致性**：开发者依赖功能规格文档学习和使用 ZORM。API 与文档不一致会导致困惑、错误和低效的开发体验。

2. **类型安全增强**：`allColumns()` 通过 comptime 反射自动获取所有字段，减少手动输入错误，提升代码可维护性。

3. **向后兼容性**：保留现有 `build()` 方法的同时添加 `buildSQL()` 别名，确保现有代码无缝工作，降低升级成本。

4. **参数管理统一**：`collectArgs()` 方法统一参数收集逻辑，消除重复代码，减少潜在 bug。

5. **项目完整性**：SELECT 查询是 ORM 最核心的功能，完善实现是后续功能（INSERT, UPDATE, DELETE）的基础。

不解决这些问题将导致：
- 用户无法按照文档使用 API
- 增加学习曲线和支持成本
- 降低开发者对项目的信任
- 技术债务积累影响后续开发

## Problem

功能规格说明书 2.2.1 定义了完整的 SELECT 查询构建器 API，但当前实现与规格存在以下差异：

1. **方法名称不一致**：规格中定义 `buildSQL()` 方法，实现中使用 `build()` 方法
2. **缺少 comptime 反射的 `allColumns()` 方法**：规格要求使用 `@typeInfo` 自动获取结构体所有字段并添加到列列表
3. **缺少参数收集方法**：规格中定义 `collectArgs()` 方法用于收集所有查询参数，但实现中未提供
4. **辅助函数位置问题**：`getTableName`, `allocArgs`, `argFromValue`, `scanRow` 等辅助函数应该在查询构建器上下文中可用

这些不一致导致：
- API 使用体验与文档不符
- 用户无法按照功能规格编写代码
- 类型安全的列选择功能不完整

## What Changes

本变更提案通过以下增量更新完善 SELECT 查询构建器实现：

1. **新增 buildSQL() 方法**：作为 `build(null)` 的别名，符合功能规格 2.2.1 定义
2. **新增 allColumns() 方法**：使用 comptime 反射自动获取模型所有字段
3. **新增 collectArgs() 内部方法**：统一收集 WHERE 和 HAVING 子句参数
4. **修改 scan() 方法**：使用 collectArgs() 管理参数
5. **修改 scanOne() 方法**：使用 collectArgs() 管理参数
6. **修改 count() 方法**：使用 collectArgs() 管理参数

影响范围：
- **文件修改**：`src/query/query.zig`（SelectQuery 结构体）
- **新增测试**：单元测试和集成测试
- **文档更新**：模块文档注释和功能规格示例

## Solution

完善 SELECT 查询构建器实现，确保与功能规格 2.2.1 完全对齐：

### 1. 统一方法命名
- 保留现有 `build(alloc: ?Allocator)` 方法（向后兼容）
- 添加 `buildSQL()` 方法作为 `build(null)` 的别名（符合规格）

### 2. 实现 comptime 反射的 allColumns()
```zig
pub fn allColumns(self: *Self) !*Self {
    const fields = @typeInfo(T).Struct.fields;
    inline for (fields) |field| {
        try self.columns.append(self.allocator, field.name);
    }
    return self;
}
```

### 3. 实现 collectArgs() 方法
```zig
fn collectArgs(self: *Self) []QueryArg {
    var args = std.ArrayList(QueryArg).init(self.allocator);
    for (self.where_clauses.items) |clause| {
        args.appendSlice(clause.args) catch unreachable;
    }
    for (self.having_clauses.items) |clause| {
        args.appendSlice(clause.args) catch unreachable;
    }
    return args.toOwnedSlice() catch unreachable;
}
```

### 4. 确保辅助函数可用
- 将 `getTableName`, `allocArgs`, `argFromValue` 移至公共位置
- 确保 `scanRow` 功能通过 `result_scanner` 模块正确实现

## Impact

### Benefits
- ✅ API 与功能规格完全一致
- ✅ 提升开发体验，自动列选择减少手动输入
- ✅ 向后兼容，保留现有 `build()` 方法
- ✅ 完善参数管理，支持复杂查询场景

### Breaking Changes
- 无破坏性变更，所有新增都是增量功能

### Migration
不需要迁移，所有现有代码继续工作

## Related

- 功能规格说明书 2.2.1 SELECT 查询
- 现有实现：`src/query/query.zig` (SelectQuery)
- 依赖模块：`src/mapper/result_scanner.zig`
- 相关规格：`query-context-api`, `db-instance-api`

## Timeline

估计实现时间：2-3 小时

1. 添加 `buildSQL()` 别名方法 - 15 分钟
2. 实现 `allColumns()` comptime 反射 - 30 分钟
3. 实现 `collectArgs()` 参数收集 - 45 分钟
4. 编写单元测试验证功能 - 60 分钟
5. 更新文档和示例 - 30 分钟

## Open Questions

1. ✅ **已解决**：`collectArgs()` 返回的参数切片是否需要调用者手动释放？
   - 决策：返回临时切片，由 query 对象管理生命周期，调用者无需释放

2. ✅ **已解决**：`allColumns()` 是否应该清空现有列列表？
   - 决策：追加到现有列表，允许混合使用 `column()` 和 `allColumns()`

3. ✅ **已解决**：是否需要同时保留 `build()` 和 `buildSQL()` 两个方法？
   - 决策：保留两者，`buildSQL()` 内部调用 `build(null)`，保持向后兼容
