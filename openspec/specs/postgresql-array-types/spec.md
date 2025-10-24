# postgresql-array-types Specification

## Purpose
TBD - created by archiving change extend-postgresql-specific-types. Update Purpose after archive.
## Requirements
### Requirement: Zig slice 类型自动映射到 PostgreSQL 数组类型

类型系统 MUST 支持检测 Zig slice 类型(如 `[]i64`, `[][]const u8`)并自动映射到对应的 PostgreSQL 数组类型(如 `BIGINT[]`, `TEXT[]`)。

**Context**: PostgreSQL 支持数组类型存储多值数据,Zig 的 slice 是天然的对应类型,需要实现自动映射以提升开发体验。

#### Scenario: 检测整数数组类型

```zig
const types = @import("schema/types.zig");

// []i64 应映射为 BIGINT[]
const sql_type = types.zigToSQLType([]i64);
try std.testing.expectEqual(types.SQLType.bigint_array, sql_type);

// []i32 应映射为 INTEGER[]
const sql_type2 = types.zigToSQLType([]i32);
try std.testing.expectEqual(types.SQLType.integer_array, sql_type2);
```

#### Scenario: 检测字符串数组类型

```zig
const types = @import("schema/types.zig");

// [][]const u8 应映射为 TEXT[]
const sql_type = types.zigToSQLType([][]const u8);
try std.testing.expectEqual(types.SQLType.text_array, sql_type);
```

#### Scenario: 检测布尔和浮点数组类型

```zig
const types = @import("schema/types.zig");

// []bool 应映射为 BOOLEAN[]
const bool_type = types.zigToSQLType([]bool);
try std.testing.expectEqual(types.SQLType.boolean_array, bool_type);

// []f64 应映射为 DOUBLE PRECISION[]
const double_type = types.zigToSQLType([]f64);
try std.testing.expectEqual(types.SQLType.double_array, double_type);
```

#### Scenario: SQLType enum 包含数组类型变体

```zig
const types = @import("schema/types.zig");

// 验证 SQLType 包含所有必要的数组类型
const integer_array: types.SQLType = .integer_array;
const bigint_array: types.SQLType = .bigint_array;
const text_array: types.SQLType = .text_array;
const boolean_array: types.SQLType = .boolean_array;
const real_array: types.SQLType = .real_array;
const double_array: types.SQLType = .double_array;

try std.testing.expectEqual(types.SQLType.integer_array, integer_array);
try std.testing.expectEqual(types.SQLType.bigint_array, bigint_array);
try std.testing.expectEqual(types.SQLType.text_array, text_array);
```

---

### Requirement: 数组类型 SQL 字符串生成

`SQLType.toSQL()` MUST 正确生成 PostgreSQL 数组类型的 SQL 字符串表示(如 `INTEGER[]`, `TEXT[]`)。

**Context**: CREATE TABLE 和其他 DDL 语句需要正确的 SQL 类型字符串。

#### Scenario: 生成数组类型 SQL 字符串

```zig
const types = @import("schema/types.zig");
const Dialect = @import("dialect/dialect.zig").Dialect;

try std.testing.expectEqualStrings("INTEGER[]", types.SQLType.integer_array.toSQL(.postgresql));
try std.testing.expectEqualStrings("BIGINT[]", types.SQLType.bigint_array.toSQL(.postgresql));
try std.testing.expectEqualStrings("TEXT[]", types.SQLType.text_array.toSQL(.postgresql));
try std.testing.expectEqualStrings("BOOLEAN[]", types.SQLType.boolean_array.toSQL(.postgresql));
try std.testing.expectEqualStrings("REAL[]", types.SQLType.real_array.toSQL(.postgresql));
try std.testing.expectEqualStrings("DOUBLE PRECISION[]", types.SQLType.double_array.toSQL(.postgresql));
```

---

### Requirement: CREATE TABLE 生成数组列定义

`generateCreateTableSQL()` MUST 为数组类型字段生成正确的 CREATE TABLE SQL,包含正确的数组类型定义。

**Context**: 开发者使用数组类型字段时,CREATE TABLE 应自动生成正确的 SQL。

#### Scenario: 生成包含数组列的 CREATE TABLE

```zig
const reflection = @import("schema/reflection.zig");
const Dialect = @import("dialect/dialect.zig").Dialect;

const Article = struct {
    id: i64,
    title: []const u8,
    tags: [][]const u8,        // TEXT[]
    view_counts: []i32,         // INTEGER[]
    is_featured: []bool,        // BOOLEAN[]

    pub const table_name = "articles";
};

const allocator = std.testing.allocator;
const sql = try reflection.generateCreateTableSQL(Article, .postgresql, allocator);
defer allocator.free(sql);

// 验证包含数组类型定义
try std.testing.expect(std.mem.indexOf(u8, sql, "tags TEXT[] NOT NULL") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "view_counts INTEGER[] NOT NULL") != null);
try std.testing.expect(std.mem.indexOf(u8, sql, "is_featured BOOLEAN[] NOT NULL") != null);
```

