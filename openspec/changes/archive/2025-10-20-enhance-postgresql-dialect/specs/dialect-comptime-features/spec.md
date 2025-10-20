# dialect-comptime-features Specification

## Purpose
定义 ZORM PostgreSQL 方言系统的编译时特性检测、SQL 生成和方言分派机制，确保零运行时开销和类型安全。

## ADDED Requirements

### Requirement: 完整的特性枚举

PostgreSQL 方言 MUST 定义完整的 Feature 枚举，覆盖所有支持的 SQL 特性。

#### Scenario: Feature 枚举包含 DML 特性

**Given** PostgreSQL 方言系统
**When** 定义 `Feature` 枚举
**Then** MUST 包含以下 DML 特性：
- `returning` - RETURNING 子句
- `on_conflict` - ON CONFLICT 子句
- `upsert` - UPSERT 操作
**And** 每个特性都有清晰的文档注释

**示例代码**:
```zig
pub const Feature = enum {
    // DML Features
    /// INSERT/UPDATE/DELETE RETURNING 支持
    returning,
    /// INSERT ON CONFLICT 支持
    on_conflict,
    /// UPSERT 操作支持
    upsert,
    // ...
};

test "DML features defined" {
    comptime {
        _ = Feature.returning;
        _ = Feature.on_conflict;
        _ = Feature.upsert;
    }
}
```

#### Scenario: Feature 枚举包含查询特性

**Given** PostgreSQL 方言系统
**When** 定义 `Feature` 枚举
**Then** MUST 包含以下查询特性：
- `cte` - CTE (Common Table Expression)
- `window_functions` - 窗口函数
- `lateral_join` - LATERAL JOIN

**示例代码**:
```zig
pub const Feature = enum {
    // Query Features
    /// WITH (CTE) 支持
    cte,
    /// 窗口函数 (OVER, PARTITION BY)
    window_functions,
    /// LATERAL JOIN 支持
    lateral_join,
    // ...
};
```

#### Scenario: Feature 枚举包含数据类型特性

**Given** PostgreSQL 方言系统
**When** 定义 `Feature` 枚举
**Then** MUST 包含以下数据类型特性：
- `arrays` - 数组类型
- `jsonb` - JSONB 类型
- `uuid` - UUID 类型

**示例代码**:
```zig
pub const Feature = enum {
    // Data Types
    /// 数组类型支持
    arrays,
    /// JSONB 类型支持
    jsonb,
    /// UUID 类型支持
    uuid,
    // ...
};
```

#### Scenario: Feature 枚举包含 PostgreSQL 特有特性

**Given** PostgreSQL 方言系统
**When** 定义 `Feature` 枚举
**Then** MUST 包含以下 PostgreSQL 特有特性：
- `generate_series` - generate_series 函数
- `listen_notify` - LISTEN/NOTIFY 事件系统
- `full_text_search` - 全文搜索

**示例代码**:
```zig
pub const Feature = enum {
    // PostgreSQL Specific
    /// generate_series 函数支持
    generate_series,
    /// LISTEN/NOTIFY 事件系统
    listen_notify,
    /// 全文搜索 (tsvector, tsquery)
    full_text_search,
    // ...
};
```

---

### Requirement: Comptime 特性检测

方言系统 MUST 提供 comptime 特性检测函数，确保所有决策在编译时完成。

#### Scenario: supports() 函数编译时求值

**Given** PostgreSQL 方言和特性标志
**When** 调用 `Dialect.postgresql.supports(feature)`
**Then** MUST 在编译时返回布尔值
**And** 不产生任何运行时代码

**示例代码**:
```zig
test "supports() is comptime" {
    comptime {
        const supports_returning = Dialect.postgresql.supports(.returning);
        std.debug.assert(supports_returning == true);

        const supports_merge = Dialect.postgresql.supports(.merge);
        std.debug.assert(supports_merge == false);
    }
}
```

#### Scenario: 所有特性都有 supports() 分支

**Given** Feature 枚举中的所有特性
**When** 实现 `supports()` 函数
**Then** MUST 为每个特性提供明确的 true/false 分支
**And** 不使用 else 分支（防止遗漏）

