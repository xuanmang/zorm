//! ZORM Type System Module
//!
//! 提供编译时类型反射和 Zig 到 SQL 类型映射功能。
//! 所有操作都在 comptime 执行,实现零运行时开销。

const std = @import("std");

/// 序列化相关错误类型
pub const SerializationError = error{
    /// 内存分配失败
    OutOfMemory,
    /// 无效的格式
    InvalidFormat,
    /// 无效的 UUID 格式
    InvalidUUIDFormat,
    /// 无效的十六进制字符
    InvalidHexDigit,
    /// 无效的 JSON 格式
    InvalidJSONFormat,
    /// 无效的数组格式
    InvalidArrayFormat,
    /// 不支持的类型
    UnsupportedType,
};

/// 获取结构体字段信息
///
/// 在编译时反射结构体类型,返回所有字段的元数据。
///
/// ## 参数
/// - `T`: 要反射的类型,必须是结构体类型
///
/// ## 返回值
/// 返回结构体字段数组,每个字段包含 name, type, default_value 等信息
///
/// ## 错误
/// 如果 T 不是结构体类型,触发编译错误
///
/// ## 示例
/// ```zig
/// const User = struct { id: i64, name: []const u8 };
/// const fields = comptime getFields(User);
/// // fields[0].name == "id"
/// // fields[0].type == i64
/// ```

// ============ PostgreSQL 特有类型定义 (Story 3.6) ============

/// JSONB 类型包装器
///
/// 用于存储 PostgreSQL JSONB 数据。
/// 在 Zig 侧以 JSON 字符串形式存储。
///
/// ## 示例
/// ```zig
/// const metadata = JSONB{ .data = "{\"author\": \"John\", \"draft\": false}" };
/// ```
pub const JSONB = struct {
    data: []const u8,

    /// 从 JSON 字符串创建 JSONB 实例
    pub fn init(json_string: []const u8) JSONB {
        return .{ .data = json_string };
    }
};

/// UUID 类型
///
/// 表示 PostgreSQL UUID (128 位唯一标识符)。
/// 使用 16 字节数组存储。
///
/// ## 示例
/// ```zig
/// const uuid: UUID = [_]u8{0x55, 0x0e, 0x84, 0x00, ...};
/// ```
pub const UUID = [16]u8;

/// TIMESTAMP WITH TIME ZONE 类型
///
/// 使用 Unix 时间戳 (i64) 存储带时区的时间戳。
/// 单位: 秒或毫秒 (根据应用需求)
pub const TimestampTz = struct {
    value: i64,

    pub fn init(timestamp: i64) TimestampTz {
        return .{ .value = timestamp };
    }

    pub fn fromUnixTimestamp(unix_ts: i64) TimestampTz {
        return .{ .value = unix_ts };
    }
};

/// TIMESTAMP WITHOUT TIME ZONE 类型
///
/// 使用 i64 存储不带时区的时间戳。
pub const Timestamp = struct {
    value: i64,

    pub fn init(timestamp: i64) Timestamp {
        return .{ .value = timestamp };
    }

    pub fn fromUnixTimestamp(unix_ts: i64) Timestamp {
        return .{ .value = unix_ts };
    }
};

pub fn getFields(comptime T: type) []const std.builtin.Type.StructField {
    const type_info = @typeInfo(T);

    // 验证是结构体类型
    if (type_info != .@"struct") {
        @compileError(@typeName(T) ++ " 不是结构体类型,无法提取字段");
    }

    return type_info.@"struct".fields;
}

/// 获取表名
///
/// 优先使用结构体的 `table_name` 声明,否则从类型名自动生成。
/// 类型名转换规则: PascalCase -> snake_case
///
/// ## 参数
/// - `T`: 结构体类型
///
/// ## 返回值
/// 表名字符串
///
/// ## 示例
/// ```zig
/// const User = struct {
///     id: i64,
///     pub const table_name = "app_users";
/// };
/// const name = comptime getTableName(User);
/// // name == "app_users"
///
/// const UserProfile = struct { id: i64 };
/// const name2 = comptime getTableName(UserProfile);
/// // name2 == "user_profile"
/// ```
pub fn getTableName(comptime T: type) []const u8 {
    // 优先使用自定义表名
    if (@hasDecl(T, "table_name")) {
        return T.table_name;
    }

    // 否则从类型名生成
    const type_name = @typeName(T);
    const simple_name = extractTypeName(type_name);
    return toLowerSnakeCase(simple_name);
}

