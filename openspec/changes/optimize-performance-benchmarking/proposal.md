# Proposal: optimize-performance-benchmarking

## Overview

实现 PRD Story 4.8 定义的性能优化和基准测试功能，确保 ZORM 提供接近原生 PostgreSQL 协议的性能（开销不超过 5%），并建立完整的性能验证体系。

## Why

性能是 ORM 库的核心竞争力之一。作为 SQL-first 的 Zig ORM，ZORM 必须证明其在提供便利性的同时不会牺牲性能。具体原因：

1. **用户信任**：开发者在选择 ORM 时，性能是关键考量因素。明确的性能数据和基准测试结果能建立用户信任
2. **竞争优势**：相比其他语言的 ORM（如 Go 的 GORM），Zig 的零成本抽象和 comptime 特性使 ZORM 有潜力实现更优性能
3. **生产就绪**：只有经过充分性能验证和优化的 ORM 才能用于生产环境，特别是高并发场景
4. **持续改进**：完善的基准测试框架和性能监控能帮助及早发现性能回归，确保代码质量
5. **PRD 承诺**：PRD Story 4.8 明确要求 ZORM 开销不超过 5%，这是对用户的承诺，必须通过技术手段保证

## Goals

1. **内存分配优化**: 优化查询构建器的内存分配策略，使用 Arena 分配器减少临时分配开销
2. **SQL 生成优化**: 预分配缓冲区，减少字符串拼接过程中的多次内存分配
3. **结果扫描优化**: 实现零拷贝或最小拷贝的结果扫描机制
4. **编译时优化**: 最大化利用 Zig comptime 特性，将类型映射和 SQL 模板生成移到编译时
5. **基准测试框架**: 建立完整的性能基准测试基础设施，验证性能目标
6. **性能文档化**: 将基准测试结果集成到文档中，提供性能数据支撑

## Non-Goals

- 不涉及底层 PostgreSQL 驱动的性能优化（这是 pg.zig 的职责）
- 不实现复杂的查询优化器（保持 SQL-first 理念）
- 不引入缓存层或连接池优化（这些在其他 Epic 中处理）

## Success Criteria

根据 PRD Story 4.8 的验收标准：

- **AC4.8.1**: 查询构建器使用 Arena 分配器优化临时内存分配
- **AC4.8.2**: SQL 生成过程预分配缓冲区，减少多次分配
- **AC4.8.3**: 结果扫描优化，最小化数据拷贝
- **AC4.8.4**: comptime 优化：类型映射、SQL 模板生成在编译时完成
- **AC4.8.5**: 提供性能基准测试（benchmarks/ 目录），包含批量插入、查询构建、结果扫描测试
- **AC4.8.6**: 性能目标：ZORM 开销不超过 pg.zig 原生操作的 5%
- **AC4.8.7**: 基准测试结果包含在文档中

## Affected Capabilities

此提案将新增以下能力（specs）：

1. **arena-allocator-optimization** - Arena 分配器集成和查询构建优化
2. **sql-buffer-preallocation** - SQL 生成缓冲区预分配策略
3. **zero-copy-result-scanning** - 零拷贝结果扫描优化
4. **comptime-type-optimization** - 编译时类型映射和 SQL 模板优化
5. **benchmark-infrastructure** - 基准测试框架和性能验证基础设施
6. **performance-documentation** - 性能目标定义和基准测试结果文档化

## Dependencies

- 依赖现有的 `src/allocator.zig` 中的 `QueryContext` 实现
- 依赖现有的 `src/reflect` 类型反射系统
- 依赖现有的查询构建器 API（SELECT、INSERT、UPDATE、DELETE）
- 需要真实的 PostgreSQL 连接进行端到端性能测试

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| 性能优化可能增加代码复杂度 | Medium | 保持清晰的抽象边界，优化限定在内部实现 |
| Comptime 优化可能增加编译时间 | Low | 仅在必要处使用 comptime，测量编译时间影响 |
| 基准测试可能不稳定（噪声干扰） | Medium | 多次运行取平均值，使用统计方法过滤异常值 |
| 零拷贝优化可能引入内存安全问题 | High | 严格的所有权管理，完善的内存泄漏测试 |

## Timeline Estimate

- **Phase 1** (2-3 days): Arena 分配器集成和 SQL 缓冲区预分配
- **Phase 2** (2-3 days): 结果扫描优化和 comptime 优化
- **Phase 3** (2-3 days): 基准测试框架和性能验证
- **Phase 4** (1-2 days): 性能文档化和最终调优

**Total**: 约 7-11 天

## Alternatives Considered

### 方案 1: 激进的零拷贝优化
- **优点**: 理论上性能最佳
- **缺点**: 复杂度极高，可能引入内存安全问题
- **决策**: 采用保守的最小拷贝策略，保证安全性

### 方案 2: 查询缓存层
- **优点**: 可以显著提升重复查询性能
- **缺点**: 增加复杂度，缓存失效策略难以正确实现
- **决策**: 不在此阶段实现，保持 SQL-first 简洁性

### 方案 3: 自定义内存池
- **优点**: 更精细的内存控制
- **缺点**: 实现复杂，Arena 分配器已经足够高效
- **决策**: 使用标准的 Arena 分配器，经过验证且可靠

## Open Questions

1. **Q**: 是否需要为不同查询类型提供不同的缓冲区大小预估策略？
   - **A**: 先实现简单的启发式策略（基于历史平均值），后续根据基准测试结果调整

2. **Q**: Comptime 优化会增加多少编译时间？
   - **A**: 需要通过实际测试验证，如果影响超过 10% 需要重新评估

3. **Q**: 基准测试是否需要在 CI 中自动运行？
   - **A**: 是的，但只运行轻量级基准测试（避免 CI 时间过长），完整测试手动运行
