# jsonb-serialization Specification

## Purpose
TBD - created by archiving change extend-postgresql-specific-types. Update Purpose after archive.
## Requirements
### Requirement: JSONB 类型通过 schema 配置标识

开发者 MUST 能够通过 `schema.sql_type = "JSONB"` 将 `[]const u8` 字段标识为 JSONB 类型,区别于普通 TEXT 类型。

**Context**: Zig 侧使用 `[]const u8` 存储 JSON 字符串,需要显式配置以区分 TEXT 和 JSONB。

#### Scenario: Schema 配置 JSONB 类型

```zig
const Product = struct {
    id: i64,
    name: []const u8,       // TEXT
    metadata: []const u8,   // JSONB

    pub const table_name = "products";

    pub const schema = .{
        .metadata = .{ .sql_type = "JSONB" },
    };
};

const allocator = std.testing.allocator;
const reflection = @import("schema/reflection.zig");

const columns = try reflection.generateColumns(Product, allocator);
defer allocator.free(columns);

// metadata 应有 custom_sql_type = "JSONB"
var metadata_col: ?table_mod.Column = null;
for (columns) |col| {
    if (std.mem.eql(u8, col.name, "metadata")) {
        metadata_col = col;
        break;
    }
}

try std.testing.expect(metadata_col != null);
try std.testing.expectEqualStrings("JSONB", metadata_col.?.custom_sql_type.?);
```

---

### Requirement: CREATE TABLE 生成 JSONB 列

`generateCreateTableSQL()` MUST 为配置了 `sql_type = "JSONB"` 的字段生成正确的 JSONB 列定义。

**Context**: CREATE TABLE 应生成 PostgreSQL JSONB 类型列。

#### Scenario: 生成 JSONB 列的 CREATE TABLE

```zig
const Product = struct {
    id: i64,
    metadata: []const u8,

    pub const table_name = "products";
    pub const schema = .{
        .metadata = .{ .sql_type = "JSONB" },
    };
};

const allocator = std.testing.allocator;
const reflection = @import("schema/reflection.zig");

const sql = try reflection.generateCreateTableSQL(Product, .postgresql, allocator);
defer allocator.free(sql);

// 验证包含 JSONB 类型
try std.testing.expect(std.mem.indexOf(u8, sql, "metadata JSONB NOT NULL") != null);
```

---

### Requirement: JSON 序列化函数

类型系统 MUST 提供 `serializeJSON()` 函数,将 Zig 数据结构序列化为 JSON 字符串。

**Context**: INSERT 操作需要将 Zig struct/value 转换为 JSON 字符串存储到 JSONB 列。

#### Scenario: 序列化 struct 为 JSON

```zig
const types = @import("core/types.zig");

const Metadata = struct {
    author: []const u8,
    draft: bool,
    tags: []const []const u8,
};

const meta = Metadata{
    .author = "John",
    .draft = false,
    .tags = &[_][]const u8{"tech", "database"},
};

const allocator = std.testing.allocator;
const json_str = try types.serializeJSON(meta, allocator);
defer allocator.free(json_str);

// 验证 JSON 格式
try std.testing.expect(std.mem.indexOf(u8, json_str, "\"author\":\"John\"") != null or
                       std.mem.indexOf(u8, json_str, "\"author\": \"John\"") != null);
try std.testing.expect(std.mem.indexOf(u8, json_str, "\"draft\":false") != null or
                       std.mem.indexOf(u8, json_str, "\"draft\": false") != null);
```

#### Scenario: 序列化简单值为 JSON

```zig
const types = @import("core/types.zig");

const num = 42;
const allocator = std.testing.allocator;

const json_str = try types.serializeJSON(num, allocator);
defer allocator.free(json_str);

try std.testing.expectEqualStrings("42", json_str);
```

#### Scenario: 序列化数组为 JSON

```zig
const types = @import("core/types.zig");

const arr = [_]i32{1, 2, 3, 4, 5};
const allocator = std.testing.allocator;

const json_str = try types.serializeJSON(arr, allocator);
defer allocator.free(json_str);

try std.testing.expectEqualStrings("[1,2,3,4,5]", json_str);
```

---

### Requirement: JSON 反序列化函数

类型系统 MUST 提供 `deserializeJSON()` 函数,将 JSON 字符串反序列化为 Zig 数据结构。

**Context**: SELECT 操作需要将 JSONB 列的 JSON 字符串转换为 Zig struct/value。

#### Scenario: 反序列化 JSON 为 struct

```zig
const types = @import("core/types.zig");

const Metadata = struct {
    author: []const u8,
    draft: bool,
};

const json_str = "{\"author\":\"John\",\"draft\":false}";
const allocator = std.testing.allocator;

const result = try types.deserializeJSON(Metadata, json_str, allocator);
defer allocator.free(result.author);  // 释放分配的字符串

try std.testing.expectEqualStrings("John", result.author);
try std.testing.expectEqual(false, result.draft);
```

#### Scenario: 反序列化 JSON 为简单值

