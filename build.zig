const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Lib
    const texzel_lib_mod = b.addModule("texzel", .{
        .root_source_file = b.path("src/texzel.zig"),
        .target = target,
        .optimize = optimize,
    });

    const texzel_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "texzel",
        .root_module = texzel_lib_mod,
    });

    b.installArtifact(texzel_lib);

    // Tests
    const texzel_unit_tests = b.addTest(.{
        .name = "texzel_unit_tests",
        .root_module = texzel_lib_mod,
    });

    const run_texzel_unit_tests = b.addRunArtifact(texzel_unit_tests);

    const texzel_test_step = b.step("test", "Run unit tests");
    texzel_test_step.dependOn(&run_texzel_unit_tests.step);

    b.installArtifact(texzel_unit_tests);

    // Docs
    const texzel_docs = b.addInstallDirectory(.{
        .source_dir = texzel_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const texzel_docs_step = b.step("docs", "Install docs");
    texzel_docs_step.dependOn(&texzel_docs.step);

    // Benchmarks
    const texzel_bench_exe_mod = b.createModule(.{
        .root_source_file = b.path("src/bench.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "texzel",
                .module = texzel_lib_mod,
            },
        },
    });

    const texzel_bench_exe = b.addExecutable(.{
        .name = "texzel_bench",
        .root_module = texzel_bench_exe_mod,
    });

    const texzel_bench_run_cmd = b.addRunArtifact(texzel_bench_exe);

    texzel_bench_run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        texzel_bench_run_cmd.addArgs(args);
    }

    const texzel_bench_step = b.step("bench", "Run the Texzel benchmarks");
    texzel_bench_step.dependOn(&texzel_bench_run_cmd.step);

    b.installArtifact(texzel_bench_exe);
}
