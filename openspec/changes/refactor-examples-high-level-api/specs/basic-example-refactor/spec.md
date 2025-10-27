# Spec: Basic CRUD 示例重构

## MODIFIED Requirements

### Requirement: 使用 INSERT 查询构建器替代原始 SQL

**优先级**: P0
**依赖**: insert-query-api

`basic.zig` 示例 **MUST** 使用 `db.newInsert()` API。

#### Scenario: 插入单条用户记录

**Given**: 已连接数据库,用户表已创建
**When**: 插入单个用户 (张三, zhangsan@example.com, 28, true)
**Then**:
- 使用 `var insert = try db.newInsert(User)`
- 调用 `try insert.values(&user)` 传入用户结构体
- 调用 `try insert.exec()` 执行插入
- 返回影响行数为 1
- 不使用原始 SQL 字符串

```zig
var insert = try db.newInsert(User);
defer insert.deinit();

const user = User{
    .id = 0,
    .name = "张三",
    .email = "zhangsan@example.com",
    .age = 28,
    .active = true,
};

try insert.values(&user);
const result = try insert.exec();
assert(result.rows_affected == 1);
```

#### Scenario: 批量插入多条用户记录

**Given**: 已连接数据库,用户表已创建
**When**: 批量插入 3 个用户 (张三、李四、王五)
**Then**:
- 使用 `db.newInsert(User)` 创建查询
- 多次调用 `try insert.values(&user)` 添加记录
- 单次 `exec()` 执行所有插入
- 总影响行数为 3

---

### Requirement: 使用 SELECT 查询构建器替代原始 SQL

**优先级**: P0
**依赖**: select-query-api

`basic.zig` 示例 **MUST** 使用类型安全的 `db.newSelect()` 查询构建器替代手写 SQL 字符串。

#### Scenario: 条件查询 (age >= 25)

**Given**: 数据库中有 3 条用户记录
**When**: 查询年龄 >= 25 的用户,按年龄降序排序
**Then**:
- 使用 `var query = try db.newSelect(User)`
- 调用 `try query.column("id").column("name").column("email").column("age").column("active")`
- 调用 `try query.where("age", .gte, .{ .int = 25 })`
- 调用 `try query.orderBy("age", .desc)`
- 调用 `var rows = try query.exec()` 执行查询
- 返回 2 条记录 (李四 32, 张三 28)

```zig
var query = try db.newSelect(User);
defer query.deinit();

try query.column("id").column("name").column("email").column("age").column("active");
try query.where("age", .gte, .{ .int = 25 });
try query.orderBy("age", .desc);

var rows = try query.exec();
defer rows.deinit();

var count: u32 = 0;
while (try rows.next()) |row| {
    const id = try row.getInt(i64, 0);
    const name = try row.getString(1);
    // ... 处理其他字段
    count += 1;
}
```

#### Scenario: 查询指定用户 (WHERE name = ?)

**Given**: 数据库中有用户 "张三"
**When**: 查询 name = "张三" 的记录
**Then**:
- 使用 `where("name", .eq, .{ .string = "张三" })`
- 返回 1 条记录
- 验证查询结果的字段值

---

### Requirement: 使用 UPDATE 查询构建器替代原始 SQL

**优先级**: P0
**依赖**: update-query-api

`basic.zig` 示例 **MUST** 使用 `db.newUpdate()` 查询构建器的 `set()` 和 `where()` 方法执行更新操作。

#### Scenario: 更新用户年龄

**Given**: 数据库中有用户 "张三", 年龄为 28
**When**: 将 "张三" 的年龄更新为 29
**Then**:
- 使用 `var update = try db.newUpdate(User)`
- 调用 `try update.set("age", .{ .int = 29 })`
- 调用 `try update.where("name", .eq, .{ .string = "张三" })`
- 调用 `const result = try update.exec()`
- 影响行数为 1

```zig
var update = try db.newUpdate(User);
defer update.deinit();

try update.set("age", .{ .int = 29 });
try update.where("name", .eq, .{ .string = "张三" });

const result = try update.exec();
assert(result.rows_affected == 1);
```

---

### Requirement: 使用 DELETE 查询构建器替代原始 SQL

**优先级**: P0
**依赖**: delete-query-api

`basic.zig` 示例 **MUST** 使用 `db.newDelete()` 查询构建器的 `where()` 方法执行删除操作。

#### Scenario: 删除不活跃用户

**Given**: 数据库中有 1 个不活跃用户 (王五, active=false)
**When**: 删除所有 active = false 的用户
**Then**:
- 使用 `var del = try db.newDelete(User)`
- 调用 `try del.where("active", .eq, .{ .bool = false })`
- 调用 `const result = try del.exec()`
- 影响行数为 1

```zig
var del = try db.newDelete(User);
defer del.deinit();

try del.where("active", .eq, .{ .bool = false });

const result = try del.exec();
assert(result.rows_affected == 1);
```

---

### Requirement: 聚合查询使用 SELECT 构建器

**优先级**: P1
**依赖**: select-query-api

`basic.zig` 示例 **MUST** 使用 `db.newSelect()` 查询构建器的 `column()` 方法执行统计查询。

#### Scenario: COUNT(*) 统计用户数

**Given**: 数据库中有 2 个活跃用户
**When**: 统计用户总数
**Then**:
- 使用 `var query = try db.newSelect(User)`
- 调用 `try query.column("COUNT(*)")`
- 调用 `var rows = try query.exec()`
- 读取 COUNT 结果为 2

```zig
var query = try db.newSelect(User);
defer query.deinit();

try query.column("COUNT(*)");

var rows = try query.exec();
defer rows.deinit();

if (try rows.next()) |row| {
    const count = try row.getInt(i64, 0);
    assert(count == 2);
}
```

---

### Requirement: 保留表创建使用反射 API

**优先级**: P0
**依赖**: schema-reflection

`basic.zig` 示例 **SHALL** 继续使用反射 API (`zorm.reflection.generateCreateTableSQL`) 生成 CREATE TABLE 语句。

#### Scenario: 使用反射 API 创建表

**Given**: 定义了 User 结构体
**When**: 生成 CREATE TABLE 语句
**Then**:
- 使用 `zorm.reflection.generateCreateTableSQL(User, .postgresql, allocator)`
- 生成的 SQL 包含所有字段定义
- 执行创建表成功

```zig
const sql = try zorm.reflection.generateCreateTableSQL(User, .postgresql, allocator);
defer allocator.free(sql);

_ = try driver.exec(sql, &[_]zorm.QueryArg{});
```

---

### Requirement: 示例输出格式保持一致

**优先级**: P2
**依赖**: 无

`basic.zig` 示例重构后 **MUST** 保持输出格式与原示例一致,方便用户对比。

#### Scenario: 输出格式一致性

**Given**: 重构后的示例
**When**: 运行示例程序
**Then**:
- 保持原有的分隔线和标题格式
- 保持原有的步骤编号 (1️⃣, 2️⃣, ...)
- 保持原有的成功标记 (✓)
- 查询结果的展示格式一致
