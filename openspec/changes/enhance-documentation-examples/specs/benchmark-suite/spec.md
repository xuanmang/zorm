# Spec: Benchmark Suite

## ADDED Requirements

### Requirement: Benchmark Testing Framework

A performance benchmark testing framework MUST be established to verify ZORM's performance goals.

#### Scenario: 基准测试基础设施

**Given** ZORM 项目需要性能验证
**When** 创建基准测试框架
**Then** 应包含以下组件：
- `benchmarks/` 目录结构
- 基准测试运行器（使用 Zig 的 benchmark 功能）
- 结果记录和报告生成
- 与原生 pg.zig 的对比测试（可选）

**And** build.zig 提供 `zig build bench` 步骤

**Verification**:
```bash
zig build bench
# 应输出性能测试结果
```

---

### Requirement: Batch Insert Performance Test

Batch insert operation performance MUST be tested to verify the <5% overhead goal is met.

#### Scenario: 批量插入基准测试

**Given** 基准测试框架已建立
**When** 运行批量插入测试
**Then** 测试应包含：
- 插入 1000 行数据的耗时
- 插入 10000 行数据的耗时
- 内存使用情况
- 与原生操作的对比（如果可行）

**And** 结果应显示 ZORM 开销 < 5%

**Example Output**:
```
Batch Insert Benchmark:
  1000 rows:  12.5ms (ZORM) vs 12.0ms (native) - 4.2% overhead
  10000 rows: 125.0ms (ZORM) vs 120.0ms (native) - 4.2% overhead
  Memory: 1.2MB allocated
```

---

### Requirement: Query Building Performance Test

SQL query building performance MUST be tested to ensure comptime optimization is effective.

#### Scenario: 查询构建基准测试

**Given** 复杂查询场景
**When** 运行查询构建测试
**Then** 测试应包含：
- 简单 SELECT 构建耗时
- 复杂 JOIN 查询构建耗时
- 带多个条件的 WHERE 子句构建
- 内存分配统计

**And** 复杂查询构建应 < 1ms

**Example Output**:
```
Query Building Benchmark:
  Simple SELECT:   0.05ms
  Complex JOIN:    0.8ms
  Multi-WHERE:     0.3ms
```

---

### Requirement: Result Scanning Performance Test

Query result scanning and serialization performance MUST be tested.

#### Scenario: 结果扫描基准测试

**Given** 查询返回大量数据
**When** 运行结果扫描测试
**Then** 测试应包含：
- 扫描 1000 行到结构体的耗时
- 扫描 10000 行的耗时
- 内存分配情况
- 与原生操作对比

**And** 开销应 < 5%

**Example Output**:
```
Result Scanning Benchmark:
  1000 rows:  8.0ms (ZORM) vs 7.8ms (native) - 2.6% overhead
  10000 rows: 80.0ms (ZORM) vs 78.0ms (native) - 2.6% overhead
```

---

### Requirement: Complete Query Pipeline Performance Test

Complete query pipeline performance MUST be tested end-to-end.

#### Scenario: 端到端基准测试

**Given** 真实应用场景
**When** 运行端到端测试
**Then** 测试应包含：
- 连接创建到查询执行的完整流程
- 复杂业务场景（JOIN + WHERE + ORDER BY + LIMIT）
- 事务处理性能
- 钩子系统的性能影响

**Example Output**:
```
End-to-End Benchmark:
  Simple query (no hooks):    15.0ms
  Simple query (with hooks):  15.5ms - 3.3% overhead
  Complex query (no hooks):   45.0ms
  Complex query (with hooks): 46.5ms - 3.3% overhead
  Transaction (10 ops):       120.0ms
```

---

### Requirement: Memory Usage Analysis

Memory usage for various operations MUST be analyzed and recorded.

#### Scenario: 内存基准测试

**Given** 各类数据库操作
**When** 运行内存测试
**Then** 测试应记录：
- 查询构建器的内存分配
- 结果集的内存占用
- Arena 分配器的使用效果
- 内存泄漏检测

**Verification**:
```bash
zig build bench-memory
# 使用 std.testing.allocator 检测泄漏
```

---

### Requirement: Benchmark Test Result Documentation

Benchmark test results MUST be recorded and included in documentation.

#### Scenario: 性能报告生成

**Given** 基准测试完成
**When** 生成测试报告
**Then** 应生成包含以下内容的报告：
- 各项测试的详细结果
- 与性能目标的对比
- 趋势分析（如果有历史数据）
- 性能优化建议

**And** 报告应保存到 `benchmarks/results/` 目录
**And** README.md 应链接到最新的测试报告

---

### Requirement: Repeatable Test Environment

Benchmark tests MUST run in a consistent environment to ensure results are repeatable.

#### Scenario: 测试环境标准化

**Given** 基准测试需要可重复
**When** 设置测试环境
**Then** 应文档化：
- 测试硬件规格
- 数据库配置（PostgreSQL 版本、配置参数）
- 测试数据集大小
- 环境变量设置

**And** 提供环境设置脚本（可选）

---

### Requirement: Continuous Performance Monitoring

A mechanism MUST be established to run benchmark tests periodically and monitor performance degradation.

#### Scenario: CI 集成（可选）

**Given** 项目有 CI/CD 流程
**When** 代码变更时
**Then** 可选择性地运行基准测试
**And** 性能下降超过阈值时发出警告

**Note**: 这是可选需求，优先级较低
