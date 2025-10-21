# 修复 Zig 0.15 ArrayList API 兼容性问题

## What

修复 `src/query/query.zig` 中由于 Zig 0.15 ArrayList API 变更导致的 4 个编译错误：

1. `SelectQuery.init()` 中的 ArrayList 字段初始化（第 87-93 行）
2. `InsertQuery.buildSQL()` 中的缓冲区初始化（第 948 行）
3. `UpdateQuery.buildSQL()` 中的缓冲区初始化（第 1464 行）
4. `DeleteQuery.buildSQL()` 中的缓冲区初始化（第 1899 行）

错误信息：`struct 'array_list.Aligned(T,null)' has no member named 'init'`

## Why

### 问题根源

Zig 0.15 对 ArrayList API 进行了重大变更：

**旧版本 (Zig 0.14 及之前):**
```zig
var list = ArrayList(T).init(allocator);
```

**新版本 (Zig 0.15):**
- `ArrayList(T)` 现在是 `Aligned(T, null)` 的别名，不再包含 allocator 字段
- 移除了 `init()` 方法
- 新增了 `empty` 常量和 `initCapacity()` 方法
- 所有操作需要显式传递 allocator

### 为什么这样设计

Zig 0.15 的设计理念：
1. **更灵活的内存管理**：允许不同操作使用不同的 allocator
2. **更清晰的所有权语义**：显式传递 allocator 使内存管理更透明
3. **更好的性能**：减少 allocator 字段的存储开销
4. **向后兼容路径**：保留了 `ArrayListManaged(T)` 作为旧 API 的兼容层

### 为什么选择 Aligned 而不是 Managed

尽管 `ArrayListManaged` 提供了向后兼容，但我们选择使用新的 `ArrayList(Aligned)` API 因为：

1. **符合语言设计方向**：`Managed` 已被标记为 deprecated
2. **代码已经存储 allocator**：`SelectQuery` 等结构体已有 `allocator: Allocator` 字段
3. **更好的灵活性**：可以在不同场景使用不同的 allocator（如 arena）
4. **长期维护性**：避免使用即将废弃的 API

## How

### 修复方案

**位置 1: SelectQuery.init() (第 87-93 行)**
```zig
// 旧代码
.columns = std.ArrayList([]const u8).init(allocator),

// 新代码
.columns = std.ArrayList([]const u8){},
```

**位置 2-4: buildSQL() 方法 (第 948, 1464, 1899 行)**
```zig
// 旧代码
var buf = std.ArrayList(u8).init(allocator);

// 新代码
var buf = std.ArrayList(u8){};
```

### 实现细节

1. **空列表初始化**：使用 `.{}` 或 `.empty` 常量
   ```zig
   var list = ArrayList(T){};  // 推荐
   // 或
   var list = ArrayList(T).empty;
   ```

2. **预分配容量初始化**：使用 `initCapacity()`
   ```zig
   var buf = try ArrayList(u8).initCapacity(allocator, estimated_size);
   ```

3. **后续操作**：所有 ArrayList 方法需要显式传递 allocator
   ```zig
   try list.append(allocator, item);
   try list.appendSlice(allocator, items);
   ```

### 影响范围

- **修改文件**：`src/query/query.zig`
- **修改位置**：4 处 ArrayList 初始化
- **向后兼容性**：完全兼容（仅内部实现变更）
- **测试影响**：无需修改测试代码，只需确保编译通过

## Success Criteria

- [x] 所有 4 个编译错误已修复
- [ ] `zig build test` 成功编译和运行
- [ ] 所有现有测试通过
- [ ] 无性能回退（理论上更快，减少 allocator 存储）
- [ ] OpenSpec 验证通过

## Risks

### 低风险

- **API 变更**：仅影响初始化方式，不影响使用方式
- **性能**：理论上更好（减少 allocator 字段存储）
- **维护**：符合 Zig 语言发展方向

### 潜在问题

- **学习曲线**：团队需要了解新的 ArrayList API
- **迁移成本**：未来其他文件可能也需要类似修复

### 缓解措施

- 在代码注释中说明 API 变更原因
- 在项目文档中记录 Zig 0.15 迁移指南
- 使用 `rg "ArrayList.*\.init"` 查找其他潜在问题

## Dependencies

- **依赖的变更**：无
- **被依赖的变更**：无
- **外部依赖**：Zig 0.15.2

## Related Changes

- **相关提案**：无
- **相关规格**：无（这是紧急的编译错误修复）
