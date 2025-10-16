const std = @import("std");

pub fn build(b: *std.Build) void {
    // 标准目标选项
    const target = b.standardTargetOptions(.{});

    // 标准优化选项
    const optimize = b.standardOptimizeOption(.{});

    // 创建 ZORM 库模块
    const zorm = b.addModule("zorm", .{
        .root_source_file = b.path("src/zorm.zig"),
        .target = target,
        .optimize = optimize,
    });

    // PostgreSQL 支持选项
    const enable_postgres = b.option(bool, "postgres", "Enable PostgreSQL support") orelse true;
    // MySQL 支持选项
    const enable_mysql = b.option(bool, "mysql", "Enable MySQL support") orelse true;
    // SQLite 支持选项
    const enable_sqlite = b.option(bool, "sqlite", "Enable SQLite support") orelse true;

    // 构建选项传递给代码
    const options = b.addOptions();
    options.addOption(bool, "enable_postgres", enable_postgres);
    options.addOption(bool, "enable_mysql", enable_mysql);
    options.addOption(bool, "enable_sqlite", enable_sqlite);

    zorm.addOptions("build_options", options);

    // 链接 C 库
    if (enable_postgres) {
        zorm.linkSystemLibrary("pq", .{});
    }
    if (enable_mysql) {
        zorm.linkSystemLibrary("mysqlclient", .{});
    }
    if (enable_sqlite) {
        zorm.linkSystemLibrary("sqlite3", .{});
    }

    // 链接 libc
    zorm.link_libc = true;

    // 创建静态库
    const lib = b.addStaticLibrary(.{
        .name = "zorm",
        .root_source_file = b.path("src/zorm.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC();
    if (enable_postgres) {
        lib.linkSystemLibrary("pq");
    }
    if (enable_mysql) {
        lib.linkSystemLibrary("mysqlclient");
    }
    if (enable_sqlite) {
        lib.linkSystemLibrary("sqlite3");
    }

    b.installArtifact(lib);

    // 单元测试
    const tests = b.addTest(.{
        .root_source_file = b.path("src/zorm.zig"),
        .target = target,
        .optimize = optimize,
    });

    tests.linkLibC();
    if (enable_postgres) {
        tests.linkSystemLibrary("pq");
    }
    if (enable_mysql) {
        tests.linkSystemLibrary("mysqlclient");
    }
    if (enable_sqlite) {
        tests.linkSystemLibrary("sqlite3");
    }

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // 示例程序
    const example = b.addExecutable(.{
        .name = "basic_example",
        .root_source_file = b.path("examples/basic.zig"),
        .target = target,
        .optimize = optimize,
    });

    example.root_module.addImport("zorm", zorm);
    example.linkLibC();
    if (enable_postgres) {
        example.linkSystemLibrary("pq");
    }

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

    // 文档生成
    const docs = b.addStaticLibrary(.{
        .name = "zorm",
        .root_source_file = b.path("src/zorm.zig"),
        .target = target,
        .optimize = .Debug,
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);

    // 格式化检查
    const fmt_check = b.addFmt(.{
        .paths = &.{ "src", "tests", "examples", "build.zig" },
        .check = true,
    });

    const fmt_check_step = b.step("fmt-check", "Check formatting");
    fmt_check_step.dependOn(&fmt_check.step);

    // 格式化代码
    const fmt = b.addFmt(.{
        .paths = &.{ "src", "tests", "examples", "build.zig" },
        .check = false,
    });

    const fmt_step = b.step("fmt", "Format code");
    fmt_step.dependOn(&fmt.step);
}
