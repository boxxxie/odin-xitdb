const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const patched = b.option(bool, "patched", "Use reference/xitdb-zig-patched instead of upstream reference/xitdb-zig") orelse false;

    const zig_dir = if (patched) "reference/xitdb-zig-patched" else "reference/xitdb-zig";

    const xitdb = b.addModule("xitdb", .{
        .root_source_file = b.path(b.fmt("{s}/src/lib.zig", .{zig_dir})),
    });

    const bench_exe = b.addExecutable(.{
        .name = "bench_xitdb_zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/bench_xitdb.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "xitdb", .module = xitdb },
            },
        }),
    });
    b.installArtifact(bench_exe);

    const run_bench = b.addRunArtifact(bench_exe);
    run_bench.step.dependOn(b.getInstallStep());
    run_bench.addPassthruArgs();

    const bench_step = b.step("bench", "Run xitdb Zig benchmark suite (mirror of bench_xitdb.odin)");
    bench_step.dependOn(&run_bench.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("{s}/src/test.zig", .{zig_dir})),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "xitdb", .module = xitdb },
            },
        }),
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run xitdb-zig library tests (pass -Dpatched=true for patched fork)");
    test_step.dependOn(&run_unit_tests.step);
}
