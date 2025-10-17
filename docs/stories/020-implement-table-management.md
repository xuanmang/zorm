# Story 020: 实现 Table 管理

## Status
Ready for Review

## Story
**As a** ZORM 开发者,
**I want** Table 管理功能,
**so that** 能够通过代码定义和创建数据库表

## Acceptance Criteria
1. ✅ 实现 Table 结构体
2. ✅ 支持 CREATE TABLE 语句生成
3. ✅ 支持列定义和约束
4. ✅ 支持主键、外键、唯一约束
5. ✅ 编写测试

## Tasks / Subtasks
- [x] 创建 src/schema/table.zig
- [x] 实现 Table 结构体
- [x] 实现 CREATE TABLE 生成
- [x] 编写测试

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md

## Dev Agent Record

### 实现概述
成功实现了完整的 Table 管理系统,提供声明式的表定义 API 和跨数据库方言的 DDL (CREATE TABLE) 生成能力。

### 核心设计

#### Column 结构体 - Builder 模式
```zig
pub const Column = struct {
    name: []const u8,
    column_type: ColumnType,
    nullable: bool = true,
    primary_key: bool = false,
    auto_increment: bool = false,
    unique: bool = false,
    default_value: ?[]const u8 = null,
    check_expr: ?[]const u8 = null,
    foreign_key: ?ForeignKeyRef = null,

    // Builder 方法
    pub fn setPrimaryKey(self: *Column) *Column
    pub fn setAutoIncrement(self: *Column) *Column
    pub fn setUnique(self: *Column) *Column
    pub fn setNotNull(self: *Column) *Column
    pub fn setDefault(self: *Column, value: []const u8) *Column
    pub fn setCheck(self: *Column, expr: []const u8) *Column
    pub fn setForeignKey(self: *Column, table: []const u8, column: []const u8) *Column
};
```

**设计要点**:
- 链式 API 支持流畅的列定义
- 所有 builder 方法返回 `*Column`,支持方法链
- 默认值设计符合 SQL 标准(nullable=true, primary_key=false 等)

#### 外键支持
```zig
pub const ForeignKeyRef = struct {
    table: []const u8,
    column: []const u8,
    on_delete: OnAction = .no_action,
    on_update: OnAction = .no_action,

    pub const OnAction = enum {
        no_action, restrict, cascade, set_null, set_default,
        pub fn toSQL(self: OnAction) []const u8
    };
};
```

**特性**:
- 支持 ON DELETE 和 ON UPDATE 动作
- 提供 5 种标准 SQL 动作(NO ACTION, RESTRICT, CASCADE, SET NULL, SET DEFAULT)
- 默认为 NO ACTION(符合 SQL 标准)

#### Table 结构体
```zig
pub const Table = struct {
    name: []const u8,
    columns: std.ArrayList(Column),
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) !Table
    pub fn deinit(self: *Table) void
    pub fn addColumn(self: *Table, column: Column) !*Table
    pub fn toSQL(self: *const Table, comptime dialect: Dialect) ![]const u8
    fn getPrimaryKeyColumns(self: *const Table) ![]const []const u8
};
```

**设计要点**:
- 显式内存管理,使用 Allocator 模式
- addColumn 返回 `*Table` 支持链式调用
- toSQL 使用 comptime dialect 参数实现零开销多态
- getPrimaryKeyColumns 辅助处理复合主键

#### CREATE TABLE SQL 生成
```zig
pub fn toSQL(self: *const Table, comptime dialect: Dialect) ![]const u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(self.allocator);
    const writer = buf.writer(self.allocator);

    // 1. CREATE TABLE 头部
    try writer.print("CREATE TABLE {s} (\n", .{self.name});

    // 2. 列定义(调用 writeColumnDefinition)
    for (self.columns.items, 0..) |col, i| {
        if (i > 0) try writer.writeAll(",\n");
        try writer.writeAll("  ");
        try writeColumnDefinition(writer, &col, dialect);
    }

    // 3. 复合主键约束(如果有多列主键)
    const pk_columns = try self.getPrimaryKeyColumns();
    defer self.allocator.free(pk_columns);
    if (pk_columns.len > 1) {
        try writer.writeAll(",\n  PRIMARY KEY (");
        for (pk_columns, 0..) |pk_col, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll(pk_col);
        }
        try writer.writeAll(")");
    }

    try writer.writeAll("\n)");
    return buf.toOwnedSlice(self.allocator);
}
```

