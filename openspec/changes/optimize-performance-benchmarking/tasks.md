# Tasks: optimize-performance-benchmarking

实现 PRD Story 4.8 的性能优化和基准测试功能。任务按依赖关系排序，可并行的任务会明确标注。

## Phase 1: Arena 分配器集成和 SQL 缓冲区优化 (2-3 days)

### Task 1.1: 重构查询构建器支持可选 allocator 参数

**依赖**: 无
**可并行**: 否

修改所有查询构建器（SELECT、INSERT、UPDATE、DELETE）的 `buildSQL()` 方法，接受可选的 allocator 参数：

```zig
pub fn buildSQL(self: *Self, allocator: ?Allocator) ![]const u8 {
    const alloc = allocator orelse self.allocator;
    // 使用 alloc 构建 SQL...
}

// 添加便捷方法
pub fn build(self: *Self, allocator: Allocator) ![]const u8 {
    return self.buildSQL(allocator);
}
```

**验证**:
- [x] 所有现有测试通过（向后兼容）
- [x] 新增测试验证使用 QueryContext allocator
- [x] API 文档更新

---

### Task 1.2: 实现 SQL 缓冲区容量预估策略

**依赖**: Task 1.1
**可并行**: 否

为每种查询类型实现容量预估函数：

```zig
// src/query/query.zig
fn estimateSelectSQLSize(self: *SelectQuery) usize {
    var size: usize = 100; // SELECT * FROM table_name
    size += self.table_name.len;
    size += self.estimateWhereClauseSize();
    size += self.estimateJoinSize();
    size += self.estimateOrderBySize();
    size += 50; // LIMIT/OFFSET
    return size;
}
```

**验证**:
- [x] 预估准确度测试（实际大小 vs 预估大小误差 < 20%）
- [x] 不同复杂度查询的预估测试
- [x] 性能测试：减少 resize 次数

---

### Task 1.3: 重构 SQL 构建逻辑使用预分配缓冲区

**依赖**: Task 1.2
**可并行**: 否

重构所有 SQL 构建逻辑，使用 ArrayList 和容量预估：

```zig
pub fn buildSQL(self: *Self, allocator: ?Allocator) ![]const u8 {
    const alloc = allocator orelse self.allocator;

    // 预估容量
    const estimated_size = self.estimateSelectSQLSize();

    // 预分配缓冲区
    var buffer = try std.ArrayList(u8).initCapacity(alloc, estimated_size);
    errdefer buffer.deinit();

    // 构建 SQL
    try self.buildSelectClause(&buffer);
    try self.buildWhereClause(&buffer);
    try self.buildOrderByClause(&buffer);
    // ...

    return buffer.toOwnedSlice();
}
```

**验证**:
- [x] 所有查询构建器测试通过
- [x] 内存泄漏检测（std.testing.allocator）
- [x] SQL 生成正确性验证

---

### Task 1.4: 添加缓冲区预分配基准测试

**依赖**: Task 1.3
**可并行**: 是（与 Task 2.1 并行）

创建基准测试验证预分配效果：

```zig
// benchmarks/buffer_preallocation_bench.zig
test "SQL buffer preallocation vs dynamic growth" {
    // 对比预分配和动态扩展的性能
    // 验证减少至少 30% 的分配次数
}
```

**验证**:
- [x] 基准测试通过（减少 > 30% 分配次数）
- [x] 性能数据记录到 benchmarks/results/

---

## Phase 2: 结果扫描优化和 Comptime 优化 (2-3 days)

### Task 2.1: 实现零拷贝结果扫描

**依赖**: 无
**可并行**: 是（与 Task 1.4 并行）

实现 `scan()` 方法直接引用 PostgreSQL 缓冲区：

```zig
pub fn scan(self: *Self, dest: *std.ArrayList(T)) !void {
    // 直接引用查询结果缓冲区，不拷贝字符串
    // 注意：数据生命周期绑定到查询对象
}
```

**验证**:
- [ ] 零拷贝扫描功能测试
- [ ] 生命周期安全测试
- [ ] API 文档明确说明所有权规则

---

### Task 2.2: 实现 scanCopy() 深拷贝方法

**依赖**: Task 2.1
**可并行**: 否

实现显式拷贝方法用于长期保存数据：

```zig
pub fn scanCopy(self: *Self, dest: *std.ArrayList(T), allocator: Allocator) !void {
    // 深拷贝所有字符串字段
    // 用户拥有数据所有权
}
```

**验证**:
- [ ] 深拷贝功能测试
- [ ] 内存所有权测试
- [ ] 对比 scan() 和 scanCopy() 性能

---

### Task 2.3: 添加零拷贝性能基准测试

