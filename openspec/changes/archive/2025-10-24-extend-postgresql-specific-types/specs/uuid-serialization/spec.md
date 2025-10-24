# uuid-serialization Specification

## Purpose
定义 UUID 类型的序列化和反序列化支持,使 ZORM 能够处理 Zig `[16]u8` 与 PostgreSQL UUID 字符串之间的转换。

## ADDED Requirements

### Requirement: UUID 类型自动映射

类型系统 MUST 支持检测 Zig `[16]u8` 类型并自动映射到 PostgreSQL UUID 类型。

**Context**: UUID 在 Zig 中常用 `[16]u8` 表示 (128-bit),需要自动映射到 PostgreSQL UUID 类型。

#### Scenario: [16]u8 映射为 UUID

```zig
const types = @import("schema/types.zig");

const sql_type = types.zigToSQLType([16]u8);
try std.testing.expectEqual(types.SQLType.uuid, sql_type);
```

---

### Requirement: CREATE TABLE 生成 UUID 列

`generateCreateTableSQL()` MUST 为 `[16]u8` 字段生成正确的 UUID 列定义。

**Context**: CREATE TABLE 应自动识别 UUID 类型字段。

#### Scenario: 生成 UUID 列的 CREATE TABLE

```zig
const User = struct {
    id: [16]u8,  // UUID
    name: []const u8,

    pub const table_name = "users";
    pub const schema = .{
        .id = .{ .primary_key = true },
    };
};

const allocator = std.testing.allocator;
const reflection = @import("schema/reflection.zig");

const sql = try reflection.generateCreateTableSQL(User, .postgresql, allocator);
defer allocator.free(sql);

// 验证包含 UUID 类型
try std.testing.expect(std.mem.indexOf(u8, sql, "id UUID") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "PRIMARY KEY") != null);
```

---

### Requirement: UUID 序列化为字符串

类型系统 MUST 提供 `serializeUUID()` 函数,将 `[16]u8` 序列化为标准 UUID 字符串格式 `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`。

**Context**: INSERT 操作需要将 `[16]u8` 转换为 PostgreSQL 可识别的 UUID 字符串。

#### Scenario: 序列化 UUID 为标准格式

```zig
const types = @import("core/types.zig");

const uuid: [16]u8 = .{
    0x12, 0x34, 0x56, 0x78,
    0x9a, 0xbc,
    0xde, 0xf0,
    0x11, 0x22,
    0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
};

const allocator = std.testing.allocator;
const uuid_str = try types.serializeUUID(uuid, allocator);
defer allocator.free(uuid_str);

// 标准 UUID 格式: 12345678-9abc-def0-1122-334455667788
try std.testing.expectEqual(@as(usize, 36), uuid_str.len);
try std.testing.expectEqualStrings("12345678-9abc-def0-1122-334455667788", uuid_str);
```

#### Scenario: UUID 字符串格式验证

```zig
const types = @import("core/types.zig");

const uuid: [16]u8 = .{0} ** 16;  // 全零 UUID
const allocator = std.testing.allocator;

const uuid_str = try types.serializeUUID(uuid, allocator);
defer allocator.free(uuid_str);

try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000000", uuid_str);

// 验证连字符位置
try std.testing.expectEqual('-', uuid_str[8]);
try std.testing.expectEqual('-', uuid_str[13]);
try std.testing.expectEqual('-', uuid_str[18]);
try std.testing.expectEqual('-', uuid_str[23]);
```

---

### Requirement: UUID 字符串反序列化为 [16]u8

类型系统 MUST 提供 `deserializeUUID()` 函数,将 PostgreSQL 返回的 UUID 字符串反序列化为 `[16]u8`。

**Context**: SELECT 操作需要将 PostgreSQL UUID 字符串转换为 Zig `[16]u8`。

#### Scenario: 反序列化标准 UUID 字符串

```zig
const types = @import("core/types.zig");

const uuid_str = "12345678-9abc-def0-1122-334455667788";

const result = try types.deserializeUUID(uuid_str);

try std.testing.expectEqual(@as(u8, 0x12), result[0]);
try std.testing.expectEqual(@as(u8, 0x34), result[1]);
try std.testing.expectEqual(@as(u8, 0x78), result[3]);
try std.testing.expectEqual(@as(u8, 0x9a), result[4]);
try std.testing.expectEqual(@as(u8, 0xbc), result[5]);
try std.testing.expectEqual(@as(u8, 0x88), result[15]);
```

#### Scenario: 大写字母 UUID 字符串

```zig
const types = @import("core/types.zig");

const uuid_str = "ABCDEF01-2345-6789-ABCD-EF0123456789";

const result = try types.deserializeUUID(uuid_str);

try std.testing.expectEqual(@as(u8, 0xAB), result[0]);
try std.testing.expectEqual(@as(u8, 0xCD), result[1]);
try std.testing.expectEqual(@as(u8, 0xEF), result[2]);
```

