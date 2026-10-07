const std = @import("std");
const builtin = @import("builtin");
const Style = @import("style.zig").Style;
const text = @import("text.zig");

pub const Options = struct {
    width: usize = 80,
    color: bool = false,
    unicode: bool = true,
    interactive: bool = false,

    /// Detect ANSI support, NO_COLOR and terminal width. COLUMNS overrides the terminal.
    /// An explicit caller override always takes precedence over detection.
    pub fn detect(io: std.Io, file: std.Io.File, env: *const std.process.Environ.Map) !Options {
        const tty = try file.isTty(io);
        const dumb = if (env.get("TERM")) |term| std.mem.eql(u8, term, "dumb") else false;
        const no_color = if (env.get("NO_COLOR")) |value| value.len != 0 else false;
        const mode = try std.Io.Terminal.Mode.detect(io, file, no_color or dumb, false);
        var result: Options = .{ .color = mode == .escape_codes, .interactive = tty and !dumb, .unicode = !dumb };
        if (env.get("COLUMNS")) |value| {
            if (std.fmt.parseInt(usize, value, 10)) |columns| {
                result.width = std.math.clamp(columns, 1, 4096);
                return result;
            } else |_| {}
        }
        if (tty) {
            if (terminalWidth(io, file)) |columns| result.width = std.math.clamp(columns, 1, 4096);
        }
        return result;
    }
};

fn terminalWidth(io: std.Io, file: std.Io.File) ?usize {
    if (builtin.os.tag == .windows) {
        var info = std.os.windows.CONSOLE.USER_IO.GET_SCREEN_BUFFER_INFO;
        return switch (info.operate(io, file) catch return null) {
            .SUCCESS => if (info.Data.dwWindowSize.X > 0) @intCast(info.Data.dwWindowSize.X) else null,
            else => null,
        };
    }
    var size: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    const result = io.operate(.{ .device_io_control = .{ .file = file, .code = std.posix.T.IOCGWINSZ, .arg = &size } }) catch return null;
    if (result.device_io_control < 0 or size.col == 0) return null;
    return size.col;
}

pub const Context = struct {
    writer: *std.Io.Writer,
    options: Options,

    pub fn repeat(self: Context, value: []const u8, count: usize) !void {
        for (0..count) |_| try self.writer.writeAll(value);
    }

    pub fn styled(self: Context, value: []const u8, style: Style) !void {
        try style.start(self.writer, self.options.color);
        try self.writer.writeAll(value);
        try Style.reset(self.writer, self.options.color);
    }

    pub fn line(self: Context, value: text.Line, columns: usize, alignment: Alignment, style: Style) !void {
        const remaining = columns - value.width;
        const before = switch (alignment) {
            .left => 0,
            .center => remaining / 2,
            .right => remaining,
        };
        try self.repeat(" ", before);
        try self.styled(value.bytes, style);
        try self.repeat(" ", remaining - before);
    }

    pub fn border(self: Context) Border {
        return if (self.options.unicode) .{} else .{
            .tl = "+",
            .tr = "+",
            .bl = "+",
            .br = "+",
            .h = "-",
            .v = "|",
            .ml = "+",
            .mr = "+",
            .top = "+",
            .bottom = "+",
            .cross = "+",
        };
    }
};

pub const Alignment = enum { left, center, right };
pub const Border = struct {
    tl: []const u8 = "╭",
    tr: []const u8 = "╮",
    bl: []const u8 = "╰",
    br: []const u8 = "╯",
    h: []const u8 = "─",
    v: []const u8 = "│",
    ml: []const u8 = "├",
    mr: []const u8 = "┤",
    top: []const u8 = "┬",
    bottom: []const u8 = "┴",
    cross: []const u8 = "┼",
};
