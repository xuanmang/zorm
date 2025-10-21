# select-query-distinct-api Specification

## Purpose
TBD - created by archiving change align-select-query-story-1-2. Update Purpose after archive.
## Requirements
### Requirement: SELECT 查询 MUST 支持 setDistinct() 方法启用去重

SELECT 查询构建器 MUST 提供 `setDistinct()` 方法，用于启用 SQL DISTINCT 去重功能，生成 `SELECT DISTINCT ...` 语句。此方法 MUST 符合 PRD Story 1.3 AC1.3.3 规范。

**契约**:
- 方法签名: `pub fn setDistinct(self: *Self) !*Self`
- 设置内部 `distinct_value` 字段为 `true`
- 返回 `*Self` 以支持链式调用
- 与现有 `distinct()` 方法功能完全等价

**依赖**:
- `distinct_value: bool` 字段已存在
- `build()` 方法已支持 DISTINCT SQL 生成

#### Scenario: 使用 setDistinct() 进行单列去重

**Given** 数据库中有多个用户在同一个部门工作
**When** 执行以下代码：
```zig
var query = try db.newSelect(User);
defer query.deinit();
try query.column("department")
    .setDistinct()
    .scan(&users);
```
**Then** 生成的 SQL 应为 `SELECT DISTINCT department FROM users`
**And** 返回结果中每个部门只出现一次

#### Scenario: 使用 setDistinct() 进行多列去重

**Given** 数据库中有用户数据包含重复的部门和角色组合
**When** 执行以下代码：
```zig
var query = try db.newSelect(User);
defer query.deinit();
try query.column("department")
    .column("role")
    .setDistinct()
    .scan(&users);
```
**Then** 生成的 SQL 应为 `SELECT DISTINCT department, role FROM users`
**And** 返回结果中每个部门-角色组合只出现一次

#### Scenario: 使用 setDistinct() 与 count() 组合统计唯一值数量

**Given** 数据库中有用户邮箱数据
**When** 执行以下代码：
```zig
var query = try db.newSelect(User);
defer query.deinit();
const count = try query.column("email")
    .setDistinct()
    .count();
```
**Then** 生成的 SQL 应为 `SELECT COUNT(DISTINCT email) FROM users`
**And** 返回唯一邮箱地址的数量

#### Scenario: setDistinct() 支持链式调用

**Given** SELECT 查询构建器已创建
**When** 执行以下代码：
```zig
var query = try db.newSelect(User);
defer query.deinit();
try query.setDistinct()
    .column("department")
    .where("active = ?", .{true})
    .orderBy("department", .asc)
    .limit(10)
    .scan(&users);
```
**Then** 所有方法调用都应成功
**And** 生成的 SQL 包含 `SELECT DISTINCT` 关键字
**And** 包含 WHERE、ORDER BY、LIMIT 子句

### Requirement: distinct() 方法文档 MUST 说明推荐使用 setDistinct()

系统 MUST 更新 `distinct()` 方法的文档注释，说明此方法保留用于向后兼容，新代码 SHALL 使用 `setDistinct()` 以符合 PRD 规范。

**契约**:
- 保留 `distinct()` 方法实现不变
- 更新文档注释包含推荐使用 `setDistinct()` 的说明
- 说明保留原因为向后兼容

#### Scenario: 现有代码继续使用 distinct() 方法

**Given** 现有代码使用 `distinct()` 方法
**When** 执行以下代码：
```zig
var query = try db.newSelect(User);
defer query.deinit();
try query.column("department")
    .distinct()
    .scan(&users);
```
**Then** 代码应继续正常工作
**And** 生成的 SQL 应为 `SELECT DISTINCT department FROM users`
**And** 功能与 `setDistinct()` 完全相同

#### Scenario: distinct() 和 setDistinct() 方法功能等价

**Given** SELECT 查询构建器
**When** 分别使用 `distinct()` 和 `setDistinct()` 方法
**Then** 两者应生成完全相同的 SQL 语句
**And** 两者应产生完全相同的查询结果
**And** 两者都应正确设置 `distinct_value = true`