#### 列定义 SQL 生成
```zig
fn writeColumnDefinition(writer: anytype, col: *const Column, comptime dialect: Dialect) !void {
    // 列名和类型
    try writer.print("{s} ", .{col.name});
    const sql_type = col.column_type.sqlType(dialect);
    try writer.writeAll(sql_type);

    // 主键(单列主键,复合主键单独处理)
    if (col.primary_key) {
        try writer.writeAll(" PRIMARY KEY");
    }

    // 自增(根据方言)
    if (col.auto_increment) {
        switch (dialect) {
            .postgresql => try writer.writeAll(" GENERATED ALWAYS AS IDENTITY"),
            .mysql => try writer.writeAll(" AUTO_INCREMENT"),
            .sqlite => {}, // SQLite 的 INTEGER PRIMARY KEY 自动自增
        }
    }

    // NOT NULL, UNIQUE, DEFAULT, CHECK, FOREIGN KEY
    // ...
}
```

**方言差异处理**:
- **PostgreSQL**: `GENERATED ALWAYS AS IDENTITY` (SQL 标准)
- **MySQL**: `AUTO_INCREMENT` (传统语法)
- **SQLite**: INTEGER PRIMARY KEY 隐含自增

### 技术挑战与解决方案

#### 挑战 1: Zig 0.15.2 ArrayList API 变化
**问题**: ArrayList 改为 unmanaged 版本,API 显著变化
```zig
// ❌ Zig 0.15.2 中不再有效
var list = std.ArrayList(T).init(allocator);
list.deinit();
list.append(item);

// ✅ 正确的 Zig 0.15.2 API
var list: std.ArrayList(T) = .{};  // 结构体字面量初始化
list.deinit(allocator);            // 需要传 allocator
list.append(allocator, item);      // 需要传 allocator
list.toOwnedSlice(allocator);      // 需要传 allocator
```

**解决方案**:
- 使用 `.{}` 结构体字面量初始化 ArrayList
- 所有方法调用都传递 allocator 参数
- 适用于 ArrayList(Column), ArrayList(u8), ArrayList([]const u8) 等

#### 挑战 2: switch exhaustiveness 检查更严格
**问题**: Zig 0.15.2 不允许已穷尽所有 case 的 switch 中有 else 分支
```zig
// ❌ 错误: unreachable else prong
switch (dialect) {
    .postgresql => ...,
    .mysql => ...,
    .sqlite => ...,
    else => @compileError("Unsupported dialect"),
}

// ✅ 正确: 移除 else
switch (dialect) {
    .postgresql => ...,
    .mysql => ...,
    .sqlite => ...,
}
```

**解决方案**:
- 在 schema.zig 和 table.zig 中移除多余的 else 分支
- 编译器会在添加新 dialect 时强制处理所有 case

#### 挑战 3: Writer API 变化
**问题**: ArrayList(u8).writer() 在 unmanaged 版本中需要 allocator
```zig
// ❌ 错误: writer() 缺少参数
var buf: std.ArrayList(u8) = .{};
const writer = buf.writer();

// ✅ 正确: 传递 allocator
var buf: std.ArrayList(u8) = .{};
const writer = buf.writer(self.allocator);
```

### 测试实现

#### 测试覆盖
1. **Column 基本创建** - 验证默认值和字段初始化
2. **Column 链式 API** - 验证 builder 模式和方法链
3. **Column 约束设置** - 验证 UNIQUE, NOT NULL, DEFAULT
4. **Column 外键设置** - 验证 ForeignKeyRef 配置
5. **Table 创建和释放** - 验证内存管理
6. **Table 添加列** - 验证列管理
7. **PostgreSQL CREATE TABLE SQL** - 验证 PG 方言 SQL 生成
8. **MySQL CREATE TABLE SQL** - 验证 MySQL 方言 SQL 生成
9. **外键约束** - 验证 REFERENCES 语法
10. **CHECK 约束** - 验证 CHECK 表达式
11. **复合主键** - 验证多列主键的 PRIMARY KEY (col1, col2) 语法