**示例代码**:
```zig
pub fn supports(comptime self: Dialect, comptime feature: Feature) bool {
    _ = self; // PostgreSQL 专用
    return comptime switch (feature) {
        .returning => true,
        .cte => true,
        .arrays => true,
        .jsonb => true,
        .on_conflict => true,
        .window_functions => true,
        .lateral_join => true,
        .upsert => true,
        .generate_series => true,
        .listen_notify => true,
        .full_text_search => true,
        .uuid => true,
        // 不支持的特性
        .merge => false,
        .output_clause => false,
        .on_duplicate_key => false,
        .insert_ignore => false,
        // 确保穷尽所有枚举值
    };
}

test "all features have supports() branch" {
    comptime {
        inline for (@typeInfo(Feature).Enum.fields) |field| {
            const feature: Feature = @enumFromInt(field.value);
            _ = Dialect.postgresql.supports(feature); // 编译时求值
        }
    }
}
```

#### Scenario: 便捷特性检测函数

**Given** 常用特性（如 RETURNING, ON CONFLICT）
**When** 提供便捷检测函数
**Then** MUST 实现 `supportsReturning()`, `supportsOnConflict()` 等
**And** 内部调用 `supports()` 函数

**示例代码**:
```zig
/// 检查是否支持 RETURNING 子句
pub fn supportsReturning(comptime self: Dialect) bool {
    return comptime self.supports(.returning);
}

/// 检查是否支持 ON CONFLICT 子句
pub fn supportsOnConflict(comptime self: Dialect) bool {
    return comptime self.supports(.on_conflict);
}

test "convenience functions work" {
    comptime {
        std.debug.assert(Dialect.postgresql.supportsReturning());
        std.debug.assert(Dialect.postgresql.supportsOnConflict());
        std.debug.assert(Dialect.postgresql.supportsCTE());
    }
}
```

---

### Requirement: 编译时 SQL 生成

方言系统 MUST 提供编译时 SQL 片段生成函数，确保零运行时分配。

#### Scenario: Comptime 占位符生成

**Given** 数据库方言和占位符索引
**When** 调用 `dialect.placeholder(index)`
**Then** MUST 在编译时生成占位符字符串
**And** PostgreSQL 生成 `$1`, `$2`, `$3`, ...
**And** 不分配任何堆内存

**示例代码**:
```zig
pub fn placeholder(comptime self: Dialect, comptime index: usize) []const u8 {
    _ = self; // PostgreSQL 专用
    return comptime std.fmt.comptimePrint("${d}", .{index});
}

test "comptime placeholder generation" {
    comptime {
        const ph1 = Dialect.postgresql.placeholder(1);
        std.debug.assert(std.mem.eql(u8, ph1, "$1"));

        const ph10 = Dialect.postgresql.placeholder(10);
        std.debug.assert(std.mem.eql(u8, ph10, "$10"));
    }
}
```

#### Scenario: Comptime 标识符引用

**Given** 数据库方言和标识符名称
**When** 调用 `dialect.quoteIdentifier(name)`
**Then** MUST 在编译时生成引用字符串
**And** PostgreSQL 生成 `"identifier"`

**示例代码**:
```zig
pub fn quoteIdentifier(comptime self: Dialect, comptime identifier: []const u8) []const u8 {
    const quotes = comptime self.identQuote();
    return comptime std.fmt.comptimePrint("{c}{s}{c}", .{ quotes.left, identifier, quotes.right });
}

test "comptime identifier quoting" {
    comptime {
        const quoted = Dialect.postgresql.quoteIdentifier("users");
        std.debug.assert(std.mem.eql(u8, quoted, "\"users\""));

        const quoted_col = Dialect.postgresql.quoteIdentifier("user_id");
        std.debug.assert(std.mem.eql(u8, quoted_col, "\"user_id\""));
    }
}
```

#### Scenario: Comptime LIMIT/OFFSET 子句生成

**Given** LIMIT 和 OFFSET 值（可选）
**When** 调用 `dialect.limitClause(limit, offset)`
**Then** MUST 在编译时生成完整的 LIMIT/OFFSET 子句
**And** 支持 LIMIT only, OFFSET only, 或两者皆有