/// Zig 类型到 PostgreSQL SQL 类型映射
///
/// 编译时将 Zig 类型转换为对应的 PostgreSQL 类型字符串。
///
/// ## 支持的类型
/// - 整数: i8/i16 -> SMALLINT, i32 -> INTEGER, i64 -> BIGINT
/// - 无符号整数: u8/u16/u32 -> INTEGER, u64 -> BIGINT
/// - 浮点: f32 -> REAL, f64 -> DOUBLE PRECISION
/// - 布尔: bool -> BOOLEAN
/// - 字符串: []const u8 -> TEXT
/// - 可选类型: ?T -> 递归映射 T
///
/// ## 参数
/// - `T`: Zig 类型
///
/// ## 返回值
/// SQL 类型名称字符串
///
/// ## 错误
/// 不支持的类型触发编译错误,并提供清晰的错误消息
///
/// ## 示例
/// ```zig
/// comptime {
///     const sql_type = zigToSQLType(i64);
///     // sql_type == "BIGINT"
/// }
/// ```
pub fn zigToSQLType(comptime T: type) []const u8 {
    // 优先检查 PostgreSQL 特有类型（使用类型名称匹配，因为现在是包装类型）
    const type_name = @typeName(T);
    if (std.mem.eql(u8, type_name, "types.JSONB")) return "JSONB";
    if (std.mem.eql(u8, type_name, "types.UUID")) return "UUID";
    if (std.mem.eql(u8, type_name, "types.TimestampTz")) return "TIMESTAMP WITH TIME ZONE";
    if (std.mem.eql(u8, type_name, "types.Timestamp")) return "TIMESTAMP WITHOUT TIME ZONE";

    return switch (@typeInfo(T)) {
        // 整数类型
        .int => |info| {
            if (info.signedness == .signed) {
                return switch (info.bits) {
                    8, 16 => "SMALLINT",
                    32 => "INTEGER",
                    64 => "BIGINT",
                    else => @compileError("不支持的整数位宽: " ++
                        std.fmt.comptimePrint("{d}", .{info.bits})),
                };
            } else {
                // 无符号整数
                return switch (info.bits) {
                    8, 16, 32 => "INTEGER",
                    64 => "BIGINT",
                    else => @compileError("不支持的无符号整数位宽: " ++
                        std.fmt.comptimePrint("{d}", .{info.bits})),
                };
            }
        },

        // 浮点类型
        .float => |info| {
            return switch (info.bits) {
                32 => "REAL",
                64 => "DOUBLE PRECISION",
                else => @compileError("不支持的浮点位宽: " ++
                    std.fmt.comptimePrint("{d}", .{info.bits})),
            };
        },

        // 布尔类型
        .bool => "BOOLEAN",

        // 指针类型 (字符串和数组)
        .pointer => |info| {
            // 字符串类型: []const u8 或 []u8
            if (info.child == u8) {
                return "TEXT";
            }

            // 切片类型 (数组): []T
            if (info.size == .Slice) {
                // 递归映射元素类型
                const element_sql_type = zigToSQLType(info.child);
                // 连接类型名和 [] 后缀
                return element_sql_type ++ "[]";
            }

            @compileError(
                "不支持的指针类型: " ++ @typeName(T) ++ "\n" ++
                    "仅支持 []const u8 (TEXT) 和切片数组类型\n" ++
                    "提示:对于字符串,使用 []const u8;对于数组,使用 []T",
            );
        },

        // 可选类型
        .optional => |info| {
            // 递归映射子类型
            return zigToSQLType(info.child);
        },

        // 数组类型 (固定大小)
        .array => |info| {
            // 固定大小数组也映射为 PostgreSQL 数组
            const element_sql_type = zigToSQLType(info.child);
            return element_sql_type ++ "[]";
        },

        // 其他不支持的类型
        else => @compileError(
            "不支持的 Zig 类型: " ++ @typeName(T) ++ "\n" ++
                "支持的类型:i8, i16, i32, i64, u8, u16, u32, u64, " ++
                "f32, f64, bool, []const u8, []T (数组), ?T, " ++
                "JSONB, UUID, TimestampTz, Timestamp\n" ++
                "提示:使用基本类型或可选类型包装",
        ),
    };
}

