//! Logging utilities for Solana programs.
//!
//! This module keeps the existing thin syscall wrappers, and now also exposes a
//! fixed-buffer `Logger(N)` helper inspired by `pinocchio-log`.
//!
//! The goals are:
//!
//! - no heap allocation
//! - predictable truncation behavior (`'@'` marks buffer overflow)
//! - simple append-style formatting for hot-path-friendly diagnostics

const builtin = @import("builtin");
const std = @import("std");
const types = @import("types.zig");
const syscalls = @import("syscalls.zig");

const TRUNCATED: u8 = '@';
const has_solana_tag = @hasField(std.Target.Os.Tag, "solana");

fn isSolanaTarget() bool {
    return comptime if (has_solana_tag) builtin.target.os.tag == .solana else false;
}

/// Formatting arguments supported by `Logger.appendWithArgs(...)`.
pub const Argument = union(enum) {
    /// Insert a decimal point for integer values using the given precision.
    ///
    /// Example: `1_234_567` with `Precision(3)` logs as `1234.567`.
    Precision: u8,
    /// Truncate string-like data at the end and append `...` when possible.
    TruncateEnd: usize,
    /// Truncate string-like data at the start and prepend `...` when possible.
    TruncateStart: usize,
};

/// Fixed-buffer append-style logger.
pub fn Logger(comptime BUFFER: usize) type {
    return struct {
        buffer: [BUFFER]u8 = [_]u8{0} ** BUFFER,
        len: usize = 0,
        truncated: bool = false,

        const Self = @This();

        pub fn init() Self {
            return .{};
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
            self.truncated = false;
        }

        pub fn isFull(self: *const Self) bool {
            return self.len == BUFFER;
        }

        pub fn remaining(self: *const Self) usize {
            return BUFFER - self.len;
        }

        pub fn bytes(self: *const Self) []const u8 {
            return self.buffer[0..self.len];
        }

        pub fn log(self: *const Self) void {
            logMessage(self.bytes());
        }

        pub fn append(self: *Self, value: anytype) *Self {
            return self.appendWithArgs(value, &.{});
        }

        pub fn appendWithArgs(self: *Self, value: anytype, args: []const Argument) *Self {
            self.appendAny(value, args);
            return self;
        }

        pub fn appendPubkeyHex(self: *Self, pubkey: *const types.Pubkey) *Self {
            for (pubkey.*) |byte| {
                self.appendByte(hexDigit(byte >> 4));
                self.appendByte(hexDigit(byte & 0x0f));
            }
            return self;
        }

        fn appendAny(self: *Self, value: anytype, args: []const Argument) void {
            const T = @TypeOf(value);
            switch (@typeInfo(T)) {
                .bool => self.appendBytes(if (value) "true" else "false"),
                .int => |int_info| {
                    const precision = findPrecision(args);
                    if (int_info.signedness == .signed) {
                        self.appendSigned(value, precision);
                    } else {
                        self.appendUnsigned(value, precision);
                    }
                },
                .comptime_int => {
                    const precision = findPrecision(args);
                    if (value < 0) {
                        self.appendSigned(@as(i128, value), precision);
                    } else {
                        self.appendUnsigned(@as(u128, value), precision);
                    }
                },
                .array => |array_info| {
                    if (array_info.child == u8) {
                        self.appendStringLike(value[0..], args);
                    } else {
                        @compileError("sdk.log.Logger.append only supports byte arrays, booleans, and integers");
                    }
                },
                .pointer => |pointer_info| {
                    switch (pointer_info.size) {
                        .slice => {
                            if (pointer_info.child == u8) {
                                self.appendStringLike(value, args);
                            } else {
                                @compileError("sdk.log.Logger.append only supports byte slices for pointer types");
                            }
                        },
                        .one => switch (@typeInfo(pointer_info.child)) {
                            .array => |array_info| {
                                if (array_info.child == u8) {
                                    self.appendStringLike(value[0..array_info.len], args);
                                } else {
                                    @compileError("sdk.log.Logger.append only supports pointers to byte arrays");
                                }
                            },
                            else => @compileError("sdk.log.Logger.append does not support this pointer type; use appendPubkeyHex or append a string/int"),
                        },
                        else => @compileError("sdk.log.Logger.append does not support many/c/sentinel pointers"),
                    }
                },
                else => @compileError("sdk.log.Logger.append only supports strings, byte slices, booleans, and integers"),
            }
        }

        fn appendStringLike(self: *Self, message_bytes: []const u8, args: []const Argument) void {
            if (findTruncateEnd(args)) |limit| {
                self.appendTruncateEnd(message_bytes, limit);
                return;
            }
            if (findTruncateStart(args)) |limit| {
                self.appendTruncateStart(message_bytes, limit);
                return;
            }
            self.appendBytes(message_bytes);
        }

        fn appendTruncateEnd(self: *Self, message_bytes: []const u8, limit: usize) void {
            if (message_bytes.len <= limit) {
                self.appendBytes(message_bytes);
                return;
            }
            if (limit <= 3) {
                self.appendBytes(message_bytes[0..@min(limit, message_bytes.len)]);
                return;
            }
            self.appendBytes(message_bytes[0 .. limit - 3]);
            self.appendBytes("...");
        }

        fn appendTruncateStart(self: *Self, message_bytes: []const u8, limit: usize) void {
            if (message_bytes.len <= limit) {
                self.appendBytes(message_bytes);
                return;
            }
            if (limit <= 3) {
                self.appendBytes(message_bytes[message_bytes.len - @min(limit, message_bytes.len) ..]);
                return;
            }
            self.appendBytes("...");
            self.appendBytes(message_bytes[message_bytes.len - (limit - 3) ..]);
        }

        fn appendUnsigned(self: *Self, value: anytype, precision: usize) void {
            self.appendUnsignedMagnitude(@as(u128, @intCast(value)), precision);
        }

        fn appendSigned(self: *Self, value: anytype, precision: usize) void {
            const T = @TypeOf(value);
            if (value < 0) {
                self.appendByte('-');
                const U = std.meta.Int(.unsigned, @bitSizeOf(T));
                const magnitude: U = @as(U, @intCast(-(value + 1))) + 1;
                self.appendUnsignedMagnitude(@as(u128, magnitude), precision);
            } else {
                self.appendUnsignedMagnitude(@as(u128, @intCast(value)), precision);
            }
        }

        fn appendUnsignedMagnitude(self: *Self, value: u128, precision: usize) void {
            var digits_buffer: [39]u8 = undefined;
            const digits = unsignedToDecimal(value, &digits_buffer);

            if (precision == 0) {
                self.appendBytes(digits);
                return;
            }

            if (digits.len > precision) {
                const integer_len = digits.len - precision;
                self.appendBytes(digits[0..integer_len]);
                self.appendByte('.');
                self.appendBytes(digits[integer_len..]);
                return;
            }

            self.appendBytes("0.");
            var padding = precision - digits.len;
            while (padding > 0) : (padding -= 1) {
                self.appendByte('0');
            }
            self.appendBytes(digits);
        }

        fn appendBytes(self: *Self, message_bytes: []const u8) void {
            for (message_bytes) |byte| {
                self.appendByte(byte);
            }
        }

        fn appendByte(self: *Self, byte: u8) void {
            if (self.truncated) return;
            if (self.len < BUFFER) {
                self.buffer[self.len] = byte;
                self.len += 1;
                return;
            }
            self.truncated = true;
            self.len = BUFFER;
            if (BUFFER > 0) {
                self.buffer[BUFFER - 1] = TRUNCATED;
            }
        }
    };
}

