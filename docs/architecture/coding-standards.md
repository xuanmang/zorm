# ZORM 编码标准文档

**Version**: v1.0
**Date**: 2025-10-19
**Project**: ZORM - SQL-first Zig ORM for PostgreSQL
**Audience**: AI 开发代理和人类开发者

---

## 文档目的

本文档定义 ZORM 项目的**强制性编码标准**，用于：
1. **AI 代理开发**：确保生成的代码符合项目规范
2. **人类代码审查**：提供统一的审查标准
3. **项目一致性**：维护代码库的长期可维护性

**重要提示**：本文档仅包含**关键规则**和**项目特定约定**，假设开发者（AI 或人类）已掌握 Zig 语言基础和通用最佳实践。

---

## 核心原则

### 1. Zig 语言版本

- **最低版本**: Zig 0.15.2
- **目标版本**: Zig 0.15.x 系列
- **关键特性依赖**:
  - ArrayList 新 API: `var list: std.ArrayList(T) = .{};` + `list.deinit(allocator)`
  - comptime 元编程和类型反射
  - error union 强制错误处理

### 2. 代码格式化

- **工具**: `zig fmt` (官方格式化工具)
- **执行时机**: 提交前必须运行 `zig fmt src/`
- **配置**: 使用默认配置，不自定义
- **CI 检查**: GitHub Actions 自动验证格式

### 3. 文档注释

**强制要求**：所有公共 API 必须包含完整文档注释

```zig
/// 创建新的 SELECT 查询构建器
///
/// 自动从类型 T 推断表名和列映射。
///
/// ## 参数
/// - `allocator`: 内存分配器，用于查询构建过程
/// - `T`: 目标结构体类型，必须包含 comptime 可反射的字段
///
/// ## 返回值
/// 返回 SelectQuery 构建器实例，调用者负责调用 `deinit()` 释放资源
///
/// ## 错误
/// - `error.OutOfMemory`: 内存分配失败
/// - `error.InvalidType`: T 不是有效的结构体类型
///
/// ## 示例
/// ```zig
/// const User = struct { id: i64, name: []const u8 };
/// var query = try db.newSelect(User, allocator);
/// defer query.deinit();
/// ```
pub fn newSelect(comptime T: type, allocator: Allocator) !SelectQuery(T) {
    // ...
}
```

**文档注释规则**：
- 使用 `///` 三斜线注释（不使用 `//!`）
- 包含：功能说明、参数、返回值、错误、示例代码
- 示例代码必须可编译并通过测试验证

---

## 内存管理规范

### 1. Allocator 模式（强制）

**规则**：所有需要动态内存的 API 必须接受 `std.mem.Allocator` 参数

```zig
// ✅ 正确
pub fn init(allocator: Allocator, config: Config) !DB {
    var db = DB{
        .allocator = allocator,
        .conn = try allocator.create(Connection),
    };
    return db;
}

// ❌ 错误 - 禁止内部隐式分配器
pub fn init(config: Config) !DB {
    const allocator = std.heap.page_allocator; // ❌ 禁止
    // ...
}
```

### 2. 资源清理模式

**规则**：所有资源（DB、Query、Transaction）必须提供 `deinit()` 方法

```zig
/// 释放查询构建器资源
pub fn deinit(self: *Self) void {
    self.columns.deinit(self.allocator);
    self.where_clauses.deinit(self.allocator);
    // 释放所有 ArrayList 和分配的内存
}
```

**使用模式**：配合 `defer` 确保资源释放

```zig
var query = try db.newSelect(User);
defer query.deinit(); // ✅ 总是使用 defer

try query.where("age > ?", .{18}).scan(&users);
```

### 3. ArrayList 使用规范（Zig 0.15.2+）

**重要**：Zig 0.15.2 改变了 ArrayList API

```zig
// ✅ 正确 (Zig 0.15.2+)
var users: std.ArrayList(User) = .{};
defer users.deinit(allocator);

// ❌ 错误 (旧版 API，不再适用)
var users = std.ArrayList(User).init(allocator); // ❌
defer users.deinit(); // ❌ 缺少 allocator 参数
```

### 4. 错误路径清理

**规则**：使用 `errdefer` 处理错误路径的资源清理

```zig
pub fn createTable(self: *DB, comptime T: type) !void {
    var sql_buf: std.ArrayList(u8) = .{};
    errdefer sql_buf.deinit(self.allocator); // 错误时自动清理

    try sql_buf.appendSlice(self.allocator, "CREATE TABLE ");
    // ... 可能失败的操作

    defer sql_buf.deinit(self.allocator); // 正常路径清理
}
```

---

## 错误处理规范

### 1. 错误联合类型（强制）