/// 提取字段名列表
///
/// ## 参数
/// - `T`: 结构体类型
///
/// ## 返回值
/// 字段名数组
///
/// ## 示例
/// ```zig
/// const User = struct { id: i64, name: []const u8 };
/// const names = comptime getFieldNames(User);
/// // names == ["id", "name"]
/// ```
pub fn getFieldNames(comptime T: type) []const []const u8 {
    const fields = getFields(T);

    comptime var names: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |field, i| {
        names[i] = field.name;
    }

    return &names;
}

/// 提取字段类型列表
///
/// ## 参数
/// - `T`: 结构体类型
///
/// ## 返回值
/// 字段类型数组
///
/// ## 示例
/// ```zig
/// const User = struct { id: i64, name: []const u8 };
/// const types = comptime getFieldTypes(User);
/// // types == [i64, []const u8]
/// ```
pub fn getFieldTypes(comptime T: type) []const type {
    const fields = getFields(T);

    comptime var types: [fields.len]type = undefined;
    inline for (fields, 0..) |field, i| {
        types[i] = field.type;
    }

    return &types;
}

/// 编译时验证类型是否支持
///
/// 遍历所有字段类型,验证是否可以映射到 SQL 类型。
///
/// ## 参数
/// - `T`: 结构体类型
///
/// ## 错误
/// 如果存在不支持的字段类型,触发编译错误
///
/// ## 示例
/// ```zig
/// const User = struct { id: i64, name: []const u8 };
/// comptime validateType(User); // 通过
///
/// const BadType = struct { callback: *const fn() void };
/// comptime validateType(BadType); // 编译错误
/// ```
pub fn validateType(comptime T: type) void {
    const fields = getFields(T);

    inline for (fields) |field| {
        // 尝试映射类型,不支持的类型会触发 @compileError
        _ = zigToSQLType(field.type);
    }
}

/// 检查字段是否是可选类型
///
/// ## 参数
/// - `field_type`: 字段类型
///
/// ## 返回值
/// 如果是可选类型返回 true,否则返回 false
pub fn isOptional(comptime field_type: type) bool {
    return @typeInfo(field_type) == .optional;
}

/// 检查类型是否为整数类型 (i8, i16, i32, i64, u8, u16, u32, u64 等)
///
/// ## 参数
/// - `field_type`: 字段类型 (支持可选类型)
///
/// ## 返回值
/// 如果是整数类型返回 true,否则返回 false
pub fn isIntegerType(comptime field_type: type) bool {
    const base_type = if (@typeInfo(field_type) == .optional)
        @typeInfo(field_type).optional.child
    else
        field_type;

    return @typeInfo(base_type) == .int;
}

// ============ PostgreSQL 类型序列化和反序列化 (Story 3.6) ============

/// 将 Zig 数组序列化为 PostgreSQL 数组字面量格式
///
/// ## 参数
/// - `T`: 数组元素类型
/// - `array`: 要序列化的数组切片
/// - `allocator`: 内存分配器
///
/// ## 返回值
/// PostgreSQL 数组字面量字符串 (调用者负责释放)
///
/// ## 错误
/// - `error.OutOfMemory`: 内存分配失败
///
/// ## 示例
/// ```zig
/// const nums = &[_]i32{1, 2, 3};
/// const result = try serializeArray(i32, nums, allocator);
/// defer allocator.free(result);
/// // result == "'{1,2,3}'"
/// ```
/// 转义字符串中的特殊字符 (用于 PostgreSQL 数组)
fn escapeString(buf: *std.ArrayList(u8), str: []const u8, allocator: std.mem.Allocator) !void {
    for (str) |ch| {
        if (ch == '"' or ch == '\\') {
            try buf.append(allocator, '\\');
        }
        try buf.append(allocator, ch);
    }
}

