# Story 019: 实现结果扫描器

## Status
Ready for Review

## Story
**As a** ZORM 开发者,
**I want** 结果扫描器,
**so that** 能够高效扫描查询结果集

## Acceptance Criteria
1. ✅ 实现结果集迭代逻辑
2. ✅ 集成 field_mapper 进行类型映射
3. ✅ 支持流式处理大结果集
4. ✅ 编写测试

## Tasks / Subtasks
- [x] 创建 src/mapper/result_scanner.zig
- [x] 实现扫描逻辑
- [x] 编写测试

## Dev Notes

### 系统架构文档
- **完整架构文档**: @docs/architecture.md

## Dev Agent Record

### 实现概述
成功实现了完整的结果扫描器系统,提供流式处理查询结果集的高级接口,与 field_mapper 无缝集成实现自动类型映射。

### 核心设计

#### 设计演进
**初始设计**: 泛型 ResultScanner(T) 结构体包装 Rows
```zig
pub fn ResultScanner(comptime T: type) type {
    return struct {
        rows: *Rows,
        allocator: Allocator,
        // ...
    };
}
```

**最终设计**: 简化为函数式 API,使用 duck typing
```zig
pub fn scanAll(comptime T: type, rows: anytype, allocator: Allocator, dest: anytype) !void
pub fn scanOne(comptime T: type, rows: anytype, allocator: Allocator) !T
```

**设计变更原因**:
- 避免 field_mapper.Row 和 driver.connection.Row 类型不兼容问题
- 使用 `anytype` 参数支持任何实现 `next()` 方法的迭代器
- 更简单的 API,零运行时开销
- 更好的可组合性

#### 核心函数

**1. scanAll() - 批量扫描**
```zig
pub fn scanAll(comptime T: type, rows: anytype, allocator: Allocator, dest: anytype) !void {
    while (try rows.next()) |row_const| {
        var row = row_const;
        const item = try field_mapper.scanRow(T, &row, allocator);
        try dest.append(allocator, item);
    }
}
```
- 流式迭代结果集
- 自动类型映射(通过 field_mapper.scanRow)
- 支持任意目标容器(ArrayList, 自定义容器等)

**2. scanOne() - 单行扫描**
```zig
pub fn scanOne(comptime T: type, rows: anytype, allocator: Allocator) !T {
    const first_row = try rows.next();
    if (first_row == null) {
        return error.NoRows;
    }
    var first = first_row.?;
    const result = try field_mapper.scanRow(T, &first, allocator);

    const second = try rows.next();
    if (second != null) {
        return error.TooManyRows;
    }
    return result;
}
```
- 确保结果集只有一行
- 提供清晰的错误信息(NoRows, TooManyRows)

**3. ScanOptions**
```zig
pub const ScanOptions = struct {
    copy_strings: bool = false,
};
```
- 为未来扩展预留配置选项
- 当前版本暂未使用,保持 API 前瞻性

### 技术挑战与解决方案

#### 挑战 1: Zig 0.15.2 ArrayList API 变化
**问题**: `std.ArrayList(T)` 返回 unmanaged 版本,没有 `init()` 方法
```zig
// ❌ 错误: Zig 0.15.2 中不存在
var list = std.ArrayList(T).init(allocator);

// ✅ 正确: 使用结构体字面量
var list: std.ArrayList(T) = .{};
defer list.deinit(allocator);  // unmanaged 版本需要传 allocator
```

**解决方案**:
- 使用 `std.ArrayList(T) = .{}` 初始化(结构体默认值)
- `deinit(allocator)` 传递 allocator
- `append(allocator, item)` 传递 allocator

#### 挑战 2: const vs mutable 指针
**问题**: `rows.next()` 返回 `?Row` (const),但 `scanRow()` 需要 `*Row`
```zig
// ❌ 错误: 类型不匹配
while (try rows.next()) |*row| {
    const item = try field_mapper.scanRow(T, row, allocator);  // row 是 *const Row
}

// ✅ 正确: 创建可变副本
while (try rows.next()) |row_const| {
    var row = row_const;  // 创建可变副本
    const item = try field_mapper.scanRow(T, &row, allocator);
}
```

**解决方案**: 在 scanAll 中创建 Row 的可变副本

#### 挑战 3: 类型系统复杂性 - Row 接口不兼容
**问题**: 两个不同的 Row 类型定义
- `field_mapper.Row`: VTable 使用 `anyerror!T`
- `driver.connection.Row`: VTable 使用特定 `Error!T`

**解决方案**:
- result_scanner 使用 `field_mapper.Row`
- 通过 `anytype` 参数避免强类型约束
- 依赖 duck typing 而非显式类型匹配

### 测试实现

#### MockRow 实现
```zig
const MockRow = struct {
    values: []const ?[]const u8,

    const vtable_impl: Row.RowVTable = .{
        .isNull = isNull,
        .getInt = getInt,
        .getFloat = getFloat,
        .getBool = getBool,
        .getString = getString,
        .getBytes = getBytes,
    };
};
```

#### MockRows 迭代器
```zig
const MockRows = struct {
    rows_data: []const []const ?[]const u8,
    current_index: usize,

    fn next(self: *MockRows) !?Row {
        if (self.current_index >= self.rows_data.len) {
            return null;
        }
        const row_values = self.rows_data[self.current_index];
        self.current_index += 1;

        var mock_row = MockRow{ .values = row_values };
        return Row{
            .driver_row = @ptrCast(&mock_row),
            .vtable = &MockRow.vtable_impl,
        };
    }
};
```

#### 测试覆盖
1. **scanAll: 批量扫描多行** - 验证多行数据正确映射
2. **scanOne: 单行扫描成功** - 验证单行场景
3. **scanOne: 无行错误** - 验证空结果集处理
4. **scanOne: 多行错误** - 验证多行异常检测
5. **scanAll: 空结果集** - 验证空结果集返回空列表

### 性能特性

- **零运行时反射**: 所有类型信息在编译时确定
- **流式处理**: 逐行迭代,内存占用可控
- **零额外抽象开销**: `anytype` 在编译时单态化
- **内存高效**: 支持字符串借用(通过 field_mapper)

### 与 zorm.zig 集成

```zig
// 导出 Mapper 模块
pub const mapper = struct {
    pub const type_info = @import("mapper/type_info.zig");
    pub const field_mapper = @import("mapper/field_mapper.zig");
    pub const result_scanner = @import("mapper/result_scanner.zig");
};

// 导出函数和类型
pub const ScanOptions = mapper.result_scanner.ScanOptions;
pub const scanAll = mapper.result_scanner.scanAll;
pub const scanOne = mapper.result_scanner.scanOne;
pub const scanRow = mapper.field_mapper.scanRow;
```

### 文件清单
- ✅ `src/mapper/result_scanner.zig` (300 行)
  - ScanOptions 定义
  - scanAll() 函数
  - scanOne() 函数
  - MockRow/MockRows 测试实现
  - 5 个完整测试用例

### 后续集成点
- 将在各个查询构建器中集成 scanAll/scanOne
- 驱动层的 Rows 实现需要提供 next() 方法
- 未来可扩展 ScanOptions 支持更多配置

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
| 2025-01-17 | 2.0 | 完成实现和测试 | Dev Agent |
