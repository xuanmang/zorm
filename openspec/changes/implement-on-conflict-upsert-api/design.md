# Design Document: ON CONFLICT Upsert API

## Architecture Overview

### 目标
重构 `InsertQuery` 的 ON CONFLICT 支持,提供链式 API 满足 PRD Story 4.1 所有验收标准,同时保持类型安全和编译时验证。

### 核心设计原则
1. **链式调用优先**: 所有方法返回 `*Self`,支持流畅的方法链
2. **状态分离**: 冲突目标、动作、更新列、WHERE 条件分别存储
3. **延迟验证**: 在 `build()` 阶段验证配置完整性
4. **编译时检查**: 使用 `dialect.supportsOnConflict()` 编译时验证

## Component Design

### 1. 状态管理

#### 当前实现 (待移除)
```zig
on_conflict: ?OnConflictClause,
```

#### 新实现
```zig
// InsertQuery 结构体新增字段
conflict_target: ?[]const []const u8 = null,  // 冲突列数组
conflict_action: ?ConflictAction = null,       // .do_nothing 或 .do_update
conflict_updates: ?[]const u8 = null,          // SQL SET 表达式
conflict_where: ?[]const u8 = null,            // WHERE 条件 (部分唯一索引)
```

**设计理由**:
- 分离存储使每个方法职责单一
- 可选类型允许逐步配置,在 `build()` 时验证
- 字符串表达式给用户最大灵活性 (EXCLUDED、函数调用等)

### 2. API 方法设计

#### onConflict(columns)
```zig
/// 指定冲突检测的列
///
/// 参数:
/// - columns: 冲突列名数组 (如 &.{"email"} 或 &.{"user_id", "project_id"})
///
/// 返回: *Self (支持链式调用)
///
/// 示例:
/// ```zig
/// _ = try query.onConflict(&.{"email"});
/// ```
pub fn onConflict(self: *Self, columns: []const []const u8) !*Self {
    if (comptime !dialect.supportsOnConflict()) {
        @compileError("ON CONFLICT is not supported by " ++ @tagName(dialect));
    }

    if (columns.len == 0) {
        return error.EmptyConflictTarget;
    }

    self.conflict_target = columns;
    return self;
}
```

**设计考虑**:
- 编译时方言检查
- 运行时参数验证 (非空列表)
- 直接存储切片引用,调用者负责生命周期

#### doNothing()
```zig
/// 冲突时不执行任何操作 (DO NOTHING)
///
/// 必须先调用 onConflict() 指定冲突目标
///
/// 返回: *Self (支持链式调用)
///
/// 示例:
/// ```zig
/// _ = try query.onConflict(&.{"email"}).doNothing();
/// ```
pub fn doNothing(self: *Self) !*Self {
    if (self.conflict_target == null) {
        return error.ConflictTargetNotSet;
    }

    self.conflict_action = .do_nothing;
    return self;
}
```

**设计考虑**:
- 前置条件检查 (必须先设置冲突目标)
- 清晰的错误消息
- 与 `doUpdate()` 互斥 (后调用覆盖)

#### doUpdate(assignments)
```zig
/// 冲突时更新指定列 (DO UPDATE SET ...)
///
/// 参数:
/// - assignments: SQL SET 表达式字符串,支持 EXCLUDED 关键字
///   示例: "name = EXCLUDED.name, age = EXCLUDED.age"
///
/// 必须先调用 onConflict() 指定冲突目标
///
/// 返回: *Self (支持链式调用)
///
/// 示例:
/// ```zig
/// _ = try query
///     .onConflict(&.{"email"})
///     .doUpdate("name = EXCLUDED.name, updated_at = CURRENT_TIMESTAMP");
/// ```
pub fn doUpdate(self: *Self, assignments: []const u8) !*Self {
    if (self.conflict_target == null) {
        return error.ConflictTargetNotSet;
    }

    if (assignments.len == 0) {
        return error.EmptyUpdateAssignments;
    }

    self.conflict_action = .do_update;
    self.conflict_updates = assignments;
    return self;
}
```

**设计考虑**:
- 接受原始 SQL 字符串,不解析 (简化实现,用户灵活性高)
- 支持 EXCLUDED 关键字、函数调用等 PostgreSQL 特性
- 前置条件检查

#### whereConflict(condition)
```zig
/// 指定部分唯一索引的 WHERE 条件
///
/// 参数:
/// - condition: SQL WHERE 条件表达式
///   示例: "active = true"
///
/// 仅在使用部分唯一索引时需要
///
/// 返回: *Self (支持链式调用)
///
/// 示例:
/// ```zig
/// _ = try query
///     .onConflict(&.{"email"})
///     .whereConflict("deleted_at IS NULL")
///     .doUpdate("name = EXCLUDED.name");
/// ```
pub fn whereConflict(self: *Self, condition: []const u8) !*Self {
    if (self.conflict_target == null) {
        return error.ConflictTargetNotSet;
    }

    if (condition.len == 0) {
        return error.EmptyWhereCondition;
    }

    self.conflict_where = condition;
    return self;
}
```

**设计考虑**:
- 满足 AC4.1.6 部分唯一索引需求
- 可选方法,不影响基础 UPSERT 功能
- 字符串表达式,用户自行保证正确性

### 3. SQL 生成逻辑

#### build() 方法更新
```zig
// 在 build() 方法中,VALUES 之后生成 ON CONFLICT 子句

// 验证配置完整性
if (self.conflict_target) |_| {
    if (self.conflict_action == null) {
        return error.ConflictActionNotSet;
    }
}