#### Scenario: 数组类型与 schema 配置组合

```zig
const reflection = @import("schema/reflection.zig");

const Product = struct {
    id: i64,
    related_ids: []i64,

    pub const table_name = "products";
    pub const schema = .{
        .related_ids = .{ .column_name = "related_product_ids" },
    };
};

const allocator = std.testing.allocator;
const sql = try reflection.generateCreateTableSQL(Product, .postgresql, allocator);
defer allocator.free(sql);

// 验证自定义列名 + 数组类型
try std.testing.expect(std.mem.indexOf(u8, sql, "related_product_ids BIGINT[] NOT NULL") != null);
```

---

### Requirement: 数组序列化为 PostgreSQL 数组字面量

`serializeArray()` MUST 将 Zig slice 序列化为 PostgreSQL 数组字面量字符串格式 `'{elem1,elem2,...}'`。

**Context**: INSERT 操作需要将 Zig 数组转换为 PostgreSQL 可识别的字面量格式。

#### Scenario: 序列化整数数组

```zig
const types = @import("core/types.zig");

const nums = &[_]i32{1, 2, 3, 4, 5};
const allocator = std.testing.allocator;

const result = try types.serializeArray(i32, nums, allocator);
defer allocator.free(result);

// PostgreSQL 数组字面量格式
try std.testing.expectEqualStrings("'{1,2,3,4,5}'", result);
```

#### Scenario: 序列化字符串数组

```zig
const types = @import("core/types.zig");

const tags = &[_][]const u8{"zig", "orm", "postgresql"};
const allocator = std.testing.allocator;

const result = try types.serializeArray([]const u8, tags, allocator);
defer allocator.free(result);

// 字符串需要引号
try std.testing.expectEqualStrings("'{\"zig\",\"orm\",\"postgresql\"}'", result);
```

#### Scenario: 序列化布尔数组

```zig
const types = @import("core/types.zig");

const flags = &[_]bool{true, false, true};
const allocator = std.testing.allocator;

const result = try types.serializeArray(bool, flags, allocator);
defer allocator.free(result);

try std.testing.expectEqualStrings("'{t,f,t}'", result);
```

#### Scenario: 序列化空数组

```zig
const types = @import("core/types.zig");

const empty: []const i32 = &[_]i32{};
const allocator = std.testing.allocator;

const result = try types.serializeArray(i32, empty, allocator);
defer allocator.free(result);

try std.testing.expectEqualStrings("'{}'", result);
```

#### Scenario: 字符串转义处理

```zig
const types = @import("core/types.zig");

const strings = &[_][]const u8{"hello \"world\"", "test\\path"};
const allocator = std.testing.allocator;

const result = try types.serializeArray([]const u8, strings, allocator);
defer allocator.free(result);

// 引号和反斜杠应被转义
try std.testing.expect(std.mem.indexOf(u8, result, "\\\"") != null);
try std.testing.expect(std.mem.indexOf(u8, result, "\\\\") != null);
```

---

### Requirement: PostgreSQL 数组字符串反序列化为 Zig ArrayList

`deserializeArray()` MUST 将 PostgreSQL 返回的数组字符串格式 `{elem1,elem2,...}` 反序列化为 Zig `ArrayList(T)`。

**Context**: SELECT 操作需要将 PostgreSQL 数组结果转换为 Zig 可用的数据结构。

#### Scenario: 反序列化整数数组

```zig
const types = @import("core/types.zig");

const pg_array = "{1,2,3,4,5}";
const allocator = std.testing.allocator;

var result = try types.deserializeArray(i32, pg_array, allocator);
defer result.deinit(allocator);

try std.testing.expectEqual(@as(usize, 5), result.items.len);
try std.testing.expectEqual(@as(i32, 1), result.items[0]);
try std.testing.expectEqual(@as(i32, 5), result.items[4]);
```

#### Scenario: 反序列化字符串数组

```zig
const types = @import("core/types.zig");

const pg_array = "{\"zig\",\"orm\",\"postgresql\"}";
const allocator = std.testing.allocator;

var result = try types.deserializeArray([]const u8, pg_array, allocator);
defer {
    for (result.items) |item| allocator.free(item);
    result.deinit(allocator);
}

try std.testing.expectEqual(@as(usize, 3), result.items.len);
try std.testing.expectEqualStrings("zig", result.items[0]);
try std.testing.expectEqualStrings("postgresql", result.items[2]);
```

#### Scenario: 反序列化空数组

```zig
const types = @import("core/types.zig");

const pg_array = "{}";
const allocator = std.testing.allocator;

var result = try types.deserializeArray(i32, pg_array, allocator);
defer result.deinit(allocator);

try std.testing.expectEqual(@as(usize, 0), result.items.len);
```

#### Scenario: 无效格式返回错误

