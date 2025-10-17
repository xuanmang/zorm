# Story 018: 实现字段映射器

## Status
Approved

## Story
**As a** ZORM 开发者,
**I want** 字段映射器,
**so that** 能够将数据库行数据映射到 Zig 结构体

## Acceptance Criteria
1. 实现 scanRow(comptime T, row, allocator) 函数
2. 支持所有基础类型 (int/float/bool/string)
3. 支持可选类型 (Optional)
4. 支持字节数组
5. 编译时生成映射逻辑,零运行时开销
6. 编写完整测试

## Tasks / Subtasks
- [ ] 创建 src/mapper/field_mapper.zig
- [ ] 实现 scanRow() 函数
- [ ] 实现 getFieldValue() 函数
- [ ] 编写测试

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md
参考 [docs/architecture.md#ModelMapper](architecture.md) (行 686-788)

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
