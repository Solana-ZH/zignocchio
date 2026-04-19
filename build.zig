// zignocchio build.zig — direct SBF build pipeline
//
// This project now targets the solana-zig fork directly:
//   1. `b.addLibrary` with `sbf-solana` triple + selected SBF CPU features
//   2. custom `bpf.ld` linker script to discard unsupported sections
//   3. final artifact emitted as `zig-out/lib/<example>.so`
//
// Invoke with the fork Zig binary, e.g.
//   $SOLANA_ZIG build -Dexample=hello

const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = .ReleaseSmall;

    const example_name = b.option(
        []const u8,
        "example",
        "Example to build (hello / hello-lazy / counter / counter-lazy / vault / vault-lazy / transfer-sol / transfer-sol-lazy / transfer-owned / transfer-owned-lazy / pda-storage / pda-storage-lazy / token-vault / token-vault-lazy / escrow / escrow-lazy / noop / noop-lazy / logonly / logonly-lazy)",
    ) orelse "counter";
    const skip_program_build = b.option(
        bool,
        "skip-program-build",
        "Skip direct-SBF artifact build and only configure host-side test steps.",
    ) orelse false;

    if (!skip_program_build) {
        const example_path = b.fmt("examples/{s}/lib.zig", .{example_name});
        try buildForkSbf(b, example_name, example_path, optimize);
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

fn buildForkSbf(
    b: *std.Build,
    example_name: []const u8,
    example_path: []const u8,
    optimize: std.builtin.OptimizeMode,
) !void {
    const cpu_features = b.option(
        []const u8,
        "sbf-cpu",
        "SBF CPU model: baseline (default) / generic / v1 / v2 / v3. v2+ requires an Agave 4.x+ runtime with SBF feature gates enabled.",
    ) orelse "baseline";

    const query = std.Target.Query.parse(.{
        .arch_os_abi = "sbf-solana-none",
        .cpu_features = cpu_features,
    }) catch |err| {
        std.log.err("direct SBF builds require the solana-zig fork (see README). Parse error: {s}", .{@errorName(err)});
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