**规则**：所有可能失败的操作必须返回 `!T` error union

```zig
// ✅ 正确
pub fn exec(self: *InsertQuery) !InsertResult {
    return self.db.execute(try self.build());
}

// ❌ 错误 - 禁止返回可选类型表示错误
pub fn exec(self: *InsertQuery) ?InsertResult { // ❌
    // ...
}
```

### 2. 错误传播

**规则**：使用 `try` 传播错误，避免 `catch` 吞没错误

```zig
// ✅ 正确
const result = try self.db.query(sql, args);

// ❌ 错误 - 不要无条件 catch
const result = self.db.query(sql, args) catch null; // ❌ 丢失错误信息
```

**例外**：仅在有明确错误处理逻辑时使用 `catch`

```zig
// ✅ 可接受 - 有具体处理逻辑
const user = self.findById(id) catch |err| switch (err) {
    error.NoRows => return error.UserNotFound,
    else => return err,
};
```

### 3. 自定义错误类型

**规则**：定义清晰的项目特定错误类型

```zig
pub const ZormError = error{
    NoRows,              // 查询无结果
    MultipleRows,        // 期望单行但返回多行
    InvalidType,         // 不支持的类型
    SQLSyntaxError,      // SQL 语法错误
    ConnectionClosed,    // 数据库连接已关闭
    TransactionActive,   // 已有活跃事务
};
```

---

## 命名约定

### 1. 标识符命名规则

| 元素类型 | 命名风格 | 示例 | 说明 |
|---------|---------|------|------|
| **类型** (struct/enum/union) | PascalCase | `SelectQuery`, `DBConfig` | 类型名使用大驼峰 |
| **函数/方法** | camelCase | `newSelect`, `addWhere` | 函数名使用小驼峰 |
| **常量** | SCREAMING_SNAKE_CASE | `MAX_CONNECTIONS` | 常量全大写+下划线 |
| **变量** | snake_case | `user_id`, `query_str` | 局部变量使用下划线 |
| **字段** | snake_case | `table_name`, `rows_affected` | 结构体字段使用下划线 |

### 2. API 命名模式

**查询构建器方法**：动词+名词

```zig
pub fn newSelect(...)   // new + 查询类型
pub fn newInsert(...)
pub fn where(...)       // 条件方法
pub fn orderBy(...)     // 排序方法
pub fn limit(...)       // 限制方法
```

**执行方法**：

```zig
pub fn exec(...)          // 执行并返回结果摘要
pub fn scan(...)          // 执行并扫描到 ArrayList
pub fn scanOne(...)       // 执行并扫描单行
pub fn build(...)         // 仅构建 SQL，不执行
```

### 3. 文件命名

- **源文件**: `snake_case.zig` (例如: `query_builder.zig`)
- **测试文件**: `{module}_test.zig` (例如: `query_builder_test.zig`)
- **示例文件**: `{scenario}.zig` (例如: `basic_usage.zig`)

---

## Comptime 元编程规范

### 1. 类型参数命名

```zig
// ✅ 正确 - 使用 T 表示泛型类型
pub fn SelectQuery(comptime T: type) type {
    return struct {
        const Self = @This();
        // ...
    };
}

// ✅ 正确 - 使用 DBType 等明确名称
pub fn newSelect(comptime DBType: type, allocator: Allocator) !SelectQuery(DBType) {
    // ...
}
```

### 2. Comptime 错误提示

**规则**：使用 `@compileError` 提供清晰的编译时错误

```zig
pub fn zigToSQLType(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .Int => |info| if (info.bits == 64) "BIGINT" else "INTEGER",
        .Bool => "BOOLEAN",
        .Pointer => |info| if (info.child == u8) "TEXT" else @compileError(
            "不支持的指针类型: " ++ @typeName(T) ++ "\n" ++
            "仅支持 []const u8 (TEXT) 类型"
        ),
        else => @compileError("不支持的 Zig 类型: " ++ @typeName(T)),
    };
}
```

### 3. 类型反射模式

```zig
pub fn getTableName(comptime T: type) []const u8 {
    // 优先使用自定义表名
    if (@hasDecl(T, "table_name")) {
        return T.table_name;
    }

    // 否则使用类型名的小写形式
    const type_name = @typeName(T);
    // 提取最后一个点之后的部分
    return extractTypeName(type_name);
}
```

---

## 测试规范

### 1. 测试文件组织

```
src/
├── query/
│   ├── query.zig           # 实现
│   └── query_test.zig      # 测试
└── core/
    ├── db.zig
    └── db_test.zig
```

### 2. 测试命名