```zig
const types = @import("core/types.zig");

const json_str = "42";
const allocator = std.testing.allocator;

const result = try types.deserializeJSON(i32, json_str, allocator);

try std.testing.expectEqual(@as(i32, 42), result);
```

#### Scenario: 无效 JSON 格式返回错误

```zig
const types = @import("core/types.zig");

const invalid_json = "{invalid json}";
const allocator = std.testing.allocator;

const Metadata = struct {
    author: []const u8,
};

try std.testing.expectError(error.InvalidJSONFormat,
    types.deserializeJSON(Metadata, invalid_json, allocator));
```

---

### Requirement: INSERT 操作集成 JSONB 序列化

INSERT Query Builder MUST 在绑定 JSONB 字段值时自动调用 JSON 序列化函数(或直接使用字符串)。

**Context**: 开发者插入数据时,JSONB 字段应自动处理序列化。

#### Scenario: INSERT JSONB 字段使用 JSON 字符串

```zig
const Product = struct {
    id: i64,
    name: []const u8,
    metadata: []const u8,  // JSONB

    pub const table_name = "products";
    pub const schema = .{
        .metadata = .{ .sql_type = "JSONB" },
    };
};

const product = Product{
    .id = 1,
    .name = "Widget",
    .metadata = "{\"color\":\"red\",\"size\":\"large\"}",  // 直接使用 JSON 字符串
};

var insert = try db.newInsert(Product);
defer insert.deinit();

const result = try insert.value(product).exec();

try std.testing.expectEqual(@as(usize, 1), result.rows_affected);
```

---

### Requirement: SELECT 操作集成 JSONB 反序列化

SELECT Query Builder MUST 在扫描 JSONB 字段时将 JSON 字符串直接赋值给 Zig `[]const u8` 字段。

**Context**: SELECT 查询 JSONB 列时,PostgreSQL 返回 JSON 字符串,直接赋值给 Zig 字段即可。

#### Scenario: SELECT JSONB 字段为字符串

```zig
const Product = struct {
    id: i64,
    name: []const u8,
    metadata: []const u8,  // JSONB

    pub const table_name = "products";
    pub const schema = .{
        .metadata = .{ .sql_type = "JSONB" },
    };
};

var products: std.ArrayList(Product) = .{};
defer products.deinit(allocator);

var select = try db.newSelect(Product);
defer select.deinit();

try select.where("id = ?", .{1}).scan(&products);

try std.testing.expectEqual(@as(usize, 1), products.items.len);

// metadata 是 JSON 字符串
const metadata = products.items[0].metadata;
try std.testing.expect(std.mem.indexOf(u8, metadata, "\"color\"") != null);
```

---

### Requirement: JSONB 字段类型检测辅助函数

类型系统 MUST 提供辅助函数,在 comptime 检测字段是否为 JSONB 类型。

**Context**: Query Builder 需要判断字段是否为 JSONB 以决定是否需要特殊处理。

#### Scenario: 检测字段是否为 JSONB

```zig
const schema_lib = @import("schema/schema.zig");

const Product = struct {
    id: i64,
    name: []const u8,
    metadata: []const u8,

    pub const schema = .{
        .metadata = .{ .sql_type = "JSONB" },
    };
};

// isJSONBField 应检测 schema.sql_type
const is_jsonb = comptime schema_lib.isJSONBField(Product, "metadata");
const is_not_jsonb = comptime schema_lib.isJSONBField(Product, "name");

try std.testing.expect(is_jsonb);
try std.testing.expect(!is_not_jsonb);
```

---

### Requirement: PRD Story 3.6 AC3.6.1 示例验证

PRD AC3.6.1 关于 JSONB 的示例代码 MUST 可编译并通过测试。

**Context**: 确保 JSONB 支持符合 PRD 要求。

#### Scenario: PRD AC3.6.8 JSONB 示例部分

```zig
const Article = struct {
    id: i64,
    title: []const u8,
    metadata: []const u8,        // JSONB

    pub const table_name = "articles";
    pub const schema = .{
        .metadata = .{ .sql_type = "JSONB" },
    };
};

const allocator = std.testing.allocator;

// CREATE TABLE
var create = try db.newCreateTable(Article);
defer create.deinit();
try create.ifNotExists().exec();

// INSERT
const article = Article{
    .id = 1,
    .title = "Introduction to ZORM",
    .metadata = "{\"author\": \"John\", \"draft\": false}",
};

var insert = try db.newInsert(Article);
defer insert.deinit();
_ = try insert.value(article).exec();

// SELECT
var articles: std.ArrayList(Article) = .{};
defer articles.deinit(allocator);

var select = try db.newSelect(Article);
defer select.deinit();

try select.where("id = ?", .{1}).scan(&articles);

try std.testing.expectEqual(@as(usize, 1), articles.items.len);

// 验证 metadata 是有效的 JSON
const metadata = articles.items[0].metadata;
try std.testing.expect(std.mem.indexOf(u8, metadata, "\"author\"") != null);
try std.testing.expect(std.mem.indexOf(u8, metadata, "\"draft\"") != null);
```

