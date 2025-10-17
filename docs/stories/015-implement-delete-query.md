# Story 015: 实现 DELETE 查询构建器

## Status
Ready for Review

## Story
**As a** ZORM 开发者,
**I want** DELETE 查询构建器,
**so that** 能够删除数据库记录

## Acceptance Criteria
1. 实现 DeleteQuery(comptime T, comptime dialect)
2. 支持 where() 条件
3. 实现 buildSQL() 和 exec()
4. 编写测试

## Tasks / Subtasks
- [x] 实现 DeleteQuery 结构体 (在 query.zig 中)
- [x] 实现 where() 和 whereOr() 方法
- [x] 实现 returning() 方法 (方言特定)
- [x] 实现 buildSQL() 和 exec()
- [x] 编写测试

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md
参考 [docs/architecture.md#DeleteQuery](architecture.md) (行 1829-1892)

## Dev Agent Record

### 实现完成日期
2025-01-17

### 实现摘要
成功实现了简洁高效的 DELETE 查询构建器，支持所有主流数据库的删除操作：
- ✅ WHERE 条件 (where/whereOr)
- ✅ RETURNING 子句 (PostgreSQL/SQLite)
- ✅ 完整 SQL 生成和执行
- ✅ 88/88 测试全部通过，无内存泄漏

### 实现细节

#### 核心功能
1. **DeleteQuery 结构体** (src/query/query.zig:926-1077)
   - 使用 comptime 泛型支持类型安全
   - 支持多种 SQL 方言（PostgreSQL/MySQL/SQLite）
   - 链式 API 设计模式

2. **新增字段**
   ```zig
   allocator: Allocator,
   db: *DBType,
   table_name: []const u8,
   where_clauses: std.ArrayList(WhereClause),
   returning_columns: ?[]const []const u8,
   ```

3. **核心方法**
   - `where()` - 添加 WHERE 条件（AND 运算符）
   - `whereOr()` - 添加 WHERE 条件（OR 运算符）
   - `returning()` - 返回删除的列（PostgreSQL/SQLite）
   - `build()` - SQL 生成
   - `exec()` - 执行删除

4. **SQL 生成** (src/query/query.zig:1025-1057)
   - 完整的 DELETE 语句构建
   - 正确的子句顺序：DELETE FROM → WHERE → RETURNING
   - 方言特定的占位符（PostgreSQL: $1, MySQL: ?）

### 技术挑战与解决方案

#### DeleteQuery 设计简洁性
**设计**: DeleteQuery 比 UPDATE 更简单，不需要 SET 子句
```zig
// 只需要 WHERE 和 RETURNING
where_clauses: std.ArrayList(WhereClause),
returning_columns: ?[]const []const u8,
```

**原因**: DELETE 只需要定位要删除的行（WHERE）和可选的返回值（RETURNING）

#### RETURNING 方言检查
**实现**: 与 UPDATE 相同的编译时检查
```zig
pub fn returning(self: *Self, cols: []const []const u8) !*Self {
    if (comptime !dialect.supportsReturning()) {
        @compileError("RETURNING is not supported by " ++ @tagName(dialect));
    }
    self.returning_columns = cols;
    return self;
}
```

**原因**: MySQL 不支持 RETURNING，编译时阻止使用

#### 内存管理
**实现**: 在 deinit() 中释放 WHERE 子句参数
```zig
pub fn deinit(self: *Self) void {
    for (self.where_clauses.items) |clause| {
        self.allocator.free(clause.args);
    }
    self.where_clauses.deinit(self.allocator);
    self.allocator.destroy(self);
}
```

### 测试结果

#### 单元测试
```bash
$ zig build test
88/88 tests passed (无内存泄漏)
```

#### 测试覆盖范围
1. **基础实例化** (1 个测试)
   - 验证不同方言的类型不同

2. **基本DELETE** (3 个测试)
   - 无 WHERE 条件: `DELETE FROM users`
   - PostgreSQL: `DELETE FROM users WHERE id = $1`
   - MySQL: `DELETE FROM users WHERE age < ?`

3. **多条件DELETE** (1 个测试)
   - AND/OR 组合: `DELETE FROM users WHERE age < $1 AND status = $2 OR role = $3`

4. **DELETE with RETURNING** (1 个测试)
   - PostgreSQL: `DELETE FROM users WHERE id = $1 RETURNING id, name`

5. **完整复杂DELETE** (1 个测试)
   - 组合多条件 + RETURNING

#### 示例测试：完整复杂删除
```zig
test "DeleteQuery: 完整复杂DELETE (PostgreSQL)" {
    var query = try DeleteQuery(User, .postgresql).init(...);
    defer query.deinit();

    _ = try query.where("age < $1", .{18});
    _ = try query.where("status = $2", .{"inactive"});
    _ = try query.whereOr("deleted_at IS NOT NULL", .{});
    _ = try query.returning(&.{"id", "name", "deleted_at"});

    const sql = try query.build();
    // 期望: DELETE FROM users WHERE age < $1 AND status = $2 OR deleted_at IS NOT NULL
    //       RETURNING id, name, deleted_at
}
```

### 修改的文件
1. **src/query/query.zig**
   - 实现完整 DeleteQuery 结构体 (行 926-1077)
   - 实现所有核心方法
   - 添加 7 个单元测试 (行 1730-1856)

### API 示例

#### 简单删除
```zig
var query = try db.newDelete(User);
defer query.deinit();

_ = try query.where("id = $1", .{1});

const sql = try query.build();
try query.exec();
```

#### 条件删除
```zig
_ = try query.where("age < $1", .{18});
_ = try query.where("status = $2", .{"inactive"});
_ = try query.whereOr("role = $3", .{"guest"});
```

#### DELETE with RETURNING (PostgreSQL)
```zig
_ = try query.where("id = $1", .{1});
_ = try query.returning(&.{"id", "name", "deleted_at"});
```

### 对比 UPDATE 和 DELETE

| 特性 | UpdateQuery | DeleteQuery |
|------|-------------|-------------|
| SET 子句 | ✅ (必需) | ❌ |
| WHERE 子句 | ✅ | ✅ |
| RETURNING | ✅ (PG/SQLite) | ✅ (PG/SQLite) |
| 参数顺序 | SET → WHERE | WHERE only |
| 复杂度 | 中等 | 简单 |

### 待后续改进
1. **批量删除优化** - 支持基于子查询的批量删除
2. **软删除支持** - 支持软删除模式（UPDATE 而非 DELETE）
3. **级联删除** - 支持级联删除相关记录

### 验证清单
- [x] 所有 Acceptance Criteria 已满足
- [x] 代码符合 Zig 0.15.2 标准
- [x] 88/88 测试通过
- [x] 无内存泄漏
- [x] 代码注释完整（说明 why，不是 what）
- [x] 支持多种 SQL 方言
- [x] 链式 API 设计
- [x] 类型安全（comptime 泛型）
- [x] 编译时特性检测（方言支持）

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
| 2025-01-17 | 2.0 | 完成实现并测试通过 | Dev Agent |
