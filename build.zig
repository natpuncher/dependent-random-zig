const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("dependent_random_zig", .{
        .root_source_file = b.path("dependentrandom.zig"),
    });

    const tests = b.addTest(.{
        .root_source_file = b.path("dependentrandom.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    const run_test = b.addRunArtifact(tests);
    test_step.dependOn(&run_test.step);
}
