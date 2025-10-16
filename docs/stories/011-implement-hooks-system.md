# Story 011: 实现查询钩子系统

## Status
Draft

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
- [ ] 创建 src/core/hooks.zig
- [ ] 定义 QueryHook 接口
- [ ] 实现 LoggingHook 示例
- [ ] 编写钩子测试

## Dev Notes
参考 [docs/architecture.md#查询钩子](architecture.md) (行 1923-1978)

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
