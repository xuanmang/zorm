# Tasks: Complete DELETE Query Builder API

## Implementation Checklist

- [ ] 补充 whereIn 基本功能测试
- [ ] 补充 whereNotIn 基本功能测试
- [ ] 补充 whereIn 与 where 组合测试
- [ ] 补充 whereIn 空列表错误测试
- [ ] 补充 whereIn SQL 生成验证测试
- [ ] 验证所有 AC2.3.x 要求已满足
- [ ] 运行完整测试套件确保无回归
- [ ] 修复任何发现的问题
- [ ] 更新 API 文档（如需要）
- [ ] 提交代码并创建提交日志

## Validation Steps

1. **功能验证**
   - WHERE 条件强制检查正常工作
   - whereIn/whereNotIn 批量删除正常
   - RETURNING 子句返回正确数据
   - 链式调用流畅无误

2. **测试验证**
   - 所有测试通过（`zig build test`）
   - 内存泄漏检测通过
   - 测试覆盖关键路径和边界情况

3. **API 一致性验证**
   - 与 UPDATE Builder API 风格一致
   - 与 Bun ORM 使用方式对齐
   - 错误消息清晰明确

## Dependencies

无外部依赖，基于现有实现进行补充。

## Notes

- DeleteQuery 核心实现已完成（src/query/query.zig:1721-2107）
- 基本测试已存在，主要补充批量删除测试
- 需要修复 Index 相关测试失败（独立问题）
