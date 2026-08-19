const std = @import("std");

/// Events intentionally have a fixed, small representation so that one event
/// fits in a single pipe write (and is therefore atomic for multiple writers).
pub const Kind = enum(u8) {
    started,
    finished,
    failed,
    cancelled,
};

pub const Event = struct {
    magic: u32 = 0x5a465731, // "ZFW1"
    version: u8 = 1,
    kind: Kind,
    process_id: u64,
    status: i32 = 0,

    pub const wire_len = 18;

    pub fn encode(self: Event) [wire_len]u8 {
        var bytes: [wire_len]u8 = undefined;
        std.mem.writeInt(u32, bytes[0..4], self.magic, .little);
        bytes[4] = self.version;
        bytes[5] = @intFromEnum(self.kind);
        std.mem.writeInt(u64, bytes[6..14], self.process_id, .little);
        std.mem.writeInt(i32, bytes[14..18], self.status, .little);
        return bytes;
    }

    pub fn decode(bytes: *const [wire_len]u8) !Event {
        if (std.mem.readInt(u32, bytes[0..4], .little) != 0x5a465731) return error.BadMagic;
        if (bytes[4] != 1) return error.UnsupportedVersion;
        return .{
            .kind = std.enums.fromInt(Kind, bytes[5]) orelse return error.BadKind,
            .process_id = std.mem.readInt(u64, bytes[6..14], .little),
            .status = std.mem.readInt(i32, bytes[14..18], .little),
        };
    }
};

/// Write a complete event with one syscall. Callers must keep this event below
/// the platform's PIPE_BUF limit; the fixed wire format is deliberately tiny.
pub fn write(fd: std.posix.fd_t, event: Event) !void {
    const bytes = event.encode();
    const written = std.c.write(fd, &bytes, bytes.len);
    if (written < 0) return error.WriteFailed;
    if (@as(usize, @intCast(written)) != bytes.len) return error.ShortWrite;
}

test "event wire format round trips" {
    const event = Event{ .kind = .finished, .process_id = 42, .status = -9 };
    const bytes = event.encode();
    const decoded = try Event.decode(&bytes);
    try std.testing.expectEqualDeep(event, decoded);
}

test "event is delivered through a pipe" {
    var fds: [2]std.posix.fd_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.pipe(&fds));
    defer _ = std.posix.system.close(fds[0]);
    defer _ = std.posix.system.close(fds[1]);

    const expected = Event{ .kind = .started, .process_id = 7 };
    try write(fds[1], expected);
    var bytes: [Event.wire_len]u8 = undefined;
    const count = std.c.read(fds[0], &bytes, bytes.len);
    try std.testing.expectEqual(@as(isize, bytes.len), count);
    try std.testing.expectEqualDeep(expected, try Event.decode(&bytes));
}
