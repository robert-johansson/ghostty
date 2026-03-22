//! Manual termio backend. This provides a terminal surface that accepts
//! input/output programmatically rather than through a PTY/subprocess.
//! This is used on platforms like iOS where PTYs are not available.
//!
//! The host application provides a write callback to receive processed
//! terminal input (from ghostty_surface_text/key). Output is fed via
//! ghostty_surface_write_output().
const Manual = @This();

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const xev = @import("../global.zig").xev;
const renderer = @import("../renderer.zig");
const terminal = @import("../terminal/main.zig");
const termio = @import("../termio.zig");

const log = std.log.scoped(.io_manual);

/// Callback for forwarding processed terminal input to the host application.
/// Called when Ghostty processes keyboard input (via ghostty_surface_text/key)
/// and the terminal needs to send data to the "child process" (Bun in our case).
pub const WriteFn = *const fn (userdata: ?*anyopaque, data: [*]const u8, len: usize) callconv(.c) void;

pub const Config = struct {
    grid_size: renderer.GridSize = .{},
    screen_size: renderer.ScreenSize = .{ .width = 1, .height = 1 },
    /// Callback invoked when terminal input should be forwarded to the host.
    write_fn: ?WriteFn = null,
    write_userdata: ?*anyopaque = null,
};

grid_size: renderer.GridSize,
screen_size: renderer.ScreenSize,
io: ?*termio.Termio = null,
write_fn: ?WriteFn = null,
write_userdata: ?*anyopaque = null,

pub fn init(alloc: Allocator, cfg: Config) !Manual {
    _ = alloc;
    return .{
        .grid_size = cfg.grid_size,
        .screen_size = cfg.screen_size,
        .write_fn = cfg.write_fn,
        .write_userdata = cfg.write_userdata,
    };
}

pub fn deinit(self: *Manual) void {
    self.* = undefined;
}

pub fn initTerminal(self: *Manual, term: *terminal.Terminal) void {
    _ = self;
    _ = term;
}

pub fn threadEnter(
    self: *Manual,
    alloc: Allocator,
    io: *termio.Termio,
    td: *termio.Termio.ThreadData,
) !void {
    _ = alloc;
    self.io = io;
    td.backend = .{ .manual = .{} };
}

pub fn threadExit(self: *Manual, td: *termio.Termio.ThreadData) void {
    _ = td;
    self.io = null;
}

pub fn focusGained(
    self: *Manual,
    td: *termio.Termio.ThreadData,
    focused: bool,
) !void {
    _ = self;
    _ = td;
    _ = focused;
}

pub fn resize(
    self: *Manual,
    grid_size: renderer.GridSize,
    screen_size: renderer.ScreenSize,
) !void {
    self.grid_size = grid_size;
    self.screen_size = screen_size;
}

pub fn queueWrite(
    self: *Manual,
    alloc: Allocator,
    td: *termio.Termio.ThreadData,
    data: []const u8,
    linefeed: bool,
) !void {
    _ = alloc;
    _ = td;
    // Forward processed input to host application via callback.
    // This is called when Ghostty processes keyboard input
    // (ghostty_surface_text/key) and needs to send it downstream.
    if (self.write_fn) |wfn| {
        wfn(self.write_userdata, data.ptr, data.len);
        if (linefeed) {
            wfn(self.write_userdata, "\n", 1);
        }
    }
}

pub const ThreadData = struct {
    pub fn deinit(self: *ThreadData, alloc: Allocator) void {
        _ = self;
        _ = alloc;
    }
};