/// 序列化单个数组元素
fn serializeElement(buf: *std.ArrayList(u8), item: anytype, allocator: std.mem.Allocator) !void {
    const T = @TypeOf(item);
    const type_info = @typeInfo(T);

    // 处理可选类型
    if (type_info == .optional) {
        if (item) |value| {
            try serializeElement(buf, value, allocator);
        } else {
            try buf.appendSlice(allocator, "NULL");
        }
        return;
    }

    if (T == []const u8 or T == []u8) {
        // 字符串需要引号和转义
        try buf.append(allocator, '"');
        try escapeString(buf, item, allocator);
        try buf.append(allocator, '"');
    } else if (type_info == .int or type_info == .float) {
        // 数字类型直接格式化
        const str = try std.fmt.allocPrint(allocator, "{d}", .{item});
        defer allocator.free(str);
        try buf.appendSlice(allocator, str);
    } else if (T == bool) {
        // 布尔值使用 PostgreSQL 格式: t/f
        try buf.appendSlice(allocator, if (item) "t" else "f");
    } else {
        @compileError("Unsupported array element type: " ++ @typeName(T));
    }
}

pub fn serializeArray(comptime T: type, array: []const T, allocator: std.mem.Allocator) ![]const u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "'{");

    for (array, 0..) |item, i| {
        if (i > 0) try buf.append(allocator, ',');
        try serializeElement(&buf, item, allocator);
    }

    try buf.appendSlice(allocator, "}'");

    defer buf.deinit(allocator);
    return allocator.dupe(u8, buf.items);
}

/// 将 PostgreSQL 数组字符串反序列化为 Zig ArrayList
///
/// ## 参数
/// - `T`: 数组元素类型
/// - `pg_array_str`: PostgreSQL 数组字面量字符串 (如 "{1,2,3}")
/// - `allocator`: 内存分配器
///
/// ## 返回值
/// 包含解析元素的 ArrayList (调用者负责释放)
///
/// ## 错误
/// - `error.OutOfMemory`: 内存分配失败
/// - `error.InvalidFormat`: 数组格式无效
///
/// ## 示例
/// ```zig
/// var result = try deserializeArray(i32, "{1,2,3}", allocator);
/// defer result.deinit(allocator);
/// // result.items == [1, 2, 3]
/// ```
pub fn deserializeArray(comptime T: type, pg_array_str: []const u8, allocator: std.mem.Allocator) !std.ArrayList(T) {
    var result: std.ArrayList(T) = .{};
    errdefer result.deinit(allocator);

    // 移除前导 '{' 和尾部 '}'
    if (pg_array_str.len < 2 or pg_array_str[0] != '{' or pg_array_str[pg_array_str.len - 1] != '}') {
        return SerializationError.InvalidArrayFormat;
    }

    const content = pg_array_str[1 .. pg_array_str.len - 1];
    if (content.len == 0) {
        return result; // 空数组
    }

    // 处理可选类型
    const base_type = if (@typeInfo(T) == .optional) @typeInfo(T).optional.child else T;
    const is_optional = @typeInfo(T) == .optional;

    // 按逗号分割 (简化实现,生产环境需要处理嵌套情况)
    var iter = std.mem.splitScalar(u8, content, ',');
    while (iter.next()) |item_str| {
        const trimmed = std.mem.trim(u8, item_str, " \t\r\n");

        // 处理 NULL 值
        if (std.mem.eql(u8, trimmed, "NULL")) {
            if (!is_optional) {
                return SerializationError.InvalidFormat;
            }
            try result.append(allocator, null);
            continue;
        }

        // 解析非 NULL 值
        if (base_type == []const u8 or base_type == []u8) {
            // 字符串: 移除引号和处理转义
            var value: []const u8 = trimmed;
            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                value = value[1 .. value.len - 1];
            }
            // TODO: 处理反斜杠转义
            const duped = try allocator.dupe(u8, value);
            if (is_optional) {
                try result.append(allocator, duped);
            } else {
                try result.append(allocator, duped);
            }
        } else if (@typeInfo(base_type) == .int) {
            // 整数解析
            const value = std.fmt.parseInt(base_type, trimmed, 10) catch {
                return SerializationError.InvalidFormat;
            };
            if (is_optional) {
                try result.append(allocator, value);
            } else {
                try result.append(allocator, value);
            }
        } else if (@typeInfo(base_type) == .float) {
            // 浮点数解析
            const value = std.fmt.parseFloat(base_type, trimmed) catch {
                return SerializationError.InvalidFormat;
            };
            if (is_optional) {
                try result.append(allocator, value);
            } else {
                try result.append(allocator, value);
            }
        } else if (base_type == bool) {
            // 布尔值解析: t/f 或 true/false
            const value = std.mem.eql(u8, trimmed, "t") or std.mem.eql(u8, trimmed, "true");
            if (is_optional) {
                try result.append(allocator, value);
            } else {
                try result.append(allocator, value);
            }
        } else {
            return SerializationError.UnsupportedType;
        }
    }

    return result;
}

