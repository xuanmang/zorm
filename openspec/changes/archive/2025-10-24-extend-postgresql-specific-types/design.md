# Design: Extend PostgreSQL Specific Types

## Architecture Overview

本设计扩展 ZORM 的类型系统,在现有基础上添加 PostgreSQL 特有类型的完整支持,包括类型映射、序列化/反序列化和 Query Builder 集成。

### 核心模块

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Code                         │
│  const Article = struct {                                    │
│      tags: [][]const u8,  // TEXT[]                         │
│      metadata: []const u8, // JSONB                         │
│  };                                                          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              Type Mapping Layer (comptime)                   │
│  - zigToSQLType(): Zig type → SQLType enum                 │
│  - detectArrayType(): 检测数组元素类型                      │
│  - SQLType.toSQL(): SQLType → SQL 字符串                   │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│           Serialization Layer (runtime)                      │
│  - serializeArray(): []T → PostgreSQL array literal         │
│  - deserializeArray(): PG string → ArrayList(T)             │
│  - serializeJSON(): Zig value → JSON string                │
│  - deserializeJSON(): JSON → Zig value                      │
│  - serializeUUID(): [16]u8 → UUID string                    │
│  - deserializeUUID(): UUID string → [16]u8                  │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              Query Builder Integration                       │
│  - INSERT: 自动调用序列化函数                               │
│  - SELECT: 自动调用反序列化函数                             │
│  - CREATE TABLE: 生成正确的 SQL 类型定义                    │
└─────────────────────────────────────────────────────────────┘
```

## Type Mapping Design

### 数组类型映射

扩展 `zigToSQLType()` 函数,支持检测 slice 类型并映射到对应的 PostgreSQL 数组类型:

```zig
// 当前实现 (types.zig)
.pointer => |ptr_info| {
    if (ptr_info.size == .slice and ptr_info.child == u8) {
        return .text;  // []const u8 → TEXT
    }
    @compileError("Unsupported pointer type");
}

// 新设计
.pointer => |ptr_info| {
    if (ptr_info.size == .slice) {
        if (ptr_info.child == u8) {
            return .text;  // []const u8 → TEXT
        }
        // 检测数组元素类型
        const elem_sql_type = zigToSQLType(ptr_info.child);
        return mapToArrayType(elem_sql_type);
    }
    @compileError("Unsupported pointer type");
}
```

### SQLType 枚举扩展

添加数组类型变体到 `SQLType` enum:

```zig
pub const SQLType = enum {
    // ... 现有类型 ...

    // 数组类型
    integer_array,   // INTEGER[]
    bigint_array,    // BIGINT[]
    text_array,      // TEXT[]
    boolean_array,   // BOOLEAN[]
    real_array,      // REAL[]
    double_array,    // DOUBLE PRECISION[]
    timestamp_array, // TIMESTAMP[]
    uuid_array,      // UUID[]
    jsonb_array,     // JSONB[]

    pub fn toSQL(self: SQLType, comptime dialect: Dialect) []const u8 {
        return switch (self) {
            // ... 现有映射 ...
            .integer_array => "INTEGER[]",
            .bigint_array => "BIGINT[]",
            .text_array => "TEXT[]",
            .boolean_array => "BOOLEAN[]",
            .real_array => "REAL[]",
            .double_array => "DOUBLE PRECISION[]",
            .timestamp_array => "TIMESTAMP[]",
            .uuid_array => "UUID[]",
            .jsonb_array => "JSONB[]",
        };
    }
};
```

### 类型检测辅助函数

```zig
/// 将基础 SQLType 映射到对应的数组类型
fn mapToArrayType(base_type: SQLType) SQLType {
    return switch (base_type) {
        .integer => .integer_array,
        .bigint => .bigint_array,
        .text => .text_array,
        .boolean => .boolean_array,
        .real => .real_array,
        .double => .double_array,
        .timestamp => .timestamp_array,
        .uuid => .uuid_array,
        .jsonb => .jsonb_array,
        else => @compileError("Array of this type not supported"),
    };
}

/// 检测类型是否为数组类型
pub fn isArrayType(comptime T: type) bool {
    const type_info = @typeInfo(T);
    if (type_info == .pointer) {
        const ptr_info = type_info.pointer;
        return ptr_info.size == .slice and ptr_info.child != u8;
    }
    return false;
}

/// 获取数组元素类型
pub fn arrayElementType(comptime T: type) type {
    const type_info = @typeInfo(T);
    if (type_info != .pointer) {
        @compileError("Not a pointer type");
    }
    const ptr_info = type_info.pointer;
    if (ptr_info.size != .slice) {
        @compileError("Not a slice type");
    }
    return ptr_info.child;
}
```

## Serialization Design

### 数组序列化增强

当前 `serializeArray()` 已存在,需要确保:
1. 支持所有基础类型 (整数、浮点、布尔、字符串)
2. 正确处理 NULL 值 (可选类型)
3. 正确转义字符串中的特殊字符

```zig
pub fn serializeArray(comptime T: type, array: []const T, allocator: std.mem.Allocator) ![]const u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "'{");

    for (array, 0..) |item, i| {
        if (i > 0) try buf.append(allocator, ',');

        // 处理可选类型
        if (@typeInfo(T) == .optional) {
            if (item) |value| {
                try serializeElement(&buf, value, allocator);
            } else {
                try buf.appendSlice(allocator, "NULL");
            }
        } else {
            try serializeElement(&buf, item, allocator);
        }
    }

    try buf.appendSlice(allocator, "}'");

    defer buf.deinit(allocator);
    return allocator.dupe(u8, buf.items);
}