```zig
const types = @import("core/types.zig");

const invalid1 = "1,2,3";  // 缺少 {}
const invalid2 = "{1,2,3";  // 缺少 }
const allocator = std.testing.allocator;

try std.testing.expectError(error.InvalidFormat, types.deserializeArray(i32, invalid1, allocator));
try std.testing.expectError(error.InvalidFormat, types.deserializeArray(i32, invalid2, allocator));
```

---

### Requirement: 数组类型辅助函数

类型系统 MUST 提供辅助函数用于检测和操作数组类型,支持 comptime 类型检查。

**Context**: Query Builder 和序列化逻辑需要在编译时和运行时判断类型是否为数组。

#### Scenario: 检测类型是否为数组

```zig
const types = @import("schema/types.zig");

try std.testing.expect(types.isArrayType([]i64));
try std.testing.expect(types.isArrayType([][]const u8));
try std.testing.expect(!types.isArrayType(i64));
try std.testing.expect(!types.isArrayType([]const u8));  // 字符串不是数组
```

#### Scenario: 获取数组元素类型

```zig
const types = @import("schema/types.zig");

const elem_type1 = types.arrayElementType([]i64);
try std.testing.expectEqual(i64, elem_type1);

const elem_type2 = types.arrayElementType([][]const u8);
try std.testing.expectEqual([]const u8, elem_type2);
```

#### Scenario: 将基础类型映射到数组类型

```zig
const types = @import("schema/types.zig");

const array_type1 = types.mapToArrayType(.integer);
try std.testing.expectEqual(types.SQLType.integer_array, array_type1);

const array_type2 = types.mapToArrayType(.text);
try std.testing.expectEqual(types.SQLType.text_array, array_type2);
```

---

### Requirement: 数组类型在 ColumnType 中的表示

`ColumnType` enum MUST 支持数组类型,使 Column 结构能够表示数组列。

**Context**: Column 结构需要正确表示数组类型以支持 Table 和 DDL 生成。

#### Scenario: ColumnType 包含数组类型

```zig
const table_mod = @import("schema/table.zig");

// ColumnType 应包含数组类型变体
const int_array: table_mod.ColumnType = .int_array;
const bigint_array: table_mod.ColumnType = .bigint_array;
const text_array: table_mod.ColumnType = .text_array;

try std.testing.expectEqual(table_mod.ColumnType.int_array, int_array);
```

#### Scenario: Column 使用数组类型

```zig
const table_mod = @import("schema/table.zig");

var col = table_mod.Column.init("tags", .text_array);
_ = col.setNotNull();

try std.testing.expectEqualStrings("tags", col.name);
try std.testing.expectEqual(table_mod.ColumnType.text_array, col.column_type);
try std.testing.expect(!col.nullable);
```

---

### Requirement: PRD Story 3.6 AC3.6.2 示例验证

完整的 PRD AC3.6.2 示例代码 MUST 可编译并通过测试,验证数组类型的端到端支持。

**Context**: 确保实现符合 PRD 要求,提供真实可用的示例。

#### Scenario: PRD AC3.6.8 Article 示例

```zig
const Article = struct {
    id: i64,
    title: []const u8,
    tags: [][]const u8,         // TEXT[] 数组
    metadata: []const u8,        // JSONB (本 spec 不涉及)
    view_counts: []i32,          // INTEGER[] 数组
    created_at: i64,

    pub const table_name = "articles";

    pub const schema = .{
        .id = .{ .primary_key = true },
        .tags = .{ .sql_type = "TEXT[]" },
        .view_counts = .{ .sql_type = "INTEGER[]" },
    };
};

const allocator = std.testing.allocator;
const reflection = @import("schema/reflection.zig");

// 验证 CREATE TABLE 生成
var create = try db.newCreateTable(Article);
defer create.deinit();

try create.ifNotExists().exec();

// 验证 INSERT 数组数据
const article = Article{
    .id = 1,
    .title = "Introduction to ZORM",
    .tags = &[_][]const u8{ "zig", "orm", "postgresql" },
    .metadata = "{\"author\": \"John\", \"draft\": false}",
    .view_counts = &[_]i32{ 100, 200, 150 },
    .created_at = std.time.timestamp(),
};

var insert = try db.newInsert(Article);
defer insert.deinit();

_ = try insert.value(article).exec();

// 验证 SELECT 反序列化数组
var articles: std.ArrayList(Article) = .{};
defer articles.deinit(allocator);

var select = try db.newSelect(Article);
defer select.deinit();

try select.where("id = ?", .{1}).scan(&articles);

try std.testing.expectEqual(@as(usize, 1), articles.items.len);
try std.testing.expectEqual(@as(usize, 3), articles.items[0].tags.len);
try std.testing.expectEqualStrings("zig", articles.items[0].tags[0]);
try std.testing.expectEqual(@as(i32, 100), articles.items[0].view_counts[0]);
```

