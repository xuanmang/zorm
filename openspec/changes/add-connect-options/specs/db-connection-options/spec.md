# DB Connection Options Configuration

## 概述
定义 `zorm.connect` 函数的 DBOptions 参数配置行为规范。

---

## ADDED Requirements

### Requirement: 支持可选的 DBOptions 参数

`zorm.connect` 函数 MUST 接受一个可选的 `DBOptions` 参数,允许用户在创建连接时自定义数据库配置。

#### Scenario: 使用默认配置创建连接

**Given** 用户调用 `zorm.connect` 时不传递 `options` 参数
**When** 连接被创建
**Then** DB 实例使用 DBOptions 的默认配置值:
- `discard_unknown_columns = false`
- `max_open_conns = 25`
- `max_idle_conns = 25`
- `conn_max_lifetime = 300` (秒)
- `conn_max_idle_time = 60` (秒)
- `query_timeout = 30_000` (毫秒)
- `enable_query_log = false`
- `enable_slow_query_log = false`
- `slow_query_threshold = 1000` (毫秒)
- `debug = false`

**示例代码**:
```zig
const db = try zorm.connect(allocator, dsn);
defer db.deinit();
// db.options 包含所有默认值
```

---

#### Scenario: 使用自定义配置创建连接

**Given** 用户创建了自定义的 DBOptions 配置
**When** 用户将该配置传递给 `zorm.connect`
**Then** DB 实例使用用户提供的配置值

**示例代码**:
```zig
const options = zorm.DBOptions{
    .debug = true,
    .max_open_conns = 50,
    .max_idle_conns = 10,
    .query_timeout = 60_000,
    .enable_query_log = true,
    .enable_slow_query_log = true,
    .slow_query_threshold = 500,
};

const db = try zorm.connect(allocator, dsn, options);
defer db.deinit();
// db.options 包含用户自定义的值
```

---

### Requirement: 向后兼容性

现有使用 `zorm.connect` 的代码 MUST 无需修改即可继续工作。

#### Scenario: 现有代码保持兼容

**Given** 现有代码使用两参数形式调用 `zorm.connect(allocator, dsn)`
**When** 代码编译和运行
**Then** 连接成功创建,使用默认配置

**示例代码**:
```zig
// 现有代码(无需修改)
const db = try zorm.connect(allocator, dsn);
defer db.deinit();
```

---

### Requirement: 配置项正确应用

传递给 `connect` 的 DBOptions 配置 MUST 正确应用到 DB 实例。

#### Scenario: Debug 模式配置生效

**Given** 用户创建连接时设置 `debug = true`
**When** 执行查询操作
**Then** 查询 SQL 和参数被打印到日志

**验证方式**: 检查 `db.options.debug == true`,执行查询时产生调试日志输出

---

#### Scenario: 连接池配置生效

**Given** 用户创建连接时设置 `max_open_conns = 100`
**When** 获取 DB 实例的 options
**Then** `db.options.max_open_conns == 100`

**验证方式**: 通过测试断言验证配置值

---

#### Scenario: 查询超时配置生效

**Given** 用户创建连接时设置 `query_timeout = 5000`
**When** 获取 DB 实例的 options
**Then** `db.options.query_timeout == 5000`

**验证方式**: 通过测试断言验证配置值

---

## 相关组件
- `src/convenience.zig` - `connect` 函数实现
- `src/core/db.zig` - `DBOptions` 结构定义

## 测试要求
- 必须包含默认配置的测试用例
- 必须包含自定义配置的测试用例
- 必须验证配置正确应用到 DB 实例