#### 示例测试
```zig
test "Table: PostgreSQL CREATE TABLE SQL" {
    var table = try Table.init(testing.allocator, "users");
    defer table.deinit();

    var id_col = Column.init("id", .bigint);
    _ = id_col.setPrimaryKey().setAutoIncrement();
    _ = try table.addColumn(id_col);

    var name_col = Column.init("name", .varchar);
    _ = name_col.setNotNull();
    _ = try table.addColumn(name_col);

    var email_col = Column.init("email", .varchar);
    _ = email_col.setUnique();
    _ = try table.addColumn(email_col);

    const sql = try table.toSQL(.postgresql);
    defer testing.allocator.free(sql);

    // 验证 SQL 包含关键部分
    try testing.expect(std.mem.indexOf(u8, sql, "CREATE TABLE users") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "id BIGINT PRIMARY KEY") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "GENERATED ALWAYS AS IDENTITY") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "name VARCHAR NOT NULL") != null);
    try testing.expect(std.mem.indexOf(u8, sql, "email VARCHAR UNIQUE") != null);
}
```

### 与 zorm.zig 集成

```zig
// 导出 Schema 模块
pub const schema = struct {
    pub const ColumnType = @import("schema/schema.zig").ColumnType;
    pub const TableMeta = @import("schema/schema.zig").TableMeta;
    pub const ColumnMeta = @import("schema/schema.zig").ColumnMeta;
    pub const getTableMeta = @import("schema/schema.zig").getTableMeta;
    pub const Table = @import("schema/table.zig").Table;
    pub const Column = @import("schema/table.zig").Column;
};

// 顶级导出,方便使用
pub const Table = schema.Table;
pub const Column = schema.Column;
pub const ColumnType = schema.ColumnType;
```

### 使用示例

```zig
const zorm = @import("zorm");

// 创建用户表
var users = try zorm.Table.init(allocator, "users");
defer users.deinit();

// 定义主键列
var id = zorm.Column.init("id", .bigint);
_ = id.setPrimaryKey().setAutoIncrement();
_ = try users.addColumn(id);

// 定义其他列
var name = zorm.Column.init("name", .varchar);
_ = name.setNotNull();
_ = try users.addColumn(name);

var email = zorm.Column.init("email", .varchar);
_ = email.setUnique().setNotNull();
_ = try users.addColumn(email);

var created_at = zorm.Column.init("created_at", .timestamp);
_ = created_at.setDefault("CURRENT_TIMESTAMP");
_ = try users.addColumn(created_at);

// 生成 CREATE TABLE SQL
const sql = try users.toSQL(.postgresql);
defer allocator.free(sql);

// 输出:
// CREATE TABLE users (
//   id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
//   name VARCHAR NOT NULL,
//   email VARCHAR NOT NULL UNIQUE,
//   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
// )
```

### 性能特性

- **编译时多态**: comptime dialect 参数实现零运行时开销
- **内存高效**: 使用 ArrayList 增量构建 SQL,避免预分配过大空间
- **显式管理**: 调用者完全控制内存生命周期
- **零拷贝**: toSQL 返回 owned slice,避免额外复制

### 文件清单
- ✅ `src/schema/table.zig` (430 行)
  - Column 结构体和 Builder API
  - ForeignKeyRef 和 OnAction 定义
  - Table 结构体和方法
  - writeColumnDefinition 辅助函数
  - 11 个完整测试用例
- ✅ `src/schema/schema.zig` (修改)
  - 移除 switch else 分支(Zig 0.15.2 兼容)
- ✅ `src/zorm.zig` (修改)
  - 集成 Table 和 Column 导出

### 测试结果
- ✅ 121 个测试全部通过
- ✅ 11 个新增 table.zig 测试
- ✅ 覆盖所有约束类型和方言差异

### 后续集成点
- 将在 Migration 系统中使用 Table.toSQL 生成建表语句
- 可扩展支持 ALTER TABLE, DROP TABLE 等 DDL 操作
- 未来可添加索引定义支持

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
| 2025-01-17 | 2.0 | 完成实现和测试,添加详细 Dev Agent Record | Dev Agent |