fn serializeElement(buf: *std.ArrayList(u8), item: anytype, allocator: std.mem.Allocator) !void {
    const T = @TypeOf(item);

    if (T == []const u8 or T == []u8) {
        // 字符串需要引号和转义
        try buf.append(allocator, '\"');
        try escapeString(buf, item, allocator);
        try buf.append(allocator, '\"');
    } else if (@typeInfo(T) == .int or @typeInfo(T) == .float) {
        const str = try std.fmt.allocPrint(allocator, "{any}", .{item});
        defer allocator.free(str);
        try buf.appendSlice(allocator, str);
    } else if (T == bool) {
        try buf.appendSlice(allocator, if (item) "t" else "f");
    } else {
        @compileError("Unsupported array element type");
    }
}

fn escapeString(buf: *std.ArrayList(u8), str: []const u8, allocator: std.mem.Allocator) !void {
    for (str) |ch| {
        if (ch == '\"' or ch == '\\') {
            try buf.append(allocator, '\\');
        }
        try buf.append(allocator, ch);
    }
}
```

### JSONB 序列化

使用 `std.json` 标准库:

```zig
pub fn serializeJSON(value: anytype, allocator: std.mem.Allocator) ![]const u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);

    try std.json.stringify(value, .{}, buf.writer(allocator));

    defer buf.deinit(allocator);
    return allocator.dupe(u8, buf.items);
}

pub fn deserializeJSON(comptime T: type, json_str: []const u8, allocator: std.mem.Allocator) !T {
    const parsed = try std.json.parseFromSlice(T, allocator, json_str, .{});
    defer parsed.deinit();

    // 深拷贝结果 (因为 parseFromSlice 的生命周期管理)
    return try deepCopy(T, parsed.value, allocator);
}

fn deepCopy(comptime T: type, value: T, allocator: std.mem.Allocator) !T {
    // 根据类型递归复制
    // 处理 struct, slice, optional 等情况
    // 详细实现略...
}
```

### UUID 序列化

```zig
pub fn serializeUUID(uuid: [16]u8) ![]const u8 {
    // UUID 格式: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    const hex = "0123456789abcdef";
    var buf: [36]u8 = undefined;

    inline for (0..16) |i| {
        const byte = uuid[i];
        const pos = switch (i) {
            0...3 => i * 2,
            4...5 => i * 2 + 1,
            6...7 => i * 2 + 2,
            8...9 => i * 2 + 3,
            10...15 => i * 2 + 4,
        };
        buf[pos] = hex[byte >> 4];
        buf[pos + 1] = hex[byte & 0x0F];
    }

    // 添加连字符
    buf[8] = '-';
    buf[13] = '-';
    buf[18] = '-';
    buf[23] = '-';

    return &buf;
}

pub fn deserializeUUID(uuid_str: []const u8) ![16]u8 {
    if (uuid_str.len != 36) return error.InvalidUUIDFormat;

    var result: [16]u8 = undefined;
    var byte_idx: usize = 0;

    for (uuid_str, 0..) |ch, i| {
        if (ch == '-') continue;

        const nibble = try parseHexDigit(ch);
        if (byte_idx % 2 == 0) {
            result[byte_idx / 2] = nibble << 4;
        } else {
            result[byte_idx / 2] |= nibble;
        }
        byte_idx += 1;
    }

    if (byte_idx != 32) return error.InvalidUUIDFormat;
    return result;
}

fn parseHexDigit(ch: u8) !u8 {
    return switch (ch) {
        '0'...'9' => ch - '0',
        'a'...'f' => ch - 'a' + 10,
        'A'...'F' => ch - 'A' + 10,
        else => error.InvalidHexDigit,
    };
}
```

## Query Builder Integration

### Column 生成 (reflection.zig)

`generateColumns()` 已正确处理 `custom_sql_type`,无需修改。数组类型通过 `zigToSQLType()` 自动检测:

```zig
// 现有代码已经支持
const sql_type = types.zigToSQLType(field.type);  // 自动检测数组
const col_type: ColumnType = mapSQLTypeToColumnType(sql_type);

