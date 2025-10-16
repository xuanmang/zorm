# Story 017: 实现编译时类型反射

## Status
Draft

## Story
**As a** ZORM 开发者,
**I want** 编译时类型反射工具,
**so that** 能够在编译时提取结构体的类型信息,实现零运行时开销

## Acceptance Criteria
1. 实现 getTableName(comptime T) 提取表名
2. 实现 getFieldNames(comptime T) 提取字段名
3. 实现 getFieldTypes(comptime T) 提取字段类型
4. 实现 getFieldCount(comptime T) 获取字段数量
5. 所有函数都是 comptime,结果在编译时计算
6. 编写测试验证编译时反射

## Tasks / Subtasks
- [ ] 创建 src/mapper/type_info.zig
- [ ] 实现类型反射函数
- [ ] 编写测试

## Dev Notes
参考 [docs/architecture.md#类型反射](architecture.md) (行 657-683)

### 关键实现
```zig
fn getTableName(comptime T: type) []const u8 {
    if (@hasDecl(T, "table_name")) {
        return T.table_name;
    }
    return @typeName(T);
}

fn getFieldNames(comptime T: type) []const []const u8 {
    const fields = @typeInfo(T).Struct.fields;
    comptime var names: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |field, i| {
        names[i] = field.name;
    }
    return &names;
}
```

## Change Log
| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2025-01-16 | 1.0 | 创建 Story | Bob |