**依赖**: Task 2.2
**可并行**: 是（与 Task 2.4 并行）

创建基准测试验证零拷贝性能提升：

```zig
// benchmarks/zero_copy_bench.zig
test "zero-copy vs copy scanning performance" {
    // 验证零拷贝至少快 30%
}
```

**验证**:
- [ ] 基准测试通过（> 30% 性能提升）
- [ ] 大结果集测试（10,000 行）

---

### Task 2.4: 实现 Comptime SQL 列名生成

**依赖**: 无
**可并行**: 是（与 Task 2.3 并行）

实现编译时列名列表生成：

```zig
// src/reflect/comptime.zig
pub fn generateColumnList(comptime T: type) []const u8 {
    const fields = @typeInfo(T).Struct.fields;
    comptime var result: []const u8 = "";
    inline for (fields, 0..) |field, i| {
        if (i > 0) result = result ++ ", ";
        result = result ++ field.name;
    }
    return result;
}
```

**验证**:
- [x] Comptime 生成测试
- [x] 不同结构体类型测试
- [x] 编译时错误处理测试

---

### Task 2.5: 实现 Comptime SQL 模板生成

**依赖**: Task 2.4
**可并行**: 否

实现常见查询的编译时模板：

```zig
pub fn generateSelectTemplate(comptime T: type) []const u8 {
    const table_name = getTableName(T);
    const column_list = generateColumnList(T);
    return comptime std.fmt.comptimePrint(
        "SELECT {s} FROM {s}",
        .{ column_list, table_name }
    );
}
```

**验证**:
- [x] 模板生成测试
- [x] 集成到查询构建器
- [x] 性能对比测试

---

### Task 2.6: 添加 Comptime 优化基准测试

**依赖**: Task 2.5
**可并行**: 是（与 Task 3.1 并行）

创建基准测试验证 comptime 性能提升：

```zig
// benchmarks/comptime_bench.zig
test "comptime vs runtime reflection" {
    // 验证 comptime 至少快 40%
}
```

**验证**:
- [x] 基准测试通过（> 40% 性能提升）
- [x] 编译时间影响评估（< 10% 增加）

---

## Phase 3: 基准测试框架和性能验证 (2-3 days)

### Task 3.1: 创建统一基准测试框架

**依赖**: 无
**可并行**: 是（与 Task 2.6 并行）

实现标准化的基准测试工具：

```zig
// benchmarks/framework/benchmark.zig
pub const Benchmark = struct {
    allocator: Allocator,
    name: []const u8,
    iterations: usize,
    warmup_iterations: usize,

    pub fn init(allocator: Allocator, options: BenchmarkOptions) Benchmark { }
    pub fn run(self: *Benchmark, benchmark_fn: anytype) !void { }
    pub fn report(self: *Benchmark) !void { }
    pub fn assertTargetMet(self: *Benchmark) !void { }
};
```

**验证**:
- [ ] 框架功能测试
- [ ] 统计分析测试（平均值、标准差、百分位数）
- [ ] 报告生成测试

---

### Task 3.2: 实现查询构建性能基准测试套件

**依赖**: Task 3.1
**可并行**: 否

创建完整的查询构建性能测试：

```zig
// benchmarks/query_builder_bench.zig
test "benchmark simple SELECT" { }
test "benchmark complex SELECT with JOINs" { }
test "benchmark batch INSERT" { }
test "benchmark UPDATE with WHERE" { }
test "benchmark DELETE with WHERE" { }
```

**验证**:
- [ ] 所有基准测试通过性能目标
- [ ] 结果保存到 benchmarks/results/

---

### Task 3.3: 实现端到端性能基准测试

**依赖**: Task 3.2
**可并行**: 否

创建真实数据库的端到端测试：

```zig
// benchmarks/e2e_bench.zig
test "ZORM vs native SQL overhead" {
    // 验证开销 < 5%
}
```

**验证**:
- [ ] 端到端测试通过（开销 < 5%）
- [ ] 真实 PostgreSQL 连接测试
- [ ] 多种查询类型对比

---

### Task 3.4: 实现性能回归检测

**依赖**: Task 3.3
**可并行**: 是（与 Task 4.1 并行）

实现基线对比功能：

```zig
// benchmarks/framework/baseline.zig
pub const BenchmarkBaseline = struct {
    pub fn load(path: []const u8) !BenchmarkBaseline { }
    pub fn save(self: *BenchmarkBaseline, path: []const u8) !void { }
    pub fn compare(self: *BenchmarkBaseline, current: *Benchmark) !Comparison { }
};
```

**验证**:
- [ ] 基线加载/保存测试
- [ ] 回归检测测试
- [ ] CI 集成测试

---

### Task 3.5: 集成到构建系统

