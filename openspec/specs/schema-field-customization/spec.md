# schema-field-customization Specification

## Purpose
TBD - created by archiving change implement-schema-field-customization. Update Purpose after archive.
## Requirements
### Requirement: 支持自定义列名配置

FieldSchema MUST 支持 `column_name` 字段，允许开发者通过 `pub const schema` 配置自定义数据库列名，映射到与 Zig 结构体字段不同的列名。

**Context**: 数据库列名命名规范可能与 Zig 代码规范不同（如数据库使用 `username`，Zig 使用 `user_name`），需要支持灵活映射。

#### Scenario: 自定义单个字段的列名

```zig
const User = struct {
    id: i64,
    user_name: []const u8, // Zig 字段名
    email: []const u8,

    pub const table_name = "users";
    pub const schema = .{
        .user_name = .{ .column_name = "username" }, // 数据库列名
    };
};

const allocator = std.testing.allocator;
const columns = try generateColumns(User, allocator);
defer allocator.free(columns);

// user_name 字段的列名应为 "username"
var found = false;
for (columns) |col| {
    if (std.mem.eql(u8, col.name, "username")) {
        found = true;
        break;
    }
}
try std.testing.expect(found);
```

#### Scenario: 自定义多个字段的列名

```zig
const Product = struct {
    product_id: i64,
    product_name: []const u8,
    product_price: f64,

    pub const table_name = "products";
    pub const schema = .{
        .product_id = .{ .column_name = "id" },
        .product_name = .{ .column_name = "name" },
        .product_price = .{ .column_name = "price" },
    };
};

const allocator = std.testing.allocator;
const columns = try generateColumns(Product, allocator);
defer allocator.free(columns);

try std.testing.expectEqual(@as(usize, 3), columns.len);
try std.testing.expectEqualStrings("id", columns[0].name);
try std.testing.expectEqualStrings("name", columns[1].name);
try std.testing.expectEqualStrings("price", columns[2].name);
```

#### Scenario: CREATE TABLE SQL 使用自定义列名

```zig
const User = struct {
    id: i64,
    user_name: []const u8,
    email: []const u8,

    pub const table_name = "users";
    pub const schema = .{
        .user_name = .{ .column_name = "username" },
    };
};

const allocator = std.testing.allocator;
var table = try Table.init(allocator, "users");
defer table.deinit();

const columns = try generateColumns(User, allocator);
defer allocator.free(columns);

for (columns) |col| {
    _ = try table.addColumn(col);
}

const sql = try table.toSQL(.postgresql);
defer allocator.free(sql);

// SQL 应包含 "username" 列而非 "user_name"
try std.testing.expect(std.mem.indexOf(u8, sql, "username") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "user_name") == null);
```

---

### Requirement: 支持显式 SQL 类型配置

FieldSchema MUST 支持 `sql_type` 字段，允许开发者通过 `pub const schema` 配置显式指定 SQL 类型字符串，覆盖 Zig 类型的自动推断。

**Context**: 某些场景需要特定的 SQL 类型（如 VARCHAR(50) 而非 TEXT，DECIMAL(10,2) 而非默认的 DOUBLE），自动推断无法满足所有需求。

#### Scenario: 指定 VARCHAR 长度限制

```zig
const User = struct {
    id: i64,
    username: []const u8,
    bio: []const u8,

    pub const table_name = "users";
    pub const schema = .{
        .username = .{ .sql_type = "VARCHAR(50)" },
        // bio 使用默认的 TEXT 类型
    };
};

const allocator = std.testing.allocator;
const columns = try generateColumns(User, allocator);
defer allocator.free(columns);

// username 应有 custom_sql_type
var username_col: ?Column = null;
for (columns) |col| {
    if (std.mem.eql(u8, col.name, "username")) {
        username_col = col;
        break;
    }
}

try std.testing.expect(username_col != null);
try std.testing.expect(username_col.?.custom_sql_type != null);
try std.testing.expectEqualStrings("VARCHAR(50)", username_col.?.custom_sql_type.?);
```

#### Scenario: CREATE TABLE SQL 使用自定义 SQL 类型

