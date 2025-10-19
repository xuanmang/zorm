# ZORM 技术栈选型文档

**Version**: v1.0
**Date**: 2025-10-19
**Project**: ZORM - SQL-first Zig ORM for PostgreSQL
**Status**: Approved ✅

---

## 概述

本文档定义 ZORM 项目的**所有技术选型决策**，是项目的**单一真实来源**。所有开发、测试、部署必须严格遵循此文档中的技术选择和版本要求。

**设计原则**：
- **Zig 原生优先**：充分利用 Zig 标准库，避免不必要的外部依赖
- **PostgreSQL 专注**：仅支持 PostgreSQL，不考虑其他数据库
- **零运行时开销**：利用 comptime 实现编译时优化
- **显式内存管理**：Allocator 模式，无垃圾回收
- **与 Bun ORM API 对齐**：保持高层 API 使用方式一致

---

## 技术栈总览表

| Category | Technology | Version | Purpose | Rationale |
|----------|-----------|---------|---------|-----------|
| **核心语言** | Zig | 0.15.2+ | 主开发语言 | 编译时元编程、显式内存管理、C 互操作性、零开销抽象 |
| **目标数据库** | PostgreSQL | 14+ | 唯一支持的数据库 | 企业级 RDBMS，RETURNING/JSONB/数组类型等高级特性 |
| **数据库驱动** | pg.zig | latest | 纯 Zig PostgreSQL 驱动 | 纯 Zig 实现，无 C 依赖，原生类型安全，跨平台一致性好 |
| **构建系统** | Zig Build System | 0.15.2+ | 编译和构建管理 | Zig 原生构建系统，build.zig 配置 |
| **测试框架** | std.testing | 0.15.2+ | 单元测试和集成测试 | Zig 标准库内置，支持内存泄漏检测 |
| **内存检测** | std.testing.allocator | 0.15.2+ | 测试中内存泄漏检测 | 自动检测未释放内存 |
| **CI/CD** | GitHub Actions | latest | 自动化测试和发布 | 免费、易配置、与 GitHub 无缝集成 |
| **代码格式化** | zig fmt | 0.15.2+ | 代码格式化 | Zig 官方格式化工具，统一代码风格 |
| **文档生成** | zig build docs | 0.15.2+ | API 文档生成 | 从 Zig 注释生成 HTML 文档 |
| **性能基准** | std.time.Timer | 0.15.2+ | 性能基准测试 | 标准库时间测量工具 |

---

## 依赖库策略

**核心原则**：**最小化外部依赖，优先使用 Zig 标准库**

### 必需依赖

1. **pg.zig (纯 Zig PostgreSQL 客户端)**
   - **版本**: latest (通过 Git 仓库引用)
   - **用途**: PostgreSQL 数据库连接和查询执行
   - **仓库**: https://github.com/karlseguin/pg.zig
   - **集成方式**: Zig 模块系统 (通过 build.zig.zon 或 Git submodule)
   - **优势**:
     - 纯 Zig 实现,无需系统安装 PostgreSQL 客户端库
     - 跨平台编译简单,无 C 依赖
     - 原生 Zig 类型安全和错误处理
     - 避免 C FFI 开销
     - 支持同步和异步操作

### 可选依赖（未来考虑）

- **Zig Package Manager**: 当 Zig 包管理成熟后用于依赖管理
- **Benchmark 工具**: 用于性能对比测试（如果标准库不足）

### 不使用的依赖

- ❌ **libpq C 库**（使用纯 Zig 实现的 pg.zig 替代）
- ❌ **其他数据库驱动**（仅支持 PostgreSQL）
- ❌ **ORM 框架**（ZORM 本身就是 ORM）
- ❌ **外部测试框架**（使用 std.testing）
- ❌ **日志库**（用户自行选择，ZORM 提供钩子接口）

---

## 开发工具链

| Tool | Version | Purpose |
|------|---------|---------|
| Zig Compiler | 0.15.2+ | 编译器和工具链 |
| PostgreSQL Server | 14+ | 本地测试数据库(仅需服务端,无需客户端库) |
| Git | 2.40+ | 版本控制 |
| Docker (可选) | 24+ | PostgreSQL 测试容器 |

