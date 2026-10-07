const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const rich = b.addModule("zrich", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const demo = b.addExecutable(.{
        .name = "zrich-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zrich", .module = rich }},
        }),
    });
    b.installArtifact(demo);
    const run = b.addRunArtifact(demo);
    // Keep the standalone binary in sync whenever the showcase runs.
    run.step.dependOn(b.getInstallStep());
    b.step("demo", "Run the Rich-style output demo").dependOn(&run.step);
    const tests = b.addTest(.{ .root_module = rich });
    b.step("test", "Run library tests").dependOn(&b.addRunArtifact(tests).step);
}
