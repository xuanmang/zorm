# timestamp-types-refinement Specification

## Purpose
细化 TIMESTAMP 类型支持,明确区分 PostgreSQL 的 `TIMESTAMP WITHOUT TIME ZONE` 和 `TIMESTAMP WITH TIME ZONE`,并提供清晰的使用指南。

## ADDED Requirements

### Requirement: TIMESTAMP 类型明确区分

SQLType enum MUST 明确区分 `timestamp` (TIMESTAMP WITHOUT TIME ZONE) 和 `timestamptz` (TIMESTAMP WITH TIME ZONE)。

**Context**: PostgreSQL 有两种 timestamp 类型,需要清晰的映射规则。

#### Scenario: SQLType 包含两种 timestamp 类型

```zig
const types = @import("schema/types.zig");

// 验证 SQLType 包含两种 timestamp 类型
const ts: types.SQLType = .timestamp;
const tstz: types.SQLType = .timestamptz;

try std.testing.expectEqual(types.SQLType.timestamp, ts);
try std.testing.expectEqual(types.SQLType.timestamptz, tstz);
```

#### Scenario: toSQL 生成正确的 SQL 字符串

```zig
const types = @import("schema/types.zig");
const Dialect = @import("dialect/dialect.zig").Dialect;

try std.testing.expectEqualStrings("TIMESTAMP", types.SQLType.timestamp.toSQL(.postgresql));
try std.testing.expectEqualStrings("TIMESTAMPTZ", types.SQLType.timestamptz.toSQL(.postgresql));
```

---

### Requirement: 默认 timestamp 类型映射

Zig `i64` 类型 (用于存储 Unix timestamp) MUST 默认映射到 `TIMESTAMP` (WITHOUT TIME ZONE)。

**Context**: 大多数场景使用 Unix timestamp (i64),默认映射为 TIMESTAMP 简化使用。

#### Scenario: i64 默认映射为 TIMESTAMP

```zig
const types = @import("schema/types.zig");

// i64 用于 Unix timestamp,默认映射为 TIMESTAMP (WITHOUT TIME ZONE)
const sql_type = types.zigToSQLType(i64);

// 注意: 这里可能映射为 .bigint 而非 .timestamp
// 需要通过 schema 配置显式指定 timestamp 类型
try std.testing.expectEqual(types.SQLType.bigint, sql_type);
```

---

### Requirement: 通过 schema 配置指定 TIMESTAMPTZ

开发者 MUST 能够通过 `schema.sql_type = "TIMESTAMPTZ"` 显式指定字段使用 `TIMESTAMP WITH TIME ZONE`。

**Context**: 需要时区信息时,开发者可显式配置 TIMESTAMPTZ。

#### Scenario: Schema 配置 TIMESTAMPTZ

```zig
const Event = struct {
    id: i64,
    name: []const u8,
    created_at: i64,        // TIMESTAMP (默认)
    scheduled_at: i64,      // TIMESTAMPTZ (显式配置)

    pub const table_name = "events";

    pub const schema = .{
        .created_at = .{ .sql_type = "TIMESTAMP" },
        .scheduled_at = .{ .sql_type = "TIMESTAMPTZ" },
    };
};

const allocator = std.testing.allocator;
const reflection = @import("schema/reflection.zig");

const columns = try reflection.generateColumns(Event, allocator);
defer allocator.free(columns);

// created_at 应有 sql_type = "TIMESTAMP"
var created_col: ?table_mod.Column = null;
for (columns) |col| {
    if (std.mem.eql(u8, col.name, "created_at")) {
        created_col = col;
        break;
    }
}
try std.testing.expect(created_col != null);
try std.testing.expectEqualStrings("TIMESTAMP", created_col.?.custom_sql_type.?);

// scheduled_at 应有 sql_type = "TIMESTAMPTZ"
var scheduled_col: ?table_mod.Column = null;
for (columns) |col| {
    if (std.mem.eql(u8, col.name, "scheduled_at")) {
        scheduled_col = col;
        break;
    }
}
try std.testing.expect(scheduled_col != null);
try std.testing.expectEqualStrings("TIMESTAMPTZ", scheduled_col.?.custom_sql_type.?);
```

---

### Requirement: CREATE TABLE 生成正确的 TIMESTAMP 类型

`generateCreateTableSQL()` MUST 根据 schema 配置生成正确的 TIMESTAMP 或 TIMESTAMPTZ 列定义。

**Context**: CREATE TABLE 应根据配置生成正确的 timestamp 类型。

#### Scenario: 生成 TIMESTAMP 和 TIMESTAMPTZ 列