```zig
const User = struct {
    id: i64,
    username: []const u8,
    email: []const u8,

    pub const table_name = "users";
    pub const schema = .{
        .username = .{ .sql_type = "VARCHAR(50)" },
        .email = .{ .sql_type = "VARCHAR(100)" },
    };
};

const allocator = std.testing.allocator;
var table = try Table.init(allocator, "users");
defer table.deinit();

const columns = try generateColumns(User, allocator);
defer allocator.free(columns);

for (columns) |col| {
    _ = try table.addColumn(col);
}

const sql = try table.toSQL(.postgresql);
defer allocator.free(sql);

// SQL 应包含 "VARCHAR(50)" 和 "VARCHAR(100)"
try std.testing.expect(std.mem.indexOf(u8, sql, "username VARCHAR(50)") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "email VARCHAR(100)") != null);
```

#### Scenario: 任意 SQL 类型字符串支持

```zig
const Product = struct {
    id: i64,
    price: f64,
    metadata: []const u8,

    pub const table_name = "products";
    pub const schema = .{
        .price = .{ .sql_type = "DECIMAL(10, 2)" },
        .metadata = .{ .sql_type = "JSONB" },
    };
};

const allocator = std.testing.allocator;
const columns = try generateColumns(Product, allocator);
defer allocator.free(columns);

// price 应有 custom_sql_type = "DECIMAL(10, 2)"
var price_col: ?Column = null;
for (columns) |col| {
    if (std.mem.eql(u8, col.name, "price")) {
        price_col = col;
        break;
    }
}

try std.testing.expect(price_col != null);
try std.testing.expectEqualStrings("DECIMAL(10, 2)", price_col.?.custom_sql_type.?);
```

---

### Requirement: 约束配置组合支持

FieldSchema MUST 支持多个约束配置的组合使用，包括 column_name, sql_type, unique, default, check 等，所有配置应正确应用到生成的 Column 和 CREATE TABLE SQL 中。

**Context**: 实际场景中字段通常需要多个配置同时生效（如自定义列名 + 唯一约束 + 默认值），需要验证组合使用的正确性。

#### Scenario: 组合使用列名和 SQL 类型

```zig
const User = struct {
    user_name: []const u8,

    pub const table_name = "users";
    pub const schema = .{
        .user_name = .{
            .column_name = "username",
            .sql_type = "VARCHAR(50)",
        },
    };
};

const allocator = std.testing.allocator;
const columns = try generateColumns(User, allocator);
defer allocator.free(columns);

try std.testing.expectEqual(@as(usize, 1), columns.len);
try std.testing.expectEqualStrings("username", columns[0].name);
try std.testing.expectEqualStrings("VARCHAR(50)", columns[0].custom_sql_type.?);
```

#### Scenario: 组合使用约束配置

```zig
const User = struct {
    username: []const u8,
    age: u32,

    pub const table_name = "users";
    pub const schema = .{
        .username = .{
            .sql_type = "VARCHAR(50)",
            .unique = true,
        },
        .age = .{
            .check = "age >= 0 AND age <= 150",
            .default = "0",
        },
    };
};

const allocator = std.testing.allocator;
const columns = try generateColumns(User, allocator);
defer allocator.free(columns);

// username 应有 unique 约束
var username_col: ?Column = null;
for (columns) |col| {
    if (std.mem.eql(u8, col.name, "username")) {
        username_col = col;
        break;
    }
}
try std.testing.expect(username_col != null);
try std.testing.expect(username_col.?.unique);

// age 应有 check 和 default
var age_col: ?Column = null;
for (columns) |col| {
    if (std.mem.eql(u8, col.name, "age")) {
        age_col = col;
        break;
    }
}
try std.testing.expect(age_col != null);
try std.testing.expectEqualStrings("age >= 0 AND age <= 150", age_col.?.check_expr.?);
try std.testing.expectEqualStrings("0", age_col.?.default_value.?);
```

#### Scenario: 完整 PRD 示例验证

