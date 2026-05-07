//! Runtime composition helpers inspired by Pinocchio's allocator / panic setup.
//!
//! Zig does not use Rust-style global allocator and panic-handler macros, but we
//! can still provide the same explicit composition points:
//!
//! - a default bump allocator (`sdk.BumpAllocator`)
//! - an explicit allocator that rejects all dynamic allocation (`NoAllocator`)
//! - manual heap reservation via `NoAllocator.allocateUnchecked(...)`
//! - panic helper functions that programs can forward their root `panic(...)` to
//!
//! ## Example: no-allocation lazy program
//!
//! ```zig
//! const std = @import("std");
//! const sdk = @import("sdk");
//!
//! pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
//!     sdk.runtime.noStdPanic(msg, trace, ret_addr);
//! }
//!
//! export fn entrypoint(input: [*]u8) u64 {
//!     return @call(.always_inline, sdk.createLazyEntrypoint(processInstruction), .{input});
//! }
//!
//! fn processInstruction(context: *sdk.lazy.EntryContext) sdk.ProgramResult {
//!     _ = context;
//!     const scratch = sdk.runtime.NoAllocator.allocateUnchecked([64]u8, 0);
//!     scratch.* = [_]u8{0} ** 64;
//!     return {};
//! }
//! ```

const builtin = @import("builtin");
const std = @import("std");
const allocator = @import("allocator.zig");
const entrypoint = @import("entrypoint.zig");
const syscalls = @import("syscalls.zig");

const has_solana_tag = @hasField(std.Target.Os.Tag, "solana");

fn isSolanaTarget() bool {
    return comptime if (has_solana_tag) builtin.target.os.tag == .solana else false;
}

pub const BumpAllocator = allocator.BumpAllocator;
pub const HEAP_START_ADDRESS = entrypoint.HEAP_START_ADDRESS;
pub const HEAP_LENGTH = entrypoint.HEAP_LENGTH;

/// Allocator that rejects all dynamic allocation attempts.
///
/// This mirrors Pinocchio's `no_allocator!` intent: if code tries to allocate,
/// the program traps immediately instead of silently consuming heap.
pub const NoAllocator = struct {
    pub fn init() NoAllocator {
        return .{};
    }

    /// Allocate memory for `T` at a fixed offset into the Solana heap window.
    ///
    /// The caller must ensure that allocations do not overlap and that zeroed
    /// memory is a valid initial state for `T` if the allocation is used before
    /// explicit initialization.
    pub fn allocateUnchecked(comptime T: type, offset: usize) *align(@alignOf(T)) T {
        return @ptrFromInt(calculateOffset(T, offset));
    }

    /// Compute the address that `allocateUnchecked(T, offset)` would use.
    pub fn calculateOffset(comptime T: type, offset: usize) usize {
        const start = @as(usize, @intCast(HEAP_START_ADDRESS)) + offset;
        const end = start + @sizeOf(T);

        std.debug.assert(end <= @as(usize, @intCast(HEAP_START_ADDRESS)) + HEAP_LENGTH);
        std.debug.assert(start % @alignOf(T) == 0);

        return start;
    }

    pub fn alloc(self: *NoAllocator, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = self;
        _ = len;
        _ = ptr_align;
        _ = ret_addr;
        @panic("NoAllocator::alloc() does not allocate memory");
    }

    pub fn resize(self: *NoAllocator, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = self;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false;
    }

    pub fn free(self: *NoAllocator, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = self;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
    }

    pub fn allocator(self: *NoAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }
};

/// Panic helper for programs that want a lightweight panic report and then trap.
///
/// This is the closest Zig-side equivalent to Pinocchio's default panic hook.
pub fn defaultPanic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = trace;
    _ = ret_addr;

    if (isSolanaTarget()) {
        const panicked = "** PANICKED **";
        syscalls.sol_log_(panicked.ptr, panicked.len);
        syscalls.sol_log_(msg.ptr, msg.len);
    }

    @trap();
}

/// Panic helper for direct-SBF / no-allocation programs.
///
/// Zig does not distinguish `std` and `no_std` panic handlers the same way as
/// Rust, so today this simply aliases the same log-and-trap behavior.
pub fn noStdPanic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    defaultPanic(msg, trace, ret_addr);
}

test "NoAllocator.calculateOffset returns expected heap-relative address" {
    const addr = NoAllocator.calculateOffset(u64, 16);
    try std.testing.expectEqual(@as(usize, @intCast(HEAP_START_ADDRESS)) + 16, addr);
}

test "NoAllocator.allocateUnchecked uses calculateOffset" {
    const ptr = NoAllocator.allocateUnchecked(u64, 16);
    try std.testing.expectEqual(NoAllocator.calculateOffset(u64, 16), @intFromPtr(ptr));
}
