//! Instructions sysvar parsing helpers.

const sdk = @import("../zignocchio.zig");
const std = @import("std");

/// Instructions sysvar ID `Sysvar1nstructions1111111111111111111111111`.
pub const ID: sdk.Pubkey = .{
    0x06, 0xa7, 0xd5, 0x17, 0x18, 0x7b, 0xd1, 0x66,
    0x35, 0xda, 0xd4, 0x04, 0x55, 0xfd, 0xc2, 0xc0,
    0xc1, 0x24, 0xc6, 0x8f, 0x21, 0x56, 0x75, 0xa5,
    0xdb, 0xba, 0xcb, 0x5f, 0x08, 0x00, 0x00, 0x00,
};

const IS_SIGNER: u8 = 0b00000001;
const IS_WRITABLE: u8 = 0b00000010;

fn readU16(bytes: []const u8, offset: usize) sdk.ProgramError!u16 {
    if (offset + 2 > bytes.len) return error.InvalidInstructionData;
    return std.mem.readInt(u16, bytes[offset .. offset + 2], .little);
}

pub const Instructions = struct {
    data: []const u8,

    pub fn initUnchecked(data: []const u8) Instructions {
        return .{ .data = data };
    }

    pub fn fromAccountInfo(account: sdk.AccountInfo) sdk.ProgramError!Instructions {
        if (!sdk.pubkeyEq(account.key(), &ID)) return error.UnsupportedSysvar;
        return .{ .data = account.borrowDataUnchecked() };
    }

    pub fn numInstructions(self: Instructions) sdk.ProgramError!usize {
        return try readU16(self.data, 0);
    }

    pub fn loadCurrentIndex(self: Instructions) sdk.ProgramError!u16 {
        if (self.data.len < 2) return error.InvalidInstructionData;
        return try readU16(self.data, self.data.len - 2);
    }

    pub fn loadInstructionAt(self: Instructions, index: usize) sdk.ProgramError!IntrospectedInstruction {
        const total = try self.numInstructions();
        if (index >= total) return error.InvalidInstructionData;
        const offset = try readU16(self.data, 2 + index * 2);
        if (offset >= self.data.len) return error.InvalidInstructionData;
        return .{ .raw = self.data[offset..] };
    }

    pub fn getInstructionRelative(self: Instructions, index_relative_to_current: i64) sdk.ProgramError!IntrospectedInstruction {
        const current = @as(i64, @intCast(try self.loadCurrentIndex()));
        const index = current + index_relative_to_current;
        if (index < 0) return error.InvalidInstructionData;
        return self.loadInstructionAt(@intCast(index));
    }
};

pub const IntrospectedInstruction = struct {
    raw: []const u8,

    pub fn numAccountMetas(self: IntrospectedInstruction) sdk.ProgramError!usize {
        return try readU16(self.raw, 0);
    }

    pub fn getInstructionAccountAt(self: IntrospectedInstruction, index: usize) sdk.ProgramError!IntrospectedInstructionAccount {
        const total = try self.numAccountMetas();
        if (index >= total) return error.InvalidArgument;
        const offset = 2 + index * IntrospectedInstructionAccount.LEN;
        if (offset + IntrospectedInstructionAccount.LEN > self.raw.len) return error.InvalidInstructionData;

        var key: sdk.Pubkey = undefined;
        @memcpy(&key, self.raw[offset + 1 .. offset + 33]);
        return .{ .flags = self.raw[offset], .key = key };
    }

    pub fn getProgramId(self: IntrospectedInstruction) sdk.ProgramError!*const sdk.Pubkey {
        const total = try self.numAccountMetas();
        const offset = 2 + total * IntrospectedInstructionAccount.LEN;
        if (offset + 32 > self.raw.len) return error.InvalidInstructionData;
        return @as(*const sdk.Pubkey, @ptrCast(self.raw[offset .. offset + 32].ptr));
    }

    pub fn getInstructionData(self: IntrospectedInstruction) sdk.ProgramError![]const u8 {
        const total = try self.numAccountMetas();
        const offset = 2 + total * IntrospectedInstructionAccount.LEN + 32;
        const data_len = try readU16(self.raw, offset);
        const start = offset + 2;
        const end = start + data_len;
        if (end > self.raw.len) return error.InvalidInstructionData;
        return self.raw[start..end];
    }
};

pub const IntrospectedInstructionAccount = struct {
    flags: u8,
    key: sdk.Pubkey,

    pub const LEN: usize = 33;

    pub fn isWritable(self: IntrospectedInstructionAccount) bool {
        return (self.flags & IS_WRITABLE) != 0;
    }

    pub fn isSigner(self: IntrospectedInstructionAccount) bool {
        return (self.flags & IS_SIGNER) != 0;
    }
};

test "Instructions parses one introspected instruction" {
    var key: sdk.Pubkey = .{1} ** 32;
    var program_id: sdk.Pubkey = .{2} ** 32;
    var bytes: [78]u8 = [_]u8{0} ** 78;
    std.mem.writeInt(u16, bytes[0..2], 1, .little);
    std.mem.writeInt(u16, bytes[2..4], 4, .little);
    std.mem.writeInt(u16, bytes[4..6], 1, .little);
    bytes[6] = IS_SIGNER | IS_WRITABLE;
    @memcpy(bytes[7..39], key[0..]);
    @memcpy(bytes[39..71], program_id[0..]);
    std.mem.writeInt(u16, bytes[71..73], 3, .little);
    bytes[73] = 9;
    bytes[74] = 8;
    bytes[75] = 7;
    std.mem.writeInt(u16, bytes[76..78], 0, .little);

    const sysvar = Instructions.initUnchecked(bytes[0..]);
    try std.testing.expectEqual(@as(usize, 1), try sysvar.numInstructions());
    try std.testing.expectEqual(@as(u16, 0), try sysvar.loadCurrentIndex());

    const instruction = try sysvar.loadInstructionAt(0);
    try std.testing.expectEqual(@as(usize, 1), try instruction.numAccountMetas());
    const account = try instruction.getInstructionAccountAt(0);
    try std.testing.expect(account.isSigner());
    try std.testing.expect(account.isWritable());
    try std.testing.expectEqual(key, account.key);
    try std.testing.expectEqual(program_id, (try instruction.getProgramId()).*);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 9, 8, 7 }, try instruction.getInstructionData());
}