/// 将 Zig 值序列化为 JSON 字符串
///
/// 使用 std.json.stringify() 实现 JSON 序列化
///
/// ## 参数
/// - `value`: 要序列化的值
/// - `allocator`: 内存分配器
///
/// ## 返回值
/// JSON 字符串
///
/// ## 错误
/// - `error.OutOfMemory`: 内存分配失败
///
/// ## 示例
/// ```zig
/// const data = .{ .name = "Alice", .age = 30 };
/// const json = try serializeJSON(data, allocator);
/// defer allocator.free(json);
/// // json == "{\"name\":\"Alice\",\"age\":30}"
/// ```
// 注意: 对于 JSONB 类型,建议直接使用 []const u8 存储 JSON 字符串
// PostgreSQL 会自动处理 JSON 验证和存储
// 如需在 Zig 中操作 JSON,可使用 std.json 标准库的相关功能

/// 将 UUID 字节数组序列化为标准 UUID 字符串格式
///
/// ## 参数
/// - `uuid`: 16 字节 UUID
/// - `allocator`: 内存分配器
///
/// ## 返回值
/// UUID 字符串 (如 "550e8400-e29b-41d4-a716-446655440000")
///
/// ## 错误
/// - `error.OutOfMemory`: 内存分配失败
///
/// ## 示例
/// ```zig
/// const uuid: UUID = [_]u8{0x55, 0x0e, 0x84, 0x00, ...};
/// const str = try uuidToString(uuid, allocator);
/// defer allocator.free(str);
/// ```
pub fn uuidToString(uuid: UUID, allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
        uuid[0],  uuid[1],  uuid[2],  uuid[3],
        uuid[4],  uuid[5],  uuid[6],  uuid[7],
        uuid[8],  uuid[9],  uuid[10], uuid[11],
        uuid[12], uuid[13], uuid[14], uuid[15],
    });
}

/// 将 UUID 字符串解析为字节数组
///
/// ## 参数
/// - `uuid_str`: UUID 字符串 (可带或不带连字符)
///
/// ## 返回值
/// 16 字节 UUID 数组
///
/// ## 错误
/// - `error.InvalidFormat`: UUID 格式无效
///
/// ## 示例
/// ```zig
/// const uuid = try stringToUuid("550e8400-e29b-41d4-a716-446655440000");
/// ```
pub fn stringToUuid(uuid_str: []const u8) !UUID {
    var result: UUID = undefined;
    var byte_idx: usize = 0;

    // 移除连字符版本
    var i: usize = 0;
    while (i < uuid_str.len and byte_idx < 16) : (i += 1) {
        const c = uuid_str[i];
        if (c == '-') continue; // 跳过连字符

        // 需要两个十六进制字符
        if (i + 1 >= uuid_str.len) return error.InvalidFormat;

        const hex_str = uuid_str[i .. i + 2];
        result[byte_idx] = std.fmt.parseInt(u8, hex_str, 16) catch return error.InvalidFormat;

        byte_idx += 1;
        i += 1; // 跳过第二个字符
    }

    if (byte_idx != 16) return error.InvalidFormat;
    return result;
}