#### Scenario: 无效 UUID 格式返回错误

```zig
const types = @import("core/types.zig");

const invalid1 = "12345678-9abc-def0-1122";  // 太短
const invalid2 = "12345678-9abc-def0-1122-334455667788-extra";  // 太长
const invalid3 = "1234567g-9abc-def0-1122-334455667788";  // 无效字符

try std.testing.expectError(error.InvalidUUIDFormat, types.deserializeUUID(invalid1));
try std.testing.expectError(error.InvalidUUIDFormat, types.deserializeUUID(invalid2));
try std.testing.expectError(error.InvalidHexDigit, types.deserializeUUID(invalid3));
```

---

### Requirement: INSERT 操作集成 UUID 序列化

INSERT Query Builder MUST 在绑定 UUID 字段值时自动调用 UUID 序列化函数。

**Context**: 开发者插入 UUID 数据时,应自动转换为 PostgreSQL UUID 字符串。

#### Scenario: INSERT UUID 字段

```zig
const Session = struct {
    id: [16]u8,  // UUID
    user_id: i64,
    created_at: i64,

    pub const table_name = "sessions";
    pub const schema = .{
        .id = .{ .primary_key = true },
    };
};

const session = Session{
    .id = .{
        0x12, 0x34, 0x56, 0x78,
        0x9a, 0xbc,
        0xde, 0xf0,
        0x11, 0x22,
        0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
    },
    .user_id = 1,
    .created_at = std.time.timestamp(),
};

var insert = try db.newInsert(Session);
defer insert.deinit();

const result = try insert.value(session).exec();

try std.testing.expectEqual(@as(usize, 1), result.rows_affected);
```

---

### Requirement: SELECT 操作集成 UUID 反序列化

SELECT Query Builder MUST 在扫描 UUID 字段时自动调用 UUID 反序列化函数。

**Context**: SELECT 查询 UUID 列时,PostgreSQL 返回字符串,需转换为 `[16]u8`。

#### Scenario: SELECT UUID 字段

```zig
const Session = struct {
    id: [16]u8,  // UUID
    user_id: i64,

    pub const table_name = "sessions";
};

var sessions: std.ArrayList(Session) = .{};
defer sessions.deinit(allocator);

var select = try db.newSelect(Session);
defer select.deinit();

try select.where("user_id = ?", .{1}).scan(&sessions);

try std.testing.expectEqual(@as(usize, 1), sessions.items.len);

// 验证 UUID 是有效的 [16]u8
const uuid = sessions.items[0].id;
try std.testing.expectEqual(@as(usize, 16), uuid.len);
```

---

### Requirement: UUID 字段类型检测辅助函数

类型系统 MUST 提供辅助函数,在 comptime 检测字段是否为 UUID 类型。

**Context**: Query Builder 需要判断字段是否为 UUID 以决定是否需要序列化。

#### Scenario: 检测字段是否为 UUID

```zig
const schema_lib = @import("schema/schema.zig");

const Session = struct {
    id: [16]u8,
    user_id: i64,
};

const is_uuid = comptime schema_lib.isUUIDField(Session, "id");
const is_not_uuid = comptime schema_lib.isUUIDField(Session, "user_id");

try std.testing.expect(is_uuid);
try std.testing.expect(!is_not_uuid);
```

---

### Requirement: PRD Story 3.6 AC3.6.3 示例验证

PRD AC3.6.3 关于 UUID 的示例代码 MUST 可编译并通过测试。

**Context**: 确保 UUID 支持符合 PRD 要求。

#### Scenario: UUID 作为主键的完整流程

```zig
const Session = struct {
    id: [16]u8,  // UUID 主键
    user_id: i64,
    token: []const u8,
    created_at: i64,

    pub const table_name = "sessions";
    pub const schema = .{
        .id = .{ .primary_key = true },
    };
};

const allocator = std.testing.allocator;

// CREATE TABLE
var create = try db.newCreateTable(Session);
defer create.deinit();
try create.ifNotExists().exec();

// 生成 UUID
var uuid: [16]u8 = undefined;
std.crypto.random.bytes(&uuid);

// INSERT
const session = Session{
    .id = uuid,
    .user_id = 1,
    .token = "abc123",
    .created_at = std.time.timestamp(),
};

var insert = try db.newInsert(Session);
defer insert.deinit();
_ = try insert.value(session).exec();

// SELECT
var sessions: std.ArrayList(Session) = .{};
defer sessions.deinit(allocator);

var select = try db.newSelect(Session);
defer select.deinit();

try select.where("user_id = ?", .{1}).scan(&sessions);

try std.testing.expectEqual(@as(usize, 1), sessions.items.len);
try std.testing.expectEqual(uuid, sessions.items[0].id);
```