```zig
const User = struct {
    id: i64,
    username: []const u8,
    email: []const u8,
    age: u32,
    status: []const u8,
    created_at: i64,

    pub const table_name = "users";
    pub const schema = .{
        .id = .{ .primary_key = true, .auto_increment = true },
        .username = .{ .unique = true, .sql_type = "VARCHAR(50)" },
        .email = .{ .unique = true },
        .age = .{ .check = "age >= 0 AND age <= 150" },
        .status = .{ .default = "'active'" },
        .created_at = .{ .default = "CURRENT_TIMESTAMP" },
    };
};

const allocator = std.testing.allocator;
var table = try Table.init(allocator, "users");
defer table.deinit();

const columns = try generateColumns(User, allocator);
defer allocator.free(columns);

for (columns) |col| {
    _ = try table.addColumn(col);
}

const sql = try table.toSQL(.postgresql);
defer allocator.free(sql);

// 验证生成的 SQL 包含所有期望的部分
try std.testing.expect(std.mem.indexOf(u8, sql, "id BIGSERIAL PRIMARY KEY") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "username VARCHAR(50) UNIQUE") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "email TEXT UNIQUE") != null or
                       std.mem.indexOf(u8, sql, "email VARCHAR UNIQUE") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "age INTEGER") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "CHECK (age >= 0 AND age <= 150)") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "status") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "DEFAULT 'active'") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "created_at") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "DEFAULT CURRENT_TIMESTAMP") != null);
```

---

### Requirement: Column 结构支持自定义 SQL 类型存储

Column 结构 MUST 添加 `custom_sql_type: ?[]const u8` 字段，用于存储 FieldSchema 中配置的任意 SQL 类型字符串。

**Context**: 当前 Column.column_type 使用 ColumnType enum，无法表示任意 SQL 类型字符串（如 "VARCHAR(50)", "DECIMAL(10,2)"），需要新字段存储自定义类型。

#### Scenario: Column 包含 custom_sql_type 字段

```zig
var col = Column.init("username", .varchar);
col.custom_sql_type = "VARCHAR(50)";

try std.testing.expectEqualStrings("username", col.name);
try std.testing.expectEqual(ColumnType.varchar, col.column_type);
try std.testing.expect(col.custom_sql_type != null);
try std.testing.expectEqualStrings("VARCHAR(50)", col.custom_sql_type.?);
```

#### Scenario: toSQL 优先使用 custom_sql_type

```zig
const allocator = std.testing.allocator;
var table = try Table.init(allocator, "users");
defer table.deinit();

var col = Column.init("username", .varchar);
col.custom_sql_type = "VARCHAR(50)";
_ = col.setNotNull();

_ = try table.addColumn(col);

const sql = try table.toSQL(.postgresql);
defer allocator.free(sql);

// SQL 应使用 "VARCHAR(50)" 而非 "VARCHAR"
try std.testing.expect(std.mem.indexOf(u8, sql, "username VARCHAR(50) NOT NULL") != null);
```

---

### Requirement: 向后兼容性保证

所有新增的 schema 配置功能 MUST 保持向后兼容，现有不使用 schema 配置的代码应继续正常工作，生成的 SQL 保持不变。

**Context**: 大量现有代码依赖自动类型推断和默认行为，新功能不能破坏现有功能。

#### Scenario: 无 schema 配置时使用默认行为

```zig
const User = struct {
    id: i64,
    name: []const u8,
    email: ?[]const u8,

    pub const table_name = "users";
    // 无 schema 配置
};

const allocator = std.testing.allocator;
const columns = try generateColumns(User, allocator);
defer allocator.free(columns);

// 列名应使用字段名
try std.testing.expectEqualStrings("id", columns[0].name);
try std.testing.expectEqualStrings("name", columns[1].name);
try std.testing.expectEqualStrings("email", columns[2].name);

// 类型应使用自动推断
try std.testing.expect(columns[0].custom_sql_type == null);
try std.testing.expectEqual(ColumnType.bigint, columns[0].column_type);
try std.testing.expect(columns[1].custom_sql_type == null);
try std.testing.expectEqual(ColumnType.text, columns[1].column_type);
```

#### Scenario: 部分字段配置不影响其他字段

```zig
const User = struct {
    id: i64,
    username: []const u8,
    email: []const u8,

    pub const table_name = "users";
    pub const schema = .{
        .username = .{ .sql_type = "VARCHAR(50)" },
        // id 和 email 无配置，应使用默认行为
    };
};

const allocator = std.testing.allocator;
const columns = try generateColumns(User, allocator);
defer allocator.free(columns);

// id 和 email 使用默认行为
try std.testing.expectEqualStrings("id", columns[0].name);
try std.testing.expect(columns[0].custom_sql_type == null);

try std.testing.expectEqualStrings("email", columns[2].name);
try std.testing.expect(columns[2].custom_sql_type == null);

// username 使用自定义配置
try std.testing.expectEqualStrings("username", columns[1].name);
try std.testing.expectEqualStrings("VARCHAR(50)", columns[1].custom_sql_type.?);
```

