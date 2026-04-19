//! Template strings for zignocchio-cli

pub const build_zig =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) !void {
    \\    const optimize = .ReleaseSmall;
    \\    try buildDirectSbf(b, "src/lib.zig", optimize);
    \\
    \\    const test_step = b.step("test", "Run unit tests");
    \\    const sdk_module = b.createModule(.{
    \\        .root_source_file = b.path("sdk/zignocchio.zig"),
    \\    });
    \\    const test_module = b.createModule(.{
    \\        .root_source_file = b.path("src/lib.zig"),
    \\        .target = b.graph.host,
    \\        .optimize = optimize,
    \\    });
    \\    test_module.addImport("sdk", sdk_module);
    \\    const lib_unit_tests = b.addTest(.{
    \\        .root_module = test_module,
    \\    });
    \\    const run_unit_tests = b.addRunArtifact(lib_unit_tests);
    \\    test_step.dependOn(&run_unit_tests.step);
    \\}
    \\
    \\fn buildDirectSbf(b: *std.Build, lib_path: []const u8, optimize: std.builtin.OptimizeMode) !void {
    \\    const cpu_features = b.option(
    \\        []const u8,
    \\        "sbf-cpu",
    \\        "SBF CPU model: baseline (default) / generic / v1 / v2 / v3. v2+ requires an Agave 4.x+ runtime with SBF feature gates enabled.",
    \\    ) orelse "baseline";
    \\
    \\    const query = std.Target.Query.parse(.{
    \\        .arch_os_abi = "sbf-solana-none",
    \\        .cpu_features = cpu_features,
    \\    }) catch |err| {
    \\        std.log.err("direct SBF builds require the solana-zig fork (see README). Parse error: {s}", .{@errorName(err)});
    \\        return error.ForkZigRequired;
    \\    };
    \\    const target = b.resolveTargetQuery(query);
    \\
    \\    const sdk_module = b.createModule(.{
    \\        .root_source_file = b.path("sdk/zignocchio.zig"),
    \\        .target = target,
    \\        .optimize = optimize,
    \\    });
    \\
    \\    const program_mod = b.createModule(.{
    \\        .root_source_file = b.path(lib_path),
    \\        .target = target,
    \\        .optimize = optimize,
    \\        .imports = &.{
    \\            .{ .name = "sdk", .module = sdk_module },
    \\        },
    \\    });
    \\    program_mod.pic = true;
    \\    program_mod.strip = true;
    \\
    \\    const program = b.addLibrary(.{
    \\        .name = "program",
    \\        .linkage = .dynamic,
    \\        .root_module = program_mod,
    \\    });
    \\    program.entry = .{ .symbol_name = "entrypoint" };
    \\    program.stack_size = 4096;
    \\    program.link_z_notext = true;
    \\
    \\    const write_file_step = b.addWriteFiles();
    \\    const linker_script = write_file_step.add("bpf.ld",
    \\        \\PHDRS
    \\        \\{
    \\        \\text PT_LOAD  ;
    \\        \\rodata PT_LOAD ;
    \\        \\data PT_LOAD ;
    \\        \\dynamic PT_DYNAMIC ;
    \\        \\}
    \\        \\
    \\        \\SECTIONS
    \\        \\{
    \\        \\. = SIZEOF_HEADERS;
    \\        \\.text : { *(.text*) } :text
    \\        \\.rodata : { *(.rodata*) } :rodata
    \\        \\.data.rel.ro : { *(.data.rel.ro*) } :rodata
    \\        \\.dynamic : { *(.dynamic) } :dynamic
    \\        \\.dynsym : { *(.dynsym) } :data
    \\        \\.dynstr : { *(.dynstr) } :data
    \\        \\.rel.dyn : { *(.rel.dyn) } :data
    \\        \\/DISCARD/ : {
    \\        \\*(.eh_frame*)
    \\        \\*(.gnu.hash*)
    \\        \\*(.hash*)
    \\        \\}
    \\        \\}
    \\    );
    \\    program.step.dependOn(&write_file_step.step);
    \\    program.setLinkerScript(linker_script);
    \\
    \\    const so = program.getEmittedBin();
    \\    const install = b.addInstallLibFile(so, "program.so");
    \\    b.getInstallStep().dependOn(&install.step);
    \\}
    \\