**依赖**: Task 3.4
**可并行**: 否

添加 `zig build bench` 命令：

```zig
// build.zig
const bench_step = b.step("bench", "Run performance benchmarks");
const bench = b.addTest(.{
    .root_source_file = b.path("benchmarks/all_benchmarks.zig"),
    .optimize = .ReleaseFast,
});
bench_step.dependOn(&b.addRunArtifact(bench).step);
```

**验证**:
- [ ] `zig build bench` 成功运行
- [ ] 所有基准测试通过
- [ ] 结果输出格式正确

---

## Phase 4: 性能文档化和最终调优 (1-2 days)

### Task 4.1: 创建性能目标文档

**依赖**: 无
**可并行**: 是（与 Task 3.4 并行）

编写完整的性能目标和验收标准文档：

```markdown
# docs/performance-targets.md
- 查询构建性能目标
- 运行时开销目标
- 内存效率目标
- 验证方法和基准测试清单
```

**验证**:
- [ ] 文档覆盖所有性能目标
- [ ] 每个目标有对应的基准测试
- [ ] 验证方法清晰明确

---

### Task 4.2: 实现自动化性能报告生成

**依赖**: Task 3.5, Task 4.1
**可并行**: 否

实现基准测试报告自动生成：

```zig
pub fn generateReport(self: *Benchmark, options: ReportOptions) !void {
    // 生成 Markdown 格式报告
    // 包含表格、图表、结论
}
```

**验证**:
- [ ] 报告生成功能测试
- [ ] 报告格式验证
- [ ] 保存到 benchmarks/results/latest.md

---

### Task 4.3: 更新 README 和项目文档

**依赖**: Task 4.2
**可并行**: 否

在 README 和文档中添加性能数据：

- README.md: 添加性能章节
- benchmarks/README.md: 更新基准测试说明
- docs/performance-best-practices.md: 性能最佳实践指南

**验证**:
- [ ] 所有性能数据准确
- [ ] 文档清晰易读
- [ ] 示例代码可运行

---

### Task 4.4: CI 集成性能监控

**依赖**: Task 4.3
**可并行**: 否

添加 GitHub Actions 性能监控：

```yaml
# .github/workflows/benchmark.yml
- name: Run benchmarks
  run: zig build bench
- name: Check performance regression
  run: python scripts/check_benchmark_results.py
```

**验证**:
- [ ] CI workflow 配置正确
- [ ] 性能回归检测工作
- [ ] 失败时 CI 报错

---

### Task 4.5: 最终性能验证和调优

**依赖**: All previous tasks
**可并行**: 否

运行完整的性能验证套件并进行最终调优：

1. 运行所有基准测试
2. 验证所有性能目标达成
3. 识别性能瓶颈并优化
4. 生成最终性能报告

**验证**:
- [ ] 所有 AC 验收标准通过
- [ ] 性能目标全部达成：
  - [ ] AC4.8.1: Arena 分配器集成
  - [ ] AC4.8.2: SQL 缓冲区预分配
  - [ ] AC4.8.3: 结果扫描优化
  - [ ] AC4.8.4: Comptime 优化
  - [ ] AC4.8.5: 基准测试套件完成
  - [ ] AC4.8.6: ZORM 开销 < 5%
  - [ ] AC4.8.7: 性能结果文档化
- [ ] 最终性能报告生成

---

## 依赖关系图

```
Phase 1 (Arena & Buffer):
Task 1.1 → Task 1.2 → Task 1.3 → Task 1.4
                                     ↓
Phase 2 (Scanning & Comptime):      ↓
Task 2.1 → Task 2.2 → Task 2.3 ← ← ┘
Task 2.4 → Task 2.5 → Task 2.6
                         ↓
Phase 3 (Benchmarks):    ↓
Task 3.1 → Task 3.2 → Task 3.3 → Task 3.4 → Task 3.5
                                     ↓
Phase 4 (Documentation):             ↓
Task 4.1 → Task 4.2 ← ← ← ← ← ← ← ← ┘
           ↓
Task 4.3 → Task 4.4 → Task 4.5
```

## 估算时间

- **Phase 1**: 2-3 days (Tasks 1.1-1.4)
- **Phase 2**: 2-3 days (Tasks 2.1-2.6, 部分并行)
- **Phase 3**: 2-3 days (Tasks 3.1-3.5)
- **Phase 4**: 1-2 days (Tasks 4.1-4.5)

**Total**: 7-11 days

## 验证清单

最终交付前验证：

- [ ] 所有任务测试通过
- [ ] 无内存泄漏（std.testing.allocator 验证）
- [ ] 所有基准测试达标
- [ ] 文档完整且准确
- [ ] CI 集成正常工作
- [ ] 代码审查通过
