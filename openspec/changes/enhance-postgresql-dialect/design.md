# Design: enhance-postgresql-dialect

## Architecture Overview

本设计文档描述 ZORM PostgreSQL 方言系统的 comptime 增强架构，确保零运行时开销并与功能规格 2.1.4 对齐。

## System Context

```
┌─────────────────────────────────────────────────────────┐
│                  ZORM Application                        │
│  ┌────────────┐  ┌────────────┐  ┌──────────────┐      │
│  │ Query      │  │ Schema     │  │ Migration    │      │
│  │ Builder    │  │ Definition │  │ System       │      │
│  └─────┬──────┘  └─────┬──────┘  └──────┬───────┘      │
│        │               │                 │              │
│        └───────────────┴─────────────────┘              │
│                        │                                │
│                        ▼                                │
│        ┌────────────────────────────────┐               │
│        │   Dialect System (Comptime)    │◄────────┐    │
│        │  ┌──────────────────────────┐  │         │    │
│        │  │ Feature Detection        │  │         │    │
│        │  │ • supports(feature)      │  │         │    │
│        │  │ • supportsReturning()    │  │   Compile    │
│        │  │ • supportsOnConflict()   │  │    Time      │
│        │  └──────────────────────────┘  │  Dispatch    │
│        │  ┌──────────────────────────┐  │         │    │
│        │  │ SQL Generation           │  │         │    │
│        │  │ • placeholder()          │  │         │    │
│        │  │ • quoteIdentifier()      │  │         │    │
│        │  │ • limitClause()          │  │         │    │
│        │  └──────────────────────────┘  │         │    │
│        │  ┌──────────────────────────┐  │         │    │
│        │  │ Dialect Dispatch         │  │         │    │
│        │  │ • dialectDispatch()      │──┘         │    │
│        │  │ • @compileError on fail  │            │    │
│        │  └──────────────────────────┘            │    │
│        └────────────────┬───────────────          │    │
│                         │                         │    │
│                         ▼                         │    │
│          ┌──────────────────────────┐             │    │
│          │ PostgreSQL Driver        │             │    │
│          │ (Runtime Execution)      │             │    │
│          └──────────────────────────┘             │    │
└─────────────────────────────────────────────────────────┘
```

## Component Design

### 1. Feature Enumeration

#### Current Implementation
```zig
pub const Feature = enum {
    returning,
    cte,
    arrays,
    jsonb,
    on_conflict,
    window_functions,
    lateral_join,
    upsert,
    generate_series,
    listen_notify,
};
```

#### Proposed Enhancement
```zig
pub const Feature = enum {
    // DML Features
    returning,
    on_conflict,
    insert_ignore,
    on_duplicate_key,
    merge,
    upsert,

    // Query Features
    cte,
    window_functions,
    lateral_join,

    // Data Types
    arrays,
    jsonb,
    uuid,

    // PostgreSQL Specific
    generate_series,
    listen_notify,
    full_text_search,

    // DDL Features
    create_index_concurrently,
    drop_index_concurrently,
};
```

**Rationale**:
- 按功能类别分组，提高可读性
- 添加 PostgreSQL 独有特性（如 `full_text_search`）
- 为未来扩展预留空间

### 2. Comptime Dialect Dispatch

#### Interface Design
```zig
/// 编译时方言分派
///
/// 如果方言不支持指定特性，在编译时触发错误。
/// 这确保了不支持的 SQL 特性无法编译通过。
///
/// 参数:
/// - feature: 要检查的特性标志
/// - callback: 特性支持时执行的 comptime 函数
///
/// 示例:
/// ```zig
/// dialectDispatch(.postgresql, .returning, struct {
///     pub fn apply() []const u8 {
///         return " RETURNING *";
///     }
/// }.apply);
/// ```
pub fn dialectDispatch(
    comptime dialect: Dialect,
    comptime feature: Feature,
    comptime callback: anytype,
) @TypeOf(callback()) {
    if (comptime dialect.supports(feature)) {
        return callback();
    } else {
        @compileError(std.fmt.comptimePrint(
            "Dialect {s} does not support feature {s}",
            .{ @tagName(dialect), @tagName(feature) },
        ));
    }
}
```

#### Usage Example
```zig
// ✅ 编译通过 - PostgreSQL 支持 RETURNING
const returning_clause = dialectDispatch(.postgresql, .returning, struct {
    pub fn apply() []const u8 {
        return " RETURNING id, name";
    }
}.apply);