```zig
const Event = struct {
    id: i64,
    created_at: i64,
    scheduled_at: i64,

    pub const table_name = "events";
    pub const schema = .{
        .id = .{ .primary_key = true },
        .created_at = .{ .sql_type = "TIMESTAMP" },
        .scheduled_at = .{ .sql_type = "TIMESTAMPTZ" },
    };
};

const allocator = std.testing.allocator;
const reflection = @import("schema/reflection.zig");

const sql = try reflection.generateCreateTableSQL(Event, .postgresql, allocator);
defer allocator.free(sql);

// 验证包含正确的类型
try std.testing.expect(std.mem.indexOf(u8, sql, "created_at TIMESTAMP NOT NULL") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "scheduled_at TIMESTAMPTZ NOT NULL") != null);
```

---

### Requirement: TIMESTAMP 类型文档说明

文档 MUST 清晰说明两种 TIMESTAMP 类型的区别和使用场景。

**Context**: 开发者需要了解何时使用 TIMESTAMP vs TIMESTAMPTZ。

#### Scenario: 使用指南文档

```markdown
## TIMESTAMP 类型选择指南

### TIMESTAMP (WITHOUT TIME ZONE)
- **使用场景**: 存储与时区无关的时间点 (如 Unix timestamp)
- **Zig 类型**: `i64` (存储 Unix timestamp 秒数或毫秒数)
- **PostgreSQL 类型**: `TIMESTAMP`
- **配置方式**: `schema.field_name = .{ .sql_type = "TIMESTAMP" }`

### TIMESTAMPTZ (WITH TIME ZONE)
- **使用场景**: 存储需要时区信息的时间点 (如跨时区事件)
- **Zig 类型**: `i64` (存储 Unix timestamp,PostgreSQL 自动处理时区转换)
- **PostgreSQL 类型**: `TIMESTAMPTZ`
- **配置方式**: `schema.field_name = .{ .sql_type = "TIMESTAMPTZ" }`

### 推荐实践
- **默认使用 Unix timestamp (i64)**: 简单、跨平台、无歧义
- **跨时区应用使用 TIMESTAMPTZ**: 让 PostgreSQL 处理时区转换
- **本地时间使用 TIMESTAMP**: 如 "每天 9:00" 的定时任务
```

---

### Requirement: 与现有代码向后兼容

timestamp 类型细化 MUST 保持与现有代码的向后兼容性,现有使用 `i64` 存储时间戳的代码应继续正常工作。

**Context**: 大量现有代码使用 `i64` 字段,不能破坏现有功能。

#### Scenario: 现有代码无配置时的默认行为

```zig
const User = struct {
    id: i64,
    name: []const u8,
    created_at: i64,  // 无 schema 配置

    pub const table_name = "users";
};

const allocator = std.testing.allocator;
const reflection = @import("schema/reflection.zig");

const sql = try reflection.generateCreateTableSQL(User, .postgresql, allocator);
defer allocator.free(sql);

// created_at 应使用默认的 BIGINT 类型 (i64 的自动映射)
try std.testing.expect(std.mem.indexOf(u8, sql, "created_at BIGINT NOT NULL") != null);
```

---

### Requirement: PRD Story 3.6 AC3.6.4 示例验证

PRD AC3.6.4 关于 TIMESTAMP 类型的示例代码 MUST 可编译并通过测试。

**Context**: 确保 TIMESTAMP 类型支持符合 PRD 要求。

#### Scenario: TIMESTAMP 类型完整示例

```zig
const Event = struct {
    id: i64,
    name: []const u8,
    description: []const u8,
    created_at: i64,        // Unix timestamp → TIMESTAMP
    scheduled_at: i64,      // Unix timestamp → TIMESTAMPTZ
    updated_at: i64,        // Unix timestamp → TIMESTAMP

    pub const table_name = "events";

    pub const schema = .{
        .id = .{ .primary_key = true },
        .created_at = .{
            .sql_type = "TIMESTAMP",
            .default = "CURRENT_TIMESTAMP",
        },
        .scheduled_at = .{
            .sql_type = "TIMESTAMPTZ",
        },
        .updated_at = .{
            .sql_type = "TIMESTAMP",
            .default = "CURRENT_TIMESTAMP",
        },
    };
};

const allocator = std.testing.allocator;

// CREATE TABLE
var create = try db.newCreateTable(Event);
defer create.deinit();
try create.ifNotExists().exec();

// INSERT
const event = Event{
    .id = 1,
    .name = "Team Meeting",
    .description = "Weekly sync",
    .created_at = std.time.timestamp(),
    .scheduled_at = std.time.timestamp() + 86400,  // 明天
    .updated_at = std.time.timestamp(),
};

var insert = try db.newInsert(Event);
defer insert.deinit();
_ = try insert.value(event).exec();

// SELECT
var events: std.ArrayList(Event) = .{};
defer events.deinit(allocator);

var select = try db.newSelect(Event);
defer select.deinit();

try select.where("id = ?", .{1}).scan(&events);

try std.testing.expectEqual(@as(usize, 1), events.items.len);
try std.testing.expectEqualStrings("Team Meeting", events.items[0].name);
```

## MODIFIED Requirements

无需修改现有需求,本 spec 为纯增量变更。