fn unsignedToDecimal(value: u128, buffer: *[39]u8) []const u8 {
    var v = value;
    var index = buffer.len;

    if (v == 0) {
        index -= 1;
        buffer[index] = '0';
        return buffer[index..];
    }

    while (v > 0) {
        index -= 1;
        buffer[index] = '0' + @as(u8, @intCast(v % 10));
        v /= 10;
    }

    return buffer[index..];
}

fn findPrecision(args: []const Argument) usize {
    for (args) |arg| {
        switch (arg) {
            .Precision => |precision| return precision,
            else => {},
        }
    }
    return 0;
}

fn findTruncateEnd(args: []const Argument) ?usize {
    for (args) |arg| {
        switch (arg) {
            .TruncateEnd => |limit| return limit,
            else => {},
        }
    }
    return null;
}

fn findTruncateStart(args: []const Argument) ?usize {
    for (args) |arg| {
        switch (arg) {
            .TruncateStart => |limit| return limit,
            else => {},
        }
    }
    return null;
}

fn hexDigit(value: u8) u8 {
    return if (value < 10) '0' + value else 'a' + (value - 10);
}

/// Log a message.
pub fn logMessage(message: []const u8) void {
    if (comptime isSolanaTarget()) {
        syscalls.log(message);
    } else {
        std.debug.print("{s}\n", .{message});
    }
}

