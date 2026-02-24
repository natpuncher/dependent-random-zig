const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dependent_random_module = b.addModule("dependent_random_zig", .{
        .root_source_file = b.path("dependentrandom.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .root_module = dependent_random_module,
    });

    const test_step = b.step("test", "Run unit tests");
    const run_test = b.addRunArtifact(tests);
    test_step.dependOn(&run_test.step);
}