**示例代码**:
```zig
pub fn limitClause(
    comptime self: Dialect,
    comptime limit: ?usize,
    comptime offset: ?usize,
) []const u8 {
    _ = self; // PostgreSQL 专用
    return comptime blk: {
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
    };
}

test "comptime LIMIT/OFFSET generation" {
    comptime {
        const clause1 = Dialect.postgresql.limitClause(10, 5);
        std.debug.assert(std.mem.eql(u8, clause1, " LIMIT 10 OFFSET 5"));

        const clause2 = Dialect.postgresql.limitClause(10, null);
        std.debug.assert(std.mem.eql(u8, clause2, " LIMIT 10"));

        const clause3 = Dialect.postgresql.limitClause(null, 5);
        std.debug.assert(std.mem.eql(u8, clause3, " OFFSET 5"));

        const clause4 = Dialect.postgresql.limitClause(null, null);
        std.debug.assert(std.mem.eql(u8, clause4, ""));
    }
}
```

#### Scenario: Comptime UPSERT 子句生成

**Given** 数据库方言
**When** 调用 `dialect.upsertClause()`
**Then** MUST 返回编译时 UPSERT 关键字
**And** PostgreSQL 返回 `"ON CONFLICT"`

**示例代码**:
```zig
pub fn upsertClause(comptime self: Dialect) []const u8 {
    _ = self; // PostgreSQL 专用
    return "ON CONFLICT";
}

test "comptime upsert clause" {
    comptime {
        const upsert = Dialect.postgresql.upsertClause();
        std.debug.assert(std.mem.eql(u8, upsert, "ON CONFLICT"));
    }
}
```

---

### Requirement: 编译时方言分派

方言系统 MUST 提供编译时方言分派机制，不支持的特性在编译时触发错误。

#### Scenario: dialectDispatch 调用成功

**Given** 数据库方言和支持的特性
**When** 调用 `dialectDispatch(dialect, feature, callback)`
**Then** MUST 在编译时执行 callback
**And** 返回 callback 的结果

**示例代码**:
```zig
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

test "dialectDispatch with supported feature" {
    const result = dialectDispatch(.postgresql, .returning, struct {
        pub fn apply() []const u8 {
            return " RETURNING *";
        }
    }.apply);

    try std.testing.expectEqualStrings(" RETURNING *", result);
}
```

#### Scenario: dialectDispatch 触发编译错误

**Given** 数据库方言和不支持的特性
**When** 调用 `dialectDispatch(dialect, unsupported_feature, callback)`
**Then** MUST 触发 `@compileError`
**And** 错误信息包含方言名称和特性名称

**示例**:
```zig
// 这段代码会触发编译错误，无法编写为测试
// 手动验证示例：

// const result = dialectDispatch(.postgresql, .merge, struct {
//     pub fn apply() []const u8 {
//         return " MERGE INTO ...";
//     }
// }.apply);

// 编译器输出:
// error: Dialect postgresql does not support feature merge
```

#### Scenario: dialectDispatch 类型安全

**Given** dialectDispatch 函数
**When** callback 返回类型不一致
**Then** MUST 在编译时触发类型错误
**And** 提示类型不匹配

**示例**:
```zig
test "dialectDispatch type safety" {
    // 正确: callback 返回 []const u8
    const str_result = dialectDispatch(.postgresql, .returning, struct {
        pub fn apply() []const u8 {
            return "RETURNING *";
        }
    }.apply);
    _ = str_result;

    // 正确: callback 返回 bool
    const bool_result = dialectDispatch(.postgresql, .cte, struct {
        pub fn apply() bool {
            return true;
        }
    }.apply);
    _ = bool_result;

    // 编译错误示例（无法写为测试）:
    // const mixed = dialectDispatch(.postgresql, .returning, struct {
    //     pub fn apply() i32 {  // 返回类型不一致
    //         return 42;
    //     }
    // }.apply);
    // 编译器会推断出正确的返回类型 i32
}
```

---

### Requirement: 运行时占位符生成

方言系统 MUST 提供运行时占位符生成函数，用于动态查询场景。

#### Scenario: placeholderAlloc 使用 allocator

**Given** Allocator 和占位符索引
**When** 调用 `dialect.placeholderAlloc(allocator, index)`
**Then** MUST 使用 allocator 分配内存
**And** 返回堆分配的占位符字符串
**And** 调用者负责释放内存

