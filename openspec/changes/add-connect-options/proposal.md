# Add DBOptions Parameter to zorm.connect

## 概述

为 `zorm.connect` 方法添加可选的 `DBOptions` 参数,允许用户在创建数据库连接时自定义配置选项,如连接池大小、超时设置、日志选项等。

## Why

当前 `zorm.connect` 函数只接受 `allocator` 和 `dsn` 两个参数,内部使用硬编码的默认 DBOptions (空结构体 `.{}`)。这限制了用户在连接创建阶段配置数据库行为的能力。

用户需要在连接时就能够配置:
- 连接池参数(最大连接数、空闲连接数等)
- 超时设置(查询超时、连接生命周期等)
- 日志选项(查询日志、慢查询日志、debug模式等)
- 其他 DBOptions 支持的配置项

这个变更将提升 API 的灵活性和易用性,同时保持完全的向后兼容性。

## 影响范围

### 修改的组件
- `src/convenience.zig` - `connect` 函数签名和实现

### 向后兼容性
- ✅ 完全向后兼容
- 现有代码无需修改即可继续工作
- 新参数为可选参数,默认使用 DBOptions 的默认值

### API 变更
- **修改**: `connect(allocator, dsn)` → `connect(allocator, dsn, options)`
- **类型**: 非破坏性变更(可选参数)

## 实现策略

1. 在 `connect` 函数中添加可选的 `options` 参数,类型为 `?DBOptions`,默认值为 `null`
2. 当 `options` 为 `null` 时,使用 `DBOptions{}` (默认配置)
3. 当 `options` 为非 `null` 时,将其传递给 `DB.init()`
4. 更新函数文档说明新参数的用法
5. 添加测试验证新功能

## 关联规范
- `db-connection-options` - 定义连接选项配置的行为规范

## 验收标准
- [x] `connect` 函数接受可选的 `DBOptions` 参数
- [x] 不传 options 时使用默认配置
- [x] 传递自定义 options 时正确应用到 DB 实例
- [x] 所有测试通过 (443/443 tests passed)
- [x] 文档完整清晰
