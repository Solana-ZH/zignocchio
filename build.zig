// zignocchio build.zig — dual backend (elf2sbpf default, fork-sbf opt-in)
//
// Backends:
//   - `elf2sbpf` (default, stock Zig):
//       1. `zig build-lib -femit-llvm-bc -fno-emit-bin`  → entrypoint.bc
//       2. `zig cc -c entrypoint.bc -mllvm -bpf-stack-size=4096` → entrypoint.o
//       3. `elf2sbpf entrypoint.o program.so`  → Solana SBPF .so
//
//   - `fork-sbf` (requires solana-zig fork: `.cpu_arch = .sbf`):
//       1. `b.addLibrary` with `sbf-solana` triple + `mcpu=v2` feature set
//       2. bpf.ld linker script to discard .eh_frame and wire PHDRs
//       Output goes straight to `zig-out/lib/<example>.so` — no separate
//       post-processing.
//
// Select with `-Dbackend=fork-sbf` (or export BACKEND=fork-sbf).
// When `fork-sbf` is selected, `-Delf2sbpf-bin` is ignored.

const std = @import("std");

const Backend = enum { elf2sbpf, @"fork-sbf" };

pub fn build(b: *std.Build) !void {
    const optimize = .ReleaseSmall;

    const example_name = b.option(
        []const u8,
        "example",
        "Example to build (hello / counter / vault / transfer-sol / pda-storage / token-vault / escrow / noop / logonly)",
    ) orelse "counter";

    const backend = b.option(
        Backend,
        "backend",
        "Build backend: elf2sbpf (default, stock Zig) or fork-sbf (solana-zig fork)",
    ) orelse .elf2sbpf;

    const example_path = b.fmt("examples/{s}/lib.zig", .{example_name});

    switch (backend) {
        .elf2sbpf => try buildElf2sbpf(b, example_name, example_path),
        .@"fork-sbf" => try buildForkSbf(b, example_name, example_path, optimize),
    }

    // Host CLI — only on elf2sbpf (stock Zig) backend, since it uses
    // `std.process.Init` which is 0.16-stable-only. The fork Zig snapshot
    // (0.16.0-dev.0+cf5f8113c) predates that API.
    if (backend == .elf2sbpf) {
        const cli_module = b.createModule(.{
            .root_source_file = b.path("cli/src/main.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        });
        cli_module.link_libc = true;
        const cli_exe = b.addExecutable(.{
            .name = "zignocchio-cli",
            .root_module = cli_module,
        });
        b.installArtifact(cli_exe);
    }

    // SDK unit tests — always host target.
    const test_step = b.step("test", "Run unit tests");
    const sdk_module = b.createModule(.{
        .root_source_file = b.path("sdk/zignocchio.zig"),
    });
    const test_module = b.createModule(.{
        .root_source_file = b.path("examples/hello/lib.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    test_module.addImport("sdk", sdk_module);
    const lib_unit_tests = b.addTest(.{
        .root_module = test_module,
    });
    const run_unit_tests = b.addRunArtifact(lib_unit_tests);
    test_step.dependOn(&run_unit_tests.step);
}

fn buildElf2sbpf(
    b: *std.Build,
    example_name: []const u8,
    example_path: []const u8,
) !void {
    const elf2sbpf_bin = b.option(
        []const u8,
        "elf2sbpf-bin",
        "Path to the elf2sbpf executable (default: look up on PATH)",
    ) orelse "elf2sbpf";

    const bitcode_path = "entrypoint.bc";
    const gen_bitcode = b.addSystemCommand(&.{
        b.graph.zig_exe,                   "build-lib",
        "-target",                         "bpfel-freestanding",
        "-O",                              "ReleaseSmall",
        "-femit-llvm-bc=" ++ bitcode_path, "-fno-emit-bin",
        "--dep",                           "sdk",
        b.fmt("-Mroot={s}", .{example_path}),
        "-Msdk=sdk/zignocchio.zig",
    });

    const mkdir_step = b.addSystemCommand(&.{ "mkdir", "-p", "zig-out/lib" });

    const obj_path = b.fmt("zig-out/lib/{s}.o", .{example_name});
    const zig_cc = b.addSystemCommand(&.{
        b.graph.zig_exe,       "cc",
        "-target",             "bpfel-freestanding",
        "-mcpu=v2",            "-O2",
        "-mllvm",              "-bpf-stack-size=4096",
        "-c",                  bitcode_path,
        "-o",                  obj_path,
    });
    zig_cc.step.dependOn(&gen_bitcode.step);
    zig_cc.step.dependOn(&mkdir_step.step);

    const program_so_path = b.fmt("zig-out/lib/{s}.so", .{example_name});
    const link_program = b.addSystemCommand(&.{
        elf2sbpf_bin, obj_path, program_so_path,
    });
    link_program.step.dependOn(&zig_cc.step);
    b.getInstallStep().dependOn(&link_program.step);
}

fn buildForkSbf(
    b: *std.Build,
    example_name: []const u8,
    example_path: []const u8,
    optimize: std.builtin.OptimizeMode,
) !void {
    // Use string-form target query so this file still compiles on stock
    // Zig 0.16 (which doesn't know `.sbf` as a cpu_arch). On stock Zig the
    // parse below will fail at runtime with a clear "unknown CPU arch"
    // error, steering the user to -Dbackend=elf2sbpf or the fork.
    const cpu_features = b.option(
        []const u8,
        "sbf-cpu",
        "SBF CPU model: generic / v1 / v2 (default) / v3. " ++
            "v2+ requires an Agave 4.x+ runtime with SBF feature gates enabled " ++
            "(mollusk 0.12.1-agave-4.0's default BPFLoaderUpgradeable does not).",
    ) orelse "v2";

    const query = std.Target.Query.parse(.{
        .arch_os_abi = "sbf-solana-none",
        .cpu_features = cpu_features,
    }) catch |err| {
        std.log.err("fork-sbf backend requires the solana-zig fork (see README). Parse error: {s}", .{@errorName(err)});
        return error.ForkZigRequired;
    };
    const target = b.resolveTargetQuery(query);

    const sdk_module = b.createModule(.{
        .root_source_file = b.path("sdk/zignocchio.zig"),
        .target = target,
        .optimize = optimize,
    });

    const program_mod = b.createModule(.{
        .root_source_file = b.path(example_path),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sdk", .module = sdk_module },
        },
    });
    program_mod.pic = true;
    program_mod.strip = true;

    const program = b.addLibrary(.{
        .name = example_name,
        .linkage = .dynamic,
        .root_module = program_mod,
    });
    program.entry = .{ .symbol_name = "entrypoint" };
    program.stack_size = 4096;
    program.link_z_notext = true;

    const write_file_step = b.addWriteFiles();
    const linker_script = write_file_step.add("bpf.ld",
        \\PHDRS
        \\{
        \\text PT_LOAD  ;
        \\rodata PT_LOAD ;
        \\data PT_LOAD ;
        \\dynamic PT_DYNAMIC ;
        \\}
        \\
        \\SECTIONS
        \\{
        \\. = SIZEOF_HEADERS;
        \\.text : { *(.text*) } :text
        \\.rodata : { *(.rodata*) } :rodata
        \\.data.rel.ro : { *(.data.rel.ro*) } :rodata
        \\.dynamic : { *(.dynamic) } :dynamic
        \\.dynsym : { *(.dynsym) } :data
        \\.dynstr : { *(.dynstr) } :data
        \\.rel.dyn : { *(.rel.dyn) } :data
        \\/DISCARD/ : {
        \\*(.eh_frame*)
        \\*(.gnu.hash*)
        \\*(.hash*)
        \\}
        \\}
    );
    program.step.dependOn(&write_file_step.step);
    program.setLinkerScript(linker_script);

    const so = program.getEmittedBin();
    const install = b.addInstallLibFile(so, b.fmt("{s}.so", .{example_name}));
    b.getInstallStep().dependOn(&install.step);
}
