# Query Hook System for Observability

## Why

虽然 ZORM 已经实现了基础的 QueryHook 接口（src/core/hooks.zig）和 DB 钩子管理（addHook/setHook），但是缺少在查询执行流程中实际触发钩子的代码。这导致开发者无法通过钩子系统进行查询日志记录、性能追踪和错误监控。为了完成 PRD Story 4.5 的需求，需要将钩子系统完全集成到查询执行生命周期中，并提供 PerformanceHook 实现。

## What Changes

- 在 DB 查询执行流程中集成钩子触发逻辑
  - 查询执行前调用 beforeQuery 钩子
  - 查询执行后调用 afterQuery 钩子，并传递执行时长
  - 查询失败时调用 onError 钩子
- 实现 PerformanceHook 用于性能追踪和慢查询检测
- 在 Transaction 中支持钩子触发
- 添加钩子触发辅助方法（triggerBeforeQuery、triggerAfterQuery、triggerOnError）
- 补充集成测试验证钩子在真实查询中的工作
- 完善文档和使用示例

## Impact

### 受影响的规范
- 新增规范：`query-hook-integration` - 查询钩子集成
- 新增规范：`performance-hook-implementation` - 性能钩子实现

### 受影响的代码
- `src/core/db.zig` - 添加钩子触发辅助方法
- `src/core/hooks.zig` - 添加 PerformanceHook 实现
- `src/query/query.zig` - 在查询构建器的 exec/scan 方法中集成钩子调用
- `src/core/transaction.zig` - 在事务中支持钩子触发
- `tests/` - 添加钩子集成测试

### 向后兼容性
- **完全兼容**：所有变更都是增强性的，不破坏现有 API
- 钩子默认为空列表，不影响没有注册钩子的代码
- 现有的 LoggingHook 和 HookChain 继续工作
