# Story 013: 实现 INSERT 查询构建器

## Status
Done

## Story
**As a** ZORM 开发者,
**I want** 功能完整的 INSERT 查询构建器,
**so that** 能够插入单行或多行数据,支持 RETURNING 等特性

## Acceptance Criteria
1. 实现 InsertQuery(comptime T, comptime dialect) 泛型结构体
2. 支持 value() 单行插入
3. 支持 values() 批量插入
4. 支持 returning() (PostgreSQL/SQLite)
5. 支持 onConflict() (PostgreSQL/SQLite)
6. 支持 onDuplicateKeyUpdate() (MySQL)
7. 实现 buildSQL() 和 exec()
8. 编写测试

## Tasks / Subtasks
- [x] 实现 InsertQuery 结构体 (在 query.zig 中)
- [x] 实现插入逻辑 (value/values)
- [x] 实现方言特定特性 (returning/onConflict/onDuplicateKeyUpdate)
- [x] 实现 buildSQL() 和 exec()
- [x] 编写测试

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md
参考 [docs/architecture.md#InsertQuery](architecture.md) (行 1661-1721)

## Dev Agent Record

### 实现完成日期
2025-01-17

### 实现摘要
成功实现了功能完整的 INSERT 查询构建器，支持所有主流数据库的插入操作特性：
- ✅ 单行插入 (value)
- ✅ 批量插入 (values)
- ✅ RETURNING 子句 (PostgreSQL/SQLite)
- ✅ ON CONFLICT (PostgreSQL/SQLite)
- ✅ ON DUPLICATE KEY UPDATE (MySQL)
- ✅ 完整 SQL 生成和执行
- ✅ 84/84 测试全部通过，无内存泄漏

### 实现细节

#### 核心功能
1. **InsertQuery 结构体** (src/query/query.zig:405-702)
   - 使用 comptime 泛型支持类型安全
   - 支持多种 SQL 方言（PostgreSQL/MySQL/SQLite）
   - 链式 API 设计模式

2. **新增字段**
   ```zig
   columns: std.ArrayList([]const u8),
   values_list: std.ArrayList([]const QueryArg),
   returning_columns: ?[]const []const u8,
   on_conflict: ?OnConflictClause,
   on_duplicate_key: ?OnDuplicateKeyUpdate,
   ```

3. **核心方法**
   - `value()` - 单行插入，自动提取结构体字段
   - `values()` - 批量插入，支持切片和数组指针
   - `returning()` - 返回插入的列（PostgreSQL/SQLite）
   - `onConflict()` - 冲突处理（PostgreSQL/SQLite）
   - `onDuplicateKeyUpdate()` - 重复键更新（MySQL）
   - `build()` - SQL 生成
   - `exec()` - 执行插入

4. **SQL 生成** (src/query/query.zig:594-683)
   - 完整的 INSERT 语句构建
   - 正确的子句顺序：INSERT INTO → VALUES → ON CONFLICT/ON DUPLICATE KEY → RETURNING
   - 方言特定的占位符（PostgreSQL: $1, MySQL: ?）

### 技术挑战与解决方案

#### 1. 变量名冲突
**问题**: 循环变量和方法名 `values` 冲突
```zig
error: capture shadows declaration of 'values'
for (self.values_list.items) |values| {  // 错误!
```

**解决方案**: 重命名变量为 `row_values`
```zig
for (self.values_list.items) |row_values| {
    self.allocator.free(row_values);
}
```

#### 2. comptime 占位符生成
**问题**: `dialect.placeholder()` 使用 `comptimePrint`，但参数索引是运行时变量
```zig
error: unable to evaluate comptime expression
const placeholder = dialect.placeholder(param_index);  // param_index 是运行时变量
```

**解决方案**: 在 build() 中直接使用 switch 和 format
```zig
switch (dialect) {
    .postgresql => try std.fmt.format(buf.writer(self.allocator), "${d}", .{param_index}),
    .mysql, .sqlite => try buf.appendSlice(self.allocator, "?"),
}
```

#### 3. 类型检查 - 数组指针 vs 切片
**问题**: `values()` 接收 `&array`，但类型检查只接受切片
```zig
const users = [_]User{...};
try query.values(&users);  // &users 是 *const [N]User，不是 []const User
```

**解决方案**: 扩展类型检查同时接受切片和数组指针
```zig
const is_valid = comptime blk: {
    if (rows_type_info != .pointer) break :blk false;
    if (rows_type_info.pointer.size == .slice) break :blk true;
    if (rows_type_info.pointer.size == .one) {
        const child_info = @typeInfo(rows_type_info.pointer.child);
        break :blk child_info == .array;
    }
    break :blk false;
};
```

#### 4. 返回值未使用
**问题**: `value()` 返回 `*Self`，但在 `values()` 中未使用
```zig
error: value of type '*InsertQuery(...)' ignored
try self.value(row);
```

**解决方案**: 显式丢弃返回值
```zig
_ = try self.value(row);
```

### 测试结果

#### 单元测试
```bash
$ zig build test
84/84 tests passed (无内存泄漏)
```

#### 测试覆盖范围
1. **基础实例化** (1 个测试)
   - 验证不同方言的类型不同

2. **单行插入** (2 个测试)
   - PostgreSQL: `INSERT INTO users (name, email, age) VALUES ($1, $2, $3)`
   - MySQL: `INSERT INTO users (name, email, age) VALUES (?, ?, ?)`

3. **批量插入** (1 个测试)
   - 多行 VALUES: `($1, $2, $3), ($4, $5, $6), ($7, $8, $9)`

4. **RETURNING** (1 个测试)
   - PostgreSQL: `RETURNING id, name`

5. **ON CONFLICT** (2 个测试)
   - DO NOTHING: `ON CONFLICT (email) DO NOTHING`
   - DO UPDATE: `ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name`

6. **ON DUPLICATE KEY UPDATE** (1 个测试)
   - MySQL: `ON DUPLICATE KEY UPDATE name = VALUES(name)`

7. **复杂插入** (1 个测试)
   - 组合批量插入 + ON CONFLICT + RETURNING

#### 示例测试：完整复杂插入
```zig
test "InsertQuery: 完整复杂插入 (PostgreSQL)" {
    var query = try InsertQuery(User, .postgresql).init(...);
    defer query.deinit();

    const users = [_]struct { name: []const u8, email: []const u8, age: u32 }{
        .{ .name = "Alice", .email = "alice@example.com", .age = 25 },
        .{ .name = "Bob", .email = "bob@example.com", .age = 30 },
    };

    _ = try query.values(&users);
    _ = try query.onConflict(.{
        .columns = &[_][]const u8{"email"},
        .action = .do_update,
        .update_columns = &[_][]const u8{"name"},
    });
    _ = try query.returning(&.{"id"});

    const sql = try query.build();
    // 期望: INSERT INTO users (name, email, age) VALUES ($1, $2, $3), ($4, $5, $6)
    //       ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name
    //       RETURNING id
}
```

### 修改的文件
1. **src/types.zig**
   - 添加 `ConflictAction` 枚举
   - 添加 `OnConflictClause` 结构体
   - 添加 `OnDuplicateKeyUpdate` 结构体
   - 添加 3 个单元测试

2. **src/query/query.zig**
   - 实现完整 InsertQuery 结构体
   - 实现所有核心方法
   - 添加 9 个单元测试
   - 修复占位符生成逻辑

3. **src/dialect/dialect.zig**
   - 添加 `placeholderAlloc()` 运行时方法
   - 保留 `placeholder()` 编译时方法（用于测试）

### API 示例

#### 单行插入
```zig
var query = try db.newInsert(User);
defer query.deinit();

_ = try query.value(.{
    .name = "Alice",
    .email = "alice@example.com",
    .age = 25,
});

const sql = try query.build();
try query.exec();
```

#### 批量插入
```zig
const users = [_]User{
    .{ .name = "Alice", .email = "alice@example.com", .age = 25 },
    .{ .name = "Bob", .email = "bob@example.com", .age = 30 },
};

_ = try query.values(&users);
```

#### UPSERT (PostgreSQL)
```zig
_ = try query.value(.{ .email = "alice@example.com", .name = "Alice" });
_ = try query.onConflict(.{
    .columns = &.{"email"},
    .action = .do_update,
    .update_columns = &.{"name"},
});
_ = try query.returning(&.{"id"});
```

#### UPSERT (MySQL)
```zig
_ = try query.value(.{ .email = "alice@example.com", .name = "Alice" });
_ = try query.onDuplicateKeyUpdate(.{
    .columns = &.{"name"},
});
```

### 待后续改进
1. **批量执行优化** - 使用预编译语句提升批量插入性能
2. **默认值支持** - 支持数据库默认值
3. **子查询插入** - 支持 INSERT INTO ... SELECT

### 验证清单
- [x] 所有 Acceptance Criteria 已满足
- [x] 代码符合 Zig 0.15.2 标准
- [x] 84/84 测试通过
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