**示例代码**:
```zig
pub fn placeholderAlloc(comptime self: Dialect, allocator: Allocator, index: usize) ![]const u8 {
    _ = self; // PostgreSQL 专用
    return try std.fmt.allocPrint(allocator, "${d}", .{index});
}

test "runtime placeholder allocation" {
    const allocator = std.testing.allocator;

    const ph1 = try Dialect.postgresql.placeholderAlloc(allocator, 1);
    defer allocator.free(ph1);
    try std.testing.expectEqualStrings("$1", ph1);

    const ph100 = try Dialect.postgresql.placeholderAlloc(allocator, 100);
    defer allocator.free(ph100);
    try std.testing.expectEqualStrings("$100", ph100);
}
```

#### Scenario: placeholderAlloc 错误处理

**Given** Allocator 分配失败
**When** 调用 `dialect.placeholderAlloc(allocator, index)`
**Then** MUST 返回 `error.OutOfMemory`
**And** 不泄漏任何内存

**示例代码**:
```zig
test "placeholderAlloc handles OutOfMemory" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, 0);

    const result = Dialect.postgresql.placeholderAlloc(failing_allocator.allocator(), 1);
    try std.testing.expectError(error.OutOfMemory, result);

    // 验证无内存泄漏（FailingAllocator 会检测）
}
```

---

### Requirement: SQL 工具函数

方言系统 MUST 提供 SQL 字符串转义和生成工具，防止 SQL 注入。

#### Scenario: escapeIdentifier 正确转义

**Given** 包含特殊字符的标识符
**When** 调用 `escapeIdentifier(allocator, dialect, identifier)`
**Then** MUST 正确转义双引号字符（双写）
**And** 返回被引用的标识符

**示例代码**:
```zig
test "escapeIdentifier handles special characters" {
    const allocator = std.testing.allocator;

    // 正常标识符
    const escaped1 = try escapeIdentifier(allocator, .postgresql, "users");
    defer allocator.free(escaped1);
    try std.testing.expectEqualStrings("\"users\"", escaped1);

    // 包含双引号的标识符
    const escaped2 = try escapeIdentifier(allocator, .postgresql, "user\"table");
    defer allocator.free(escaped2);
    try std.testing.expectEqualStrings("\"user\"\"table\"", escaped2);
}
```

#### Scenario: escapeString 防止注入

**Given** 包含单引号的字符串
**When** 调用 `escapeString(allocator, dialect, str)`
**Then** MUST 正确转义单引号（双写）
**And** 返回被单引号包裹的字符串字面量

**示例代码**:
```zig
test "escapeString prevents SQL injection" {
    const allocator = std.testing.allocator;

    // 正常字符串
    const escaped1 = try escapeString(allocator, .postgresql, "hello");
    defer allocator.free(escaped1);
    try std.testing.expectEqualStrings("'hello'", escaped1);

    // 包含单引号（SQL 注入尝试）
    const escaped2 = try escapeString(allocator, .postgresql, "it's");
    defer allocator.free(escaped2);
    try std.testing.expectEqualStrings("'it''s'", escaped2);

    // 恶意 SQL 注入尝试
    const malicious = "admin' OR '1'='1";
    const escaped3 = try escapeString(allocator, .postgresql, malicious);
    defer allocator.free(escaped3);
    try std.testing.expectEqualStrings("'admin'' OR ''1''=''1'", escaped3);
}
```

#### Scenario: buildInClause 生成占位符列表

**Given** IN 子句中值的数量
**When** 调用 `buildInClause(allocator, dialect, count, start_index)`
**Then** MUST 生成 `IN ($1, $2, $3, ...)` 格式的字符串
**And** 占位符数量等于 count

**示例代码**:
```zig
test "buildInClause generates correct placeholder list" {
    const allocator = std.testing.allocator;

    const in_clause = try buildInClause(allocator, .postgresql, 3, 1);
    defer allocator.free(in_clause);
    try std.testing.expectEqualStrings("IN ($1, $2, $3)", in_clause);

    const in_clause2 = try buildInClause(allocator, .postgresql, 5, 10);
    defer allocator.free(in_clause2);
    try std.testing.expectEqualStrings("IN ($10, $11, $12, $13, $14)", in_clause2);
}
```

---

### Requirement: 零运行时开销保证

方言系统 MUST 确保所有编译时决策不产生运行时代码。

#### Scenario: Comptime 函数零分配

**Given** 编译时方言函数（placeholder, quoteIdentifier, limitClause）
**When** 在 comptime 块中调用
**Then** MUST 不产生任何堆分配
**And** 不产生任何运行时代码

