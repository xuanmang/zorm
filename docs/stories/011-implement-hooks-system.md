# Story 011: 实现查询钩子系统

## Status
Ready for Review

## Story
**As a** ZORM 开发者,
**I want** 灵活的查询钩子系统,
**so that** 能够在查询执行前后插入自定义逻辑(日志、监控等)

## Acceptance Criteria
1. 定义 QueryHook 接口 (beforeQuery/afterQuery/onError)
2. 实现 VTable 模式支持多种钩子实现
3. 提供 LoggingHook 示例实现
4. 钩子系统与 DB 实例集成
5. 支持链式钩子调用
6. 编写钩子测试

## Tasks / Subtasks
- [x] 创建 src/core/hooks.zig
- [x] 定义 QueryHook 接口
- [x] 实现 LoggingHook 示例
- [x] 编写钩子测试

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md
参考 [docs/architecture.md#查询钩子](architecture.md) (行 1923-1978)

## Dev Agent Record

### Agent Model Used
Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)

### File List
- src/core/hooks.zig (新建)
- src/core/db.zig (修改 - 添加钩子支持)
- src/zorm.zig (修改 - 导出钩子类型)
- src/hooks/hooks.zig (删除 - 移动到 core/)

### Completion Notes
- ✅ 实现了完整的 QueryHook 接口 (beforeQuery/afterQuery/onError)
- ✅ 使用 VTable 模式实现运行时多态
- ✅ 提供 LoggingHook 示例实现,支持慢查询检测
- ✅ 实现 HookChain 支持链式钩子调用
- ✅ 与 DB 实例集成,添加 setHook/removeHook 方法
- ✅ 编写完整的单元测试 (5个测试用例)
- ✅ 所有测试通过,项目编译成功
- ✅ 符合架构文档 (docs/architecture.md:1923-1978) 的设计规范
- ✅ 适配 Zig 0.15.2 API (ArrayList 需要 allocator 参数)

### Debug Log References
无严重问题。主要处理了 Zig 0.15.2 ArrayList API 变更。

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
| 2025-01-17 | 1.1 | 完成实现 | James (Dev Agent) |