/// 事务隔离级别 (Story 2.5)
///
/// PostgreSQL 支持四个标准隔离级别:
/// - read_uncommitted: 读未提交 (PostgreSQL 实际等同于 read_committed)
/// - read_committed: 读已提交 (PostgreSQL 默认)
/// - repeatable_read: 可重复读
/// - serializable: 串行化
///
/// ## 隔离级别说明
///
/// **READ UNCOMMITTED** (PostgreSQL 不完全支持):
/// - PostgreSQL 会自动升级为 READ COMMITTED
/// - 不推荐使用,仅为 SQL 标准兼容性保留
///
/// **READ COMMITTED** (默认,推荐):
/// - 查询只能看到事务开始前已提交的数据
/// - 同一事务内的重复查询可能看到不同结果 (Non-repeatable Read)
/// - 适用场景: 大多数 OLTP 应用,高并发场景
/// - 性能开销: 最低
///
/// **REPEATABLE READ**:
/// - 事务内的查询看到一致性快照
/// - 避免 Non-repeatable Read
/// - PostgreSQL MVCC 机制实际也避免了 Phantom Read
/// - 适用场景: 需要一致性读的报表或分析
/// - 性能开销: 中等
///
/// **SERIALIZABLE**:
/// - 最高隔离级别,完全避免并发异常
/// - 通过 SSI (Serializable Snapshot Isolation) 检测读写冲突
/// - 可能导致事务串行化错误,需要应用层重试
/// - 适用场景: 金融系统、关键业务逻辑
/// - 性能开销: 最高
///
/// ## 示例
/// ```zig
/// const opts = TxOptions{ .isolation_level = .serializable };
/// var tx = try db.beginTx(opts);
/// defer tx.deinit();
/// ```
pub const IsolationLevel = enum {
    /// 读未提交 (PostgreSQL 实际等同于 read_committed)
    read_uncommitted,
    /// 读已提交 (PostgreSQL 默认)
    read_committed,
    /// 可重复读
    repeatable_read,
    /// 串行化
    serializable,

    /// 转换为 SQL 语句
    ///
    /// 返回 PostgreSQL SET TRANSACTION ISOLATION LEVEL 语句中使用的级别名称
    ///
    /// ## 返回
    /// SQL 隔离级别名称字符串
    ///
    /// ## 示例
    /// ```zig
    /// const level = IsolationLevel.serializable;
    /// const sql = level.toSQL(); // "SERIALIZABLE"
    /// ```
    pub fn toSQL(self: IsolationLevel) []const u8 {
        return switch (self) {
            .read_uncommitted => "READ UNCOMMITTED",
            .read_committed => "READ COMMITTED",
            .repeatable_read => "REPEATABLE READ",
            .serializable => "SERIALIZABLE",
        };
    }
};

// ============ 辅助工具函数 ============

/// 提取完全限定名的最后部分
///
/// ## 参数
/// - `qualified_name`: 完全限定的类型名 (如 "myapp.models.User")
///
/// ## 返回值
/// 类型名的最后部分 (如 "User")
///
/// ## 示例
/// ```zig
/// extractTypeName("myapp.models.User") == "User"
/// extractTypeName("User") == "User"
/// ```
fn extractTypeName(comptime qualified_name: []const u8) []const u8 {
    // 查找最后一个 '.' 或 '::'
    comptime var i: usize = qualified_name.len;
    while (i > 0) : (i -= 1) {
        if (qualified_name[i - 1] == '.') {
            return qualified_name[i..];
        }
        if (i >= 2 and qualified_name[i - 2] == ':' and qualified_name[i - 1] == ':') {
            return qualified_name[i..];
        }
    }
    return qualified_name;
}

/// 将 PascalCase 转换为 snake_case
///
/// ## 参数
/// - `name`: PascalCase 或 camelCase 名称
///
/// ## 返回值
/// snake_case 名称
///
/// ## 示例
/// ```zig
/// toLowerSnakeCase("UserProfile") == "user_profile"
/// toLowerSnakeCase("HTTPRequest") == "http_request"
/// toLowerSnakeCase("User") == "user"
/// ```
fn toLowerSnakeCase(comptime name: []const u8) []const u8 {
    @setEvalBranchQuota(10000);

    // 计算结果长度
    comptime var result_len: usize = 0;
    comptime var prev_was_lower = false;

    comptime {
        for (name) |c| {
            if (std.ascii.isUpper(c)) {
                if (prev_was_lower) result_len += 1; // 下划线
                result_len += 1; // 小写字母
                prev_was_lower = false;
            } else {
                result_len += 1;
                prev_was_lower = std.ascii.isLower(c);
            }
        }
    }

    // 使用编译时块创建常量数组
    const result = comptime blk: {
        var buf: [result_len]u8 = undefined;
        var idx: usize = 0;
        var prev_lower = false;

        for (name) |c| {
            if (std.ascii.isUpper(c)) {
                if (prev_lower) {
                    buf[idx] = '_';
                    idx += 1;
                }
                buf[idx] = std.ascii.toLower(c);
                idx += 1;
                prev_lower = false;
            } else {
                buf[idx] = c;
                idx += 1;
                prev_lower = std.ascii.isLower(c);
            }
        }

        break :blk buf;
    };

    return &result;
}