// 生成 ON CONFLICT 子句
if (self.conflict_target) |columns| {
    try buf.appendSlice(allocator, " ON CONFLICT (");

    for (columns, 0..) |col, i| {
        if (i > 0) try buf.appendSlice(allocator, ", ");
        try buf.appendSlice(allocator, col);
    }

    try buf.appendSlice(allocator, ")");

    // WHERE 条件 (部分唯一索引)
    if (self.conflict_where) |where| {
        try buf.appendSlice(allocator, " WHERE ");
        try buf.appendSlice(allocator, where);
    }

    // 冲突动作
    if (self.conflict_action) |action| {
        switch (action) {
            .do_nothing => {
                try buf.appendSlice(allocator, " DO NOTHING");
            },
            .do_update => {
                if (self.conflict_updates) |updates| {
                    try buf.appendSlice(allocator, " DO UPDATE SET ");
                    try buf.appendSlice(allocator, updates);
                } else {
                    return error.UpdateAssignmentsNotSet;
                }
            },
        }
    }
}
```

**生成的 SQL 示例**:
```sql
-- DO NOTHING
INSERT INTO users (name, email) VALUES ($1, $2) ON CONFLICT (email) DO NOTHING

-- DO UPDATE
INSERT INTO users (name, email) VALUES ($1, $2)
ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name

-- 部分唯一索引
INSERT INTO users (name, email) VALUES ($1, $2)
ON CONFLICT (email) WHERE active = true
DO UPDATE SET name = EXCLUDED.name
```

### 4. 错误处理策略

#### 编译时错误
```zig
@compileError("ON CONFLICT is not supported by " ++ @tagName(dialect))
```

#### 运行时错误
```zig
pub const InsertError = error{
    // 现有错误...

    // ON CONFLICT 相关错误
    EmptyConflictTarget,        // 冲突列数组为空
    ConflictTargetNotSet,       // 未调用 onConflict()
    ConflictActionNotSet,       // 未调用 doNothing() 或 doUpdate()
    EmptyUpdateAssignments,     // doUpdate() 表达式为空
    UpdateAssignmentsNotSet,    // doUpdate() 但未设置更新表达式
    EmptyWhereCondition,        // whereConflict() 条件为空
};
```

**错误消息示例**:
```
error: ConflictTargetNotSet
note: must call onConflict() before doNothing() or doUpdate()
```

### 5. 与现有功能集成

#### RETURNING 子句
ON CONFLICT 与 RETURNING 完全兼容:
```zig
var upserted = std.ArrayList(User).init(allocator);
defer upserted.deinit();

try query
    .value(user)
    .onConflict(&.{"email"})
    .doUpdate("name = EXCLUDED.name")
    .returning(&.{"*"})
    .execReturning(&upserted);
```

生成 SQL:
```sql
INSERT INTO users (name, email) VALUES ($1, $2)
ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name
RETURNING *
```

#### 批量插入
ON CONFLICT 支持批量插入:
```zig
_ = try query
    .values(&users)  // 批量插入
    .onConflict(&.{"email"})
    .doUpdate("updated_at = CURRENT_TIMESTAMP")
    .exec();
```

生成 SQL:
```sql
INSERT INTO users (name, email) VALUES ($1, $2), ($3, $4), ($5, $6)
ON CONFLICT (email) DO UPDATE SET updated_at = CURRENT_TIMESTAMP
```

## Migration Strategy

### 步骤 1: 内部状态重构
1. 添加新字段: `conflict_target`, `conflict_action`, `conflict_updates`, `conflict_where`
2. 保留旧字段 `on_conflict` (暂时)

### 步骤 2: 实现新 API 方法
1. 实现 `onConflict()`, `doNothing()`, `doUpdate()`, `whereConflict()`
2. 更新 `build()` 方法读取新字段

### 步骤 3: 更新测试
1. 重构现有 ON CONFLICT 测试使用新 API
2. 添加新边界情况测试
3. 添加集成测试

### 步骤 4: 移除旧 API
1. 删除 `on_conflict` 字段
2. 删除旧 `onConflict(OnConflictClause)` 实现

## Testing Strategy

### 单元测试
1. **正常流程测试**:
   - DO NOTHING 基础功能
   - DO UPDATE 基础功能
   - WHERE 条件支持
   - 与 RETURNING 集成

2. **边界情况测试**:
   - 空列名数组 → `EmptyConflictTarget`
   - 未调用 `onConflict()` → `ConflictTargetNotSet`
   - 空更新表达式 → `EmptyUpdateAssignments`
   - 多列冲突目标
   - 复杂 SQL 表达式

3. **编译时测试**:
   - 非 PostgreSQL 方言编译失败

### 集成测试
1. **真实数据库测试**:
   - 创建带唯一约束的表
   - 插入冲突数据验证 DO NOTHING
   - 插入冲突数据验证 DO UPDATE
   - 验证 EXCLUDED 关键字正确性
   - 部分唯一索引 WHERE 条件

2. **性能测试**:
   - 批量 UPSERT 性能基准

## Open Questions
1. ~~是否需要自动推断冲突列?~~ → **否**,要求用户显式指定
2. ~~是否需要解析 UPDATE 表达式?~~ → **否**,接受原始 SQL 字符串
3. ~~是否需要支持约束名称 (ON CONSTRAINT)?~~ → **未来变更**

## References
- [PostgreSQL ON CONFLICT 官方文档](https://www.postgresql.org/docs/current/sql-insert.html#SQL-ON-CONFLICT)
- PRD Story 4.1: PostgreSQL ON CONFLICT (Upsert) Support
- 现有实现: `src/query/query.zig:1020-1028`
