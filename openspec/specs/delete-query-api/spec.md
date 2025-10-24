# delete-query-api Specification

## Purpose
TBD - created by archiving change complete-delete-query-api. Update Purpose after archive.
## Requirements
### Requirement: DeleteQuery 提供类型安全的删除查询构建

DeleteQuery MUST provide a type-safe DELETE SQL query builder that supports WHERE conditions, batch deletion, and RETURNING clauses. 查询构建器必须通过 comptime 泛型实现类型安全，并强制要求 WHERE 条件以防止意外删除所有数据。

**Rationale**: 实现 PRD Story 2.3 的所有 AC 要求，为开发者提供安全、便捷的数据删除 API。

#### Scenario: 基本 DELETE 查询

```zig
var query = try db.newDelete(User);
defer query.deinit();

const result = try query
    .where("id = ?", .{123})
    .exec();

std.debug.print("删除了 {d} 行\n", .{result.rows_affected});
```

**Expected**:
- 生成 SQL: `DELETE FROM users WHERE id = $1`
- 返回 DeleteResult 包含 rows_affected
- 参数正确绑定，防止 SQL 注入

#### Scenario: WHERE 条件强制检查

```zig
var query = try db.newDelete(User);
defer query.deinit();

// 未设置 WHERE 条件
const result = query.exec();

// 应该返回错误
try std.testing.expectError(error.MissingWhereClause, result);
```

**Expected**:
- 未设置 WHERE 时，exec() 返回 error.MissingWhereClause
- 防止意外删除所有数据

### Requirement: 支持 whereIn/whereNotIn 批量删除

DeleteQuery MUST support whereIn and whereNotIn methods for batch matching and deleting multiple rows. 方法必须接受数组或切片参数，生成 WHERE column IN (...) 或 WHERE column NOT IN (...) 子句，并正确绑定所有参数。

**Rationale**: 批量删除是常见需求，whereIn 提供简洁的 API，避免手写复杂 SQL。

#### Scenario: whereIn 批量删除

```zig
var query = try db.newDelete(User);
defer query.deinit();

const user_ids = [_]i64{ 1, 2, 3, 5, 8 };
const result = try query
    .whereIn("id", &user_ids)
    .exec();

std.debug.print("删除了 {d} 行\n", .{result.rows_affected});
```

**Expected**:
- 生成 SQL: `DELETE FROM users WHERE id IN ($1, $2, $3, $4, $5)`
- 正确绑定所有参数
- 标记 has_where = true

#### Scenario: whereIn 空列表返回错误

```zig
var query = try db.newDelete(User);
defer query.deinit();

const empty: []const i64 = &[_]i64{};
const result = query.whereIn("id", empty);

try std.testing.expectError(error.EmptyWhereIn, result);
```

**Expected**:
- 空列表返回 error.EmptyWhereIn
- 防止生成无效 SQL

#### Scenario: whereIn 与 where 组合

```zig
var query = try db.newDelete(User);
defer query.deinit();

const user_ids = [_]i64{ 1, 2, 3 };
_ = try query
    .whereIn("id", &user_ids)
    .where("status = ?", .{"inactive"});

const sql = try query.build(null);
defer allocator.free(sql);
```

**Expected**:
- 生成 SQL: `DELETE FROM users WHERE id IN ($1, $2, $3) AND status = $4`
- 多个 WHERE 条件正确组合

#### Scenario: whereNotIn 批量排除

```zig
var query = try db.newDelete(User);
defer query.deinit();

const protected_ids = [_]i64{ 1, 100 };
_ = try query
    .whereNotIn("id", &protected_ids)
    .where("status = ?", .{"inactive"});

const sql = try query.build(null);
defer allocator.free(sql);
```

**Expected**:
- 生成 SQL: `DELETE FROM users WHERE id NOT IN ($1, $2) AND status = $3`
- 正确排除指定值

### Requirement: 支持 RETURNING 子句返回被删除数据

DeleteQuery MUST support PostgreSQL RETURNING clause to return deleted data for audit logging and rollback scenarios. 方言兼容性必须在编译时检查，不支持 RETURNING 的方言（如 MySQL）必须触发 comptime 错误。

**Rationale**: RETURNING 是 PostgreSQL 强大特性，DELETE 场景常用于审计和回滚。

#### Scenario: RETURNING 返回被删除数据

```zig
var query = try db.newDelete(User);
defer query.deinit();

var deleted_users = std.ArrayList(User){};
defer deleted_users.deinit(allocator);

try query
    .where("status = ?", .{"inactive"})
    .where("last_login < ?", .{cutoff_timestamp})
    .setReturning(&.{"*"})
    .execReturning(&deleted_users);

for (deleted_users.items) |user| {
    std.debug.print("Deleted: {s} ({s})\n", .{user.name, user.email});
}
```

**Expected**:
- 生成 SQL: `DELETE FROM users WHERE status = $1 AND last_login < $2 RETURNING *`
- 被删除的行扫描到 ArrayList
- 数据可用于审计日志

### Requirement: 链式 API 提供流畅的调用体验

DeleteQuery MUST implement fluent interface pattern where all builder methods return `*Self` to enable method chaining. API 风格必须与 SELECT/INSERT/UPDATE Query Builder 保持一致。

**Rationale**: 与 SELECT/INSERT/UPDATE 保持一致的 API 风格，符合 Zig 和 Bun ORM 惯例。

#### Scenario: 链式调用

```zig
var query = try db.newDelete(User);
defer query.deinit();

const result = try query
    .where("age < ?", .{18})
    .where("status = ?", .{"inactive"})
    .whereOr("deleted_at IS NOT NULL", .{})
    .exec();
```

**Expected**:
- 所有方法返回 `*Self`
- 支持链式调用，代码简洁易读