// ❌ 编译错误 - PostgreSQL 不支持 OUTPUT (SQL Server 特性)
const output_clause = dialectDispatch(.postgresql, .output_clause, struct {
    pub fn apply() []const u8 {
        return " OUTPUT INSERTED.*";
    }
}.apply);
// 编译器错误: Dialect postgresql does not support feature output_clause
```

### 3. SQL Generation Utilities

#### Enhanced Placeholder Generation
```zig
/// 编译时占位符生成 (零分配)
pub fn placeholder(comptime dialect: Dialect, comptime index: usize) []const u8 {
    return comptime switch (dialect) {
        .postgresql => std.fmt.comptimePrint("${d}", .{index}),
    };
}

/// 运行时占位符生成 (使用 allocator)
pub fn placeholderAlloc(comptime dialect: Dialect, allocator: Allocator, index: usize) ![]const u8 {
    return switch (dialect) {
        .postgresql => try std.fmt.allocPrint(allocator, "${d}", .{index}),
    };
}
```

#### Enhanced LIMIT/OFFSET Clause
```zig
/// 编译时 LIMIT/OFFSET 生成
///
/// PostgreSQL 特性:
/// - 支持 LIMIT without OFFSET
/// - 支持 OFFSET without LIMIT
/// - 支持 LIMIT ... OFFSET ...
///
/// 示例:
/// ```zig
/// const clause1 = limitClause(.postgresql, 10, null);    // " LIMIT 10"
/// const clause2 = limitClause(.postgresql, 10, 5);       // " LIMIT 10 OFFSET 5"
/// const clause3 = limitClause(.postgresql, null, 5);     // " OFFSET 5"
/// const clause4 = limitClause(.postgresql, null, null);  // ""
/// ```
pub fn limitClause(
    comptime dialect: Dialect,
    comptime limit: ?usize,
    comptime offset: ?usize,
) []const u8 {
    return comptime switch (dialect) {
        .postgresql => blk: {
            if (limit) |l| {
                if (offset) |o| {
                    break :blk std.fmt.comptimePrint(" LIMIT {d} OFFSET {d}", .{ l, o });
                } else {
                    break :blk std.fmt.comptimePrint(" LIMIT {d}", .{l});
                }
            } else if (offset) |o| {
                break :blk std.fmt.comptimePrint(" OFFSET {d}", .{o});
            } else {
                break :blk "";
            }
        },
    };
}
```

#### UPSERT Clause Generation
```zig
/// 编译时 UPSERT 子句生成
///
/// PostgreSQL: ON CONFLICT
/// MySQL: ON DUPLICATE KEY UPDATE
/// SQLite: ON CONFLICT
///
/// 示例:
/// ```zig
/// const pg_upsert = upsertClause(.postgresql); // "ON CONFLICT"
/// ```
pub fn upsertClause(comptime dialect: Dialect) []const u8 {
    return comptime switch (dialect) {
        .postgresql => "ON CONFLICT",
    };
}
```

### 4. Type Safety and Boundaries

#### Comptime Type Constraints
```zig
/// 确保函数在 comptime 执行
pub fn ensureComptime(comptime T: type) void {
    // 强制 comptime 求值
    comptime {
        _ = T;
    }
}

/// Comptime 类型检查示例
test "comptime type safety" {
    comptime {
        // 确保 placeholder 返回编译时已知字符串
        const ph = Dialect.postgresql.placeholder(1);
        ensureComptime(@TypeOf(ph)); // 编译时字符串切片

        // 确保 supports 返回编译时已知布尔值
        const sup = Dialect.postgresql.supports(.returning);
        ensureComptime(@TypeOf(sup)); // 编译时布尔值
    }
}
```

## Data Flow

### Compile-Time Flow
```
User Code (Query Builder)
    │
    ├─ comptime dialect = .postgresql
    │
    ▼
