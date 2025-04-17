const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const texzel_lib_mod = b.createModule(.{
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

    const texzel_unit_tests = b.addTest(.{
        .name = "texzel_unit_tests",
        .root_module = texzel_lib_mod,
    });

    const run_texzel_unit_tests = b.addRunArtifact(texzel_unit_tests);

    const texzel_test_step = b.step("test", "Run unit tests");
    texzel_test_step.dependOn(&run_texzel_unit_tests.step);

    b.installArtifact(texzel_unit_tests);
}