**示例代码**:
```zig
test "comptime functions zero allocation" {
    comptime {
        // 这些调用完全在编译时求值，零运行时开销
        const ph = Dialect.postgresql.placeholder(1);
        const quoted = Dialect.postgresql.quoteIdentifier("users");
        const limit = Dialect.postgresql.limitClause(10, 5);

        _ = ph;
        _ = quoted;
        _ = limit;

        // 如果有运行时代码，Zig 会在编译时警告
    }
}
```

#### Scenario: supports() 编译时常量折叠

**Given** supports() 函数调用
**When** 在条件分支中使用
**Then** MUST 在编译时完成分支选择
**And** 死代码分支被编译器消除

**示例代码**:
```zig
fn conditionalSQL() []const u8 {
    if (comptime Dialect.postgresql.supports(.returning)) {
        // PostgreSQL 支持 RETURNING，这个分支会被保留
        return "INSERT INTO users (name) VALUES ($1) RETURNING id";
    } else {
        // 这个分支在编译时被消除（死代码）
        return "INSERT INTO users (name) VALUES ($1)";
    }
}

test "dead code elimination" {
    const sql = conditionalSQL();
    // 编译后的代码只包含第一个分支
    try std.testing.expect(std.mem.indexOf(u8, sql, "RETURNING") != null);
}
```

#### Scenario: dialectDispatch 无运行时分支

**Given** dialectDispatch 函数
**When** 编译包含 dialectDispatch 的代码
**Then** MUST 在编译时完成分派
**And** 生成的代码不包含条件分支

**示例代码**:
```zig
fn generateReturningClause() []const u8 {
    return dialectDispatch(.postgresql, .returning, struct {
        pub fn apply() []const u8 {
            return " RETURNING *";
        }
    }.apply);
}

test "dialectDispatch no runtime branching" {
    const clause = generateReturningClause();
    // 生成的代码直接返回常量字符串，无分支
    try std.testing.expectEqualStrings(" RETURNING *", clause);
}
```

---

### Requirement: 类型安全和边界检查

方言系统 MUST 利用 Zig 类型系统确保编译时类型安全。

#### Scenario: Comptime 参数类型检查

**Given** 方言函数要求 comptime 参数
**When** 传入运行时值
**Then** MUST 触发编译错误
**And** 提示参数必须是 comptime 已知

**示例**:
```zig
// 正确: comptime 参数
test "comptime parameter enforcement" {
    comptime {
        const ph = Dialect.postgresql.placeholder(1); // ✅ 编译时常量
        _ = ph;
    }
}

// 编译错误示例（无法写为测试）:
// fn runtimePlaceholder(index: usize) []const u8 {
//     return Dialect.postgresql.placeholder(index); // ❌ 编译错误: 期望 comptime 值
// }
```

#### Scenario: Feature 枚举穷尽性检查

**Given** Feature 枚举
**When** 在 switch 表达式中使用
**Then** MUST 编译器强制穷尽所有枚举值
**And** 缺少分支时触发编译错误

**示例代码**:
```zig
fn featureName(feature: Feature) []const u8 {
    return switch (feature) {
        .returning => "RETURNING",
        .cte => "CTE",
        .arrays => "Arrays",
        // ... 必须列举所有枚举值
        // 如果遗漏任何值，编译器会报错
    };
}

test "switch exhaustiveness" {
    const name = featureName(.returning);
    try std.testing.expectEqualStrings("RETURNING", name);
}
```

#### Scenario: 返回类型推导

**Given** dialectDispatch 和不同返回类型的 callback
**When** 编译器推导返回类型
**Then** MUST 正确推导 callback 的返回类型
**And** 类型不匹配时触发编译错误

**示例代码**:
```zig
test "return type inference" {
    // 推导为 []const u8
    const str_result: []const u8 = dialectDispatch(.postgresql, .returning, struct {
        pub fn apply() []const u8 {
            return "RETURNING *";
        }
    }.apply);
    _ = str_result;

    // 推导为 bool
    const bool_result: bool = dialectDispatch(.postgresql, .cte, struct {
        pub fn apply() bool {
            return true;
        }
    }.apply);
    _ = bool_result;

    // 推导为 usize
    const num_result: usize = dialectDispatch(.postgresql, .arrays, struct {
        pub fn apply() usize {
            return 42;
        }
    }.apply);
    _ = num_result;
}
```

---
