# Spec: benchmark-infrastructure

建立完整的性能基准测试基础设施，验证 ZORM 性能目标并提供持续性能监控能力。

## ADDED Requirements

### Requirement: 提供统一的基准测试框架

MUST 创建标准化的基准测试工具，简化性能测试编写和结果收集。

#### Scenario: 使用基准测试框架

```zig
const Benchmark = @import("benchmark").Benchmark;

test "benchmark query builder performance" {
    var bench = Benchmark.init(std.testing.allocator, .{
        .name = "SELECT query builder",
        .iterations = 10000,
        .warmup_iterations = 100,
    });
    defer bench.deinit();

    try bench.run(struct {
        fn benchmark(ctx: *Benchmark.Context) !void {
            var query = try db.newSelect(User);
            defer query.deinit();

            try query.where("age > ?", .{18});
            _ = try query.buildSQL();

            ctx.recordIteration();
        }
    }.benchmark);

    // 自动输出结果：平均时间、标准差、p50/p95/p99 等
    try bench.report();
}
```

#### Scenario: 对比基准测试

```zig
test "benchmark arena vs individual allocation" {
    var suite = BenchmarkSuite.init(std.testing.allocator);
    defer suite.deinit();

    // 添加第一个基准测试
    try suite.add("Arena allocator", struct {
        fn benchmark(ctx: *Benchmark.Context) !void {
            var arena_ctx = QueryContext.init(allocator);
            defer arena_ctx.deinit();
            // 测试代码...
            ctx.recordIteration();
        }
    }.benchmark);

    // 添加第二个基准测试
    try suite.add("Individual allocation", struct {
        fn benchmark(ctx: *Benchmark.Context) !void {
            // 测试代码...
            ctx.recordIteration();
        }
    }.benchmark);

    // 运行并对比结果
    try suite.runAndCompare();
}
```

### Requirement: 基准测试覆盖所有关键路径

MUST 确保基准测试覆盖查询构建、SQL 生成、结果扫描等关键性能路径。

#### Scenario: 查询构建性能基准测试

```zig
test "benchmark SELECT query building" {
    // 简单查询
    try benchmarkSimpleSelect();

    // 复杂查询（多个 WHERE、JOIN、ORDER BY）
    try benchmarkComplexSelect();

    // 批量插入
    try benchmarkBatchInsert();
}

fn benchmarkSimpleSelect() !void {
    var bench = Benchmark.init(allocator, .{
        .name = "Simple SELECT",
        .target_time_ns = 1_000_000, // 1ms 目标
    });
    defer bench.deinit();

    try bench.run(struct {
        fn benchmark(ctx: *Benchmark.Context) !void {
            var query = try db.newSelect(User);
            defer query.deinit();

            try query.where("id = ?", .{123});
            _ = try query.buildSQL();

            ctx.recordIteration();
        }
    }.benchmark);

    try bench.assertTargetMet(); // 验证是否达到目标
}
```

#### Scenario: 内存分配性能基准测试

```zig
test "benchmark memory allocation patterns" {
    var bench = Benchmark.init(allocator, .{
        .name = "Memory allocation",
        .track_allocations = true, // 追踪分配次数和大小
    });
    defer bench.deinit();

    try bench.run(struct {
        fn benchmark(ctx: *Benchmark.Context) !void {
            var arena_ctx = QueryContext.init(allocator);
            defer arena_ctx.deinit();

            for (0..100) |i| {
                var query = try db.newSelect(User);
                defer query.deinit();

                try query.where("id = ?", .{i});
                _ = try query.build(arena_ctx.allocator());

                arena_ctx.reset();
            }

            ctx.recordIteration();
        }
    }.benchmark);

    // 报告包含分配次数和峰值内存使用
    try bench.report();
}
```

### Requirement: 端到端性能基准测试

MUST 提供真实数据库连接的端到端性能测试，验证 ZORM 相比原生 SQL 的开销。

#### Scenario: ZORM vs 原生 SQL 性能对比

```zig
test "benchmark ZORM vs native SQL" {
    const pg_conn = try setupTestDatabase();
    defer pg_conn.deinit();

    var suite = BenchmarkSuite.init(allocator);
    defer suite.deinit();

    // ZORM 查询
    try suite.add("ZORM SELECT", struct {
        fn benchmark(ctx: *Benchmark.Context) !void {
            var query = try db.newSelect(User);
            defer query.deinit();

            var users: std.ArrayList(User) = .{};
            defer users.deinit(allocator);

            try query.where("age > ?", .{18}).scan(&users);

            ctx.recordIteration();
        }
    }.benchmark);

    // 原生 SQL
    try suite.add("Native SQL", struct {
        fn benchmark(ctx: *Benchmark.Context) !void {
            const sql = "SELECT * FROM users WHERE age > $1";
            const result = try pg_conn.query(sql, .{18});
            defer result.deinit();

            // 手动解析结果...

            ctx.recordIteration();
        }
    }.benchmark);

    // 验证 ZORM 开销不超过 5%
    const comparison = try suite.runAndCompare();
    const overhead = (comparison.zorm_time - comparison.native_time) / comparison.native_time;
    try std.testing.expect(overhead <= 0.05);
}
```

### Requirement: 性能回归检测

MUST 提供基线对比功能，检测性能回归。

#### Scenario: 基线对比

```zig
test "detect performance regression" {
    // 加载历史基线数据
    const baseline = try BenchmarkBaseline.load("benchmarks/results/baseline.json");
    defer baseline.deinit();

    // 运行当前基准测试
    var bench = Benchmark.init(allocator, .{
        .name = "SELECT query builder",
    });
    defer bench.deinit();

    try bench.run(selectQueryBenchmark);

    // 对比基线，检测回归
    const comparison = try bench.compareWithBaseline(baseline);

    // 如果性能下降超过 10%，测试失败
    if (comparison.regression_percent > 10.0) {
        std.debug.print("Performance regression detected: {d:.2}%\n", .{comparison.regression_percent});
        return error.PerformanceRegression;
    }
}
```

## MODIFIED Requirements

### Requirement: 集成到构建系统

MUST 添加 `zig build bench` 命令运行所有基准测试。

#### Scenario: 构建系统集成

```zig
// build.zig
pub fn build(b: *std.Build) void {
    // ... 现有构建配置 ...

    // 添加基准测试步骤
    const bench_step = b.step("bench", "Run performance benchmarks");

    const bench = b.addTest(.{
        .root_source_file = b.path("benchmarks/all_benchmarks.zig"),
        .target = target,
        .optimize = .ReleaseFast, // 基准测试使用 ReleaseFast
    });

    const run_bench = b.addRunArtifact(bench);
    bench_step.dependOn(&run_bench.step);
}
```

```bash
# 用户运行基准测试
$ zig build bench

# 输出示例
Running benchmarks...
✓ SELECT query builder: 4.2μs (target: <1ms) PASS
✓ Batch INSERT (1000 rows): 3.8ms (target: <5ms) PASS
✓ Arena allocator: 20% faster than individual allocation
✓ ZORM overhead: 3.2% (target: <5%) PASS

All benchmarks passed!
```