;

pub const lib_zig =
    \\//! %%NAME%% program entrypoint
    \\
    \\const sdk = @import("sdk");
    \\
    \\pub const CounterState = extern struct {
    \\    pub const DISCRIMINATOR: u8 = 0xC0;
    \\    discriminator: u8,
    \\    owner: sdk.Pubkey,
    \\    count: u64,
    \\};
    \\
    \\pub const InitializeAccounts = struct {
    \\    owner: sdk.AccountInfo,
    \\    counter: sdk.AccountInfo,
    \\    system_program: sdk.AccountInfo,
    \\};
    \\
    \\fn validateInitialize(
    \\    accounts: []sdk.AccountInfo,
    \\    program_id: *const sdk.Pubkey,
    \\) sdk.ProgramError!InitializeAccounts {
    \\    if (accounts.len < 3) return error.NotEnoughAccountKeys;
    \\    const owner = accounts[0];
    \\    const counter = accounts[1];
    \\    const system_program = accounts[2];
    \\
    \\    try sdk.guard.assert_signer(owner);
    \\    try sdk.guard.assert_writable(counter);
    \\
    \\    var system_program_id: sdk.Pubkey = undefined;
    \\    sdk.system.getSystemProgramId(&system_program_id);
    \\    try sdk.guard.assert_owner(counter, &system_program_id);
    \\
    \\    if (counter.lamports() != 0) return error.AccountAlreadyInitialized;
    \\
    \\    const owner_key = owner.key().*;
    \\    const seeds = &[_][]const u8{ "counter", &owner_key };
    \\    var expected_counter: sdk.Pubkey = undefined;
    \\    var bump: u8 = undefined;
    \\    try sdk.findProgramAddress(seeds, program_id, &expected_counter, &bump);
    \\    if (!sdk.pubkeyEq(counter.key(), &expected_counter)) return error.IncorrectProgramId;
    \\
    \\    if (!sdk.pubkeyEq(system_program.key(), &system_program_id)) return error.IncorrectProgramId;
    \\
    \\    return InitializeAccounts{ .owner = owner, .counter = counter, .system_program = system_program };
    \\}
    \\
    \\pub fn processInitialize(
    \\    program_id: *const sdk.Pubkey,
    \\    accounts: []sdk.AccountInfo,
    \\) sdk.ProgramResult {
    \\    const validated = try validateInitialize(accounts, program_id);
    \\
    \\    const space: u64 = @sizeOf(CounterState);
    \\    const rent_exempt = ((space / 256) + 1) * 6960;
    \\    const lamports = rent_exempt;
    \\
    \\    const owner_key = validated.owner.key().*;
    \\    const seeds = &[_][]const u8{ "counter", &owner_key };
    \\    var expected_counter: sdk.Pubkey = undefined;
    \\    var bump: u8 = undefined;
    \\    try sdk.findProgramAddress(seeds, program_id, &expected_counter, &bump);
    \\
    \\    const signers_seeds = &[_][]const u8{
    \\        "counter",
    \\        &owner_key,
    \\        &[_]u8{bump},
    \\    };
    \\
    \\    try sdk.system.createAccountSigned(
    \\        validated.owner,
    \\        validated.counter,
    \\        program_id,
    \\        space,
    \\        lamports,
    \\        signers_seeds,
    \\    );
    \\
    \\    const Schema = sdk.schema.AccountSchema(CounterState);
    \\    const data = validated.counter.borrowMutDataUnchecked();
    \\    var state = Schema.from_bytes_unchecked(data);
    \\    state.discriminator = CounterState.DISCRIMINATOR;
    \\    state.owner = validated.owner.key().*;
    \\    state.count = 0;
    \\}
    \\
    \\pub const INSTRUCTION_INIT = 0;
    \\
    \\pub fn processInstruction(
    \\    program_id: *const sdk.Pubkey,
    \\    accounts: []sdk.AccountInfo,
    \\    instruction_data: []const u8,
    \\) sdk.ProgramResult {