Dialect.supports(.returning)  ◄─── Comptime evaluation
    │
    ├─ true  ──► Generate " RETURNING *"
    │
    └─ false ──► @compileError("Not supported")
    │
    ▼
SQL String (comptime known)
    │
    ▼
Runtime Execution (Driver)
```

### Runtime Flow (Minimal)
```
Query Execution
    │
    ├─ SQL String (comptime generated)
    │
    ├─ Parameters (runtime values)
    │
    ▼
Driver.exec(sql, params)
    │
    ▼
PostgreSQL Database
```

## Error Handling

### Compile-Time Errors
```zig
// 场景 1: 不支持的特性
if (!comptime Dialect.postgresql.supports(.merge)) {
    @compileError("PostgreSQL does not support MERGE statement");
}

// 场景 2: 类型不匹配
const result = dialectDispatch(.postgresql, .returning, 42); // 错误: 期望函数
// 编译错误: expected function, found comptime_int
```

### Runtime Errors (Delegation to Driver)
```zig
// 方言层不处理运行时错误，由驱动层负责
const result = db.exec(sql, params); // !Result
if (result) |r| {
    // 成功
} else |err| {
    // 驱动层错误: ConnectionFailed, QueryFailed, etc.
}
```

## Performance Considerations

### Zero Runtime Overhead
- **所有方言决策在编译时完成**：无运行时分支
- **SQL 字符串编译时生成**：无动态字符串拼接
- **类型信息编译时已知**：无反射开销

### Memory Allocation
- **Comptime 函数**：零分配（`placeholder()`, `limitClause()`）
- **Runtime 函数**：显式 allocator 参数（`placeholderAlloc()`）
- **调用者负责内存管理**：清晰的所有权语义

### Code Size
- **单方言专用**：避免多方言分支膨胀代码
- **内联优化**：Zig 编译器内联 comptime 函数

## Testing Strategy

### Unit Tests (Comptime)
```zig
test "all features are tested" {
    comptime {
        inline for (@typeInfo(Feature).Enum.fields) |field| {
            const feature: Feature = @enumFromInt(field.value);
            const supported = Dialect.postgresql.supports(feature);
            _ = supported; // 确保所有特性都有 supports() 分支
        }
    }
}

test "dialectDispatch compiles on supported features" {
    const result = dialectDispatch(.postgresql, .returning, struct {
        pub fn apply() []const u8 {
            return "RETURNING *";
        }
    }.apply);

    try std.testing.expectEqualStrings("RETURNING *", result);
}