```zig
// ✅ 正确 - 使用描述性测试名
test "SelectQuery: basic where clause" {
    const allocator = std.testing.allocator;
    // ...
}

test "InsertQuery: batch insert with RETURNING" {
    // ...
}

// ❌ 错误 - 测试名不够描述性
test "test1" { // ❌
    // ...
}
```

### 3. 内存泄漏检测

**强制要求**：所有测试必须使用 `std.testing.allocator`

```zig
test "ArrayList memory management" {
    const allocator = std.testing.allocator; // ✅ 使用 testing allocator

    var users: std.ArrayList(User) = .{};
    defer users.deinit(allocator);

    try users.append(allocator, User{ .id = 1, .name = "Alice" });

    try std.testing.expectEqual(1, users.items.len);
}
// 测试结束后自动检测内存泄漏
```

### 4. 测试覆盖率目标

- **单元测试**: 覆盖率 ≥ 80%
- **关键路径**: 覆盖率 ≥ 95% (查询构建、类型映射、内存管理)
- **边界条件**: 必须测试空输入、最大值、NULL 处理

---

## 关键禁止规则

### ❌ 绝对禁止

1. **禁止硬编码 SQL**
   ```zig
   // ❌ 错误
   const sql = "SELECT * FROM users WHERE id = " ++ user_id;

   // ✅ 正确 - 使用参数绑定
   const sql = "SELECT * FROM users WHERE id = $1";
   const result = try db.query(sql, .{user_id});
   ```

2. **禁止全局可变状态**
   ```zig
   // ❌ 错误
   var global_db: ?*DB = null;

   // ✅ 正确 - 通过参数传递
   pub fn processUser(db: *DB, user_id: i64) !void {
       // ...
   }
   ```

3. **禁止忽略错误**
   ```zig
   // ❌ 错误
   _ = db.execute(sql);  // 忽略错误

   // ✅ 正确
   try db.execute(sql);
   ```

4. **禁止使用 `std.debug.print` 在非 Debug 代码中**
   ```zig
   // ❌ 错误 - 生产代码中使用 debug print
   pub fn exec(self: *Query) !void {
       std.debug.print("Executing: {s}\n", .{self.sql}); // ❌
   }

   // ✅ 正确 - 通过钩子系统或用户提供的 logger
   if (self.db.query_hook) |hook| {
       try hook.beforeQuery(self.sql, self.args);
   }
   ```

### ⚠️ 需谨慎使用

1. **Unsafe 操作**
   - `@ptrCast`, `@intFromPtr` 等必须有明确注释
   - 必须有对应的安全检查
   - 仅在绝对必要时使用（pg.zig 已封装底层 unsafe 操作）

---

## 性能优化指南

### 1. 优先使用 Comptime

```zig
// ✅ 好 - 编译时计算
pub fn createTableSQL(comptime T: type) []const u8 {
    comptime {
        var sql = "CREATE TABLE " ++ getTableName(T) ++ " (";
        // ... 编译时构建 SQL
        return sql;
    }
}
```

### 2. Arena Allocator 用于临时分配

```zig
pub fn buildQuery(self: *SelectQuery) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    const arena_allocator = arena.allocator();

    // 使用 arena 进行临时分配，统一释放
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(arena_allocator);

    // ... 构建 SQL

    // 最终结果使用主 allocator
    return self.allocator.dupe(u8, buf.items);
}
```

### 3. 预分配容量

```zig
// ✅ 好 - 预分配减少重新分配
var columns: std.ArrayList([]const u8) = .{};
try columns.ensureTotalCapacity(allocator, 10); // 预分配 10 个元素
```

---

## 代码审查检查清单

### 提交前自检

- [ ] 运行 `zig fmt src/` 格式化代码
- [ ] 运行 `zig build test` 通过所有测试
- [ ] 运行 `zig build` 无警告编译
- [ ] 所有公共 API 包含文档注释
- [ ] 新增测试覆盖新功能
- [ ] 内存泄漏检测通过（测试 allocator）
- [ ] 错误处理完整（无 `catch` 吞没错误）
- [ ] 无硬编码 SQL 字符串拼接

---

## 变更记录

| Date | Version | Change | Author |
|------|---------|--------|--------|
| 2025-10-19 | v1.0 | 初始编码标准定义 | Winston (Architect) |
| 2025-10-19 | v1.1 | 移除 C FFI 相关规则(改用 pg.zig 纯 Zig 驱动) | Winston (Architect) |

---

## 参考资源

- **Zig Style Guide**: https://ziglang.org/documentation/0.15.2/#Style-Guide
- **Zig Standard Library**: https://ziglang.org/documentation/0.15.2/std/
- **项目 PRD**: docs/prd.md
- **技术栈文档**: docs/tech-stack.md
