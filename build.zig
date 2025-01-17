const std = @import("std");

pub fn build(b: *std.Build) void {
    if (comptime !checkVersion())
        @compileError("Please! Update zig toolchain!");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ggml = b.addStaticLibrary(.{
        .name = "ggml",
        .target = target,
        .optimize = optimize,
    });
    if (optimize == .ReleaseSafe)
        ggml.bundle_compiler_rt = true;
    if (target.getAbi() != .msvc)
        ggml.defineCMacro("_GNU_SOURCE", null);
    ggml.addIncludePath(.{ .path = "." });
    ggml.addCSourceFiles(&.{
        "ggml.c",
        "ggml-backend.c",
        "ggml-quants.c",
        "ggml-alloc.c",
    }, cflags);
    if (target.isDarwin())
        ggml.linkFramework("accelerate");
    ggml.linkLibC();
    b.installArtifact(ggml);

    buildExe(
        b,
        ggml,
        .{
            .name = "whisper",
            .files = &.{
                "examples/main/main.cpp",
                "whisper.cpp",
                "examples/common.cpp",
            },
        },
    );
}

fn buildExe(b: *std.Build, ggml: *std.Build.CompileStep, binfo: BuildInfo) void {
    const exe = b.addExecutable(.{
        .name = binfo.name,
        .target = ggml.target,
        .optimize = ggml.optimize,
    });
    if (ggml.optimize != .Debug)
        exe.strip = true;
    if (exe.target.isWindows())
        exe.want_lto = false;
    if (exe.target.isDarwin())
        exe.linkFramework("accelerate");
    exe.addIncludePath(.{ .path = "." });
    exe.addIncludePath(.{ .path = "examples" });
    exe.linkLibrary(ggml);
    exe.addCSourceFiles(
        binfo.files,
        cflags,
    );

    // static-linking to llvm-libcxx
    if (exe.target.getAbi() != .msvc)
        exe.linkLibCpp()
    else
        exe.linkLibC();

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    if (!std.mem.startsWith(u8, binfo.name, "test"))
        b.installArtifact(exe);

    // This *creates* a RunStep in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step(binfo.name, b.fmt("Run the {s}", .{binfo.name}));
    run_step.dependOn(&run_cmd.step);
}

const BuildInfo = struct {
    name: []const u8,
    files: []const []const u8,
};

const cflags: []const []const u8 = &.{
    "-Wall",
    "-Wextra",
    "-Wpedantic",
    "-Wshadow",
    "-Wcast-qual",
    "-Wstrict-prototypes",
    "-Wpointer-arith",
    "-Wno-unused-function",
    "-Wno-unused-variable",
    "-Wno-gnu-binary-literal",
};

fn checkVersion() bool {
    const builtin = @import("builtin");
    if (!@hasDecl(builtin, "zig_version")) {
        return false;
    }

    const needed_version = std.SemanticVersion.parse("0.11.0") catch unreachable;
    const version = builtin.zig_version;
    const order = version.order(needed_version);
    return order != .lt;
}
