const std = @import("std");

pub fn build(b: *std.Build) void {
    // 标准目标选项
    const target = b.standardTargetOptions(.{});

    // 标准优化选项
    const optimize = b.standardOptimizeOption(.{});

    // PostgreSQL 支持选项
    const enable_postgres = b.option(bool, "postgres", "Enable PostgreSQL support") orelse false;
    // MySQL 支持选项

    // 构建选项
    const options = b.addOptions();
    options.addOption(bool, "enable_postgres", enable_postgres);

    // 获取 pg.zig 依赖
    const pg_dep = b.dependency("pg", .{
        .target = target,
        .optimize = optimize,
    });

    // 创建 ZORM 库模块
    const zorm_module = b.createModule(.{
        .root_source_file = b.path("src/zorm.zig"),
        .target = target,
        .optimize = optimize,
    });

    zorm_module.addOptions("build_options", options);

    // 添加 pg.zig 模块
    zorm_module.addImport("pg", pg_dep.module("pg"));

    // 格式化检查
    const fmt_check = b.addFmt(.{
        .paths = &.{ "src", "build.zig" },
        .check = true,
    });

    const fmt_check_step = b.step("fmt-check", "Check formatting");
    fmt_check_step.dependOn(&fmt_check.step);

    // 格式化代码
    const fmt = b.addFmt(.{
        .paths = &.{ "src", "build.zig" },
        .check = false,
    });

    const fmt_step = b.step("fmt", "Format code");
    fmt_step.dependOn(&fmt.step);

    // 文档生成配置
    // Zig 0.15.2 通过测试模块生成文档
    const docs_obj = b.addTest(.{
        .root_module = zorm_module,
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_obj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate API documentation");
    docs_step.dependOn(&install_docs.step);

    // 单元测试配置
    const unit_test_module = b.createModule(.{
        .root_source_file = b.path("src/zorm.zig"),
        .target = target,
        .optimize = optimize,
    });

    unit_test_module.addOptions("build_options", options);
    unit_test_module.addImport("pg", pg_dep.module("pg"));

    const unit_tests = b.addTest(.{
        .root_module = unit_test_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // 添加 CREATE INDEX 测试
    const create_index_test_module = b.createModule(.{
        .root_source_file = b.path("tests/create_index_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    create_index_test_module.addOptions("build_options", options);
    create_index_test_module.addImport("pg", pg_dep.module("pg"));
    create_index_test_module.addImport("zorm", zorm_module);

    const create_index_tests = b.addTest(.{
        .root_module = create_index_test_module,
    });

    const run_create_index_tests = b.addRunArtifact(create_index_tests);
    test_step.dependOn(&run_create_index_tests.step);

    // 添加 DROP INDEX 测试
    const drop_index_test_module = b.createModule(.{
        .root_source_file = b.path("tests/drop_index_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    drop_index_test_module.addOptions("build_options", options);
    drop_index_test_module.addImport("pg", pg_dep.module("pg"));
    drop_index_test_module.addImport("zorm", zorm_module);

    const drop_index_tests = b.addTest(.{
        .root_module = drop_index_test_module,
    });

    const run_drop_index_tests = b.addRunArtifact(drop_index_tests);
    test_step.dependOn(&run_drop_index_tests.step);

    // 添加 PostgreSQL 特定类型集成测试
    const pg_types_test_module = b.createModule(.{
        .root_source_file = b.path("tests/postgresql_types_integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 添加必要的模块导入
    pg_types_test_module.addImport("zorm", zorm_module);

    const pg_types_tests = b.addTest(.{
        .root_module = pg_types_test_module,
    });

    const run_pg_types_tests = b.addRunArtifact(pg_types_tests);
    test_step.dependOn(&run_pg_types_tests.step);

    // 添加 JOIN 查询测试
    const join_query_test_module = b.createModule(.{
        .root_source_file = b.path("tests/join_query_test_simple.zig"),
        .target = target,
        .optimize = optimize,
    });

    join_query_test_module.addOptions("build_options", options);
    join_query_test_module.addImport("zorm", zorm_module);

    const join_query_tests = b.addTest(.{
        .root_module = join_query_test_module,
    });

    const run_join_query_tests = b.addRunArtifact(join_query_tests);
    test_step.dependOn(&run_join_query_tests.step);

    // 添加子查询测试
    const subquery_test_module = b.createModule(.{
        .root_source_file = b.path("tests/subquery_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    subquery_test_module.addOptions("build_options", options);
    subquery_test_module.addImport("zorm", zorm_module);

    const subquery_tests = b.addTest(.{
        .root_module = subquery_test_module,
    });

    const run_subquery_tests = b.addRunArtifact(subquery_tests);
    test_step.dependOn(&run_subquery_tests.step);

    // 添加 debug 和错误上下文测试
    const debug_error_test_module = b.createModule(.{
        .root_source_file = b.path("tests/debug_error_context_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    debug_error_test_module.addOptions("build_options", options);
    debug_error_test_module.addImport("zorm", zorm_module);

    const debug_error_tests = b.addTest(.{
        .root_module = debug_error_test_module,
    });

    const run_debug_error_tests = b.addRunArtifact(debug_error_tests);
    test_step.dependOn(&run_debug_error_tests.step);

    // ========================================
    // 示例程序 (Examples)
    // ========================================
    // 注: examples/*.example 文件是文档示例,展示 API 用法但不编译
    //     schema.zig 是可运行的示例程序

    // Schema 示例程序
    const schema_example_module = b.createModule(.{
        .root_source_file = b.path("examples/schema.zig"),
        .target = target,
        .optimize = optimize,
    });

    schema_example_module.addImport("zorm", zorm_module);

    const schema_example = b.addExecutable(.{
        .name = "schema-example",
        .root_module = schema_example_module,
    });

    const run_schema_example = b.addRunArtifact(schema_example);
    const schema_example_step = b.step("run-example-schema", "Run schema management example");
    schema_example_step.dependOn(&run_schema_example.step);

    // Basic CRUD 示例程序
    const basic_example_module = b.createModule(.{
        .root_source_file = b.path("examples/basic.zig"),
        .target = target,
        .optimize = optimize,
    });

    basic_example_module.addImport("zorm", zorm_module);

    const basic_example = b.addExecutable(.{
        .name = "basic-example",
        .root_module = basic_example_module,
    });

    const run_basic_example = b.addRunArtifact(basic_example);
    const basic_example_step = b.step("run-example-basic", "Run basic CRUD operations example");
    basic_example_step.dependOn(&run_basic_example.step);

    // Transaction 示例程序
    const transaction_example_module = b.createModule(.{
        .root_source_file = b.path("examples/transaction.zig"),
        .target = target,
        .optimize = optimize,
    });

    transaction_example_module.addImport("zorm", zorm_module);

    const transaction_example = b.addExecutable(.{
        .name = "transaction-example",
        .root_module = transaction_example_module,
    });

    const run_transaction_example = b.addRunArtifact(transaction_example);
    const transaction_example_step = b.step("run-example-transaction", "Run transaction management example");
    transaction_example_step.dependOn(&run_transaction_example.step);

    // JOIN 示例程序
    const join_example_module = b.createModule(.{
        .root_source_file = b.path("examples/join.zig"),
        .target = target,
        .optimize = optimize,
    });

    join_example_module.addImport("zorm", zorm_module);

    const join_example = b.addExecutable(.{
        .name = "join-example",
        .root_module = join_example_module,
    });

    const run_join_example = b.addRunArtifact(join_example);
    const join_example_step = b.step("run-example-join", "Run JOIN query example");
    join_example_step.dependOn(&run_join_example.step);

    // 统一的示例编译步骤
    const examples_step = b.step("examples", "Compile all examples");
    examples_step.dependOn(&schema_example.step);
    examples_step.dependOn(&basic_example.step);
    examples_step.dependOn(&transaction_example.step);
    examples_step.dependOn(&join_example.step);

    // ========================================
    // 性能基准测试 (Benchmarks)
    // ========================================
    // 注: benchmarks/*.example 文件是基准测试模板
    //     需要配合实际的数据库驱动才能运行
    //     当前作为参考文档提供

    // 基准测试步骤(占位)
    const bench_step = b.step("bench", "Performance benchmarks (requires DB driver)");
    _ = bench_step;
}
