# Story 014: 实现 UPDATE 查询构建器

## Status
Ready for Review

## Story
**As a** ZORM 开发者,
**I want** UPDATE 查询构建器,
**so that** 能够更新数据库记录

## Acceptance Criteria
1. 实现 UpdateQuery(comptime T, comptime dialect)
2. 支持 set() 设置字段
3. 支持 where() 条件
4. 支持 returning() (PostgreSQL/SQLite)
5. 实现 buildSQL() 和 exec()
6. 编写测试

## Tasks / Subtasks
- [x] 实现 UpdateQuery 结构体 (在 query.zig 中)
- [x] 实现 set() 方法
- [x] 实现 where() 和 whereOr() 方法
- [x] 实现 returning() 方法 (方言特定)
- [x] 实现 buildSQL() 和 exec()
- [x] 编写测试

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md
参考 [docs/architecture.md#UpdateQuery](architecture.md) (行 1722-1828)

## Dev Agent Record

### 实现完成日期
2025-01-17

### 实现摘要
成功实现了功能完整的 UPDATE 查询构建器，支持所有主流数据库的更新操作特性：
- ✅ 单字段更新 (set)
- ✅ 多字段更新 (多次调用 set)
- ✅ WHERE 条件 (where/whereOr)
- ✅ RETURNING 子句 (PostgreSQL/SQLite)
- ✅ 完整 SQL 生成和执行
- ✅ 81/81 测试全部通过，无内存泄漏

### 实现细节

#### 核心功能
1. **UpdateQuery 结构体** (src/query/query.zig:714-924)
   - 使用 comptime 泛型支持类型安全
   - 支持多种 SQL 方言（PostgreSQL/MySQL/SQLite）
   - 链式 API 设计模式

2. **新增字段**
   ```zig
   set_clauses: std.ArrayList(SetClause),
   where_clauses: std.ArrayList(WhereClause),
   returning_columns: ?[]const []const u8,
   ```

3. **核心方法**
   - `set()` - 设置要更新的字段
   - `where()` / `whereOr()` - 添加 WHERE 条件
   - `returning()` - 返回更新的列（PostgreSQL/SQLite）
   - `build()` - SQL 生成
   - `exec()` - 执行更新

4. **SQL 生成** (src/query/query.zig:844-897)
   - 完整的 UPDATE 语句构建
   - 正确的子句顺序：UPDATE → SET → WHERE → RETURNING
   - 方言特定的占位符（PostgreSQL: $1, MySQL: ?）
   - 参数顺序：SET 参数在前，WHERE 参数在后

### 技术挑战与解决方案

#### 1. SetClause 内部结构
**设计**: 定义 SetClause 结构体存储字段名和值
```zig
const SetClause = struct {
    column: []const u8,
    value: QueryArg,
};
```

**原因**: 需要同时存储列名和值，用于生成 `SET column = value` 语句

#### 2. 参数索引管理
**问题**: UPDATE 语句中 SET 和 WHERE 部分都需要占位符
```sql
UPDATE users SET name = $1, email = $2 WHERE id = $3
```

**解决方案**: SET 参数优先，WHERE 参数使用后续索引
```zig
// build() 中: SET 部分使用 $1, $2, $3
var param_index: usize = 1;
for (self.set_clauses.items, 0..) |set_clause, i| {
    // ...生成占位符...
    param_index += 1;
}

// exec() 中: 先收集 SET 参数，再收集 WHERE 参数
for (self.set_clauses.items) |set_clause| {
    try all_args.append(self.allocator, set_clause.value);
}
for (self.where_clauses.items) |clause| {
    try all_args.appendSlice(self.allocator, clause.args);
}
```

#### 3. RETURNING 方言检查
**实现**: 编译时检查方言是否支持 RETURNING
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

### 测试结果

#### 单元测试
```bash
$ zig build test
81/81 tests passed (无内存泄漏)
```

#### 测试覆盖范围
1. **基础实例化** (1 个测试)
   - 验证不同方言的类型不同

2. **基本UPDATE** (2 个测试)
   - PostgreSQL: `UPDATE users SET name = $1`
   - MySQL: `UPDATE users SET name = ?`

3. **多字段UPDATE** (1 个测试)
   - `UPDATE users SET name = $1, email = $2, age = $3`

4. **UPDATE with WHERE** (2 个测试)
   - 单条件: `UPDATE users SET name = $1 WHERE id = $2`
   - 多条件: `UPDATE users SET name = $1 WHERE age > $2 AND status = $3 OR role = $4`

5. **RETURNING** (1 个测试)
   - PostgreSQL: `UPDATE users SET name = $1 WHERE id = $2 RETURNING id, updated_at`

6. **完整复杂UPDATE** (1 个测试)
   - 组合多字段 + 多条件 + RETURNING

#### 示例测试：完整复杂更新
```zig
test "UpdateQuery: 完整复杂UPDATE (PostgreSQL)" {
    var query = try UpdateQuery(User, .postgresql).init(...);
    defer query.deinit();

    _ = try query.set("name", "Alice");
    _ = try query.set("email", "alice@example.com");
    _ = try query.set("age", 25);
    _ = try query.where("id = $4", .{1});
    _ = try query.where("status = $5", .{"active"});
    _ = try query.returning(&.{"id"});

    const sql = try query.build();
    // 期望: UPDATE users SET name = $1, email = $2, age = $3
    //       WHERE id = $4 AND status = $5
    //       RETURNING id
}
```

### 修改的文件
1. **src/query/query.zig**
   - 实现完整 UpdateQuery 结构体 (行 714-924)
   - 实现所有核心方法
   - 添加 8 个单元测试 (行 1460-1609)

### API 示例

#### 单字段更新
```zig
var query = try db.newUpdate(User);
defer query.deinit();

_ = try query.set("name", "Alice");
_ = try query.where("id = $2", .{1});

const sql = try query.build();
try query.exec();
```

#### 多字段更新
```zig
_ = try query.set("name", "Alice");
_ = try query.set("email", "alice@example.com");
_ = try query.set("age", 25);
_ = try query.where("id = $4", .{1});
```

#### UPDATE with RETURNING (PostgreSQL)
```zig
_ = try query.set("name", "Alice");
_ = try query.where("id = $2", .{1});
_ = try query.returning(&.{"id", "updated_at"});
```

### 待后续改进
1. **批量更新优化** - 支持批量更新多行
2. **条件更新** - 支持 CASE WHEN 条件更新
3. **JOIN 更新** - 支持基于 JOIN 的复杂更新

### 验证清单
- [x] 所有 Acceptance Criteria 已满足
- [x] 代码符合 Zig 0.15.2 标准
- [x] 81/81 测试通过
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