### 推荐的 IDE/编辑器

- **VS Code** + Zig Language Extension
- **Neovim/Vim** + zig.vim
- **JetBrains IDEs** + Zig Plugin
- **Sublime Text** + Zig Syntax

---

## 平台支持

### 操作系统

| OS | Status | Notes |
|----|--------|-------|
| **Linux** | ✅ 主要支持 | Ubuntu 22.04+, Debian 11+, Arch Linux |
| **macOS** | ✅ 主要支持 | macOS 12+ (Intel & Apple Silicon) |
| **Windows** | ✅ 支持 | Windows 10/11, 需要 MSVC 或 MinGW |

### CPU 架构

- **x86_64** (Intel/AMD 64-bit) - ✅ 主要支持
- **aarch64** (ARM 64-bit, Apple M1/M2) - ✅ 主要支持
- **其他架构** - ⚠️ 未测试，理论上支持

---

## 版本策略

### Zig 版本兼容性

- **最低支持版本**: Zig 0.15.2
- **目标版本**: Zig 0.15.x 系列
- **升级策略**:
  - 跟踪 Zig 稳定版本发布
  - 主版本升级时创建迁移指南
  - CI 测试多个 Zig 版本 (0.15.2, 0.15.latest)

### PostgreSQL 版本兼容性

- **最低支持版本**: PostgreSQL 14
- **推荐版本**: PostgreSQL 15+
- **测试版本**: 14, 15, 16

### 语义化版本控制

ZORM 遵循 [Semantic Versioning 2.0.0](https://semver.org/):
- **Major (X.y.z)**: 破坏性 API 变更
- **Minor (x.Y.z)**: 向后兼容的新功能
- **Patch (x.y.Z)**: 向后兼容的 bug 修复

---

## 构建目标

### 输出

- **静态库**: `libzorm.a` (Unix), `zorm.lib` (Windows)
- **动态库**: `libzorm.so` (Linux), `libzorm.dylib` (macOS), `zorm.dll` (Windows)
- **Zig 模块**: 可通过 `@import("zorm")` 引入

### 构建模式

| Mode | Optimization | Debug Info | Use Case |
|------|--------------|------------|----------|
| **Debug** | -O Debug | 完整 | 开发调试 |
| **ReleaseSafe** | -O ReleaseSafe | 部分 | 默认发布模式，保留安全检查 |
| **ReleaseFast** | -O ReleaseFast | 无 | 性能优先场景 |
| **ReleaseSmall** | -O ReleaseSmall | 无 | 二进制大小优先 |

**默认推荐**: `ReleaseSafe` - 平衡性能和安全

---

## 技术约束

### 硬性约束（不可变更）

1. **Zig 0.15.2+ 必需**：使用最新 ArrayList API 和语言特性
2. **PostgreSQL 专用**：不支持其他数据库（MySQL/SQLite/MSSQL/Oracle）
3. **纯 Zig 实现**：使用 pg.zig 驱动，避免 C 依赖
4. **显式内存管理**：所有 API 必须接受 Allocator 参数
5. **强制错误处理**：所有可能失败的操作返回 `!T` error union

### 软性约束（可讨论）

1. **最小外部依赖**：优先标准库，除非有明确收益
2. **零垃圾回收**：避免任何 GC 依赖
3. **编译时优化优先**：利用 comptime 减少运行时开销

---

## 变更记录

| Date | Version | Change | Author |
|------|---------|--------|--------|
| 2025-10-19 | v1.0 | 初始技术栈定义 | Winston (Architect) |
| 2025-10-19 | v1.1 | 替换 libpq 为 pg.zig 纯 Zig 驱动,添加 Zig 语言手册引用 | Winston (Architect) |

---

## 参考资源

- **Zig 官方文档**: https://ziglang.org/documentation/0.15.2/
- **Zig 0.15.2 语言手册**: https://ziglang.org/documentation/0.15.2/std/ (或本地: /opt/homebrew/Cellar/zig/0.15.2/doc/langref.html)
- **PostgreSQL 文档**: https://www.postgresql.org/docs/14/
- **pg.zig 仓库**: https://github.com/karlseguin/pg.zig
- **Bun ORM 文档**: https://bun.sh/docs/api/database
