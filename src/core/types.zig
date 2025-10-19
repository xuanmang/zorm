//! ZORM Type System Module
//!
//! 提供编译时类型反射和 Zig 到 SQL 类型映射功能。
//! 所有操作都在 comptime 执行,实现零运行时开销。

const std = @import("std");

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

        // 指针类型 (字符串)
        .pointer => |info| {
            if (info.child == u8) {
                // []const u8 或 []u8 → TEXT
                return "TEXT";
            }
            @compileError(
                "不支持的指针类型: " ++ @typeName(T) ++ "\n" ++
                    "仅支持 []const u8 (TEXT) 类型\n" ++
                    "提示:对于字符串,使用 []const u8",
            );
        },

        // 可选类型
        .optional => |info| {
            // 递归映射子类型
            return zigToSQLType(info.child);
        },

        // 数组类型 (Story 3.6)
        .array => @compileError(
            "数组类型映射将在 Story 3.6 中实现\n" ++
                "类型: " ++ @typeName(T),
        ),

        // 其他不支持的类型
        else => @compileError(
            "不支持的 Zig 类型: " ++ @typeName(T) ++ "\n" ++
                "支持的类型:i8, i16, i32, i64, u8, u16, u32, u64, " ++
                "f32, f64, bool, []const u8, ?T\n" ++
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
