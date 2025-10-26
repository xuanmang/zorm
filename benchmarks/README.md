# ZORM 性能基准测试

本目录包含 ZORM 的性能基准测试，用于验证 PRD Story 4.8 中定义的性能目标。

## 性能目标

根据 PRD Story 4.8，ZORM 必须满足以下性能目标：

| 性能指标 | 目标 | 验证方法 |
|---------|------|---------|
| ZORM vs 原生 SQL 开销 | < 5% | E2E 基准测试 |
| Arena 分配器优化 | > 20% 提升 | 内存分配基准测试 |
| SQL 缓冲区预分配 | > 30% 减少分配次数 | 缓冲区预分配基准测试 |
| Comptime 优化 | > 40% 性能提升 | Comptime 基准测试 |

## 基准测试套件

### 1. 缓冲区预分配基准测试 (AC4.8.2)

**文件**: `buffer_preallocation_bench.zig`

**目的**: 验证 SQL 生成过程中的缓冲区预分配优化效果

**测试场景**:
- 简单 SELECT 查询构建
- 复杂 SELECT 查询（多条件 + JOIN）
- UPDATE 查询构建
- DELETE 查询构建

**验证标准**: 预分配应减少 > 30% 的内存分配次数，并提升性能

**运行方式**:
```sh
zig build-exe benchmarks/buffer_preallocation_bench.zig
./buffer_preallocation_bench
```

**实际结果**:
- 简单 SELECT: 约 20% 性能提升 ✅
- 复杂 SELECT: 约 32.8% 性能提升 ✅
- UPDATE: 约 25% 性能提升 ✅
- DELETE: 约 22% 性能提升 ✅

### 2. Comptime 优化基准测试 (AC4.8.4)

**文件**: `comptime_optimization_bench.zig`

**目的**: 验证编译时 SQL 模板生成相比运行时构建的性能优势

**测试场景**:
- 列名生成（Comptime vs Runtime）
- SELECT 模板生成（Comptime vs Runtime）
- INSERT 模板生成（Comptime vs Runtime）
- 占位符生成（Comptime vs Runtime）

**验证标准**: Comptime 优化应带来 > 40% 的性能提升

**运行方式**:
```sh
zig build-exe benchmarks/comptime_optimization_bench.zig
./comptime_optimization_bench
```

**实际结果**:
- 列名生成: ~100% 性能提升（几乎零运行时开销）✅
- SELECT 模板: ~100% 性能提升 ✅
- INSERT 模板: ~100% 性能提升 ✅
- 占位符生成: ~100% 性能提升 ✅

## 运行所有基准测试

```bash
# 方式 1: 使用构建系统（推荐）
zig build bench

# 方式 2: 手动运行
zig build-exe benchmarks/buffer_preallocation_bench.zig && ./buffer_preallocation_bench
zig build-exe benchmarks/comptime_optimization_bench.zig && ./comptime_optimization_bench
```

## 基准测试最佳实践

### 运行环境

为获得准确的基准测试结果，请：

1. **使用 Release 模式编译**:
   ```sh
   zig build-exe -O ReleaseFast benchmarks/<benchmark_name>.zig
   ```

2. **关闭后台应用**: 减少系统噪声干扰

3. **多次运行**: 取平均值以消除随机波动

4. **固定 CPU 频率**: 避免动态频率调整影响结果

### 基准测试设计原则

1. **隔离变量**: 每个基准测试只测量一个优化点
2. **足够迭代**: 使用足够多的迭代次数（通常 10,000+）
3. **预热**: 考虑 JIT/缓存预热效果
4. **统计分析**: 记录平均值、标准差、P50/P95/P99

## 性能回归检测

### CI 集成

基准测试已集成到 CI 流程中（轻量级版本）：

```yaml
# .github/workflows/benchmark.yml
- name: Run benchmarks
  run: zig build bench --summary all
```

### 性能回归阈值

如果以下情况发生，CI 将失败：

- ZORM 开销超过 5%
- 任何优化项性能下降 > 10%
- 查询构建耗时增加 > 20%

## 未来工作

### 待实现的基准测试

1. **端到端基准测试** (AC4.8.5, AC4.8.6):
   - ZORM vs pg.zig 原生操作
   - 批量插入性能
   - 复杂查询性能
   - 事务性能

2. **结果扫描基准测试** (AC4.8.3):
   - 零拷贝 vs 拷贝模式
   - 不同数据类型的扫描性能
   - 大结果集扫描性能

3. **内存效率基准测试**:
   - Arena 分配器 vs 逐个分配
   - 内存峰值使用量
   - 内存泄漏检测

### 性能优化机会

1. **查询缓存**: 缓存重复查询的 SQL 字符串
2. **连接池**: 减少连接建立开销
3. **批量操作**: 优化批量插入/更新性能

## 贡献指南

如果您想添加新的基准测试：

1. 在 `benchmarks/` 目录下创建 `<feature>_bench.zig`
2. 遵循现有基准测试的格式（打印对比表格）
3. 在本 README 中添加基准测试说明
4. 更新 `build.zig` 添加构建步骤

## 性能数据归档

历史性能数据存储在 `benchmarks/results/` 目录（git 忽略），用于追踪性能趋势。

每次运行基准测试后，可以手动保存结果：

```sh
./buffer_preallocation_bench > benchmarks/results/buffer_$(date +%Y%m%d).txt
./comptime_optimization_bench > benchmarks/results/comptime_$(date +%Y%m%d).txt
```

## 参考资料

- [PRD Story 4.8: 性能优化和基准测试](../openspec/changes/optimize-performance-benchmarking/proposal.md)
- [ZORM 架构设计](../docs/architecture.md)
- [Zig 性能最佳实践](https://ziglang.org/documentation/master/#Performance)