// 注意: 无法直接测试 @compileError，只能通过手动验证
// 或使用外部编译测试工具
```

### Integration Tests
```zig
test "query builder uses dialect features" {
    const User = struct {
        id: i64,
        name: []const u8,
    };

    var db = try DB(.postgresql).init(allocator, conn, .{});
    defer db.deinit();

    var insert = try db.newInsert(User);
    defer insert.deinit();

    // 使用 RETURNING (PostgreSQL 支持)
    try insert.setReturning("*");

    const sql = try insert.buildSQL();
    defer allocator.free(sql);

    // 验证 SQL 包含 RETURNING 子句
    try std.testing.expect(std.mem.indexOf(u8, sql, "RETURNING *") != null);
}
```

## Migration Path

### Phase 1: Feature Enumeration (Week 1)
- 扩展 `Feature` 枚举，添加新特性
- 更新 `supports()` 实现
- 添加便捷检测函数（如 `supportsFullTextSearch()`）

### Phase 2: Dialect Dispatch (Week 2)
- 实现 `dialectDispatch()` 函数
- 添加编译时错误检测测试
- 更新文档和示例

### Phase 3: SQL Utilities (Week 3)
- 增强 `limitClause()`, `upsertClause()` 等工具函数
- 添加新的 SQL 生成工具（如 `timestampClause()`）
- 完善运行时 allocator 版本

### Phase 4: Integration (Week 4)
- 将新特性集成到查询构建器
- 更新 Schema 系统使用新的方言 API
- 性能基准测试和优化

### Phase 5: Documentation (Week 5)
- 更新 API 文档
- 编写使用指南和最佳实践
- 创建迁移指南（如果有破坏性变更）

## Security Considerations

### SQL Injection Prevention
- **Comptime 生成确保安全**：无动态字符串拼接
- **运行时参数绑定**：使用占位符 (`$1`, `$2`)
- **标识符转义**：`escapeIdentifier()` 防止注入

### Type Safety
- **Comptime 类型检查**：错误的类型在编译时被捕获
- **明确的错误处理**：所有运行时错误通过 `!T` 传播

## Monitoring and Observability

### Compile-Time Metrics
- **编译时间**：通过 `zig build` 输出监控
- **代码大小**：通过 `zig build-lib -fstrip` 检查

### Runtime Metrics (Out of Scope for Dialect)
- 查询执行时间、错误率等由 DB 层和钩子系统处理
- 方言层保持纯编译时抽象

## Open Issues

### Issue 1: PostgreSQL 版本差异
**问题**：不同 PostgreSQL 版本（如 12, 13, 14, 15+）支持的特性不同。

**当前方案**：假设使用现代 PostgreSQL（14+），不做版本检测。

**未来考虑**：可添加 `DialectVersion` 参数：
```zig
pub fn supports(
    comptime dialect: Dialect,
    comptime version: ?u32, // PostgreSQL 版本
    comptime feature: Feature,
) bool
```

### Issue 2: PostgreSQL 扩展支持
**问题**：PostGIS, TimescaleDB 等扩展引入新的 SQL 特性。

**当前方案**：暂不支持，等待实际需求。

**未来考虑**：添加 `Extension` 枚举和 `hasExtension()` 检测。

### Issue 3: 运行时与编译时的边界
**问题**：某些场景需要运行时决策（如根据配置文件选择方言）。

**当前方案**：ZORM 是 PostgreSQL 专用，无此需求。

**未来考虑**：如果引入多方言，需设计运行时分派机制（与当前 comptime 设计冲突）。

## Alternatives Evaluated

### Alternative 1: Runtime Dispatch with Enums
**描述**：使用运行时枚举切换，而非 comptime。

**优点**：运行时灵活性。

**缺点**：
- 引入运行时开销
- 违背 Zig 零成本抽象
- 增加代码复杂度

**决策**：❌ 不采纳

### Alternative 2: Trait-Based Design
**描述**：使用 Zig 的接口/trait 模式（通过 vtable）。

**优点**：更灵活的多态。

**缺点**：
- 运行时 vtable 查找
- 与 comptime 优先理念冲突
- PostgreSQL 专用场景不需要多态

**决策**：❌ 不采纳

### Alternative 3: Macro-Based Code Generation
**描述**：使用宏生成不同方言的代码。

**优点**：编译时生成，无运行时开销。

**缺点**：
- Zig 无传统宏系统
- comptime 已提供更好的解决方案
- 可读性和调试性差

**决策**：❌ 不采纳

## Future Considerations

### Potential Enhancements
1. **PostgreSQL 特定优化**：
   - `COPY` 命令支持（批量导入）
   - `LISTEN/NOTIFY` 事件系统
   - Full-text search 全文搜索

2. **Schema 迁移集成**：
   - 利用方言特性生成迁移 SQL
   - 版本兼容性检查

3. **性能分析工具**：
   - 编译时 SQL 复杂度分析
   - 查询计划提示生成

### Deprecation Plan
- 无计划废弃现有 API
- 所有变更向后兼容
- 新增功能通过新函数提供

## Conclusion

本设计通过完善 ZORM 的 PostgreSQL 方言 comptime 实现，确保：
- ✅ 零运行时开销
- ✅ 完整的特性覆盖
- ✅ 类型安全和编译时错误检测
- ✅ 与功能规格 2.1.4 对齐
- ✅ 保持 PostgreSQL 专用定位

所有设计决策优先考虑性能和类型安全，利用 Zig 的 comptime 特性实现零成本抽象。
