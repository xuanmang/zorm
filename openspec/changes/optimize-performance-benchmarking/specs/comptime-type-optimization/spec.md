# Spec: comptime-type-optimization

最大化利用 Zig comptime 特性，将类型映射和 SQL 模板生成移到编译时，减少运行时开销。

## ADDED Requirements

### Requirement: Comptime 生成 SQL 列名列表

MUST 在编译时生成表的列名列表，避免运行时反射。

#### Scenario: 编译时生成列名

```zig
fn generateColumnList(comptime T: type) []const u8 {
    const fields = @typeInfo(T).Struct.fields;
    comptime var result: []const u8 = "";

    inline for (fields, 0..) |field, i| {
        if (i > 0) {
            result = result ++ ", ";
        }
        result = result ++ field.name;
    }

    return result;
}

// 使用示例
const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
};

// 编译时生成："id, name, email"
const column_list = comptime generateColumnList(User);

// 运行时直接使用，无反射开销
fn buildSelectSQL() []const u8 {
    return "SELECT " ++ column_list ++ " FROM users";
}
```

#### Scenario: 编译时生成 INSERT 占位符

```zig
fn generatePlaceholders(comptime T: type) []const u8 {
    const fields = @typeInfo(T).Struct.fields;
    comptime var result: []const u8 = "";

    inline for (fields, 0..) |_, i| {
        if (i > 0) {
            result = result ++ ", ";
        }
        result = result ++ "$" ++ std.fmt.comptimePrint("{d}", .{i + 1});
    }

    return result;
}

// 编译时生成："$1, $2, $3"
const placeholders = comptime generatePlaceholders(User);
```

### Requirement: Comptime 类型映射表

MUST 构建编译时的 Zig 类型到 SQL 类型的映射表，避免运行时查找。

#### Scenario: 编译时类型映射

```zig
fn zigTypeToSQLType(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .Int => |int| switch (int.signedness) {
            .signed => switch (int.bits) {
                1...16 => "SMALLINT",
                17...32 => "INTEGER",
                33...64 => "BIGINT",
                else => @compileError("Unsupported integer size"),
            },
            .unsigned => switch (int.bits) {
                1...16 => "SMALLINT",
                17...32 => "INTEGER",
                33...64 => "BIGINT",
                else => @compileError("Unsupported integer size"),
            },
        },
        .Float => |float| switch (float.bits) {
            32 => "REAL",
            64 => "DOUBLE PRECISION",
            else => @compileError("Unsupported float size"),
        },
        .Bool => "BOOLEAN",
        .Pointer => |ptr| switch (ptr.size) {
            .Slice => if (ptr.child == u8) "TEXT" else @compileError("Unsupported slice type"),
            else => @compileError("Unsupported pointer type"),
        },
        .Optional => |opt| {
            const inner_type = zigTypeToSQLType(opt.child);
            return inner_type; // Optional 自动映射为 NULL 允许
        },
        else => @compileError("Unsupported type for SQL mapping"),
    };
}

// 使用示例
const User = struct {
    id: i64,         // comptime => "BIGINT"
    name: []const u8, // comptime => "TEXT"
    age: u32,        // comptime => "INTEGER"
    active: bool,    // comptime => "BOOLEAN"
};
```

### Requirement: 编译时 SQL 模板生成

MUST 为常见查询模式生成编译时的 SQL 模板，减少运行时字符串拼接。

#### Scenario: 编译时生成 SELECT 模板

```zig
fn generateSelectTemplate(comptime T: type) []const u8 {
    const table_name = getTableName(T);
    const column_list = generateColumnList(T);

    // 编译时生成 SQL 模板
    return comptime std.fmt.comptimePrint(
        "SELECT {s} FROM {s}",
        .{ column_list, table_name }
    );
}

// 运行时只需添加 WHERE、ORDER BY 等动态部分
fn buildSelectSQL(where_clause: []const u8) ![]const u8 {
    const base_sql = comptime generateSelectTemplate(User);

    var buffer = std.ArrayList(u8).init(allocator);
    try buffer.appendSlice(base_sql);
    if (where_clause.len > 0) {
        try buffer.appendSlice(" WHERE ");
        try buffer.appendSlice(where_clause);
    }
    return buffer.toOwnedSlice();
}
```

### Requirement: 测量 Comptime 优化的性能影响

MUST 验证 comptime 优化相比运行时反射的性能提升（目标：至少 40% 提升）。

#### Scenario: Comptime vs 运行时反射性能对比

```zig
test "comptime type mapping vs runtime reflection" {
    const allocator = std.testing.allocator;

    // 测试 1: Comptime 类型映射
    var comptime_timer = try std.time.Timer.start();
    {
        for (0..10000) |_| {
            // 编译时已生成，运行时直接使用
            _ = comptime generateColumnList(User);
            _ = comptime generateSelectTemplate(User);
        }
    }
    const comptime_time = comptime_timer.read();

    // 测试 2: 运行时反射
    var runtime_timer = try std.time.Timer.start();
    {
        for (0..10000) |_| {
            // 运行时通过 @typeInfo 反射
            const fields = @typeInfo(User).Struct.fields;
            var buffer = std.ArrayList(u8).init(allocator);
            defer buffer.deinit();
            for (fields, 0..) |field, i| {
                if (i > 0) try buffer.appendSlice(", ");
                try buffer.appendSlice(field.name);
            }
        }
    }
    const runtime_time = runtime_timer.read();

    // 验证 comptime 至少快 40%
    const speedup = @as(f64, @floatFromInt(runtime_time)) / @as(f64, @floatFromInt(comptime_time));
    try std.testing.expect(speedup >= 1.4);
}
```

## MODIFIED Requirements

### Requirement: 重构现有类型映射逻辑

MUST 将现有的运行时类型映射逻辑迁移到 comptime，保持 API 兼容性。

#### Scenario: 重构类型映射函数

```zig
// 旧代码（运行时反射）
fn getFieldSQLType(field: std.builtin.Type.StructField) []const u8 {
    // 运行时类型判断...
}

// 新代码（comptime）
fn getFieldSQLType(comptime T: type, comptime field_name: []const u8) []const u8 {
    const fields = @typeInfo(T).Struct.fields;
    inline for (fields) |field| {
        if (comptime std.mem.eql(u8, field.name, field_name)) {
            return comptime zigTypeToSQLType(field.type);
        }
    }
    @compileError("Field not found: " ++ field_name);
}
```