pub const log = logMessage;

/// Log a single u64 value.
pub fn logU64(value: u64) void {
    if (comptime isSolanaTarget()) {
        syscalls.log_u64(value);
    } else {
        std.debug.print("{}\n", .{value});
    }
}

/// Log 5 u64 values.
pub fn log64(arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64) void {
    if (comptime isSolanaTarget()) {
        syscalls.sol_log_64_(arg1, arg2, arg3, arg4, arg5);
    } else {
        std.debug.print("{} {} {} {} {}\n", .{ arg1, arg2, arg3, arg4, arg5 });
    }
}

/// Log a pubkey.
pub fn logPubkey(pubkey: *const types.Pubkey) void {
    if (comptime isSolanaTarget()) {
        syscalls.sol_log_pubkey(@as([*]const u8, @ptrCast(pubkey)));
        return;
    }

    var logger = Logger(64).init();
    _ = logger.appendPubkeyHex(pubkey);
    logMessage(logger.bytes());
}

/// Log current compute units consumed.
pub fn logComputeUnits() void {
    if (comptime isSolanaTarget()) {
        syscalls.logComputeUnits();
    }
}

/// Get remaining compute units.
pub fn getRemainingComputeUnits() u64 {
    if (comptime isSolanaTarget()) {
        return syscalls.getRemainingComputeUnits();
    }
    return 0;
}

test "Logger appends strings and integers" {
    var logger = Logger(32).init();
    _ = logger.append("balance=").append(@as(u64, 42));
    try std.testing.expectEqualStrings("balance=42", logger.bytes());
}

test "Logger marks truncation with at sign" {
    var logger = Logger(8).init();
    _ = logger.append("Hello ").append("world!");
    try std.testing.expectEqualStrings("Hello w@", logger.bytes());
}

test "Logger supports precision for integers" {
    var logger = Logger(32).init();
    _ = logger.appendWithArgs(@as(u64, 1_234_567), &.{.{ .Precision = 3 }});
    try std.testing.expectEqualStrings("1234.567", logger.bytes());
}

test "Logger supports truncate start/end for strings" {
    var end_logger = Logger(32).init();
    _ = end_logger.appendWithArgs("0123456789", &.{.{ .TruncateEnd = 6 }});
    try std.testing.expectEqualStrings("012...", end_logger.bytes());

    var start_logger = Logger(32).init();
    _ = start_logger.appendWithArgs("0123456789", &.{.{ .TruncateStart = 6 }});
    try std.testing.expectEqualStrings("...789", start_logger.bytes());
}

test "Logger appends signed values and hex pubkeys" {
    var logger = Logger(96).init();
    const key: types.Pubkey = .{0xab} ** 32;
    _ = logger.append(@as(i64, -25)).append(" ").appendPubkeyHex(&key);
    try std.testing.expect(std.mem.startsWith(u8, logger.bytes(), "-25 abab"));
    try std.testing.expectEqual(@as(usize, 68), logger.bytes().len);
}
