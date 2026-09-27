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
    // Zig 0.17 forwards build arguments through the Run step; 0.16 stores
    // them on Build. Feature detection keeps both toolchains supported.
    if (@hasDecl(std.Build.Step.Run, "addPassthruArgs")) {
        run.addPassthruArgs();
    } else if (b.args) |args| {
        run.addArgs(args);
    }
    b.step("demo", "Run the Rich-style output demo").dependOn(&run.step);
    const tests = b.addTest(.{ .root_module = rich });
    b.step("test", "Run library tests").dependOn(&b.addRunArtifact(tests).step);
}