columns[i] = .{
    .name = col_name,
    .column_type = col_type,
    .custom_sql_type = schema_cfg.sql_type,  // 优先使用自定义类型
    // ...
};
```

### INSERT 集成

在 `InsertQuery` 中,需要在参数绑定时调用序列化函数:

```zig
// src/query/insert.zig
pub fn bindValue(self: *InsertQuery, field_type: type, value: anytype) !void {
    const allocator = self.allocator;

    if (types.isArrayType(field_type)) {
        // 数组类型 → 序列化为 PostgreSQL 数组字面量
        const serialized = try types.serializeArray(
            types.arrayElementType(field_type),
            value,
            allocator
        );
        try self.addParam(serialized);
    } else if (field_type == []const u8 and isJSONBField(self.model, field_name)) {
        // JSONB 类型 → 直接作为 JSON 字符串
        try self.addParam(value);
    } else if (field_type == [16]u8 and isUUIDField(self.model, field_name)) {
        // UUID 类型 → 序列化为 UUID 字符串
        const serialized = try types.serializeUUID(value);
        try self.addParam(serialized);
    } else {
        // 普通类型 → 直接绑定
        try self.addParam(value);
    }
}
```

### SELECT 集成

在 `SelectQuery.scan()` 中,需要在结果扫描时调用反序列化函数:

```zig
// src/query/select.zig
pub fn scan(self: *SelectQuery, dest: anytype) !void {
    // 执行查询获取 PostgreSQL 结果
    const rows = try self.execute();
    defer rows.deinit();

    for (rows.items) |row| {
        var item: T = undefined;

        inline for (@typeInfo(T).@"struct".fields) |field| {
            const col_value = row.get(field.name);

            if (types.isArrayType(field.type)) {
                // PostgreSQL 数组 → 反序列化
                const array = try types.deserializeArray(
                    types.arrayElementType(field.type),
                    col_value,
                    self.allocator
                );
                @field(item, field.name) = array.items;
            } else if (field.type == []const u8 and isJSONBField(T, field.name)) {
                // JSONB → 直接使用 JSON 字符串
                @field(item, field.name) = col_value;
            } else if (field.type == [16]u8 and isUUIDField(T, field.name)) {
                // UUID 字符串 → 反序列化
                const uuid = try types.deserializeUUID(col_value);
                @field(item, field.name) = uuid;
            } else {
                // 普通类型 → 直接赋值
                @field(item, field.name) = col_value;
            }
        }

        try dest.append(self.allocator, item);
    }
}
```

## Schema Configuration Integration

通过现有的 `schema.sql_type` 机制,开发者可以显式覆盖自动检测:

```zig
const Article = struct {
    id: i64,
    tags: [][]const u8,  // 自动检测为 TEXT[]
    metadata: []const u8,

    pub const schema = .{
        .metadata = .{ .sql_type = "JSONB" },  // 显式指定 JSONB
        // tags 无需配置,自动检测为 TEXT[]
    };
};
```

## Type Detection Helpers

需要在编译时和运行时判断字段类型:

```zig
// comptime 检测 (reflection.zig)
fn isJSONBField(comptime T: type, comptime field_name: []const u8) bool {
    const schema_cfg = getFieldSchema(T, field_name);
    if (schema_cfg.sql_type) |sql_type| {
        return std.mem.eql(u8, sql_type, "JSONB");
    }
    return false;
}

fn isUUIDField(comptime T: type, comptime field_name: []const u8) bool {
    const field_type = getFieldType(T, field_name);
    const sql_type = zigToSQLType(field_type);
    return sql_type == .uuid;
}
```

## Error Handling

所有序列化/反序列化函数返回错误联合类型:

```zig
pub const SerializationError = error{
    OutOfMemory,
    InvalidFormat,
    InvalidUUIDFormat,
    InvalidHexDigit,
    InvalidJSONFormat,
};
```

## Performance Considerations

1. **Arena 分配器**: INSERT/SELECT 操作使用 Arena 分配器管理序列化产生的临时字符串
2. **零拷贝优化**: 尽量避免不必要的内存拷贝,直接传递 slice
3. **Comptime 优化**: 类型检测在编译时完成,零运行时开销

## Testing Strategy

### 单元测试
- `zigToSQLType()` 数组类型检测
- `serializeArray()` / `deserializeArray()` 所有基础类型
- `serializeJSON()` / `deserializeJSON()` 各种 Zig 类型
- `serializeUUID()` / `deserializeUUID()` 格式验证

### 集成测试
- CREATE TABLE 生成正确的数组/JSONB/UUID 列定义
- INSERT 数组/JSONB/UUID 数据
- SELECT 查询并反序列化数组/JSONB/UUID 数据
- 端到端流程: 插入 → 查询 → 验证数据一致性

### 边界情况测试
- 空数组 `[]`
- NULL 值处理
- 特殊字符转义 (字符串中包含引号、反斜杠)
- 无效 UUID 格式
- 无效 JSON 格式

## Migration Path

此变更完全向后兼容:
- 现有代码无需修改
- 新功能为可选,仅在使用特定类型时生效
- `custom_sql_type` 覆盖机制保持不变

## Documentation Requirements

1. 类型映射表: Zig 类型 → PostgreSQL 类型完整映射
2. 使用示例: 数组、JSONB、UUID 的完整示例代码
3. 性能指南: 大数组和大 JSON 的性能考虑
4. 错误处理: 序列化错误的常见原因和解决方法

Authored-By: mobus <mobussun@gmail.com>