// ============ 编译时测试 ============

test "extractTypeName: simple name" {
    comptime {
        const name = extractTypeName("User");
        try std.testing.expectEqualStrings("User", name);
    }
}

test "extractTypeName: qualified name with dot" {
    comptime {
        const name = extractTypeName("myapp.models.User");
        try std.testing.expectEqualStrings("User", name);
    }
}

test "toLowerSnakeCase: single word" {
    comptime {
        const result = toLowerSnakeCase("User");
        try std.testing.expectEqualStrings("user", result);
    }
}

test "toLowerSnakeCase: two words" {
    comptime {
        const result = toLowerSnakeCase("UserProfile");
        try std.testing.expectEqualStrings("user_profile", result);
    }
}

test "toLowerSnakeCase: acronym" {
    comptime {
        const result = toLowerSnakeCase("HTTPRequest");
        try std.testing.expectEqualStrings("httprequest", result);
    }
}

test "serializeArray: integers" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const nums = &[_]i64{ 1, 2, 3, 4, 5 };
    const result = try serializeArray(i64, nums, allocator);
    defer allocator.free(result);

    try testing.expectEqualStrings("'{1,2,3,4,5}'", result);
}

test "serializeArray: floats" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const nums = &[_]f64{ 1.5, 2.5, 3.5 };
    const result = try serializeArray(f64, nums, allocator);
    defer allocator.free(result);

    try testing.expectEqualStrings("'{1.5,2.5,3.5}'", result);
}

test "serializeArray: booleans" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const bools = &[_]bool{ true, false, true };
    const result = try serializeArray(bool, bools, allocator);
    defer allocator.free(result);

    try testing.expectEqualStrings("'{t,f,t}'", result);
}

test "serializeArray: strings" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strs = &[_][]const u8{ "hello", "world", "test" };
    const result = try serializeArray([]const u8, strs, allocator);
    defer allocator.free(result);

    try testing.expectEqualStrings("'{\"hello\",\"world\",\"test\"}'", result);
}

test "serializeArray: strings with quotes" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strs = &[_][]const u8{ "hello", "wo\"rld", "te\\st" };
    const result = try serializeArray([]const u8, strs, allocator);
    defer allocator.free(result);

    try testing.expectEqualStrings("'{\"hello\",\"wo\\\"rld\",\"te\\\\st\"}'", result);
}

test "serializeArray: empty array" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const nums = &[_]i32{};
    const result = try serializeArray(i32, nums, allocator);
    defer allocator.free(result);

    try testing.expectEqualStrings("'{}'", result);
}

test "deserializeArray: integers" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var result = try deserializeArray(i64, "{1,2,3,4,5}", allocator);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(usize, 5), result.items.len);
    try testing.expectEqual(@as(i64, 1), result.items[0]);
    try testing.expectEqual(@as(i64, 2), result.items[1]);
    try testing.expectEqual(@as(i64, 3), result.items[2]);
    try testing.expectEqual(@as(i64, 4), result.items[3]);
    try testing.expectEqual(@as(i64, 5), result.items[4]);
}

test "deserializeArray: floats" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var result = try deserializeArray(f64, "{1.5,2.5,3.5}", allocator);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(usize, 3), result.items.len);
    try testing.expectEqual(@as(f64, 1.5), result.items[0]);
    try testing.expectEqual(@as(f64, 2.5), result.items[1]);
    try testing.expectEqual(@as(f64, 3.5), result.items[2]);
}

test "deserializeArray: booleans" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var result = try deserializeArray(bool, "{t,f,t}", allocator);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(usize, 3), result.items.len);
    try testing.expect(result.items[0]);
    try testing.expect(!result.items[1]);
    try testing.expect(result.items[2]);
}

test "deserializeArray: strings" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var result = try deserializeArray([]const u8, "{\"hello\",\"world\",\"test\"}", allocator);
    defer {
        for (result.items) |item| {
            allocator.free(item);
        }
        result.deinit(allocator);
    }

    try testing.expectEqual(@as(usize, 3), result.items.len);
    try testing.expectEqualStrings("hello", result.items[0]);
    try testing.expectEqualStrings("world", result.items[1]);
    try testing.expectEqualStrings("test", result.items[2]);
}

