# 增强错误处理和调试模式

## Why

根据 PRD Story 4.6 的要求，ZORM 需要提供：
1. **清晰的错误消息**：所有错误必须包含足够的上下文信息（SQL 语句、参数、错误位置），便于快速调试
2. **Debug 模式**：提供 `DBOptions.debug = true` 选项自动打印生成的 SQL 语句和参数
3. **Explain 方法**：查询构建器提供 `.explain()` 方法返回生成的 SQL（不执行）
4. **明确的错误类型**：连接错误、查询错误、类型转换错误返回明确的错误类型
5. **错误信息包含足够信息帮助调试**（不需要额外日志）

当前实现已经具备：
- 完整的错误类型定义（db-error-handling spec）
- 查询构建器的 `buildSQL()` 方法
- 基础的查询日志选项（`enable_query_log`）

但缺少：
- Debug 模式的实现和集成
- 错误消息的上下文增强（SQL、参数、位置）
- `explain()` 方法的别名支持
- 错误消息格式化的标准化

## What Changes

### 1. 添加 Debug 模式支持
- 在 `DBOptions` 中添加 `debug: bool` 选项（默认 false）
- Debug 模式启用时自动打印 SQL 和参数（在查询执行前/后）
- Debug 输出使用 `std.debug.print` 或 `std.log.debug`

### 2. 增强错误上下文
- 修改 `DB.exec()` 和 `DB.query()` 在错误发生时记录：
  - 完整的 SQL 语句
  - 绑定参数（格式化为可读形式）
  - 错误类型名称（`@errorName(err)`）
- 使用 `std.log.err` 输出结构化的错误信息

### 3. 查询构建器 explain 方法
- 为所有查询构建器（SelectQuery, InsertQuery, UpdateQuery, DeleteQuery, CreateTableQuery 等）添加 `explain()` 方法
- `explain()` 作为 `buildSQL()` 的语义化别名
- 提供文档说明用途和示例

### 4. 错误消息格式化
- 定义标准的错误消息格式：
  ```
  [ZORM Error] QueryFailed
  SQL: SELECT * FROM users WHERE id = $1
  Args: [123]
  Cause: relation "users" does not exist
  ```
- 在 DB 方法中集成错误格式化逻辑

## Impact

### 影响的规范
- **db-error-handling**: 添加 debug 模式的错误日志需求
- **dialect-comptime-features**: 添加 `explain()` 方法作为编译时特性

### 影响的代码
- `src/core/db.zig`:
  - 修改 `DBOptions` 添加 `debug` 字段
  - 修改 `exec()` 和 `query()` 方法增强错误日志
- `src/query/query.zig`: 为 SelectQuery 添加 `explain()` 方法
- `src/query/insert.zig`: 为 InsertQuery 添加 `explain()` 方法
- `src/query/update.zig`: 为 UpdateQuery 添加 `explain()` 方法
- `src/query/delete.zig`: 为 DeleteQuery 添加 `explain()` 方法
- `src/schema/create_table.zig`: 为 CreateTableQuery 添加 `explain()` 方法
- `src/schema/drop_table.zig`: 为 DropTableQuery 添加 `explain()` 方法
- `src/schema/create_index.zig`: 为 CreateIndexQuery 添加 `explain()` 方法
- `src/schema/drop_index.zig`: 为 DropIndexQuery 添加 `explain()` 方法

### 破坏性变更
**无** - 所有变更都是向后兼容的：
- `debug` 选项默认为 `false`（保持现有行为）
- `explain()` 是新增方法，不影响现有 API
- 错误日志增强不改变错误类型和传播机制

### 用户体验改进
- **开发效率提升**：Debug 模式让开发者快速看到生成的 SQL
- **调试更简单**：错误消息包含完整上下文，减少猜测
- **学习曲线降低**：`explain()` 方法提供语义清晰的 API
- **生产就绪**：错误信息足够详细，无需额外日志配置
