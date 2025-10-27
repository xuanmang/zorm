# 任务列表

## 1. 修改 connect 函数签名
- [x] 在 `src/convenience.zig` 中修改 `connect` 函数
- [x] 添加可选的 `options: ?DBOptions` 参数,默认为 `null`
- [x] 实现参数处理逻辑:
  - 当 `options == null` 时,使用 `DBOptions{}`
  - 当 `options != null` 时,使用 `options.?`
- [x] 将处理后的 options 传递给 `DB.init()`
- [x] 更新函数文档注释,说明新参数的用途和用法

**验证方式**: 代码编译通过,函数签名正确 ✅

---

## 2. 编写单元测试
- [x] 在 `src/convenience.zig` 中添加测试用例:
  - `test "connect with default options"` - 验证不传 options 的向后兼容性
  - `test "connect with custom options"` - 验证传递自定义 options
  - `test "custom options applied to DB instance"` - 验证 options 正确应用
- [x] 测试场景包括:
  - 验证 debug 模式配置
  - 验证连接池配置
  - 验证超时配置

**验证方式**: 运行 `zig build test`,所有测试通过 ✅ (443/443 tests passed)

---

## 3. 更新示例代码
- [x] 在 `examples/` 目录中找到使用 `zorm.connect` 的示例
- [x] 更新现有示例文件,添加 `null` 参数以保持向后兼容
  - examples/basic.zig
  - examples/transaction.zig
  - examples/join.zig
  - examples/schema.zig
- [x] 添加展示自定义 options 用法的新示例文件 `examples/custom_options.zig`
- [x] 示例应包含:
  - 使用默认配置的基本用法
  - 使用自定义 options 的高级用法
  - 常见配置场景(开发环境、生产环境、高并发场景)

**验证方式**: 示例代码可以编译和运行 ✅

---

## 4. 更新文档和注释
- [x] 更新 `connect` 函数的文档注释
- [x] 添加参数说明和使用示例
- [x] 在注释中说明向后兼容性
- [x] 添加代码示例展示两种用法:
  - 基本用法(不传 options)
  - 高级用法(传递自定义 options)

**验证方式**: 文档清晰完整,示例代码正确 ✅
