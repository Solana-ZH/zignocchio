//! Solana syscalls - Auto-generated from tools/syscall_defs.zig
//! DO NOT EDIT MANUALLY
//!
//! Syscalls are declared as external functions so the linker can emit
//! Solana-compatible syscall relocations (e.g. `sol_log_`).
//! MurmurHash3-32 values are kept in the docs for reference only.


/// sol_log_
/// Hash: 0x207559bd
/// Parameters:
///   - message: [*]const u8
///   - len: u64
pub extern fn sol_log_(message: [*]const u8, len: u64) callconv(.c) void;

/// sol_log_64_
/// Hash: 0x5c2a3178
/// Parameters:
///   - arg1: u64
///   - arg2: u64
///   - arg3: u64
///   - arg4: u64
///   - arg5: u64
pub extern fn sol_log_64_(arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64) callconv(.c) void;

/// sol_log_compute_units_
/// Hash: 0x52ba5096
pub extern fn sol_log_compute_units_() callconv(.c) void;

/// sol_log_pubkey
/// Hash: 0x7ef088ca
/// Parameters:
///   - pubkey_addr: [*]const u8
pub extern fn sol_log_pubkey(pubkey_addr: [*]const u8) callconv(.c) void;

/// sol_log_data
/// Hash: 0x7317b434
/// Parameters:
///   - data: [*]const u8
///   - data_len: u64
pub extern fn sol_log_data(data: [*]const u8, data_len: u64) callconv(.c) void;

/// sol_sha256
/// Hash: 0x11f49d86
/// Parameters:
///   - vals: [*]const u8
///   - val_len: u64
///   - hash_result: [*]u8
/// Returns: u64
pub extern fn sol_sha256(vals: [*]const u8, val_len: u64, hash_result: [*]u8) callconv(.c) u64;

/// sol_keccak256
/// Hash: 0xd7793abb
/// Parameters:
///   - vals: [*]const u8
///   - val_len: u64
///   - hash_result: [*]u8
/// Returns: u64
pub extern fn sol_keccak256(vals: [*]const u8, val_len: u64, hash_result: [*]u8) callconv(.c) u64;

/// sol_blake3
/// Hash: 0x174c5122
/// Parameters:
///   - vals: [*]const u8
///   - val_len: u64
///   - hash_result: [*]u8
/// Returns: u64
pub extern fn sol_blake3(vals: [*]const u8, val_len: u64, hash_result: [*]u8) callconv(.c) u64;

/// sol_memcpy_
/// Hash: 0x717cc4a3
/// Parameters:
///   - dst: [*]u8
///   - src: [*]const u8
///   - n: u64
pub extern fn sol_memcpy_(dst: [*]u8, src: [*]const u8, n: u64) callconv(.c) void;

/// sol_memmove_
/// Hash: 0x434371f8
/// Parameters:
///   - dst: [*]u8
///   - src: [*]const u8
///   - n: u64
pub extern fn sol_memmove_(dst: [*]u8, src: [*]const u8, n: u64) callconv(.c) void;

/// sol_memcmp_
/// Hash: 0x5fdcde31
/// Parameters:
///   - s1: [*]const u8
///   - s2: [*]const u8
///   - n: u64
///   - result: [*]i32
pub extern fn sol_memcmp_(s1: [*]const u8, s2: [*]const u8, n: u64, result: [*]i32) callconv(.c) void;

/// sol_memset_
/// Hash: 0x3770fb22
/// Parameters:
///   - s: [*]u8
///   - c: u8
///   - n: u64
pub extern fn sol_memset_(s: [*]u8, c: u8, n: u64) callconv(.c) void;

/// sol_invoke_signed_c
/// Hash: 0xa22b9c85
/// Parameters:
///   - instruction_addr: [*]const u8
///   - account_infos_addr: [*]const u8
///   - account_infos_len: u64
///   - signers_seeds_addr: [*]const u8
///   - signers_seeds_len: u64
/// Returns: u64
pub extern fn sol_invoke_signed_c(instruction_addr: [*]const u8, account_infos_addr: [*]const u8, account_infos_len: u64, signers_seeds_addr: [*]const u8, signers_seeds_len: u64) callconv(.c) u64;

/// sol_invoke_signed_rust
/// Hash: 0xd7449092
/// Parameters:
///   - instruction_addr: [*]const u8
///   - account_infos_addr: [*]const u8
///   - account_infos_len: u64
///   - signers_seeds_addr: [*]const u8
///   - signers_seeds_len: u64
/// Returns: u64
pub extern fn sol_invoke_signed_rust(instruction_addr: [*]const u8, account_infos_addr: [*]const u8, account_infos_len: u64, signers_seeds_addr: [*]const u8, signers_seeds_len: u64) callconv(.c) u64;

/// sol_set_return_data
/// Hash: 0xa226d3eb
/// Parameters:
///   - data: [*]const u8
///   - length: u64
pub extern fn sol_set_return_data(data: [*]const u8, length: u64) callconv(.c) void;

