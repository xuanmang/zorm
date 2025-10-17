const std = @import("std");

pub fn build(b: *std.Build) void {
    // 标准目标选项
    const target = b.standardTargetOptions(.{});

    // 标准优化选项
    const optimize = b.standardOptimizeOption(.{});

    // PostgreSQL 支持选项
    const enable_postgres = b.option(bool, "postgres", "Enable PostgreSQL support") orelse false;
    // MySQL 支持选项
    const enable_mysql = b.option(bool, "mysql", "Enable MySQL support") orelse false;
    // SQLite 支持选项
    const enable_sqlite = b.option(bool, "sqlite", "Enable SQLite support") orelse false;

    // 构建选项
    const options = b.addOptions();
    options.addOption(bool, "enable_postgres", enable_postgres);
    options.addOption(bool, "enable_mysql", enable_mysql);
    options.addOption(bool, "enable_sqlite", enable_sqlite);

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

    // 示例程序
    const example_module = b.createModule(.{
        .root_source_file = b.path("examples/basic.zig"),
        .target = target,
        .optimize = optimize,
    });

    example_module.addImport("zorm", zorm_module);

    const example = b.addExecutable(.{
        .name = "basic_example",
        .root_module = example_module,
    });

    const install_example = b.addInstallArtifact(example, .{});
    const example_step = b.step("example", "Build and install example");
    example_step.dependOn(&install_example.step);

    const run_example = b.addRunArtifact(example);
    run_example.step.dependOn(&install_example.step);

    if (b.args) |args| {
        run_example.addArgs(args);
    }

    const run_example_step = b.step("run-example", "Run the basic example");
    run_example_step.dependOn(&run_example.step);

    // 格式化检查
    const fmt_check = b.addFmt(.{
        .paths = &.{ "src", "examples", "build.zig" },
        .check = true,
    });

    const fmt_check_step = b.step("fmt-check", "Check formatting");
    fmt_check_step.dependOn(&fmt_check.step);

    // 格式化代码
    const fmt = b.addFmt(.{
        .paths = &.{ "src", "examples", "build.zig" },
        .check = false,
    });

    const fmt_step = b.step("fmt", "Format code");
    fmt_step.dependOn(&fmt.step);

    // 单元测试配置
    const unit_tests = b.addTest(.{
        .root_module = zorm_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // 连接池测试
    const pool_test_module = b.createModule(.{
        .root_source_file = b.path("tests/pool_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    pool_test_module.addImport("zorm", zorm_module);

    const pool_tests = b.addTest(.{
        .root_module = pool_test_module,
    });

    const run_pool_tests = b.addRunArtifact(pool_tests);
    const pool_test_step = b.step("test-pool", "Run connection pool tests");
    pool_test_step.dependOn(&run_pool_tests.step);

    // 将 pool 测试添加到主测试步骤
    test_step.dependOn(&run_pool_tests.step);

    // PostgreSQL 集成测试
    if (enable_postgres) {
        const postgres_test_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/postgres_test.zig"),
            .target = target,
            .optimize = optimize,
        });

        postgres_test_module.addImport("zorm", zorm_module);

        const postgres_tests = b.addTest(.{
            .root_module = postgres_test_module,
        });

        const run_postgres_tests = b.addRunArtifact(postgres_tests);
        const postgres_test_step = b.step("test-postgres", "Run PostgreSQL integration tests");
        postgres_test_step.dependOn(&run_postgres_tests.step);

        const all_tests_step = b.step("test-all", "Run all tests (unit + integration)");
        all_tests_step.dependOn(&run_unit_tests.step);
        all_tests_step.dependOn(&run_postgres_tests.step);

        // 简单 PostgreSQL 测试程序
        const simple_pg_test_module = b.createModule(.{
            .root_source_file = b.path("simple_pg_test.zig"),
            .target = target,
            .optimize = optimize,
        });

        simple_pg_test_module.addImport("pg", pg_dep.module("pg"));

        const simple_pg_test_exe = b.addExecutable(.{
            .name = "simple_pg_test",
            .root_module = simple_pg_test_module,
        });

        b.installArtifact(simple_pg_test_exe);

        const run_simple_pg_test = b.addRunArtifact(simple_pg_test_exe);
        const simple_pg_test_step = b.step("test-simple-pg", "Run simple PostgreSQL test");
        simple_pg_test_step.dependOn(&run_simple_pg_test.step);

        // 最小化集成测试
        const minimal_test_module = b.createModule(.{
            .root_source_file = b.path("minimal_test.zig"),
            .target = target,
            .optimize = optimize,
        });

        minimal_test_module.addImport("zorm", zorm_module);

        const minimal_tests = b.addTest(.{
            .root_module = minimal_test_module,
        });

        const run_minimal_tests = b.addRunArtifact(minimal_tests);
        const minimal_test_step = b.step("test-minimal", "Run minimal integration test");
        minimal_test_step.dependOn(&run_minimal_tests.step);

        // Stmt 参数绑定测试程序
        const simple_test_module = b.createModule(.{
            .root_source_file = b.path("simple_test.zig"),
            .target = target,
            .optimize = optimize,
        });

        simple_test_module.addImport("pg", pg_dep.module("pg"));

        const simple_test_exe = b.addExecutable(.{
            .name = "simple_test",
            .root_module = simple_test_module,
        });

        b.installArtifact(simple_test_exe);

        const run_simple_test = b.addRunArtifact(simple_test_exe);
        const simple_test_step = b.step("test-simple", "Run simple Stmt bind test");
        simple_test_step.dependOn(&run_simple_test.step);
    }
}