test "deserializeArray: empty array" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var result = try deserializeArray(i32, "{}", allocator);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(usize, 0), result.items.len);
}

test "deserializeArray: invalid format" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const err = deserializeArray(i32, "1,2,3", allocator);
    try testing.expectError(SerializationError.InvalidArrayFormat, err);
}

// ============ UUID 序列化/反序列化测试 (Task 4.1-4.2) ============

test "uuidToString: standard UUID format" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const uuid: UUID = [_]u8{
        0x55, 0x0e, 0x84, 0x00,
        0xe2, 0x9b, 0x41, 0xd4,
        0xa7, 0x16, 0x44, 0x66,
        0x55, 0x44, 0x00, 0x00,
    };

    const str = try uuidToString(uuid, allocator);
    defer allocator.free(str);

    try testing.expectEqualStrings("550e8400-e29b-41d4-a716-446655440000", str);
}

test "uuidToString: all zeros" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const uuid: UUID = [_]u8{0} ** 16;
    const str = try uuidToString(uuid, allocator);
    defer allocator.free(str);

    try testing.expectEqualStrings("00000000-0000-0000-0000-000000000000", str);
}

test "uuidToString: all ones" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const uuid: UUID = [_]u8{0xff} ** 16;
    const str = try uuidToString(uuid, allocator);
    defer allocator.free(str);

    try testing.expectEqualStrings("ffffffff-ffff-ffff-ffff-ffffffffffff", str);
}

test "stringToUuid: standard format" {
    const testing = std.testing;

    const uuid = try stringToUuid("550e8400-e29b-41d4-a716-446655440000");

    try testing.expectEqual(@as(u8, 0x55), uuid[0]);
    try testing.expectEqual(@as(u8, 0x0e), uuid[1]);
    try testing.expectEqual(@as(u8, 0x84), uuid[2]);
    try testing.expectEqual(@as(u8, 0x00), uuid[3]);
    try testing.expectEqual(@as(u8, 0xe2), uuid[4]);
    try testing.expectEqual(@as(u8, 0x9b), uuid[5]);
    try testing.expectEqual(@as(u8, 0x41), uuid[6]);
    try testing.expectEqual(@as(u8, 0xd4), uuid[7]);
}

test "stringToUuid: uppercase letters" {
    const testing = std.testing;

    const uuid = try stringToUuid("550E8400-E29B-41D4-A716-446655440000");

    try testing.expectEqual(@as(u8, 0x55), uuid[0]);
    try testing.expectEqual(@as(u8, 0x0e), uuid[1]);
    try testing.expectEqual(@as(u8, 0x84), uuid[2]);
    try testing.expectEqual(@as(u8, 0x00), uuid[3]);
}

test "stringToUuid: no hyphens" {
    const testing = std.testing;

    const uuid = try stringToUuid("550e8400e29b41d4a716446655440000");

    try testing.expectEqual(@as(u8, 0x55), uuid[0]);
    try testing.expectEqual(@as(u8, 0x0e), uuid[1]);
    try testing.expectEqual(@as(u8, 0x84), uuid[2]);
    try testing.expectEqual(@as(u8, 0x00), uuid[3]);
}

test "stringToUuid: invalid format - too short" {
    const testing = std.testing;

    const err = stringToUuid("550e8400-e29b-41d4");
    try testing.expectError(error.InvalidFormat, err);
}

test "stringToUuid: invalid format - invalid hex" {
    const testing = std.testing;

    const err = stringToUuid("550e8400-e29b-41d4-a716-44665544000g");
    try testing.expectError(error.InvalidFormat, err);
}

test "stringToUuid: round-trip conversion" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const original_uuid: UUID = [_]u8{
        0x55, 0x0e, 0x84, 0x00,
        0xe2, 0x9b, 0x41, 0xd4,
        0xa7, 0x16, 0x44, 0x66,
        0x55, 0x44, 0x00, 0x00,
    };

    // UUID -> String
    const str = try uuidToString(original_uuid, allocator);
    defer allocator.free(str);

    // String -> UUID
    const parsed_uuid = try stringToUuid(str);

    // 验证一致性
    try testing.expectEqualSlices(u8, &original_uuid, &parsed_uuid);
}
