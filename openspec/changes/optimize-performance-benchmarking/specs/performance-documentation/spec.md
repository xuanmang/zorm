# Spec: performance-documentation

定义性能目标，文档化基准测试结果，为用户提供性能数据支撑。

## ADDED Requirements

### Requirement: 明确定义性能目标

MUST 在文档中明确列出所有性能目标和验收标准。

#### Scenario: 性能目标文档

```markdown
# ZORM 性能目标

## 查询构建性能

| 操作类型 | 性能目标 | 验证方法 |
|---------|---------|---------|
| 简单 SELECT 查询构建 | < 1ms | benchmark: `bench_simple_select` |
| 复杂 SELECT 查询构建（5个条件+JOIN） | < 1ms | benchmark: `bench_complex_select` |
| 批量 INSERT（1000行） | < 5ms | benchmark: `bench_batch_insert_1k` |

## 运行时开销

| 对比项 | 性能目标 | 验证方法 |
|-------|---------|---------|
| ZORM vs 原生 SQL | < 5% 开销 | benchmark: `bench_zorm_vs_native` |
| Arena 分配器 vs 逐个分配 | > 20% 提升 | benchmark: `bench_arena_vs_individual` |
| 零拷贝 vs 拷贝模式 | > 30% 提升 | benchmark: `bench_zerocopy_vs_copy` |

## 内存效率

| 指标 | 性能目标 | 验证方法 |
|-----|---------|---------|
| SQL 缓冲区预分配 | 减少 > 30% 分配次数 | benchmark: `bench_buffer_prealloc` |
| Comptime 优化 | > 40% 性能提升 | benchmark: `bench_comptime_vs_runtime` |
```

### Requirement: 基准测试结果自动生成报告

基准测试框架 MUST 基准测试框架自动生成格式化的性能报告。

#### Scenario: 自动生成性能报告

```zig
// 基准测试运行后自动生成报告
const report = try bench.generateReport(.{
    .format = .markdown,
    .include_charts = true,
    .output_path = "benchmarks/results/latest.md",
});

// 生成的报告示例
```

```markdown
# ZORM 性能基准测试报告

**生成时间**: 2025-10-26 14:30:00
**Zig 版本**: 0.15.2
**优化级别**: ReleaseFast

## 查询构建性能

### 简单 SELECT 查询

| 指标 | 值 |
|-----|---|
| 迭代次数 | 10,000 |
| 平均耗时 | 4.2μs |
| 标准差 | 0.8μs |
| P50 | 4.0μs |
| P95 | 5.5μs |
| P99 | 6.8μs |
| **目标** | < 1ms |
| **结果** | ✅ PASS |

### 批量 INSERT（1000行）

| 指标 | 值 |
|-----|---|
| 批量大小 | 1,000 行 |
| 构建耗时 | 3.8ms |
| SQL 长度 | 125,678 字节 |
| **目标** | < 5ms |
| **结果** | ✅ PASS |

## 性能对比

### ZORM vs 原生 SQL

| 操作 | ZORM | 原生 SQL | 开销 | 目标 | 结果 |
|-----|------|---------|-----|------|------|
| SELECT 查询 | 104μs | 101μs | 3.0% | < 5% | ✅ PASS |
| INSERT 单行 | 52μs | 50μs | 4.0% | < 5% | ✅ PASS |
| UPDATE 单行 | 48μs | 47μs | 2.1% | < 5% | ✅ PASS |

### 内存分配优化

| 优化项 | 优化前 | 优化后 | 提升 | 目标 | 结果 |
|-------|-------|-------|-----|------|------|
| Arena 分配器 | 45μs | 36μs | 20.0% | > 20% | ✅ PASS |
| 缓冲区预分配 | 15次分配 | 10次分配 | 33.3% | > 30% | ✅ PASS |
| 零拷贝扫描 | 89μs | 62μs | 30.3% | > 30% | ✅ PASS |
| Comptime 优化 | 67μs | 40μs | 40.3% | > 40% | ✅ PASS |

## 结论

**所有基准测试通过** ✅

ZORM 成功达到所有性能目标：
- 查询构建开销 < 1ms ✓
- 运行时开销 < 5% ✓
- 内存分配优化 > 20% ✓
```

### Requirement: 性能最佳实践指南

MUST 提供性能最佳实践文档，指导用户优化应用性能。

#### Scenario: 性能最佳实践文档

```markdown
# ZORM 性能优化最佳实践

## 1. 使用 QueryContext 管理临时内存

**推荐**:
```zig
var ctx = QueryContext.init(db.allocator);
defer ctx.deinit();

var query = try db.newSelect(User);
defer query.deinit();

const sql = try query.build(ctx.allocator());
```

**避免**:
```zig
var query = try db.newSelect(User);
defer query.deinit();

const sql = try query.buildSQL();
defer db.allocator.free(sql); // 逐个释放，性能较差
```

## 2. 循环中复用 QueryContext

**推荐**:
```zig
var ctx = QueryContext.init(db.allocator);
defer ctx.deinit();

for (ids) |id| {
    var query = try db.newSelect(User);
    defer query.deinit();

    _ = try query.where("id = ?", .{id}).build(ctx.allocator());
    ctx.reset(); // 复用容量
}
```

## 3. 选择合适的扫描模式

- **短期使用**: 使用 `scan()` 零拷贝模式
- **长期保存**: 使用 `scanCopy()` 拷贝模式

## 4. 批量操作优于循环单次操作

**推荐**:
```zig
try db.newInsert(User).values(&users).exec(); // 单次批量插入
```

**避免**:
```zig
for (users) |user| {
    try db.newInsert(User).value(user).exec(); // 多次单行插入
}
```
```

### Requirement: CI 集成性能监控

MUST 在 CI 中运行轻量级基准测试，监控性能回归。

#### Scenario: GitHub Actions 性能监控

```yaml
# .github/workflows/benchmark.yml
name: Performance Benchmarks

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.2

      - name: Run benchmarks
        run: zig build bench --summary all

      - name: Check performance targets
        run: |
          # 解析基准测试结果
          # 如果有性能回归，CI 失败
          python scripts/check_benchmark_results.py

      - name: Upload results
        uses: actions/upload-artifact@v3
        with:
          name: benchmark-results
          path: benchmarks/results/
```

## MODIFIED Requirements

### Requirement: 更新 README 包含性能数据

MUST 在项目 README 中添加性能亮点和基准测试结果摘要。

#### Scenario: README 性能章节

```markdown
# ZORM

## Performance

ZORM 提供接近原生 SQL 的性能，开销不超过 5%：

| 操作 | ZORM | 原生 SQL | 开销 |
|-----|------|---------|-----|
| SELECT 查询 | 104μs | 101μs | 3.0% |
| INSERT 单行 | 52μs | 50μs | 4.0% |
| 批量 INSERT（1000行） | 3.8ms | 3.7ms | 2.7% |

查询构建性能：
- 简单查询: 4.2μs
- 复杂查询: 25.7μs
- 批量插入（1000行）: 3.8ms

详细基准测试结果请参阅 [benchmarks/README.md](benchmarks/README.md)。
```