/// sol_get_return_data
/// Hash: 0x5d2245e4
/// Parameters:
///   - data: [*]u8
///   - length: u64
///   - program_id: [*]u8
/// Returns: u64
pub extern fn sol_get_return_data(data: [*]u8, length: u64, program_id: [*]u8) callconv(.c) u64;

/// sol_get_stack_height
/// Hash: 0x85532d94
/// Returns: u64
pub extern fn sol_get_stack_height() callconv(.c) u64;

/// sol_create_program_address
/// Hash: 0x9377323c
/// Parameters:
///   - seeds_addr: [*]const u8
///   - seeds_len: u64
///   - program_id_addr: [*]const u8
///   - address_bytes_addr: [*]const u8
/// Returns: u64
pub extern fn sol_create_program_address(seeds_addr: [*]const u8, seeds_len: u64, program_id_addr: [*]const u8, address_bytes_addr: [*]const u8) callconv(.c) u64;

/// sol_try_find_program_address
/// Hash: 0x48504a38
/// Parameters:
///   - seeds_addr: [*]const u8
///   - seeds_len: u64
///   - program_id_addr: [*]const u8
///   - address_bytes_addr: [*]const u8
///   - bump_seed_addr: [*]const u8
/// Returns: u64
pub extern fn sol_try_find_program_address(seeds_addr: [*]const u8, seeds_len: u64, program_id_addr: [*]const u8, address_bytes_addr: [*]const u8, bump_seed_addr: [*]const u8) callconv(.c) u64;

/// sol_secp256k1_recover
/// Hash: 0x17e40350
/// Parameters:
///   - hash: [*]const u8
///   - recovery_id: u64
///   - signature: [*]const u8
///   - result: [*]u8
/// Returns: u64
pub extern fn sol_secp256k1_recover(hash: [*]const u8, recovery_id: u64, signature: [*]const u8, result: [*]u8) callconv(.c) u64;

/// sol_poseidon
/// Hash: 0xc4947c21
/// Parameters:
///   - parameters: u64
///   - endianness: u64
///   - vals: [*]const u8
///   - val_len: u64
///   - hash_result: [*]u8
/// Returns: u64
pub extern fn sol_poseidon(parameters: u64, endianness: u64, vals: [*]const u8, val_len: u64, hash_result: [*]u8) callconv(.c) u64;

/// sol_remaining_compute_units
/// Hash: 0xedef5aee
/// Returns: u64
pub extern fn sol_remaining_compute_units() callconv(.c) u64;

/// sol_alt_bn128_group_op
/// Hash: 0xae0c318b
/// Parameters:
///   - group_op: u64
///   - input: [*]const u8
///   - input_size: u64
///   - result: [*]u8
/// Returns: u64
pub extern fn sol_alt_bn128_group_op(group_op: u64, input: [*]const u8, input_size: u64, result: [*]u8) callconv(.c) u64;

/// sol_big_mod_exp
/// Hash: 0x780e4c15
/// Parameters:
///   - params: [*]const u8
///   - result: [*]u8
/// Returns: u64
pub extern fn sol_big_mod_exp(params: [*]const u8, result: [*]u8) callconv(.c) u64;

/// sol_curve_validate_point
/// Hash: 0xaa2607ca
/// Parameters:
///   - curve_id: u64
///   - point_addr: [*]const u8
///   - result: [*]u8
/// Returns: u64
pub extern fn sol_curve_validate_point(curve_id: u64, point_addr: [*]const u8, result: [*]u8) callconv(.c) u64;

/// sol_curve_group_op
/// Hash: 0xdd1c41a6
/// Parameters:
///   - curve_id: u64
///   - group_op: u64
///   - left_input_addr: [*]const u8
///   - right_input_addr: [*]const u8
///   - result_point_addr: [*]u8
/// Returns: u64
pub extern fn sol_curve_group_op(curve_id: u64, group_op: u64, left_input_addr: [*]const u8, right_input_addr: [*]const u8, result_point_addr: [*]u8) callconv(.c) u64;

/// sol_get_sysvar
/// Hash: 0x13c1b505
/// Parameters:
///   - sysvar_id_addr: [*]const u8
///   - result: [*]u8
///   - offset: u64
///   - length: u64
/// Returns: u64
pub extern fn sol_get_sysvar(sysvar_id_addr: [*]const u8, result: [*]u8, offset: u64, length: u64) callconv(.c) u64;


// Convenience helpers

/// Log a message (wrapper around sol_log_)
pub fn log(message: []const u8) void {
    sol_log_(message.ptr, message.len);
}

/// Log a single u64 value
pub fn log_u64(value: u64) void {
    sol_log_64_(value, 0, 0, 0, 0);
}

/// Log current compute units consumed
pub fn logComputeUnits() void {
    sol_log_compute_units_();
}

/// Get remaining compute units
pub fn getRemainingComputeUnits() u64 {
    return sol_remaining_compute_units();
}
