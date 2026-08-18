const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zig_filewatch", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "zig_filewatch",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_filewatch", .module = mod },
            },
        }),
    });
    // const glob_dep = b.dependency("glob", .{ .target = target, .optimize = optimize });
    // exe.root_module.addImport("glob", glob_dep.module("glob"));

    const nightwatch = b.dependency("nightwatch", .{});
    exe.root_module.addImport("nightwatch", nightwatch.module("nightwatch"));

    const zigcli = b.dependency("zigcli", .{});
    exe.root_module.addImport("zigcli", zigcli.module("zigcli"));

    exe.root_module.addCSourceFile(.{.file = b.path("vendor/wildmatch/wildmatch.c")});
    exe.root_module.addIncludePath(b.path("vendor/wildmatch"));

    b.installArtifact(exe);

    const test_exe = b.addExecutable(.{
        .name = "test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
            },
        })
    });
    b.installArtifact(test_exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
